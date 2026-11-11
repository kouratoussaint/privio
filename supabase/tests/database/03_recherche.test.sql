-- Recherche par identifiant et par numéro : réponses minimales, découvrabilité, blocages,
-- comptes supprimés, limitation de débit.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now()),
  ('00000000-0000-0000-0000-0000000000d1', '22670000004', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob'),
  ('00000000-0000-0000-0000-0000000000d1', 'dina', 'Dina');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","session_id":"00000000-0000-0000-0000-00000000aaaa","role":"authenticated"}', true);
set local role authenticated;

select results_eq($$ select handle, display_name from public.find_user_by_handle('@Bob_Ouaga') $$,
  $$ values ('bob_ouaga'::text, 'Bob'::text) $$, 'recherche exacte par identifiant');
select is_empty($$ select * from public.find_user_by_handle('bob') $$,
  'pas de recherche par préfixe');
select is_empty($$ select * from public.find_user_by_handle('alice_bf') $$,
  'on ne se trouve pas soi-même');
select is_empty($$ select * from public.find_user_by_phone('70 00 00 02') $$,
  'numéro non découvrable : réponse vide');

reset role;
update private.user_contacts set phone_discoverable = true
 where user_id = '00000000-0000-0000-0000-0000000000b1';
set local role authenticated;

select results_eq($$ select handle from public.find_user_by_phone('70 00 00 02') $$,
  $$ values ('bob_ouaga'::text) $$, 'numéro découvrable trouvé (8 chiffres → +226)');
select results_eq($$ select handle from public.find_user_by_phone('0022670000002') $$,
  $$ values ('bob_ouaga'::text) $$, 'format international 00 accepté');
select is((select count(*)::int from information_schema.parameters
            where specific_schema = 'public' and specific_name like 'find_user_by_phone%'
              and parameter_mode = 'OUT' and parameter_name ilike '%phone%'), 0,
  'la recherche par numéro ne renvoie jamais de numéro');

-- Blocage par B : A ne trouve plus B (et inversement).
reset role;
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select is_empty($$ select * from public.find_user_by_handle('bob_ouaga') $$,
  'utilisateur qui m''a bloqué : introuvable par identifiant');
select is_empty($$ select * from public.find_user_by_phone('+22670000002') $$,
  'utilisateur qui m''a bloqué : introuvable par numéro');

-- Compte supprimé.
reset role;
update public.profiles set deleted_at = now() where handle = 'dina';
set local role authenticated;
select is_empty($$ select * from public.find_user_by_handle('dina') $$, 'compte supprimé introuvable');

-- Découvrabilité gérée par l'utilisateur lui-même.
select is(public.set_phone_discoverable(true), true, 'activation de la découvrabilité');
select is((public.get_my_account() ->> 'phone_discoverable')::boolean, true, 'état relu via get_my_account');

-- Limitation : 20 recherches par numéro et par heure (politique par défaut).
-- 4 recherches ont déjà été faites ci-dessus.
do $$ begin
  for i in 1..16 loop perform * from public.find_user_by_phone('+22670000009'); end loop;
end $$;
select throws_ok($$ select * from public.find_user_by_phone('+22670000009') $$,
  'P0001', 'RATE_LIMITED', '21e recherche par numéro dans l''heure refusée');

reset role;
select * from finish();
rollback;
