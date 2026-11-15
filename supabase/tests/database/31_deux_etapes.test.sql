-- Lot 8.4a — vérification en deux étapes : code haché, session en attente sans aucun accès,
-- essais limités, changement de numéro protégé, code oublié (assistance, console).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now());
-- Bob : téléphone actuel (b1b1…) puis un nouveau téléphone (b2b2…) après le SMS.
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000b1b1b', '00000000-0000-0000-0000-0000000000b1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin_privio', 'Admin'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob');

create function pg_temp.as_session(p_user char, p_session text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p_user || '1',
    'session_id', p_session,
    'role', 'authenticated')::text, true);
$$;
grant execute on function pg_temp.as_session(char, text) to authenticated;
create function pg_temp.bob_old() returns void language sql as $$
  select pg_temp.as_session('b', '00000000-0000-0000-0000-0000000b1b1b') $$;
create function pg_temp.bob_new() returns void language sql as $$
  select pg_temp.as_session('b', '00000000-0000-0000-0000-0000000b2b2b') $$;
grant execute on function pg_temp.bob_old(), pg_temp.bob_new() to authenticated;

-- ---------------------------------------------------------------------------
-- Activation
-- ---------------------------------------------------------------------------
select pg_temp.bob_old();
set local role authenticated;
select public.register_device('android', '0.1.0+52');
select is(public.two_step_state() ->> 'enabled', 'false', 'désactivée par défaut');
select throws_ok($$ select public.enable_two_step('123456') $$, 'P0001', 'TWO_STEP_PIN_WEAK',
  'suite de chiffres refusée');
select throws_ok($$ select public.enable_two_step('777777') $$, 'P0001', 'TWO_STEP_PIN_WEAK',
  'chiffre répété refusé');
select throws_ok($$ select public.enable_two_step('12a456') $$, 'P0001', 'TWO_STEP_PIN_WEAK',
  '6 chiffres seulement');
select lives_ok($$ select public.enable_two_step('258014') $$, 'code accepté');
select throws_ok($$ select public.enable_two_step('369025') $$, 'P0001', 'TWO_STEP_ALREADY_ENABLED',
  'déjà activée');
select is(public.two_step_state() ->> 'verified', 'true', 'le téléphone qui active est vérifié');
reset role;
select ok((select pin_hash <> '258014' and pin_hash like '$2%' from private.two_step
            where user_id = '00000000-0000-0000-0000-0000000000b1'), 'code gardé haché (bcrypt)');

-- ---------------------------------------------------------------------------
-- Nouveau téléphone : session en attente, aucun accès ; l'ancien reste connecté
-- ---------------------------------------------------------------------------
insert into auth.sessions (id, user_id)
values ('00000000-0000-0000-0000-0000000b2b2b', '00000000-0000-0000-0000-0000000000b1');
select pg_temp.bob_new();
set local role authenticated;
select is(public.two_step_state() ->> 'verified', 'false', 'nouveau téléphone : en attente du code');
select throws_ok($$ select public.get_my_account() $$, 'P0001', 'AUTH_REQUIRED', 'compte illisible');
select throws_ok($$ select * from public.list_conversations() $$, 'P0001', 'AUTH_REQUIRED',
  'discussions illisibles');
select throws_ok($$ select public.register_device('android', '0.1.0+52') $$, 'P0001', 'AUTH_REQUIRED',
  'ne peut pas déconnecter l''ancien téléphone');
select is((select count(*)::int from public.profiles), 0, 'RLS : rien n''est visible');
select pg_temp.bob_old();
select lives_ok($$ select public.get_my_account() $$, 'l''ancien téléphone reste connecté');

-- Essais : 4 erreurs sans attente, la 5e impose une attente ; le bon code attend aussi.
select pg_temp.bob_new();
select is((public.verify_two_step('111222') ->> 'ok'), 'false', 'mauvais code');
select public.verify_two_step('111223');
select public.verify_two_step('111224');
select is((public.verify_two_step('111225') ->> 'retry_at'), null, '4 erreurs : pas d''attente');
select isnt((public.verify_two_step('111226') ->> 'retry_at'), null, '5e erreur : attente');
select is((public.verify_two_step('258014') ->> 'ok'), 'false', 'pendant l''attente : refusé');
reset role;
update private.two_step set retry_at = now() - interval '1 second'
 where user_id = '00000000-0000-0000-0000-0000000000b1';
select pg_temp.bob_new();
set local role authenticated;
select is((public.verify_two_step('258014') ->> 'ok'), 'true', 'bon code');
select is(public.two_step_state() ->> 'verified', 'true', 'nouveau téléphone vérifié');
select lives_ok($$ select public.register_device('android', '0.1.0+52') $$,
  'enregistre l''appareil (l''ancien est alors déconnecté)');
