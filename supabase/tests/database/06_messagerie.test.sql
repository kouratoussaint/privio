-- Lot 2.1 — Messagerie 1:1 : accès, envoi idempotent, accusés, réactions, réponses,
-- modification (60 min), suppressions, blocage, EXPIRATION À 72 H (P0), purge, temps réel.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Lot 4.7 : ce fichier ouvre des discussions directement (règles d'avant les demandes de
-- connexion, testées dans 16_demandes_connexion).
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

create temporary table t (k text primary key, v uuid) on commit drop;
grant all on t to authenticated;

-- Helpers de session (en tant que postgres, avant de changer de rôle).
create function pg_temp.as_user(p char) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p || '1',
    'session_id', '00000000-0000-0000-0000-00000000' || repeat(p, 4),
    'role', 'authenticated')::text, true);
$$;

-- ============================ Démarrer une discussion ============================
select pg_temp.as_user('a');
set local role authenticated;

insert into t values ('conv', public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1'));
select isnt((select v from t where k = 'conv'), null, 'A démarre une discussion avec B');
select is(public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1'),
          (select v from t where k = 'conv'), 'une seule discussion directe par paire (idempotent)');
select throws_ok($$ select public.start_direct_conversation('00000000-0000-0000-0000-0000000000a1') $$,
  'P0001', 'SELF_CONVERSATION', 'pas de discussion avec soi-même');
select throws_ok($$ select public.start_direct_conversation('00000000-0000-0000-0000-00000000dead') $$,
  'P0001', 'USER_NOT_FOUND', 'destinataire inexistant');
select throws_ok($$ insert into public.conversations (kind, direct_key) values ('direct', 'x:y') $$,
  '42501', null, 'aucune écriture directe dans conversations');

-- ================================== Envoi ==================================
insert into t values ('m1', (select id from public.send_message(
  (select v from t where k = 'conv'), '11111111-1111-1111-1111-111111111111', '  Bonjour Bob  ')));
select isnt((select v from t where k = 'm1'), null, 'A envoie un message');
select is((select body from public.messages where id = (select v from t where k = 'm1')), 'Bonjour Bob',
  'le texte est nettoyé des espaces superflus');
select is((select expires_at - sent_at from public.messages where id = (select v from t where k = 'm1')),
  interval '72 hours', 'expiration fixée par le serveur à 72 h exactement');
select is((select id from public.send_message((select v from t where k = 'conv'),
            '11111111-1111-1111-1111-111111111111', 'Bonjour Bob')),
  (select v from t where k = 'm1'), 'renvoi du même message (réseau instable) : pas de doublon');
select is((select count(*)::int from public.messages), 1, 'un seul message stocké');
select throws_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), '   ') $$,
  (select v from t where k = 'conv')), 'P0001', 'BODY_INVALID', 'message vide refusé');
select throws_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), repeat('x', 4001)) $$,
  (select v from t where k = 'conv')), 'P0001', 'BODY_INVALID', 'message de plus de 4000 caractères refusé');
select throws_ok($$ insert into public.messages (conversation_id, client_msg_id, body, expires_at)
                    values (gen_random_uuid(), gen_random_uuid(), 'x', now() + interval '1 hour') $$,
  '42501', null, 'aucune insertion directe de message');

-- Conflit d'idempotence : même identifiant client dans une autre discussion.
insert into t values ('conv_ac', public.start_direct_conversation('00000000-0000-0000-0000-0000000000c1'));
select throws_ok(format($$ select * from public.send_message(%L, '11111111-1111-1111-1111-111111111111', 'x') $$,
  (select v from t where k = 'conv_ac')), 'P0001', 'IDEMPOTENCY_CONFLICT',
  'identifiant client réutilisé dans une autre discussion : refus');

-- Profils : A lit maintenant celui de B (discussion commune).
select is((select display_name from public.profiles where handle = 'bob_ouaga'), 'Bob',
  'profil du correspondant lisible');

-- ============================== Côté destinataire ==============================
reset role;
select pg_temp.as_user('b');
set local role authenticated;

select is((select body from public.get_messages((select v from t where k = 'conv'))), 'Bonjour Bob',
  'B lit le message');
select is((select unread_count from public.list_conversations()), 1, 'B a 1 message non lu');
select is((select last_expires_at - last_sent_at from public.list_conversations()), interval '72 hours',
  'la liste expose l''expiration du dernier message');
select is((select peer_display_name from public.list_conversations()), 'Alice',
  'la liste affiche le nom du correspondant');
