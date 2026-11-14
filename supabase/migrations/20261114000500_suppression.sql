-- PRIVIO — lot 7.2b1 (décisions du 14/11/2026) : supprimer une discussion ou un groupe.
--   * discussion à deux : « Supprimer chez moi » (elle disparaît de ma liste, ma copie est
--     effacée ; un nouveau message la fait revenir, vide) ou « Supprimer pour nous deux »
--     (même accord que « Vider pour nous deux », puis elle disparaît des deux côtés) ;
--   * groupe : le créateur ou un administrateur le supprime pour tous : messages, photos et
--     vocaux effacés, membres retirés. Chaque membre voit une ligne « Le groupe X a été
--     supprimé » dans l'onglet Groupes (à fermer ; effacée au bout de 30 jours). Pas de
--     notification. Un groupe fermé par Privio ne se supprime pas (il est sous modération).

alter table public.conversation_members add column if not exists hidden_at timestamptz;
alter table private.clear_requests add column if not exists then_delete boolean not null default false;

create table private.group_deletion_notices (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users (id) on delete cascade,
  title       text        not null,
  deleted_at  timestamptz not null default now()
);
create index group_deletion_notices_user_idx on private.group_deletion_notices (user_id);
revoke all on private.group_deletion_notices from public, anon, authenticated;

