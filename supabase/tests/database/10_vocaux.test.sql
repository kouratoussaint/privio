-- Lot 3.1 — Messages vocaux : réservation, validation serveur, lecture réservée aux membres,
-- expiration, suppression, signalement, effacement physique.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

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
create function pg_temp.v(p_k text) returns text language sql as $$ select v from t where k = p_k $$;
grant execute on function pg_temp.v(text), pg_temp.as_user(char) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Infrastructure
-- ---------------------------------------------------------------------------
select ok(to_regclass('storage.buckets') is null
          or exists (select 1 from storage.buckets where id = 'voice' and not public
                       and file_size_limit = 1048576 and allowed_mime_types = array['audio/mp4']),
  'bucket « voice » privé, 1 Mio au plus, audio/mp4 uniquement');
select ok(to_regclass('storage.objects') is null
          or (select count(*) = 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                and policyname like 'privio_voice%'),
  'une seule politique Storage pour les vocaux (lecture), aucune écriture cliente');
select ok(to_regclass('storage.objects') is null
          or (select cmd = 'SELECT' from pg_policies where schemaname = 'storage' and policyname = 'privio_voice_read'),
  'la politique Storage ne couvre que la lecture');
select is((select implemented from private.policy_definitions where key = 'voice_max_seconds'), true,
  'politique voice_max_seconds (30 s) déclarée implémentée');

-- ---------------------------------------------------------------------------
-- Réservation (application)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('conv', public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1')::text);
insert into t values ('cid1', gen_random_uuid()::text);
insert into t select 'path1', path from public.prepare_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid);
select matches(pg_temp.v('path1'), '^' || pg_temp.v('conv') || '/[0-9a-f-]{36}\.m4a$',
  'chemin opaque rangé sous la discussion');
select is((select path from public.prepare_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid)),
  pg_temp.v('path1'), 'même identifiant client : même réservation (idempotent)');
select throws_ok(format($$ select * from public.send_voice_message(%L, %L) $$, pg_temp.v('conv'), pg_temp.v('cid1')),
  'P0001', 'MEDIA_NOT_FOUND', 'publication refusée tant que le fichier n''est pas validé par le serveur');
select throws_ok(format($$ select public.commit_voice_upload(%L, 5000, 1000) $$, pg_temp.v('path1')),
  '42501', null, 'l''application ne peut pas valider elle-même un fichier');
select throws_ok($$ select * from public.media_purge_claim('x') $$, '42501', null,
  'l''application ne peut pas déclencher l''effacement');

select pg_temp.as_user('c');
select throws_ok(format($$ select * from public.prepare_voice_message(%L, gen_random_uuid()) $$, pg_temp.v('conv')),
  'P0001', 'NOT_MEMBER', 'une personne extérieure ne peut rien déposer');

-- ---------------------------------------------------------------------------
-- Validation (service, après mesure du fichier par voice-send)
-- ---------------------------------------------------------------------------
reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select throws_ok(format($$ select public.commit_voice_upload(%L, 31000, 1000) $$, pg_temp.v('path1')),
  'P0001', 'VOICE_TOO_LONG', 'plus de 30 s : refusé');
select throws_ok(format($$ select public.commit_voice_upload(%L, 12000, 600000) $$, pg_temp.v('path1')),
  'P0001', 'MEDIA_TOO_LARGE', 'plus de 512 Kio : refusé');
select throws_ok($$ select public.commit_voice_upload('inconnu/x.m4a', 12000, 1000) $$,
  'P0001', 'MEDIA_NOT_FOUND', 'fichier non réservé : refusé');
select lives_ok(format($$ select public.commit_voice_upload(%L, 12000, 48000) $$, pg_temp.v('path1')),
  '12 s, 48 Kio : validé');

-- ---------------------------------------------------------------------------
-- Publication et lecture
-- ---------------------------------------------------------------------------
reset role;
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'v1', id::text from public.send_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid);
select is((select media_duration_ms from public.send_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid)),
  12000, 'durée mesurée par le serveur');
