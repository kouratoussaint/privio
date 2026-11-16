-- Lot 10.1 — Effacer après lecture : réglage (A, B), échéance propre à chaque lecteur (C),
-- copie de l'expéditeur effacée quand tout le monde a lu (D), messages suivants seulement (E).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now()),
  ('00000000-0000-0000-0000-0000000000c1', '22670000003', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-00000000cccc', '00000000-0000-0000-0000-0000000000c1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob'),
  ('00000000-0000-0000-0000-0000000000c1', 'carla', 'Carla');

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
  select to_jsonb(r) ->> 'id' from public.send_message(p_conv::uuid, gen_random_uuid(), p_body) r $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text),
  pg_temp.send(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Discussion à deux
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t values ('avant', pg_temp.send(pg_temp.v('ab'), 'Envoyé avant'));
select throws_ok(format($$ select public.set_read_erase(%L, 60) $$, pg_temp.v('ab')), 'P0001',
  'READ_ERASE_INVALID', 'A : seulement 30 s, 5 min ou 1 h');
reset role;

-- B : l'une ou l'autre personne peut l'activer.
select pg_temp.as_user('b');
set local role authenticated;
select is(public.set_read_erase(pg_temp.v('ab')::uuid, 300), 300, 'Bob active 5 min');
select is((select read_erase_seconds from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  300, 'réglage visible dans la liste');
select is((select body from public.get_messages(pg_temp.v('ab')::uuid) where kind = 'system' limit 1),
  'erase:300', 'message d''information dans la discussion');
reset role;

select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('apres', pg_temp.send(pg_temp.v('ab'), 'Envoyé après'));
select is((select read_erase_seconds from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('avant')::uuid),
  null, 'E : message envoyé avant : non concerné');
select is((select read_erase_seconds from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('apres')::uuid),
  300, 'E : message envoyé après : 5 min après lecture');
-- L'expéditeur qui se « lit » lui-même ne déclenche rien.
select public.mark_conversation(pg_temp.v('ab')::uuid, now(), now());
reset role;
select is((select count(*)::int from private.read_erasures), 0, 'l''expéditeur ne déclenche pas l''effacement');

-- Bob lit : échéance dans 5 min, pour lui et (D) pour Alice.
select pg_temp.as_user('b');
set local role authenticated;
select public.mark_conversation(pg_temp.v('ab')::uuid, now(), now());
select ok((select expires_at from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('apres')::uuid)
          between now() + interval '299 seconds' and now() + interval '301 seconds',
  'Bob : disparaît 5 min après sa lecture');
select ok((select expires_at from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('avant')::uuid)
          > now() + interval '1 hour', 'Bob : le message d''avant garde sa durée normale');
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select ok((select expires_at from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('apres')::uuid)
          between now() + interval '299 seconds' and now() + interval '301 seconds',
  'D : copie d''Alice effacée au même moment');
reset role;

-- Échéance passée : plus rien, nulle part.
update private.read_erasures set erase_at = now() - interval '1 second';
select pg_temp.as_user('b');
set local role authenticated;
select is((select count(*)::int from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('apres')::uuid),
  0, 'Bob : message disparu');
select throws_ok(format($$ select public.set_reaction(%L, '👍') $$, pg_temp.v('apres')), 'P0001',
  'MESSAGE_EXPIRED', 'plus de réaction possible');
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select is((select count(*)::int from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('apres')::uuid),
  1, 'Alice : effacé à l''échéance fixée sur le message (vérifié ci-dessus)');
reset role;

-- Couper : les messages suivants ne sont plus concernés.
select pg_temp.as_user('a');
set local role authenticated;
select is(public.set_read_erase(pg_temp.v('ab')::uuid, null), null, 'coupé');
insert into t values ('ensuite', pg_temp.send(pg_temp.v('ab'), 'Normal'));
select is((select read_erase_seconds from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('ensuite')::uuid),
  null, 'messages suivants : durée normale');
select is((select count(*)::int from public.get_messages(pg_temp.v('ab')::uuid) where kind = 'system' and body = 'erase:0'),
  1, 'information « désactivé »');
reset role;

-- ---------------------------------------------------------------------------
-- Groupe : administrateurs seulement ; chacun à son rythme ; effacé quand tous ont lu
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('g', public.create_group('Voisins', null, array[pg_temp.uid('b'), pg_temp.uid('c')])::text);
reset role;
select pg_temp.as_user('b');
set local role authenticated;
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
select throws_ok(format($$ select public.set_read_erase(%L, 30) $$, pg_temp.v('g')), 'P0001', 'NOT_ADMIN',
  'B : un membre ne peut pas l''activer');
reset role;
select pg_temp.as_user('c');
set local role authenticated;
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select is(public.set_read_erase(pg_temp.v('g')::uuid, 30), 30, 'l''administratrice active 30 s');
insert into t values ('gm', pg_temp.send(pg_temp.v('g'), 'Rendez-vous à 18 h'));
reset role;

select pg_temp.as_user('b');
set local role authenticated;
select public.mark_conversation(pg_temp.v('g')::uuid, now(), now());
select ok((select expires_at from public.get_messages(pg_temp.v('g')::uuid) where id = pg_temp.v('gm')::uuid)
          < now() + interval '31 seconds', 'C : Bob a lu, son échéance est dans 30 s');
reset role;
select pg_temp.as_user('c');
set local role authenticated;
select ok((select expires_at from public.get_messages(pg_temp.v('g')::uuid) where id = pg_temp.v('gm')::uuid)
          > now() + interval '1 hour', 'C : Carla n''a pas lu, le message reste');
reset role;
select ok((select expires_at from public.messages where id = pg_temp.v('gm')::uuid) > now() + interval '1 hour',
  'pas encore lu par tous : pas supprimé pour tout le monde');

-- L'échéance de Bob passe : masqué chez lui seulement.
update private.read_erasures set erase_at = now() - interval '1 second' where user_id = pg_temp.uid('b');
select ok(private.apply_read_erasures() >= 1, 'tâche de la minute');
select is((select count(*)::int from public.message_hidden where message_id = pg_temp.v('gm')::uuid), 1,
  'masqué chez Bob seulement (favoris, médias, épinglés)');
select pg_temp.as_user('b');
set local role authenticated;
select is((select count(*)::int from public.get_messages(pg_temp.v('g')::uuid) where id = pg_temp.v('gm')::uuid),
  0, 'Bob ne le voit plus');
select isnt((select last_message_id from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid),
  pg_temp.v('gm')::uuid, 'liste de Bob : le message n''y figure plus');
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select is((select count(*)::int from public.get_messages(pg_temp.v('g')::uuid) where id = pg_temp.v('gm')::uuid),
  1, 'Alice (expéditrice) le voit encore');
reset role;

-- Carla lit : tout le monde a lu → supprimé pour tous à la dernière échéance (D).
select pg_temp.as_user('c');
set local role authenticated;
select public.mark_conversation(pg_temp.v('g')::uuid, now(), now());
reset role;
select ok((select expires_at from public.messages where id = pg_temp.v('gm')::uuid)
          between now() + interval '29 seconds' and now() + interval '31 seconds',
  'lu par tous : effacé pour tout le monde 30 s après la dernière lecture');

select * from finish();
rollback;
