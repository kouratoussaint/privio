-- Lot 7.3a — autocollants Privio.
--
-- Un autocollant est un message de type « sticker » dont le corps désigne l'image intégrée
-- à l'application (« série/nom ») : aucune image n'est envoyée ni stockée. Il s'efface,
-- se supprime et se signale comme un autre message ; il ne se modifie pas.

alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check
  check (kind in ('text', 'system', 'voice', 'photo', 'sticker'));

-- Envoi (inchangé, plus le type « sticker »).
CREATE OR REPLACE FUNCTION private.post_message(p_uid uuid, p_conversation_id uuid, p_client_msg_id uuid, p_kind text, p_body text, p_reply_to_id uuid, p_ttl_seconds integer, p_media_path text DEFAULT NULL::text, p_duration_ms integer DEFAULT NULL::integer, p_width integer DEFAULT NULL::integer, p_height integer DEFAULT NULL::integer)
 RETURNS messages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_body     text := case p_kind
                       when 'text'  then btrim(coalesce(p_body, ''))
                       when 'photo' then nullif(btrim(coalesce(p_body, '')), '')
                       when 'sticker' then btrim(coalesce(p_body, ''))
                     end;
  v_existing public.messages%rowtype;
  v_reply    public.messages%rowtype;
  v_row      public.messages%rowtype;
  v_ttl      integer;
begin
  if p_client_msg_id is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;

  -- Idempotence : un renvoi (réseau instable) renvoie le message déjà créé.
  select * into v_existing from public.messages m
   where m.sender_id = p_uid and m.client_msg_id = p_client_msg_id;
  if found then
    if v_existing.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    return v_existing;
  end if;

  perform private.check_can_post(p_conversation_id, p_uid);
  if p_kind = 'text'
     and (char_length(v_body) = 0 or char_length(v_body) > private.policy_int('message_max_chars')) then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if p_kind = 'photo' and v_body is not null
     and char_length(v_body) > private.policy_int('photo_caption_max_chars') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  -- Lot 7.3a : un autocollant est désigné par « série/nom » (jamais d'image envoyée).
  if p_kind = 'sticker' and v_body !~ '^[a-z0-9_]{1,40}/[a-z0-9_]{1,40}$' then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if p_reply_to_id is not null then
    select * into v_reply from public.messages m where m.id = p_reply_to_id;
    if not found or v_reply.conversation_id <> p_conversation_id or v_reply.expires_at <= now()
       or v_reply.kind not in ('text', 'voice', 'photo', 'sticker')
       or not private.can_see_message(p_conversation_id, v_reply.sent_at, p_uid) then
      raise exception 'REPLY_NOT_FOUND' using errcode = 'P0001';
    end if;
  end if;

  perform private.consume_rate_limit(p_uid, 'message_send',
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
    insert into public.messages
      (conversation_id, sender_id, client_msg_id, kind, body, reply_to_id, sent_at, expires_at,
       media_path, media_duration_ms, media_width, media_height)
    values
      (p_conversation_id, p_uid, p_client_msg_id, p_kind, v_body, p_reply_to_id, now(),
       now() + make_interval(secs => v_ttl), p_media_path, p_duration_ms, p_width, p_height)
    returning * into v_row;
  exception when unique_violation then
    -- Même message envoyé deux fois au même instant : on renvoie le premier.
    select * into v_existing from public.messages m
     where m.sender_id = p_uid and m.client_msg_id = p_client_msg_id;
    return v_existing;
  end;

  update public.conversations set last_message_at = v_row.sent_at where id = p_conversation_id;
  -- L'expéditeur a forcément reçu et lu son propre message.
  update public.conversation_members
     set delivered_up_to = greatest(coalesce(delivered_up_to, v_row.sent_at), v_row.sent_at),
         read_up_to      = greatest(coalesce(read_up_to, v_row.sent_at), v_row.sent_at),
         archived_at     = null
   where conversation_id = p_conversation_id and user_id = p_uid;
  -- Un nouveau message désarchive la discussion chez les autres membres.
  update public.conversation_members set archived_at = null
   where conversation_id = p_conversation_id and user_id <> p_uid;

  perform private.signal_members(p_conversation_id, 'message');
  return v_row;
end;
$function$;

create or replace function public.send_sticker(
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_sticker         text,
  p_reply_to_id     uuid default null,
  p_ttl_seconds     integer default null
)
returns table (id uuid, sent_at timestamptz, expires_at timestamptz)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_member(p_conversation_id);
  v     public.messages%rowtype;
begin
  v := private.post_message(v_uid, p_conversation_id, p_client_msg_id, 'sticker', p_sticker,
                            p_reply_to_id, p_ttl_seconds);
  return query select v.id, v.sent_at, v.expires_at;
end;
$$;

-- Un autocollant ne se modifie pas (sa suppression reste possible).
create or replace function private.messages_sticker_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.kind = 'sticker' and new.deleted_at is null and new.body is distinct from old.body then
    raise exception 'MESSAGE_NOT_EDITABLE' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_sticker_guard on public.messages;
create trigger messages_sticker_guard before update on public.messages
  for each row execute function private.messages_sticker_guard();

-- Liste des discussions : inchangée, un autocollant compte comme non lu.
CREATE OR REPLACE FUNCTION public.list_conversations()
 RETURNS TABLE(conversation_id uuid, kind text, peer_id uuid, peer_handle text, peer_display_name text, peer_avatar_path text, peer_deleted boolean, blocked boolean, last_message_id uuid, last_sender_id uuid, last_sender_name text, last_body text, last_deleted boolean, last_sent_at timestamp with time zone, last_expires_at timestamp with time zone, last_kind text, ttl_seconds integer, unread_count integer, pinned boolean, archived boolean, muted_until timestamp with time zone, peer_delivered_up_to timestamp with time zone, peer_read_up_to timestamp with time zone, sort_at timestamp with time zone, title text, description text, avatar_path text, member_count integer, my_role text, posting text, info_editing text, cleared_before timestamp with time zone, clear_request_by uuid, clear_request_expires_at timestamp with time zone, clear_request_delete boolean)
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
       and v.kind in ('text', 'voice', 'photo', 'sticker')
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
$function$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.send_sticker(uuid, uuid, text, uuid, integer) to authenticated;
grant execute on function public.list_conversations() to authenticated;
