-- PRIVIO — Migration 10 (lot 3.1) : messages vocaux
-- Invariants :
--   * le son est stocké dans un bucket Storage PRIVÉ « voice », sous un chemin opaque.
--     Aucune URL publique ni signée : l'application télécharge avec son jeton, et la
--     politique Storage n'autorise la lecture qu'aux membres de la discussion, tant que
--     le message existe, n'est pas supprimé et n'a pas expiré ;
--   * la durée (≤ voice_max_seconds) et la taille sont MESURÉES par le serveur (fonction
--     voice-send, table d'échantillons du fichier), jamais reprises de l'application ;
--   * à l'expiration ou à la suppression du message, le fichier devient illisible
--     immédiatement, puis il est effacé physiquement par la fonction media-purge via
--     l'API Storage (un DELETE SQL laisserait le fichier orphelin dans le stockage).

-- ---------------------------------------------------------------------------
-- Politiques
-- ---------------------------------------------------------------------------
update private.policy_definitions set implemented = true where key = 'voice_max_seconds';

insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('voice_max_bytes', 'integer', '524288', 65536, 1048576, null, false, true,
   'Taille maximale d''un message vocal (octets).'),
  ('voice_upload_hourly_limit', 'integer', '120', 10, 1000, null, false, true,
   'Messages vocaux préparés par compte et par heure (anti-abus).');

-- ---------------------------------------------------------------------------
-- Réglages d'exécution (jamais exposés) : adresse des fonctions, jeton de purge.
-- ---------------------------------------------------------------------------
create table private.runtime_settings (
  key        text        primary key,
  value      text        not null,
  updated_at timestamptz not null default now()
);
insert into private.runtime_settings (key, value)
values ('media_purge_token',
        replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''))
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Registre des fichiers médias (réservation → envoi → rattachement → purge)
-- ---------------------------------------------------------------------------
create table private.media_objects (
  path               text        primary key,
  bucket             text        not null default 'voice' check (bucket in ('voice')),
  -- Mis à null quand la réservation est abandonnée (une nouvelle peut alors être créée).
  owner_id           uuid        references auth.users (id) on delete set null,
  conversation_id    uuid        not null,
  client_msg_id      uuid        not null,
  state              text        not null default 'reserved'
                       check (state in ('reserved', 'uploaded', 'attached', 'purge')),
  duration_ms        integer     check (duration_ms > 0),
  bytes              integer     check (bytes > 0),
  message_id         uuid,
  created_at         timestamptz not null default now(),
  purge_requested_at timestamptz,
  purge_claimed_at   timestamptz,
  purge_attempts     integer     not null default 0,
  -- Copie jointe à un signalement (avec l'accord de la personne) : effacement différé.
  report_hold_until  timestamptz,
  unique (owner_id, client_msg_id),
  check ((state = 'purge') = (purge_requested_at is not null))
);
create index media_objects_purge_idx on private.media_objects (purge_requested_at) where state = 'purge';
create index media_objects_stale_idx on private.media_objects (created_at) where state in ('reserved', 'uploaded');
revoke all on private.media_objects, private.runtime_settings from public, anon, authenticated;

-- Demande d'effacement physique d'un fichier (le fichier est déjà illisible).
create or replace function private.mark_media_for_purge(p_path text)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update private.media_objects
     set state = 'purge', purge_requested_at = coalesce(purge_requested_at, now())
   where path = p_path;
$$;

-- ---------------------------------------------------------------------------
-- Messages : type « voice », chemin et durée du son
-- ---------------------------------------------------------------------------
alter table public.messages
  add column media_path        text,
  add column media_duration_ms integer check (media_duration_ms is null or media_duration_ms between 1 and 60000);
create index messages_media_path_idx on public.messages (media_path) where media_path is not null;

alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check check (kind in ('text', 'system', 'voice'));

-- Remplace « (deleted_at is null) = (body is not null) » par une règle par type.
do $$
declare
  r record;
begin
  for r in
    select conname from pg_constraint
     where conrelid = 'public.messages'::regclass and contype = 'c'
       and pg_get_constraintdef(oid) like '%(deleted_at IS NULL) = (body IS NOT NULL)%'
  loop
    execute format('alter table public.messages drop constraint %I', r.conname);
  end loop;
end;
$$;
alter table public.messages add constraint messages_content_check check (
  case
    when deleted_at is not null then body is null and media_path is null and media_duration_ms is null
    when kind = 'voice'         then body is null and media_path is not null and media_duration_ms is not null
    else                             body is not null and media_path is null and media_duration_ms is null
  end
);

grant select (media_path, media_duration_ms) on public.messages to authenticated;

-- Un vocal ne se modifie pas ; sa suppression libère le fichier.
create or replace function private.messages_media_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.kind = 'voice' and new.body is not null then
    raise exception 'MESSAGE_NOT_EDITABLE' using errcode = 'P0001';
  end if;
  if new.deleted_at is not null and old.media_path is not null then
    perform private.mark_media_for_purge(old.media_path);
    new.media_path := null;
    new.media_duration_ms := null;
  end if;
  return new;
end;
$$;

create or replace function private.messages_media_release()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.media_path is not null then
    perform private.mark_media_for_purge(old.media_path);
  end if;
  return old;
end;
$$;

create trigger messages_media_guard before update on public.messages
  for each row execute function private.messages_media_guard();
-- Expiration (purge), suppression de compte, suppression en cascade.
create trigger messages_media_release after delete on public.messages
  for each row execute function private.messages_media_release();

-- ---------------------------------------------------------------------------
-- Lecture du son : membre actif, message présent, non supprimé, non expiré.
-- ---------------------------------------------------------------------------
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
       and private.is_member(m.conversation_id, auth.uid())
  );
