-- Garde-fous structurels : RLS partout, aucun accès anonyme, schéma privé fermé,
-- aucune trace de « communautés », aucun numéro de téléphone dans les tables publiques.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

select is_empty($$
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
$$, 'RLS activée sur toutes les tables du schéma public');

select is_empty($$
  select table_name from information_schema.role_table_grants
   where grantee = 'anon' and table_schema = 'public'
$$, 'anon n''a aucun droit sur les tables publiques');

select is_empty($$
  select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private')
     and has_function_privilege('anon', p.oid, 'execute')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
$$, 'aucune fonction public/private exécutable par anon');

select is_empty($$
  select table_name from information_schema.role_table_grants
   where grantee in ('anon', 'authenticated') and table_schema = 'private'
$$, 'aucun droit client sur les tables du schéma private');

select is(
  (select string_agg(p.proname::text, ',' order by p.proname::text collate "C")
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and has_function_privilege('authenticated', p.oid, 'execute')),
  -- Lot 7.3b : GIF, aperçus des liens, règles de lecture du stockage.
  'can_read_avatar,can_read_evidence,can_read_gif,can_read_photo,can_read_preview,can_read_sticker,can_read_voice,can_see_message,is_member,session_is_active,shares_conversation',
  'seules les fonctions privées utilisées par la RLS sont exécutables par authenticated');

select is_empty($$
  select n.nspname || '.' || c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where c.relname ilike '%communit%' or c.relname ilike '%communaut%'
  union all
  select table_schema || '.' || table_name || '.' || column_name from information_schema.columns
   where column_name ilike '%communit%' or column_name ilike '%communaut%'
  union all
  select proname from pg_proc where proname ilike '%communit%' or proname ilike '%communaut%'
$$, 'aucune table, colonne ou fonction « communauté »');

select is_empty($$
  select table_name || '.' || column_name from information_schema.columns
   where table_schema = 'public' and column_name ilike '%phone%'
$$, 'aucune colonne téléphone dans le schéma public');

select is_empty($$
  select table_name || '.' || column_name from information_schema.columns
   where table_schema = 'public' and column_name ilike '%email%'
$$, 'aucune colonne e-mail dans le schéma public');

select * from finish();
rollback;
