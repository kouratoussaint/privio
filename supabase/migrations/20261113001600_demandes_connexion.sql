-- PRIVIO — lot 4.7 : demande de connexion avant le premier message (amendement 8, ADR-014).
--
-- On ne peut plus écrire directement à quelqu'un : on lui envoie une demande, avec un
-- petit mot facultatif. Il accepte (la discussion s'ouvre chez les deux ; le mot en est
-- le premier message et s'efface 5 min après), refuse (l'expéditeur est prévenu) ou
-- bloque. Demandes croisées : connexion immédiate. Les discussions existantes restent.
--
-- Règles (administrables) : expiration 24 h ; 5 min d'attente après un refus ; 3 demandes
-- au plus vers une même personne par jour ; mot de 140 caractères, effacé à la réponse
-- ou à l'expiration. Réglage personnel : accepter les demandes (tout le monde / personne).

-- ---------------------------------------------------------------------------
-- Politiques
-- ---------------------------------------------------------------------------
insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('connection_requests_required', 'boolean', 'true', null, null, null, true, true,
   'Premier contact par demande de connexion (sinon, écriture directe comme avant).'),
  ('connection_request_expiry_hours', 'integer', '24', 1, 168, null, true, true,
   'Une demande sans réponse expire après ce nombre d''heures.'),
  ('connection_request_retry_minutes', 'integer', '5', 1, 10080, null, true, true,
   'Attente avant de redemander après un refus.'),
  ('connection_request_daily_per_person', 'integer', '3', 1, 20, null, true, true,
   'Nombre de demandes au plus vers une même personne par jour.'),
  ('connection_note_max_chars', 'integer', '140', 1, 280, null, true, true,
   'Longueur maximale du petit mot joint à une demande.'),
  ('connection_note_ttl_minutes', 'integer', '5', 1, 60, null, true, true,
   'Après acceptation, durée de vie du petit mot devenu premier message.');

