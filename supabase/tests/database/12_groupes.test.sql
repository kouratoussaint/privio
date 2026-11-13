-- Lot 3.3 — Groupes : invitations acceptées, rôles, restrictions, historique depuis l'arrivée,
-- accusés de groupe, limite de taille, départ, photo de groupe, signalement.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Lot 4.7 : ce fichier ouvre des discussions directement (règles d'avant les demandes de
-- connexion, testées dans 16_demandes_connexion).
insert into private.policies (key, value) values ('connection_requests_required', 'false');

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now()),
  ('00000000-0000-0000-0000-0000000000c1', '22670000003', now()),
  ('00000000-0000-0000-0000-0000000000d1', '22670000004', now()),
  ('00000000-0000-0000-0000-0000000000e1', '22670000005', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-00000000cccc', '00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-00000000dddd', '00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-00000000eeee', '00000000-0000-0000-0000-0000000000e1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob'),
  ('00000000-0000-0000-0000-0000000000c1', 'carla', 'Carla'),
  ('00000000-0000-0000-0000-0000000000d1', 'dani', 'Dani'),
  ('00000000-0000-0000-0000-0000000000e1', 'emma', 'Emma');

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated, service_role;
create function pg_temp.as_user(p char) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p || '1',
    'session_id', '00000000-0000-0000-0000-00000000' || repeat(p, 4),
    'role', 'authenticated')::text, true);
$$;
create function pg_temp.v(p_k text) returns text language sql as $$ select v from t where k = p_k $$;
create function pg_temp.uid(p char) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;
create function pg_temp.inv(p char) returns uuid language sql as $$
  select invitation_id from public.list_my_invitations() limit 1 $$;
create function pg_temp.events() returns text language sql as $$
  select string_agg((body::jsonb) ->> 'e', ',' order by sent_at, id)
    from public.messages where conversation_id = pg_temp.v('g')::uuid and kind = 'system' and body like '{%' $$;
grant execute on function pg_temp.v(text), pg_temp.as_user(char), pg_temp.uid(char), pg_temp.inv(char),
  pg_temp.events() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Création et invitations (acceptation obligatoire)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok($$ select public.create_group('   ') $$, 'P0001', 'GROUP_TITLE_INVALID', 'titre vide : refusé');
insert into t values ('g', public.create_group('Famille', 'Nouvelles de la famille',
  array[pg_temp.uid('b'), pg_temp.uid('c'), pg_temp.uid('a')])::text);
select results_eq(
  format($$ select kind, title, member_count, my_role from public.list_conversations() where conversation_id = %L $$, pg_temp.v('g')),
  $$ values ('group'::text, 'Famille'::text, 1, 'owner'::text) $$,
  'le créateur est propriétaire et seul membre : les invités doivent accepter');
select is(pg_temp.events(), 'created', 'message système : groupe créé');

select pg_temp.as_user('b');
select results_eq($$ select title, inviter_name, member_count from public.list_my_invitations() $$,
  $$ values ('Famille'::text, 'Alice'::text, 1) $$, 'Bob voit l''invitation (titre, qui invite, taille)');
select throws_ok(format($$ select * from public.get_messages(%L) $$, pg_temp.v('g')),
  'P0001', 'NOT_MEMBER', 'avant d''accepter : aucun message lisible');
select is(public.respond_to_invitation(pg_temp.inv('b'), true)::text, pg_temp.v('g'), 'Bob accepte');
select is((select member_count from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid), 2,
  'le groupe compte 2 membres');
select throws_ok(format($$ select public.respond_to_invitation(%L, true) $$, gen_random_uuid()),
  'P0001', 'INVITATION_NOT_FOUND', 'invitation inconnue : refusée');

select pg_temp.as_user('c');
select is(public.respond_to_invitation(pg_temp.inv('c'), false), null, 'Carla refuse');
select is_empty($$ select * from public.list_my_invitations() $$, 'invitation refusée : plus proposée');
select ok(not private.is_member(pg_temp.v('g')::uuid, pg_temp.uid('c')), 'refus : Carla n''est pas membre');

-- ---------------------------------------------------------------------------
-- Historique : un nouveau membre ne voit que les messages postérieurs à son arrivée
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
insert into t select 'old', id::text from public.send_message(pg_temp.v('g')::uuid, gen_random_uuid(), 'Avant Dani');
reset role;
update public.messages set sent_at = now() - interval '1 minute', expires_at = expires_at - interval '1 minute'
 where id = pg_temp.v('old')::uuid;
update public.conversation_members set joined_at = now() - interval '2 minutes'
 where conversation_id = pg_temp.v('g')::uuid;
