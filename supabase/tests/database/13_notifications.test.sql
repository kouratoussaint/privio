-- Lot 4.1 — notifications : jeton par appareil actif, destinataires calculés par la base.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob');
create temporary table t (k text primary key, v uuid) on commit drop;
grant all on t to authenticated;
create function pg_temp.as_user(p char) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p || '1',
    'session_id', '00000000-0000-0000-0000-00000000' || repeat(p, 4),
    'role', 'authenticated')::text, true);
$$;
create function pg_temp.tok() returns text language sql as $$
  select value from private.runtime_settings where key = 'push_dispatch_token';
$$;

select is((private.policy_value('group_max_members') #>> '{}')::int, 25,
  'B2 : 25 membres par groupe par défaut');

-- B enregistre son appareil puis son jeton FCM.
select pg_temp.as_user('b');
set local role authenticated;
select public.register_device('android', 'test');
select lives_ok($$ select public.register_push_token('jeton-fcm-de-bob-000000000001') $$,
  'B enregistre le jeton de notification de son appareil');
select throws_ok($$ select public.register_push_token('court') $$, 'P0001', 'BODY_INVALID',
  'jeton invalide refusé');
select throws_ok($$ select * from private.push_tokens $$, '42501', null,
  'les jetons sont illisibles depuis l''application');

-- A écrit à B.
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select public.register_device('android', 'test');
select public.register_push_token('jeton-fcm-d-alice-00000000001');
insert into t values ('conv', public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1'));
insert into t values ('m1', (select id from public.send_message((select v from t where k = 'conv'), gen_random_uuid(), 'Coucou')));
select throws_ok(format($$ select * from public.push_targets('x', %L) $$, (select v from t where k = 'm1')),
  '42501', null, 'push_targets est réservé au service');

reset role;
select throws_ok(format($$ select * from public.push_targets('mauvais', %L) $$, (select v from t where k = 'm1')),
  'P0001', 'AUTH_REQUIRED', 'jeton interne exigé');
select results_eq(format($$ select token from public.push_targets(%L, %L) $$, pg_temp.tok(), (select v from t where k = 'm1')),
  $$ values ('jeton-fcm-de-bob-000000000001'::text) $$,
  'seul le destinataire est notifié, jamais l''expéditeur');
select is((select count(*)::int from information_schema.parameters
            where specific_schema = 'public' and specific_name like 'push_targets%'
              and parameter_mode = 'OUT' and parameter_name in ('body', 'display_name', 'handle')), 0,
  'aucun contenu ni nom transmis pour la notification');

-- Sourdine : plus de notification.
update public.conversation_members set muted_until = now() + interval '1 hour'
 where conversation_id = (select v from t where k = 'conv') and user_id = '00000000-0000-0000-0000-0000000000b1';
select is_empty(format($$ select * from public.push_targets(%L, %L) $$, pg_temp.tok(), (select v from t where k = 'm1')),
  'discussion en sourdine : aucune notification');
update public.conversation_members set muted_until = null
 where conversation_id = (select v from t where k = 'conv');

-- Blocage : plus de notification.
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1');
select is_empty(format($$ select * from public.push_targets(%L, %L) $$, pg_temp.tok(), (select v from t where k = 'm1')),
  'blocage : aucune notification');
delete from public.blocks;

-- Message expiré : rien.
update public.messages set sent_at = now() - interval '73 hours', expires_at = now() - interval '1 hour'
 where id = (select v from t where k = 'm1');
select is_empty(format($$ select * from public.push_targets(%L, %L) $$, pg_temp.tok(), (select v from t where k = 'm1')),
  'message expiré : aucune notification');

-- Compte rendu : les jetons refusés par FCM sont supprimés.
select lives_ok(format($$ select public.push_report(%L, %L, 1, 0, 1, 'sent', array['jeton-fcm-de-bob-000000000001']) $$,
  pg_temp.tok(), (select v from t where k = 'm1')), 'compte rendu d''envoi enregistré');
select is((select count(*)::int from private.push_tokens where token = 'jeton-fcm-de-bob-000000000001'), 0,
  'un jeton refusé par FCM est supprimé');

-- Appareil révoqué (B se connecte ailleurs) : jeton supprimé.
select pg_temp.as_user('b');
set local role authenticated;
select public.register_push_token('jeton-fcm-de-bob-000000000002');
reset role;
update public.devices set revoked_at = now(), revoked_reason = 'new_device'
 where user_id = '00000000-0000-0000-0000-0000000000b1';
select is((select count(*)::int from private.push_tokens where user_id = '00000000-0000-0000-0000-0000000000b1'), 0,
  'appareil révoqué : plus aucun jeton, donc plus de notification');

reset role;
select * from finish();
rollback;
