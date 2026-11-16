-- Lot 5.6 : comptes dans la console.
--   * numéro de téléphone et photo de profil visibles dans la console seulement
--     (liste, recherche et fiche ; jamais ailleurs dans l'application) ;
--   * recherche par numéro, même partiel (4 chiffres au moins) ;
--   * filtres de la liste : suspendus, supprimés, nouveaux (7 j), inactifs (30 j), deux étapes ;
--   * fiche enrichie : appareils (modèle, version d'Android, version de l'app, dernière
--     connexion), historique des actions de l'administration ;
--   * nouvelles actions : retirer la photo, imposer un nouvel identifiant, déconnecter
--     un appareil précis ;
--   * identifiants réservés gérés dans la console (en plus des mots toujours réservés).

-- ---------------------------------------------------------------------------
-- 1. Appareils : modèle et version d'Android
-- ---------------------------------------------------------------------------
alter table public.devices
  add column if not exists model      text check (model is null or char_length(model) <= 64),
  add column if not exists os_version text check (os_version is null or char_length(os_version) <= 32);

drop function if exists public.register_device(text, text);

create or replace function public.register_device(
  p_platform text, p_app_version text, p_model text default null, p_os_version text default null
)
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
  v_model      text := nullif(left(btrim(coalesce(p_model, '')), 64), '');
  v_os         text := nullif(left(btrim(coalesce(p_os_version, '')), 32), '');
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
       set last_seen_at = now(), app_version = p_app_version,
           model = coalesce(v_model, model), os_version = coalesce(v_os, os_version)
     where id = v_device_id;
    return v_device_id;
  end if;

  insert into public.devices (user_id, session_id, platform, app_version, model, os_version)
  values (v_uid, v_session_id, p_platform, p_app_version, v_model, v_os)
  returning id into v_device_id;
  return v_device_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Identifiants réservés (en plus des mots toujours réservés de handle_is_valid)
-- ---------------------------------------------------------------------------
create table if not exists private.reserved_handles (
  handle     text        primary key
             check (handle ~ '^[a-z0-9][a-z0-9_.]{1,22}[a-z0-9]$' and position('..' in handle) = 0),
  created_by uuid        references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create or replace function private.handle_is_reserved(p_handle text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.reserved_handles r where r.handle = p_handle);
$$;

-- Mots toujours réservés (affichés verrouillés dans la console).
create or replace function private.base_reserved_handles()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['privio','admin','administrateur','administrator','support','aide','help',
               'moderation','moderateur','moderator','securite','security','systeme','system',
               'root','officiel','official','staff','equipe','team','null','undefined','contact'];
$$;

-- Création de profil : refuse aussi les identifiants réservés depuis la console
-- (même message que « déjà pris » : la liste n'est pas révélée).
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
  if private.handle_is_reserved(v_handle) then
    raise exception 'HANDLE_TAKEN' using errcode = 'P0001';
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
  if not private.handle_is_valid(v_handle) or private.handle_is_reserved(v_handle) then
    return false;
  end if;
  return not exists (select 1 from public.profiles p where p.handle = v_handle);
end;
$$;

create or replace function public.console_reserved_handles()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_console_admin();
  return jsonb_build_object(
    'base', to_jsonb(private.base_reserved_handles()),
    'added', (select coalesce(jsonb_agg(jsonb_build_object(
                  'handle', r.handle, 'created_at', r.created_at,
                  'in_use', exists (select 1 from public.profiles p where p.handle = r.handle))
                order by r.handle), '[]'::jsonb)
                from private.reserved_handles r));
end;
$$;

create or replace function public.console_reserve_handle(p_handle text, p_reserved boolean)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_console_admin();
  v_handle text := private.normalize_handle(p_handle);
begin
  if v_handle is null or v_handle !~ '^[a-z0-9][a-z0-9_.]{1,22}[a-z0-9]$'
     or position('..' in v_handle) > 0 then
    raise exception 'HANDLE_INVALID' using errcode = 'P0001';
  end if;
  if v_handle = any (private.base_reserved_handles()) then
    raise exception 'HANDLE_ALWAYS_RESERVED' using errcode = 'P0001';
  end if;
  if coalesce(p_reserved, true) then
    insert into private.reserved_handles (handle, created_by) values (v_handle, v_uid)
    on conflict (handle) do nothing;
  else
    delete from private.reserved_handles where handle = v_handle;
  end if;
  perform private.admin_log(v_uid, 'reserved_handle', jsonb_build_object(
    'handle', v_handle, 'reserved', coalesce(p_reserved, true)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Identifiant imposé par l'administration
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists handle_reset_at timestamptz;

create or replace function public.console_reset_handle(p_user_id uuid, p_note text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_console_admin();
  v_note text := btrim(coalesce(p_note, ''));
  v_old  text;
  v_new  text;
  v_hex  text := replace(p_user_id::text, '-', '');
  v_len  integer := 8;
begin
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  select p.handle into v_old from public.profiles p where p.id = p_user_id and p.deleted_at is null;
  if not found then
    raise exception 'ACCOUNT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if private.is_console_admin(p_user_id) then
    raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
  end if;
  -- Identifiant neutre provisoire : l'ancien disparaît aussitôt de la recherche.
  loop
    v_new := 'compte_' || left(v_hex, v_len);
    exit when not exists (select 1 from public.profiles p where p.handle = v_new);
    v_len := v_len + 2;
  end loop;
  update public.profiles set handle = v_new, handle_reset_at = now(), updated_at = now()
   where id = p_user_id;
  perform private.signal_user(p_user_id, null, 'moderation');
  perform private.admin_log(v_uid, 'handle_reset', jsonb_build_object(
    'user_id', p_user_id, 'handle', v_new, 'old_handle', v_old));
  return v_new;
end;
$$;

-- Côté personne concernée : choisir son nouvel identifiant (seulement quand il est imposé).
create or replace function public.choose_new_handle(p_handle text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_active_user();
  v_handle text := private.normalize_handle(p_handle);
begin
  perform private.consume_rate_limit(v_uid, 'profile_write',
    (private.policy_value('profile_write_hourly_limit') #>> '{}')::integer, interval '1 hour');
  if not exists (select 1 from public.profiles p
                  where p.id = v_uid and p.handle_reset_at is not null and p.deleted_at is null) then
    raise exception 'HANDLE_CHANGE_NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if not private.handle_is_valid(v_handle) then
    raise exception 'HANDLE_INVALID' using errcode = 'P0001';
  end if;
  if private.handle_is_reserved(v_handle) then
    raise exception 'HANDLE_TAKEN' using errcode = 'P0001';
  end if;
  begin
    update public.profiles set handle = v_handle, handle_reset_at = null, updated_at = now()
     where id = v_uid;
  exception when unique_violation then
    raise exception 'HANDLE_TAKEN' using errcode = 'P0001';
  end;
  return v_handle;
end;
$$;

create or replace function public.my_moderation_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  s     private.sanctions%rowtype := private.active_suspension(v_uid);
  w     private.sanctions%rowtype;
begin
  select * into w from private.sanctions x
   where x.user_id = v_uid and x.kind = 'warning' and x.acknowledged_at is null
   order by x.created_at limit 1;
  return jsonb_build_object(
    'suspension', case when s.id is null then null else jsonb_build_object(
      'id', s.id, 'until', s.until, 'reason', s.user_reason, 'created_at', s.created_at,
      'appealed', s.appeal_at is not null, 'appeal_decision', s.appeal_decision) end,
    'warning', case when w.id is null then null else jsonb_build_object(
      'id', w.id, 'reason', w.user_reason, 'created_at', w.created_at) end,
    -- Lot 5.6 : identifiant imposé par l'équipe Privio, à remplacer.
    'handle_reset', exists (select 1 from public.profiles p
                             where p.id = v_uid and p.handle_reset_at is not null
                               and p.deleted_at is null));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Photo retirée par l'administration
-- ---------------------------------------------------------------------------
create or replace function public.console_remove_avatar(p_user_id uuid, p_note text)
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
  if private.is_console_admin(p_user_id) then
    raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
  end if;
  update public.profiles set avatar_path = null, updated_at = now()
   where id = p_user_id and deleted_at is null and avatar_path is not null;
  if not found then
    raise exception 'AVATAR_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'avatar_remove', jsonb_build_object(
    'user_id', p_user_id, 'handle', (select p.handle from public.profiles p where p.id = p_user_id)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Déconnexion : tout le compte, ou un appareil précis
-- ---------------------------------------------------------------------------
drop function if exists public.console_disconnect_device(uuid, text);

create or replace function public.console_disconnect_device(
  p_user_id uuid, p_note text, p_device_id uuid default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_console_admin();
  v_note text := btrim(coalesce(p_note, ''));
  v_n    integer;
begin
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  if private.is_console_admin(p_user_id) then
    raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
  end if;
  if p_device_id is not null and not exists (
       select 1 from public.devices d
        where d.id = p_device_id and d.user_id = p_user_id and d.revoked_at is null) then
    raise exception 'DEVICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  -- Prévenir l'application ouverte avant de couper (message dédié à l'écran de connexion).
  perform private.signal_user(p_user_id, null, 'disconnected');
  update public.devices set revoked_at = now(), revoked_reason = 'admin'
   where user_id = p_user_id and revoked_at is null
     and (p_device_id is null or id = p_device_id);
  get diagnostics v_n = row_count;
  delete from auth.sessions where user_id = p_user_id;
  perform private.admin_log(v_uid, 'disconnect', jsonb_build_object(
    'user_id', p_user_id, 'devices', v_n,
    'handle', (select p.handle from public.profiles p where p.id = p_user_id)));
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Liste, recherche et fiche
-- ---------------------------------------------------------------------------
create or replace function private.last_seen(p_uid uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select max(x.seen) from (
    select pr.last_seen_at as seen from private.presence pr where pr.user_id = p_uid
    union all
    select dv.last_seen_at from public.devices dv where dv.user_id = p_uid) x;
$$;

create or replace function private.account_matches(p_filter text, p public.profiles)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case coalesce(p_filter, 'all')
    when 'all'       then true
    when 'suspended' then p.deleted_at is null and private.is_suspended(p.id)
    when 'deleted'   then p.deleted_at is not null
    when 'new'       then p.created_at > now() - interval '7 days'
    when 'inactive'  then p.deleted_at is null
                          and coalesce(private.last_seen(p.id), p.created_at) < now() - interval '30 days'
    when 'two_step'  then exists (select 1 from private.two_step t where t.user_id = p.id)
    else false
  end;
$$;

create or replace function private.account_row(p public.profiles)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'user_id', p.id, 'handle', p.handle, 'display_name', p.display_name,
    'avatar_path', case when p.deleted_at is null then p.avatar_path end,
    'phone_e164', (select c.phone_e164 from private.user_contacts c where c.user_id = p.id),
    'created_at', p.created_at, 'deleted', p.deleted_at is not null,
    'suspended', private.is_suspended(p.id));
$$;

drop function if exists public.console_accounts_page(integer, integer);

create or replace function public.console_accounts_page(
  p_page integer default 1, p_size integer default 25, p_filter text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := private.require_console_admin();
  v_size    integer := least(greatest(coalesce(p_size, 25), 5), 100);
  v_page    integer := greatest(coalesce(p_page, 1), 1);
  v_filter  text := coalesce(p_filter, 'all');
  v_total   integer;
  v_rows    jsonb;
  v_letters jsonb;
  v_counts  jsonb;
begin
  if v_filter not in ('all', 'suspended', 'deleted', 'new', 'inactive', 'two_step') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'account_list',
    jsonb_build_object('page', v_page, 'filter', v_filter));
  with ordered as (
    select p.id,
           row_number() over (order by private.name_sort_key(p.display_name), p.handle) - 1 as pos,
           left(private.name_sort_key(p.display_name), 1) as initial
      from public.profiles p
     where private.account_matches(v_filter, p)
  )
  select
    (select count(*) from ordered),
    (select coalesce(jsonb_agg(private.account_row(p) order by o.pos), '[]'::jsonb)
       from ordered o join public.profiles p on p.id = o.id
      where o.pos >= (v_page - 1) * v_size and o.pos < v_page * v_size),
    (select coalesce(jsonb_object_agg(l.letter, l.first_pos), '{}'::jsonb)
       from (select case when o.initial ~ '^[A-Z]$' then o.initial else '#' end as letter,
                    min(o.pos) as first_pos
               from ordered o group by 1) l)
    into v_total, v_rows, v_letters;
  -- Nombre de comptes par filtre (pastilles).
  select jsonb_build_object(
           'all', count(*),
           'suspended', count(*) filter (where private.account_matches('suspended', p)),
           'deleted', count(*) filter (where p.deleted_at is not null),
           'new', count(*) filter (where p.created_at > now() - interval '7 days'),
           'inactive', count(*) filter (where private.account_matches('inactive', p)),
           'two_step', count(*) filter (where private.account_matches('two_step', p)))
    into v_counts
    from public.profiles p;
  return jsonb_build_object('total', v_total, 'page', v_page, 'size', v_size, 'filter', v_filter,
                            'rows', v_rows, 'letters', v_letters, 'counts', v_counts);
end;
$$;

drop function if exists public.console_search_accounts(text);

-- Recherche : @identifiant, nom, ou numéro (4 chiffres au moins, n'importe où dans le numéro).
create or replace function public.console_search_accounts(p_query text)
returns table (
  user_id      uuid,
  handle       text,
  display_name text,
  avatar_path  text,
  phone_e164   text,
  created_at   timestamptz,
  deleted      boolean,
  suspended    boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid    uuid := private.require_console_admin();
  v_q      text := btrim(coalesce(p_query, ''));
  v_digits text := regexp_replace(v_q, '[^0-9]', '', 'g');
begin
  if v_q ~ '^[+0-9 .-]+$' then
    perform private.admin_log(v_uid, 'account_search', jsonb_build_object('by', 'phone'));
    if char_length(v_digits) < 4 then
      raise exception 'SEARCH_PHONE_INCOMPLETE' using errcode = 'P0001';
    end if;
    return query
    select p.id, p.handle, p.display_name,
           case when p.deleted_at is null then p.avatar_path end, c.phone_e164,
           p.created_at, p.deleted_at is not null, private.is_suspended(p.id)
      from private.user_contacts c
      join public.profiles p on p.id = c.user_id
     where c.phone_e164 like '%' || v_digits || '%'
     order by private.name_sort_key(p.display_name), p.handle
     limit 30;
    return;
  end if;
  v_q := lower(ltrim(v_q, '@'));
  if char_length(v_q) < 2 then
    raise exception 'SEARCH_TOO_SHORT' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'account_search', jsonb_build_object('by', 'name'));
  return query
  select p.id, p.handle, p.display_name,
         case when p.deleted_at is null then p.avatar_path end, c.phone_e164,
         p.created_at, p.deleted_at is not null, private.is_suspended(p.id)
    from public.profiles p
    left join private.user_contacts c on c.user_id = p.id
   where p.handle like replace(replace(v_q, '%', ''), '_', '\_') || '%'
      or lower(p.display_name) like '%' || replace(v_q, '%', '') || '%'
   order by (p.handle = v_q) desc, p.handle
   limit 30;
end;
$$;

-- Fiche d'un compte : numéro, photo, appareils, chiffres et historique des actions de
-- l'administration. Jamais de contact, de discussion ni de message.
create or replace function public.console_account(p_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console_admin();
  p     public.profiles%rowtype;
  d     public.devices%rowtype;
  s     private.sanctions%rowtype;
begin
  select * into p from public.profiles where id = p_user_id;
  if not found then
    raise exception 'ACCOUNT_NOT_FOUND' using errcode = 'P0001';
  end if;
  select * into d from public.devices x
   where x.user_id = p_user_id and x.revoked_at is null
   order by x.created_at desc limit 1;
  s := private.active_suspension(p_user_id);
  perform private.admin_log(v_uid, 'account', jsonb_build_object('handle', p.handle, 'user_id', p.id));
  return jsonb_build_object(
    'user_id', p.id,
    'handle', p.handle,
    'display_name', p.display_name,
    'avatar_path', case when p.deleted_at is null then p.avatar_path end,
    'phone_e164', (select c.phone_e164 from private.user_contacts c where c.user_id = p.id),
    'created_at', p.created_at,
    'deleted', p.deleted_at is not null,
    'last_seen_day', (private.last_seen(p_user_id) at time zone 'utc')::date,
    'last_seen_at', private.last_seen(p_user_id),
    'suspended', s.id is not null,
    'suspended_until', s.until,
    'protected', private.is_console_admin(p_user_id),
    'handle_reset', p.handle_reset_at is not null,
    'two_step', exists (select 1 from private.two_step t where t.user_id = p_user_id),
    'device', case when d.id is null then null else jsonb_build_object(
      'platform', d.platform, 'app_version', d.app_version, 'since', d.created_at,
      'push', exists (select 1 from private.push_tokens t where t.device_id = d.id)) end,
    'devices', (select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb) from (
        select dv.created_at, jsonb_build_object(
                 'id', dv.id, 'platform', dv.platform, 'app_version', dv.app_version,
                 'model', dv.model, 'os_version', dv.os_version, 'created_at', dv.created_at,
                 'last_seen_at', dv.last_seen_at, 'revoked_at', dv.revoked_at,
                 'revoked_reason', dv.revoked_reason,
                 'push', dv.revoked_at is null
                         and exists (select 1 from private.push_tokens t where t.device_id = dv.id)) j
          from public.devices dv where dv.user_id = p_user_id
         order by dv.created_at desc limit 10) x),
    'directs', (select count(*) from public.conversation_members m
                  join public.conversations c on c.id = m.conversation_id and c.kind = 'direct'
                 where m.user_id = p_user_id and m.left_at is null),
    'groups', (select count(*) from public.conversation_members m
                 join public.conversations c on c.id = m.conversation_id and c.kind = 'group'
                where m.user_id = p_user_id and m.left_at is null),
    'reports_received_90d', (select count(*) from private.reports r
                              where r.reported_user_id = p_user_id and r.created_at > now() - interval '90 days'),
    'reports_made_90d', (select count(*) from private.reports r
                          where r.reporter_id = p_user_id and r.reason <> 'support'
                            and r.created_at > now() - interval '90 days'),
    'support', (select coalesce(jsonb_agg(jsonb_build_object(
                    'id', r.id, 'details', r.details, 'created_at', r.created_at,
                    'reply', r.reply, 'replied_at', r.replied_at) order by r.created_at desc), '[]'::jsonb)
                  from private.reports r
                 where r.reporter_id = p_user_id and r.reason = 'support' and r.purge_after > now()),
    -- Actions de l'administration sur ce compte (hors sanctions, listées à part).
    'actions', (select coalesce(jsonb_agg(jsonb_build_object(
                    'action', a.action, 'created_at', a.created_at, 'detail', a.detail)
                  order by a.id desc), '[]'::jsonb)
                  from (select * from private.admin_audit a
                         where a.action in ('avatar_remove', 'handle_reset', 'disconnect', 'two_step_reset')
                           and (a.detail ->> 'user_id' = p_user_id::text
                                or (a.detail ->> 'user_id' is null and a.detail ->> 'handle' = p.handle))
                         order by a.id desc limit 20) a));
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Journal : nouveaux types d'action
-- ---------------------------------------------------------------------------
create or replace function private.journal_type(p_action text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_action in ('account', 'account_search', 'account_list', 'lift',
                      'avatar_remove', 'handle_reset') then 'accounts'
    when p_action in ('moderation', 'evidence', 'appeal') then 'reports'
    when p_action in ('policy', 'reserved_handle') then 'settings'
    when p_action in ('two_step_reset', 'disconnect') then 'security'
    when p_action = 'reply' then 'support'
    else 'views'
  end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant select (id, platform, app_version, model, os_version, created_at, last_seen_at, revoked_at,
              revoked_reason)
  on public.devices to authenticated;

grant execute on function public.register_device(text, text, text, text) to authenticated;
grant execute on function public.create_profile(text, text) to authenticated;
grant execute on function public.is_handle_available(text) to authenticated;
grant execute on function public.choose_new_handle(text) to authenticated;
grant execute on function public.my_moderation_status() to authenticated;
grant execute on function public.console_reserved_handles() to authenticated;
grant execute on function public.console_reserve_handle(text, boolean) to authenticated;
grant execute on function public.console_reset_handle(uuid, text) to authenticated;
grant execute on function public.console_remove_avatar(uuid, text) to authenticated;
grant execute on function public.console_disconnect_device(uuid, text, uuid) to authenticated;
grant execute on function public.console_accounts_page(integer, integer, text) to authenticated;
grant execute on function public.console_search_accounts(text) to authenticated;
grant execute on function public.console_account(uuid) to authenticated;
