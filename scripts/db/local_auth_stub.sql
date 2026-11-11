-- Imitation MINIMALE de Supabase pour exécuter les tests pgTAP sans Docker.
-- N'est JAMAIS appliqué à un projet Supabase. En CI, les tests tournent sur un vrai
-- Supabase local (supabase db start) : c'est cette exécution qui fait foi.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin noinherit bypassrls; end if;
end $$;
create schema if not exists extensions;
create schema if not exists auth;
grant usage on schema public to anon, authenticated, service_role;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  phone text unique,
  phone_confirmed_at timestamptz,
  email text,
  created_at timestamptz default now()
);
create table auth.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now()
);
create table auth.refresh_tokens (
  id bigserial primary key,
  session_id uuid references auth.sessions(id) on delete cascade,
  token text
);
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim', true), ''),
                  nullif(current_setting('request.jwt.claims', true), ''))::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated;
-- Comportement cloud par défaut : Supabase accorde tout sur public aux rôles API.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