select lives_ok(format($$ select public.mark_conversation(%L, now(), now()) $$, (select v from t where k = 'conv')),
  'B marque la discussion comme lue');
select is((select unread_count from public.list_conversations()), 0, 'plus aucun non lu');

-- Réponse et réaction
insert into t values ('m2', (select id from public.send_message((select v from t where k = 'conv'),
  gen_random_uuid(), 'Salut Alice', (select v from t where k = 'm1'))));
select is((select reply_preview from public.get_messages((select v from t where k = 'conv'))
            where id = (select v from t where k = 'm2')), 'Bonjour Bob', 'la réponse cite le message d''origine');
select lives_ok(format($$ select public.set_reaction(%L, '👍') $$, (select v from t where k = 'm1')),
  'B réagit avec un emoji');
select throws_ok(format($$ select public.set_reaction(%L, 'ok') $$, (select v from t where k = 'm1')),
  'P0001', 'REACTION_INVALID', 'une réaction doit être un emoji');
select is((select reactions -> 0 ->> 'emoji' from public.get_messages((select v from t where k = 'conv'))
            where id = (select v from t where k = 'm1')), '👍', 'la réaction est visible');
select throws_ok(format($$ select public.edit_message(%L, 'piraté') $$, (select v from t where k = 'm1')),
  'P0001', 'NOT_SENDER', 'B ne peut pas modifier le message de A');

-- « Supprimer pour moi »
select lives_ok(format($$ select public.delete_message_for_me(%L) $$, (select v from t where k = 'm2')),
  'B masque son propre message pour lui-même');
select is((select count(*)::int from public.get_messages((select v from t where k = 'conv'))
            where id = (select v from t where k = 'm2')), 0, 'masqué chez B');

-- ================================ Retour chez A ================================
reset role;
select pg_temp.as_user('a');
set local role authenticated;

select is((select count(*)::int from public.get_messages((select v from t where k = 'conv'))
            where id = (select v from t where k = 'm2')), 1, 'toujours visible chez A');
select isnt((select peer_read_up_to from public.list_conversations()
              where conversation_id = (select v from t where k = 'conv')), null,
  'A voit que B a lu (accusé de lecture)');
select lives_ok(format($$ select public.edit_message(%L, 'Bonjour Bob !') $$, (select v from t where k = 'm1')),
  'A modifie son message dans les 60 minutes');
select isnt((select edited_at from public.messages where id = (select v from t where k = 'm1')), null,
  'le message est marqué « modifié »');

-- Épingler / archiver
select lives_ok(format($$ select public.set_conversation_flags(%L, true, true) $$, (select v from t where k = 'conv')),
  'A épingle et archive');
select is((select pinned and archived from public.list_conversations()
            where conversation_id = (select v from t where k = 'conv')), true, 'état personnel enregistré');

-- Fenêtre de modification dépassée (61 minutes)
reset role;
update public.messages set sent_at = sent_at - interval '61 minutes', expires_at = expires_at - interval '61 minutes'
 where id = (select v from t where k = 'm1');
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select public.edit_message(%L, 'trop tard') $$, (select v from t where k = 'm1')),
  'P0001', 'EDIT_WINDOW_EXPIRED', 'modification refusée après 60 minutes');

-- Supprimer pour tout le monde
select lives_ok(format($$ select public.delete_message_for_everyone(%L) $$, (select v from t where k = 'm1')),
  'A supprime son message pour tout le monde');
select ok((select body is null and deleted_at is not null from public.messages
            where id = (select v from t where k = 'm1')), 'le contenu est effacé immédiatement');
select is((select jsonb_array_length(reactions) from public.get_messages((select v from t where k = 'conv'))
            where id = (select v from t where k = 'm1')), 0, 'les réactions sont retirées');

-- ============================ Non-membre (C) ============================
reset role;
select pg_temp.as_user('c');
set local role authenticated;
select is((select count(*)::int from public.messages where conversation_id = (select v from t where k = 'conv')), 0,
  'C ne voit aucun message d''une discussion dont il n''est pas membre');
select throws_ok(format($$ select * from public.get_messages(%L) $$, (select v from t where k = 'conv')),
  'P0001', 'NOT_MEMBER', 'C ne peut pas lire la discussion');
select throws_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), 'intrus') $$,
  (select v from t where k = 'conv')), 'P0001', 'NOT_MEMBER', 'C ne peut pas écrire dans la discussion');
