-- Lot 10.5 — groupes « Annonces » (type définitif, seuls les administrateurs écrivent,
-- membres cachés aux simples membres, plafond propre) et sondages éphémères (groupes
-- seulement, anonymes ou visibles, vote modifiable, fermeture par le créateur).
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
  ('00000000-0000-0000-0000-0000000000d1', 'dao', 'Dao');

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
create function pg_temp.accept() returns void language sql as $$
  select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true) $$;
create function pg_temp.poll(p_conv text, p_q text, p_opts text[], p_multi boolean default false,
                             p_anon boolean default true) returns text language sql as $$
  select to_jsonb(r) ->> 'id'
    from public.send_poll(p_conv::uuid, gen_random_uuid(), p_q, p_opts, p_multi, p_anon) r $$;
create function pg_temp.state(p_conv text, p_msg text) returns jsonb language sql as $$
  select m.poll from public.get_messages(p_conv::uuid) m where m.id = p_msg::uuid $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text), pg_temp.accept(),
  pg_temp.poll(text, text, text[], boolean, boolean), pg_temp.state(text, text) to authenticated;

-- ------------------------------------------------------------------ Groupe « Annonces »
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ann', public.create_group('Infos du quartier', null,
  array[pg_temp.uid('b'), pg_temp.uid('c')], true)::text);
insert into t values ('fam', public.create_group('Famille', null, array[pg_temp.uid('b'), pg_temp.uid('c')])::text);
reset role;
select is((select posting from public.conversations where id = pg_temp.v('ann')::uuid), 'admins',
  'groupe « Annonces » : seuls les administrateurs écrivent');
select is((select announcement from public.conversations where id = pg_temp.v('fam')::uuid), false,
  'groupe normal par défaut');

select pg_temp.as_user('b');
set local role authenticated;
select pg_temp.accept();
select pg_temp.accept();
reset role;
select pg_temp.as_user('c');
set local role authenticated;
select pg_temp.accept();
select pg_temp.accept();
reset role;

select pg_temp.as_user('a');
set local role authenticated;
select is((select announcement from public.list_conversations() where conversation_id = pg_temp.v('ann')::uuid),
  true, 'la liste indique un groupe « Annonces »');
select is((select count(*)::int from public.get_conversation_members(pg_temp.v('ann')::uuid)), 3,
  'l''administratrice voit tous les membres');
select throws_ok(format($$ select public.set_group_settings(%L, 'all') $$, pg_temp.v('ann')),
  'P0001', 'ANNOUNCEMENT_LOCKED', 'un groupe « Annonces » ne s''ouvre pas à tous');
insert into t select 'm1', to_jsonb(r) ->> 'id'
  from public.send_message(pg_temp.v('ann')::uuid, gen_random_uuid(), 'Coupure d''eau demain') r;
reset role;
select throws_ok(format($$ update public.conversations set announcement = false where id = %L $$, pg_temp.v('ann')),
  'P0001', 'ANNOUNCEMENT_LOCKED', 'le type ne change jamais');
-- Une seule transaction : l'annonce passe après les arrivées.
update public.messages set sent_at = now() + interval '1 second' where id = pg_temp.v('m1')::uuid;

select pg_temp.as_user('b');
set local role authenticated;
select results_eq(format($$ select user_id from public.get_conversation_members(%L) order by user_id $$, pg_temp.v('ann')),
  format($$ values (%L::uuid), (%L::uuid) $$, pg_temp.uid('a'), pg_temp.uid('b')),
  'un membre ne voit que l''administratrice et lui-même');
select throws_ok(format($$ select public.send_message(%L, gen_random_uuid(), 'Moi aussi') $$, pg_temp.v('ann')),
  'P0001', 'POSTING_RESTRICTED', 'un membre n''écrit pas');
select lives_ok(format($$ select public.set_reaction(%L, '👍') $$, pg_temp.v('m1')), 'un membre réagit');
select is((select count(*)::int from public.get_messages(pg_temp.v('ann')::uuid) m
            where m.kind = 'system' and m.body like '%"joined"%'), 1,
  'un membre ne voit que sa propre arrivée');
select is((select last_kind from public.list_conversations() where conversation_id = pg_temp.v('ann')::uuid),
  'text', 'aperçu de la liste : l''annonce, pas l''arrivée d''un autre membre');
select is((select count(*)::int from public.list_common_groups(pg_temp.uid('c'))), 1,
  'groupes en commun avec un autre membre : le groupe normal seulement');
