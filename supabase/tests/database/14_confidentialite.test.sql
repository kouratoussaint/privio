-- Lot 4.3 — Confidentialité avancée (photo, présence, accusés, écriture, invitations, durée
-- par défaut) et « vider une discussion » (chez moi ; pour tous avec accord ; groupe : admin).
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
  ('00000000-0000-0000-0000-0000000000d1', '22670000004', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-00000000cccc', '00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-00000000dddd', '00000000-0000-0000-0000-0000000000d1');
insert into public.profiles (id, handle, display_name, avatar_path) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice', 'a1/photo.jpg'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob', null),
  ('00000000-0000-0000-0000-0000000000c1', 'carla', 'Carla', null),
  ('00000000-0000-0000-0000-0000000000d1', 'dani', 'Dani', null);

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
-- Réglages complets en une ligne : présence, accusés, écriture, photo, invitations, durée.
create function pg_temp.privacy(pr text, rr boolean, ty boolean, av text, gi text, ttl integer)
returns void language sql as $$ select public.set_my_privacy(pr, rr, ty, av, gi, ttl) $$;
grant execute on function pg_temp.v(text), pg_temp.as_user(char), pg_temp.uid(char),
  pg_temp.privacy(text, boolean, boolean, text, text, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Réglages : valeurs par défaut, validation
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select results_eq($$ select * from public.get_my_privacy() $$,
  $$ values ('contacts'::text, true, true, 'everyone'::text, 'everyone'::text, null::integer) $$,
  'par défaut : présence aux contacts, accusés et écriture actifs, photo et invitations ouvertes');
select throws_ok($$ select pg_temp.privacy('amis', true, true, 'everyone', 'everyone', null) $$,
  'P0001', 'PRIVACY_SETTING_INVALID', 'valeur inconnue : refusée');
select throws_ok($$ select pg_temp.privacy('everyone', null, true, 'everyone', 'everyone', null) $$,
  'P0001', 'PRIVACY_SETTING_INVALID', 'valeur manquante : refusée');
select throws_ok($$ select pg_temp.privacy('everyone', true, true, 'everyone', 'everyone', 60) $$,
  'P0001', 'TTL_INVALID', 'durée par défaut sous le minimum : refusée');
select throws_ok($$ select pg_temp.privacy('everyone', true, true, 'everyone', 'everyone', 80 * 3600) $$,
  'P0001', 'TTL_INVALID', 'durée par défaut au-delà de 72 h : refusée');

-- ---------------------------------------------------------------------------
-- Photo de profil : tout le monde / mes contacts / personne
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
select is((select avatar_path from public.find_user_by_handle('alice_bf')), 'a1/photo.jpg',
  '« tout le monde » : Bob voit la photo d''Alice dans la recherche');
select pg_temp.as_user('a');
select pg_temp.privacy('contacts', true, true, 'contacts', 'everyone', null);
select pg_temp.as_user('b');
select is((select avatar_path from public.find_user_by_handle('alice_bf')), null,
  '« mes contacts » : pas de photo pour un inconnu');
select ok(not private.can_read_avatar('a1/photo.jpg'), '« mes contacts » : fichier illisible pour un inconnu');
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('a'))::text);
select is((select avatar_path from public.find_user_by_handle('alice_bf')), 'a1/photo.jpg',
  'une discussion à deux existe : Bob est un contact, la photo apparaît');
