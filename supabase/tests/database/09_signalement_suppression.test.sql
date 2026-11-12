-- Lot 2.5 — signalement (consentement à la copie), assistance, suppression de compte.
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
create temporary table t (k text primary key, v uuid) on commit drop;
grant all on t to authenticated;
create function pg_temp.as_user(p char) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p || '1',
    'session_id', '00000000-0000-0000-0000-00000000' || repeat(p, 4),
    'role', 'authenticated')::text, true);
$$;

-- B écrit à A un message abusif.
select pg_temp.as_user('b');
set local role authenticated;
insert into t values ('conv', public.start_direct_conversation('00000000-0000-0000-0000-0000000000a1'));
insert into t values ('m1', (select id from public.send_message((select v from t where k = 'conv'), gen_random_uuid(), 'Message abusif')));
insert into t values ('m2', (select id from public.send_message((select v from t where k = 'conv'), gen_random_uuid(), 'Autre message')));

reset role;
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('r1', public.report('harassment', '00000000-0000-0000-0000-0000000000b1',
  (select v from t where k = 'conv'), (select v from t where k = 'm1'), 'Insultes', true));
select isnt((select v from t where k = 'r1'), null, 'A signale un message de B');
select is(public.report('harassment', '00000000-0000-0000-0000-0000000000b1',
  (select v from t where k = 'conv'), (select v from t where k = 'm1'), null, true),
  (select v from t where k = 'r1'), 'signaler deux fois le même message : un seul signalement');
insert into t values ('r2', public.report('spam', '00000000-0000-0000-0000-0000000000b1',
  (select v from t where k = 'conv'), (select v from t where k = 'm2'), null, false));
select throws_ok($$ select public.report('spam', '00000000-0000-0000-0000-0000000000a1') $$,
  'P0001', 'REPORT_INVALID', 'impossible de se signaler soi-même');
select throws_ok(format($$ select public.report('spam', '00000000-0000-0000-0000-0000000000c1', %L, %L) $$,
  (select v from t where k = 'conv'), (select v from t where k = 'm1')),
  'P0001', 'REPORT_INVALID', 'le message doit appartenir à la personne signalée');
select throws_ok($$ select public.report('support') $$, 'P0001', 'REPORT_INVALID',
  'une demande d''assistance exige un texte');
select isnt(public.report('support', p_details => 'Je ne reçois pas les codes SMS'), null,
  'demande d''assistance enregistrée');
select throws_ok($$ select * from private.reports $$, '42501', null,
  'les signalements sont illisibles depuis l''application');
insert into t values ('ma', (select id from public.send_message((select v from t where k = 'conv'), gen_random_uuid(), 'Réponse de A')));

reset role;
select is((select evidence ->> 'body' from private.reports where id = (select v from t where k = 'r1')),
  'Message abusif', 'copie du message jointe avec l''accord de la personne');
select is((select evidence from private.reports where id = (select v from t where k = 'r2')), null,
  'sans accord : aucune copie du contenu');
select is((select purge_after::date - created_at::date from private.reports where id = (select v from t where k = 'r1')),
  90, 'conservation : 90 jours (B3)');

-- La copie survit à l'expiration du message, puis disparaît à échéance.
update public.messages set sent_at = now() - interval '73 hours', expires_at = now() - interval '1 hour'
 where id = (select v from t where k = 'm1');
select private.purge_expired();
select is((select evidence ->> 'body' from private.reports where id = (select v from t where k = 'r1')),
  'Message abusif', 'la copie reste disponible pour la modération après expiration du message');
update private.reports set purge_after = now() - interval '1 minute' where id = (select v from t where k = 'r1');
select private.purge_expired();
select is((select count(*)::int from private.reports where id = (select v from t where k = 'r1')), 0,
  'à échéance, le signalement et sa copie sont effacés');

-- Suppression du compte de B.
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok($$ select public.delete_my_account('oui') $$, 'P0001', 'CONFIRMATION_REQUIRED',
  'confirmation explicite exigée');
select lives_ok($$ select public.delete_my_account('SUPPRIMER') $$, 'B supprime son compte');

reset role;
select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-0000000000b1'), 0,
  'compte Auth supprimé');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-0000000000b1'), 0,
  'profil supprimé');
select is((select count(*)::int from private.user_contacts where user_id = '00000000-0000-0000-0000-0000000000b1'), 0,
  'numéro de téléphone supprimé');
select is((select count(*)::int from public.messages where conversation_id = (select v from t where k = 'conv')
             and id <> (select v from t where k = 'ma')), 0,
  'ses messages sont effacés chez son correspondant');
select is((select body from public.messages where id = (select v from t where k = 'ma')), 'Réponse de A',
  'les messages de A restent jusqu''à leur expiration');
select is((select count(*)::int from private.reports where id = (select v from t where k = 'r2')), 1,
  'les signalements le concernant restent pour la modération (sans lien de compte)');

select pg_temp.as_user('a');
set local role authenticated;
select is((select peer_deleted from public.list_conversations() where conversation_id = (select v from t where k = 'conv')),
  true, 'chez A, la discussion indique « compte supprimé »');

reset role;
select * from finish();
rollback;