select is((select count(*)::int from public.list_common_groups(pg_temp.uid('a'))), 2,
  'groupes en commun avec l''administratrice : les deux');
reset role;

select pg_temp.as_user('c');
set local role authenticated;
select public.set_reaction(pg_temp.v('m1')::uuid, '❤️');
select is((select jsonb_path_query_array(m.reactions, '$[*].user_id')
             from public.get_messages(pg_temp.v('ann')::uuid) m where m.id = pg_temp.v('m1')::uuid),
  format('[null, "%s"]', pg_temp.uid('c'))::jsonb, 'un membre ne voit pas qui d''autre a réagi');
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select is((select jsonb_array_length(jsonb_path_query_array(m.reactions, '$[*] ? (@.user_id != null)'))
             from public.get_messages(pg_temp.v('ann')::uuid) m where m.id = pg_temp.v('m1')::uuid),
  2, 'l''administratrice voit qui a réagi');
reset role;

-- Plafond propre aux groupes « Annonces ».
insert into private.policies (key, value) values ('announcement_max_members', '3');
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select private.invite(%L, %L, %L) $$, pg_temp.v('ann'), pg_temp.uid('a'), pg_temp.uid('d')),
  '42501', null, 'fonctions privées inaccessibles');
reset role;
select throws_ok(format($$ select private.invite(%L, %L, %L) $$, pg_temp.v('ann'), pg_temp.uid('a'), pg_temp.uid('d')),
  'P0001', 'GROUP_FULL', 'plafond « Annonces » atteint');
update private.policies set value = '500' where key = 'announcement_max_members';
select is(private.group_member_cap(pg_temp.v('ann')::uuid), 500, 'plafond « Annonces » réglable');
select is(private.group_member_cap(pg_temp.v('fam')::uuid), private.policy_int('group_max_members'),
  'groupe normal : plafond habituel');

-- ------------------------------------------------------------------ Sondages
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok(format($$ select pg_temp.poll(%L, 'Réunion ?', array['Oui', 'Non']) $$, pg_temp.v('ann')),
  'P0001', 'POSTING_RESTRICTED', 'groupe « Annonces » : un membre ne crée pas de sondage');
select throws_ok(format($$ select pg_temp.poll(%L, 'Un seul choix ?', array['Oui', '  ']) $$, pg_temp.v('fam')),
  'P0001', 'POLL_INVALID', 'au moins deux choix');
select throws_ok(format($$ select pg_temp.poll(%L, 'Doublon ?', array['Oui', 'oui']) $$, pg_temp.v('fam')),
  'P0001', 'POLL_INVALID', 'pas deux fois le même choix');
insert into t values ('dir', public.start_direct_conversation(pg_temp.uid('c'))::text);
select throws_ok(format($$ select pg_temp.poll(%L, 'Ciné ?', array['Oui', 'Non']) $$, pg_temp.v('dir')),
  'P0001', 'POLL_GROUP_ONLY', 'pas de sondage dans une discussion à deux');
-- Groupe normal : tout membre peut créer un sondage ; votes visibles.
insert into t values ('pv', pg_temp.poll(pg_temp.v('fam'), '  Quel   jour ? ', array['Samedi', 'Dimanche', 'Lundi'], true, false));
select is((select body from public.messages where id = pg_temp.v('pv')::uuid), 'Quel jour ?',
  'la question est le corps du message (espaces nettoyés)');
select is(public.vote_poll(pg_temp.v('pv')::uuid, array[0, 1]) -> 'mine', '[0, 1]'::jsonb,
  'plusieurs réponses');
select throws_ok(format($$ select public.edit_message(%L, 'Autre question') $$, pg_temp.v('pv')),
  'P0001', 'MESSAGE_NOT_EDITABLE', 'un sondage ne se modifie pas');
reset role;

select pg_temp.as_user('c');
set local role authenticated;
select is(public.vote_poll(pg_temp.v('pv')::uuid, array[1]) -> 'counts', '[1, 2, 0]'::jsonb, 'totaux par choix');
select is(pg_temp.state(pg_temp.v('fam'), pg_temp.v('pv')) -> 'by_option' -> 0,
  format('["%s"]', pg_temp.uid('b'))::jsonb, 'vote visible : on voit qui a choisi quoi');
select is((pg_temp.state(pg_temp.v('fam'), pg_temp.v('pv')) ->> 'voters')::int, 2, '2 votants');
select throws_ok(format($$ select public.close_poll(%L) $$, pg_temp.v('pv')),
  'P0001', 'NOT_SENDER', 'seul le créateur ferme le sondage');
