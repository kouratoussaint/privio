-- Lot 5.7 — Santé du service : versions, appels (relais), parcours d'inscription et coût
-- des SMS, diagnostics, alertes de l'administration.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';

insert into auth.users (id, phone, phone_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '2267000000' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3)) as x(p, n);
insert into auth.sessions (id, user_id)
select ('00000000-0000-0000-0000-00000000' || repeat(p, 4))::uuid,
       ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid
  from (values ('a'), ('b'), ('c')) as x(p);
insert into public.profiles (id, handle, display_name)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, h, n
  from (values ('a', 'admin_privio', 'Admin'), ('b', 'bob_ouaga', 'Bob'), ('c', 'carla', 'Carla')) as x(p, h, n);

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
create function pg_temp.stat(p_metric text) returns bigint language sql as $$
  select coalesce(sum(value), 0)::bigint from private.daily_stats where metric = p_metric $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Réglages : versions et lien de mise à jour (vus par les téléphones)
-- ---------------------------------------------------------------------------
select is(private.build_of('0.1.0+69'), 69, 'numéro de compilation lu après le +');
select is(private.build_of('0.1.0'), null::integer, 'version sans numéro : illisible');
select is(private.build_of('0.1.0+abc'), null::integer, 'numéro illisible');

select pg_temp.as_user('b');
set local role authenticated;
select is(public.get_client_policies() -> 'values' -> 'app_min_build', '0'::jsonb, 'version minimale : 0 par défaut');
select ok(public.get_client_policies() -> 'values' ? 'app_recommended_build', 'version conseillée visible');
select ok(public.get_client_policies() -> 'values' ? 'app_update_url', 'lien visible');
select ok(not (public.get_client_policies() -> 'values' ? 'sms_unit_cost'), 'prix des SMS invisible des téléphones');
select throws_ok($$ select public.console_health() $$, 'P0001', 'ADMIN_REQUIRED', 'santé réservée à l''administration');
select throws_ok($$ select public.console_test_push() $$, 'P0001', 'ADMIN_REQUIRED', 'test réservé');
select throws_ok($$ select public.console_relay_test() $$, 'P0001', 'ADMIN_REQUIRED', 'test du relais réservé');
select throws_ok($$ select count(*) from private.sms_log $$, '42501', null, 'journal des codes inaccessible');
reset role;

select pg_temp.as_user('a');
set local role authenticated;
select lives_ok($$ select public.console_set_policy('app_min_build', '60'::jsonb) $$, 'version minimale réglée');
select lives_ok($$ select public.console_set_policy('app_recommended_build', '69'::jsonb) $$, 'version conseillée réglée');
select lives_ok($$ select public.console_set_policy('app_update_url', '"https://privio.example/privio.apk"'::jsonb) $$,
  'lien https accepté');
select throws_ok($$ select public.console_set_policy('app_update_url', '"http://privio.example/a.apk"'::jsonb) $$,
  'P0001', 'POLICY_OUT_OF_BOUNDS', 'lien non https refusé');
select throws_ok($$ select public.console_set_policy('app_update_url', '"https://a b"'::jsonb) $$,
  'P0001', 'POLICY_OUT_OF_BOUNDS', 'lien avec espace refusé');
select lives_ok($$ select public.console_set_policy('sms_unit_cost', '25'::jsonb) $$, 'prix d''un SMS réglé');
reset role;

-- Téléphones : Bob en 0.1.0+55 (sous la minimale), Carla en 0.1.0+65 (sous la conseillée).
select pg_temp.as_user('b');
set local role authenticated;
select public.register_device('android', '0.1.0+55');
select pg_temp.as_user('c');
select public.register_device('android', '0.1.0+65');
select pg_temp.as_user('a');
select public.register_device('android', '0.1.0+70');
reset role;

-- ---------------------------------------------------------------------------
-- Parcours d'inscription : codes envoyés, vérifiés, profils créés
-- ---------------------------------------------------------------------------
insert into auth.users (id, phone, confirmation_sent_at)
values ('00000000-0000-0000-0000-0000000000e1', '22670000005', now());
select is((select count(*) from private.sms_log where kind = 'code')::int, 1, 'nouveau numéro : 1 code');
update auth.users set confirmation_sent_at = now() + interval '1 second'
 where id = '00000000-0000-0000-0000-0000000000e1';
select is((select count(*) from private.sms_log where kind = 'code')::int, 2, 'code renvoyé : compté');
update auth.users set last_sign_in_at = now(), phone_confirmed_at = now()
 where id = '00000000-0000-0000-0000-0000000000e1';
select is((select count(*) from private.sms_log where kind = 'verified')::int, 1, 'code vérifié');
update auth.users set last_sign_in_at = now() + interval '1 minute'
 where id = pg_temp.uid('b');
select is((select count(*) from private.sms_log where kind = 'verified')::int, 1,
  'connexion sans code récent : pas une vérification');