select is((select peer_avatar_path from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  'a1/photo.jpg', 'photo visible aussi dans la liste des discussions');
select ok(private.can_read_avatar('a1/photo.jpg'), 'fichier lisible par un contact');
select pg_temp.as_user('c');
select ok(not private.can_read_avatar('a1/photo.jpg'), 'Carla (pas contact) : fichier illisible');
select pg_temp.as_user('a');
select pg_temp.privacy('contacts', true, true, 'nobody', 'everyone', null);
select ok(private.can_read_avatar('a1/photo.jpg'), '« personne » : Alice voit toujours sa propre photo');
select pg_temp.as_user('b');
select is((select peer_avatar_path from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  null, '« personne » : même un contact ne voit plus la photo');
select ok(not private.can_read_avatar('a1/photo.jpg'), '« personne » : fichier illisible pour un contact');

-- ---------------------------------------------------------------------------
-- Présence (« en ligne », « vu à »), non réciproque
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
select lives_ok($$ select public.touch_presence(true) $$, 'Alice signale qu''elle est en ligne');
select pg_temp.as_user('b');
select results_eq(format($$ select visible, online from public.get_presence(%L) $$, pg_temp.uid('a')),
  $$ values (true, true) $$, '« mes contacts » : Bob voit Alice en ligne');
select pg_temp.as_user('c');
select results_eq(format($$ select visible, online, last_seen_at from public.get_presence(%L) $$, pg_temp.uid('a')),
  $$ values (false, false, null::timestamptz) $$, 'Carla, sans discussion commune : rien');
-- Carla rejoint un groupe avec Alice : « tout le monde » la laisse voir, « mes contacts » non.
select pg_temp.as_user('a');
insert into t values ('g', public.create_group('Voisins', null, array[pg_temp.uid('c'), pg_temp.uid('b')])::text);
select pg_temp.as_user('c');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
select is((select visible from public.get_presence(pg_temp.uid('a'))), false,
  'groupe commun mais pas contact : « mes contacts » cache la présence');
select pg_temp.as_user('a');
select pg_temp.privacy('everyone', true, true, 'nobody', 'everyone', null);
select pg_temp.as_user('c');
select is((select visible from public.get_presence(pg_temp.uid('a'))), true,
  '« tout le monde » : visible des personnes avec qui l''on partage un groupe');
select pg_temp.as_user('a');
select public.touch_presence(false);
select pg_temp.as_user('b');
select results_eq(format($$ select online, last_seen_at is not null from public.get_presence(%L) $$, pg_temp.uid('a')),
  $$ values (false, true) $$, 'application fermée : plus en ligne, « vu à » connu');
select pg_temp.as_user('a');
select pg_temp.privacy('nobody', true, true, 'nobody', 'everyone', null);
select pg_temp.as_user('b');
select is((select visible from public.get_presence(pg_temp.uid('a'))), false, '« personne » : statut caché');
-- Non réciproque : Alice cache tout mais voit toujours Bob.
select public.touch_presence(true);
select pg_temp.as_user('a');
select is((select online from public.get_presence(pg_temp.uid('b'))), true,
  'non réciproque : Alice (cachée) voit quand même Bob en ligne');
select is((select visible from public.get_presence(pg_temp.uid('a'))), false, 'pas de statut pour soi-même');

-- ---------------------------------------------------------------------------
-- Accusés de lecture
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
insert into t select 'm1', id::text from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Bonjour');
select pg_temp.as_user('b');
select public.mark_conversation(pg_temp.v('ab')::uuid, now(), now());
select pg_temp.as_user('a');
select ok((select peer_read_up_to is not null from public.list_conversations()
            where conversation_id = pg_temp.v('ab')::uuid), 'accusés actifs : Alice voit « lu »');
select pg_temp.as_user('b');
select pg_temp.privacy('contacts', false, true, 'everyone', 'everyone', null);
select pg_temp.as_user('a');
select results_eq(format($$ select peer_delivered_up_to is not null, peer_read_up_to is null
                              from public.list_conversations() where conversation_id = %L $$, pg_temp.v('ab')),
  $$ values (true, true) $$, 'Bob coupe ses accusés : « reçu » reste, « lu » disparaît');
select pg_temp.as_user('a');
select public.mark_conversation(pg_temp.v('ab')::uuid, now(), now());
select pg_temp.as_user('b');
select ok((select peer_read_up_to is not null from public.list_conversations()
            where conversation_id = pg_temp.v('ab')::uuid), 'non réciproque : Bob voit toujours « lu » d''Alice');

-- ---------------------------------------------------------------------------
-- Indicateur d'écriture
-- ---------------------------------------------------------------------------
reset role;
insert into t values ('typing0', (select count(*) from private.rate_limit_hits)::text);
set local role authenticated;
select pg_temp.as_user('b');
select pg_temp.privacy('contacts', false, false, 'everyone', 'everyone', null);
select lives_ok(format($$ select public.signal_typing(%L) $$, pg_temp.v('ab')),
  'écriture désactivée : l''appel réussit sans rien envoyer');
reset role;
select is((select count(*) from private.rate_limit_hits)::text, pg_temp.v('typing0'),
  'aucun signal émis (rien n''est même compté)');
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Invitations dans les groupes
-- ---------------------------------------------------------------------------
select pg_temp.as_user('d');
select pg_temp.privacy('contacts', true, true, 'everyone', 'nobody', null);
select pg_temp.as_user('a');
select is(public.invite_to_group(pg_temp.v('g')::uuid, array[pg_temp.uid('d')]), 0,
  '« personne » : Dani n''est pas invitée (sans le révéler)');
select pg_temp.as_user('d');
select pg_temp.privacy('contacts', true, true, 'everyone', 'contacts', null);
select pg_temp.as_user('a');
select is(public.invite_to_group(pg_temp.v('g')::uuid, array[pg_temp.uid('d')]), 0,
  '« mes contacts » : pas d''invitation sans discussion à deux');
select public.start_direct_conversation(pg_temp.uid('d'));
select is(public.invite_to_group(pg_temp.v('g')::uuid, array[pg_temp.uid('d')]), 1,
  '« mes contacts » : invitation possible après une discussion à deux');

-- ---------------------------------------------------------------------------
-- Durée par défaut des nouvelles discussions
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c');
select pg_temp.privacy('contacts', true, true, 'everyone', 'everyone', 3600);
insert into t values ('cd', public.start_direct_conversation(pg_temp.uid('d'))::text);
select is((select ttl_seconds from public.list_conversations() where conversation_id = pg_temp.v('cd')::uuid),
  3600, 'nouvelle discussion : durée par défaut de Carla (1 h)');
insert into t values ('g2', public.create_group('Club', null, '{}')::text);
select is((select ttl_seconds from public.list_conversations() where conversation_id = pg_temp.v('g2')::uuid),
  3600, 'nouveau groupe : même durée par défaut');
select pg_temp.as_user('b');
select is((select ttl_seconds from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  259200, 'discussion existante (Alice et Bob) : durée inchangée (72 h)');
select pg_temp.as_user('c');

-- ---------------------------------------------------------------------------
-- Vider chez moi
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
insert into t select 'm2', id::text from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Salut Alice');
reset role;
update public.messages set sent_at = sent_at - interval '10 minutes',
       expires_at = expires_at - interval '10 minutes', updated_at = now() - interval '10 minutes'
 where conversation_id = pg_temp.v('ab')::uuid;
set local role authenticated;
select pg_temp.as_user('a');
select is((select count(*)::int from public.get_messages(pg_temp.v('ab')::uuid)), 2, 'avant : 2 messages');
select is(public.clear_conversation(pg_temp.v('ab')::uuid, 'me'), 'cleared', 'Alice vide chez elle');
select is((select count(*)::int from public.get_messages(pg_temp.v('ab')::uuid)), 0, 'chez Alice : vide');
select results_eq(format($$ select last_message_id is null, cleared_before is not null, unread_count
                              from public.list_conversations() where conversation_id = %L $$, pg_temp.v('ab')),
  $$ values (true, true, 0) $$, 'liste : plus d''aperçu, date de vidage connue, rien à lire');
select pg_temp.as_user('b');
select is((select count(*)::int from public.get_messages(pg_temp.v('ab')::uuid)), 2,
  'chez Bob : les 2 messages restent');
select is((select cleared_before from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  null, 'Bob n''a rien vidé');
select public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Tu es là ?');
select pg_temp.as_user('a');
select is((select count(*)::int from public.get_messages(pg_temp.v('ab')::uuid)), 1,
  'un nouveau message après le vidage apparaît chez Alice');

-- ---------------------------------------------------------------------------
-- Vider pour nous deux : demande, refus, annulation, accord
-- ---------------------------------------------------------------------------
select throws_ok(format($$ select public.clear_conversation(%L, 'tout') $$, pg_temp.v('ab')),
  'P0001', 'CLEAR_SCOPE_INVALID', 'portée inconnue : refusée');
select is(public.clear_conversation(pg_temp.v('ab')::uuid, 'everyone'), 'requested', 'Alice demande l''accord de Bob');
select is(public.clear_conversation(pg_temp.v('ab')::uuid, 'everyone'), 'requested', 'redemander : sans effet');
select is((select clear_request_by from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  pg_temp.uid('a'), 'Alice voit sa demande en attente');
select throws_ok(format($$ select public.respond_clear_request(%L, true) $$, pg_temp.v('ab')),
  'P0001', 'CLEAR_REQUEST_NOT_FOUND', 'on ne répond pas à sa propre demande');
select pg_temp.as_user('b');
select is((select clear_request_by from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  pg_temp.uid('a'), 'Bob voit la demande d''Alice');
select is(public.respond_clear_request(pg_temp.v('ab')::uuid, false), 'refused', 'Bob refuse');
select is((select count(*)::int from public.get_messages(pg_temp.v('ab')::uuid)), 3, 'refus : rien n''est effacé');
select throws_ok(format($$ select public.respond_clear_request(%L, true) $$, pg_temp.v('ab')),
  'P0001', 'CLEAR_REQUEST_NOT_FOUND', 'plus de demande après un refus');
select pg_temp.as_user('a');
select public.clear_conversation(pg_temp.v('ab')::uuid, 'everyone');
select lives_ok(format($$ select public.cancel_clear_request(%L) $$, pg_temp.v('ab')), 'Alice annule');
select is((select clear_request_by from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  null, 'annulée : plus de demande');
-- Demande échue : ignorée.
select public.clear_conversation(pg_temp.v('ab')::uuid, 'everyone');
reset role;
update private.clear_requests set expires_at = now() - interval '1 minute'
 where conversation_id = pg_temp.v('ab')::uuid;
set local role authenticated;
select pg_temp.as_user('b');
select throws_ok(format($$ select public.respond_clear_request(%L, true) $$, pg_temp.v('ab')),
  'P0001', 'CLEAR_REQUEST_NOT_FOUND', 'demande échue (24 h) : plus valable');
-- Accord : tout disparaît des deux côtés, sans aucune trace.
select pg_temp.as_user('a');
select public.clear_conversation(pg_temp.v('ab')::uuid, 'everyone');
select pg_temp.as_user('b');
select is(public.respond_clear_request(pg_temp.v('ab')::uuid, true), 'cleared', 'Bob accepte');
reset role;
select is((select count(*)::int from public.messages where conversation_id = pg_temp.v('ab')::uuid), 0,
  'tous les messages sont supprimés définitivement (aucun « Message supprimé », aucun message système)');
select is((select count(*)::int from private.clear_requests where conversation_id = pg_temp.v('ab')::uuid), 0,
  'la demande est close');
set local role authenticated;
select pg_temp.as_user('b');
select results_eq(format($$ select last_message_id is null, cleared_before is not null
                              from public.list_conversations() where conversation_id = %L $$, pg_temp.v('ab')),
  $$ values (true, true) $$, 'chez Bob : discussion vide, toujours listée');
select pg_temp.as_user('a');
select ok((select cleared_before is not null from public.list_conversations()
            where conversation_id = pg_temp.v('ab')::uuid), 'chez Alice aussi');
-- Demandes croisées : celle de l'autre vaut accord.
select public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Nouveau départ');
select public.clear_conversation(pg_temp.v('ab')::uuid, 'everyone');
select pg_temp.as_user('b');
select is(public.clear_conversation(pg_temp.v('ab')::uuid, 'everyone'), 'cleared',
  'Bob demande aussi pendant la demande d''Alice : accord, discussion vidée');
-- Personne bloquée : pas de vidage pour les deux.
reset role;
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('b'), pg_temp.uid('a'));
set local role authenticated;
select throws_ok(format($$ select public.clear_conversation(%L, 'everyone') $$, pg_temp.v('ab')),
  'P0001', 'CLEAR_NOT_ALLOWED', 'blocage : vider pour les deux est impossible');
select is(public.clear_conversation(pg_temp.v('ab')::uuid, 'me'), 'cleared', 'blocage : vider chez soi reste possible');

-- ---------------------------------------------------------------------------
-- Groupes : un administrateur vide pour tous, un membre seulement chez lui
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c');
select public.send_message(pg_temp.v('g')::uuid, gen_random_uuid(), 'Message de Carla');
select throws_ok(format($$ select public.clear_conversation(%L, 'everyone') $$, pg_temp.v('g')),
  'P0001', 'NOT_ADMIN', 'membre simple : ne vide pas le groupe pour tous');
select pg_temp.as_user('a');
select is(public.clear_conversation(pg_temp.v('g')::uuid, 'everyone'), 'cleared', 'l''administratrice vide le groupe');
reset role;
select is((select count(*)::int from public.messages where conversation_id = pg_temp.v('g')::uuid), 0,
  'groupe : tous les messages (système compris) supprimés, sans trace');
set local role authenticated;
select pg_temp.as_user('c');
select is((select count(*)::int from public.get_messages(pg_temp.v('g')::uuid)), 0, 'chez Carla : vide');
select ok((select cleared_before is not null from public.list_conversations()
            where conversation_id = pg_temp.v('g')::uuid), 'Carla sait que le groupe a été vidé');

-- ---------------------------------------------------------------------------
-- Purge : demandes échues retirées
-- ---------------------------------------------------------------------------
reset role;
insert into private.clear_requests (conversation_id, requested_by, expires_at)
values (pg_temp.v('cd')::uuid, pg_temp.uid('c'), now() - interval '1 hour');
select private.purge_expired();
select is((select count(*)::int from private.clear_requests where conversation_id = pg_temp.v('cd')::uuid), 0,
  'purge : demandes échues supprimées');

select * from finish();
rollback;
