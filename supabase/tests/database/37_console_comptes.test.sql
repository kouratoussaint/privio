-- Lot 5.6 — Comptes dans la console : numéro et photo (console seulement), filtres,
-- appareils (modèle, Android), photo retirée, identifiant imposé, @ réservés.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now()),
  ('00000000-0000-0000-0000-0000000000c1', '22670000003', now()),
  ('00000000-0000-0000-0000-0000000000d1', '22670000004', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-00000000cccc', '00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-00000000dddd', '00000000-0000-0000-0000-0000000000d1');
insert into public.profiles (id, handle, display_name, avatar_path, created_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin_privio', 'Admin', null, now() - interval '60 days'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob', 'b/photo.jpg', now() - interval '60 days'),
  ('00000000-0000-0000-0000-0000000000c1', 'carla', 'Carla', null, now() - interval '2 days');
insert into private.user_contacts (user_id, phone_e164, phone_verified_at) values
  ('00000000-0000-0000-0000-0000000000b1', '+22670000002', now()),
  ('00000000-0000-0000-0000-0000000000c1', '+22670000003', now()),
  ('00000000-0000-0000-0000-0000000000d1', '+22670000004', now())
on conflict (user_id) do update set phone_e164 = excluded.phone_e164;

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated;
create function pg_temp.as_user(p char) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p || '1',
    'session_id', '00000000-0000-0000-0000-00000000' || repeat(p, 4),
    'role', 'authenticated')::text, true);
$$;
create function pg_temp.uid(p char) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;
create function pg_temp.v(p_k text) returns text language sql as $$ select v from t where k = p_k $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Appareils : modèle et version d'Android (l'ancienne application reste compatible)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
select lives_ok($$ select public.register_device('android', '0.1.0+60') $$, 'ancienne app : 2 paramètres');
select lives_ok($$ select public.register_device('android', '0.1.0+66', 'Tecno Spark 10', '13') $$,
  'nouvelle app : modèle et Android');
select is((select model || ' / ' || os_version from public.devices where revoked_at is null), 'Tecno Spark 10 / 13',
  'chacun voit son appareil');
reset role;
-- Bob est inactif depuis 40 jours, Carla est nouvelle.
update public.devices set last_seen_at = now() - interval '40 days'
 where user_id = pg_temp.uid('b');
update public.devices set created_at = now() - interval '40 days' where user_id = pg_temp.uid('b');
insert into private.two_step (user_id, pin_hash) values (pg_temp.uid('c'), 'x');
insert into private.presence (user_id, online_until, last_seen_at) values (pg_temp.uid('a'), now(), now());

-- ---------------------------------------------------------------------------
-- Réservé à l'administration
-- ---------------------------------------------------------------------------
select pg_temp.as_user('d');
set local role authenticated;
select throws_ok($$ select public.console_accounts_page(1, 25, 'new') $$, 'P0001', 'ADMIN_REQUIRED', 'liste refusée');
select throws_ok(format($$ select public.console_remove_avatar(%L, 'Photo choquante') $$, pg_temp.uid('b')),
  'P0001', 'ADMIN_REQUIRED', 'retrait de photo refusé');
select throws_ok(format($$ select public.console_reset_handle(%L, 'Usurpation') $$, pg_temp.uid('b')),
  'P0001', 'ADMIN_REQUIRED', 'identifiant imposé refusé');
select throws_ok($$ select public.console_reserved_handles() $$, 'P0001', 'ADMIN_REQUIRED', '@ réservés refusés');
select throws_ok($$ select public.console_reserve_handle('vip', true) $$, 'P0001', 'ADMIN_REQUIRED',
  'réserver refusé');
select throws_ok($$ select public.choose_new_handle('carla_2') $$, 'P0001', 'HANDLE_CHANGE_NOT_ALLOWED',
  'changer son identifiant : seulement quand l''équipe l''impose');
reset role;

-- ---------------------------------------------------------------------------
-- Liste : numéro, photo, filtres
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('all', public.console_accounts_page(1, 25)::text);
select is((select r ->> 'phone_e164' from jsonb_array_elements(pg_temp.v('all')::jsonb -> 'rows') r
            where r ->> 'handle' = 'bob_ouaga'), '+22670000002', 'liste : numéro');
