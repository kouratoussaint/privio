-- Lot 4.7 — Demande de connexion avant le premier message : envoi, réponse (accepter,
-- refuser, bloquer), annulation, expiration, attente après refus, limite par personne et
-- par jour, demandes croisées, réglage « qui peut m'envoyer une demande », notifications.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

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
grant execute on function pg_temp.v(text), pg_temp.as_user(char), pg_temp.uid(char)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Politiques par défaut
-- ---------------------------------------------------------------------------
select is(private.policy_bool('connection_requests_required'), true, 'demandes obligatoires par défaut');
select is(private.policy_int('connection_request_expiry_hours'), 24, 'expiration : 24 h');
select is(private.policy_int('connection_request_retry_minutes'), 5, 'attente après refus : 5 min');
select is(private.policy_int('connection_request_daily_per_person'), 3, '3 demandes par personne et par jour');
select is(private.policy_int('connection_note_ttl_minutes'), 5, 'mot effacé 5 min après acceptation');

-- ---------------------------------------------------------------------------
-- Plus d'écriture directe à un inconnu
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok($$ select public.start_direct_conversation(pg_temp.uid('b')) $$,
  'P0001', 'CONNECTION_REQUIRED', 'écrire directement à un inconnu : refusé');
select results_eq($$ select state from public.connection_status(pg_temp.uid('b')) $$,
  $$ values ('none'::text) $$, 'aucune relation : « none »');
select throws_ok($$ select * from public.send_connection_request(pg_temp.uid('b'), repeat('x', 141)) $$,
  'P0001', 'CONNECTION_NOTE_TOO_LONG', 'mot de plus de 140 caractères : refusé');
select throws_ok($$ select * from public.send_connection_request(pg_temp.uid('a'), null) $$,
  'P0001', 'SELF_CONVERSATION', 'demande à soi-même : refusée');
select throws_ok($$ select * from private.connection_requests $$, '42501', null,
  'table des demandes : aucun accès direct');

-- ---------------------------------------------------------------------------
-- Alice → Bob : demande, puis refus (Alice est prévenue), attente de 5 min
-- ---------------------------------------------------------------------------
insert into t select 'r1', request_id::text
  from public.send_connection_request(pg_temp.uid('b'), '  Bonjour Bob, c''est Alice  ');
select results_eq($$ select state from public.send_connection_request(pg_temp.uid('b'), 'encore') $$,
  $$ values ('requested'::text) $$, 'nouvel envoi pendant l''attente : même demande (idempotent)');
select is((select count(*)::int from public.list_connection_requests() where direction = 'outgoing'), 1,
  'une seule demande envoyée');
select results_eq($$ select state, request_id::text from public.connection_status(pg_temp.uid('b')) $$,
  $$ values ('outgoing'::text, pg_temp.v('r1')) $$, 'Alice : demande en attente');

select pg_temp.as_user('b');
select results_eq($$ select state from public.connection_status(pg_temp.uid('a')) $$,
  $$ values ('incoming'::text) $$, 'Bob : demande reçue');
select results_eq(
  $$ select direction, handle, display_name, note, status from public.list_connection_requests() $$,
  $$ values ('incoming'::text, 'alice_bf'::text, 'Alice'::text, 'Bonjour Bob, c''est Alice'::text, 'pending'::text) $$,
  'Bob voit qui demande et le mot (espaces retirés) ; jamais de numéro');
select throws_ok($$ select * from public.cancel_connection_request(pg_temp.v('r1')::uuid) $$,
  'P0001', 'CONNECTION_REQUEST_NOT_FOUND', 'Bob ne peut pas annuler la demande d''Alice');
select results_eq($$ select state from public.respond_connection_request(pg_temp.v('r1')::uuid, 'refuse') $$,
  $$ values ('refused'::text) $$, 'Bob refuse');
reset role;
select is((select note from private.connection_requests where id = pg_temp.v('r1')::uuid), null,
  'refus : le mot est effacé du serveur');
select is((select count(*)::int from public.conversations where direct_key = private.direct_key(pg_temp.uid('a'), pg_temp.uid('b'))),
  0, 'refus : aucune discussion créée');