select is(public.vote_poll(pg_temp.v('pv')::uuid, '{}') -> 'counts', '[1, 1, 0]'::jsonb, 'vote retiré');
select throws_ok(format($$ select public.vote_poll(%L, array[3]) $$, pg_temp.v('pv')),
  'P0001', 'POLL_INVALID', 'choix inexistant');
reset role;

select pg_temp.as_user('b');
set local role authenticated;
select lives_ok(format($$ select public.close_poll(%L) $$, pg_temp.v('pv')), 'le créateur ferme le sondage');
reset role;
select pg_temp.as_user('c');
set local role authenticated;
select throws_ok(format($$ select public.vote_poll(%L, array[0]) $$, pg_temp.v('pv')),
  'P0001', 'POLL_CLOSED', 'sondage fermé : plus de vote');
select isnt(pg_temp.state(pg_temp.v('fam'), pg_temp.v('pv')) ->> 'closed_at', null, 'fermeture visible');
reset role;

-- Groupe « Annonces » : sondage de l'administratrice, une réponse, anonyme.
select pg_temp.as_user('a');
set local role authenticated;
select public.set_read_erase(pg_temp.v('ann')::uuid, 30);
insert into t values ('pa', pg_temp.poll(pg_temp.v('ann'), 'Nettoyage samedi ?', array['Oui', 'Non']));
insert into t values ('pv2', pg_temp.poll(pg_temp.v('ann'), 'Qui vient ?', array['Moi', 'Pas moi'], false, false));
reset role;
select is((select read_erase_seconds from public.messages where id = pg_temp.v('pa')::uuid), null,
  'un sondage n''est pas effacé après lecture');

select pg_temp.as_user('b');
set local role authenticated;
select is((select unread_count from public.list_conversations() where conversation_id = pg_temp.v('ann')::uuid),
  3, 'les sondages comptent comme non lus');
select throws_ok(format($$ select public.vote_poll(%L, array[0, 1]) $$, pg_temp.v('pa')),
  'P0001', 'POLL_INVALID', 'une seule réponse');
select lives_ok(format($$ select public.vote_poll(%L, array[0]) $$, pg_temp.v('pa')), 'un membre vote');
select lives_ok(format($$ select public.vote_poll(%L, array[0]) $$, pg_temp.v('pv2')), 'vote visible');
select is(pg_temp.state(pg_temp.v('ann'), pg_temp.v('pa')) -> 'by_option', 'null'::jsonb,
  'vote anonyme : aucun votant');
select is(pg_temp.state(pg_temp.v('ann'), pg_temp.v('pv2')) -> 'by_option', 'null'::jsonb,
  'groupe « Annonces » : un membre ne voit pas les votants');
reset role;
select pg_temp.as_user('c');
set local role authenticated;
select public.vote_poll(pg_temp.v('pa')::uuid, array[1]);
select is(pg_temp.state(pg_temp.v('ann'), pg_temp.v('pa')) -> 'counts', '[1, 1]'::jsonb, 'totaux anonymes');
select is(pg_temp.state(pg_temp.v('ann'), pg_temp.v('pa')) -> 'mine', '[1]'::jsonb, 'mon vote');
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select is(pg_temp.state(pg_temp.v('ann'), pg_temp.v('pa')) -> 'by_option', 'null'::jsonb,
  'anonyme même pour son créateur');
select is(pg_temp.state(pg_temp.v('ann'), pg_temp.v('pv2')) -> 'by_option' -> 0,
  format('["%s"]', pg_temp.uid('b'))::jsonb, 'l''administratrice voit les votants d''un vote visible');
select public.delete_message_for_everyone(pg_temp.v('pa')::uuid);
reset role;
select is((select count(*)::int from private.poll_votes where message_id = pg_temp.v('pa')::uuid), 0,
  'supprimé pour tous : les votes partent');

-- Effacé avec le message.
update public.messages set sent_at = now() - interval '2 hours', expires_at = now() - interval '1 second'
 where id = pg_temp.v('pv2')::uuid;
select private.purge_expired();
select is((select count(*)::int from private.polls where message_id = pg_temp.v('pv2')::uuid), 0,
  'sondage et votes effacés avec le message');

set local role authenticated;
select throws_ok($$ select count(*) from private.poll_votes $$, '42501', null, 'votes inaccessibles directement');
reset role;

select * from finish();
rollback;