select is((select r ->> 'avatar_path' from jsonb_array_elements(pg_temp.v('all')::jsonb -> 'rows') r
            where r ->> 'handle' = 'bob_ouaga'), 'b/photo.jpg', 'liste : photo');
select is(pg_temp.v('all')::jsonb -> 'counts',
  '{"all": 3, "new": 1, "deleted": 0, "inactive": 1, "two_step": 1, "suspended": 0}'::jsonb,
  'nombre de comptes par filtre');
select is((select jsonb_agg(r ->> 'handle') from jsonb_array_elements(public.console_accounts_page(1, 25, 'new') -> 'rows') r),
  '["carla"]'::jsonb, 'filtre : nouveaux (7 j)');
select is((select jsonb_agg(r ->> 'handle') from jsonb_array_elements(public.console_accounts_page(1, 25, 'inactive') -> 'rows') r),
  '["bob_ouaga"]'::jsonb, 'filtre : inactifs (30 j)');
select is((select jsonb_agg(r ->> 'handle') from jsonb_array_elements(public.console_accounts_page(1, 25, 'two_step') -> 'rows') r),
  '["carla"]'::jsonb, 'filtre : deux étapes');
select is(public.console_accounts_page(1, 25, 'new') -> 'letters', '{"C": 0}'::jsonb, 'index A–Z du filtre');
select throws_ok($$ select public.console_accounts_page(1, 25, 'tout') $$, 'P0001', 'BODY_INVALID', 'filtre inconnu');
select results_eq($$ select phone_e164 from public.console_search_accounts('0003') $$,
  $$ values ('+22670000003'::text) $$, 'recherche partielle : numéro renvoyé');