$$;

-- Bucket privé et politique de lecture. Aucune politique d'écriture : seul le service
-- (fonction voice-send, après vérification) dépose des fichiers.
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('voice', 'voice', false, 1048576, array['audio/mp4'])
    on conflict (id) do update
      set public = false,
          file_size_limit = excluded.file_size_limit,
          allowed_mime_types = excluded.allowed_mime_types;
    execute 'drop policy if exists privio_voice_read on storage.objects';
    execute $p$
      create policy privio_voice_read on storage.objects
        for select to authenticated
        using (bucket_id = 'voice' and private.can_read_voice(name))
    $p$;
  else
    raise notice 'Storage absent : bucket « voice » non créé (environnement de test local)';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Envoi commun (texte et vocal) : appartenance, blocage, réponse, limite, durée.
-- ---------------------------------------------------------------------------
create or replace function private.post_message(
  p_uid             uuid,
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_kind            text,
  p_body            text,
  p_reply_to_id     uuid,
  p_ttl_seconds     integer,
  p_media_path      text default null,
  p_duration_ms     integer default null
)
returns public.messages
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_body     text := case when p_kind = 'text' then btrim(coalesce(p_body, '')) end;
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
  if p_reply_to_id is not null then
    select * into v_reply from public.messages m where m.id = p_reply_to_id;
    if not found or v_reply.conversation_id <> p_conversation_id or v_reply.expires_at <= now()
       or v_reply.kind not in ('text', 'voice') then
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
       media_path, media_duration_ms)
    values
      (p_conversation_id, p_uid, p_client_msg_id, p_kind, v_body, p_reply_to_id, now(),
       now() + make_interval(secs => v_ttl), p_media_path, p_duration_ms)
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

-- Texte : même signature et même comportement qu'au lot 2.E.
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
declare
  v_uid uuid := private.require_member(p_conversation_id);
  v     public.messages%rowtype;
begin
  v := private.post_message(v_uid, p_conversation_id, p_client_msg_id, 'text', p_body,
                            p_reply_to_id, p_ttl_seconds);
  return query select v.id, v.sent_at, v.expires_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- Vocal, étape 1 (application, via voice-send) : réserver un chemin de fichier.
