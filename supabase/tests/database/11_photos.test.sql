-- Lot 3.2 — Photos (quota journalier atomique et remboursable) et photo de profil.
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

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated, service_role;
create function pg_temp.as_user(p char) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p || '1',
    'session_id', '00000000-0000-0000-0000-00000000' || repeat(p, 4),
    'role', 'authenticated')::text, true);
$$;
create function pg_temp.v(p_k text) returns text language sql as $$ select v from t where k = p_k $$;
create function pg_temp.used() returns int language sql as $$
  select (public.get_photo_quota() ->> 'used')::int $$;
grant execute on function pg_temp.v(text), pg_temp.as_user(char), pg_temp.used()
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Infrastructure
-- ---------------------------------------------------------------------------
select ok(to_regclass('storage.buckets') is null
          or (select count(*) = 2 from storage.buckets
               where id in ('photos', 'avatars') and not public and allowed_mime_types = array['image/jpeg']),
  'buckets « photos » et « avatars » privés, JPEG uniquement');
select ok(to_regclass('storage.objects') is null
          or (select count(*) = 2 and bool_and(cmd = 'SELECT') from pg_policies
               where schemaname = 'storage' and policyname in ('privio_photo_read', 'privio_avatar_read')),
  'Storage : lecture seule pour les photos et photos de profil, aucune écriture cliente');

-- ---------------------------------------------------------------------------
-- Quota : 5 par jour, débit atomique, idempotent
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('conv', public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1')::text);
select is((public.get_photo_quota() ->> 'limit')::int, 5, 'quota par défaut : 5 photos par jour');
select is(pg_temp.used(), 0, 'aucune photo envoyée aujourd''hui');

insert into t values ('cid1', gen_random_uuid()::text);
insert into t select 'path1', path from public.prepare_photo_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid);
select matches(pg_temp.v('path1'), '^' || pg_temp.v('conv') || '/[0-9a-f-]{36}\.jpg$', 'chemin opaque rangé sous la discussion');
select is(pg_temp.used(), 1, 'une réservation = une photo débitée');
select is((select path from public.prepare_photo_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid)),
  pg_temp.v('path1'), 'renvoi avec le même identifiant client : même réservation');
select is(pg_temp.used(), 1, 'renvoi : jamais débité deux fois');

do $$ begin
  for i in 2..5 loop
    insert into t select 'path' || i, path
      from public.prepare_photo_message(pg_temp.v('conv')::uuid, gen_random_uuid());
  end loop;
end $$;
select is(pg_temp.used(), 5, '5 photos réservées');
select is((public.get_photo_quota() ->> 'remaining')::int, 0, 'compteur : plus aucune photo aujourd''hui');
select throws_ok(format($$ select * from public.prepare_photo_message(%L, gen_random_uuid()) $$, pg_temp.v('conv')),
  'P0001', 'PHOTO_QUOTA_REACHED', '6e photo du jour : refusée');
select is(pg_temp.used(), 5, 'refus : rien n''est débité ni réservé');

-- ---------------------------------------------------------------------------
-- Fonctions réservées au service
-- ---------------------------------------------------------------------------
select throws_ok(format($$ select public.commit_photo_upload(%L, 100, 100, 1000) $$, pg_temp.v('path1')),
  '42501', null, 'l''application ne peut pas valider une photo elle-même');
select throws_ok(format($$ select public.release_media_reservation(%L) $$, pg_temp.v('path2')),
  '42501', null, 'l''application ne peut pas se rembourser elle-même');
select throws_ok($$ select public.commit_avatar('x', 1, 1, 1) $$, '42501', null,
  'l''application ne peut pas imposer une photo de profil sans vérification');

reset role;
set local role service_role;
select throws_ok(format($$ select public.commit_photo_upload(%L, 4000, 3000, 1000) $$, pg_temp.v('path1')),
  'P0001', 'MEDIA_INVALID', 'photo trop grande (côté > 2048 px) : refusée');
select throws_ok(format($$ select public.commit_photo_upload(%L, 1600, 1200, 3000000) $$, pg_temp.v('path1')),
  'P0001', 'MEDIA_TOO_LARGE', 'photo trop lourde (> 1 Mio) : refusée');
select lives_ok(format($$ select public.commit_photo_upload(%L, 1600, 1200, 250000) $$, pg_temp.v('path1')),
  'photo 1600 × 1200, 250 Kio : validée');

-- Fichier refusé par la fonction : réservation abandonnée, photo remboursée.
select lives_ok(format($$ select public.release_media_reservation(%L) $$, pg_temp.v('path2')),
  'fichier refusé : réservation libérée');
reset role;
select is((select state from private.media_objects where path = pg_temp.v('path2')), 'purge',
  'réservation libérée : à effacer');
