-- Lot 10.2 — Discussions cachées : état propre à chaque personne (H), signalé dans la liste,
-- notifications et appels neutres (E, F), pas de rappel d'effacement.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

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
create function pg_temp.uid(p char) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;
create function pg_temp.v(p_k text) returns text language sql as $$ select v from t where k = p_k $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text) to authenticated;

-- Bob a un téléphone avec notifications.
select pg_temp.as_user('b');
set local role authenticated;
select public.register_device('android', '0.1.0+68');
select public.register_push_token('jeton-fcm-de-bob-000000000001');
reset role;

select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t select 'm', (to_jsonb(r) ->> 'id') from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Coucou') r;
reset role;

-- Bob cache la discussion.
select pg_temp.as_user('b');
set local role authenticated;
select is((select secret from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  false, 'visible par défaut');
select is(public.set_conversation_secret(pg_temp.v('ab')::uuid, true), true, 'Bob la cache');
select is((select secret from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  true, 'la liste la signale comme cachée (l''application la range à part)');
reset role;

select pg_temp.as_user('a');
set local role authenticated;
select is((select secret from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  false, 'H : Alice ne sait rien');
reset role;

-- E : la notification est marquée « cachée » (texte neutre côté service d'envoi).
select results_eq(format($$ select secret from public.push_targets(%L, %L) $$,
    (select value from private.runtime_settings where key = 'push_dispatch_token'), pg_temp.v('m')),
  $$ values (true) $$, 'E : notification neutre pour Bob');

-- F : appel d'Alice vers Bob.
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'call', public.start_call(pg_temp.v('ab')::uuid, 'audio') ->> 'id';
reset role;
select results_eq(format($$ select secret from public.push_call_targets(%L, %L, 'ring') $$,
    (select value from private.runtime_settings where key = 'push_dispatch_token'), pg_temp.v('call')),
  $$ values (true) $$, 'F : sonnerie neutre pour Bob');

-- Rappel « bientôt effacés » : jamais pour une discussion cachée.
update public.messages set sent_at = now() - interval '70 hours',
       expires_at = now() + interval '1 hour' where id = pg_temp.v('m')::uuid;
select is((select count(*)::int from private.expiry_reminder_candidates()
            where conversation_id = pg_temp.v('ab')::uuid), 0, 'pas de rappel d''effacement');

-- Ne plus masquer.
select pg_temp.as_user('b');
set local role authenticated;
select is(public.set_conversation_secret(pg_temp.v('ab')::uuid, false), false, 'Bob ne la masque plus');
select is((select secret from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  false, 'de retour dans la liste');
reset role;
select is((select count(*)::int from private.expiry_reminder_candidates()
            where conversation_id = pg_temp.v('ab')::uuid), 1, 'rappel de nouveau possible');
select results_eq(format($$ select secret from public.push_targets(%L, %L) $$,
    (select value from private.runtime_settings where key = 'push_dispatch_token'), pg_temp.v('m')),
  $$ values (false) $$, 'notification habituelle');

-- Seulement un membre.
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select public.set_conversation_secret(%L, true) $$, gen_random_uuid()),
  'P0001', null, 'discussion inconnue : refusé');
reset role;

select * from finish();
rollback;
