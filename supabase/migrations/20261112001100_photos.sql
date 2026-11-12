-- PRIVIO — Migration 11 (lot 3.2) : photos (5 par jour) et photo de profil
-- Invariants :
--   * buckets Storage PRIVÉS « photos » et « avatars » (JPEG uniquement), sans URL publique
--     ni signée, sans écriture cliente : les fonctions photo-send et avatar-set vérifient le
--     fichier (JPEG valide, dimensions, taille) et en RETIRENT les métadonnées (position GPS,
--     appareil, date…) avant de le déposer ;
--   * quota de photos (photo_daily_limit, 5 par défaut, groupes inclus) décompté dans la même
--     transaction que la réservation, par compte et par jour (fuseau quota_timezone),
--     idempotent par identifiant client ; remboursé si l'envoi échoue AVANT acceptation
--     (fichier refusé, réservation abandonnée), jamais après (suppression d'un message envoyé) ;
--   * une photo suit les mêmes règles que tout message : lecture réservée aux membres, illisible
--     à l'expiration ou à la suppression, puis effacée physiquement par media-purge ;
--   * photo de profil : visible des personnes connectées non bloquées ; l'ancienne est effacée
--     au remplacement, au retrait et à la suppression du compte.

-- ---------------------------------------------------------------------------
-- Politiques
-- ---------------------------------------------------------------------------
update private.policy_definitions set implemented = true where key = 'photo_daily_limit';

insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('photo_max_bytes', 'integer', '1048576', 131072, 2097152, null, false, true,
   'Taille maximale d''une photo après compression (octets).'),
  ('photo_max_dimension', 'integer', '2048', 640, 4096, null, false, true,
   'Plus grand côté d''une photo (pixels).'),
  ('photo_caption_max_chars', 'integer', '1000', 0, 4000, null, true, true,
   'Longueur maximale de la légende d''une photo.'),
  ('avatar_max_bytes', 'integer', '262144', 32768, 1048576, null, false, true,
   'Taille maximale d''une photo de profil (octets).'),
  ('avatar_upload_daily_limit', 'integer', '20', 1, 200, null, false, true,
   'Changements de photo de profil par compte et par jour (anti-abus).');

-- Jour de quota (minuit selon le fuseau administrable, Ouagadougou par défaut).
create or replace function private.quota_day()
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (now() at time zone (private.policy_value('quota_timezone') #>> '{}'))::date;
$$;

-- ---------------------------------------------------------------------------
-- Quota journalier de photos
-- ---------------------------------------------------------------------------
create table private.photo_quota_daily (
  user_id    uuid    not null references auth.users (id) on delete cascade,
  quota_day  date    not null,
  used       integer not null default 0 check (used >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, quota_day)
);
revoke all on private.photo_quota_daily from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Registre des médias : photos et photos de profil
-- ---------------------------------------------------------------------------
alter table private.media_objects drop constraint if exists media_objects_bucket_check;
alter table private.media_objects add constraint media_objects_bucket_check
  check (bucket in ('voice', 'photos', 'avatars'));
alter table private.media_objects
  alter column conversation_id drop not null,
  alter column client_msg_id drop not null,
  add column width     integer check (width is null or width between 1 and 8192),
  add column height    integer check (height is null or height between 1 and 8192),
  -- Photos : jour de quota débité (pour un éventuel remboursement).
  add column quota_day date;
alter table private.media_objects add constraint media_objects_kind_shape check (
  case bucket
    when 'avatars' then conversation_id is null and client_msg_id is null
    else (state = 'purge' or (conversation_id is not null and client_msg_id is not null))
  end
);

-- Réservation abandonnée avant acceptation : fichier à effacer, photo remboursée.
create or replace function private.abandon_reservation(p_path text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v private.media_objects%rowtype;
begin
  select * into v from private.media_objects where path = p_path for update;
  if not found or v.state not in ('reserved', 'uploaded') then
    return;
  end if;
  if v.bucket = 'photos' and v.owner_id is not null and v.quota_day is not null then
    update private.photo_quota_daily
       set used = greatest(used - 1, 0), updated_at = now()
     where user_id = v.owner_id and quota_day = v.quota_day;
  end if;
  update private.media_objects
     set state = 'purge', owner_id = null, purge_requested_at = now()
   where path = p_path;
end;
$$;

-- ---------------------------------------------------------------------------
-- Messages : type « photo » (légende facultative), dimensions
-- ---------------------------------------------------------------------------
alter table public.messages
  add column media_width  integer check (media_width is null or media_width between 1 and 8192),
  add column media_height integer check (media_height is null or media_height between 1 and 8192);

alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check
  check (kind in ('text', 'system', 'voice', 'photo'));

alter table public.messages drop constraint if exists messages_content_check;
alter table public.messages add constraint messages_content_check check (
  case
    when deleted_at is not null then body is null and media_path is null and media_duration_ms is null
                                     and media_width is null and media_height is null
    when kind = 'voice' then body is null and media_path is not null and media_duration_ms is not null
                             and media_width is null and media_height is null
    when kind = 'photo' then media_path is not null and media_width is not null
                             and media_height is not null and media_duration_ms is null
    else body is not null and media_path is null and media_duration_ms is null
         and media_width is null and media_height is null
  end
);

grant select (media_width, media_height) on public.messages to authenticated;

-- Vocal et photo ne se modifient pas ; leur suppression libère le fichier.
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
  if new.deleted_at is not null and old.media_path is not null then
    perform private.mark_media_for_purge(old.media_path);
    new.media_path := null;
    new.media_duration_ms := null;
    new.media_width := null;
    new.media_height := null;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lecture : photo d'un message (comme un vocal) ; photo de profil (personne connectée,
-- profil actif, aucun blocage entre les deux comptes).
-- ---------------------------------------------------------------------------
create or replace function private.can_read_photo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and exists (
    select 1 from public.messages m
     where m.media_path = p_name and m.kind = 'photo' and m.deleted_at is null
       and m.expires_at > now()
       and private.is_member(m.conversation_id, auth.uid())
  );
$$;

create or replace function private.can_read_avatar(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and exists (
    select 1 from public.profiles p
     where p.avatar_path = p_name and p.deleted_at is null
       and (p.id = auth.uid() or not private.is_blocked_between(auth.uid(), p.id))
  );
$$;

do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('photos', 'photos', false, 2097152, array['image/jpeg']),
           ('avatars', 'avatars', false, 1048576, array['image/jpeg'])
    on conflict (id) do update
      set public = false,
          file_size_limit = excluded.file_size_limit,
          allowed_mime_types = excluded.allowed_mime_types;
    execute 'drop policy if exists privio_photo_read on storage.objects';
    execute $p$
      create policy privio_photo_read on storage.objects
        for select to authenticated
        using (bucket_id = 'photos' and private.can_read_photo(name))
    $p$;
    execute 'drop policy if exists privio_avatar_read on storage.objects';
    execute $p$
      create policy privio_avatar_read on storage.objects
        for select to authenticated
        using (bucket_id = 'avatars' and private.can_read_avatar(name))
    $p$;
  else
    raise notice 'Storage absent : buckets « photos » et « avatars » non créés (test local)';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Envoi commun : + légende de photo et dimensions.
-- ---------------------------------------------------------------------------
drop function if exists private.post_message(uuid, uuid, uuid, text, text, uuid, integer, text, integer);

create or replace function private.post_message(
  p_uid             uuid,
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_kind            text,
  p_body            text,
  p_reply_to_id     uuid,
  p_ttl_seconds     integer,
  p_media_path      text default null,
  p_duration_ms     integer default null,
  p_width           integer default null,
  p_height          integer default null
)
returns public.messages
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_body     text := case p_kind
                       when 'text'  then btrim(coalesce(p_body, ''))
                       when 'photo' then nullif(btrim(coalesce(p_body, '')), '')
                     end;
  v_peer     uuid;
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

  v_peer := private.direct_peer(p_conversation_id, p_uid);
  if v_peer is not null and private.is_blocked_between(p_uid, v_peer) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;
  if p_kind = 'text'
     and (char_length(v_body) = 0 or char_length(v_body) > private.policy_int('message_max_chars')) then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if p_kind = 'photo' and v_body is not null
     and char_length(v_body) > private.policy_int('photo_caption_max_chars') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if p_reply_to_id is not null then
    select * into v_reply from public.messages m where m.id = p_reply_to_id;
    if not found or v_reply.conversation_id <> p_conversation_id or v_reply.expires_at <= now()
       or v_reply.kind not in ('text', 'voice', 'photo') then
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
  -- Un nouveau message désarchive la discussion chez le destinataire.
  update public.conversation_members set archived_at = null
   where conversation_id = p_conversation_id and user_id <> p_uid;

  perform private.signal_members(p_conversation_id, 'message');
  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- Quota : consultation (compteur affiché, PHOTO-005)
-- ---------------------------------------------------------------------------
create or replace function public.get_photo_quota()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_active_user();
  v_day   date := private.quota_day();
  v_limit integer := private.policy_int('photo_daily_limit');
  v_used  integer := coalesce((select q.used from private.photo_quota_daily q
                                where q.user_id = v_uid and q.quota_day = v_day), 0);
  v_tz    text := private.policy_value('quota_timezone') #>> '{}';
begin
  return jsonb_build_object(
    'limit', v_limit,
    'used', v_used,
    'remaining', greatest(v_limit - v_used, 0),
    'day', v_day,
    'resets_at', ((v_day + 1)::timestamp at time zone v_tz));
end;
$$;

-- ---------------------------------------------------------------------------
-- Photo, étape 1 (application, via photo-send) : réserver ET débiter le quota, d'un seul
-- tenant. Idempotent : même identifiant client → même réservation, jamais débitée deux fois.
-- ---------------------------------------------------------------------------
create or replace function public.prepare_photo_message(p_conversation_id uuid, p_client_msg_id uuid)
returns table (path text, state text, message_id uuid, remaining integer)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_member(p_conversation_id);
  v_peer  uuid;
  v_msg   public.messages%rowtype;
  v_row   private.media_objects%rowtype;
  v_path  text;
  v_day   date := private.quota_day();
  v_limit integer := private.policy_int('photo_daily_limit');
  v_used  integer;
begin
  if p_client_msg_id is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  select * into v_msg from public.messages m
   where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
  if found then
    if v_msg.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    return query select null::text, 'sent'::text, v_msg.id, null::integer;
    return;
  end if;

  v_peer := private.direct_peer(p_conversation_id, v_uid);
  if v_peer is not null and private.is_blocked_between(v_uid, v_peer) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;

  -- La réservation d'abord : un second appel simultané avec le même identifiant client
  -- ne débite rien (conflit), il retrouve la réservation existante.
  insert into private.media_objects (path, bucket, owner_id, conversation_id, client_msg_id, quota_day)
  values (p_conversation_id::text || '/' || gen_random_uuid()::text || '.jpg', 'photos',
          v_uid, p_conversation_id, p_client_msg_id, v_day)
  on conflict (owner_id, client_msg_id) do nothing
  returning private.media_objects.path into v_path;

  if v_path is not null then
    -- Débit atomique : jamais « compter puis insérer ». Échec : tout est annulé.
    insert into private.photo_quota_daily as q (user_id, quota_day, used)
    values (v_uid, v_day, 1)
    on conflict (user_id, quota_day) do update
      set used = q.used + 1, updated_at = now()
      where q.used < v_limit
    returning q.used into v_used;
    if v_used is null or v_used > v_limit then
      raise exception 'PHOTO_QUOTA_REACHED' using errcode = 'P0001';
    end if;
  end if;

  select * into v_row from private.media_objects o
   where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id;
  if v_row.conversation_id is distinct from p_conversation_id or v_row.bucket <> 'photos' then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query
    select v_row.path, v_row.state, null::uuid,
           greatest(v_limit - coalesce((select q.used from private.photo_quota_daily q
                                         where q.user_id = v_uid and q.quota_day = v_day), 0), 0);
end;
$$;

-- Photo, étape 2 (SERVICE, après vérification et nettoyage du fichier par photo-send).
create or replace function public.commit_photo_upload(
  p_path text, p_width integer, p_height integer, p_bytes integer
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_max integer := private.policy_int('photo_max_dimension');
begin
  perform private.require_service();
  if p_width is null or p_height is null or p_width < 1 or p_height < 1
     or greatest(p_width, p_height) > v_max then
    raise exception 'MEDIA_INVALID' using errcode = 'P0001';
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > private.policy_int('photo_max_bytes') then
    raise exception 'MEDIA_TOO_LARGE' using errcode = 'P0001';
  end if;
  update private.media_objects
     set state = 'uploaded', width = p_width, height = p_height, bytes = p_bytes
   where path = p_path and bucket = 'photos' and state in ('reserved', 'uploaded');
  if not found then
    raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
  end if;
end;
$$;

-- Fichier refusé par la fonction (SERVICE) : réservation abandonnée, photo remboursée.
create or replace function public.release_media_reservation(p_path text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.require_service();
  perform private.abandon_reservation(p_path);
end;
$$;

-- Photo, étape 3 (application, via photo-send) : publier, avec légende facultative.
create or replace function public.send_photo_message(
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_caption         text default null,
  p_reply_to_id     uuid default null,
  p_ttl_seconds     integer default null
)
returns table (id uuid, sent_at timestamptz, expires_at timestamptz, body text,
               media_path text, media_width integer, media_height integer)
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
     where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id and o.bucket = 'photos';
    if not found or v_obj.state not in ('uploaded', 'attached') then
      raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
    end if;
    if v_obj.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    v := private.post_message(v_uid, p_conversation_id, p_client_msg_id, 'photo', p_caption,
                              p_reply_to_id, p_ttl_seconds, v_obj.path, null,
                              v_obj.width, v_obj.height);
    update private.media_objects o set state = 'attached', message_id = v.id
     where o.path = v_obj.path and o.state = 'uploaded';
  elsif v.conversation_id <> p_conversation_id then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query select v.id, v.sent_at, v.expires_at, v.body, v.media_path, v.media_width, v.media_height;
end;
$$;

-- Limites appliquées par photo-send et avatar-set avant tout dépôt (SERVICE).
create or replace function public.image_limits()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_service();
  return jsonb_build_object(
    'photo_max_bytes', private.policy_int('photo_max_bytes'),
    'photo_max_dimension', private.policy_int('photo_max_dimension'),
    'avatar_max_bytes', private.policy_int('avatar_max_bytes'),
    'avatar_max_dimension', 1024);
end;
$$;

-- ---------------------------------------------------------------------------
-- Photo de profil (AUTH-003)
-- ---------------------------------------------------------------------------
-- L'ancienne photo est effacée dès qu'elle est remplacée ou retirée, ou que le profil disparaît.
create or replace function private.profiles_avatar_release()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.avatar_path is not null
     and (tg_op = 'DELETE' or new.avatar_path is distinct from old.avatar_path
          or new.deleted_at is not null) then
    perform private.mark_media_for_purge(old.avatar_path);
  end if;
  return coalesce(new, old);
end;
$$;

create trigger profiles_avatar_release after update of avatar_path, deleted_at or delete
  on public.profiles for each row execute function private.profiles_avatar_release();

create or replace function public.prepare_avatar_upload()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_path text := v_uid::text || '/' || gen_random_uuid()::text || '.jpg';
begin
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.deleted_at is null) then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(v_uid, 'avatar_upload',
    private.policy_int('avatar_upload_daily_limit'), interval '1 day');
  insert into private.media_objects (path, bucket, owner_id) values (v_path, 'avatars', v_uid);
  return v_path;
end;
$$;

-- SERVICE : le fichier vérifié et nettoyé est déposé ; il devient la photo de profil.
create or replace function public.commit_avatar(
  p_path text, p_width integer, p_height integer, p_bytes integer
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v private.media_objects%rowtype;
begin
  perform private.require_service();
  if p_width is null or p_height is null or p_width < 1 or p_height < 1
     or greatest(p_width, p_height) > 1024 then
    raise exception 'MEDIA_INVALID' using errcode = 'P0001';
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > private.policy_int('avatar_max_bytes') then
    raise exception 'MEDIA_TOO_LARGE' using errcode = 'P0001';
  end if;
  select * into v from private.media_objects
   where path = p_path and bucket = 'avatars' and state = 'reserved' and owner_id is not null
   for update;
  if not found then
    raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
  end if;
  update private.media_objects
     set state = 'attached', width = p_width, height = p_height, bytes = p_bytes
   where path = p_path;
  update public.profiles set avatar_path = p_path where id = v.owner_id and deleted_at is null;
end;
$$;

create or replace function public.remove_avatar()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  update public.profiles set avatar_path = null where id = v_uid and avatar_path is not null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lecture des messages : + dimensions des photos.
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
  media_height      integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_member(p_conversation_id);
  v_limit int  := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  return query
  select m.id, m.sender_id, m.kind, m.body, m.reply_to_id,
         case when r.id is not null and r.expires_at > now() and r.deleted_at is null
              then left(r.body, 120) end,
         case when r.id is not null and r.expires_at > now() and r.deleted_at is null
              then r.kind end,
         m.sent_at, m.expires_at, m.edited_at, m.deleted_at, m.updated_at,
         coalesce((select jsonb_agg(jsonb_build_object('user_id', x.user_id, 'emoji', x.emoji)
                                    order by x.created_at)
                     from public.message_reactions x where x.message_id = m.id), '[]'::jsonb),
         m.media_path, m.media_duration_ms, m.media_width, m.media_height
    from public.messages m
    left join public.messages r on r.id = m.reply_to_id
   where m.conversation_id = p_conversation_id
     and m.expires_at > now()
     and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
     and (p_since is null or m.updated_at > p_since)
     and (p_before is null or m.sent_at < p_before)
   order by
     case when p_since is not null then m.updated_at end asc,
     case when p_since is null then m.sent_at end desc
   limit v_limit;
end;
$$;

-- Liste : les photos comptent comme non lues (même retour qu'à la migration 10).
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
     where v.sender_id is distinct from v_uid and v.deleted_at is null
       and v.kind in ('text', 'voice', 'photo')
       and (mine.read_up_to is null or v.sent_at > mine.read_up_to)
     group by v.conversation_id
  )
  select mine.id, mine.kind,
         peer.user_id, p.handle, p.display_name,
         case when p.deleted_at is null and not coalesce(private.is_blocked_between(v_uid, peer.user_id), false)
              then p.avatar_path end,
         (p.id is null or p.deleted_at is not null),
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

-- ---------------------------------------------------------------------------
-- Signalement : une photo peut être signalée (copie conservée avec accord, comme un vocal).
-- ---------------------------------------------------------------------------
create or replace function public.report(
  p_reason           text,
  p_reported_user_id uuid default null,
  p_conversation_id  uuid default null,
  p_message_id       uuid default null,
  p_details          text default null,
  p_include_message  boolean default false
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := private.require_active_user();
  v_msg      public.messages%rowtype;
  v_evidence jsonb;
  v_id       uuid;
  v_details  text := nullif(btrim(coalesce(p_details, '')), '');
  v_purge    timestamptz := now() + make_interval(days => private.policy_int('report_retention_days'));
begin
  perform private.consume_rate_limit(v_uid, 'report',
    private.policy_int('report_daily_limit'), interval '1 day');

  if p_reason is null or p_reason not in
     ('spam', 'harassment', 'inappropriate', 'threat', 'impersonation', 'other', 'support') then
    raise exception 'REPORT_INVALID' using errcode = 'P0001';
  end if;
  if v_details is not null and char_length(v_details) > 1000 then
    raise exception 'REPORT_INVALID' using errcode = 'P0001';
  end if;

  if p_reason = 'support' then
    -- Demande d'assistance : aucune cible, un texte obligatoire.
    if p_reported_user_id is not null or p_message_id is not null or v_details is null then
      raise exception 'REPORT_INVALID' using errcode = 'P0001';
    end if;
  else
    if p_reported_user_id is null or p_reported_user_id = v_uid then
      raise exception 'REPORT_INVALID' using errcode = 'P0001';
    end if;
    if p_conversation_id is not null and not private.is_member(p_conversation_id, v_uid) then
      raise exception 'NOT_MEMBER' using errcode = 'P0001';
    end if;
    if p_message_id is not null then
      v_msg := private.visible_message(p_message_id, v_uid);
      if v_msg.kind not in ('text', 'voice', 'photo') or v_msg.sender_id is distinct from p_reported_user_id
         or v_msg.conversation_id is distinct from p_conversation_id then
        raise exception 'REPORT_INVALID' using errcode = 'P0001';
      end if;
      -- Déjà signalé par cette personne : on renvoie le signalement existant.
      select r.id into v_id from private.reports r
       where r.reporter_id = v_uid and r.message_id = p_message_id;
      if v_id is not null then
        return v_id;
      end if;
      if coalesce(p_include_message, false) and v_msg.deleted_at is null then
        v_evidence := jsonb_build_object(
          'kind', v_msg.kind, 'body', v_msg.body, 'sent_at', v_msg.sent_at,
          'sender_id', v_msg.sender_id, 'conversation_id', v_msg.conversation_id,
          'copied_at', now());
        if v_msg.media_path is not null then
          v_evidence := v_evidence || jsonb_build_object(
            'media_path', v_msg.media_path, 'duration_ms', v_msg.media_duration_ms);
          update private.media_objects
             set report_hold_until = greatest(coalesce(report_hold_until, v_purge), v_purge)
           where path = v_msg.media_path;
        end if;
      end if;
    end if;
  end if;

  insert into private.reports
    (reporter_id, reported_user_id, conversation_id, message_id, reason, details, evidence, purge_after)
  values
    (v_uid, p_reported_user_id, p_conversation_id, p_message_id, p_reason, v_details, v_evidence, v_purge)
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Purge : réservations abandonnées remboursées ; compteurs de quota de plus de 7 jours.
-- ---------------------------------------------------------------------------
create or replace function private.purge_expired()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_count integer;
  r       record;
begin
  -- Les réponses perdent leur lien (on delete set null) avant la suppression.
  -- Les fichiers des messages supprimés passent en attente d'effacement (déclencheur).
  delete from public.messages where expires_at <= now();
  get diagnostics v_count = row_count;
  for r in
    select o.path from private.media_objects o
     where o.state in ('reserved', 'uploaded') and o.created_at < now() - interval '1 hour'
  loop
    perform private.abandon_reservation(r.path);
  end loop;
  delete from private.rate_limit_hits where window_start < now() - interval '1 day';
  delete from private.reports where purge_after <= now();
  delete from private.photo_quota_daily where quota_day < private.quota_day() - 7;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits. harden_privileges() : + lecture Storage des photos et photos de profil.
-- ---------------------------------------------------------------------------
create or replace function private.harden_privileges()
returns void
language plpgsql
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig, n.nspname
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private')
       and not exists (select 1 from pg_catalog.pg_depend d
                        where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    if r.nspname = 'private' then
      execute format('revoke all on function %s from authenticated', r.sig);
    end if;
  end loop;
  -- Liste blanche explicite (fonctions utilisées dans des politiques RLS / Storage).
  grant execute on function private.session_is_active() to authenticated;
  grant execute on function private.is_member(uuid, uuid) to authenticated;
  grant execute on function private.shares_conversation(uuid, uuid) to authenticated;
  grant execute on function private.can_read_voice(text) to authenticated;
  grant execute on function private.can_read_photo(text) to authenticated;
  grant execute on function private.can_read_avatar(text) to authenticated;
  execute 'revoke all on all tables in schema private from public, anon, authenticated';
end;
$$;

select private.harden_privileges();

grant execute on function public.get_photo_quota() to authenticated;
grant execute on function public.prepare_photo_message(uuid, uuid) to authenticated;
grant execute on function public.send_photo_message(uuid, uuid, text, uuid, integer) to authenticated;
grant execute on function public.prepare_avatar_upload() to authenticated;
grant execute on function public.remove_avatar() to authenticated;
grant execute on function public.get_messages(uuid, timestamptz, timestamptz, integer) to authenticated;
grant execute on function public.list_conversations() to authenticated;
grant execute on function public.report(text, uuid, uuid, uuid, text, boolean) to authenticated;

-- Fonctions réservées au service (photo-send, avatar-set).
revoke all on function public.commit_photo_upload(text, integer, integer, integer) from authenticated;
revoke all on function public.release_media_reservation(text) from authenticated;
revoke all on function public.image_limits() from authenticated;
revoke all on function public.commit_avatar(text, integer, integer, integer) from authenticated;
grant execute on function public.commit_photo_upload(text, integer, integer, integer) to service_role;
grant execute on function public.release_media_reservation(text) to service_role;
grant execute on function public.image_limits() to service_role;
grant execute on function public.commit_avatar(text, integer, integer, integer) to service_role;