select pg_temp.as_user('a');
set local role authenticated;
select is(pg_temp.used(), 4, 'échec AVANT envoi : photo remboursée');

-- ---------------------------------------------------------------------------
-- Publication, lecture, règles du message
-- ---------------------------------------------------------------------------
select throws_ok(format($$ select * from public.send_photo_message(%L, %L, repeat('x', 1001)) $$,
  pg_temp.v('conv'), pg_temp.v('cid1')), 'P0001', 'BODY_INVALID', 'légende de plus de 1000 caractères : refusée');
insert into t select 'p1', id::text
  from public.send_photo_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid, '  Le marché  ');
select is((select body from public.messages where id = pg_temp.v('p1')::uuid), 'Le marché', 'légende enregistrée');
select is((select id::text from public.send_photo_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid)),
  pg_temp.v('p1'), 'renvoi : même message');
select throws_ok(format($$ select public.edit_message(%L, 'autre') $$, pg_temp.v('p1')),
  'P0001', 'MESSAGE_NOT_EDITABLE', 'une photo ne se modifie pas');
select throws_ok(format($$ select * from public.send_photo_message(%L, %L) $$, pg_temp.v('conv'), gen_random_uuid()),
  'P0001', 'MEDIA_NOT_FOUND', 'aucune publication sans fichier validé');

select pg_temp.as_user('b');
select results_eq(
  format($$ select kind, body, media_path, media_width, media_height from public.get_messages(%L) $$, pg_temp.v('conv')),
  format($$ values ('photo'::text, 'Le marché'::text, %L::text, 1600, 1200) $$, pg_temp.v('path1')),
  'le destinataire voit la photo, sa légende et ses dimensions');
select ok(private.can_read_photo(pg_temp.v('path1')), 'le destinataire peut télécharger la photo');
select is((select unread_count from public.list_conversations() where conversation_id = pg_temp.v('conv')::uuid),
  1, 'une photo compte comme non lue');
insert into t select 'r1', id::text
  from public.send_message(pg_temp.v('conv')::uuid, gen_random_uuid(), 'Joli !', pg_temp.v('p1')::uuid);
select results_eq(
  format($$ select reply_kind, reply_preview from public.get_messages(%L) where id = %L $$, pg_temp.v('conv'), pg_temp.v('r1')),
  $$ values ('photo'::text, 'Le marché'::text) $$, 'une réponse cite une photo (type et légende)');

select pg_temp.as_user('c');
select ok(not private.can_read_photo(pg_temp.v('path1')), 'une personne extérieure ne peut pas télécharger');

-- Signalement avec copie : photo conservée pour la modération.
select pg_temp.as_user('b');
select lives_ok(format($$ select public.report('inappropriate', %L, %L, %L, null, true) $$,
  '00000000-0000-0000-0000-0000000000a1', pg_temp.v('conv'), pg_temp.v('p1')), 'une photo peut être signalée');
reset role;
select ok((select report_hold_until > now() from private.media_objects where path = pg_temp.v('path1')),
  'photo signalée conservée pour la modération');

-- Suppression pour tous : illisible aussitôt, PAS de remboursement.
select pg_temp.as_user('a');
set local role authenticated;
select lives_ok(format($$ select public.delete_message_for_everyone(%L) $$, pg_temp.v('p1')),
  'l''expéditeur supprime la photo pour tous');
select is(pg_temp.used(), 4, 'suppression APRÈS envoi : pas de remboursement');
select pg_temp.as_user('b');
select ok(not private.can_read_photo(pg_temp.v('path1')), 'photo supprimée : plus téléchargeable');
select results_eq(
  format($$ select media_path, media_width from public.get_messages(%L) where id = %L $$, pg_temp.v('conv'), pg_temp.v('p1')),
  $$ values (null::text, null::integer) $$, 'photo supprimée : plus de chemin ni de dimensions');

-- Expiration : illisible, puis à effacer.
reset role;
set local role service_role;
select public.commit_photo_upload(pg_temp.v('path3'), 800, 600, 90000);
reset role;
insert into t select 'cid3', client_msg_id::text from private.media_objects where path = pg_temp.v('path3');
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'p3m', id::text
  from public.send_photo_message(pg_temp.v('conv')::uuid, pg_temp.v('cid3')::uuid, null, null, 300);
reset role;
select is((select expires_at - sent_at from public.messages where id = pg_temp.v('p3m')::uuid), interval '5 minutes',
  'une photo suit la durée choisie pour le message');
update public.messages set sent_at = now() - interval '10 minutes', expires_at = now() - interval '1 second'
 where id = pg_temp.v('p3m')::uuid;
select pg_temp.as_user('b');
set local role authenticated;
select ok(not private.can_read_photo(pg_temp.v('path3')), 'photo expirée : plus téléchargeable avant même la purge');
reset role;
-- Réservations restées en plan plus d'une heure : abandonnées et remboursées.
update private.media_objects set created_at = now() - interval '2 hours'
 where path in (pg_temp.v('path4'), pg_temp.v('path5'));
