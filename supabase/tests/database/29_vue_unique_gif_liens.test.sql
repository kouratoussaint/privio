-- Lot 7.3b — vue unique, GIF, aperçus des liens.
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
  from (values ('a', 'alice_bf', 'Alice'), ('b', 'bob_ouaga', 'Bob'), ('c', 'carla', 'Carla')) as x(p, h, n);

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
create function pg_temp.msg(p_k text) returns record language sql as $$
  select m from public.get_messages(pg_temp.v('ab')::uuid) m where m.id = pg_temp.v(p_k)::uuid $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text)
  to authenticated, service_role;

select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);

-- ---------------------------------------------------------------------------
-- Vue unique (photo)
-- ---------------------------------------------------------------------------
insert into t values ('c1', gen_random_uuid()::text);
insert into t select 'p1', path from public.prepare_photo_message(pg_temp.v('ab')::uuid, pg_temp.v('c1')::uuid);
select lives_ok(format($$ select public.mark_media_view_once(%L) $$, pg_temp.v('c1')), 'vue unique demandée');
reset role;
set local role service_role;
select public.commit_photo_upload(pg_temp.v('p1'), 800, 600, 90000);
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select * from public.send_photo_message(%L, %L, 'légende') $$, pg_temp.v('ab'), pg_temp.v('c1')),
  'P0001', 'BODY_INVALID', 'vue unique : pas de légende');
insert into t select 'v1', id::text from public.send_photo_message(pg_temp.v('ab')::uuid, pg_temp.v('c1')::uuid);
select is((select view_once from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('v1')::uuid), true,
  'message en vue unique');
select is((select media_path from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('v1')::uuid), null,
  'l''expéditrice ne revoit pas le fichier');
select is(private.can_read_photo(pg_temp.v('p1')), false, 'ni par le stockage');
select throws_ok(format($$ select public.open_view_once(%L) $$, pg_temp.v('v1')),
  'P0001', 'VIEW_ONCE_UNAVAILABLE', 'l''expéditrice ne l''ouvre pas');

select pg_temp.as_user('b');
select is((select media_path from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('v1')::uuid), null,
  'avant ouverture : pas de fichier');
select is(private.can_read_photo(pg_temp.v('p1')), false, 'avant ouverture : stockage fermé');
select lives_ok(format($$ select public.open_view_once(%L) $$, pg_temp.v('v1')), 'Bob ouvre');
select is((select media_path from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('v1')::uuid), pg_temp.v('p1'),
  'ouverte : le fichier est lisible');
select is(private.can_read_photo(pg_temp.v('p1')), true, 'ouverte : stockage ouvert');
select is((select opened from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('v1')::uuid), true,
  'marquée ouverte pour Bob');
select pg_temp.as_user('a');
select is((select opened_count from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('v1')::uuid), 1,
  'Alice voit « Ouvert »');
select pg_temp.as_user('b');
select public.close_view_once(pg_temp.v('v1')::uuid);
select is(private.can_read_photo(pg_temp.v('p1')), false, 'fermée : plus lisible');
select throws_ok(format($$ select public.open_view_once(%L) $$, pg_temp.v('v1')),
  'P0001', 'VIEW_ONCE_UNAVAILABLE', 'on ne la rouvre pas');
reset role;
select is((select state from private.media_objects where path = pg_temp.v('p1')), 'purge',
  'tous l''ont fermée : fichier en attente d''effacement');
select is((select media_path from public.messages where id = pg_temp.v('v1')::uuid), null,
  'le message ne pointe plus vers le fichier');

-- Ouverte sans être fermée : plus lisible après 2 minutes.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('c2', gen_random_uuid()::text);
insert into t select 'p2', path from public.prepare_photo_message(pg_temp.v('ab')::uuid, pg_temp.v('c2')::uuid);
select public.mark_media_view_once(pg_temp.v('c2')::uuid);
reset role;
set local role service_role;
select public.commit_photo_upload(pg_temp.v('p2'), 800, 600, 90000);
reset role;
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'v2', id::text from public.send_photo_message(pg_temp.v('ab')::uuid, pg_temp.v('c2')::uuid);
select pg_temp.as_user('b');
select public.open_view_once(pg_temp.v('v2')::uuid);
reset role;
update private.view_once_opens set opened_at = now() - interval '3 minutes' where message_id = pg_temp.v('v2')::uuid;
select pg_temp.as_user('b');
set local role authenticated;
select is(private.can_read_photo(pg_temp.v('p2')), false, 'après 2 minutes : plus lisible');

