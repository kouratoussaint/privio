-- Politiques : bornes, invariant 72 h, fonctionnalités non implémentées, historique immuable.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1');

select throws_ok($$ insert into private.policies (key, value) values ('message_ttl_hours', '96') $$,
  'P0001', 'POLICY_OUT_OF_BOUNDS', 'impossible d''étendre la durée au-delà de 72 h');
select throws_ok($$ insert into private.policies (key, value) values ('message_ttl_hours', '"72"') $$,
  'P0001', 'POLICY_TYPE_INVALID', 'type de valeur contrôlé');
select throws_ok($$ insert into private.policies (key, value) values ('video_upload_enabled', 'true') $$,
  'P0001', 'FEATURE_NOT_IMPLEMENTED', 'fonction non développée non activable');
select throws_ok($$ insert into private.policies (key, value) values ('quota_timezone', '"Europe/Paris"') $$,
  'P0001', 'POLICY_OUT_OF_BOUNDS', 'fuseau hors liste refusé');
select lives_ok($$ insert into private.policies (key, value) values ('search_phone_hourly_limit', '10') $$,
  'valeur dans les bornes acceptée');
select lives_ok($$ update private.policies set value = '15' where key = 'search_phone_hourly_limit' $$,
  'modification acceptée');
select is((select version from private.policies where key = 'search_phone_hourly_limit'), 2,
  'la version est incrémentée');
select is((select count(*)::int from private.policy_history where policy_key = 'search_phone_hourly_limit'), 2,
  'chaque changement est historisé');
select throws_ok($$ delete from private.policy_history $$, 'P0001', 'APPEND_ONLY',
  'l''historique est en ajout seul');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","session_id":"00000000-0000-0000-0000-00000000aaaa","role":"authenticated"}', true);
set local role authenticated;
select is((public.get_client_policies() -> 'values' ->> 'message_ttl_hours')::int, 72,
  'le client lit la durée de vie effective (72 h)');
select throws_ok($$ select * from private.policies $$, '42501', null,
  'le client ne lit pas les tables de politiques');

reset role;
select * from finish();
rollback;