select private.purge_expired();
select is((select state from private.media_objects where path = pg_temp.v('path3')), 'purge',
  'photo expirée purgée : fichier à effacer');
select is((select count(*)::int from private.media_objects
            where path in (pg_temp.v('path4'), pg_temp.v('path5')) and state = 'purge'), 2,
  'réservations abandonnées : à effacer');
select pg_temp.as_user('a');
set local role authenticated;
select is(pg_temp.used(), 2, 'réservations abandonnées : remboursées');

-- Le jour suivant, le compteur repart de zéro ; l'administrateur peut abaisser la limite.
reset role;
update private.photo_quota_daily set quota_day = quota_day - 1;
select pg_temp.as_user('a');
set local role authenticated;
select is(pg_temp.used(), 0, 'nouveau jour : compteur remis à zéro');
reset role;
insert into private.policies (key, value) values ('photo_daily_limit', '0');
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select * from public.prepare_photo_message(%L, gen_random_uuid()) $$, pg_temp.v('conv')),
  'P0001', 'PHOTO_QUOTA_REACHED', 'limite administrable (0) : photos désactivées');
reset role;
update private.policies set value = '5' where key = 'photo_daily_limit';

-- ---------------------------------------------------------------------------
-- Photo de profil
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('av1', public.prepare_avatar_upload());
select matches(pg_temp.v('av1'), '^00000000-0000-0000-0000-0000000000a1/[0-9a-f-]{36}\.jpg$',
  'photo de profil rangée sous le compte');
reset role;
set local role service_role;
select throws_ok(format($$ select public.commit_avatar(%L, 2000, 2000, 1000) $$, pg_temp.v('av1')),
  'P0001', 'MEDIA_INVALID', 'photo de profil de plus de 1024 px : refusée');
select lives_ok(format($$ select public.commit_avatar(%L, 512, 512, 40000) $$, pg_temp.v('av1')),
  'photo de profil 512 × 512 validée');
select throws_ok(format($$ select public.commit_avatar(%L, 512, 512, 40000) $$, pg_temp.v('av1')),
  'P0001', 'MEDIA_NOT_FOUND', 'une réservation ne sert qu''une fois');
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select is((public.get_my_account() -> 'profile' ->> 'avatar_path'), pg_temp.v('av1'),
  'le profil porte la nouvelle photo');
select ok(private.can_read_avatar(pg_temp.v('av1')), 'chacun voit sa propre photo');
select pg_temp.as_user('b');
select ok(private.can_read_avatar(pg_temp.v('av1')), 'un correspondant voit la photo');
select is((select peer_avatar_path from public.list_conversations() where conversation_id = pg_temp.v('conv')::uuid),
  pg_temp.v('av1'), 'la liste des discussions donne la photo du correspondant');

-- Nouvelle photo : l'ancienne est effacée.
select pg_temp.as_user('a');
insert into t values ('av2', public.prepare_avatar_upload());
reset role;
set local role service_role;
select public.commit_avatar(pg_temp.v('av2'), 400, 400, 30000);
reset role;
select is((select state from private.media_objects where path = pg_temp.v('av1')), 'purge',
  'photo remplacée : l''ancienne est effacée');
select ok(not exists (select 1 from public.profiles where avatar_path = pg_temp.v('av1')), 'ancienne photo détachée');

-- Blocage : plus de photo dans un sens comme dans l'autre.
insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1');
select pg_temp.as_user('b');
set local role authenticated;
select ok(not private.can_read_avatar(pg_temp.v('av2')), 'après blocage : photo de profil invisible');
select is((select peer_avatar_path from public.list_conversations() where conversation_id = pg_temp.v('conv')::uuid),
  null, 'après blocage : la liste ne donne plus la photo');
select pg_temp.as_user('c');
select ok(private.can_read_avatar(pg_temp.v('av2')), 'une autre personne connectée la voit toujours');
reset role;
delete from public.blocks;

-- Retrait, puis suppression du compte.
select pg_temp.as_user('a');
set local role authenticated;
select lives_ok($$ select public.remove_avatar() $$, 'retirer sa photo de profil');
reset role;
select is((select state from private.media_objects where path = pg_temp.v('av2')), 'purge',
  'photo retirée : effacée');
select pg_temp.as_user('b');
set local role authenticated;
insert into t values ('avb', public.prepare_avatar_upload());
reset role;
set local role service_role;
select public.commit_avatar(pg_temp.v('avb'), 300, 300, 20000);
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-0000000000b1';
select is((select state from private.media_objects where path = pg_temp.v('avb')), 'purge',
  'compte supprimé : sa photo de profil est effacée');

select * from finish();
rollback;