create or replace function private.policy_bool(p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (private.policy_value(p_key) #>> '{}')::boolean;
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table private.connection_settings (
  user_id         uuid        primary key references auth.users (id) on delete cascade,
  accept_requests boolean     not null default true,
  updated_at      timestamptz not null default now()
);

create table private.connection_requests (
  id              uuid        primary key default gen_random_uuid(),
  from_user       uuid        not null references auth.users (id) on delete cascade,
  to_user         uuid        not null references auth.users (id) on delete cascade,
  note            text        check (note is null or char_length(note) between 1 and 280),
  status          text        not null default 'pending'
                              check (status in ('pending', 'accepted', 'refused', 'cancelled', 'expired')),
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  answered_at     timestamptz,
  conversation_id uuid        references public.conversations (id) on delete set null,
  check (from_user <> to_user),
  -- Le mot ne survit pas à la réponse.
  check (status = 'pending' or note is null)
);
create unique index connection_requests_one_pending
  on private.connection_requests (from_user, to_user) where status = 'pending';
create index connection_requests_to_idx on private.connection_requests (to_user, status);
create index connection_requests_from_idx on private.connection_requests (from_user, created_at);

-- ---------------------------------------------------------------------------
-- Outils internes
-- ---------------------------------------------------------------------------
create or replace function private.direct_key(a uuid, b uuid)
returns text
language sql
immutable
set search_path = ''
as $$
  select least(a::text, b::text) || ':' || greatest(a::text, b::text);
$$;

create or replace function private.direct_conversation_between(a uuid, b uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id from public.conversations c where c.direct_key = private.direct_key(a, b);
$$;

-- Crée (ou retrouve) la discussion à deux ; durée par défaut de [p_creator].
create or replace function private.create_direct_conversation(p_creator uuid, p_other uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_key text := private.direct_key(p_creator, p_other);
  v_id  uuid;
begin
  insert into public.conversations (kind, direct_key, created_by, ttl_seconds)
  values ('direct', v_key, p_creator, private.default_ttl_for(p_creator))
  on conflict (direct_key) do nothing
  returning id into v_id;
  if v_id is null then
    select c.id into v_id from public.conversations c where c.direct_key = v_key;
    return v_id;
  end if;
  insert into public.conversation_members (conversation_id, user_id)
  values (v_id, p_creator), (v_id, p_other);
  return v_id;
end;
$$;

-- Demandes échues : expirées, mot effacé.
create or replace function private.expire_connection_requests()
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update private.connection_requests
     set status = 'expired', note = null, answered_at = expires_at
   where status = 'pending' and expires_at <= now();
$$;

-- Nettoyage planifié : expiration + oubli des demandes closes depuis 7 jours.
create or replace function private.purge_connection_requests()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.expire_connection_requests();
  delete from private.connection_requests
   where status <> 'pending' and coalesce(answered_at, created_at) < now() - interval '7 days';
end;
$$;

create or replace function private.accepts_requests(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select s.accept_requests from private.connection_settings s
                    where s.user_id = p_user), true);
$$;

-- Prévient une personne : temps réel (son app recharge) et notification sans contenu.
create or replace function private.notify_connection(p_user uuid, p_request_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_url   text := (select s.value from private.runtime_settings s where s.key = 'functions_url');
  v_token text := (select s.value from private.runtime_settings s where s.key = 'push_dispatch_token');
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is not null then
    execute 'select realtime.send($1, $2, $3, true)'
      using jsonb_build_object('request_id', p_request_id), 'request', 'user:' || p_user::text;
  end if;
  if v_url is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null
     or not exists (select 1 from private.push_tokens t where t.user_id = p_user) then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
    using v_url || '/push-dispatch', jsonb_build_object('request_id', p_request_id),
          jsonb_build_object('Content-Type', 'application/json', 'x-privio-push', v_token), 10000;
end;
$$;

-- Acceptation (aussi utilisée pour les demandes croisées) : discussion + premier message.
create or replace function private.accept_connection_request(p_request_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r      private.connection_requests%rowtype;
  v_conv uuid;
begin
  select * into r from private.connection_requests where id = p_request_id for update;
  v_conv := private.create_direct_conversation(r.from_user, r.to_user);
  if r.note is not null then
    -- Pas de notification « nouveau message » pour la personne qui vient d'accepter.
    perform set_config('privio.skip_push', 'on', true);
    perform private.post_message(r.from_user, v_conv, gen_random_uuid(), 'text', r.note, null,
                                 greatest(private.policy_int('connection_note_ttl_minutes'),
                                          private.policy_int('message_ttl_min_minutes')) * 60);
    perform set_config('privio.skip_push', 'off', true);
  end if;
  update private.connection_requests
     set status = 'accepted', note = null, answered_at = now(), conversation_id = v_conv
   where id = p_request_id;
  perform private.notify_connection(r.from_user, p_request_id);
  return v_conv;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : état de la relation avec une personne (bouton de la recherche)
--   connected (discussion existante) · outgoing (ma demande attend) · incoming (la sienne
--   attend) · refused (refus récent : retry_at) · none
-- ---------------------------------------------------------------------------
create or replace function public.connection_status(p_user_id uuid)
returns table (state text, conversation_id uuid, request_id uuid, retry_at timestamptz)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_conv uuid;
  r      private.connection_requests%rowtype;
begin
  if p_user_id is null or p_user_id = v_uid then
    raise exception 'SELF_CONVERSATION' using errcode = 'P0001';
  end if;
  perform private.expire_connection_requests();
  v_conv := private.direct_conversation_between(v_uid, p_user_id);
  if v_conv is not null or not private.policy_bool('connection_requests_required') then
    return query select 'connected'::text, v_conv, null::uuid, null::timestamptz;
    return;
  end if;
  select * into r from private.connection_requests c
   where c.from_user = v_uid and c.to_user = p_user_id and c.status = 'pending';
  if found then
    return query select 'outgoing'::text, null::uuid, r.id, null::timestamptz;
    return;
  end if;
  select * into r from private.connection_requests c
   where c.from_user = p_user_id and c.to_user = v_uid and c.status = 'pending';
  if found then
    return query select 'incoming'::text, null::uuid, r.id, null::timestamptz;
    return;
  end if;
  select * into r from private.connection_requests c
   where c.from_user = v_uid and c.to_user = p_user_id and c.status = 'refused'
   order by c.answered_at desc limit 1;
  if found and r.answered_at + make_interval(mins => private.policy_int('connection_request_retry_minutes')) > now() then
    return query select 'refused'::text, null::uuid, r.id,
      r.answered_at + make_interval(mins => private.policy_int('connection_request_retry_minutes'));
    return;
  end if;
  return query select 'none'::text, null::uuid, null::uuid, null::timestamptz;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : envoyer une demande → connected (discussion) | requested (demande)
-- ---------------------------------------------------------------------------
create or replace function public.send_connection_request(p_user_id uuid, p_note text default null)
returns table (state text, conversation_id uuid, request_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_conv uuid;
  v_id   uuid;
  r      private.connection_requests%rowtype;
  v_day  date := private.quota_day();
  v_tz   text := private.policy_value('quota_timezone') #>> '{}';
begin
  if p_user_id is null or p_user_id = v_uid then
    raise exception 'SELF_CONVERSATION' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user_id and p.deleted_at is null) then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_note is not null and char_length(v_note) > private.policy_int('connection_note_max_chars') then
    raise exception 'CONNECTION_NOTE_TOO_LONG' using errcode = 'P0001';
  end if;
  -- Une seule opération à la fois par paire : deux demandes croisées au même instant
  -- donnent une connexion, pas deux demandes en attente.
  perform pg_advisory_xact_lock(hashtext('connection:' || private.direct_key(v_uid, p_user_id)));
  perform private.expire_connection_requests();

  -- Déjà connectés (ou demandes désactivées) : on écrit directement.
  v_conv := private.direct_conversation_between(v_uid, p_user_id);
  if v_conv is not null then
    return query select 'connected'::text, v_conv, null::uuid;
    return;
  end if;
  -- Blocage (dans un sens ou l'autre) et refus de toute demande : même réponse, rien
  -- n'indique à l'expéditeur qu'il est bloqué.
  if private.is_blocked_between(v_uid, p_user_id) or not private.accepts_requests(p_user_id) then
    raise exception 'CONNECTION_NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if not private.policy_bool('connection_requests_required') then
    perform private.consume_rate_limit(v_uid, 'conversation_create',
      private.policy_int('conversation_create_hourly_limit'), interval '1 hour');
    return query select 'connected'::text, private.create_direct_conversation(v_uid, p_user_id), null::uuid;
    return;
  end if;

  -- Demande croisée : l'autre m'a déjà demandé → connexion immédiate.
  select * into r from private.connection_requests c
   where c.from_user = p_user_id and c.to_user = v_uid and c.status = 'pending' for update;
  if found then
    return query select 'connected'::text, private.accept_connection_request(r.id), null::uuid;
    return;
  end if;
  -- Ma demande attend déjà : rien de neuf (idempotent).
  select * into r from private.connection_requests c
   where c.from_user = v_uid and c.to_user = p_user_id and c.status = 'pending';
  if found then
    return query select 'requested'::text, null::uuid, r.id;
    return;
  end if;
  -- Refus récent : attendre.
  if exists (select 1 from private.connection_requests c
              where c.from_user = v_uid and c.to_user = p_user_id and c.status = 'refused'
                and c.answered_at + make_interval(mins => private.policy_int('connection_request_retry_minutes')) > now()) then
    raise exception 'CONNECTION_RETRY_LATER' using errcode = 'P0001';
  end if;
  -- Au plus N demandes vers cette personne par jour (fuseau des quotas).
  if (select count(*) from private.connection_requests c
       where c.from_user = v_uid and c.to_user = p_user_id
         and (c.created_at at time zone v_tz)::date = v_day)
     >= private.policy_int('connection_request_daily_per_person') then
    raise exception 'CONNECTION_DAILY_LIMIT' using errcode = 'P0001';
  end if;
  -- Garde-fou global contre les envois en masse.
  perform private.consume_rate_limit(v_uid, 'conversation_create',
    private.policy_int('conversation_create_hourly_limit'), interval '1 hour');

  insert into private.connection_requests (from_user, to_user, note, expires_at)
  values (v_uid, p_user_id, v_note,
          now() + make_interval(hours => private.policy_int('connection_request_expiry_hours')))
  returning id into v_id;
  perform private.notify_connection(p_user_id, v_id);
  return query select 'requested'::text, null::uuid, v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : répondre à une demande reçue (accept | refuse | block)
-- ---------------------------------------------------------------------------
create or replace function public.respond_connection_request(p_request_id uuid, p_action text)
returns table (state text, conversation_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  r     private.connection_requests%rowtype;
begin
  if p_action is null or p_action not in ('accept', 'refuse', 'block') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  select * into r from private.connection_requests c where c.id = p_request_id;
  if found then
    perform pg_advisory_xact_lock(hashtext('connection:' || private.direct_key(r.from_user, r.to_user)));
  end if;
  perform private.expire_connection_requests();
  select * into r from private.connection_requests c
   where c.id = p_request_id and c.to_user = v_uid and c.status = 'pending' for update;
  if not found then
    raise exception 'CONNECTION_REQUEST_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_action = 'accept' then
    if private.is_blocked_between(v_uid, r.from_user) then
      raise exception 'BLOCKED' using errcode = 'P0001';
    end if;
    return query select 'accepted'::text, private.accept_connection_request(r.id);
    return;
  end if;
  update private.connection_requests
     set status = 'refused', note = null, answered_at = now()
   where id = r.id;
  if p_action = 'block' then
    insert into public.blocks (blocker_id, blocked_id) values (v_uid, r.from_user)
    on conflict do nothing;
  else
    -- Refus simple : l'expéditeur est prévenu (décision du 13/11/2026). Bloqué : rien.
    perform private.notify_connection(r.from_user, r.id);
  end if;
  return query select case when p_action = 'block' then 'blocked' else 'refused' end, null::uuid;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : annuler sa propre demande
-- ---------------------------------------------------------------------------
create or replace function public.cancel_connection_request(p_request_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_to  uuid;
begin
  update private.connection_requests c
     set status = 'cancelled', note = null, answered_at = now()
   where c.id = p_request_id and c.from_user = v_uid and c.status = 'pending'
  returning c.to_user into v_to;
  if v_to is null then
    raise exception 'CONNECTION_REQUEST_NOT_FOUND' using errcode = 'P0001';
  end if;
  -- L'encart du destinataire se met à jour (aucune notification).
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is not null then
    execute 'select realtime.send($1, $2, $3, true)'
      using jsonb_build_object('request_id', p_request_id), 'request', 'user:' || v_to::text;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : mes demandes — reçues en attente ; envoyées en attente, refusées ou expirées
-- (7 jours). Jamais de numéro de téléphone ; la photo suit le réglage de son titulaire.
-- ---------------------------------------------------------------------------
create or replace function public.list_connection_requests()
returns table (
  id           uuid,
  direction    text,
  user_id      uuid,
  handle       text,
  display_name text,
  avatar_path  text,
  note         text,
  status       text,
  created_at   timestamptz,
  expires_at   timestamptz,
  answered_at  timestamptz,
  retry_at     timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_active_user();
  v_retry integer := private.policy_int('connection_request_retry_minutes');
begin
  perform private.expire_connection_requests();
  return query
  select c.id,
         case when c.to_user = v_uid then 'incoming' else 'outgoing' end,
         p.id, p.handle, p.display_name, private.avatar_for(p.id, v_uid, p.avatar_path),
         c.note, c.status, c.created_at, c.expires_at, c.answered_at,
         case when c.status = 'refused' then c.answered_at + make_interval(mins => v_retry) end
    from private.connection_requests c
    join public.profiles p
      on p.id = case when c.to_user = v_uid then c.from_user else c.to_user end
   where p.deleted_at is null
     and ((c.to_user = v_uid and c.status = 'pending'
           and not private.is_blocked_between(v_uid, c.from_user))
       or (c.from_user = v_uid and c.status in ('pending', 'refused', 'expired')))
   order by c.created_at desc
   limit 200;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : réglage « Qui peut m'envoyer une demande »
-- ---------------------------------------------------------------------------
create or replace function public.get_connection_settings()
returns table (accept_requests boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  return query select private.accepts_requests(v_uid);
end;
$$;

create or replace function public.set_connection_settings(p_accept_requests boolean)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  if p_accept_requests is null then
    raise exception 'PRIVACY_SETTING_INVALID' using errcode = 'P0001';
  end if;
  insert into private.connection_settings as s (user_id, accept_requests, updated_at)
  values (v_uid, p_accept_requests, now())
  on conflict (user_id) do update set accept_requests = excluded.accept_requests, updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Ouverture directe : seulement une discussion existante (ou demandes désactivées).
-- ---------------------------------------------------------------------------
create or replace function public.start_direct_conversation(p_other_user_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_id  uuid;
begin
  if p_other_user_id is null or p_other_user_id = v_uid then
    raise exception 'SELF_CONVERSATION' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_other_user_id and p.deleted_at is null) then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if private.is_blocked_between(v_uid, p_other_user_id) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;
  v_id := private.direct_conversation_between(v_uid, p_other_user_id);
  if v_id is not null then
    return v_id;
  end if;
  if private.policy_bool('connection_requests_required') then
    raise exception 'CONNECTION_REQUIRED' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(v_uid, 'conversation_create',
    private.policy_int('conversation_create_hourly_limit'), interval '1 hour');
  return private.create_direct_conversation(v_uid, p_other_user_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Notifications (push-dispatch) : destinataire d'un événement de demande, sans contenu.
--   pending → la personne sollicitée (« received ») ; accepted / refused → l'expéditeur.
-- ---------------------------------------------------------------------------
create or replace function public.push_request_targets(p_token text, p_request_id uuid)
returns table (token text, event text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  r      private.connection_requests%rowtype;
  v_to   uuid;
  v_kind text;
begin
  perform private.check_push_token(p_token);
  select * into r from private.connection_requests c where c.id = p_request_id;
  if not found then
    return;
  end if;
  if r.status = 'pending' and r.expires_at > now() then
    v_to := r.to_user; v_kind := 'received';
  elsif r.status in ('accepted', 'refused') and r.answered_at > now() - interval '1 hour' then
    v_to := r.from_user; v_kind := r.status;
  else
    return;
  end if;
  if private.is_blocked_between(r.from_user, r.to_user) then
    return;
  end if;
  return query
  select t.token, v_kind
    from private.push_tokens t
    join public.devices d on d.id = t.device_id and d.revoked_at is null
   where t.user_id = v_to;
end;
$$;

-- Nouveau message : notification, sauf le mot d'une demande tout juste acceptée.
create or replace function private.request_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url   text := (select s.value from private.runtime_settings s where s.key = 'functions_url');
  v_token text := (select s.value from private.runtime_settings s where s.key = 'push_dispatch_token');
begin
  if new.kind = 'system' or current_setting('privio.skip_push', true) = 'on' then
    return new;
  end if;
  -- Personne à prévenir : aucun appel.
  if not exists (
    select 1 from public.conversation_members m
      join private.push_tokens t on t.user_id = m.user_id
     where m.conversation_id = new.conversation_id and m.left_at is null
       and m.user_id is distinct from new.sender_id) then
    return new;
  end if;
  if v_url is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    return new;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
    using v_url || '/push-dispatch', jsonb_build_object('message_id', new.id),
          jsonb_build_object('Content-Type', 'application/json', 'x-privio-push', v_token), 10000;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Nettoyage planifié (toutes les 10 minutes)
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_purge_connection_requests';
    perform cron.schedule('privio_purge_connection_requests', '*/10 * * * *',
                          'select private.purge_connection_requests()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();

grant execute on function public.connection_status(uuid) to authenticated;
grant execute on function public.send_connection_request(uuid, text) to authenticated;
grant execute on function public.respond_connection_request(uuid, text) to authenticated;
grant execute on function public.cancel_connection_request(uuid) to authenticated;
grant execute on function public.list_connection_requests() to authenticated;
grant execute on function public.get_connection_settings() to authenticated;
grant execute on function public.set_connection_settings(boolean) to authenticated;
grant execute on function public.start_direct_conversation(uuid) to authenticated;
revoke all on function public.push_request_targets(text, uuid) from authenticated;
grant execute on function public.push_request_targets(text, uuid) to service_role;