-- Photo ordinaire : inchangée.
select pg_temp.as_user('a');
insert into t values ('c3', gen_random_uuid()::text);
insert into t select 'p3', path from public.prepare_photo_message(pg_temp.v('ab')::uuid, pg_temp.v('c3')::uuid);
reset role;
set local role service_role;
select public.commit_photo_upload(pg_temp.v('p3'), 800, 600, 90000);
reset role;
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'v3', id::text from public.send_photo_message(pg_temp.v('ab')::uuid, pg_temp.v('c3')::uuid, 'Légende');
select pg_temp.as_user('b');
select is(private.can_read_photo(pg_temp.v('p3')), true, 'photo ordinaire : lisible sans ouverture');
select throws_ok(format($$ select public.open_view_once(%L) $$, pg_temp.v('v3')),
  'P0001', 'VIEW_ONCE_UNAVAILABLE', 'une photo ordinaire n''est pas en vue unique');

-- ---------------------------------------------------------------------------
-- GIF
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
select matches(public.gif_customer_id(), '^[0-9a-f]{32}$', 'identifiant pseudonyme pour KLIPY');
select isnt(public.gif_customer_id(), pg_temp.uid('a')::text, 'jamais l''identifiant Privio');
insert into t values ('g1c', gen_random_uuid()::text);
insert into t select 'g1p', path from public.prepare_gif_message(pg_temp.v('ab')::uuid, pg_temp.v('g1c')::uuid);
select throws_ok(format($$ select public.commit_gif_upload(%L, 200, 200, 1000) $$, pg_temp.v('g1p')),
  '42501', null, 'l''application ne valide pas un GIF elle-même');
select throws_ok(format($$ select * from public.send_gif_message(%L, %L) $$, pg_temp.v('ab'), pg_temp.v('g1c')),
  'P0001', 'MEDIA_NOT_FOUND', 'pas de message sans fichier validé');
reset role;
set local role service_role;
select throws_ok(format($$ select public.commit_gif_upload(%L, 200, 200, 5000000) $$, pg_temp.v('g1p')),
  'P0001', 'MEDIA_TOO_LARGE', 'GIF trop lourd : refusé');
select lives_ok(format($$ select public.commit_gif_upload(%L, 220, 180, 400000) $$, pg_temp.v('g1p')), 'GIF validé');
reset role;
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'g1', id::text from public.send_gif_message(pg_temp.v('ab')::uuid, pg_temp.v('g1c')::uuid);
select is((select kind || ':' || media_width || 'x' || media_height from public.get_messages(pg_temp.v('ab')::uuid)
            where id = pg_temp.v('g1')::uuid), 'gif:220x180', 'message GIF');
select pg_temp.as_user('b');
select is(private.can_read_gif(pg_temp.v('g1p')), true, 'Bob lit le GIF');
select is((select unread_count from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid) >= 1,
  true, 'un GIF compte comme non lu');
select pg_temp.as_user('c');
select is(private.can_read_gif(pg_temp.v('g1p')), false, 'une personne extérieure non');

-- ---------------------------------------------------------------------------
-- Aperçus des liens
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
insert into t select 'l1', id::text from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(),
  'Regarde ça : https://exemple.bf/article?id=3. Bien, non ?');
select is(public.link_preview_target(pg_temp.v('l1')::uuid), 'https://exemple.bf/article?id=3',
  'premier lien, sans la ponctuation finale');
insert into t select 'l2', id::text from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Pas de lien ici');
select is(public.link_preview_target(pg_temp.v('l2')::uuid), null, 'pas de lien : rien');
select pg_temp.as_user('b');
select throws_ok(format($$ select public.link_preview_target(%L) $$, pg_temp.v('l1')),
  'P0001', 'NOT_SENDER', 'seulement pour ses propres messages');
select throws_ok(format($$ select public.save_link_preview(%L, 'https://x', 'Titre', null, null) $$, pg_temp.v('l1')),
  '42501', null, 'l''application n''écrit pas d''aperçu elle-même');
reset role;
set local role service_role;
select lives_ok(format($$ select public.save_link_preview(%L, 'https://exemple.bf/article?id=3', 'Un article',
  'Une description', 'exemple.bf', %L, 400, 210, 30000) $$, pg_temp.v('l1'), pg_temp.v('ab') || '/apercu-1'),
  'aperçu enregistré par le serveur');
reset role;
select pg_temp.as_user('b');
set local role authenticated;
select is((select link_preview ->> 'title' from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('l1')::uuid),
  'Un article', 'Bob voit l''aperçu');
select is(private.can_read_preview(pg_temp.v('ab') || '/apercu-1'), true, 'et son image');
select pg_temp.as_user('a');
select is(public.link_preview_target(pg_temp.v('l1')::uuid), null, 'déjà un aperçu : rien à refaire');
select public.delete_message_for_everyone(pg_temp.v('l1')::uuid);
reset role;
select is((select count(*)::int from private.link_previews where message_id = pg_temp.v('l1')::uuid), 0,
  'supprimé pour tous : aperçu effacé');
select is((select state from private.media_objects where path = pg_temp.v('ab') || '/apercu-1'), 'purge',
  'et son image en attente d''effacement');

select * from finish();
rollback;
