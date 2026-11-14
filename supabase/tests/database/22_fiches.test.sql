-- Lot 7.1a — Fiches : « À propos » (réglage « Qui voit mon À propos », contacts par défaut),
-- fiche d'un contact, groupes en commun, médias encore présents dans une discussion.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now()),
  ('00000000-0000-0000-0000-0000000000c1', '22670000003', now()),
  ('00000000-0000-0000-0000-0000000000d1', '22670000004', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-00000000cccc', '00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-00000000dddd', '00000000-0000-0000-0000-0000000000d1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob'),
  ('00000000-0000-0000-0000-0000000000c1', 'carla', 'Carla'),
  ('00000000-0000-0000-0000-0000000000d1', 'dani', 'Dani');

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

-- Alice et Bob : une discussion ; Alice, Bob et Carla : un groupe ; Dani : aucun lien.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t values ('g', public.create_group('Voisins', null, array[pg_temp.uid('b'), pg_temp.uid('c')])::text);
select pg_temp.as_user('b');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
select pg_temp.as_user('c');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);

-- ---------------------------------------------------------------------------
-- À propos
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
select is(public.set_my_about('  Au travail   jusqu''à 18 h  '), 'Au travail jusqu''à 18 h', 'espaces nettoyés');
select throws_ok(format($$ select public.set_my_about(%L) $$, repeat('x', 141)), 'P0001', 'ABOUT_TOO_LONG',
  '141 caractères : refusé');
select is((select about_visibility from public.get_my_privacy()), 'contacts', 'par défaut : mes contacts');

select pg_temp.as_user('b');
select is((select about from public.get_contact_profile(pg_temp.uid('a'))), 'Au travail jusqu''à 18 h',
  'Bob (contact) voit l''À propos d''Alice');
select pg_temp.as_user('c');
select is((select about from public.get_contact_profile(pg_temp.uid('a'))), null,
  'Carla (même groupe, pas contact) ne le voit pas');
select is((select handle from public.get_contact_profile(pg_temp.uid('a'))), 'alice_bf',
  'Carla voit quand même le nom et l''identifiant');
select pg_temp.as_user('d');
select is_empty(format($$ select * from public.get_contact_profile(%L) $$, pg_temp.uid('a')),
  'Dani (aucune discussion commune) : rien');

select pg_temp.as_user('a');
select public.set_my_privacy('contacts', true, true, 'everyone', 'everyone', null, 'everyone');
select pg_temp.as_user('c');
select is((select about from public.get_contact_profile(pg_temp.uid('a'))), 'Au travail jusqu''à 18 h',
  '« Tout le monde » : Carla le voit');
select pg_temp.as_user('a');
select public.set_my_privacy('contacts', true, true, 'everyone', 'everyone', null);
select is((select about_visibility from public.get_my_privacy()), 'everyone',
  'ancienne version (sans le réglage) : inchangé');
select public.set_my_privacy('contacts', true, true, 'everyone', 'everyone', null, 'nobody');
select pg_temp.as_user('b');
select is((select about from public.get_contact_profile(pg_temp.uid('a'))), null, '« Personne » : caché');
select throws_ok($$ select public.set_my_privacy('contacts', true, true, 'everyone', 'everyone', null, 'amis') $$,
  'P0001', 'PRIVACY_SETTING_INVALID', 'valeur inconnue refusée');
select pg_temp.as_user('a');
select is((select about from public.get_contact_profile(pg_temp.uid('a'))), 'Au travail jusqu''à 18 h',
  'on voit toujours son propre À propos');

-- Blocage : plus rien de visible.
reset role;
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('a'), pg_temp.uid('b'));
update private.privacy_settings set about_visibility = 'everyone' where user_id = pg_temp.uid('a');
select pg_temp.as_user('b');
set local role authenticated;
select is((select about from public.get_contact_profile(pg_temp.uid('a'))), null, 'bloqué : À propos caché');
reset role;
delete from public.blocks;

-- ---------------------------------------------------------------------------
-- Groupes en commun
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select results_eq(format($$ select title, member_count from public.list_common_groups(%L) $$, pg_temp.uid('b')),
  $$ values ('Voisins'::text, 3) $$, 'Alice et Bob : « Voisins »');
select is_empty(format($$ select * from public.list_common_groups(%L) $$, pg_temp.uid('d')),
  'Alice et Dani : aucun');
select pg_temp.as_user('d');
select is_empty(format($$ select * from public.list_common_groups(%L) $$, pg_temp.uid('b')),
  'Dani ne découvre pas les groupes des autres');

-- ---------------------------------------------------------------------------
-- Médias de la discussion
-- ---------------------------------------------------------------------------
reset role;
insert into public.messages (id, conversation_id, sender_id, client_msg_id, kind, sent_at, expires_at,
                             media_path, media_width, media_height)
values ('00000000-0000-0000-0000-00000000f001', pg_temp.v('ab')::uuid, pg_temp.uid('a'), gen_random_uuid(),
        'photo', now(), now() + interval '1 hour', 'photos/ab/1.jpg', 800, 600);
insert into public.messages (id, conversation_id, sender_id, client_msg_id, kind, sent_at, expires_at,
                             media_path, media_duration_ms)
values ('00000000-0000-0000-0000-00000000f002', pg_temp.v('ab')::uuid, pg_temp.uid('b'), gen_random_uuid(),
        'voice', now() - interval '1 minute', now() + interval '1 hour', 'voice/ab/1.m4a', 12000);
insert into public.messages (id, conversation_id, sender_id, client_msg_id, kind, sent_at, expires_at,
                             deleted_at)
values ('00000000-0000-0000-0000-00000000f003', pg_temp.v('ab')::uuid, pg_temp.uid('a'), gen_random_uuid(),
        'photo', now(), now() + interval '1 hour', now());
select pg_temp.as_user('a');
set local role authenticated;
select results_eq(format($$ select kind, media_path from public.list_conversation_media(%L) $$, pg_temp.v('ab')),
  $$ values ('photo'::text, 'photos/ab/1.jpg'::text), ('voice'::text, 'voice/ab/1.m4a'::text) $$,
  'photo et vocal présents (le supprimé n''y est pas), du plus récent au plus ancien');
select pg_temp.as_user('c');
select throws_ok(format($$ select * from public.list_conversation_media(%L) $$, pg_temp.v('ab')),
  'P0001', 'NOT_MEMBER', 'hors de la discussion : refusé');

select * from finish();
rollback;