select pg_temp.as_user('a');
set local role authenticated;
select is(public.invite_to_group(pg_temp.v('g')::uuid, array[pg_temp.uid('d')]), 1, 'Alice invite Dani');
select pg_temp.as_user('d');
select lives_ok($$ select public.respond_to_invitation(pg_temp.inv('d'), true) $$, 'Dani accepte');
select is((select count(*)::int from public.get_messages(pg_temp.v('g')::uuid) where kind <> 'system'), 0,
  'Dani ne voit aucun message antérieur à son arrivée');
select ok(not private.can_see_message(pg_temp.v('g')::uuid, now() - interval '1 minute', pg_temp.uid('d')),
  'même règle pour la RLS et les fichiers');
select is((select count(*)::int from public.messages where id = pg_temp.v('old')::uuid), 0,
  'RLS : lecture directe de l''ancien message impossible');
select pg_temp.as_user('b');
select is((select count(*)::int from public.get_messages(pg_temp.v('g')::uuid) where body = 'Avant Dani'), 1,
  'Bob (déjà membre) voit le message');

-- ---------------------------------------------------------------------------
-- Restrictions et informations
-- ---------------------------------------------------------------------------
select throws_ok(format($$ select public.set_group_settings(%L, 'admins') $$, pg_temp.v('g')),
  'P0001', 'NOT_ADMIN', 'un membre ne change pas les réglages');
select throws_ok(format($$ select public.update_group_info(%L, 'Piraté') $$, pg_temp.v('g')),
  'P0001', 'NOT_ADMIN', 'par défaut, seuls les administrateurs modifient les informations');
select throws_ok(format($$ select public.set_conversation_ttl(%L, 3600) $$, pg_temp.v('g')),
  'P0001', 'NOT_ADMIN', 'ni la durée des messages');
select pg_temp.as_user('a');
select lives_ok(format($$ select public.set_group_settings(%L, 'admins') $$, pg_temp.v('g')),
  'Alice réserve la publication aux administrateurs');
select pg_temp.as_user('b');
select throws_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), 'Salut') $$, pg_temp.v('g')),
  'P0001', 'POSTING_RESTRICTED', 'un membre ne peut plus écrire');
select throws_ok(format($$ select * from public.prepare_photo_message(%L, gen_random_uuid()) $$, pg_temp.v('g')),
  'P0001', 'POSTING_RESTRICTED', 'ni envoyer de photo');
select is((public.get_photo_quota() ->> 'used')::int, 0, 'photo refusée : rien n''est débité');
select pg_temp.as_user('a');
select lives_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), 'Annonce') $$, pg_temp.v('g')),
  'l''administrateur écrit toujours');
select lives_ok(format($$ select public.update_group_info(%L, 'Famille Ouédraogo', 'Toute la famille') $$, pg_temp.v('g')),
  'Alice renomme le groupe');
select lives_ok(format($$ select public.set_group_settings(%L, 'all', 'all') $$, pg_temp.v('g')),
  'Alice rouvre la publication et la modification des informations');
select pg_temp.as_user('b');
select lives_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), 'Merci') $$, pg_temp.v('g')),
  'Bob écrit de nouveau');
select lives_ok(format($$ select public.update_group_info(%L, null, 'Description de Bob') $$, pg_temp.v('g')),
  'réglage « tous » : un membre modifie la description');
select ok(pg_temp.events() like 'created,joined,joined,posting,title,description,posting,info_editing,description',
  'chaque événement est annoncé par un message système : ' || pg_temp.events());

-- ---------------------------------------------------------------------------
-- Rôles
-- ---------------------------------------------------------------------------
select throws_ok(format($$ select public.set_member_role(%L, %L, 'admin') $$, pg_temp.v('g'), pg_temp.uid('d')),
  'P0001', 'NOT_ADMIN', 'un membre ne nomme personne');
select pg_temp.as_user('a');
select lives_ok(format($$ select public.set_member_role(%L, %L, 'admin') $$, pg_temp.v('g'), pg_temp.uid('b')),
  'Alice nomme Bob administrateur');
select pg_temp.as_user('b');
select lives_ok(format($$ select public.set_member_role(%L, %L, 'admin') $$, pg_temp.v('g'), pg_temp.uid('d')),
  'un administrateur nomme un autre administrateur');
select throws_ok(format($$ select public.set_member_role(%L, %L, 'member') $$, pg_temp.v('g'), pg_temp.uid('d')),
  'P0001', 'NOT_OWNER', 'seul le propriétaire retire le rôle d''administrateur');
select throws_ok(format($$ select public.remove_group_member(%L, %L) $$, pg_temp.v('g'), pg_temp.uid('d')),
  'P0001', 'NOT_OWNER', 'un administrateur ne retire pas un autre administrateur');
select throws_ok(format($$ select public.remove_group_member(%L, %L) $$, pg_temp.v('g'), pg_temp.uid('a')),
  'P0001', 'ROLE_INVALID', 'personne ne retire le propriétaire');