-- ---------------------------------------------------------------------------
-- Fiche : appareils
-- ---------------------------------------------------------------------------
insert into t values ('fiche', public.console_account(pg_temp.uid('b'))::text);
select is(jsonb_array_length(pg_temp.v('fiche')::jsonb -> 'devices'), 1, 'fiche : 1 appareil');
select is(pg_temp.v('fiche')::jsonb #>> '{devices,0,model}', 'Tecno Spark 10', 'fiche : modèle');
select is(pg_temp.v('fiche')::jsonb #>> '{devices,0,os_version}', '13', 'fiche : Android');
select is(pg_temp.v('fiche')::jsonb #>> '{devices,0,app_version}', '0.1.0+66', 'fiche : version de l''app');
select is((pg_temp.v('fiche')::jsonb ->> 'two_step')::boolean, false, 'fiche : deux étapes');
select isnt(pg_temp.v('fiche')::jsonb ->> 'last_seen_at', null, 'fiche : dernière activité');
insert into t values ('dev', pg_temp.v('fiche')::jsonb #>> '{devices,0,id}');

-- ---------------------------------------------------------------------------
-- Photo retirée
-- ---------------------------------------------------------------------------
select throws_ok(format($$ select public.console_remove_avatar(%L, 'x') $$, pg_temp.uid('b')),
  'P0001', 'MODERATION_NOTE_REQUIRED', 'motif obligatoire');
select throws_ok(format($$ select public.console_remove_avatar(%L, 'Photo choquante') $$, pg_temp.uid('a')),
  'P0001', 'ADMIN_PROTECTED', 'compte de l''administration protégé');
select lives_ok(format($$ select public.console_remove_avatar(%L, 'Photo choquante') $$, pg_temp.uid('b')),
  'photo retirée');
select throws_ok(format($$ select public.console_remove_avatar(%L, 'Encore') $$, pg_temp.uid('b')),
  'P0001', 'AVATAR_NOT_FOUND', 'plus de photo');
reset role;
select is((select avatar_path from public.profiles where id = pg_temp.uid('b')), null, 'photo absente du profil');

-- ---------------------------------------------------------------------------
-- @ réservés
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select ok(public.console_reserved_handles() -> 'base' ? 'privio', 'mots toujours réservés listés');
select throws_ok($$ select public.console_reserve_handle('privio', false) $$, 'P0001', 'HANDLE_ALWAYS_RESERVED',
  'mot toujours réservé : non modifiable');
select throws_ok($$ select public.console_reserve_handle('a', true) $$, 'P0001', 'HANDLE_INVALID',
  'identifiant invalide');
select lives_ok($$ select public.console_reserve_handle('@Orange_BF', true) $$, 'réservé (normalisé)');
select is(public.console_reserved_handles() -> 'added' -> 0 ->> 'handle', 'orange_bf', 'ajouté à la liste');
reset role;
select pg_temp.as_user('d');
set local role authenticated;
select is(public.is_handle_available('orange_bf'), false, 'réservé : indisponible');
select throws_ok($$ select * from public.create_profile('orange_bf', 'Dédé') $$, 'P0001', 'HANDLE_TAKEN',
  'réservé : création refusée');
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select lives_ok($$ select public.console_reserve_handle('orange_bf', false) $$, 'libéré');
reset role;
select pg_temp.as_user('d');
set local role authenticated;
select is(public.is_handle_available('orange_bf'), true, 'libéré : disponible');
reset role;

-- ---------------------------------------------------------------------------
-- Identifiant imposé
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('tmp', public.console_reset_handle(pg_temp.uid('b'), 'Identifiant trompeur'));
select ok(pg_temp.v('tmp') like 'compte\_%', 'identifiant provisoire neutre');
reset role;
select is((select handle from public.profiles where id = pg_temp.uid('b')), pg_temp.v('tmp'),
  'l''ancien identifiant disparaît');
select pg_temp.as_user('b');
set local role authenticated;
select is((public.my_moderation_status() ->> 'handle_reset')::boolean, true, 'Bob doit en choisir un autre');
select throws_ok($$ select public.choose_new_handle('carla') $$, 'P0001', 'HANDLE_TAKEN', 'déjà pris');
select throws_ok($$ select public.choose_new_handle('admin') $$, 'P0001', 'HANDLE_INVALID', 'mot réservé');
select is(public.choose_new_handle('@Bob_Ouaga2'), 'bob_ouaga2', 'nouvel identifiant choisi');
select is((public.my_moderation_status() ->> 'handle_reset')::boolean, false, 'demande levée');
select throws_ok($$ select public.choose_new_handle('bob_3') $$, 'P0001', 'HANDLE_CHANGE_NOT_ALLOWED',
  'une seule fois');
reset role;

-- ---------------------------------------------------------------------------
-- Déconnecter un appareil précis ; historique de la fiche ; journal
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select public.console_disconnect_device(%L, 'Perdu', %L) $$,
  pg_temp.uid('b'), gen_random_uuid()), 'P0001', 'DEVICE_NOT_FOUND', 'appareil inconnu');
select is(public.console_disconnect_device(pg_temp.uid('b'), 'Téléphone perdu', pg_temp.v('dev')::uuid), 1,
  'appareil déconnecté');
insert into t values ('fiche2', public.console_account(pg_temp.uid('b'))::text);
select is(pg_temp.v('fiche2')::jsonb #>> '{devices,0,revoked_reason}', 'admin', 'appareil : déconnecté par l''équipe');
select is((select jsonb_agg(x ->> 'action') from jsonb_array_elements(pg_temp.v('fiche2')::jsonb -> 'actions') x),
  '["disconnect", "handle_reset", "avatar_remove"]'::jsonb, 'historique des actions sur ce compte');
select is((select count(*)::int from jsonb_array_elements(
            (public.console_journal_page('accounts', null, 1, 100)) -> 'rows') r
            where r ->> 'action' in ('avatar_remove', 'handle_reset')), 2, 'journal : comptes');
select is((select count(*)::int from jsonb_array_elements(
            (public.console_journal_page('settings', null, 1, 100)) -> 'rows') r
            where r ->> 'action' = 'reserved_handle'), 2, 'journal : réglages (@ réservés)');
reset role;

select * from finish();
rollback;
