-- Lot 7.3a — autocollants Privio.
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


select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t select 's1', id::text from public.send_sticker(pg_temp.v('ab')::uuid, gen_random_uuid(), 'privio/merci');
select is((select kind || ':' || body from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('s1')::uuid),
  'sticker:privio/merci', 'autocollant envoyé : type et nom');
select throws_ok(format($$ select * from public.send_sticker(%L, gen_random_uuid(), 'https://exemple.com/x.png') $$, pg_temp.v('ab')),
  'P0001', 'BODY_INVALID', 'un nom d''autocollant invalide est refusé');
select throws_ok(format($$ select * from public.send_sticker(%L, gen_random_uuid(), '') $$, pg_temp.v('ab')),
  'P0001', 'BODY_INVALID', 'vide : refusé');
select throws_ok(format($$ select public.edit_message(%L, 'privio/bravo') $$, pg_temp.v('s1')),
  'P0001', 'MESSAGE_NOT_EDITABLE', 'un autocollant ne se modifie pas');

select pg_temp.as_user('b');
select is((select unread_count from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid), 1,
  'compte comme non lu');
select is((select last_kind from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid), 'sticker',
  'aperçu de la liste : autocollant');
insert into t select 'r1', id::text from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Merci à toi', pg_temp.v('s1')::uuid);
select is((select reply_kind from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('r1')::uuid), 'sticker',
  'on peut répondre à un autocollant');
select lives_ok(format($$ select public.set_reaction(%L, '❤️') $$, pg_temp.v('s1')), 'réagir à un autocollant');

select pg_temp.as_user('a');
select lives_ok(format($$ select public.delete_message_for_everyone(%L) $$, pg_temp.v('s1')),
  'supprimer pour tout le monde');
select is((select deleted_at is not null and body is null from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('s1')::uuid),
  true, 'supprimé : plus de nom d''autocollant');

select pg_temp.as_user('c');
select throws_ok(format($$ select * from public.send_sticker(%L, gen_random_uuid(), 'privio/merci') $$, pg_temp.v('ab')),
  'P0001', 'NOT_MEMBER', 'une personne extérieure ne peut pas en envoyer');

select * from finish();
rollback;