select is((select id::text from public.send_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid)),
  pg_temp.v('v1'), 'renvoi : même message (idempotent)');
select is((select state from public.prepare_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid)),
  'sent', 'réservation d''un message déjà publié : « sent »');
select throws_ok(format($$ select public.edit_message(%L, 'texte') $$, pg_temp.v('v1')),
  'P0001', 'MESSAGE_NOT_EDITABLE', 'un vocal ne se modifie pas');

select pg_temp.as_user('b');
select results_eq(
  format($$ select kind, body, media_path, media_duration_ms from public.get_messages(%L) $$, pg_temp.v('conv')),
  format($$ values ('voice'::text, null::text, %L::text, 12000) $$, pg_temp.v('path1')),
  'le destinataire voit le vocal (type, chemin, durée), sans texte');
select ok(private.can_read_voice(pg_temp.v('path1')), 'le destinataire peut télécharger le son');
select is((select unread_count from public.list_conversations() where conversation_id = pg_temp.v('conv')::uuid),
  1, 'un vocal compte comme non lu');
select is((select last_kind from public.list_conversations() where conversation_id = pg_temp.v('conv')::uuid),
  'voice', 'la liste indique un dernier message vocal');

-- Réponse texte à un vocal, réaction.
insert into t select 'r1', id::text from public.send_message(pg_temp.v('conv')::uuid, gen_random_uuid(), 'Bien reçu', pg_temp.v('v1')::uuid);
select is((select reply_kind from public.get_messages(pg_temp.v('conv')::uuid) where id = pg_temp.v('r1')::uuid),
  'voice', 'une réponse cite un vocal (type de la citation)');
select lives_ok(format($$ select public.set_reaction(%L, '👍') $$, pg_temp.v('v1')), 'réaction sur un vocal');

select pg_temp.as_user('c');
select ok(not private.can_read_voice(pg_temp.v('path1')), 'une personne extérieure ne peut pas télécharger');

-- Signalement d'un vocal, avec copie (accord de la personne).
select pg_temp.as_user('b');
select lives_ok(format($$ select public.report('harassment', %L, %L, %L, null, true) $$,
  '00000000-0000-0000-0000-0000000000a1', pg_temp.v('conv'), pg_temp.v('v1')), 'un vocal peut être signalé');
reset role;
select is((select evidence ->> 'kind' from private.reports where message_id = pg_temp.v('v1')::uuid), 'voice',
  'la copie indique un vocal');
select is((select evidence ->> 'media_path' from private.reports where message_id = pg_temp.v('v1')::uuid), pg_temp.v('path1'),
  'la copie désigne le fichier conservé');
select ok((select report_hold_until > now() + interval '89 days' from private.media_objects where path = pg_temp.v('path1')),
  'fichier conservé pour la modération jusqu''à l''échéance du signalement (90 j)');

-- ---------------------------------------------------------------------------
-- Suppression pour tous : fichier illisible tout de suite, puis à effacer.
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select lives_ok(format($$ select public.delete_message_for_everyone(%L) $$, pg_temp.v('v1')),
  'l''expéditeur supprime le vocal pour tous');
select pg_temp.as_user('b');
select ok(not private.can_read_voice(pg_temp.v('path1')), 'après suppression : plus téléchargeable');
select is((select media_path from public.get_messages(pg_temp.v('conv')::uuid) where id = pg_temp.v('v1')::uuid),
  null, 'après suppression : plus de chemin');
reset role;
select is((select state from private.media_objects where path = pg_temp.v('path1')), 'purge',
  'après suppression : fichier en attente d''effacement physique');

