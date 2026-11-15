-- Lot 9.1a — appels audio : mise en relation, états, trace dans la discussion, règles.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

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
create function pg_temp.tok() returns text language sql as $$
  select value from private.runtime_settings where key = 'push_dispatch_token' $$;
create function pg_temp.send(p_conv text, p_body text) returns text language sql as $$
  select id::text from public.send_message(pg_temp.v(p_conv)::uuid, gen_random_uuid(), p_body) $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text),
  pg_temp.send(text, text) to authenticated;

-- Discussion Alice–Bob ; groupe d'Alice avec Bob et Carla (membres).
select pg_temp.as_user('a');

-- Contacts : Alice–Bob, Bob–Carla ; un groupe Alice, Bob, Carla.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t values ('g', public.create_group('Voisins', null, array[pg_temp.uid('b'), pg_temp.uid('c')])::text);
select pg_temp.as_user('b');
insert into t values ('bc', public.start_direct_conversation(pg_temp.uid('c'))::text);
reset role;
create function pg_temp.call(p_conv text, p_kind text default 'audio') returns jsonb language sql as $$
  select public.start_call(pg_temp.v(p_conv)::uuid, p_kind) $$;
grant execute on function pg_temp.call(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Règles
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok($$ select pg_temp.call('g') $$, 'P0001', 'CALL_DIRECT_ONLY', 'pas d''appel de groupe');
select throws_ok($$ select pg_temp.call('ab', 'video') $$, 'P0001', 'CALL_KIND_UNAVAILABLE',
  'vidéo : pas encore');
select pg_temp.as_user('c');
select throws_ok($$ select pg_temp.call('ab') $$, 'P0001', 'NOT_MEMBER', 'pas un contact : refusé');
select pg_temp.as_user('b');
select public.set_accept_calls(false);
select pg_temp.as_user('a');
select throws_ok($$ select pg_temp.call('ab') $$, 'P0001', 'CALLS_DISABLED', 'appels coupés chez Bob');
select pg_temp.as_user('b');
select is(public.get_accept_calls(), false, 'réglage lu');
select public.set_accept_calls(true);

-- ---------------------------------------------------------------------------
-- Appel décroché puis raccroché
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
insert into t values ('c1', (pg_temp.call('ab') ->> 'id'));
select is((public.call_state(pg_temp.v('c1')::uuid) ->> 'status'), 'ringing', 'ça sonne');
select is(public.can_use_call_relay(), true, 'relais autorisé pendant l''appel');
select throws_ok($$ select pg_temp.call('ab') $$, 'P0001', 'CALL_ALREADY_ACTIVE', 'un appel à la fois');
select public.send_call_signal(pg_temp.v('c1')::uuid, 'offer', '{"sdp":"v=0 offre"}');
select pg_temp.as_user('b');
select is((public.my_open_call() ->> 'id'), pg_temp.v('c1'), 'Bob voit l''appel entrant');
select is((public.my_open_call() ->> 'outgoing'), 'false', 'entrant');
select is((public.my_open_call() ->> 'peer_name'), 'Alice', 'nom de l''appelante');
select is(jsonb_array_length(public.call_state(pg_temp.v('c1')::uuid) -> 'signals'), 1, 'Bob reçoit l''offre');
select pg_temp.as_user('a');
select throws_ok(format($$ select public.answer_call(%L) $$, pg_temp.v('c1')), 'P0001', 'CALL_NOT_FOUND',
  'l''appelante ne décroche pas pour Bob');
select is(jsonb_array_length(public.call_state(pg_temp.v('c1')::uuid) -> 'signals'), 0,
  'ses propres signaux ne lui reviennent pas');
select pg_temp.as_user('b');
select is((public.answer_call(pg_temp.v('c1')::uuid) ->> 'status'), 'accepted', 'Bob décroche');
insert into t values ('s1', public.send_call_signal(pg_temp.v('c1')::uuid, 'answer', '{"sdp":"v=0 réponse"}')::text);
select public.send_call_signal(pg_temp.v('c1')::uuid, 'ice', '{"candidate":"x"}');
select pg_temp.as_user('a');
select is(jsonb_array_length(public.call_state(pg_temp.v('c1')::uuid, pg_temp.v('s1')::bigint) -> 'signals'), 1,
  'signaux reçus après un numéro');
select pg_temp.as_user('c');
select throws_ok(format($$ select public.call_state(%L) $$, pg_temp.v('c1')), 'P0001', 'CALL_NOT_FOUND',
  'une autre personne ne voit rien');
reset role;
update private.calls set answered_at = now() - interval '183 seconds' where id = pg_temp.v('c1')::uuid;
select pg_temp.as_user('a');
set local role authenticated;
select is((public.end_call(pg_temp.v('c1')::uuid) ->> 'status'), 'ended', 'raccroché');
select is(public.can_use_call_relay(), false, 'plus de relais après l''appel');
reset role;
select is((select count(*)::int from private.call_signals where call_id = pg_temp.v('c1')::uuid), 0,
  'signaux effacés à la fin');
select ok((select body::jsonb ->> 'v' like 'ended:18%' from public.messages
            where conversation_id = pg_temp.v('ab')::uuid and kind = 'system' order by sent_at desc limit 1),
  'trace dans la discussion avec la durée');

-- ---------------------------------------------------------------------------
-- Annulé, refusé, sans réponse, occupé
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('c2', (pg_temp.call('ab') ->> 'id'));
select is((public.end_call(pg_temp.v('c2')::uuid) ->> 'status'), 'cancelled', 'annulé avant la réponse');
insert into t values ('c3', (pg_temp.call('ab') ->> 'id'));
select pg_temp.as_user('b');
select is((public.decline_call(pg_temp.v('c3')::uuid) ->> 'status'), 'declined', 'refusé');
select pg_temp.as_user('a');
insert into t values ('c4', (pg_temp.call('ab') ->> 'id'));
reset role;
update private.calls set created_at = now() - interval '46 seconds' where id = pg_temp.v('c4')::uuid;
select pg_temp.as_user('a');
set local role authenticated;
select is((public.call_state(pg_temp.v('c4')::uuid) ->> 'status'), 'missed', 'sans réponse en 45 s : manqué');

select pg_temp.as_user('b');
insert into t values ('c5', (public.start_call(pg_temp.v('bc')::uuid) ->> 'id'));
select pg_temp.as_user('a');
select is((pg_temp.call('ab') ->> 'end_reason'), 'busy', 'Bob déjà en appel : occupé');
reset role;
select is((select count(*)::int from public.messages
            where conversation_id = pg_temp.v('ab')::uuid and kind = 'system' and body like '%"e": "call"%'), 5,
  'chaque appel laisse une trace');

-- Plus de nouvelles pendant 60 s : terminé.
select pg_temp.as_user('c');
set local role authenticated;
select public.answer_call(pg_temp.v('c5')::uuid);
reset role;
update private.calls set callee_seen_at = now() - interval '61 seconds' where id = pg_temp.v('c5')::uuid;
select is(private.expire_calls(), 1, 'appel perdu clos');

-- Blocage.
select pg_temp.as_user('b');
set local role authenticated;
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('b'), pg_temp.uid('a'));
select pg_temp.as_user('a');
select throws_ok($$ select pg_temp.call('ab') $$, 'P0001', 'BLOCKED', 'bloqué : pas d''appel');
reset role;

select is(has_function_privilege('anon', 'public.start_call(uuid, text)', 'execute'), false,
  'fermé aux visiteurs non connectés');
select is(has_table_privilege('authenticated', 'private.call_signals', 'select'), false,
  'signaux illisibles directement');
select * from finish();
rollback;
