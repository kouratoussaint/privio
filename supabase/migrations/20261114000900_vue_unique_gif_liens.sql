-- Lot 7.3b — vue unique (photos et vocaux), GIF (KLIPY), aperçus des liens.
--
-- Décisions (amendement 17) :
-- * vue unique : le destinataire ouvre une seule fois ; le fichier n'est lisible que dans
--   les 2 minutes qui suivent l'ouverture et jusqu'à la fermeture ; quand tous l'ont
--   fermée, le fichier est effacé ; l'expéditeur ne le revoit pas ;
-- * GIF : choisis chez KLIPY par le serveur (clé côté serveur), copiés dans le stockage
--   privé de Privio ; ils s'effacent avec le message ;
-- * aperçus des liens : préparés par le serveur (le site ne voit pas les personnes), image
--   gardée dans le stockage privé, effacée avec le message.

-- ---------------------------------------------------------------------------
-- Types, colonnes, compartiments
-- ---------------------------------------------------------------------------
alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check
  check (kind in ('text', 'system', 'voice', 'photo', 'sticker', 'gif'));
alter table public.messages add column view_once boolean not null default false;

-- Contenu selon le type : en plus, le GIF ; et une photo ou un vocal en vue unique perd
-- son fichier une fois fermé par tous.
alter table public.messages drop constraint if exists messages_content_check;
alter table public.messages add constraint messages_content_check check (
  case
    when deleted_at is not null then
      body is null and media_path is null and media_duration_ms is null and media_width is null
      and media_height is null and media_waveform is null
    when kind = 'voice' then
      body is null and (media_path is not null or view_once) and media_duration_ms is not null
      and media_width is null and media_height is null
    when kind = 'photo' then
      (media_path is not null or view_once) and media_width is not null and media_height is not null
      and media_duration_ms is null and media_waveform is null
    when kind = 'gif' then
      body is null and media_path is not null and media_width is not null and media_height is not null
      and media_duration_ms is null and media_waveform is null
    else
      body is not null and media_path is null and media_duration_ms is null and media_width is null
      and media_height is null and media_waveform is null
  end
);

alter table private.media_objects add column view_once boolean not null default false;
alter table private.media_objects drop constraint if exists media_objects_bucket_check;
alter table private.media_objects add constraint media_objects_bucket_check
  check (bucket in ('voice', 'photos', 'avatars', 'gifs', 'previews'));

create table private.view_once_opens (
  message_id uuid        not null references public.messages (id) on delete cascade,
  user_id    uuid        not null references auth.users (id) on delete cascade,
  opened_at  timestamptz not null default now(),
  closed_at  timestamptz,
  primary key (message_id, user_id)
);