-- ---------------------------------------------------------------------------
-- Expiration : illisible à l'échéance, puis purgé.
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('cid2', gen_random_uuid()::text);
insert into t select 'path2', path from public.prepare_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid2')::uuid);
reset role;
set local role service_role;
select public.commit_voice_upload(pg_temp.v('path2'), 3000, 9000);
reset role;
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'v2', id::text from public.send_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid2')::uuid, null, 300);
select is((select expires_at - sent_at from public.messages where id = pg_temp.v('v2')::uuid), interval '5 minutes',
  'un vocal suit la durée choisie pour le message');
reset role;
update public.messages set sent_at = now() - interval '10 minutes', expires_at = now() - interval '1 second'
 where id = pg_temp.v('v2')::uuid;
select pg_temp.as_user('b');
set local role authenticated;
select ok(not private.can_read_voice(pg_temp.v('path2')), 'vocal expiré : plus téléchargeable, même avant la purge');
reset role;
select ok(private.purge_expired() >= 1, 'purge des messages expirés');
select is((select state from private.media_objects where path = pg_temp.v('path2')), 'purge',
  'vocal expiré purgé : fichier en attente d''effacement physique');

-- Réservation abandonnée (fichier jamais publié) : balayée après 1 h, recréable.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('cid3', gen_random_uuid()::text);
insert into t select 'path3', path from public.prepare_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid3')::uuid);
reset role;
update private.media_objects set created_at = now() - interval '2 hours' where path = pg_temp.v('path3');
select private.purge_expired();
select is((select state from private.media_objects where path = pg_temp.v('path3')), 'purge',
  'réservation abandonnée depuis plus d''une heure : à effacer');
select pg_temp.as_user('a');
set local role authenticated;
select isnt((select path from public.prepare_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid3')::uuid)),
  pg_temp.v('path3'), 'un renvoi tardif obtient une nouvelle réservation');

-- ---------------------------------------------------------------------------
-- Effacement physique (service + jeton)
-- ---------------------------------------------------------------------------
reset role;
insert into t select 'token', value from private.runtime_settings where key = 'media_purge_token';
select ok(length(pg_temp.v('token')) = 64, 'jeton de purge aléatoire créé par la migration');
set local role service_role;
select throws_ok($$ select * from public.media_purge_claim('mauvais') $$, 'P0001', 'AUTH_REQUIRED',
  'jeton incorrect : refusé');
select set_eq(format($$ select path from public.media_purge_claim(%L) $$, pg_temp.v('token')),
  format($$ values (%L), (%L) $$, pg_temp.v('path2'), pg_temp.v('path3')),
  'lot à effacer : vocal expiré et réservation abandonnée, PAS le vocal signalé');
select is_empty(format($$ select * from public.media_purge_claim(%L) $$, pg_temp.v('token')),
  'un lot réservé n''est pas redistribué immédiatement');
select is(public.media_purge_complete(pg_temp.v('token'), array[pg_temp.v('path2'), pg_temp.v('path3')]), 2,
  'fichiers effacés : leur trace disparaît');
reset role;
select is((select count(*)::int from private.media_objects where path in (pg_temp.v('path2'), pg_temp.v('path3'))), 0,
  'plus aucune trace des fichiers effacés');
select is(private.request_media_purge(), null, 'rien à effacer : aucun appel réseau');

set local role service_role;
select throws_ok($$ select public.media_register_endpoint('ftp://ailleurs') $$, 'P0001', 'BODY_INVALID',
  'adresse de fonctions invalide refusée');
select lives_ok($$ select public.media_register_endpoint('https://exemple.supabase.co/functions/v1') $$,
  'adresse des fonctions enregistrée');
reset role;
select is((select value from private.runtime_settings where key = 'functions_url'),
  'https://exemple.supabase.co/functions/v1', 'adresse conservée pour la tâche planifiée');

-- ---------------------------------------------------------------------------
-- Blocage
-- ---------------------------------------------------------------------------
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1');
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select * from public.prepare_voice_message(%L, gen_random_uuid()) $$, pg_temp.v('conv')),
  'P0001', 'BLOCKED', 'contact bloqué : aucun vocal');

select * from finish();
rollback;
