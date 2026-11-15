-- Lot 9.1b — appels : réveil du téléphone de l'appelé et « Appel manqué ».
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');
insert into private.runtime_settings (key, value) values ('functions_url', 'http://fonctions.test/functions/v1')
on conflict (key) do update set value = excluded.value;

insert into auth.users (id, phone, phone_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '2267000000' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3), ('d', 4)) as x(p, n);
insert into auth.sessions (id, user_id)
select ('00000000-0000-0000-0000-00000000' || repeat(p, 4))::uuid,
       ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid
  from (values ('a'), ('b'), ('c'), ('d')) as x(p);
insert into public.profiles (id, handle, display_name)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, h, n
  from (values ('a', 'alice_bf', 'Alice'), ('b', 'bob_ouaga', 'Bob'), ('c', 'carla', 'Carla'),
               ('d', 'dani', 'Dani')) as x(p, h, n);

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
create function pg_temp.send(p_conv text, p_body text) returns text language sql as $$
  select id::text from public.send_message(pg_temp.v(p_conv)::uuid, gen_random_uuid(), p_body) $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text),
  pg_temp.send(text, text) to authenticated;

-- Discussion Alice–Bob ; groupe d'Alice avec Bob et Carla (membres).
select pg_temp.as_user('a');

select pg_temp.as_user('b');
set local role authenticated;
select public.register_device('android', '0.1.0+56');
select public.register_push_token('jeton-fcm-de-bob-000000000001');
select pg_temp.as_user('a');
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
reset role;
create function pg_temp.events() returns text[] language sql as $$
  select coalesce(array_agg(convert_from(q.body, 'utf8')::jsonb ->> 'call_event' order by q.id), '{}')
    from net.http_request_queue q where convert_from(q.body, 'utf8')::jsonb ? 'call_event' $$;
create function pg_temp.tok() returns text language sql as $$
  select value from private.runtime_settings where key = 'push_dispatch_token' $$;

select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('c1', public.start_call(pg_temp.v('ab')::uuid) ->> 'id');
reset role;
select is(pg_temp.events(), array['ring'], 'appel : le téléphone de Bob est réveillé');
select is((select count(*)::int from public.push_call_targets(pg_temp.tok(), pg_temp.v('c1')::uuid, 'ring')), 1,
  'jeton de Bob pendant la sonnerie');
select is((select count(*)::int from public.push_call_targets(pg_temp.tok(), pg_temp.v('c1')::uuid, 'missed')), 0,
  'pas encore manqué');
select throws_ok(format($$ select * from public.push_call_targets('faux', %L, 'ring') $$, pg_temp.v('c1')),
  'P0001', 'AUTH_REQUIRED', 'jeton de service exigé');

select pg_temp.as_user('a');
set local role authenticated;
select public.end_call(pg_temp.v('c1')::uuid);
reset role;
select is(pg_temp.events(), array['ring', 'missed'], 'annulé : sonnerie arrêtée, appel manqué');
select is((select count(*)::int from public.push_call_targets(pg_temp.tok(), pg_temp.v('c1')::uuid, 'missed')), 1,
  'jeton de Bob pour l''appel manqué');
select is((select count(*)::int from public.push_call_targets(pg_temp.tok(), pg_temp.v('c1')::uuid, 'ring')), 0,
  'plus de sonnerie');

-- Décroché puis raccroché : rien de plus.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('c2', public.start_call(pg_temp.v('ab')::uuid) ->> 'id');
select pg_temp.as_user('b');
select public.answer_call(pg_temp.v('c2')::uuid);
select public.end_call(pg_temp.v('c2')::uuid);
reset role;
select is(pg_temp.events(), array['ring', 'missed', 'ring'], 'appel décroché : pas d''« appel manqué »');

-- Sourdine : la notification d'appel manqué est coupée.
update public.conversation_members set muted_until = now() + interval '1 hour'
 where conversation_id = pg_temp.v('ab')::uuid and user_id = pg_temp.uid('b');
select is(public.push_call_muted(pg_temp.tok(), pg_temp.v('c2')::uuid), true, 'sourdine vue par push-dispatch');

select is(has_function_privilege('authenticated', 'public.push_call_targets(text, uuid, text)', 'execute'),
  false, 'réservé au service');
select * from finish();
rollback;
