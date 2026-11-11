-- PRIVIO : esquisse de migration, PAS une migration de production.
-- Claude doit ajouter toutes les tables, contraintes, fonctions, politiques RLS et tests.
create extension if not exists pgcrypto;
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  handle text unique not null,
  display_name text not null,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "profiles_owner_select" on public.profiles for select to authenticated using (auth.uid() = id);
create policy "profiles_owner_update" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
-- Ne PAS exposer des messages tant que les RLS membership + TTL ne sont pas implémentées et testées.
-- Utiliser RPC transactionnelle pour les quotas photo; pas de SELECT puis INSERT concurrent.