set local role authenticated;
select throws_ok($$ select * from public.respond_connection_request(pg_temp.v('r1')::uuid, 'accept') $$,
  'P0001', 'CONNECTION_REQUEST_NOT_FOUND', 'une demande déjà refusée ne peut plus être acceptée');

select pg_temp.as_user('a');
select results_eq($$ select status, retry_at is not null from public.list_connection_requests() $$,
  $$ values ('refused'::text, true) $$, 'Alice voit le refus et quand elle pourra redemander');
select results_eq($$ select state from public.connection_status(pg_temp.uid('b')) $$,
  $$ values ('refused'::text) $$, 'Alice : refus récent');
select throws_ok($$ select * from public.send_connection_request(pg_temp.uid('b'), null) $$,
  'P0001', 'CONNECTION_RETRY_LATER', 'redemander avant 5 min : refusé');

-- 6 minutes plus tard : 2e demande, annulée ; 3e demande, annulée ; la 4e du jour est refusée.
reset role;
update private.connection_requests set answered_at = answered_at - interval '6 minutes'
 where id = pg_temp.v('r1')::uuid;
set local role authenticated;
insert into t select 'r2', request_id::text from public.send_connection_request(pg_temp.uid('b'), null);
select isnt(pg_temp.v('r2'), pg_temp.v('r1'), 'après 5 min : nouvelle demande possible');
select lives_ok($$ select public.cancel_connection_request(pg_temp.v('r2')::uuid) $$, 'Alice annule sa demande');
insert into t select 'r3', request_id::text from public.send_connection_request(pg_temp.uid('b'), null);
select lives_ok($$ select public.cancel_connection_request(pg_temp.v('r3')::uuid) $$, '3e demande du jour, annulée');
select throws_ok($$ select * from public.send_connection_request(pg_temp.uid('b'), null) $$,
  'P0001', 'CONNECTION_DAILY_LIMIT', '4e demande du jour vers la même personne : refusée');
select results_eq($$ select state from public.send_connection_request(pg_temp.uid('c'), null) $$,
  $$ values ('requested'::text) $$, 'la limite vaut par personne : Carla reste joignable');

-- ---------------------------------------------------------------------------
-- Carla → Bob : acceptation ; le mot devient le 1er message (5 min)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c');
insert into t select 'r4', request_id::text from public.send_connection_request(pg_temp.uid('b'), 'Salut, c''est Carla');
select pg_temp.as_user('b');
insert into t select 'cb', conversation_id::text
  from public.respond_connection_request(pg_temp.v('r4')::uuid, 'accept');
select isnt(pg_temp.v('cb'), null, 'acceptation : discussion créée');
select results_eq(
  $$ select sender_id, body, kind from public.get_messages(pg_temp.v('cb')::uuid) $$,
  $$ values (pg_temp.uid('c'), 'Salut, c''est Carla'::text, 'text'::text) $$,
  'le mot de Carla est le premier message');
select ok((select expires_at - sent_at = interval '5 minutes'
             from public.get_messages(pg_temp.v('cb')::uuid)), 'le premier message s''efface après 5 min');
select results_eq($$ select state, conversation_id::text from public.connection_status(pg_temp.uid('c')) $$,
  $$ values ('connected'::text, pg_temp.v('cb')) $$, 'Bob et Carla sont connectés');
select is(public.start_direct_conversation(pg_temp.uid('c'))::text, pg_temp.v('cb'),
  'discussion existante : s''ouvre directement');
select is((select count(*)::int from public.list_connection_requests()), 0,
  'demande acceptée : plus dans la liste de Bob');
reset role;
select results_eq($$ select status, note from private.connection_requests where id = pg_temp.v('r4')::uuid $$,
  $$ values ('accepted'::text, null::text) $$, 'acceptation : mot effacé de la demande');
select ok(not exists (select 1 from private.push_log), 'le mot ne déclenche pas de notification « nouveau message »');
set local role authenticated;
select pg_temp.as_user('c');
select results_eq($$ select state, conversation_id::text from public.send_connection_request(pg_temp.uid('b'), null) $$,
  $$ values ('connected'::text, pg_temp.v('cb')) $$, 'déjà connectés : la demande renvoie la discussion');

