-- Lot 8.4b — rappel avant effacement : non-lus de 12 h ou plus qui s'effacent dans moins
-- de 4 h ; une notification sans contenu par discussion et par 12 h ; réglage, sourdine,
-- « Mentions seulement » et blocage respectés.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');
insert into private.runtime_settings (key, value) values ('functions_url', 'http://fonctions.test/functions/v1')
on conflict (key) do update set value = excluded.value;

insert into auth.users (id, phone, phone_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '2267000000' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3)) as x(p, n);
insert into auth.sessions (id, user_id)
select ('00000000-0000-0000-0000-00000000' || repeat(p, 4))::uuid,
       ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid
  from (values ('a'), ('b'), ('c')) as x(p);
insert into public.profiles (id, handle, display_name)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, h, n
  from (values ('a', 'alice_bf', 'Alice'), ('b', 'bob_ouaga', 'Bob'), ('c', 'carla', 'Carla')) as x(p, h, n);

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
create function pg_temp.candidates() returns integer language sql as $$
  select count(*)::int from private.expiry_reminder_candidates() where user_id = pg_temp.uid('b') $$;

-- Bob a un appareil avec notifications ; Alice lui écrit (72 h) et à Carla.
select pg_temp.as_user('b');
set local role authenticated;
select public.register_device('android', '0.1.0+53');
select public.register_push_token('jeton-fcm-de-bob-000000000001');
select pg_temp.as_user('a');
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t values ('m1', (select id::text from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Rendez-vous demain')));
reset role;

select is(pg_temp.candidates(), 0, 'loin de l''effacement : pas de rappel');

-- Le message s'efface dans 3 h (envoyé il y a 69 h).
update public.messages set sent_at = now() - interval '69 hours', expires_at = now() + interval '3 hours'
 where id = pg_temp.v('m1')::uuid;
select is(pg_temp.candidates(), 1, 'non lu, 3 h avant l''effacement : rappel');

-- Réglage coupé.
select pg_temp.as_user('b');
set local role authenticated;
select is(public.get_expiry_reminder(), true, 'activé par défaut');
select public.set_expiry_reminder(false);
reset role;
select is(pg_temp.candidates(), 0, 'réglage coupé : pas de rappel');
select pg_temp.as_user('b');
set local role authenticated;
select public.set_expiry_reminder(true);
reset role;

-- Sourdine, puis « Mentions seulement ».
update public.conversation_members set muted_until = now() + interval '1 hour'
 where conversation_id = pg_temp.v('ab')::uuid and user_id = pg_temp.uid('b');
select is(pg_temp.candidates(), 0, 'sourdine : pas de rappel');
update public.conversation_members set muted_until = null, notify_mode = 'mentions'
 where conversation_id = pg_temp.v('ab')::uuid and user_id = pg_temp.uid('b');
select is(pg_temp.candidates(), 0, '« Mentions seulement » : pas de rappel');
update public.conversation_members set notify_mode = 'all'
 where conversation_id = pg_temp.v('ab')::uuid and user_id = pg_temp.uid('b');

-- Message court (durée 1 h) : jamais de rappel.
update public.messages set sent_at = now() - interval '30 minutes', expires_at = now() + interval '30 minutes'
 where id = pg_temp.v('m1')::uuid;
select is(pg_temp.candidates(), 0, 'message de moins de 12 h : pas de rappel');
update public.messages set sent_at = now() - interval '69 hours', expires_at = now() + interval '3 hours'
 where id = pg_temp.v('m1')::uuid;

-- Envoi : une seule notification par discussion et par 12 h.
select is(private.send_expiry_reminders(), 1, 'un rappel envoyé');
select is(private.send_expiry_reminders(), 0, 'pas deux fois');
select is((select count(*)::int from net.http_request_queue q
            where convert_from(q.body, 'utf8')::jsonb ? 'expiry_reminder_id'
              and convert_from(q.body, 'utf8')::jsonb - 'expiry_reminder_id' = '{}'::jsonb), 1,
  'confié à push-dispatch (identifiant seul, sans contenu)');
select is((select count(*)::int from public.push_expiry_reminder_targets(
            (select value from private.runtime_settings where key = 'push_dispatch_token'),
            (select id from private.expiry_reminders limit 1))), 1, 'jeton de Bob');
select throws_ok($$ select * from public.push_expiry_reminder_targets('faux', gen_random_uuid()) $$,
  'P0001', NULL, 'jeton de service exigé');

-- Lu : plus de rappel.
delete from private.expiry_reminders;
update public.conversation_members set read_up_to = now()
 where conversation_id = pg_temp.v('ab')::uuid and user_id = pg_temp.uid('b');
select is(pg_temp.candidates(), 0, 'lu : pas de rappel');

-- Mes propres messages ne déclenchent rien chez moi.
select is((select count(*)::int from private.expiry_reminder_candidates() where user_id = pg_temp.uid('a')), 0,
  'l''expéditrice n''est pas rappelée');

select is(has_function_privilege('authenticated', 'public.push_expiry_reminder_targets(text, uuid)', 'execute'),
  false, 'cibles réservées au service');
select * from finish();
rollback;
