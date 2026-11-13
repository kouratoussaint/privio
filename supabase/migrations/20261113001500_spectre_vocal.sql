-- PRIVIO — lot 4.5 : spectre des messages vocaux.
--
-- Le téléphone qui enregistre mesure le niveau sonore et en tire un profil de 8 à 64
-- valeurs (0 à 100). Ce profil accompagne le fichier : voice-send le vérifie, le dépose
-- avec le fichier (service), puis il est recopié dans le message. Il s'efface avec le
-- message (suppression, expiration). Les anciens vocaux n'en ont pas : spectre neutre.

-- ---------------------------------------------------------------------------
-- Stockage
-- ---------------------------------------------------------------------------
create or replace function private.waveform_valid(p smallint[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p is null
      or (cardinality(p) between 8 and 64
          and array_position(p, null) is null
          and 0 <= all (p) and 100 >= all (p));
$$;

alter table private.media_objects
  add column waveform smallint[] check (private.waveform_valid(waveform));

alter table public.messages
  add column media_waveform smallint[] check (private.waveform_valid(media_waveform));

alter table public.messages drop constraint if exists messages_content_check;
alter table public.messages add constraint messages_content_check check (
  case
    when deleted_at is not null then body is null and media_path is null and media_duration_ms is null
                                     and media_width is null and media_height is null
                                     and media_waveform is null
    when kind = 'voice' then body is null and media_path is not null and media_duration_ms is not null
                             and media_width is null and media_height is null
    when kind = 'photo' then media_path is not null and media_width is not null
                             and media_height is not null and media_duration_ms is null
                             and media_waveform is null
    else body is not null and media_path is null and media_duration_ms is null
         and media_width is null and media_height is null and media_waveform is null
  end
);

grant select (media_waveform) on public.messages to authenticated;

-- Suppression d'un média : le profil part avec le fichier.
create or replace function private.messages_media_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.kind in ('voice', 'photo') and new.deleted_at is null
     and new.body is distinct from old.body then
    raise exception 'MESSAGE_NOT_EDITABLE' using errcode = 'P0001';
  end if;
  if old.kind = 'voice' and new.deleted_at is null and old.media_waveform is not null
     and new.media_waveform is distinct from old.media_waveform then
    raise exception 'MESSAGE_NOT_EDITABLE' using errcode = 'P0001';
  end if;
  if new.deleted_at is not null and old.media_path is not null then
    perform private.mark_media_for_purge(old.media_path);
    new.media_path := null;
    new.media_duration_ms := null;
    new.media_width := null;
    new.media_height := null;
    new.media_waveform := null;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Vocal, étape 2 (SERVICE) : + profil sonore vérifié.
-- ---------------------------------------------------------------------------
drop function if exists public.commit_voice_upload(text, integer, integer);

create or replace function public.commit_voice_upload(
  p_path        text,
  p_duration_ms integer,
  p_bytes       integer,
  p_waveform    smallint[] default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if current_setting('role', true) is distinct from 'service_role' then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  if p_duration_ms is null or p_duration_ms < 1
     or p_duration_ms > private.policy_int('voice_max_seconds') * 1000 + 500 then
    raise exception 'VOICE_TOO_LONG' using errcode = 'P0001';
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > private.policy_int('voice_max_bytes') then
    raise exception 'MEDIA_TOO_LARGE' using errcode = 'P0001';
  end if;
  if not private.waveform_valid(p_waveform) then
    raise exception 'MEDIA_INVALID' using errcode = 'P0001';
  end if;
  update private.media_objects
     set state = 'uploaded', duration_ms = p_duration_ms, bytes = p_bytes, waveform = p_waveform
   where path = p_path and state in ('reserved', 'uploaded');
  if not found then
    raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Vocal, étape 3 : le message reçoit le profil ; la réponse le renvoie.
-- ---------------------------------------------------------------------------
drop function if exists public.send_voice_message(uuid, uuid, uuid, integer);

create or replace function public.send_voice_message(
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_reply_to_id     uuid default null,
  p_ttl_seconds     integer default null
)
returns table (id uuid, sent_at timestamptz, expires_at timestamptz,
               media_path text, media_duration_ms integer, media_waveform smallint[])
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_member(p_conversation_id);
  v_obj private.media_objects%rowtype;
  v     public.messages%rowtype;
begin
  select * into v from public.messages m
   where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
  if not found then
    select * into v_obj from private.media_objects o
     where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id;
    if not found or v_obj.state not in ('uploaded', 'attached') then
      raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
    end if;
    if v_obj.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    v := private.post_message(v_uid, p_conversation_id, p_client_msg_id, 'voice', null,
                              p_reply_to_id, p_ttl_seconds, v_obj.path, v_obj.duration_ms);
    if v_obj.waveform is not null then
      update public.messages m set media_waveform = v_obj.waveform
       where m.id = v.id
      returning * into v;
    end if;
    update private.media_objects o set state = 'attached', message_id = v.id
     where o.path = v_obj.path and o.state = 'uploaded';
  elsif v.conversation_id <> p_conversation_id then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query select v.id, v.sent_at, v.expires_at, v.media_path, v.media_duration_ms,
                      v.media_waveform;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lecture des messages : + profil sonore (dernier champ).
-- ---------------------------------------------------------------------------
drop function if exists public.get_messages(uuid, timestamptz, timestamptz, integer);

create or replace function public.get_messages(
  p_conversation_id uuid,
  p_since           timestamptz default null,
  p_before          timestamptz default null,
  p_limit           integer default 50
)
returns table (
  id                uuid,
  sender_id         uuid,
  sender_name       text,
  kind              text,
  body              text,
  reply_to_id       uuid,
  reply_preview     text,
  reply_kind        text,
  sent_at           timestamptz,
  expires_at        timestamptz,
  edited_at         timestamptz,
  deleted_at        timestamptz,
  updated_at        timestamptz,
  reactions         jsonb,
  media_path        text,
  media_duration_ms integer,
  media_width       integer,
  media_height      integer,
  media_waveform    smallint[]
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
         m.sent_at, m.expires_at, m.edited_at, m.deleted_at, m.updated_at,
         coalesce((select jsonb_agg(jsonb_build_object('user_id', x.user_id, 'emoji', x.emoji)
                                    order by x.created_at)
                     from public.message_reactions x where x.message_id = m.id), '[]'::jsonb),
         m.media_path, m.media_duration_ms, m.media_width, m.media_height, m.media_waveform
    from public.messages m
    left join public.messages r on r.id = m.reply_to_id
    left join public.profiles sp on sp.id = m.sender_id and sp.deleted_at is null
   where m.conversation_id = p_conversation_id
     and m.expires_at > now()
     and m.sent_at >= v_since
     and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
     and (p_since is null or m.updated_at > p_since)
     and (p_before is null or m.sent_at < p_before)
   order by
     case when p_since is not null then m.updated_at end asc,
     case when p_since is null then m.sent_at end desc
   limit v_limit;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();

grant execute on function public.send_voice_message(uuid, uuid, uuid, integer) to authenticated;
grant execute on function public.get_messages(uuid, timestamptz, timestamptz, integer) to authenticated;
revoke all on function public.commit_voice_upload(text, integer, integer, smallint[]) from authenticated;
grant execute on function public.commit_voice_upload(text, integer, integer, smallint[]) to service_role;
