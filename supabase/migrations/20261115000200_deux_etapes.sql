-- PRIVIO — lot 8.4a : vérification en deux étapes (ADR-033, décisions du 15/11/2026).
--
-- Facultative. Un « code de vérification » à 6 chiffres, gardé haché (bcrypt). Une session
-- ouverte par SMS sur un compte protégé reste « en attente » tant que le code n'a pas été
-- saisi : session_is_active() la refuse partout (RLS, fonctions, Storage, temps réel).
-- Elle ne peut donc ni lire, ni écrire, ni enregistrer l'appareil : le téléphone déjà
-- connecté le reste jusqu'à la bonne saisie (register_device révoque alors l'ancien).
-- Code oublié : demande à l'assistance, qui réinitialise depuis la console.

create extension if not exists pgcrypto with schema extensions;

create table private.two_step (
  user_id             uuid        primary key references auth.users (id) on delete cascade,
  pin_hash            text        not null,
  enabled_at          timestamptz not null default now(),
  failures            integer     not null default 0,
  retry_at            timestamptz,
  -- Changement de numéro autorisé jusqu'à (code saisi juste avant).
  phone_change_until  timestamptz,
  reset_requested_at  timestamptz
);
revoke all on private.two_step from public, anon, authenticated;

-- Sessions qui ont saisi le code (ou qui l'ont activé).
create table private.two_step_sessions (
  session_id  uuid        primary key,
  user_id     uuid        not null references auth.users (id) on delete cascade,
  verified_at timestamptz not null default now()
);
create index two_step_sessions_user_idx on private.two_step_sessions (user_id);
revoke all on private.two_step_sessions from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Session : existe (jeton valide) / active (et vérifiée si le compte est protégé)
-- ---------------------------------------------------------------------------
create or replace function private.session_exists()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select exists (
      select 1 from auth.sessions s
       where s.id = nullif(auth.jwt() ->> 'session_id', '')::uuid and s.user_id = auth.uid())
  ), false);
$$;

create or replace function private.session_is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_exists()
     and (not exists (select 1 from private.two_step t where t.user_id = auth.uid())
          or exists (select 1 from private.two_step_sessions v
                      where v.session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid
                        and v.user_id = auth.uid()));
$$;

-- Utilisateur d'une session existante, même en attente du code.
create or replace function private.require_session_user()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not private.session_exists() then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  return v_uid;
end;
$$;

