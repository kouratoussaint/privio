-- Lot 7.4 — autocollants personnels : collection pour mon compte (60 au plus, lisible par
-- moi seul), envoi par copie du fichier (s'efface avec le message), corps
-- « perso/partageable » ou « perso/prive », ajout d'un autocollant partageable reçu.
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
grant all on t to authenticated, service_role;
create function pg_temp.as_user(p char) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p || '1',
    'session_id', '00000000-0000-0000-0000-00000000' || repeat(p, 4),
    'role', 'authenticated')::text, true);
$$;
create function pg_temp.uid(p char) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;
create function pg_temp.v(p_k text) returns text language sql as $$ select v from t where k = p_k $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text)
  to authenticated, service_role;

-- Alice et Bob se connaissent.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);

-- ------------------------------------------------------------------ Collection
insert into t select 's1', id::text from public.reserve_sticker(true);
insert into t select 's2', id::text from public.reserve_sticker(false);
select is((select count(*)::int from public.my_stickers()), 0, 'réservé : pas encore dans la collection');
reset role;
select is((select path from private.user_stickers where id = pg_temp.v('s1')::uuid),
  pg_temp.uid('a')::text || '/' || pg_temp.v('s1'), 'fichier rangé sous mon compte');

set local role authenticated;
select throws_ok(format($$ select public.commit_sticker(%L, 512, 512, 1000) $$, pg_temp.v('s1')),
  '42501', null, 'seul le serveur valide un dépôt');
reset role;
set local role service_role;
select throws_ok(format($$ select public.commit_sticker(%L, 1024, 512, 1000) $$, pg_temp.v('s1')),
  'P0001', 'MEDIA_INVALID', '512 px au plus');
select throws_ok(format($$ select public.commit_sticker(%L, 512, 512, 600000) $$, pg_temp.v('s1')),
  'P0001', 'MEDIA_TOO_LARGE', '512 Ko au plus');
select lives_ok(format($$ select public.commit_sticker(%L, 512, 480, 90000) $$, pg_temp.v('s1')),
  'dépôt validé');
select lives_ok(format($$ select public.commit_sticker(%L, 512, 512, 80000) $$, pg_temp.v('s2')),
  'second dépôt validé');
reset role;

select pg_temp.as_user('a');
set local role authenticated;
select results_eq($$ select shareable from public.my_stickers() order by shareable $$,
  $$ values (false), (true) $$, 'Alice retrouve ses deux autocollants');
select ok(private.can_read_sticker(pg_temp.uid('a')::text || '/' || pg_temp.v('s1')),
  'Alice lit son fichier');
reset role;
select pg_temp.as_user('b');
set local role authenticated;
select is((select count(*)::int from public.my_stickers()), 0, 'Bob ne voit pas la collection d''Alice');
select ok(not private.can_read_sticker(pg_temp.uid('a')::text || '/' || pg_temp.v('s1')),
  'Bob ne lit pas la collection d''Alice');
reset role;

-- Limite de 60.
insert into private.user_stickers (owner_id, path, state, width, height, bytes)
select pg_temp.uid('c'), 'c/' || g, 'ready', 10, 10, 10 from generate_series(1, 60) g;
select pg_temp.as_user('c');
set local role authenticated;
select throws_ok($$ select public.reserve_sticker(false) $$, 'P0001', 'STICKER_LIMIT', '60 au plus');
reset role;

-- ------------------------------------------------------------------ Envoi
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'cm', gen_random_uuid()::text;
select throws_ok(format($$ select public.prepare_sticker_message(%L, %L, gen_random_uuid()) $$,
  pg_temp.v('ab'), pg_temp.v('cm')), 'P0001', 'STICKER_NOT_FOUND', 'autocollant inconnu');
insert into t select 'mp', path from public.prepare_sticker_message(pg_temp.v('ab')::uuid,
  pg_temp.v('cm')::uuid, pg_temp.v('s1')::uuid);
select ok(pg_temp.v('mp') like 'msg/' || pg_temp.v('ab') || '/%', 'copie propre au message');
select throws_ok(format($$ select public.send_sticker_message(%L, %L, %L) $$,
  pg_temp.v('ab'), pg_temp.v('cm'), pg_temp.v('s1')), 'P0001', 'MEDIA_NOT_FOUND', 'pas avant la copie');