select pg_temp.as_user('a');
select lives_ok(format($$ select public.set_member_role(%L, %L, 'member') $$, pg_temp.v('g'), pg_temp.uid('d')),
  'le propriétaire retire le rôle de Dani');
select results_eq(
  format($$ select display_name, role from public.get_conversation_members(%L) where not invited $$, pg_temp.v('g')),
  $$ values ('Alice'::text, 'owner'::text), ('Bob', 'admin'), ('Dani', 'member') $$,
  'membres et rôles (propriétaire, administrateurs, membres)');

-- Modération : un administrateur supprime le message d'un membre pour tous.
select pg_temp.as_user('d');
insert into t select 'dm', id::text from public.send_message(pg_temp.v('g')::uuid, gen_random_uuid(), 'Pub interdite');
select pg_temp.as_user('b');
select lives_ok(format($$ select public.delete_message_for_everyone(%L) $$, pg_temp.v('dm')),
  'un administrateur supprime le message d''un membre pour tous');
select pg_temp.as_user('d');
select throws_ok(format($$ select public.delete_message_for_everyone(%L) $$,
  (select id from public.get_messages(pg_temp.v('g')::uuid) where body = 'Merci')),
  'P0001', 'NOT_SENDER', 'un membre ne supprime pas le message d''un autre');

-- Retrait d'un membre : plus aucun accès.
select pg_temp.as_user('b');
select lives_ok(format($$ select public.remove_group_member(%L, %L) $$, pg_temp.v('g'), pg_temp.uid('d')),
  'un administrateur retire un membre');
select pg_temp.as_user('d');
select throws_ok(format($$ select * from public.get_messages(%L) $$, pg_temp.v('g')),
  'P0001', 'NOT_MEMBER', 'membre retiré : plus aucun message');
select is((select count(*)::int from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid), 0,
  'membre retiré : le groupe disparaît de sa liste');

-- ---------------------------------------------------------------------------
-- Invitations : blocages, limite de taille, liste des administrateurs
-- ---------------------------------------------------------------------------
reset role;
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('e'), pg_temp.uid('a'));
select pg_temp.as_user('a');
set local role authenticated;
select is(public.invite_to_group(pg_temp.v('g')::uuid, array[pg_temp.uid('e')]), 0,
  'personne bloquée : aucune invitation (sans le révéler)');
select is(public.invite_to_group(pg_temp.v('g')::uuid, array[pg_temp.uid('c')]), 1, 'Carla réinvitée');
select is((select count(*)::int from public.get_conversation_members(pg_temp.v('g')::uuid) where invited), 1,
  'les administrateurs voient les invitations en attente');
select pg_temp.as_user('b');
reset role;
insert into private.policies (key, value) values ('group_max_members', '2');
select pg_temp.as_user('c');
set local role authenticated;
select throws_ok($$ select public.respond_to_invitation(pg_temp.inv('c'), true) $$,
  'P0001', 'GROUP_FULL', 'groupe complet (limite administrable) : acceptation refusée');
select pg_temp.as_user('a');
select throws_ok(format($$ select public.invite_to_group(%L, array[%L]::uuid[]) $$, pg_temp.v('g'), pg_temp.uid('d')),
  'P0001', 'GROUP_FULL', 'groupe complet : invitation refusée');
reset role;
update private.policies set value = '100' where key = 'group_max_members';
select pg_temp.as_user('c');
set local role authenticated;
select lives_ok($$ select public.respond_to_invitation(pg_temp.inv('c'), true) $$, 'limite relevée : Carla entre');

-- ---------------------------------------------------------------------------
-- Accusés de groupe : « lu » quand TOUS les autres l'ont lu
-- ---------------------------------------------------------------------------
-- (Dans ce test, tout se passe dans une seule transaction : on vieillit les messages
--  précédents pour que « Qui vient ? » soit bien le dernier.)
reset role;
update public.messages set sent_at = sent_at - interval '10 minutes', expires_at = expires_at - interval '10 minutes'
 where conversation_id = pg_temp.v('g')::uuid;
update public.conversation_members set joined_at = joined_at - interval '10 minutes'
 where conversation_id = pg_temp.v('g')::uuid;
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'm1', sent_at::text from public.send_message(pg_temp.v('g')::uuid, gen_random_uuid(), 'Qui vient ?');
select pg_temp.as_user('b');
select public.mark_conversation(pg_temp.v('g')::uuid, null, pg_temp.v('m1')::timestamptz);
select pg_temp.as_user('a');
select is((select peer_read_up_to from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid), null,
  'lu par Bob seulement : pas encore « lu »');
