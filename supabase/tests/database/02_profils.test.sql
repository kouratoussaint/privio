-- Création de profil, identifiant unique, droits de lecture et de modification.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now()),
  ('00000000-0000-0000-0000-0000000000c1', '22670000003', null);
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-00000000cccc', '00000000-0000-0000-0000-0000000000c1');

select results_eq(
  $$ select phone_e164 from private.user_contacts where user_id = '00000000-0000-0000-0000-0000000000a1' $$,
  $$ values ('+22670000001'::text) $$,
  'le numéro vérifié est copié en E.164 dans private.user_contacts');
select is_empty(
  $$ select 1 from private.user_contacts where user_id = '00000000-0000-0000-0000-0000000000c1' $$,
  'un numéro non vérifié n''est pas copié');

-- Utilisateur A
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","session_id":"00000000-0000-0000-0000-00000000aaaa","role":"authenticated"}', true);
set local role authenticated;

select throws_ok($$ select * from public.create_profile('ab', 'Alice') $$,
  'P0001', 'HANDLE_INVALID', 'identifiant trop court refusé');
select throws_ok($$ select * from public.create_profile('admin', 'Alice') $$,
  'P0001', 'HANDLE_INVALID', 'identifiant réservé refusé');
select throws_ok($$ select * from public.create_profile('ali..ce', 'Alice') $$,
  'P0001', 'HANDLE_INVALID', 'double point refusé');
select throws_ok($$ select * from public.create_profile('alice', '   ') $$,
  'P0001', 'DISPLAY_NAME_INVALID', 'nom vide refusé');
select results_eq($$ select handle from public.create_profile('  @Alice_BF ', 'Alice') $$,
  $$ values ('alice_bf'::text) $$, 'identifiant normalisé (espaces, @, majuscules)');
select throws_ok($$ select * from public.create_profile('autre', 'Alice') $$,
  'P0001', 'PROFILE_EXISTS', 'un seul profil par compte');
select lives_ok($$ update public.profiles set display_name = 'Alice B.' where id = auth.uid() $$,
  'le propriétaire peut modifier son nom');
select throws_ok($$ update public.profiles set handle = 'pirate' where id = auth.uid() $$,
  '42501', null, 'l''identifiant n''est pas modifiable directement');

-- Utilisateur B
reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000b1","session_id":"00000000-0000-0000-0000-00000000bbbb","role":"authenticated"}', true);
set local role authenticated;

select throws_ok($$ select * from public.create_profile('ALICE_bf', 'Bob') $$,
  'P0001', 'HANDLE_TAKEN', 'identifiant déjà pris (insensible à la casse)');
select is(public.is_handle_available('alice_bf'), false, 'disponibilité : pris');
select is(public.is_handle_available('bob_ouaga'), true, 'disponibilité : libre');
select lives_ok($$ select * from public.create_profile('bob_ouaga', 'Bob') $$, 'B crée son profil');
select is_empty($$ select 1 from public.profiles where handle = 'alice_bf' $$,
  'B ne peut pas lire directement le profil de A');

-- Utilisateur C (numéro non vérifié)
reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000c1","session_id":"00000000-0000-0000-0000-00000000cccc","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select * from public.create_profile('charlie', 'Charlie') $$,
  'P0001', 'PHONE_NOT_VERIFIED', 'profil impossible sans numéro vérifié');

-- Anonyme
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
select throws_ok($$ select * from public.create_profile('anon_x', 'X') $$,
  '42501', null, 'anon ne peut pas créer de profil');

reset role;
select * from finish();
rollback;
