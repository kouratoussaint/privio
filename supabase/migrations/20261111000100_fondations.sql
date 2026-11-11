-- PRIVIO — Migration 1 : fondations de sécurité
-- Règles : refus par défaut, aucun accès implicite, aucune fonction exécutable par anon,
-- schéma `private` jamais exposé par l'API (absent de [api].schemas).

create schema if not exists private;

-- Les fonctions sont exécutables par PUBLIC par défaut dans PostgreSQL. Un retrait par
-- schéma est sans effet (les droits par schéma ne font qu'ajouter) : on retire donc le droit
-- globalement, puis private.harden_privileges() (appelée en fin de chaque migration)
-- revoque explicitement tout droit résiduel, y compris ceux ajoutés par Supabase sur public.
alter default privileges revoke execute on functions from public;
alter default privileges in schema public  revoke all on tables from anon, authenticated;
alter default privileges in schema private revoke all on tables from anon, authenticated;

revoke all on schema private from public, anon;
-- `authenticated` doit pouvoir appeler les rares fonctions privées utilisées dans les
-- politiques RLS ; l'usage du schéma ne donne accès à aucune table (aucun GRANT de table).
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Session active : l'accès aux données exige que la session du JWT existe encore.
-- Quand un nouvel appareil se connecte, les autres sessions sont supprimées
-- (règle « un seul appareil actif »), ce qui coupe immédiatement leur accès.
-- ---------------------------------------------------------------------------
create or replace function private.session_is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select exists (
        select 1
        from auth.sessions s
        where s.id = nullif(auth.jwt() ->> 'session_id', '')::uuid
          and s.user_id = auth.uid()
      )
    ),
    false
  );
$$;
revoke all on function private.session_is_active() from public;
grant execute on function private.session_is_active() to authenticated;

-- Identifiant de l'utilisateur courant, uniquement si sa session est active.
create or replace function private.require_active_user()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not private.session_is_active() then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  return v_uid;
end;
$$;
revoke all on function private.require_active_user() from public;

-- ---------------------------------------------------------------------------
-- Identifiant Privio : minuscules, 3 à 24 caractères [a-z0-9_.],
-- commence et finit par une lettre ou un chiffre, pas de « .. », mots réservés interdits.
-- ---------------------------------------------------------------------------
create or replace function private.normalize_handle(p_handle text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(lower(ltrim(btrim(coalesce(p_handle, '')), '@')), '');
$$;

create or replace function private.handle_is_valid(p_handle text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_handle is not null
     and p_handle ~ '^[a-z0-9][a-z0-9_.]{1,22}[a-z0-9]$'
     and position('..' in p_handle) = 0
     and p_handle <> all (array[
       'privio','admin','administrateur','administrator','support','aide','help',
       'moderation','moderateur','moderator','securite','security','systeme','system',
       'root','officiel','official','staff','equipe','team','null','undefined','contact'
     ]);
$$;

-- ---------------------------------------------------------------------------
-- Numéro de téléphone au format E.164. 8 chiffres sans indicatif = Burkina Faso (+226).
-- Supabase Auth stocke auth.users.phone SANS le « + » : on le rajoute.
-- ---------------------------------------------------------------------------
create or replace function private.normalize_phone_e164(p_phone text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := regexp_replace(coalesce(p_phone, ''), '[\s\-\.\(\)]', '', 'g');
begin
  if v = '' then
    return null;
  elsif v ~ '^00' then
    v := '+' || substr(v, 3);
  elsif v ~ '^[0-9]{8}$' then
    v := '+226' || v;
  elsif v !~ '^\+' then
    return null;
  end if;
  if v ~ '^\+[1-9][0-9]{7,14}$' then
    return v;
  end if;
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Limitation de débit par utilisateur, fenêtre fixe.
-- ---------------------------------------------------------------------------
create table private.rate_limit_hits (
  user_id      uuid        not null,
  bucket       text        not null,
  window_start timestamptz not null,
  hits         integer     not null default 0,
  primary key (user_id, bucket, window_start)
);
comment on table private.rate_limit_hits is
  'Compteurs de limitation de débit. Purge des fenêtres échues : tâche planifiée (étape 2).';

create or replace function private.consume_rate_limit(
  p_user_id uuid, p_bucket text, p_max integer, p_window interval
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hits integer;
begin
  insert into private.rate_limit_hits as r (user_id, bucket, window_start, hits)
  values (p_user_id, p_bucket,
          date_bin(p_window, now(), timestamptz '2000-01-01 00:00:00+00'), 1)
  on conflict (user_id, bucket, window_start)
  do update set hits = r.hits + 1
  returning hits into v_hits;

  if v_hits > p_max then
    raise exception 'RATE_LIMITED' using errcode = 'P0001';
  end if;
end;
$$;
revoke all on function private.consume_rate_limit(uuid, text, integer, interval) from public;

-- ---------------------------------------------------------------------------
-- Durcissement : à appeler en fin de CHAQUE migration.
-- public  : aucune fonction exécutable par PUBLIC/anon (les RPC sont accordées une à une
--           au rôle authenticated dans leur migration).
-- private : aucune fonction exécutable par un rôle client, sauf session_is_active (RLS).
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
  execute 'grant execute on function private.session_is_active() to authenticated';
  execute 'revoke all on all tables in schema private from public, anon, authenticated';
end;
$$;

select private.harden_privileges();