-- ---------------------------------------------------------------------------
-- Demandes croisées : Dani → Alice, puis Alice → Dani = connexion immédiate
-- ---------------------------------------------------------------------------
select pg_temp.as_user('d');
insert into t select 'r5', request_id::text from public.send_connection_request(pg_temp.uid('a'), 'Coucou');
select pg_temp.as_user('a');
select results_eq($$ select state, conversation_id is not null from public.send_connection_request(pg_temp.uid('d'), null) $$,
  $$ values ('connected'::text, true) $$, 'demandes croisées : connectés sans attendre');
select is((select count(*)::int from public.list_connection_requests() where direction = 'incoming'), 0,
  'demande croisée : plus rien en attente');

-- ---------------------------------------------------------------------------
-- Réglage « Qui peut m'envoyer une demande » : personne
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
select results_eq($$ select * from public.get_connection_settings() $$, $$ values (true) $$,
  'par défaut : tout le monde peut envoyer une demande');
select lives_ok($$ select public.set_connection_settings(false) $$, 'Bob : « personne »');
select pg_temp.as_user('d');
select throws_ok($$ select * from public.send_connection_request(pg_temp.uid('b'), null) $$,
  'P0001', 'CONNECTION_NOT_ALLOWED', '« personne » : demande impossible');
select pg_temp.as_user('b');
select lives_ok($$ select public.set_connection_settings(true) $$, 'Bob : « tout le monde »');

-- ---------------------------------------------------------------------------
-- Bloquer depuis une demande
-- ---------------------------------------------------------------------------
select pg_temp.as_user('d');
insert into t select 'r6', request_id::text from public.send_connection_request(pg_temp.uid('b'), 'Hé');
select pg_temp.as_user('b');
select results_eq($$ select state from public.respond_connection_request(pg_temp.v('r6')::uuid, 'block') $$,
  $$ values ('blocked'::text) $$, 'Bob bloque Dani depuis la demande');
select ok(exists (select 1 from public.blocks where blocker_id = pg_temp.uid('b') and blocked_id = pg_temp.uid('d')),
  'Dani est dans les personnes bloquées de Bob');
select pg_temp.as_user('d');
reset role;
update private.connection_requests set answered_at = answered_at - interval '1 hour'
 where id = pg_temp.v('r6')::uuid;
set local role authenticated;
select throws_ok($$ select * from public.send_connection_request(pg_temp.uid('b'), null) $$,
  'P0001', 'CONNECTION_NOT_ALLOWED', 'bloqué : même réponse que « personne » (rien n''indique le blocage)');

-- ---------------------------------------------------------------------------
-- Expiration à 24 h
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c');
insert into t select 'r7', request_id::text from public.send_connection_request(pg_temp.uid('d'), 'Tu es là ?');
reset role;
update private.connection_requests set expires_at = now() - interval '1 second'
 where id = pg_temp.v('r7')::uuid;
set local role authenticated;
select pg_temp.as_user('d');
select is((select count(*)::int from public.list_connection_requests() where direction = 'incoming'), 0,
  'demande échue : n''apparaît plus chez Dani');
select pg_temp.as_user('c');
select results_eq($$ select status, note from public.list_connection_requests() where id = pg_temp.v('r7')::uuid $$,
  $$ values ('expired'::text, null::text) $$, 'Carla voit l''expiration ; le mot est effacé');
select results_eq($$ select state from public.connection_status(pg_temp.uid('d')) $$,
  $$ values ('none'::text) $$, 'après expiration : on peut redemander');

-- ---------------------------------------------------------------------------
-- Notifications : réservées au service, jamais de contenu
-- ---------------------------------------------------------------------------
reset role;
select throws_ok($$ select * from public.push_request_targets('mauvais-jeton', pg_temp.v('r1')::uuid) $$,
  'P0001', 'AUTH_REQUIRED', 'cibles de notification : jeton du service obligatoire');
select ok(not has_function_privilege('authenticated', 'public.push_request_targets(text, uuid)', 'execute'),
  'cibles de notification : interdites aux utilisateurs');

-- Nettoyage : demandes closes depuis plus de 7 jours oubliées.
update private.connection_requests set answered_at = now() - interval '8 days' where id = pg_temp.v('r1')::uuid;
select private.purge_connection_requests();
select ok(not exists (select 1 from private.connection_requests where id = pg_temp.v('r1')::uuid),
  'nettoyage : demande close depuis 8 jours supprimée');

select * from finish();
rollback;
