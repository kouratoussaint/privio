-- Lot 7.4 : autocollants personnels (décisions du 17/11/2026, ADR-051).
--   Création sur le téléphone (photo détourée ou recadrée, texte facultatif), image PNG ou
--   WebP de 512 px au plus et 512 Ko au plus, déposée par la fonction « sticker ».
--   Collection gardée ici pour mon compte (60 au plus), lisible par moi seul.
--   Envoi : le fichier est recopié pour le message (compartiment « stickers », chemin
--   msg/<discussion>/…) et s'efface avec lui, comme une photo. Corps du message :
--   « perso/partageable » ou « perso/prive ». Un autocollant « partageable » reçu peut être
--   ajouté à ma collection (copie faite par le serveur).

-- ---------------------------------------------------------------------------
-- 1. Messages : un autocollant personnel porte son fichier
-- ---------------------------------------------------------------------------
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
    when kind = 'sticker' then
      body is not null and media_duration_ms is null and media_waveform is null
      and ((media_path is null and media_width is null and media_height is null)
           or (media_path is not null and media_width is not null and media_height is not null))
    else
      body is not null and media_path is null and media_duration_ms is null and media_width is null
      and media_height is null and media_waveform is null
  end
);

alter table private.media_objects drop constraint if exists media_objects_bucket_check;
alter table private.media_objects add constraint media_objects_bucket_check
  check (bucket in ('voice', 'photos', 'avatars', 'gifs', 'previews', 'stickers'));

-- ---------------------------------------------------------------------------
-- 2. Ma collection
-- ---------------------------------------------------------------------------
create table if not exists private.user_stickers (
  id         uuid        primary key default gen_random_uuid(),
  owner_id   uuid        not null references auth.users (id) on delete cascade,
  path       text        not null unique,
  shareable  boolean     not null default false,
  state      text        not null default 'reserved' check (state in ('reserved', 'ready')),
  width      integer     check (width between 1 and 512),
  height     integer     check (height between 1 and 512),
  bytes      integer     check (bytes between 1 and 524288),
  created_at timestamptz not null default now()
);
create index if not exists user_stickers_owner_idx on private.user_stickers (owner_id, created_at);
alter table private.user_stickers enable row level security;

