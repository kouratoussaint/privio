-- Lot 5.2 — Console : réglages (modification, bornes, cadenas, historique, retour à la valeur
-- par défaut), statistiques sur 30 jours (nombres seulement) et journal de la console.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob');

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated;
create function pg_temp.as_user(p char) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p || '1',
    'session_id', '00000000-0000-0000-0000-00000000' || repeat(p, 4),
    'role', 'authenticated')::text, true);
$$;
create function pg_temp.v(p_k text) returns text language sql as $$ select v from t where k = p_k $$;
grant execute on function pg_temp.as_user(char), pg_temp.v(text) to authenticated;

insert into t select 'n', count(*)::text from private.policy_definitions;

-- Chaque réglage est classé et nommé en français (garde-fou pour les futurs réglages).
select is_empty($$ select key from private.policy_definitions where category is null or label_fr is null $$,
  'tous les réglages ont un thème et un libellé');
select is_empty($$ select key from private.policy_definitions
                   where category in ('locked', 'future') and not admin_locked $$,
  'invariants et fonctions non développées : cadenas');

-- ---------------------------------------------------------------------------
-- Réservé à l'administrateur
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok($$ select * from public.console_policies() $$, 'P0001', 'ADMIN_REQUIRED', 'liste refusée à un autre compte');
select throws_ok($$ select public.console_set_policy('photo_daily_limit', '3') $$, 'P0001', 'ADMIN_REQUIRED',
  'modification refusée à un autre compte');
select throws_ok($$ select public.console_stats() $$, 'P0001', 'ADMIN_REQUIRED', 'statistiques refusées');
select throws_ok($$ select * from public.console_journal() $$, 'P0001', 'ADMIN_REQUIRED', 'journal refusé');
select throws_ok($$ select * from public.console_policy_history() $$, 'P0001', 'ADMIN_REQUIRED', 'historique refusé');

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
select is((select count(*)::int from public.console_policies()), pg_temp.v('n')::int,
  'tous les réglages sont listés');
select results_eq($$ select value, default_value, locked from public.console_policies() where key = 'group_max_members' $$,
  $$ values ('25'::jsonb, '25'::jsonb, false) $$, 'membres par groupe : 25, modifiable');
select is((select locked from public.console_policies() where key = 'message_ttl_hours'), true, '72 h : cadenas');
select is((select locked from public.console_policies() where key = 'video_upload_enabled'), true,
  'vidéos (non développées) : cadenas');

select is(public.console_set_policy('photo_daily_limit', '3'), '3'::jsonb, 'photos par jour : 5 → 3');
select is((public.get_client_policies() -> 'values' ->> 'photo_daily_limit')::int, 3, 'le serveur applique aussitôt la nouvelle valeur');
select is((public.get_client_policies() -> 'values' ->> 'photo_daily_limit')::int, 3,
  'les téléphones reçoivent la nouvelle valeur');
select is(public.console_set_policy('connection_requests_required', 'true'), 'true'::jsonb, 'interrupteur');

select throws_ok($$ select public.console_set_policy('photo_daily_limit', '11') $$, 'P0001', 'POLICY_OUT_OF_BOUNDS',
  'hors bornes : refusé');
select throws_ok($$ select public.console_set_policy('photo_daily_limit', '"trois"') $$, 'P0001', 'POLICY_TYPE_INVALID',
  'mauvais type : refusé');
select throws_ok($$ select public.console_set_policy('message_ttl_hours', '48') $$, 'P0001', 'POLICY_LOCKED',
  '72 h : non modifiable');
select throws_ok($$ select public.console_set_policy('screen_capture_allowed', 'true') $$, 'P0001', 'POLICY_LOCKED',
  'captures d''écran : non modifiable');
select throws_ok($$ select public.console_set_policy('video_upload_enabled', 'true') $$, 'P0001', 'POLICY_LOCKED',
  'vidéos : non activables');
select throws_ok($$ select public.console_set_policy('inconnu', '1') $$, 'P0001', 'POLICY_NOT_FOUND', 'réglage inconnu');
select is((public.get_client_policies() -> 'values' ->> 'photo_daily_limit')::int, 3, 'un refus ne change rien');

-- Historique et retour à la valeur par défaut.
select results_eq($$ select before, after, by_console from public.console_policy_history('photo_daily_limit') $$,
  $$ values (null::jsonb, '3'::jsonb, true) $$, 'historique : 3, posé depuis la console');
select is(public.console_set_policy('photo_daily_limit', '5'), '5'::jsonb, 'retour à la valeur par défaut (5)');
select results_eq($$ select before, after from public.console_policy_history('photo_daily_limit') limit 1 $$,
  $$ values ('3'::jsonb, '5'::jsonb) $$, 'historique : 3 → 5');
select isnt((select updated_at from public.console_policies() where key = 'photo_daily_limit'), null,
  'date du dernier changement affichée');

-- ---------------------------------------------------------------------------
-- Journal de la console
-- ---------------------------------------------------------------------------
select results_eq($$ select action, key, before, after from public.console_journal() limit 1 $$,
  $$ values ('policy'::text, 'photo_daily_limit'::text, '3'::jsonb, '5'::jsonb) $$,
  'journal : dernier changement avec avant / après');
select is((select label from public.console_journal() limit 1), 'Photos par compte et par jour', 'journal : libellé');

-- ---------------------------------------------------------------------------
-- Statistiques
-- ---------------------------------------------------------------------------
select is(public.console_set_policy('connection_requests_required', 'false'), 'false'::jsonb, 'interrupteur : retour');
insert into t values ('conv', public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1')::text);
select public.send_message(pg_temp.v('conv')::uuid, gen_random_uuid(), 'Bonjour');
reset role;
insert into private.push_log (message_id, recipients, sent, failed, status) values (gen_random_uuid(), 3, 2, 1, 'partial');
update public.devices set app_version = '0.1.0+27';
insert into public.devices (user_id, session_id, platform, app_version)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000bbbb', 'android', '0.1.0+27');
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('s', public.console_stats()::text);
reset role;

select is(jsonb_array_length(pg_temp.v('s')::jsonb -> 'days'), 30, '30 jours');
select is((pg_temp.v('s')::jsonb -> 'days' -> 29 ->> 'text')::int, 1, 'aujourd''hui : 1 message texte');
select is((pg_temp.v('s')::jsonb -> 'days' -> 29 ->> 'new_accounts')::int, 2, 'aujourd''hui : 2 nouveaux comptes');
select is((pg_temp.v('s')::jsonb -> 'days' -> 29 ->> 'active')::int, 1, 'aujourd''hui : 1 compte actif (relevé)');
select is((pg_temp.v('s')::jsonb -> 'days' -> 29 ->> 'push_sent')::int, 2, 'notifications envoyées : 2');
select is((pg_temp.v('s')::jsonb -> 'days' -> 29 ->> 'push_failed')::int, 1, 'notifications en échec : 1');
select is(pg_temp.v('s')::jsonb -> 'versions', '[{"version": "0.1.0+27", "devices": 1}]'::jsonb,
  'versions installées sur les téléphones actifs');
select ok(pg_temp.v('s') not like '%Bonjour%' and pg_temp.v('s') not like '%alice%'
          and pg_temp.v('s') not like '%2267000%', 'statistiques : aucun contenu, nom ni numéro');
select is((select count(*)::int from private.daily_stats where metric = 'active_users'), 1,
  'comptes actifs : un nombre par jour, rien d''autre');
select is((select count(*)::int from private.admin_audit where action = 'stats'), 1, 'consultation journalisée');

select * from finish();
rollback;
