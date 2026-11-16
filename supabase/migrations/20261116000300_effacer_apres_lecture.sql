-- Lot 10.1 : « Effacer après lecture » (décisions du 16/11/2026).
--   A. délais : 30 s, 5 min ou 1 h après la lecture ;
--   B. activation : l'une ou l'autre personne d'une discussion à deux ; les administrateurs
--      d'un groupe ;
--   C. groupe : chaque lecteur voit le message disparaître à son propre délai ; le message est
--      supprimé pour tous quand tous les membres l'ont lu (plus le délai) ;
--   D. la copie de l'expéditeur disparaît quand le message a été lu (par tous) plus le délai ;
--   E. seulement pour les messages envoyés après l'activation (réglage copié à l'envoi).
-- La limite de 72 h reste la règle de fond : un message jamais lu s'efface comme avant.

-- ---------------------------------------------------------------------------
-- 1. Réglage de la discussion, copié sur chaque message à l'envoi
-- ---------------------------------------------------------------------------
alter table public.conversations
  add column if not exists read_erase_seconds integer
  check (read_erase_seconds is null or read_erase_seconds in (30, 300, 3600));

alter table public.messages
  add column if not exists read_erase_seconds integer
  check (read_erase_seconds is null or read_erase_seconds in (30, 300, 3600));

create or replace function private.messages_read_erase()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind <> 'system' then
    new.read_erase_seconds := (select c.read_erase_seconds from public.conversations c
                                where c.id = new.conversation_id);
  else
    new.read_erase_seconds := null;
  end if;
  return new;
end;
$$;

drop trigger if exists messages_read_erase on public.messages;
create trigger messages_read_erase before insert on public.messages
  for each row execute function private.messages_read_erase();

-- ---------------------------------------------------------------------------
-- 2. Lectures : quand chaque lecteur verra le message disparaître
-- ---------------------------------------------------------------------------
create table if not exists private.read_erasures (
  message_id uuid        not null references public.messages (id) on delete cascade,
  user_id    uuid        not null references auth.users (id) on delete cascade,
  erase_at   timestamptz not null,
  primary key (message_id, user_id)
);
create index if not exists read_erasures_erase_idx on private.read_erasures (erase_at);
create index if not exists read_erasures_user_idx on private.read_erasures (user_id);

create or replace function private.erased_for(p_message_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.read_erasures e
                  where e.message_id = p_message_id and e.user_id = p_user_id
                    and e.erase_at <= now());
$$;

-- Messages lus par tous les membres qui pouvaient les voir : effacés pour tout le monde
-- (expéditeur compris) à la dernière échéance.
create or replace function private.finish_read_erasures(p_conversation_id uuid default null)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_n     integer;
  v_convs uuid[];
  v_c     uuid;
begin
  with done as (
    select e.message_id, max(e.erase_at) as last_erase
      from private.read_erasures e
      join public.messages m on m.id = e.message_id
     where (p_conversation_id is null or m.conversation_id = p_conversation_id)
       and m.read_erase_seconds is not null
     group by e.message_id
  ), upd as (
    update public.messages m
       set expires_at = d.last_erase, updated_at = now()
      from done d
     where m.id = d.message_id and m.expires_at > d.last_erase and d.last_erase > m.sent_at
       and not exists (
         select 1 from public.conversation_members cm
          where cm.conversation_id = m.conversation_id and cm.left_at is null
            and cm.user_id is distinct from m.sender_id
            and private.can_see_message(m.conversation_id, m.sent_at, cm.user_id)
            and not exists (select 1 from private.read_erasures e2
                             where e2.message_id = m.id and e2.user_id = cm.user_id))
    returning m.conversation_id
  )
  select count(*), array_agg(distinct conversation_id) into v_n, v_convs from upd;
  if v_n > 0 then
    foreach v_c in array v_convs loop
      perform private.signal_members(v_c, 'message_changed');
    end loop;
  end if;
  return v_n;
end;
$$;