-- Au plus 60 autocollants par compte (les réservations de plus d'une heure ne comptent plus).
create or replace function private.require_sticker_room(p_uid uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select count(*) from private.user_stickers s
       where s.owner_id = p_uid
         and (s.state = 'ready' or s.created_at > now() - interval '1 hour')) >= 60 then
    raise exception 'STICKER_LIMIT' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.my_stickers()
returns table (id uuid, path text, shareable boolean, width integer, height integer,
               created_at timestamptz)
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
  select s.id, s.path, s.shareable, s.width, s.height, s.created_at
    from private.user_stickers s
   where s.owner_id = v_uid and s.state = 'ready'
   order by s.created_at desc;
end;
$$;

-- Réserver la place d'un nouvel autocollant (avant le dépôt du fichier par la fonction).
create or replace function public.reserve_sticker(p_shareable boolean default false)
returns table (id uuid, path text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_id  uuid := gen_random_uuid();
begin
  perform private.require_sticker_room(v_uid);
  perform private.consume_rate_limit(v_uid, 'sticker_create', 30, interval '1 hour');
  delete from private.user_stickers s
   where s.owner_id = v_uid and s.state = 'reserved' and s.created_at < now() - interval '1 hour';
  insert into private.user_stickers (id, owner_id, path, shareable)
  values (v_id, v_uid, v_uid::text || '/' || v_id::text, coalesce(p_shareable, false));
  return query select v_id, v_uid::text || '/' || v_id::text;
end;
$$;

-- Fichier déposé (fonction « sticker », clé de service) : l'autocollant devient utilisable.
create or replace function public.commit_sticker(
  p_id uuid, p_width integer, p_height integer, p_bytes integer
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.require_service();
  if p_width is null or p_height is null or p_width < 1 or p_height < 1
     or greatest(p_width, p_height) > 512 then
    raise exception 'MEDIA_INVALID' using errcode = 'P0001';
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > 524288 then
    raise exception 'MEDIA_TOO_LARGE' using errcode = 'P0001';
  end if;
  update private.user_stickers
     set state = 'ready', width = p_width, height = p_height, bytes = p_bytes
   where id = p_id;
  if not found then
    raise exception 'STICKER_NOT_FOUND' using errcode = 'P0001';
  end if;
end;
$$;

-- Retirer de ma collection ; renvoie le fichier à effacer (les messages déjà envoyés ont
-- leur propre copie).
create or replace function public.remove_sticker(p_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_path text;
begin
  delete from private.user_stickers s
   where s.id = p_id and s.owner_id = v_uid
  returning s.path into v_path;
  if v_path is null then
    raise exception 'STICKER_NOT_FOUND' using errcode = 'P0001';
  end if;
  return v_path;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Envoi : copie du fichier pour le message (comme un GIF)
-- ---------------------------------------------------------------------------
create or replace function public.prepare_sticker_message(
  p_conversation_id uuid, p_client_msg_id uuid, p_sticker_id uuid
)
returns table (path text, source text, state text, message_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_member(p_conversation_id);
  v_msg public.messages%rowtype;
  v_st  private.user_stickers%rowtype;
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
    return query select null::text, null::text, 'sent'::text, v_msg.id;
    return;
  end if;
  select * into v_st from private.user_stickers s
   where s.id = p_sticker_id and s.owner_id = v_uid and s.state = 'ready';
  if not found then
    raise exception 'STICKER_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.check_can_post(p_conversation_id, v_uid);
  insert into private.media_objects (path, bucket, owner_id, conversation_id, client_msg_id,
                                     width, height)
  values ('msg/' || p_conversation_id::text || '/' || gen_random_uuid()::text, 'stickers', v_uid,
          p_conversation_id, p_client_msg_id, v_st.width, v_st.height)
  on conflict (owner_id, client_msg_id) do nothing;
  select * into v_row from private.media_objects o
   where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id;
  if v_row.conversation_id is distinct from p_conversation_id or v_row.bucket <> 'stickers' then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query select v_row.path, v_st.path, v_row.state, null::uuid;
end;
$$;

-- Copie faite (clé de service).
create or replace function public.commit_sticker_message(p_path text, p_bytes integer)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.require_service();
  if p_bytes is null or p_bytes < 1 or p_bytes > 524288 then
    raise exception 'MEDIA_TOO_LARGE' using errcode = 'P0001';
  end if;
  update private.media_objects
     set state = 'uploaded', bytes = p_bytes
   where path = p_path and bucket = 'stickers' and state in ('reserved', 'uploaded');
  if not found then
    raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.send_sticker_message(
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_sticker_id      uuid,
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
  v_st  private.user_stickers%rowtype;
  v     public.messages%rowtype;
begin
  select * into v from public.messages m
   where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
  if not found then
    select * into v_obj from private.media_objects o
     where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id and o.bucket = 'stickers';
    if not found or v_obj.state not in ('uploaded', 'attached') then
      raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
    end if;
    if v_obj.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    select * into v_st from private.user_stickers s
     where s.id = p_sticker_id and s.owner_id = v_uid;
    if not found then
      raise exception 'STICKER_NOT_FOUND' using errcode = 'P0001';
    end if;
    v := private.post_message(v_uid, p_conversation_id, p_client_msg_id, 'sticker',
                              case when v_st.shareable then 'perso/partageable' else 'perso/prive' end,
                              p_reply_to_id, p_ttl_seconds, v_obj.path, null,
                              v_obj.width, v_obj.height);
    update private.media_objects o set state = 'attached', message_id = v.id
     where o.path = v_obj.path and o.state = 'uploaded';
  elsif v.conversation_id <> p_conversation_id then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query select v.id, v.sent_at, v.expires_at, v.body, v.media_path, v.media_width,
                      v.media_height;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Ajouter à ma collection un autocollant « partageable » reçu
-- ---------------------------------------------------------------------------
create or replace function public.prepare_save_sticker(p_message_id uuid)
returns table (id uuid, path text, source text, width integer, height integer)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype := private.require_visible_message(p_message_id, v_uid);
  v_id  uuid := gen_random_uuid();
begin
  if v.kind <> 'sticker' or v.media_path is null then
    raise exception 'STICKER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v.body is distinct from 'perso/partageable' then
    raise exception 'STICKER_NOT_SHAREABLE' using errcode = 'P0001';
  end if;
  perform private.require_sticker_room(v_uid);
  perform private.consume_rate_limit(v_uid, 'sticker_create', 30, interval '1 hour');
  insert into private.user_stickers (id, owner_id, path, shareable)
  values (v_id, v_uid, v_uid::text || '/' || v_id::text, true);
  return query select v_id, v_uid::text || '/' || v_id::text, v.media_path, v.media_width,
                      v.media_height;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Lecture des fichiers : ma collection, ou un message que je peux voir
-- ---------------------------------------------------------------------------
create or replace function private.can_read_sticker(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and (
    exists (select 1 from private.user_stickers s
             where s.path = p_name and s.owner_id = auth.uid() and s.state = 'ready')
    or exists (
      select 1 from public.messages m
       where m.media_path = p_name and m.kind = 'sticker' and m.deleted_at is null
         and m.expires_at > now()
         and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
         and not private.erased_for(m.id, auth.uid())
    )
  );
$$;

do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('stickers', 'stickers', false, 524288, array['image/png', 'image/webp'])
    on conflict (id) do update
      set public = false,
          file_size_limit = excluded.file_size_limit,
          allowed_mime_types = excluded.allowed_mime_types;
    execute 'drop policy if exists privio_sticker_read on storage.objects';
    execute $p$
      create policy privio_sticker_read on storage.objects
        for select to authenticated
        using (bucket_id = 'stickers' and private.can_read_sticker(name))
    $p$;
  else
    raise notice 'Storage absent : compartiment « stickers » non créé (test local)';
  end if;
end;
$$;

-- Lot 7.4 : la lecture des autocollants reste permise après chaque durcissement.
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
  grant execute on function private.can_read_sticker(text) to authenticated;
  execute 'revoke all on all tables in schema private from public, anon, authenticated';
end;
$function$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function private.can_read_sticker(text) to authenticated;
grant execute on function public.my_stickers() to authenticated;
grant execute on function public.reserve_sticker(boolean) to authenticated;
grant execute on function public.remove_sticker(uuid) to authenticated;
grant execute on function public.prepare_sticker_message(uuid, uuid, uuid) to authenticated;
grant execute on function public.send_sticker_message(uuid, uuid, uuid, uuid, integer) to authenticated;
grant execute on function public.prepare_save_sticker(uuid) to authenticated;
revoke all on function public.commit_sticker(uuid, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.commit_sticker(uuid, integer, integer, integer) to service_role;
revoke all on function public.commit_sticker_message(text, integer) from public, anon, authenticated;
grant execute on function public.commit_sticker_message(text, integer) to service_role;