update auth.users set recovery_sent_at = now() where id = pg_temp.uid('b');
select is((select count(*) from private.sms_log where kind = 'code')::int, 3, 'numéro inscrit : code compté');
update auth.users set phone_change = '22670000009', phone_change_sent_at = now() where id = pg_temp.uid('c');
select is((select count(*) from private.sms_log where kind = 'code' and purpose = 'phone_change')::int, 1,
  'changement de numéro : code compté');
update auth.users set phone = '22670000009', phone_change = '' where id = pg_temp.uid('c');
select is((select count(*) from private.sms_log where kind = 'verified' and purpose = 'phone_change')::int, 1,
  'changement de numéro vérifié');
insert into public.profiles (id, handle, display_name)
values ('00000000-0000-0000-0000-0000000000e1', 'emile', 'Émile');
select is(pg_temp.stat('signup_profiles'), 4::bigint, 'profils créés comptés');
select ok(not exists (select 1 from information_schema.columns
                       where table_schema = 'private' and table_name = 'sms_log'
                         and column_name in ('phone', 'user_id')), 'aucun numéro ni compte dans le journal des codes');

-- ---------------------------------------------------------------------------
-- Appels : issues, durée, relais
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
reset role;
insert into private.calls (id, conversation_id, caller_id, callee_id, kind, status, answered_at, created_at)
values ('00000000-0000-0000-0000-00000000ca11', pg_temp.v('ab')::uuid, pg_temp.uid('a'), pg_temp.uid('b'),
        'audio', 'accepted', now() - interval '120 seconds', now() - interval '130 seconds'),
       ('00000000-0000-0000-0000-00000000ca12', pg_temp.v('ab')::uuid, pg_temp.uid('a'), pg_temp.uid('b'),
        'video', 'ringing', null, now()),
       ('00000000-0000-0000-0000-00000000ca13', pg_temp.v('ab')::uuid, pg_temp.uid('a'), pg_temp.uid('b'),
        'audio', 'accepted', now() - interval '20 seconds', now() - interval '25 seconds');
update private.calls set status = 'ended', end_reason = 'hangup', ended_at = now()
 where id = '00000000-0000-0000-0000-00000000ca11';
update private.calls set status = 'missed', end_reason = 'timeout', ended_at = now()
 where id = '00000000-0000-0000-0000-00000000ca12';
update private.calls set status = 'ended', end_reason = 'lost', ended_at = now()
 where id = '00000000-0000-0000-0000-00000000ca13';
select is(pg_temp.stat('calls_ok'), 1::bigint, 'appel réussi compté');
select is(pg_temp.stat('calls_unanswered'), 1::bigint, 'appel manqué compté');
select is(pg_temp.stat('calls_failed'), 1::bigint, 'appel perdu compté en échec');
select is(pg_temp.stat('calls_video'), 1::bigint, 'type d''appel compté');
select ok(pg_temp.stat('calls_seconds') between 119 and 121, 'durée de l''appel réussi');
update private.calls set end_reason = 'hangup' where id = '00000000-0000-0000-0000-00000000ca11';
select is(pg_temp.stat('calls_ok'), 1::bigint, 'compté une seule fois');

select pg_temp.as_user('c');
set local role authenticated;
select throws_ok($$ select public.report_call_quality('00000000-0000-0000-0000-00000000ca11', true, 1000) $$,
  'P0001', 'CALL_NOT_FOUND', 'compte rendu : seulement les deux personnes de l''appel');
select pg_temp.as_user('b');
select throws_ok($$ select public.report_call_quality('00000000-0000-0000-0000-00000000ca12', false, 10) $$,
  'P0001', 'CALL_NOT_FOUND', 'appel jamais décroché : pas de compte rendu');
select lives_ok($$ select public.report_call_quality('00000000-0000-0000-0000-00000000ca11', true, 3000000) $$,
  'compte rendu de Bob (relais)');
select lives_ok($$ select public.report_call_quality('00000000-0000-0000-0000-00000000ca11', true, 9000000) $$,
  'deuxième compte rendu ignoré');
select pg_temp.as_user('a');
select lives_ok($$ select public.report_call_quality('00000000-0000-0000-0000-00000000ca11', true, 3200000) $$,
  'compte rendu d''Alice (relais)');
select lives_ok($$ select public.report_call_quality('00000000-0000-0000-0000-00000000ca13', false, 50000) $$,
  'appel direct');
reset role;
select is(pg_temp.stat('calls_reported'), 2::bigint, 'deux appels avec compte rendu');
select is(pg_temp.stat('calls_relayed'), 1::bigint, 'un appel par le relais');
select is(pg_temp.stat('relay_bytes'), 3200000::bigint, 'volume du relais : le plus grand des deux comptes rendus');
select is(private.relay_bytes_month(), 3200000::bigint, 'volume du mois');