-- À la lecture : échéance de chaque message « effacer après lecture » pour ce lecteur.
create or replace function private.record_read_erasures(
  p_conversation_id uuid, p_user_id uuid, p_read_up_to timestamptz
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  with ins as (
    insert into private.read_erasures (message_id, user_id, erase_at)
    select m.id, p_user_id, now() + make_interval(secs => m.read_erase_seconds)
      from public.messages m
     where m.conversation_id = p_conversation_id
       and m.read_erase_seconds is not null
       and m.kind <> 'system'
       and m.sender_id is distinct from p_user_id
       and m.deleted_at is null
       and m.expires_at > now()
       and m.sent_at <= p_read_up_to
       and private.can_see_message(p_conversation_id, m.sent_at, p_user_id)
    on conflict (message_id, user_id) do nothing
    returning message_id
  )
  -- Le lecteur relit ces messages (nouvelle échéance) au prochain rafraîchissement.
  update public.messages set updated_at = now() where id in (select message_id from ins);
  get diagnostics v_n = row_count;
  if v_n > 0 then
    perform private.signal_user(p_user_id, p_conversation_id, 'message_changed');
    perform private.finish_read_erasures(p_conversation_id);
  end if;
  return v_n;
end;
$$;

create or replace function public.mark_conversation(
  p_conversation_id uuid,
  p_delivered_up_to timestamptz default null,
  p_read_up_to      timestamptz default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := private.require_member(p_conversation_id);
  v_read      timestamptz := case when p_read_up_to is null then null
                                  else least(p_read_up_to, now()) end;
  v_delivered timestamptz := case when p_delivered_up_to is null and p_read_up_to is null then null
                                  else least(greatest(p_delivered_up_to, p_read_up_to), now()) end;
  v_old_d     timestamptz;
  v_old_r     timestamptz;
begin
  if v_delivered is null and v_read is null then
    return;
  end if;
  select m.delivered_up_to, m.read_up_to into v_old_d, v_old_r
    from public.conversation_members m
   where m.conversation_id = p_conversation_id and m.user_id = v_uid
   for update;
  if (v_delivered is null or v_delivered <= coalesce(v_old_d, '-infinity'))
     and (v_read is null or v_read <= coalesce(v_old_r, '-infinity')) then
    return;
  end if;
  update public.conversation_members
     set delivered_up_to = greatest(delivered_up_to, v_delivered),
         read_up_to      = greatest(read_up_to, v_read)
   where conversation_id = p_conversation_id and user_id = v_uid;
  if v_delivered is not null and v_delivered > coalesce(v_old_d, '-infinity') then
    insert into private.receipt_marks (conversation_id, user_id, kind, up_to)
    values (p_conversation_id, v_uid, 'delivered', v_delivered);
  end if;
  if v_read is not null and v_read > coalesce(v_old_r, '-infinity') then
    insert into private.receipt_marks (conversation_id, user_id, kind, up_to)
    values (p_conversation_id, v_uid, 'read', v_read);
  end if;
  perform private.signal_members(p_conversation_id, 'receipt');
  -- Lot 10.1 : effacer après lecture.
  if v_read is not null and v_read > coalesce(v_old_r, '-infinity') then
    perform private.record_read_erasures(p_conversation_id, v_uid, v_read);
  end if;
end;
$$;

-- Chaque minute : messages arrivés à échéance masqués chez le lecteur (favoris, médias,
-- épinglés), et messages lus par tous effacés (par sécurité, si un membre est parti).
create or replace function private.apply_read_erasures()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  insert into public.message_hidden (message_id, user_id)
  select e.message_id, e.user_id from private.read_erasures e
   where e.erase_at <= now()
  on conflict do nothing;
  get diagnostics v_n = row_count;
  perform private.finish_read_erasures(null);
  return v_n;
end;
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_read_erasures';
    perform cron.schedule('privio_read_erasures', '* * * * *', 'select private.apply_read_erasures()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Activer, changer ou couper le réglage
-- ---------------------------------------------------------------------------
create or replace function public.set_read_erase(p_conversation_id uuid, p_seconds integer)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_peer uuid;
begin
  if p_seconds is not null and p_seconds not in (30, 300, 3600) then
    raise exception 'READ_ERASE_INVALID' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.conversations c where c.id = p_conversation_id and c.kind = 'group') then
    if coalesce(private.member_role(p_conversation_id, v_uid), '') not in ('owner', 'admin') then
      raise exception 'NOT_ADMIN' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.conversations c where c.id = p_conversation_id and c.posting = 'closed') then
      raise exception 'GROUP_CLOSED' using errcode = 'P0001';
    end if;
  else
    v_peer := private.direct_peer(p_conversation_id, v_uid);
    if v_peer is not null and private.is_blocked_between(v_uid, v_peer) then
      raise exception 'BLOCKED' using errcode = 'P0001';
    end if;
  end if;
  if exists (select 1 from public.conversations c
              where c.id = p_conversation_id and c.read_erase_seconds is not distinct from p_seconds) then
    return p_seconds;
  end if;
  update public.conversations set read_erase_seconds = p_seconds, last_message_at = now()
   where id = p_conversation_id;
  insert into public.messages (conversation_id, sender_id, client_msg_id, kind, body, sent_at, expires_at)
  values (p_conversation_id, v_uid, gen_random_uuid(), 'system', 'erase:' || coalesce(p_seconds, 0), now(),
          now() + make_interval(secs => private.effective_ttl(p_conversation_id)));
  perform private.signal_members(p_conversation_id, 'message');
  return p_seconds;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Lecture des messages : échéance propre à chaque lecteur
-- ---------------------------------------------------------------------------
drop function if exists public.get_messages(uuid, timestamptz, timestamptz, integer);
CREATE OR REPLACE FUNCTION public.get_messages(p_conversation_id uuid, p_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, sender_id uuid, sender_name text, kind text, body text, reply_to_id uuid, reply_preview text, reply_kind text, sent_at timestamp with time zone, expires_at timestamp with time zone, edited_at timestamp with time zone, deleted_at timestamp with time zone, updated_at timestamp with time zone, reactions jsonb, media_path text, media_duration_ms integer, media_width integer, media_height integer, media_waveform smallint[], mentions uuid[], view_once boolean, opened boolean, opened_count integer, link_preview jsonb, read_erase_seconds integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_member(p_conversation_id);
  v_since timestamptz := private.member_since(p_conversation_id, v_uid);
  v_limit int  := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  return query
  select m.id, m.sender_id, sp.display_name, m.kind, m.body, m.reply_to_id,
         case when r.id is not null and r.expires_at > now() and r.deleted_at is null
                   and r.sent_at >= v_since
              then left(r.body, 120) end,
         case when r.id is not null and r.expires_at > now() and r.deleted_at is null
                   and r.sent_at >= v_since
              then r.kind end,
         m.sent_at, least(m.expires_at, er.erase_at), m.edited_at, m.deleted_at, m.updated_at,
         coalesce((select jsonb_agg(jsonb_build_object('user_id', x.user_id, 'emoji', x.emoji)
                                    order by x.created_at)
                     from public.message_reactions x where x.message_id = m.id), '[]'::jsonb),
         -- Vue unique : le fichier n'est lisible que par un destinataire qui vient de l'ouvrir.
         case when m.view_once and not private.view_once_readable(m.id, m.sender_id, v_uid)
              then null else m.media_path end,
         m.media_duration_ms, m.media_width, m.media_height, m.media_waveform,
         case when m.deleted_at is null then
           coalesce((select array_agg(mm.user_id order by mm.user_id)
                       from private.message_mentions mm where mm.message_id = m.id), '{}'::uuid[])
         else '{}'::uuid[] end,
         m.view_once,
         exists (select 1 from private.view_once_opens o where o.message_id = m.id and o.user_id = v_uid),
         case when m.view_once and m.sender_id = v_uid then
           (select count(*)::int from private.view_once_opens o where o.message_id = m.id)
         end,
         case when m.deleted_at is null then
           (select jsonb_build_object('url', lp.url, 'title', lp.title, 'description', lp.description,
                                      'site', lp.site, 'image_path', lp.image_path,
                                      'image_width', lp.image_width, 'image_height', lp.image_height)
              from private.link_previews lp where lp.message_id = m.id)
         end,
         m.read_erase_seconds
    from public.messages m
    left join private.read_erasures er on er.message_id = m.id and er.user_id = v_uid
    left join public.messages r on r.id = m.reply_to_id
    left join public.profiles sp on sp.id = m.sender_id and sp.deleted_at is null
   where m.conversation_id = p_conversation_id
     and m.expires_at > now()
     and (er.erase_at is null or er.erase_at > now())
     and m.sent_at >= v_since
     and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
     and (p_since is null or m.updated_at > p_since)
     and (p_before is null or m.sent_at < p_before)
   order by
     case when p_since is not null then m.updated_at end asc,
     case when p_since is null then m.sent_at end desc
   limit v_limit;
end;
$function$;

drop function if exists public.list_conversations();

CREATE OR REPLACE FUNCTION public.list_conversations()
 RETURNS TABLE(conversation_id uuid, kind text, peer_id uuid, peer_handle text, peer_display_name text, peer_avatar_path text, peer_deleted boolean, blocked boolean, last_message_id uuid, last_sender_id uuid, last_sender_name text, last_body text, last_deleted boolean, last_sent_at timestamp with time zone, last_expires_at timestamp with time zone, last_kind text, ttl_seconds integer, unread_count integer, pinned boolean, archived boolean, muted_until timestamp with time zone, peer_delivered_up_to timestamp with time zone, peer_read_up_to timestamp with time zone, sort_at timestamp with time zone, title text, description text, avatar_path text, member_count integer, my_role text, posting text, info_editing text, cleared_before timestamp with time zone, clear_request_by uuid, clear_request_expires_at timestamp with time zone, clear_request_delete boolean, read_erase_seconds integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid uuid := private.require_active_user();
  v_max integer := private.policy_int('message_ttl_hours') * 3600;
begin
  return query
  with mine as (
    select c.id, c.kind, c.created_by, c.created_at, c.ttl_seconds, c.title, c.description,
           c.avatar_path, c.posting, c.info_editing, c.cleared_at, c.read_erase_seconds,
           me.joined_at, me.read_up_to, me.pinned_at, me.archived_at, me.muted_until, me.role,
           me.cleared_before, me.hidden_at,
           private.member_since(c.id, v_uid) as since
      from public.conversation_members me
      join public.conversations c on c.id = me.conversation_id
     where me.user_id = v_uid and me.left_at is null
  ),
  visible as (
    select m.*, er.erase_at from public.messages m
      join mine on mine.id = m.conversation_id
      left join private.read_erasures er on er.message_id = m.id and er.user_id = v_uid
     where m.expires_at > now() and m.sent_at >= mine.since
       and (er.erase_at is null or er.erase_at > now())
       and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
  ),
  last_msg as (
    select distinct on (v.conversation_id) v.* from visible v
     order by v.conversation_id, v.sent_at desc
  ),
  unread as (
    select v.conversation_id, count(*)::int as n from visible v
      join mine on mine.id = v.conversation_id
     where v.sender_id is distinct from v_uid and v.deleted_at is null
       and v.kind in ('text', 'voice', 'photo', 'sticker', 'gif')
       and (mine.read_up_to is null or v.sent_at > mine.read_up_to)
     group by v.conversation_id
  ),
  others as (
    -- Accusés agrégés d'un groupe : « lu » ne tient compte que des membres qui partagent
    -- leurs accusés de lecture.
    select o.conversation_id,
           count(*)::int as n,
           case when bool_or(o.delivered_up_to is null) then null else min(o.delivered_up_to) end as delivered,
           case when count(*) filter (where private.read_receipts_on(o.conversation_id, o.user_id)) = 0 then null
                when bool_or(o.read_up_to is null)
                       filter (where private.read_receipts_on(o.conversation_id, o.user_id)) then null
                else min(o.read_up_to) filter (where private.read_receipts_on(o.conversation_id, o.user_id)) end as read
      from public.conversation_members o
      join mine on mine.id = o.conversation_id
     where o.user_id <> v_uid and o.left_at is null
     group by o.conversation_id
  ),
  direct_peer as (
    select peer.conversation_id, peer.user_id, peer.delivered_up_to,
           case when private.read_receipts_on(peer.conversation_id, peer.user_id) then peer.read_up_to end as read_up_to
      from public.conversation_members peer
      join mine on mine.id = peer.conversation_id and mine.kind = 'direct'
     where peer.user_id <> v_uid
  )
  select mine.id, mine.kind,
         dp.user_id, p.handle, p.display_name,
         case when mine.kind = 'direct' and p.deleted_at is null
              then private.avatar_for(dp.user_id, v_uid, p.avatar_path) end,
         mine.kind = 'direct' and (p.id is null or p.deleted_at is not null),
         mine.kind = 'direct' and coalesce(private.is_blocked_between(v_uid, dp.user_id), false),
         lm.id, lm.sender_id,
         case when lm.sender_id = v_uid then null
              else (select sp.display_name from public.profiles sp where sp.id = lm.sender_id) end,
         lm.body, lm.deleted_at is not null, lm.sent_at, least(lm.expires_at, lm.erase_at), lm.kind,
         least(coalesce(mine.ttl_seconds, v_max), v_max),
         coalesce(u.n, 0),
         mine.pinned_at is not null, mine.archived_at is not null,
         case when mine.muted_until > now() then mine.muted_until end,
         case when mine.kind = 'direct' then dp.delivered_up_to else o.delivered end,
         case when mine.kind = 'direct' then dp.read_up_to else o.read end,
         coalesce(lm.sent_at, mine.created_at),
         mine.title, mine.description, mine.avatar_path,
         coalesce(o.n, 0) + 1,
         case when mine.kind = 'group' then mine.role end,
         mine.posting, mine.info_editing,
         nullif(greatest(coalesce(mine.cleared_before, '-infinity'::timestamptz),
                         coalesce(mine.cleared_at, '-infinity'::timestamptz)), '-infinity'::timestamptz),
         cr.requested_by, cr.expires_at, coalesce(cr.then_delete, false),
         mine.read_erase_seconds
    from mine
    left join direct_peer dp on dp.conversation_id = mine.id
    left join public.profiles p on p.id = dp.user_id
    left join last_msg lm on lm.conversation_id = mine.id
    left join unread u on u.conversation_id = mine.id
    left join others o on o.conversation_id = mine.id
    left join private.clear_requests cr on cr.conversation_id = mine.id and cr.expires_at > now()
   -- Une discussion 1:1 vide n'apparaît que chez la personne qui l'a créée, sauf si elle a
   -- été vidée ou qu'une demande est en cours ; un groupe apparaît toujours.
   -- Lot 7.2b1 : une discussion supprimée chez moi ne revient qu'avec un nouveau message.
   where (lm.id is not null or mine.created_by = v_uid or mine.kind = 'group'
      or mine.cleared_before is not null or mine.cleared_at is not null or cr.conversation_id is not null)
     and (mine.hidden_at is null or lm.id is not null)
   order by (mine.pinned_at is not null) desc, coalesce(lm.sent_at, mine.created_at) desc;
end;
$function$;

-- Message lu et effacé : plus de réaction, réponse, épingle…
CREATE OR REPLACE FUNCTION private.visible_message(p_message_id uuid, p_user_id uuid)
 RETURNS messages
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v public.messages%rowtype;
begin
  select * into v from public.messages where id = p_message_id;
  if not found or not private.can_see_message(v.conversation_id, v.sent_at, p_user_id) then
    raise exception 'MESSAGE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v.expires_at <= now() or private.erased_for(v.id, p_user_id) then
    raise exception 'MESSAGE_EXPIRED' using errcode = 'P0001';
  end if;
  return v;
end;
$function$;

-- Fichiers (photo, vocal, GIF, aperçu) : plus lisibles par le lecteur après l'échéance.
CREATE OR REPLACE FUNCTION private.can_read_photo(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.session_is_active() and exists (
    select 1 from public.messages m
     where m.media_path = p_name and m.kind = 'photo' and m.deleted_at is null
       and m.expires_at > now()
       and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
       and not private.erased_for(m.id, auth.uid())
       and (not m.view_once or private.view_once_readable(m.id, m.sender_id, auth.uid()))
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_read_voice(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.session_is_active() and exists (
    select 1 from public.messages m
     where m.media_path = p_name and m.kind = 'voice' and m.deleted_at is null
       and m.expires_at > now()
       and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
       and not private.erased_for(m.id, auth.uid())
       and (not m.view_once or private.view_once_readable(m.id, m.sender_id, auth.uid()))
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_read_gif(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.session_is_active() and exists (
    select 1 from public.messages m
     where m.media_path = p_name and m.kind = 'gif' and m.deleted_at is null
       and m.expires_at > now()
       and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
       and not private.erased_for(m.id, auth.uid())
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_read_preview(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.session_is_active() and exists (
    select 1 from private.link_previews lp
      join public.messages m on m.id = lp.message_id
     where lp.image_path = p_name and m.deleted_at is null and m.expires_at > now()
       and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
       and not private.erased_for(m.id, auth.uid())
  );
$function$;


-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.get_messages(uuid, timestamptz, timestamptz, integer) to authenticated;
grant execute on function public.list_conversations() to authenticated;
grant execute on function public.mark_conversation(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.set_read_erase(uuid, integer) to authenticated;
grant execute on function private.can_read_photo(text) to authenticated;
grant execute on function private.can_read_voice(text) to authenticated;
grant execute on function private.can_read_gif(text) to authenticated;
grant execute on function private.can_read_preview(text) to authenticated;
