-- Un seul appareil actif : le nouvel appareil révoque l'ancien et supprime sa session.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-0000000000a1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice');

-- Téléphone 1
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","session_id":"00000000-0000-0000-0000-0000000a0001","role":"authenticated"}', true);
set local role authenticated;
select isnt(public.register_device('android', '0.1.0'), null, 'téléphone 1 enregistré');
select is((select count(*)::int from public.profiles), 1, 'téléphone 1 lit son profil');

-- Téléphone 2 : connexion OTP sur un autre téléphone (nouvelle session), puis enregistrement.
reset role;
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-0000000a0002', '00000000-0000-0000-0000-0000000000a1');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","session_id":"00000000-0000-0000-0000-0000000a0002","role":"authenticated"}', true);
set local role authenticated;
select isnt(public.register_device('android', '0.1.0'), null, 'téléphone 2 enregistré');
select is((select count(*)::int from public.devices where revoked_at is null), 1, 'un seul appareil actif');
select is((select revoked_reason from public.devices where revoked_at is not null), 'new_device',
  'l''ancien appareil est révoqué pour cause de nouvel appareil');

reset role;
select is_empty($$ select 1 from auth.sessions where id = '00000000-0000-0000-0000-0000000a0001' $$,
  'la session du téléphone 1 est supprimée');

-- Téléphone 1 tente encore d'accéder avec un jeton d'accès non expiré.
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","session_id":"00000000-0000-0000-0000-0000000a0001","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.profiles), 0, 'téléphone 1 ne lit plus rien (RLS)');
select throws_ok($$ select public.get_my_account() $$, 'P0001', 'AUTH_REQUIRED',
  'téléphone 1 ne peut plus appeler les RPC');

reset role;
select * from finish();
rollback;