reset role;
set local role service_role;
select public.commit_sticker_message(pg_temp.v('mp'), 90000);
reset role;
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'm1', id::text from public.send_sticker_message(pg_temp.v('ab')::uuid,
  pg_temp.v('cm')::uuid, pg_temp.v('s1')::uuid);
select is((select body from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('m1')::uuid),
  'perso/partageable', 'autocollant partageable');
select is((select media_width from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('m1')::uuid),
  512, 'dimensions du message');
select is((select id::text from public.send_sticker_message(pg_temp.v('ab')::uuid,
  pg_temp.v('cm')::uuid, pg_temp.v('s1')::uuid)), pg_temp.v('m1'), 'renvoi : même message');
-- Autocollant privé.
insert into t select 'cm2', gen_random_uuid()::text;
insert into t select 'mp2', path from public.prepare_sticker_message(pg_temp.v('ab')::uuid,
  pg_temp.v('cm2')::uuid, pg_temp.v('s2')::uuid);
reset role;
set local role service_role;
select public.commit_sticker_message(pg_temp.v('mp2'), 80000);
reset role;
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'm2', id::text from public.send_sticker_message(pg_temp.v('ab')::uuid,
  pg_temp.v('cm2')::uuid, pg_temp.v('s2')::uuid);
reset role;

-- ------------------------------------------------------------------ Réception
select pg_temp.as_user('b');
set local role authenticated;
select ok(private.can_read_sticker(pg_temp.v('mp')), 'Bob lit l''autocollant reçu');
select throws_ok(format($$ select public.prepare_save_sticker(%L) $$, pg_temp.v('m2')),
  'P0001', 'STICKER_NOT_SHAREABLE', 'autocollant privé : pas d''ajout');
insert into t select 'save', source || '|' || path from public.prepare_save_sticker(pg_temp.v('m1')::uuid);
select is(split_part(pg_temp.v('save'), '|', 1), pg_temp.v('mp'), 'copie depuis le message reçu');
select ok(split_part(pg_temp.v('save'), '|', 2) like pg_temp.uid('b')::text || '/%',
  'rangé dans la collection de Bob');
reset role;
select pg_temp.as_user('c');
set local role authenticated;
select ok(not private.can_read_sticker(pg_temp.v('mp')), 'Carla ne lit pas un autocollant qui ne lui est pas destiné');
reset role;

-- Supprimé pour tous : le fichier du message part à l'effacement.
select pg_temp.as_user('a');
set local role authenticated;
select public.delete_message_for_everyone(pg_temp.v('m2')::uuid);
reset role;
select is((select state from private.media_objects where path = pg_temp.v('mp2')), 'purge',
  'copie du message effacée avec lui');

-- Expiré : plus lisible, fichier effacé.
update public.messages set sent_at = now() - interval '2 hours', expires_at = now() - interval '1 second'
 where id = pg_temp.v('m1')::uuid;
select pg_temp.as_user('b');
set local role authenticated;
select ok(not private.can_read_sticker(pg_temp.v('mp')), 'message expiré : fichier illisible');
reset role;
select private.purge_expired();
select is((select state from private.media_objects where path = pg_temp.v('mp')), 'purge',
  'message effacé : sa copie aussi');
select is((select count(*)::int from private.user_stickers where id = pg_temp.v('s1')::uuid), 1,
  'la collection d''Alice reste');

-- Retirer de ma collection.
select pg_temp.as_user('a');
set local role authenticated;
select is(public.remove_sticker(pg_temp.v('s2')::uuid), pg_temp.uid('a')::text || '/' || pg_temp.v('s2'),
  'retiré : fichier à effacer renvoyé');
reset role;
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok(format($$ select public.remove_sticker(%L) $$, pg_temp.v('s1')),
  'P0001', 'STICKER_NOT_FOUND', 'Bob ne retire pas l''autocollant d''Alice');
select throws_ok($$ select count(*) from private.user_stickers $$, '42501', null, 'table inaccessible');
reset role;

select * from finish();
rollback;