-- ---------------------------------------------------------------------------
-- Console : rubrique Santé
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('h', public.console_health()::text);
reset role;
select is((pg_temp.v('h')::jsonb #>> '{versions,min_build}')::int, 60, 'santé : version minimale');
select is((pg_temp.v('h')::jsonb #>> '{versions,below_min}')::int, 1, 'un téléphone sous la minimale');
select is((pg_temp.v('h')::jsonb #>> '{versions,below_recommended}')::int, 2, 'deux sous la conseillée');
select is(pg_temp.v('h')::jsonb #>> '{versions,update_url}', 'https://privio.example/privio.apk', 'lien affiché');
select is(jsonb_array_length(pg_temp.v('h')::jsonb #> '{versions,installed}'), 3, 'versions installées');
select is(pg_temp.v('h')::jsonb #>> '{versions,installed,0,version}', '0.1.0+70', 'la plus récente en tête');
select is((pg_temp.v('h')::jsonb #>> '{calls,ok_30d}')::int, 1, 'santé : appels réussis');
select is((pg_temp.v('h')::jsonb #>> '{calls,relayed_30d}')::int, 1, 'santé : appels par le relais');
select is((pg_temp.v('h')::jsonb #>> '{signup,codes_30d}')::int, 4, 'santé : codes envoyés');
select is((pg_temp.v('h')::jsonb #>> '{signup,verified_30d}')::int, 2, 'santé : codes vérifiés');
select is((pg_temp.v('h')::jsonb #>> '{signup,cost_30d}')::int, 100, 'coût estimé : 4 codes × 25 FCFA');
select is((pg_temp.v('h')::jsonb #>> '{alerts,enabled}')::boolean, true, 'alertes activées par défaut');
select ok(pg_temp.v('h')::jsonb::text !~ '2267000000', 'aucun numéro dans la santé du service');
select is((select action from private.admin_audit order by id desc limit 1), 'health', 'consultation journalisée');

-- Diagnostics : notification de test (une toutes les 30 s), test du relais journalisé.
select pg_temp.as_user('a');
set local role authenticated;
select lives_ok($$ select public.console_test_push() $$, 'notification de test demandée');
select throws_ok($$ select public.console_test_push() $$, 'P0001', 'RATE_LIMITED', 'pas deux tests en 30 s');
select is(public.console_relay_test(), true, 'test du relais autorisé');
reset role;
select is((select count(*) from private.admin_alerts where kind = 'test')::int, 1, 'test enregistré');
select is((select action from private.admin_audit order by id desc limit 1), 'health_relay', 'test du relais journalisé');
insert into private.push_log (message_id, recipients, sent, failed, status)
select id, 1, 1, 0, 'sent' from private.admin_alerts where kind = 'test';
select pg_temp.as_user('a');
set local role authenticated;
select is(public.console_health() #>> '{diagnostics,last_test,result,status}', 'sent', 'résultat du test affiché');
reset role;

-- ---------------------------------------------------------------------------
-- Alertes
-- ---------------------------------------------------------------------------
select is(private.check_health_alerts(), '{}'::text[], 'rien d''anormal : aucune alerte');
-- Pic de codes : 31 en une heure (seuil 30).
insert into private.sms_log (kind, purpose) select 'code', 'login' from generate_series(1, 27);
select is(private.check_health_alerts(), array['sms'], 'pic de codes : alerte');
select is(private.check_health_alerts(), '{}'::text[], 'au plus une alerte par type toutes les 6 h');
-- Notifications en échec : 8 sur 10 en une heure.
insert into private.push_log (message_id, recipients, sent, failed, status)
values (gen_random_uuid(), 10, 2, 8, 'partial');
select is(private.check_health_alerts(), array['failures'], 'échecs de notifications : alerte');
-- Message expiré depuis 15 min encore présent : effacement en retard.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('m', (select id::text from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Bonjour')));
reset role;
update public.messages set sent_at = now() - interval '20 minutes', expires_at = now() - interval '15 minutes' where id = pg_temp.v('m')::uuid;
select is(private.check_health_alerts(), array['purge'], 'effacement en retard : alerte');
-- Relais : 801 Go ce mois-ci.
select private.add_stat('relay_bytes', 801000000000);
select is(private.check_health_alerts(), array['relay'], 'relais au-delà de 80 % : alerte');
select is((select count(*) from private.admin_alerts where kind <> 'test')::int, 4, 'quatre alertes');
-- Alertes coupées dans la console : plus rien.
delete from private.admin_alerts where kind <> 'test';
insert into private.policies (key, value) values ('health_alerts_enabled', 'false');
select is(private.check_health_alerts(), '{}'::text[], 'alertes coupées');
select pg_temp.as_user('a');
set local role authenticated;
select is(jsonb_array_length(public.console_health() #> '{alerts,recent}'), 0, 'liste des alertes (test exclu)');
reset role;

-- Nettoyage : alertes de plus de 30 jours, codes de plus de 35 jours.
update private.admin_alerts set created_at = now() - interval '31 days';
update private.sms_log set created_at = now() - interval '36 days';
select private.purge_health_data();
select is((select count(*) from private.admin_alerts)::int, 0, 'alertes effacées après 30 jours');
select is((select count(*) from private.sms_log)::int, 0, 'journal des codes effacé après 35 jours');

select * from finish();
rollback;