create table private.link_previews (
  message_id   uuid        primary key references public.messages (id) on delete cascade,
  url          text        not null check (char_length(url) <= 2000),
  title        text        check (title is null or char_length(title) <= 300),
  description  text        check (description is null or char_length(description) <= 500),
  site         text        check (site is null or char_length(site) <= 100),
  image_path   text,
  image_width  integer     check (image_width is null or image_width between 1 and 8192),
  image_height integer     check (image_height is null or image_height between 1 and 8192),
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Vue unique
-- ---------------------------------------------------------------------------

-- Lisible par cette personne maintenant ? Jamais par l'expéditeur ; pour un destinataire,
-- seulement entre l'ouverture (2 minutes au plus) et la fermeture.
create or replace function private.view_once_readable(p_message_id uuid, p_sender uuid, p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_uid is distinct from p_sender and exists (
    select 1 from private.view_once_opens o
     where o.message_id = p_message_id and o.user_id = p_uid
       and o.closed_at is null and o.opened_at > now() - interval '2 minutes'
  );
$$;

-- Avant la publication d'une photo ou d'un vocal : « vue unique » (appelé par la fonction
-- d'envoi, au nom de l'expéditeur, sur SA réservation).
create or replace function public.mark_media_view_once(p_client_msg_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  update private.media_objects o set view_once = true
   where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id
     and o.bucket in ('photos', 'voice') and o.state in ('reserved', 'uploaded');
  if not found then
    raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
  end if;
end;
$$;

-- À la création du message : il hérite de « vue unique » de son fichier. Pas de légende.
create or replace function private.messages_view_once_from_media()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.media_path is not null and exists (
       select 1 from private.media_objects o where o.path = new.media_path and o.view_once) then
    if new.kind = 'photo' and new.body is not null then
      raise exception 'BODY_INVALID' using errcode = 'P0001';
    end if;
    new.view_once := true;
  end if;
  return new;
end;
$$;

drop trigger if exists messages_view_once on public.messages;
create trigger messages_view_once before insert on public.messages
  for each row execute function private.messages_view_once_from_media();

create or replace function public.open_view_once(p_message_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype := private.require_visible_message(p_message_id, v_uid);
  v_o   private.view_once_opens%rowtype;
begin
  if not v.view_once or v.sender_id = v_uid then
    raise exception 'VIEW_ONCE_UNAVAILABLE' using errcode = 'P0001';
  end if;
  select * into v_o from private.view_once_opens o
   where o.message_id = v.id and o.user_id = v_uid;
  if found then
    if v_o.closed_at is not null or v_o.opened_at <= now() - interval '2 minutes' then
      raise exception 'VIEW_ONCE_UNAVAILABLE' using errcode = 'P0001';
    end if;
    return;
  end if;
  if v.media_path is null then
    raise exception 'VIEW_ONCE_UNAVAILABLE' using errcode = 'P0001';
  end if;
  insert into private.view_once_opens (message_id, user_id) values (v.id, v_uid);
  update public.messages set updated_at = now() where id = v.id;
  perform private.signal_members(v.conversation_id, 'message_changed');
end;
$$;

-- Fermeture : quand tous les destinataires présents à l'envoi l'ont fermée, le fichier
-- est effacé.
create or replace function public.close_view_once(p_message_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype;
begin
  select * into v from public.messages m where m.id = p_message_id;
  if not found or not private.is_member(v.conversation_id, v_uid) then
    raise exception 'MESSAGE_NOT_FOUND' using errcode = 'P0001';
  end if;
  update private.view_once_opens o set closed_at = coalesce(closed_at, now())
   where o.message_id = v.id and o.user_id = v_uid;
  if v.media_path is not null and not exists (
       select 1 from public.conversation_members cm
        where cm.conversation_id = v.conversation_id and cm.left_at is null
          and cm.user_id is distinct from v.sender_id
          and private.member_since(v.conversation_id, cm.user_id) <= v.sent_at
          and not exists (select 1 from private.view_once_opens o
                           where o.message_id = v.id and o.user_id = cm.user_id
                             and (o.closed_at is not null or o.opened_at <= now() - interval '2 minutes'))) then
    perform private.mark_media_for_purge(v.media_path);
    update public.messages set media_path = null, updated_at = now() where id = v.id;
    perform private.signal_members(v.conversation_id, 'message_changed');
  end if;
end;
$$;

-- Fichiers des photos et vocaux : en plus, la règle de la vue unique.
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
       and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
       and (not m.view_once or private.view_once_readable(m.id, m.sender_id, auth.uid()))
  );
$$;

create or replace function private.can_read_voice(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and exists (
    select 1 from public.messages m
     where m.media_path = p_name and m.kind = 'voice' and m.deleted_at is null
       and m.expires_at > now()
       and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
       and (not m.view_once or private.view_once_readable(m.id, m.sender_id, auth.uid()))
  );
$$;

-- ---------------------------------------------------------------------------
-- GIF
-- ---------------------------------------------------------------------------

-- Identifiant pseudonyme transmis à KLIPY (jamais l'identifiant Privio) ; limite de
-- recherches.
create or replace function public.gif_customer_id()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  perform private.consume_rate_limit(v_uid, 'gif_search', 300, interval '1 hour');
  return md5('privio-gif:' || v_uid::text);
end;
$$;

create or replace function public.prepare_gif_message(p_conversation_id uuid, p_client_msg_id uuid)
returns table (path text, state text, message_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_member(p_conversation_id);
  v_msg public.messages%rowtype;
  v_row private.media_objects%rowtype;
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
    return query select null::text, 'sent'::text, v_msg.id;
    return;
  end if;
  perform private.check_can_post(p_conversation_id, v_uid);
  insert into private.media_objects (path, bucket, owner_id, conversation_id, client_msg_id)
  values (p_conversation_id::text || '/' || gen_random_uuid()::text, 'gifs', v_uid,
          p_conversation_id, p_client_msg_id)
  on conflict (owner_id, client_msg_id) do nothing;
  select * into v_row from private.media_objects o
   where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id;
  if v_row.conversation_id is distinct from p_conversation_id or v_row.bucket <> 'gifs' then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query select v_row.path, v_row.state, null::uuid;
end;
$$;

create or replace function public.commit_gif_upload(p_path text, p_width integer, p_height integer, p_bytes integer)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.require_service();
  if p_width is null or p_height is null or p_width < 1 or p_height < 1
     or greatest(p_width, p_height) > 2048 then
    raise exception 'MEDIA_INVALID' using errcode = 'P0001';
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > 4194304 then
    raise exception 'MEDIA_TOO_LARGE' using errcode = 'P0001';
  end if;
  update private.media_objects
     set state = 'uploaded', width = p_width, height = p_height, bytes = p_bytes
   where path = p_path and bucket = 'gifs' and state in ('reserved', 'uploaded');
  if not found then
    raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.send_gif_message(
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_reply_to_id     uuid default null,
  p_ttl_seconds     integer default null
)
returns table (id uuid, sent_at timestamptz, expires_at timestamptz, media_path text,
               media_width integer, media_height integer)
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
     where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id and o.bucket = 'gifs';
    if not found or v_obj.state not in ('uploaded', 'attached') then
      raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
    end if;
    if v_obj.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    v := private.post_message(v_uid, p_conversation_id, p_client_msg_id, 'gif', null,
                              p_reply_to_id, p_ttl_seconds, v_obj.path, null,
                              v_obj.width, v_obj.height);
    update private.media_objects o set state = 'attached', message_id = v.id
     where o.path = v_obj.path and o.state = 'uploaded';
  elsif v.conversation_id <> p_conversation_id then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query select v.id, v.sent_at, v.expires_at, v.media_path, v.media_width, v.media_height;
end;
$$;

create or replace function private.can_read_gif(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and exists (
    select 1 from public.messages m
     where m.media_path = p_name and m.kind = 'gif' and m.deleted_at is null
       and m.expires_at > now()
       and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
  );
$$;

-- ---------------------------------------------------------------------------
-- Aperçus des liens
-- ---------------------------------------------------------------------------

-- Lien à prévisualiser : le premier lien http(s) d'un de MES messages texte, s'il n'a pas
-- encore d'aperçu (null sinon).
create or replace function public.link_preview_target(p_message_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype := private.require_visible_message(p_message_id, v_uid);
  v_url text;
begin
  if v.sender_id is distinct from v_uid then
    raise exception 'NOT_SENDER' using errcode = 'P0001';
  end if;
  if v.kind <> 'text' or exists (select 1 from private.link_previews lp where lp.message_id = v.id) then
    return null;
  end if;
  perform private.consume_rate_limit(v_uid, 'link_preview', 60, interval '1 hour');
  v_url := substring(v.body from '(https?://[^[:space:]<>"]+)');
  v_url := regexp_replace(v_url, '[.,;:!?)\]»’'']+$', '');
  if v_url is null or char_length(v_url) > 2000 then
    return null;
  end if;
  return v_url;
end;
$$;

create or replace function public.save_link_preview(
  p_message_id   uuid,
  p_url          text,
  p_title        text,
  p_description  text,
  p_site         text,
  p_image_path   text default null,
  p_image_width  integer default null,
  p_image_height integer default null,
  p_image_bytes  integer default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v public.messages%rowtype;
begin
  perform private.require_service();
  select * into v from public.messages m where m.id = p_message_id;
  if not found or v.deleted_at is not null or v.expires_at <= now() or v.kind <> 'text' then
    raise exception 'MESSAGE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_title is null and p_description is null and p_image_path is null then
    return;
  end if;
  if p_image_path is not null then
    insert into private.media_objects (path, bucket, owner_id, conversation_id, client_msg_id,
                                       state, message_id, width, height, bytes)
    values (p_image_path, 'previews', v.sender_id, v.conversation_id, v.client_msg_id,
            'attached', v.id, p_image_width, p_image_height, p_image_bytes);
  end if;
  insert into private.link_previews (message_id, url, title, description, site, image_path,
                                     image_width, image_height)
  values (v.id, left(p_url, 2000), left(p_title, 300), left(p_description, 500), left(p_site, 100),
          p_image_path, p_image_width, p_image_height)
  on conflict (message_id) do nothing;
  update public.messages set updated_at = now() where id = v.id;
  perform private.signal_members(v.conversation_id, 'message_changed');
end;
$$;

-- L'image d'un aperçu s'efface avec lui (message expiré, supprimé pour tous).
create or replace function private.link_preview_release()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.image_path is not null then
    perform private.mark_media_for_purge(old.image_path);
  end if;
  return old;
end;
$$;

drop trigger if exists link_preview_release on private.link_previews;
create trigger link_preview_release after delete on private.link_previews
  for each row execute function private.link_preview_release();

create or replace function private.messages_drop_preview()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    delete from private.link_previews where message_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists messages_drop_preview on public.messages;
create trigger messages_drop_preview after update on public.messages
  for each row execute function private.messages_drop_preview();

create or replace function private.can_read_preview(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and exists (
    select 1 from private.link_previews lp
      join public.messages m on m.id = lp.message_id
     where lp.image_path = p_name and m.deleted_at is null and m.expires_at > now()
       and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
  );
$$;

-- ---------------------------------------------------------------------------
-- Compartiments privés
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('gifs', 'gifs', false, 4194304, array['image/gif', 'image/webp']),
           ('previews', 'previews', false, 524288, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do update
      set public = false,
          file_size_limit = excluded.file_size_limit,
          allowed_mime_types = excluded.allowed_mime_types;
    execute 'drop policy if exists privio_gif_read on storage.objects';
    execute $p$
      create policy privio_gif_read on storage.objects
        for select to authenticated
        using (bucket_id = 'gifs' and private.can_read_gif(name))
    $p$;
    execute 'drop policy if exists privio_preview_read on storage.objects';
    execute $p$
      create policy privio_preview_read on storage.objects
        for select to authenticated
        using (bucket_id = 'previews' and private.can_read_preview(name))
    $p$;
  else
    raise notice 'Storage absent : compartiments « gifs » et « previews » non créés (test local)';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Envoi, liste, messages : inchangés, plus les GIF, la vue unique et les aperçus.
-- ---------------------------------------------------------------------------
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
       or v_reply.kind not in ('text', 'voice', 'photo', 'sticker', 'gif')
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

drop function if exists public.get_messages(uuid, timestamptz, timestamptz, integer);

CREATE OR REPLACE FUNCTION public.get_messages(p_conversation_id uuid, p_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, sender_id uuid, sender_name text, kind text, body text, reply_to_id uuid, reply_preview text, reply_kind text, sent_at timestamp with time zone, expires_at timestamp with time zone, edited_at timestamp with time zone, deleted_at timestamp with time zone, updated_at timestamp with time zone, reactions jsonb, media_path text, media_duration_ms integer, media_width integer, media_height integer, media_waveform smallint[], mentions uuid[], view_once boolean, opened boolean, opened_count integer, link_preview jsonb)
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
         m.sent_at, m.expires_at, m.edited_at, m.deleted_at, m.updated_at,
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
         end
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
$function$;

-- Droits : les règles de lecture des nouveaux compartiments s'ajoutent à la liste.
CREATE OR REPLACE FUNCTION private.harden_privileges()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
  grant execute on function private.session_is_active() to authenticated;
  grant execute on function private.is_member(uuid, uuid) to authenticated;
  grant execute on function private.shares_conversation(uuid, uuid) to authenticated;
  grant execute on function private.can_see_message(uuid, timestamptz, uuid) to authenticated;
  grant execute on function private.can_read_voice(text) to authenticated;
  grant execute on function private.can_read_photo(text) to authenticated;
  grant execute on function private.can_read_avatar(text) to authenticated;
  grant execute on function private.can_read_evidence(text) to authenticated;
  grant execute on function private.can_read_gif(text) to authenticated;
  grant execute on function private.can_read_preview(text) to authenticated;
  execute 'revoke all on all tables in schema private from public, anon, authenticated';
end;
$function$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.mark_media_view_once(uuid) to authenticated;
grant execute on function public.open_view_once(uuid) to authenticated;
grant execute on function public.close_view_once(uuid) to authenticated;
grant execute on function public.gif_customer_id() to authenticated;
grant execute on function public.prepare_gif_message(uuid, uuid) to authenticated;
grant execute on function public.send_gif_message(uuid, uuid, uuid, integer) to authenticated;
grant execute on function public.link_preview_target(uuid) to authenticated;
revoke all on function public.commit_gif_upload(text, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.save_link_preview(uuid, text, text, text, text, text, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.commit_gif_upload(text, integer, integer, integer) to service_role;
grant execute on function public.save_link_preview(uuid, text, text, text, text, text, integer, integer, integer) to service_role;
grant execute on function public.list_conversations() to authenticated;
grant execute on function public.get_messages(uuid, timestamptz, timestamptz, integer) to authenticated;
