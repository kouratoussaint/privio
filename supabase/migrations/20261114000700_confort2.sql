-- Lot 7.2c2 — messages épinglés, favoris, infos d'un message, « Mentions seulement ».
--
-- Décisions (amendement 16) :
-- * épingler : dans une discussion à deux, les deux personnes ; dans un groupe, les
--   administrateurs ; 3 messages épinglés au plus par discussion ;
-- * favoris : personnels ;
-- * épinglés et favoris s'effacent AVEC le message (clé étrangère en cascade, et filtrés
--   tant que le message n'est pas encore purgé) : ils ne prolongent jamais sa durée de vie ;
-- * infos d'un message (mes messages) : heures de distribution et de lecture, par membre
--   dans un groupe ; la lecture reste cachée pour qui a désactivé ses accusés de lecture ;
-- * notifications d'un groupe : « Mentions seulement ».

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table private.message_pins (
  message_id      uuid        primary key references public.messages (id) on delete cascade,
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  pinned_by       uuid        references auth.users (id) on delete set null,
  pinned_at       timestamptz not null default now()
);
create index message_pins_conv_idx on private.message_pins (conversation_id, pinned_at desc);

create table private.message_favorites (
  user_id         uuid        not null references auth.users (id) on delete cascade,
  message_id      uuid        not null references public.messages (id) on delete cascade,
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  created_at      timestamptz not null default now(),
  primary key (user_id, message_id)
);
create index message_favorites_conv_idx on private.message_favorites (user_id, conversation_id);

