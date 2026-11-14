-- Lot 7.2b1-bis — un accusé « distribué » seul ne marque jamais « lu ».
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

insert into auth.users (id, phone, phone_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '2267000000' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3)) as x(p, n);
insert into auth.sessions (id, user_id)
select ('00000000-0000-0000-0000-00000000' || repeat(p, 4))::uuid,
       ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid
  from (values ('a'), ('b'), ('c')) as x(p);
insert into public.profiles (id, handle, display_name)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, h, n
  from (values ('a', 'alice_bf', 'Alice'), ('b', 'bob_ouaga', 'Bob'), ('c', 'carla', 'Carla'))
       as x(p, h, n);

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
create function pg_temp.unread(p_k text) returns int language sql as $$
  select unread_count from public.list_conversations() where conversation_id = pg_temp.v(p_k)::uuid $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text),
  pg_temp.unread(text) to authenticated;

-- Alice écrit à Bob (discussion) et au groupe (Bob, Carla).
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t values ('g', public.create_group('Voisins', null,
  array[pg_temp.uid('b'), pg_temp.uid('c')])::text);
reset role;
-- Bob et Carla acceptent l'invitation.
select pg_temp.as_user('b');
set local role authenticated;
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
reset role;
select pg_temp.as_user('c');
set local role authenticated;
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select * from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Bonjour Bob');
select * from public.send_message(pg_temp.v('g')::uuid, gen_random_uuid(), 'Bonjour le groupe');
reset role;
-- Une transaction : le message de la discussion est daté juste avant (sent_at et
-- expires_at ensemble). Celui du groupe garde l'heure de la transaction (celle de l'arrivée
-- des membres) : il n'est visible qu'à partir de leur arrivée.
update public.messages set sent_at = sent_at - interval '1 minute',
                           expires_at = expires_at - interval '1 minute'
 where conversation_id = pg_temp.v('ab')::uuid;

-- Bob est sur la liste : seulement « distribué ».
select pg_temp.as_user('b');
set local role authenticated;
select is(pg_temp.unread('ab'), 1, 'discussion : 1 non lu avant');
select is(pg_temp.unread('g'), 1, 'groupe : 1 non lu avant');
select public.mark_conversation(pg_temp.v('ab')::uuid, p_delivered_up_to => now());
select public.mark_conversation(pg_temp.v('g')::uuid, p_delivered_up_to => now());
select is(pg_temp.unread('ab'), 1, 'discussion : « distribué » ne vaut pas « lu »');
select is(pg_temp.unread('g'), 1, 'groupe : « distribué » ne vaut pas « lu »');
-- Appel vide : rien ne change.
select public.mark_conversation(pg_temp.v('ab')::uuid);
select is(pg_temp.unread('ab'), 1, 'appel sans date : toujours non lu');
reset role;
select ok(
  (select delivered_up_to is not null and read_up_to is null
     from public.conversation_members
    where conversation_id = pg_temp.v('ab')::uuid and user_id = pg_temp.uid('b')),
  'Bob : distribué enregistré, lu vide');

-- Côté Alice : « distribué », pas « lu ».
select pg_temp.as_user('a');
set local role authenticated;
select ok(
  (select peer_delivered_up_to is not null and peer_read_up_to is null
     from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  'Alice voit « distribué », pas « lu »');
reset role;

-- Bob ouvre la discussion : « lu ».
select pg_temp.as_user('b');
set local role authenticated;
select public.mark_conversation(pg_temp.v('ab')::uuid, now(), now());
select is(pg_temp.unread('ab'), 0, 'discussion ouverte : lu');
select is(pg_temp.unread('g'), 1, 'le groupe reste non lu');
-- Un « distribué » plus ancien ne recule pas la lecture.
select public.mark_conversation(pg_temp.v('ab')::uuid, now() - interval '1 hour');
select is(pg_temp.unread('ab'), 0, 'un accusé plus ancien ne recule rien');
reset role;

select * from finish();
rollback;