select is((select count(*)::int from public.profiles where handle = 'bob_ouaga'), 0,
  'C ne lit pas le profil de B (aucune discussion commune)');

-- ====================== EXPIRATION À LA SECONDE (P0) ======================
reset role;
insert into public.messages (id, conversation_id, sender_id, client_msg_id, body, sent_at, expires_at) values
  ('22222222-2222-2222-2222-222222222201', (select v from t where k = 'conv'),
   '00000000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'encore 1 seconde',
   now() - interval '71:59:59', now() + interval '1 second'),
  ('22222222-2222-2222-2222-222222222202', (select v from t where k = 'conv'),
   '00000000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'expiré',
   now() - interval '72 hours', now());
select pg_temp.as_user('b');
set local role authenticated;
select is((select count(*)::int from public.messages where id = '22222222-2222-2222-2222-222222222201'), 1,
  'à expires_at − 1 s : message visible');
select is((select count(*)::int from public.messages where id = '22222222-2222-2222-2222-222222222202'), 0,
  'à expires_at : message invisible (RLS), même avant la purge');
select is((select count(*)::int from public.get_messages((select v from t where k = 'conv'))
            where id = '22222222-2222-2222-2222-222222222202'), 0, 'à expires_at : absent des RPC');
select throws_ok($$ select public.set_reaction('22222222-2222-2222-2222-222222222202', '👍') $$,
  'P0001', 'MESSAGE_EXPIRED', 'aucune action possible sur un message expiré');
select throws_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), 'r', '22222222-2222-2222-2222-222222222202') $$,
  (select v from t where k = 'conv')), 'P0001', 'REPLY_NOT_FOUND', 'impossible de répondre à un message expiré');

reset role;
select cmp_ok(private.purge_expired(), '>=', 1, 'la purge supprime les messages expirés');
select is((select count(*)::int from public.messages where id = '22222222-2222-2222-2222-222222222202'), 0,
  'le message expiré n''existe plus en base');
select is((select count(*)::int from public.messages where id = '22222222-2222-2222-2222-222222222201'), 1,
  'le message non expiré est conservé');

-- Durée réduite par l'administration : s'applique aux NOUVEAUX messages seulement.
insert into private.policies (key, value) values ('message_ttl_hours', '24');
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('m3', (select id from public.send_message((select v from t where k = 'conv'),
  gen_random_uuid(), 'durée réduite')));
select is((select expires_at - sent_at from public.messages where id = (select v from t where k = 'm3')),
  interval '24 hours', 'nouvelle durée appliquée au nouveau message');
select is((select expires_at - sent_at from public.messages where id = '22222222-2222-2222-2222-222222222201'),
  interval '72 hours', 'les messages existants gardent leur expiration');

-- ================================== Blocage ==================================
reset role;
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1');
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), 'tu es là ?') $$,
  (select v from t where k = 'conv')), 'P0001', 'BLOCKED', 'message refusé si l''un a bloqué l''autre');
select is((select blocked from public.list_conversations() where conversation_id = (select v from t where k = 'conv')),
  true, 'la liste signale le blocage');
reset role;
select pg_temp.as_user('b');
set local role authenticated;
select is((select handle from public.list_blocked_users()), 'alice_bf', 'B voit qui il a bloqué');

-- ============================ Temps réel et purge planifiée ============================
reset role;
create function pg_temp.scalar(q text) returns text language plpgsql as $$
declare r text; begin execute q into r; return r; end; $$;

select case when to_regclass('realtime.messages') is not null then
  ok(pg_temp.scalar($q$ select (count(*) > 0)::text from realtime.messages
                       where topic = 'user:00000000-0000-0000-0000-0000000000b1' $q$)::boolean,
     'un signal temps réel a été émis vers le canal privé de B')
else skip('Realtime absent (environnement local sans Supabase)') end;
select case when to_regclass('realtime.messages') is not null then
  is(pg_temp.scalar($q$ select count(*)::text from realtime.messages
                       where topic like 'user:%' and payload::text ilike '%bonjour%' $q$), '0',
     'les signaux ne contiennent aucun texte de message')
else skip('Realtime absent (environnement local sans Supabase)') end;
select case when to_regclass('cron.job') is not null then
  is(pg_temp.scalar($q$ select schedule from cron.job where jobname = 'privio_purge_expired' $q$),
     '* * * * *', 'purge planifiée chaque minute (pg_cron)')
else skip('pg_cron absent (environnement local sans Supabase)') end;

select * from finish();
rollback;
