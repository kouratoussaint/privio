-- PRIVIO — Migration 3 : identité, profil et recherche
-- Authentification par téléphone uniquement. Le numéro vérifié vit dans un schéma privé,
-- jamais dans une table exposée. Recherche exacte uniquement (pas de préfixe), limitée.

-- ---------------------------------------------------------------------------
-- Coordonnées privées, synchronisées depuis auth.users après vérification OTP.
-- ---------------------------------------------------------------------------
create table private.user_contacts (
  user_id            uuid        primary key references auth.users (id) on delete cascade,
  phone_e164         text        not null unique check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  phone_verified_at  timestamptz not null,
  phone_discoverable boolean     not null default false,
  updated_at         timestamptz not null default now()
);

create or replace function private.sync_user_contact()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := private.normalize_phone_e164('+' || ltrim(coalesce(new.phone, ''), '+'));
begin
  if v_phone is null or new.phone_confirmed_at is null then
    if tg_op = 'UPDATE' and new.phone is distinct from old.phone and coalesce(new.phone, '') = '' then
      delete from private.user_contacts where user_id = new.id;
    end if;
    -- Ne jamais faire échouer Auth : un format inattendu laisse simplement le compte
    -- sans numéro vérifié côté Privio (create_profile refusera alors PHONE_NOT_VERIFIED).
    return new;
  end if;

  insert into private.user_contacts (user_id, phone_e164, phone_verified_at)
  values (new.id, v_phone, new.phone_confirmed_at)
  on conflict (user_id) do update
    set phone_e164        = excluded.phone_e164,
        phone_verified_at = excluded.phone_verified_at,
        updated_at        = now();
  return new;
end;
$$;
revoke all on function private.sync_user_contact() from public;

create trigger on_auth_user_phone_sync
  after insert or update of phone, phone_confirmed_at on auth.users
  for each row execute function private.sync_user_contact();