-- Quand les accusés avancent : sert à donner l'heure de distribution et de lecture d'un
-- message (les accusés eux-mêmes ne sont que des bornes « jusqu'à »). Gardé 4 jours (plus
-- que la durée de vie d'un message).
create table private.receipt_marks (
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  user_id         uuid        not null references auth.users (id) on delete cascade,
  kind            text        not null check (kind in ('delivered', 'read')),
  up_to           timestamptz not null,
  at              timestamptz not null default now()
);
create index receipt_marks_idx on private.receipt_marks (conversation_id, user_id, kind, up_to);

alter table public.conversation_members
  add column notify_mode text not null default 'all' check (notify_mode in ('all', 'mentions'));

-- Message que la personne peut voir (non expiré, non supprimé, après son arrivée, non masqué
-- chez elle). Lève les erreurs habituelles sinon.
create or replace function private.require_visible_message(p_message_id uuid, p_uid uuid)
returns public.messages
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.messages%rowtype;
begin
  select * into v from public.messages m where m.id = p_message_id;
  if not found or v.kind = 'system' or not private.is_member(v.conversation_id, p_uid)
     or v.sent_at < private.member_since(v.conversation_id, p_uid)
     or exists (select 1 from public.message_hidden h
                 where h.message_id = v.id and h.user_id = p_uid) then
    raise exception 'MESSAGE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v.expires_at <= now() then
    raise exception 'MESSAGE_EXPIRED' using errcode = 'P0001';
  end if;
  if v.deleted_at is not null then
    raise exception 'MESSAGE_DELETED' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Épingler
-- ---------------------------------------------------------------------------
create or replace function public.pin_message(p_message_id uuid, p_pin boolean)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype := private.require_visible_message(p_message_id, v_uid);
begin
  if exists (select 1 from public.conversations c where c.id = v.conversation_id and c.kind = 'group')
     and private.member_role(v.conversation_id, v_uid) not in ('owner', 'admin') then
    raise exception 'NOT_ADMIN' using errcode = 'P0001';
  end if;
  if p_pin then
    if exists (select 1 from private.message_pins p where p.message_id = v.id) then
      return;
    end if;
    if (select count(*) from private.message_pins p
          join public.messages m on m.id = p.message_id
         where p.conversation_id = v.conversation_id
           and m.expires_at > now() and m.deleted_at is null) >= 3 then
      raise exception 'PIN_LIMIT_REACHED' using errcode = 'P0001';
    end if;
    insert into private.message_pins (message_id, conversation_id, pinned_by)
    values (v.id, v.conversation_id, v_uid);
  else
    delete from private.message_pins p where p.message_id = v.id;
    if not found then
      return;
    end if;
  end if;
  perform private.signal_members(v.conversation_id, 'pin');
end;
$$;

create or replace function public.list_pinned_messages(p_conversation_id uuid)
returns table (
  message_id  uuid,
  sender_id   uuid,
  sender_name text,
  kind        text,
  body        text,
  sent_at     timestamptz,
  pinned_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_member(p_conversation_id);
  v_since timestamptz := private.member_since(p_conversation_id, v_uid);
begin
  return query
  select m.id, m.sender_id, sp.display_name, m.kind, left(m.body, 200), m.sent_at, p.pinned_at
    from private.message_pins p
    join public.messages m on m.id = p.message_id
    left join public.profiles sp on sp.id = m.sender_id and sp.deleted_at is null
   where p.conversation_id = p_conversation_id
     and m.expires_at > now() and m.deleted_at is null and m.sent_at >= v_since
     and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
   order by p.pinned_at desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Favoris (plusieurs messages à la fois : sélection multiple)
-- ---------------------------------------------------------------------------
create or replace function public.set_message_favorites(p_message_ids uuid[], p_on boolean)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_id  uuid;
  v     public.messages%rowtype;
  v_n   integer := 0;
begin
  if coalesce(cardinality(p_message_ids), 0) = 0 or cardinality(p_message_ids) > 100 then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  foreach v_id in array p_message_ids loop
    if p_on then
      v := private.require_visible_message(v_id, v_uid);
      insert into private.message_favorites (user_id, message_id, conversation_id)
      values (v_uid, v.id, v.conversation_id)
      on conflict do nothing;
    else
      -- Retirer reste possible même si le message vient d'expirer ou d'être supprimé.
      delete from private.message_favorites f where f.user_id = v_uid and f.message_id = v_id;
    end if;
    if found then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$$;

create or replace function public.list_favorite_messages(p_conversation_id uuid)
returns table (
  message_id  uuid,
  sender_id   uuid,
  sender_name text,
  kind        text,
  body        text,
  sent_at     timestamptz,
  expires_at  timestamptz,
  created_at  timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_member(p_conversation_id);
  v_since timestamptz := private.member_since(p_conversation_id, v_uid);
begin
  return query
  select m.id, m.sender_id, sp.display_name, m.kind, left(m.body, 500), m.sent_at, m.expires_at,
         f.created_at
    from private.message_favorites f
    join public.messages m on m.id = f.message_id
    left join public.profiles sp on sp.id = m.sender_id and sp.deleted_at is null
   where f.user_id = v_uid and f.conversation_id = p_conversation_id
     and m.expires_at > now() and m.deleted_at is null and m.sent_at >= v_since
     and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
   order by m.sent_at desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Accusés : on note quand ils avancent (heures de distribution et de lecture).
-- Même règle que le lot 7.2b1-bis : sans date, rien n'est enregistré.
-- ---------------------------------------------------------------------------
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
end;
$$;

-- Infos d'un de MES messages : pour chaque destinataire présent à l'envoi, distribué / lu
-- et à quelle heure (null : avant le lot 7.2c2, heure inconnue). La lecture n'est pas
-- donnée pour qui a désactivé ses accusés de lecture.
create or replace function public.get_message_info(p_message_id uuid)
returns table (
  user_id         uuid,
  display_name    text,
  delivered       boolean,
  delivered_at    timestamptz,
  read            boolean,
  read_at         timestamptz,
  receipts_hidden boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype := private.require_visible_message(p_message_id, v_uid);
begin
  if v.sender_id is distinct from v_uid then
    raise exception 'NOT_SENDER' using errcode = 'P0001';
  end if;
  return query
  select o.user_id, p.display_name,
         coalesce(o.delivered_up_to >= v.sent_at, false),
         (select min(r.at) from private.receipt_marks r
           where r.conversation_id = v.conversation_id and r.user_id = o.user_id
             and r.up_to >= v.sent_at),
         private.read_receipts_on(v.conversation_id, o.user_id)
           and coalesce(o.read_up_to >= v.sent_at, false),
         case when private.read_receipts_on(v.conversation_id, o.user_id) then
           (select min(r.at) from private.receipt_marks r
             where r.conversation_id = v.conversation_id and r.user_id = o.user_id
               and r.kind = 'read' and r.up_to >= v.sent_at)
         end,
         not private.read_receipts_on(v.conversation_id, o.user_id)
    from public.conversation_members o
    left join public.profiles p on p.id = o.user_id and p.deleted_at is null
   where o.conversation_id = v.conversation_id
     and o.user_id <> v_uid
     and o.left_at is null
     and private.member_since(v.conversation_id, o.user_id) <= v.sent_at
   order by p.display_name;
end;
$$;

create or replace function private.purge_receipt_marks()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.receipt_marks where at < now() - interval '4 days';
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_purge_receipt_marks';
    perform cron.schedule('privio_purge_receipt_marks', '53 3 * * *', 'select private.purge_receipt_marks()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Notifications d'un groupe : tout, ou mentions seulement
-- ---------------------------------------------------------------------------
create or replace function public.get_notify_mode(p_conversation_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_member(p_conversation_id);
begin
  return (select m.notify_mode from public.conversation_members m
           where m.conversation_id = p_conversation_id and m.user_id = v_uid);
end;
$$;

create or replace function public.set_notify_mode(p_conversation_id uuid, p_mode text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_member(p_conversation_id);
begin
  if p_mode is null or p_mode not in ('all', 'mentions') then
    raise exception 'SETTING_INVALID' using errcode = 'P0001';
  end if;
  if p_mode = 'mentions'
     and not exists (select 1 from public.conversations c where c.id = p_conversation_id and c.kind = 'group') then
    raise exception 'NOT_GROUP' using errcode = 'P0001';
  end if;
  update public.conversation_members set notify_mode = p_mode
   where conversation_id = p_conversation_id and user_id = v_uid;
end;
$$;

-- Destinataires d'une notification : inchangé (lot 7.1b), plus « Mentions seulement ».
create or replace function public.push_targets(p_token text, p_message_id uuid)
returns table (token text, conversation_id uuid, is_group boolean, mentioned boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v public.messages%rowtype;
begin
  perform private.check_push_token(p_token);
  select * into v from public.messages m where m.id = p_message_id;
  if not found or v.expires_at <= now() or v.kind = 'system' or v.deleted_at is not null then
    return;
  end if;
  return query
  select t.token, v.conversation_id, c.kind = 'group', x.mentioned
    from public.conversation_members m
    join public.conversations c on c.id = m.conversation_id
    join private.push_tokens t on t.user_id = m.user_id
    join public.devices d on d.id = t.device_id and d.revoked_at is null
    cross join lateral (
      select exists (select 1 from private.message_mentions mm
                      where mm.message_id = v.id and mm.user_id = m.user_id) as mentioned
    ) x
   where m.conversation_id = v.conversation_id
     and m.left_at is null
     and m.user_id is distinct from v.sender_id
     and (x.mentioned
          or ((m.muted_until is null or m.muted_until <= now()) and m.notify_mode = 'all'))
     and (v.sender_id is null or not private.is_blocked_between(m.user_id, v.sender_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on function public.push_targets(text, uuid) from public, anon, authenticated;
grant execute on function public.push_targets(text, uuid) to service_role;
grant execute on function public.pin_message(uuid, boolean) to authenticated;
grant execute on function public.list_pinned_messages(uuid) to authenticated;
grant execute on function public.set_message_favorites(uuid[], boolean) to authenticated;
grant execute on function public.list_favorite_messages(uuid) to authenticated;
grant execute on function public.mark_conversation(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.get_message_info(uuid) to authenticated;
grant execute on function public.get_notify_mode(uuid) to authenticated;
grant execute on function public.set_notify_mode(uuid, text) to authenticated;