-- Retirer la discussion de la liste de [p_user] (sa copie est vidée en même temps).
create or replace function private.hide_for(p_conversation_id uuid, p_user uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update public.conversation_members
     set hidden_at = clock_timestamp(), cleared_before = clock_timestamp(), pinned_at = null,
         archived_at = null
   where conversation_id = p_conversation_id and user_id = p_user;
$$;

-- Groupe supprimé pour tous : un avis pour chaque membre (sauf l'auteur), puis la
-- discussion disparaît (messages, médias, invitations, codes, demandes : en cascade).
create or replace function private.delete_group(p_conversation_id uuid, p_by uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_title text := (select c.title from public.conversations c where c.id = p_conversation_id);
  r       record;
begin
  for r in
    select m.user_id from public.conversation_members m
     where m.conversation_id = p_conversation_id and m.left_at is null
  loop
    if r.user_id <> p_by then
      insert into private.group_deletion_notices (user_id, title) values (r.user_id, coalesce(v_title, 'Groupe'));
    end if;
    perform private.signal_user(r.user_id, p_conversation_id, 'group_deleted');
  end loop;
  delete from public.conversations where id = p_conversation_id;
end;
$$;

-- p_scope : 'me' ou 'everyone'. Renvoie 'deleted' ou 'requested' (accord attendu).
create or replace function public.delete_conversation(p_conversation_id uuid, p_scope text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_kind text;
  v_peer uuid;
  v_req  private.clear_requests;
begin
  select c.kind into v_kind from public.conversations c where c.id = p_conversation_id for update;
  if v_kind = 'group' then
    -- Groupe : supprimé pour tous, par le créateur ou un administrateur ; un membre le quitte.
    if p_scope is distinct from 'everyone' then
      raise exception 'CLEAR_SCOPE_INVALID' using errcode = 'P0001';
    end if;
    perform private.require_group_role(p_conversation_id, array['owner', 'admin']);
    perform private.require_open_group(p_conversation_id);
    perform private.delete_group(p_conversation_id, v_uid);
    return 'deleted';
  end if;

  if p_scope = 'me' then
    perform private.hide_for(p_conversation_id, v_uid);
    perform private.signal_user(v_uid, p_conversation_id, 'message');
    return 'deleted';
  elsif p_scope is distinct from 'everyone' then
    raise exception 'CLEAR_SCOPE_INVALID' using errcode = 'P0001';
  end if;

  -- Pour nous deux : l'accord de l'autre personne est nécessaire (comme pour vider).
  v_peer := private.direct_peer(p_conversation_id, v_uid);
  if v_peer is null or private.is_blocked_between(v_uid, v_peer)
     or not exists (select 1 from public.profiles p where p.id = v_peer and p.deleted_at is null) then
    raise exception 'CLEAR_NOT_ALLOWED' using errcode = 'P0001';
  end if;
  select * into v_req from private.clear_requests
   where conversation_id = p_conversation_id and expires_at > now();
  if found and v_req.requested_by = v_peer and v_req.then_delete then
    -- L'autre l'avait déjà demandé : c'est un accord.
    perform private.wipe_conversation(p_conversation_id);
    perform private.hide_for(p_conversation_id, v_uid);
    perform private.hide_for(p_conversation_id, v_peer);
    return 'deleted';
  end if;
  if found and v_req.requested_by = v_uid and v_req.then_delete then
    return 'requested';
  end if;
  perform private.consume_rate_limit(v_uid, 'clear_request',
    private.policy_int('clear_request_daily_limit'), interval '1 day');
  insert into private.clear_requests (conversation_id, requested_by, requested_at, expires_at, then_delete)
  values (p_conversation_id, v_uid, now(),
          now() + make_interval(hours => private.policy_int('clear_request_ttl_hours')), true)
  on conflict (conversation_id) do update
    set requested_by = excluded.requested_by, requested_at = excluded.requested_at,
        expires_at = excluded.expires_at, then_delete = true;
  perform private.signal_members(p_conversation_id, 'message');
  return 'requested';
end;
$$;

-- Réponse de l'autre personne : inchangée (lot 4.3), plus la suppression quand c'était
-- une demande de suppression. Renvoie 'cleared', 'deleted' ou 'refused'.
create or replace function public.respond_clear_request(p_conversation_id uuid, p_accept boolean)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_member(p_conversation_id);
  v_req private.clear_requests;
begin
  select * into v_req from private.clear_requests
   where conversation_id = p_conversation_id and expires_at > now()
   for update;
  if not found or v_req.requested_by = v_uid then
    raise exception 'CLEAR_REQUEST_NOT_FOUND' using errcode = 'P0001';
  end if;
  if coalesce(p_accept, false) then
    if private.is_blocked_between(v_uid, v_req.requested_by) then
      raise exception 'CLEAR_NOT_ALLOWED' using errcode = 'P0001';
    end if;
    perform private.wipe_conversation(p_conversation_id);
    if v_req.then_delete then
      perform private.hide_for(p_conversation_id, v_uid);
      perform private.hide_for(p_conversation_id, v_req.requested_by);
      return 'deleted';
    end if;
    return 'cleared';
  end if;
  delete from private.clear_requests where conversation_id = p_conversation_id;
  perform private.signal_members(p_conversation_id, 'message');
  return 'refused';
end;
$$;

-- « Vider pour nous deux » d'une demande de suppression déjà faite par l'autre : on garde
-- le comportement du lot 4.3 (accord = vider), sans supprimer.

-- Avis de suppression de groupe (onglet Groupes).
create or replace function public.list_group_deletion_notices()
returns table (id uuid, title text, deleted_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_active_user();
begin
  return query
  select n.id, n.title, n.deleted_at from private.group_deletion_notices n
   where n.user_id = v_uid and n.deleted_at > now() - interval '30 days'
   order by n.deleted_at desc;
end;
$$;

create or replace function public.dismiss_group_deletion_notice(p_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  delete from private.group_deletion_notices where id = p_id and user_id = v_uid;
end;
$$;

create or replace function private.purge_group_deletion_notices()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.group_deletion_notices where deleted_at < now() - interval '30 days';
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_purge_group_notices';
    perform cron.schedule('privio_purge_group_notices', '47 3 * * *', 'select private.purge_group_deletion_notices()');
  end if;
end;
$$;

-- Liste des discussions : inchangée (lot 7.2a), plus les discussions supprimées chez moi et
-- le type de demande en cours (vider ou supprimer).
drop function if exists public.list_conversations();

create or replace function public.list_conversations()
returns table (
  conversation_id      uuid,
  kind                 text,
  peer_id              uuid,
  peer_handle          text,
  peer_display_name    text,
  peer_avatar_path     text,
  peer_deleted         boolean,
  blocked              boolean,
  last_message_id      uuid,
  last_sender_id       uuid,
  last_sender_name     text,
  last_body            text,
  last_deleted         boolean,
  last_sent_at         timestamptz,
  last_expires_at      timestamptz,
  last_kind            text,
  ttl_seconds          integer,
  unread_count         integer,
  pinned               boolean,
  archived             boolean,
  muted_until          timestamptz,
  peer_delivered_up_to timestamptz,
  peer_read_up_to      timestamptz,
  sort_at              timestamptz,
  title                text,
  description          text,
  avatar_path          text,
  member_count         integer,
  my_role              text,
  posting              text,
  info_editing         text,
  cleared_before       timestamptz,
  clear_request_by     uuid,
  clear_request_expires_at timestamptz,
  clear_request_delete boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_active_user();
  v_max integer := private.policy_int('message_ttl_hours') * 3600;
begin
  return query
  with mine as (
    select c.id, c.kind, c.created_by, c.created_at, c.ttl_seconds, c.title, c.description,
           c.avatar_path, c.posting, c.info_editing, c.cleared_at,
           me.joined_at, me.read_up_to, me.pinned_at, me.archived_at, me.muted_until, me.role,
           me.cleared_before, me.hidden_at,
           private.member_since(c.id, v_uid) as since
      from public.conversation_members me
      join public.conversations c on c.id = me.conversation_id
     where me.user_id = v_uid and me.left_at is null
  ),
  visible as (
    select m.* from public.messages m
      join mine on mine.id = m.conversation_id
     where m.expires_at > now() and m.sent_at >= mine.since
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
       and v.kind in ('text', 'voice', 'photo')
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
         lm.body, lm.deleted_at is not null, lm.sent_at, lm.expires_at, lm.kind,
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
         cr.requested_by, cr.expires_at, coalesce(cr.then_delete, false)
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
$$;


select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.delete_conversation(uuid, text) to authenticated;
grant execute on function public.respond_clear_request(uuid, boolean) to authenticated;
grant execute on function public.list_group_deletion_notices() to authenticated;
grant execute on function public.dismiss_group_deletion_notice(uuid) to authenticated;
grant execute on function public.list_conversations() to authenticated;