reset role;
select is((select failures from private.two_step where user_id = '00000000-0000-0000-0000-0000000000b1'), 0,
  'compteur remis à zéro');
select is((select count(*)::int from auth.sessions where user_id = '00000000-0000-0000-0000-0000000000b1'), 1,
  'un seul téléphone connecté');

-- ---------------------------------------------------------------------------
-- Changement de numéro : code exigé par le serveur
-- ---------------------------------------------------------------------------
select throws_ok($$ update auth.users set phone = '22670000009'
                     where id = '00000000-0000-0000-0000-0000000000b1' $$,
  'P0001', 'TWO_STEP_REQUIRED', 'sans code : numéro inchangé');
select pg_temp.bob_new();
set local role authenticated;
select is((public.authorize_phone_change('000111') ->> 'ok'), 'false', 'mauvais code : refusé');
select is((public.authorize_phone_change('258014') ->> 'ok'), 'true', 'bon code : autorisé');
reset role;
select lives_ok($$ update auth.users set phone = '22670000009'
                    where id = '00000000-0000-0000-0000-0000000000b1' $$, 'numéro changé');
select throws_ok($$ update auth.users set phone = '22670000008'
                     where id = '00000000-0000-0000-0000-0000000000b1' $$,
  'P0001', 'TWO_STEP_REQUIRED', 'autorisation utilisée une seule fois');

-- ---------------------------------------------------------------------------
-- Changer le code
-- ---------------------------------------------------------------------------
select pg_temp.bob_new();
set local role authenticated;
select is((public.change_two_step('000111', '470258') ->> 'ok'), 'false', 'code actuel faux');
select is((public.change_two_step('258014', '470258') ->> 'ok'), 'true', 'code changé');
reset role;

-- ---------------------------------------------------------------------------
-- Code oublié : demande d'assistance depuis un 3e téléphone, réinitialisation console
-- ---------------------------------------------------------------------------
insert into auth.sessions (id, user_id)
values ('00000000-0000-0000-0000-0000000b3b3b', '00000000-0000-0000-0000-0000000000b1');
select pg_temp.as_session('b', '00000000-0000-0000-0000-0000000b3b3b');
set local role authenticated;
select isnt(public.request_two_step_reset(), null, 'demande envoyée');
select public.request_two_step_reset();
reset role;
select is((select count(*)::int from private.reports
            where reporter_id = '00000000-0000-0000-0000-0000000000b1' and reason = 'support'), 1,
  'une seule demande d''assistance par 24 h');
select pg_temp.bob_new();
set local role authenticated;
select throws_ok(format($$ select public.console_reset_two_step(%L, 'identité vérifiée') $$,
  '00000000-0000-0000-0000-0000000000b1'), 'P0001', 'ADMIN_REQUIRED', 'réservé à l''administration');
select pg_temp.as_session('a', '00000000-0000-0000-0000-00000000aaaa');
select is((public.console_two_step('00000000-0000-0000-0000-0000000000b1') ->> 'enabled'), 'true',
  'console : vérification activée');
select isnt((public.console_two_step('00000000-0000-0000-0000-0000000000b1') ->> 'reset_requested_at'),
  null, 'console : demande visible');
select throws_ok(format($$ select public.console_reset_two_step(%L, '') $$,
  '00000000-0000-0000-0000-0000000000b1'), 'P0001', 'MODERATION_NOTE_REQUIRED', 'motif obligatoire');
select lives_ok(format($$ select public.console_reset_two_step(%L, 'Identité vérifiée par appel') $$,
  '00000000-0000-0000-0000-0000000000b1'), 'réinitialisée');
select pg_temp.as_session('b', '00000000-0000-0000-0000-0000000b3b3b');
select is(public.two_step_state() ->> 'enabled', 'false', 'le 3e téléphone peut continuer');
select lives_ok($$ select public.get_my_account() $$, 'accès rétabli');
reset role;
select is((select count(*)::int from private.admin_audit where action = 'two_step_reset'), 1,
  'réinitialisation journalisée');

-- ---------------------------------------------------------------------------
-- Désactiver (code exigé)
-- ---------------------------------------------------------------------------
select pg_temp.as_session('b', '00000000-0000-0000-0000-0000000b3b3b');
set local role authenticated;
select public.enable_two_step('369025');
select is((public.disable_two_step('000111') ->> 'ok'), 'false', 'mauvais code : reste activée');
select is((public.disable_two_step('369025') ->> 'ok'), 'true', 'désactivée');
select is(public.two_step_state() ->> 'enabled', 'false', 'plus de vérification');
reset role;

select is(has_function_privilege('anon', 'public.verify_two_step(text)', 'execute'), false,
  'fermé aux visiteurs non connectés');
select is(has_table_privilege('authenticated', 'private.two_step', 'select'), false,
  'table des codes illisible');

select * from finish();
rollback;
