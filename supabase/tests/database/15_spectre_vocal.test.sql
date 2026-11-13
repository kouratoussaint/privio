-- Lot 4.5 — Spectre des messages vocaux : profil sonore vérifié, recopié dans le message,
-- lu par les membres, effacé avec le message ; les anciens vocaux restent valides sans profil.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Lot 4.7 : ce fichier ouvre des discussions directement (règles d'avant les demandes de
-- connexion, testées dans 16_demandes_connexion).
insert into private.policies (key, value) values ('connection_requests_required', 'false');

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob');

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
-- Schéma et règles
-- ---------------------------------------------------------------------------
select has_column('public', 'messages', 'media_waveform', 'colonne du profil sonore');
select col_type_is('public', 'messages', 'media_waveform', 'smallint[]', 'profil : liste d''entiers');
select ok(private.waveform_valid(null), 'aucun profil : valide (anciens vocaux)');
select ok(private.waveform_valid(array_fill(50::smallint, array[40])), '40 valeurs : valide');
select ok(not private.waveform_valid(array_fill(50::smallint, array[7])), 'moins de 8 valeurs : refusé');
select ok(not private.waveform_valid(array_fill(50::smallint, array[65])), 'plus de 64 valeurs : refusé');
select ok(not private.waveform_valid(array[101, 0, 0, 0, 0, 0, 0, 0]::smallint[]), 'valeur > 100 : refusée');
select ok(not private.waveform_valid(array[-1, 0, 0, 0, 0, 0, 0, 0]::smallint[]), 'valeur négative : refusée');
select ok(not private.waveform_valid(array[null, 0, 0, 0, 0, 0, 0, 0]::smallint[]), 'valeur vide : refusée');

-- ---------------------------------------------------------------------------
-- Réservation, validation avec profil (service), publication
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('conv', public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1')::text);
insert into t values ('cid1', gen_random_uuid()::text), ('cid2', gen_random_uuid()::text);
insert into t select 'path1', path from public.prepare_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid);
insert into t select 'path2', path from public.prepare_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid2')::uuid);
select throws_ok(
  format($$ select public.commit_voice_upload(%L, 5000, 1000, array_fill(1::smallint, array[40])) $$,
         pg_temp.v('path1')),
  '42501', null, 'l''application ne peut pas déposer elle-même un profil');

reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select throws_ok(
  format($$ select public.commit_voice_upload(%L, 5000, 1000, array[200,0,0,0,0,0,0,0]::smallint[]) $$,
         pg_temp.v('path1')),
  'P0001', 'MEDIA_INVALID', 'profil hors bornes : refusé');
select lives_ok(
  format($$ select public.commit_voice_upload(%L, 5000, 1000,
                     (select array_agg((i * 2)::smallint order by i) from generate_series(1, 40) i)) $$,
         pg_temp.v('path1')),
  'vocal validé avec son profil (40 valeurs)');
select lives_ok(format($$ select public.commit_voice_upload(%L, 4000, 900) $$, pg_temp.v('path2')),
  'vocal validé sans profil (ancienne version de l''application)');

reset role;
select pg_temp.as_user('a');
set local role authenticated;
insert into t select 'v1', id::text from public.send_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid);
insert into t select 'v2', id::text from public.send_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid2')::uuid);
select is(
  (select media_waveform[1:3] from public.send_voice_message(pg_temp.v('conv')::uuid, pg_temp.v('cid1')::uuid)),
  array[2, 4, 6]::smallint[], 'la réponse d''envoi porte le profil (renvoi idempotent)');

select pg_temp.as_user('b');
select is(
  (select cardinality(media_waveform) from public.get_messages(pg_temp.v('conv')::uuid) where id = pg_temp.v('v1')::uuid),
  40, 'le destinataire reçoit le profil complet');
select is(
  (select media_waveform[40] from public.get_messages(pg_temp.v('conv')::uuid) where id = pg_temp.v('v1')::uuid),
  80::smallint, 'valeurs identiques chez l''expéditeur et le destinataire');
select is(
  (select media_waveform from public.get_messages(pg_temp.v('conv')::uuid) where id = pg_temp.v('v2')::uuid),
  null, 'vocal sans profil : lisible, spectre neutre côté application');

-- ---------------------------------------------------------------------------
-- Intégrité : le profil ne se modifie pas et part avec le message
-- ---------------------------------------------------------------------------
insert into t select 'txt', (public.send_message(pg_temp.v('conv')::uuid, gen_random_uuid(), 'Bonjour')).id::text;
reset role;
select throws_ok(
  format($$ update public.messages set media_waveform = array_fill(9::smallint, array[40]) where id = %L $$,
         pg_temp.v('v1')),
  'P0001', 'MESSAGE_NOT_EDITABLE', 'le profil d''un vocal envoyé ne se modifie pas');
select throws_ok(
  format($$ update public.messages set media_waveform = array_fill(9::smallint, array[40])
             where id = %L $$, pg_temp.v('txt')),
  '23514', null, 'un message qui n''est pas un vocal ne peut pas porter de profil');

select pg_temp.as_user('a');
set local role authenticated;
select lives_ok(format($$ select public.delete_message_for_everyone(%L) $$, pg_temp.v('v1')),
  'suppression pour tout le monde');
reset role;
select is((select media_waveform from public.messages where id = pg_temp.v('v1')::uuid), null,
  'suppression : profil effacé avec le fichier');

select * from finish();
rollback;