-- ---------------------------------------------------------------------------
-- Profils publics (champs minimaux).
-- ---------------------------------------------------------------------------
create table public.profiles (
  id           uuid        primary key references auth.users (id) on delete cascade,
  handle       text        not null unique
               check (handle ~ '^[a-z0-9][a-z0-9_.]{1,22}[a-z0-9]$' and position('..' in handle) = 0),
  -- (règle complète, mots réservés inclus : private.handle_is_valid, appliquée par create_profile ;
  --  une contrainte CHECK appelant une fonction exigerait un droit d'exécution côté client)
  display_name text        not null check (char_length(btrim(display_name)) between 1 and 40),
  about        text        check (about is null or char_length(about) <= 140),
  avatar_path  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

alter table public.profiles enable row level security;
revoke all on public.profiles from public, anon, authenticated;
grant select (id, handle, display_name, about, avatar_path, created_at) on public.profiles to authenticated;
grant update (display_name, about) on public.profiles to authenticated;

-- Étape 1 : chacun ne lit que son propre profil. Les autres profils ne sont accessibles
-- qu'au travers des RPC de recherche (réponses minimales), puis, à l'étape 2, entre
-- membres d'une même conversation.
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) and (select private.session_is_active()));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()) and (select private.session_is_active()))
  with check (id = (select auth.uid()));

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Blocages (utilisés dès maintenant par la recherche ; écran de gestion à l'étape 2).
-- ---------------------------------------------------------------------------
create table public.blocks (
  blocker_id uuid        not null references auth.users (id) on delete cascade,
  blocked_id uuid        not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.blocks enable row level security;
revoke all on public.blocks from public, anon, authenticated;
grant select, insert, delete on public.blocks to authenticated;

create policy blocks_own on public.blocks
  for all to authenticated
  using (blocker_id = (select auth.uid()) and (select private.session_is_active()))
  with check (blocker_id = (select auth.uid()) and (select private.session_is_active()));

create or replace function private.is_blocked_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks
     where (blocker_id = a and blocked_id = b)
        or (blocker_id = b and blocked_id = a)
  );
$$;
revoke all on function private.is_blocked_between(uuid, uuid) from public;

-- ---------------------------------------------------------------------------
-- RPC : création de profil (écran 06), identifiant unique attribué atomiquement.
-- ---------------------------------------------------------------------------
create or replace function public.create_profile(p_handle text, p_display_name text)
returns table (id uuid, handle text, display_name text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_active_user();
  v_handle text := private.normalize_handle(p_handle);
  v_name   text := btrim(coalesce(p_display_name, ''));
begin
  perform private.consume_rate_limit(v_uid, 'profile_write',
    (private.policy_value('profile_write_hourly_limit') #>> '{}')::integer, interval '1 hour');

  if not exists (select 1 from private.user_contacts c where c.user_id = v_uid) then
    raise exception 'PHONE_NOT_VERIFIED' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'PROFILE_EXISTS' using errcode = 'P0001';
  end if;
  if not private.handle_is_valid(v_handle) then
    raise exception 'HANDLE_INVALID' using errcode = 'P0001';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'DISPLAY_NAME_INVALID' using errcode = 'P0001';
  end if;

  begin
    insert into public.profiles (id, handle, display_name)
    values (v_uid, v_handle, v_name);
  exception when unique_violation then
    raise exception 'HANDLE_TAKEN' using errcode = 'P0001';
  end;

  return query select v_uid, v_handle, v_name;
end;
$$;
revoke all on function public.create_profile(text, text) from public, anon;
grant execute on function public.create_profile(text, text) to authenticated;

-- Disponibilité d'un identifiant (saisie en direct, limitée).
create or replace function public.is_handle_available(p_handle text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_active_user();
  v_handle text := private.normalize_handle(p_handle);
begin
  perform private.consume_rate_limit(v_uid, 'handle_check',
    (private.policy_value('handle_check_hourly_limit') #>> '{}')::integer, interval '1 hour');
  if not private.handle_is_valid(v_handle) then
    return false;
  end if;
  return not exists (select 1 from public.profiles p where p.handle = v_handle);
end;
$$;
revoke all on function public.is_handle_available(text) from public, anon;
grant execute on function public.is_handle_available(text) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC : recherche. Correspondance exacte, blocages respectés, comptes supprimés exclus,
-- aucune coordonnée privée renvoyée, réponse vide identique dans tous les cas d'échec.
-- ---------------------------------------------------------------------------
create or replace function public.find_user_by_handle(p_handle text)
returns table (id uuid, handle text, display_name text, avatar_path text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  perform private.consume_rate_limit(v_uid, 'search_handle',
    (private.policy_value('search_handle_hourly_limit') #>> '{}')::integer, interval '1 hour');

  return query
    select p.id, p.handle, p.display_name, p.avatar_path
      from public.profiles p
     where p.handle = private.normalize_handle(p_handle)
       and p.deleted_at is null
       and p.id <> v_uid
       and not private.is_blocked_between(v_uid, p.id);
end;
$$;
revoke all on function public.find_user_by_handle(text) from public, anon;
grant execute on function public.find_user_by_handle(text) to authenticated;

create or replace function public.find_user_by_phone(p_phone text)
returns table (id uuid, handle text, display_name text, avatar_path text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  perform private.consume_rate_limit(v_uid, 'search_phone',
    (private.policy_value('search_phone_hourly_limit') #>> '{}')::integer, interval '1 hour');

  return query
    select p.id, p.handle, p.display_name, p.avatar_path
      from private.user_contacts c
      join public.profiles p on p.id = c.user_id
     where c.phone_e164 = private.normalize_phone_e164(p_phone)
       and c.phone_discoverable
       and p.deleted_at is null
       and p.id <> v_uid
       and not private.is_blocked_between(v_uid, p.id);
end;
$$;
revoke all on function public.find_user_by_phone(text) from public, anon;
grant execute on function public.find_user_by_phone(text) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC : compte courant et découvrabilité par numéro (désactivée par défaut).
-- ---------------------------------------------------------------------------
create or replace function public.get_my_account()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_result jsonb;
begin
  select jsonb_build_object(
           'user_id', v_uid,
           'phone_e164', c.phone_e164,
           'phone_discoverable', coalesce(c.phone_discoverable, false),
           'profile', case when p.id is null then null else jsonb_build_object(
               'handle', p.handle, 'display_name', p.display_name,
               'about', p.about, 'avatar_path', p.avatar_path) end)
    into v_result
    from (select v_uid as uid) u
    left join private.user_contacts c on c.user_id = u.uid
    left join public.profiles p on p.id = u.uid and p.deleted_at is null;
  return v_result;
end;
$$;
revoke all on function public.get_my_account() from public, anon;
grant execute on function public.get_my_account() to authenticated;

create or replace function public.set_phone_discoverable(p_discoverable boolean)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  update private.user_contacts
     set phone_discoverable = coalesce(p_discoverable, false), updated_at = now()
   where user_id = v_uid;
  if not found then
    raise exception 'PHONE_NOT_VERIFIED' using errcode = 'P0001';
  end if;
  return coalesce(p_discoverable, false);
end;
$$;
revoke all on function public.set_phone_discoverable(boolean) from public, anon;
grant execute on function public.set_phone_discoverable(boolean) to authenticated;

revoke all on all tables in schema private from public, anon, authenticated;

select private.harden_privileges();