create or replace function private.valid_two_step_pin(p_pin text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_pin ~ '^[0-9]{6}$'
     and p_pin !~ '^(.)\1{5}$'
     and position(p_pin in '0123456789012345') = 0
     and position(p_pin in '9876543210987654') = 0;
$$;

-- Vérifie un code (compteur d'essais : 5 erreurs, puis attente qui double, 24 h au plus).
-- Renvoie {ok, retry_at, failures}. Le compte doit avoir la vérification activée.
create or replace function private.check_two_step(p_uid uuid, p_pin text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  t private.two_step%rowtype;
begin
  select * into t from private.two_step where user_id = p_uid for update;
  if not found then
    raise exception 'TWO_STEP_NOT_ENABLED' using errcode = 'P0001';
  end if;
  if t.retry_at is not null and t.retry_at > now() then
    return jsonb_build_object('ok', false, 'retry_at', t.retry_at, 'failures', t.failures);
  end if;
  if p_pin is not null and p_pin ~ '^[0-9]{6}$'
     and extensions.crypt(p_pin, t.pin_hash) = t.pin_hash then
    update private.two_step set failures = 0, retry_at = null where user_id = p_uid;
    return jsonb_build_object('ok', true, 'retry_at', null, 'failures', 0);
  end if;
  t.failures := t.failures + 1;
  t.retry_at := case when t.failures >= 5
                     then now() + least(interval '24 hours',
                                        interval '1 minute' * power(2, t.failures - 5))
                end;
  update private.two_step set failures = t.failures, retry_at = t.retry_at where user_id = p_uid;
  return jsonb_build_object('ok', false, 'retry_at', t.retry_at, 'failures', t.failures);
end;
$$;

-- ---------------------------------------------------------------------------
-- Fonctions de l'application
-- ---------------------------------------------------------------------------
create or replace function public.two_step_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_session_user();
  t     private.two_step%rowtype;
begin
  select * into t from private.two_step where user_id = v_uid;
  return jsonb_build_object(
    'enabled', found,
    'verified', not found or exists (
      select 1 from private.two_step_sessions v
       where v.session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid and v.user_id = v_uid),
    'retry_at', t.retry_at,
    'reset_requested_at', t.reset_requested_at);
end;
$$;

create or replace function public.enable_two_step(p_pin text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  if not private.valid_two_step_pin(p_pin) then
    raise exception 'TWO_STEP_PIN_WEAK' using errcode = 'P0001';
  end if;
  insert into private.two_step (user_id, pin_hash)
  values (v_uid, extensions.crypt(p_pin, extensions.gen_salt('bf', 8)))
  on conflict (user_id) do nothing;
  if not found then
    raise exception 'TWO_STEP_ALREADY_ENABLED' using errcode = 'P0001';
  end if;
  -- Ce téléphone est déjà vérifié ; toute autre session ne l'est pas.
  delete from private.two_step_sessions where user_id = v_uid;
  insert into private.two_step_sessions (session_id, user_id)
  values (nullif(auth.jwt() ->> 'session_id', '')::uuid, v_uid);
end;
$$;

-- Saisie du code par un téléphone en attente (après le SMS).
create or replace function public.verify_two_step(p_pin text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_session_user();
  v_res jsonb;
begin
  if not exists (select 1 from private.two_step where user_id = v_uid) then
    return jsonb_build_object('ok', true, 'retry_at', null, 'failures', 0);
  end if;
  v_res := private.check_two_step(v_uid, p_pin);
  if (v_res ->> 'ok')::boolean then
    insert into private.two_step_sessions (session_id, user_id)
    values (nullif(auth.jwt() ->> 'session_id', '')::uuid, v_uid)
    on conflict (session_id) do nothing;
    update private.two_step set reset_requested_at = null where user_id = v_uid;
  end if;
  return v_res;
end;
$$;

create or replace function public.change_two_step(p_current text, p_new text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_res jsonb;
begin
  if not private.valid_two_step_pin(p_new) then
    raise exception 'TWO_STEP_PIN_WEAK' using errcode = 'P0001';
  end if;
  v_res := private.check_two_step(v_uid, p_current);
  if (v_res ->> 'ok')::boolean then
    update private.two_step
       set pin_hash = extensions.crypt(p_new, extensions.gen_salt('bf', 8))
     where user_id = v_uid;
  end if;
  return v_res;
end;
$$;

create or replace function public.disable_two_step(p_pin text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_res jsonb := private.check_two_step(v_uid, p_pin);
begin
  if (v_res ->> 'ok')::boolean then
    delete from private.two_step where user_id = v_uid;
    delete from private.two_step_sessions where user_id = v_uid;
  end if;
  return v_res;
end;
$$;

-- Changement de numéro : le code est demandé juste avant (15 minutes pour finir).
create or replace function public.authorize_phone_change(p_pin text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_res jsonb;
begin
  if not exists (select 1 from private.two_step where user_id = v_uid) then
    return jsonb_build_object('ok', true, 'retry_at', null, 'failures', 0);
  end if;
  v_res := private.check_two_step(v_uid, p_pin);
  if (v_res ->> 'ok')::boolean then
    update private.two_step set phone_change_until = now() + interval '15 minutes'
     where user_id = v_uid;
  end if;
  return v_res;
end;
$$;

-- Garde serveur : sans code saisi, le numéro d'un compte protégé ne change pas.
create or replace function private.guard_phone_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.phone is not null and new.phone is not null and old.phone is distinct from new.phone
     and exists (select 1 from private.two_step t where t.user_id = old.id) then
    if not exists (select 1 from private.two_step t
                    where t.user_id = old.id and t.phone_change_until > now()) then
      raise exception 'TWO_STEP_REQUIRED' using errcode = 'P0001';
    end if;
    update private.two_step set phone_change_until = null where user_id = old.id;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_phone_guard
  before update of phone on auth.users
  for each row execute function private.guard_phone_change();

-- Code oublié : demande d'assistance (une par 24 h), depuis le téléphone en attente.
create or replace function public.request_two_step_reset()
returns timestamptz
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_session_user();
  t     private.two_step%rowtype;
begin
  select * into t from private.two_step where user_id = v_uid for update;
  if not found then
    raise exception 'TWO_STEP_NOT_ENABLED' using errcode = 'P0001';
  end if;
  if t.reset_requested_at is not null and t.reset_requested_at > now() - interval '24 hours' then
    return t.reset_requested_at;
  end if;
  insert into private.reports (reporter_id, reason, details, purge_after)
  values (v_uid, 'support',
          'Code de vérification oublié : demande de réinitialisation de la vérification en deux étapes.',
          now() + make_interval(days => private.policy_int('report_retention_days')));
  update private.two_step set reset_requested_at = now() where user_id = v_uid;
  return now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Console : état et réinitialisation (identité vérifiée par l'assistance, motif obligatoire)
-- ---------------------------------------------------------------------------
create or replace function public.console_two_step(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console_admin();
  t     private.two_step%rowtype;
begin
  select * into t from private.two_step where user_id = p_user_id;
  return jsonb_build_object(
    'enabled', found,
    'enabled_at', t.enabled_at,
    'reset_requested_at', t.reset_requested_at);
end;
$$;

create or replace function public.console_reset_two_step(p_user_id uuid, p_note text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_console_admin();
  v_note text := btrim(coalesce(p_note, ''));
begin
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  if private.is_console_admin(p_user_id) and p_user_id <> v_uid then
    raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
  end if;
  delete from private.two_step where user_id = p_user_id;
  if not found then
    raise exception 'TWO_STEP_NOT_ENABLED' using errcode = 'P0001';
  end if;
  delete from private.two_step_sessions where user_id = p_user_id;
  perform private.admin_log(v_uid, 'two_step_reset', jsonb_build_object(
    'handle', (select p.handle from public.profiles p where p.id = p_user_id), 'note', v_note));
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.two_step_state() to authenticated;
grant execute on function public.enable_two_step(text) to authenticated;
grant execute on function public.verify_two_step(text) to authenticated;
grant execute on function public.change_two_step(text, text) to authenticated;
grant execute on function public.disable_two_step(text) to authenticated;
grant execute on function public.authorize_phone_change(text) to authenticated;
grant execute on function public.request_two_step_reset() to authenticated;
grant execute on function public.console_two_step(uuid) to authenticated;
grant execute on function public.console_reset_two_step(uuid, text) to authenticated;
