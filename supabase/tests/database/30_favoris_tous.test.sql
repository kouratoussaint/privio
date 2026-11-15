-- Lot 8.3a — favoris de toutes les discussions.
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
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t values ('g', public.create_group('Voisins', null,
  array[pg_temp.uid('b'), pg_temp.uid('c')])::text);
select pg_temp.as_user('b');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
select pg_temp.as_user('c');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
select pg_temp.as_user('a');
insert into t values ('m1', pg_temp.send('ab', 'Un'));
insert into t values ('m2', pg_temp.send('ab', 'Deux'));
insert into t values ('m3', pg_temp.send('ab', 'Trois'));
insert into t values ('m4', pg_temp.send('ab', 'Quatre'));
insert into t values ('g1', pg_temp.send('g', 'Bonjour le groupe'));

-- Bob : un favori dans la discussion à deux, un dans le groupe.
select pg_temp.as_user('b');
select public.set_message_favorites(array[pg_temp.v('m4')::uuid, pg_temp.v('g1')::uuid], true);
select is((select array_agg(body order by body) from public.list_all_favorite_messages()),
  array['Bonjour le groupe', 'Quatre'], 'toutes les discussions réunies');
select is((select conversation_id::text from public.list_all_favorite_messages() where body = 'Quatre'),
  pg_temp.v('ab'), 'chaque favori indique sa discussion');
select pg_temp.as_user('c');
select is((select count(*)::int from public.list_all_favorite_messages()), 0,
  'les favoris sont personnels');

-- Supprimé chez moi, puis groupe quitté : plus listés.
select pg_temp.as_user('b');
select public.delete_message_for_me(pg_temp.v('m4')::uuid);
select is((select array_agg(body) from public.list_all_favorite_messages()),
  array['Bonjour le groupe'], 'message supprimé chez moi : retiré');
select public.leave_group(pg_temp.v('g')::uuid);
select is((select count(*)::int from public.list_all_favorite_messages()), 0,
  'groupe quitté : ses favoris ne sont plus listés');

-- Expiré : plus listé.
select pg_temp.as_user('a');
select public.set_message_favorites(array[pg_temp.v('m1')::uuid], true);
reset role;
update public.messages set sent_at = now() - interval '73 hours', expires_at = now() - interval '1 hour'
 where id = pg_temp.v('m1')::uuid;
select pg_temp.as_user('a');
set local role authenticated;
select is((select count(*)::int from public.list_all_favorite_messages()), 0, 'message expiré : retiré');

reset role;
select is(has_function_privilege('anon', 'public.list_all_favorite_messages()', 'execute'), false,
  'fermé aux visiteurs non connectés');

select * from finish();
rollback;
