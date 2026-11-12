-- PRIVIO — Migration 7 (lot 2.E) : durée d'expiration configurable
--   * par discussion (ttl_seconds) : réglable par chaque membre, s'applique aux NOUVEAUX
--     messages ; le changement est annoncé par un message système visible des deux côtés ;
--   * par message (p_ttl_seconds) : jamais au-delà de la durée de la discussion ;
--   * bornes : minimum administrable (5 min par défaut), maximum = invariant 72 h.

insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('message_ttl_min_minutes', 'integer', '5', 1, 60, null, true, true,
   'Durée de vie minimale réglable pour un message ou une discussion.');

alter table public.conversations
  add column ttl_seconds integer check (ttl_seconds is null or ttl_seconds between 60 and 259200);

alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check check (kind in ('text', 'system'));

-- Durée effective d'une discussion (bornée par la politique en vigueur).
create or replace function private.effective_ttl(p_conversation_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select least(
    coalesce((select c.ttl_seconds from public.conversations c where c.id = p_conversation_id),
             private.policy_int('message_ttl_hours') * 3600),
    private.policy_int('message_ttl_hours') * 3600);
$$;

-- Un message système ne se modifie, ne se supprime pour tous et ne reçoit aucune réaction.
create or replace function private.protect_system_messages()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_table_name = 'messages' then
    if old.kind = 'system' and (new.body is distinct from old.body or new.deleted_at is not null) then
      raise exception 'MESSAGE_NOT_EDITABLE' using errcode = 'P0001';
    end if;
    return new;
  end if;
  if exists (select 1 from public.messages m where m.id = new.message_id and m.kind = 'system') then
    raise exception 'MESSAGE_NOT_EDITABLE' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger messages_protect_system before update on public.messages
  for each row execute function private.protect_system_messages();
create trigger reactions_protect_system before insert or update on public.message_reactions
  for each row execute function private.protect_system_messages();

-- Régler la durée d'une discussion.
create or replace function public.set_conversation_ttl(p_conversation_id uuid, p_ttl_seconds integer)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_max  integer := private.policy_int('message_ttl_hours') * 3600;
  v_min  integer := private.policy_int('message_ttl_min_minutes') * 60;
  v_peer uuid;
begin
  if p_ttl_seconds is null or p_ttl_seconds < v_min or p_ttl_seconds > v_max then
    raise exception 'TTL_INVALID' using errcode = 'P0001';
  end if;
  v_peer := private.direct_peer(p_conversation_id, v_uid);
  if v_peer is not null and private.is_blocked_between(v_uid, v_peer) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;
  if private.effective_ttl(p_conversation_id) = p_ttl_seconds then
    return p_ttl_seconds;
  end if;

  update public.conversations set ttl_seconds = p_ttl_seconds, last_message_at = now()
   where id = p_conversation_id;
  insert into public.messages (conversation_id, sender_id, client_msg_id, kind, body, sent_at, expires_at)
  values (p_conversation_id, v_uid, gen_random_uuid(), 'system', 'ttl:' || p_ttl_seconds, now(),
          now() + make_interval(secs => p_ttl_seconds));
  perform private.signal_members(p_conversation_id, 'message');
  return p_ttl_seconds;
end;
$$;

-- Envoi : nouvelle signature (durée par message).
drop function if exists public.send_message(uuid, uuid, text, uuid);

create or replace function public.send_message(
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_body            text,
  p_reply_to_id     uuid default null,
  p_ttl_seconds     integer default null
)
returns table (id uuid, sent_at timestamptz, expires_at timestamptz)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_body text := btrim(coalesce(p_body, ''));
  v_peer uuid;
  v_existing public.messages%rowtype;
  v_reply public.messages%rowtype;
  v_row  public.messages%rowtype;
  v_ttl  integer;
begin
  if p_client_msg_id is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;

  -- Idempotence : un renvoi (réseau instable) renvoie le message déjà créé.
  select * into v_existing from public.messages m
   where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
  if found then
    if v_existing.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    return query select v_existing.id, v_existing.sent_at, v_existing.expires_at;
    return;
  end if;

  v_peer := private.direct_peer(p_conversation_id, v_uid);
  if v_peer is not null and private.is_blocked_between(v_uid, v_peer) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;
  if char_length(v_body) = 0 or char_length(v_body) > private.policy_int('message_max_chars') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if p_reply_to_id is not null then
    select * into v_reply from public.messages m where m.id = p_reply_to_id;
    if not found or v_reply.conversation_id <> p_conversation_id or v_reply.expires_at <= now()
       or v_reply.kind <> 'text' then
      raise exception 'REPLY_NOT_FOUND' using errcode = 'P0001';
    end if;
  end if;

  perform private.consume_rate_limit(v_uid, 'message_send',
    private.policy_int('message_send_hourly_limit'), interval '1 hour');

  -- Durée : celle choisie pour ce message, jamais au-delà de celle de la discussion.
  v_ttl := private.effective_ttl(p_conversation_id);
  if p_ttl_seconds is not null then
    if p_ttl_seconds < private.policy_int('message_ttl_min_minutes') * 60 then
      raise exception 'TTL_INVALID' using errcode = 'P0001';
    end if;
    v_ttl := least(p_ttl_seconds, v_ttl);
  end if;

  begin
    insert into public.messages (conversation_id, sender_id, client_msg_id, body, reply_to_id, sent_at, expires_at)
    values (p_conversation_id, v_uid, p_client_msg_id, v_body, p_reply_to_id, now(),
            now() + make_interval(secs => v_ttl))
    returning * into v_row;
  exception when unique_violation then
    -- Même message envoyé deux fois au même instant : on renvoie le premier.
    select * into v_existing from public.messages m
     where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
    return query select v_existing.id, v_existing.sent_at, v_existing.expires_at;
    return;
  end;

  update public.conversations set last_message_at = v_row.sent_at where conversations.id = p_conversation_id;
  -- L'expéditeur a forcément reçu et lu son propre message.
  update public.conversation_members
     set delivered_up_to = greatest(coalesce(delivered_up_to, v_row.sent_at), v_row.sent_at),
         read_up_to      = greatest(coalesce(read_up_to, v_row.sent_at), v_row.sent_at),
         archived_at     = null
   where conversation_id = p_conversation_id and user_id = v_uid;
  -- Un nouveau message désarchive la discussion chez le destinataire.
  update public.conversation_members set archived_at = null
   where conversation_id = p_conversation_id and user_id <> v_uid;

  perform private.signal_members(p_conversation_id, 'message');
  return query select v_row.id, v_row.sent_at, v_row.expires_at;
end;
$$;


-- Liste : durée de la discussion et type du dernier message.
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
  last_body            text,
  last_deleted         boolean,
  last_sent_at         timestamptz,
  last_expires_at      timestamptz,
  last_kind            text,
  ttl_seconds          integer,
  unread_count         integer,
  pinned               boolean,
  archived             boolean,
  peer_delivered_up_to timestamptz,
  peer_read_up_to      timestamptz,
  sort_at              timestamptz
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
    select c.id, c.kind, c.created_by, c.created_at, c.ttl_seconds, me.read_up_to, me.pinned_at, me.archived_at
      from public.conversation_members me
      join public.conversations c on c.id = me.conversation_id
     where me.user_id = v_uid and me.left_at is null
  ),
  visible as (
    select m.* from public.messages m
      join mine on mine.id = m.conversation_id
     where m.expires_at > now()
       and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
  ),
  last_msg as (
    select distinct on (v.conversation_id) v.* from visible v
     order by v.conversation_id, v.sent_at desc
  ),
  unread as (
    select v.conversation_id, count(*)::int as n from visible v
      join mine on mine.id = v.conversation_id
     where v.sender_id is distinct from v_uid and v.deleted_at is null and v.kind = 'text'
       and (mine.read_up_to is null or v.sent_at > mine.read_up_to)
     group by v.conversation_id
  )
  select mine.id, mine.kind,
         peer.user_id, p.handle, p.display_name, p.avatar_path,
         coalesce(p.deleted_at is not null, true),
         coalesce(private.is_blocked_between(v_uid, peer.user_id), false),
         lm.id, lm.sender_id, lm.body, lm.deleted_at is not null, lm.sent_at, lm.expires_at, lm.kind,
         least(coalesce(mine.ttl_seconds, v_max), v_max),
         coalesce(u.n, 0),
         mine.pinned_at is not null, mine.archived_at is not null,
         peer.delivered_up_to, peer.read_up_to,
         coalesce(lm.sent_at, mine.created_at)
    from mine
    left join public.conversation_members peer
           on peer.conversation_id = mine.id and peer.user_id <> v_uid
    left join public.profiles p on p.id = peer.user_id
    left join last_msg lm on lm.conversation_id = mine.id
    left join unread u on u.conversation_id = mine.id
   -- Une discussion vide n'apparaît que chez la personne qui l'a créée.
   where lm.id is not null or mine.created_by = v_uid
   order by (mine.pinned_at is not null) desc, coalesce(lm.sent_at, mine.created_at) desc;
end;
$$;



select private.harden_privileges();
grant execute on function public.set_conversation_ttl(uuid, integer) to authenticated;
grant execute on function public.send_message(uuid, uuid, text, uuid, integer) to authenticated;
grant execute on function public.list_conversations() to authenticated;
