-- PRIVIO — Migration 4 : un seul appareil actif par compte (décision A4)
-- Enregistrer un appareil révoque les autres appareils ET supprime leurs sessions Auth
-- (leurs jetons de rafraîchissement deviennent inutilisables, et session_is_active()
-- leur ferme immédiatement l'accès aux données).

create table public.devices (
  id             uuid        primary key default gen_random_uuid(),
  user_id        uuid        not null references auth.users (id) on delete cascade,
  session_id     uuid        not null,
  platform       text        not null check (platform in ('android')),
  app_version    text        not null check (char_length(app_version) between 1 and 32),
  created_at     timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  revoked_at     timestamptz,
  revoked_reason text        check (revoked_reason in ('new_device', 'logout', 'admin', 'account_deleted')),
  check ((revoked_at is null) = (revoked_reason is null))
);

create unique index devices_one_active_per_user on public.devices (user_id) where revoked_at is null;
create index devices_user_idx on public.devices (user_id);

alter table public.devices enable row level security;
revoke all on public.devices from public, anon, authenticated;
grant select (id, platform, app_version, created_at, last_seen_at, revoked_at, revoked_reason)
  on public.devices to authenticated;

create policy devices_select_own on public.devices
  for select to authenticated
  using (user_id = (select auth.uid()) and (select private.session_is_active()));

create or replace function public.register_device(p_platform text, p_app_version text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := private.require_active_user();
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_device_id  uuid;
begin
  -- Sérialise les enregistrements concurrents d'un même compte.
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));

  select d.id into v_device_id
    from public.devices d
   where d.user_id = v_uid and d.session_id = v_session_id and d.revoked_at is null;

  update public.devices
     set revoked_at = now(), revoked_reason = 'new_device'
   where user_id = v_uid and revoked_at is null and session_id <> v_session_id;

  delete from auth.sessions
   where user_id = v_uid and id <> v_session_id;

  if v_device_id is not null then
    update public.devices
       set last_seen_at = now(), app_version = p_app_version
     where id = v_device_id;
    return v_device_id;
  end if;

  insert into public.devices (user_id, session_id, platform, app_version)
  values (v_uid, v_session_id, p_platform, p_app_version)
  returning id into v_device_id;
  return v_device_id;
end;
$$;
revoke all on function public.register_device(text, text) from public, anon;
grant execute on function public.register_device(text, text) to authenticated;

-- Déconnexion volontaire : l'appareil courant est marqué révoqué avant signOut().
create or replace function public.unregister_current_device()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  update public.devices
     set revoked_at = now(), revoked_reason = 'logout'
   where user_id = v_uid
     and session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid
     and revoked_at is null;
end;
$$;
revoke all on function public.unregister_current_device() from public, anon;
grant execute on function public.unregister_current_device() to authenticated;

select private.harden_privileges();