select pg_temp.as_user('c');
select public.mark_conversation(pg_temp.v('g')::uuid, null, pg_temp.v('m1')::timestamptz);
select pg_temp.as_user('a');
select ok((select peer_read_up_to >= pg_temp.v('m1')::timestamptz from public.list_conversations()
            where conversation_id = pg_temp.v('g')::uuid), 'lu par tous : « lu »');
select is((select last_sender_name from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid),
  null, 'son propre dernier message : pas de nom');
select pg_temp.as_user('c');
select is((select last_sender_name from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid),
  'Alice', 'dernier message d''un autre : son nom pour l''aperçu');
select is((select sender_name from public.get_messages(pg_temp.v('g')::uuid) where body = 'Qui vient ?'),
  'Alice', 'chaque message porte le nom de son expéditeur');

-- ---------------------------------------------------------------------------
-- Sourdine, signalement, photo de groupe
-- ---------------------------------------------------------------------------
select lives_ok(format($$ select public.set_conversation_mute(%L, now() + interval '8 hours') $$, pg_temp.v('g')),
  'mettre le groupe en sourdine 8 h');
select ok((select muted_until > now() from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid),
  'sourdine visible dans la liste');
select public.set_conversation_mute(pg_temp.v('g')::uuid, null);
select is((select muted_until from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid), null,
  'sourdine levée');
select lives_ok(format($$ select public.report('spam', null, %L) $$, pg_temp.v('g')), 'un membre signale le groupe');
select pg_temp.as_user('e');
select throws_ok(format($$ select public.report('spam', null, %L) $$, pg_temp.v('g')),
  'P0001', 'REPORT_INVALID', 'une personne extérieure ne peut pas le signaler');

select pg_temp.as_user('a');
select lives_ok(format($$ select public.set_group_settings(%L, null, 'admins') $$, pg_temp.v('g')),
  'informations de nouveau réservées aux administrateurs');
select pg_temp.as_user('c');
select throws_ok(format($$ select public.prepare_group_avatar_upload(%L) $$, pg_temp.v('g')),
  'P0001', 'NOT_ADMIN', 'un membre ne change pas la photo du groupe');
select pg_temp.as_user('a');
insert into t values ('ga1', public.prepare_group_avatar_upload(pg_temp.v('g')::uuid));
select matches(pg_temp.v('ga1'), '^groups/' || pg_temp.v('g') || '/[0-9a-f-]{36}\.jpg$', 'photo de groupe rangée sous le groupe');
reset role;
set local role service_role;
select throws_ok(format($$ select public.commit_avatar(%L, 400, 400, 1000) $$, pg_temp.v('ga1')),
  'P0001', 'MEDIA_NOT_FOUND', 'une photo de groupe ne devient jamais une photo de profil');
select lives_ok(format($$ select public.commit_group_avatar(%L, 400, 400, 30000) $$, pg_temp.v('ga1')),
  'photo de groupe validée');
reset role;
select pg_temp.as_user('c');
set local role authenticated;
select ok(private.can_read_avatar(pg_temp.v('ga1')), 'un membre voit la photo du groupe');
select is((select avatar_path from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid),
  pg_temp.v('ga1'), 'la liste donne la photo du groupe');
select pg_temp.as_user('e');
select ok(not private.can_read_avatar(pg_temp.v('ga1')), 'une personne extérieure ne la voit pas');
select pg_temp.as_user('a');
select lives_ok(format($$ select public.remove_group_avatar(%L) $$, pg_temp.v('g')), 'photo de groupe retirée');
reset role;
select is((select state from private.media_objects where path = pg_temp.v('ga1')), 'purge', 'ancienne photo effacée');

-- ---------------------------------------------------------------------------
-- Départ du propriétaire, suppression de compte, discussion 1:1
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select lives_ok(format($$ select public.leave_group(%L) $$, pg_temp.v('g')), 'la propriétaire quitte le groupe');
select pg_temp.as_user('b');
select is((select my_role from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid), 'owner',
  'le plus ancien administrateur devient propriétaire');
select ok(pg_temp.events() like '%,left,owner_changed', 'départ et nouveau propriétaire annoncés');
reset role;
delete from auth.users where id = pg_temp.uid('b');
select is((select user_id from public.conversation_members
            where conversation_id = pg_temp.v('g')::uuid and role = 'owner' and left_at is null),
  pg_temp.uid('c'), 'compte du propriétaire supprimé : le groupe garde un propriétaire');

select pg_temp.as_user('c');
set local role authenticated;
insert into t values ('dc', public.start_direct_conversation(pg_temp.uid('d'))::text);
select throws_ok(format($$ select public.leave_group(%L) $$, pg_temp.v('dc')),
  'P0001', 'NOT_GROUP', 'une discussion 1:1 ne se « quitte » pas');
select is((select kind from public.list_conversations() where conversation_id = pg_temp.v('dc')::uuid), 'direct',
  'les discussions 1:1 restent inchangées');

select * from finish();
rollback;