-- Idempotent : un renvoi avec le même identifiant client retrouve la même réservation,
-- ou le message déjà envoyé (state = 'sent').
-- ---------------------------------------------------------------------------
create or replace function public.prepare_voice_message(p_conversation_id uuid, p_client_msg_id uuid)
returns table (path text, state text, message_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_peer uuid;
  v_msg  public.messages%rowtype;
  v_row  private.media_objects%rowtype;
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

  v_peer := private.direct_peer(p_conversation_id, v_uid);
  if v_peer is not null and private.is_blocked_between(v_uid, v_peer) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;

  select * into v_row from private.media_objects o
   where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id;
  if not found then
    perform private.consume_rate_limit(v_uid, 'voice_upload',
      private.policy_int('voice_upload_hourly_limit'), interval '1 hour');
    insert into private.media_objects (path, owner_id, conversation_id, client_msg_id)
    values (p_conversation_id::text || '/' || gen_random_uuid()::text || '.m4a',
            v_uid, p_conversation_id, p_client_msg_id)
    on conflict (owner_id, client_msg_id) do nothing;
    select * into v_row from private.media_objects o
     where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id;
  end if;
  if v_row.conversation_id <> p_conversation_id then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query select v_row.path, v_row.state, null::uuid;
end;
$$;

-- Vocal, étape 2 (SERVICE uniquement, après dépôt du fichier vérifié par voice-send).
create or replace function public.commit_voice_upload(p_path text, p_duration_ms integer, p_bytes integer)
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
  update private.media_objects
     set state = 'uploaded', duration_ms = p_duration_ms, bytes = p_bytes
   where path = p_path and state in ('reserved', 'uploaded');
  if not found then
    raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
  end if;
end;
$$;

-- Vocal, étape 3 (application, via voice-send) : publier le message.
create or replace function public.send_voice_message(
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_reply_to_id     uuid default null,
  p_ttl_seconds     integer default null
)
returns table (id uuid, sent_at timestamptz, expires_at timestamptz,
               media_path text, media_duration_ms integer)
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
    update private.media_objects o set state = 'attached', message_id = v.id
     where o.path = v_obj.path and o.state = 'uploaded';
  elsif v.conversation_id <> p_conversation_id then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query select v.id, v.sent_at, v.expires_at, v.media_path, v.media_duration_ms;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lecture des messages : + chemin et durée du son, type du message cité.
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
  media_duration_ms integer
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
         m.media_path, m.media_duration_ms
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

-- Liste : les vocaux comptent comme non lus (même retour qu'à la migration 9).
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
     where v.sender_id is distinct from v_uid and v.deleted_at is null and v.kind in ('text', 'voice')
       and (mine.read_up_to is null or v.sent_at > mine.read_up_to)
     group by v.conversation_id
  )
  select mine.id, mine.kind,
         peer.user_id, p.handle, p.display_name, p.avatar_path,
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
-- Signalement : un vocal peut être signalé. Avec l'accord de la personne, le fichier
-- est conservé pour la modération jusqu'à l'échéance du signalement (décision B3),
-- sans redevenir lisible par l'application.
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
      if v_msg.kind not in ('text', 'voice') or v_msg.sender_id is distinct from p_reported_user_id
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
        if v_msg.kind = 'voice' then
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
-- Effacement physique des fichiers (fonction media-purge, SERVICE uniquement).
-- ---------------------------------------------------------------------------
create or replace function private.require_service()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if current_setting('role', true) is distinct from 'service_role' then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function private.check_purge_token(p_token text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_service();
  if p_token is null or p_token is distinct from
     (select s.value from private.runtime_settings s where s.key = 'media_purge_token') then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
end;
$$;

-- Limites appliquées par voice-send avant le dépôt du fichier.
create or replace function public.voice_limits()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_service();
  return jsonb_build_object('voice_max_seconds', private.policy_int('voice_max_seconds'),
                            'voice_max_bytes', private.policy_int('voice_max_bytes'));
end;
$$;

-- Adresse des fonctions, déclarée par les fonctions elles-mêmes (variable SUPABASE_URL
-- de leur environnement) : la tâche planifiée sait ainsi où appeler media-purge.
create or replace function public.media_register_endpoint(p_functions_url text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.require_service();
  if p_functions_url is null or p_functions_url !~ '^https?://[^ ]+/functions/v1$' then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  insert into private.runtime_settings (key, value) values ('functions_url', p_functions_url)
  on conflict (key) do update set value = excluded.value, updated_at = now()
   where private.runtime_settings.value is distinct from excluded.value;
end;
$$;

-- Lot de fichiers à effacer (réservés 5 min ; repris ensuite en cas d'échec).
create or replace function public.media_purge_claim(p_token text, p_limit integer default 100)
returns table (bucket text, path text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.check_purge_token(p_token);
  return query
  update private.media_objects o
     set purge_claimed_at = now(), purge_attempts = o.purge_attempts + 1
   where o.path in (
     select x.path from private.media_objects x
      where x.state = 'purge'
        and (x.report_hold_until is null or x.report_hold_until <= now())
        and (x.purge_claimed_at is null or x.purge_claimed_at < now() - interval '5 minutes')
      order by x.purge_requested_at
      limit least(greatest(coalesce(p_limit, 100), 1), 500)
      for update skip locked)
  returning o.bucket, o.path;
end;
$$;

-- Fichiers effectivement effacés du stockage : on oublie leur trace.
create or replace function public.media_purge_complete(p_token text, p_paths text[])
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  perform private.check_purge_token(p_token);
  delete from private.media_objects where state = 'purge' and path = any (coalesce(p_paths, '{}'));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Appel de media-purge par la base (pg_net), uniquement s'il y a du travail.
create or replace function private.request_media_purge()
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_url   text := (select s.value from private.runtime_settings s where s.key = 'functions_url');
  v_token text := (select s.value from private.runtime_settings s where s.key = 'media_purge_token');
  v_id    bigint;
begin
  if not exists (
    select 1 from private.media_objects x
     where x.state = 'purge'
       and (x.report_hold_until is null or x.report_hold_until <= now())
       and (x.purge_claimed_at is null or x.purge_claimed_at < now() - interval '5 minutes')) then
    return null;
  end if;
  if v_url is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    return null;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
     into v_id
    using v_url || '/media-purge', '{}'::jsonb,
          jsonb_build_object('Content-Type', 'application/json', 'x-privio-purge', v_token), 20000;
  return v_id;
end;
$$;

-- Purge : + réservations abandonnées depuis plus d'une heure (fichier jamais publié).
create or replace function private.purge_expired()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  -- Les réponses perdent leur lien (on delete set null) avant la suppression.
  -- Les fichiers des vocaux supprimés passent en attente d'effacement (déclencheur).
  delete from public.messages where expires_at <= now();
  get diagnostics v_count = row_count;
  update private.media_objects
     set state = 'purge', owner_id = null, purge_requested_at = now()
   where state in ('reserved', 'uploaded') and created_at < now() - interval '1 hour';
  delete from private.rate_limit_hits where window_start < now() - interval '1 day';
  delete from private.reports where purge_after <= now();
  return v_count;
end;
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  else
    raise notice 'pg_net indisponible : effacement physique non planifié (environnement de test local)';
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_media_purge';
    perform cron.schedule('privio_media_purge', '* * * * *', 'select private.request_media_purge()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits. harden_privileges() : + private.can_read_voice (politique Storage).
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
  execute 'revoke all on all tables in schema private from public, anon, authenticated';
end;
$$;

select private.harden_privileges();

grant execute on function public.send_message(uuid, uuid, text, uuid, integer) to authenticated;
grant execute on function public.prepare_voice_message(uuid, uuid) to authenticated;
grant execute on function public.send_voice_message(uuid, uuid, uuid, integer) to authenticated;
grant execute on function public.get_messages(uuid, timestamptz, timestamptz, integer) to authenticated;
grant execute on function public.list_conversations() to authenticated;
grant execute on function public.report(text, uuid, uuid, uuid, text, boolean) to authenticated;

-- Fonctions réservées au service (fonctions voice-send et media-purge).
revoke all on function public.commit_voice_upload(text, integer, integer) from authenticated;
revoke all on function public.voice_limits() from authenticated;
revoke all on function public.media_register_endpoint(text) from authenticated;
revoke all on function public.media_purge_claim(text, integer) from authenticated;
revoke all on function public.media_purge_complete(text, text[]) from authenticated;
grant execute on function public.commit_voice_upload(text, integer, integer) to service_role;
grant execute on function public.voice_limits() to service_role;
grant execute on function public.media_register_endpoint(text) to service_role;
grant execute on function public.media_purge_claim(text, integer) to service_role;
grant execute on function public.media_purge_complete(text, text[]) to service_role;
