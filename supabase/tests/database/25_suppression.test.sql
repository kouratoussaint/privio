-- Lot 7.2b1 — supprimer une discussion (chez moi, pour nous deux) ou un groupe (pour tous).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

insert into auth.users (id, phone, phone_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '2267000000' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3), ('d', 4)) as x(p, n);
insert into auth.sessions (id, user_id)
select ('00000000-0000-0000-0000-00000000' || repeat(p, 4))::uuid,
       ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid
  from (values ('a'), ('b'), ('c'), ('d')) as x(p);
insert into public.profiles (id, handle, display_name)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, h, n
  from (values ('a', 'alice_bf', 'Alice'), ('b', 'bob_ouaga', 'Bob'), ('c', 'carla', 'Carla'),
               ('d', 'dani', 'Dani')) as x(p, h, n);

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
create function pg_temp.listed(p_k text) returns boolean language sql as $$
  select exists (select 1 from public.list_conversations() where conversation_id = pg_temp.v(p_k)::uuid) $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text), pg_temp.listed(text) to authenticated;

select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t values ('ac', public.start_direct_conversation(pg_temp.uid('c'))::text);
select * from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Bonjour Bob');
select * from public.send_message(pg_temp.v('ac')::uuid, gen_random_uuid(), 'Bonjour Carla');
-- Une seule transaction : les messages reçoivent la même heure ; on les date juste avant.
reset role;
update public.messages set sent_at = sent_at - interval '1 minute', expires_at = expires_at - interval '1 minute';
select pg_temp.as_user('a');
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Supprimer chez moi
-- ---------------------------------------------------------------------------
select is(public.delete_conversation(pg_temp.v('ab')::uuid, 'me'), 'deleted', 'Alice supprime chez elle');
select ok(not pg_temp.listed('ab'), 'disparue de sa liste');
select is_empty(format($$ select * from public.get_messages(%L) $$, pg_temp.v('ab')), 'sa copie est vide');
select pg_temp.as_user('b');
select ok(pg_temp.listed('ab'), 'Bob la garde');
select isnt_empty(format($$ select * from public.get_messages(%L) $$, pg_temp.v('ab')), 'avec ses messages');
select * from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Tu es là ?');
reset role;
update public.messages set sent_at = sent_at + interval '1 minute', expires_at = expires_at + interval '1 minute'
 where body = 'Tu es là ?';
select pg_temp.as_user('a');
set local role authenticated;
select ok(pg_temp.listed('ab'), 'nouveau message : elle revient chez Alice');
select results_eq(format($$ select body from public.get_messages(%L) $$, pg_temp.v('ab')),
  $$ values ('Tu es là ?'::text) $$, 'seulement le nouveau message');

-- ---------------------------------------------------------------------------
-- Supprimer pour nous deux (avec accord)
-- ---------------------------------------------------------------------------
select is(public.delete_conversation(pg_temp.v('ac')::uuid, 'everyone'), 'requested', 'demande envoyée à Carla');
select is((select clear_request_delete from public.list_conversations() where conversation_id = pg_temp.v('ac')::uuid),
  true, 'la demande est une suppression');
select ok(pg_temp.listed('ac'), 'rien ne change avant l''accord');
select pg_temp.as_user('c');
select is(public.respond_clear_request(pg_temp.v('ac')::uuid, true), 'deleted', 'Carla accepte');
select ok(not pg_temp.listed('ac'), 'disparue chez Carla');
select pg_temp.as_user('a');
select ok(not pg_temp.listed('ac'), 'disparue chez Alice');
reset role;
select is((select count(*)::int from public.messages where conversation_id = pg_temp.v('ac')::uuid), 0,
  'messages effacés de la base');
select pg_temp.as_user('a');
set local role authenticated;

-- Refus : rien ne disparaît.
select * from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Encore là');
select is(public.delete_conversation(pg_temp.v('ab')::uuid, 'everyone'), 'requested', 'nouvelle demande à Bob');
select pg_temp.as_user('b');
select is(public.respond_clear_request(pg_temp.v('ab')::uuid, false), 'refused', 'Bob refuse');
select ok(pg_temp.listed('ab'), 'la discussion reste chez Bob');
select pg_temp.as_user('a');
select ok(pg_temp.listed('ab'), 'et chez Alice');
select throws_ok($$ select public.delete_conversation(null, 'me') $$, 'P0001', 'NOT_MEMBER', 'discussion inconnue');
select throws_ok(format($$ select public.delete_conversation(%L, 'tout') $$, pg_temp.v('ab')),
  'P0001', 'CLEAR_SCOPE_INVALID', 'choix inconnu');

-- ---------------------------------------------------------------------------
-- Supprimer un groupe pour tous
-- ---------------------------------------------------------------------------
insert into t values ('g', public.create_group('Voisins', null, array[pg_temp.uid('b'), pg_temp.uid('c'), pg_temp.uid('d')])::text);
select pg_temp.as_user('b');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
select pg_temp.as_user('c');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
select pg_temp.as_user('a');
select public.set_member_role(pg_temp.v('g')::uuid, pg_temp.uid('b'), 'admin');
select * from public.send_message(pg_temp.v('g')::uuid, gen_random_uuid(), 'Réunion samedi');
select pg_temp.as_user('c');
select throws_ok(format($$ select public.delete_conversation(%L, 'everyone') $$, pg_temp.v('g')),
  'P0001', 'NOT_ADMIN', 'un simple membre ne supprime pas le groupe');
select throws_ok(format($$ select public.delete_conversation(%L, 'me') $$, pg_temp.v('g')),
  'P0001', 'CLEAR_SCOPE_INVALID', 'groupe : pas de « chez moi » (on le quitte)');

select pg_temp.as_user('a');
insert into t values ('g2', public.create_group('Fermé', null, array[]::uuid[])::text);
reset role;
update public.conversations set posting = 'closed' where id = pg_temp.v('g2')::uuid;
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select public.delete_conversation(%L, 'everyone') $$, pg_temp.v('g2')),
  'P0001', 'GROUP_CLOSED', 'groupe fermé par Privio : pas de suppression');
select pg_temp.as_user('b');
select is(public.delete_conversation(pg_temp.v('g')::uuid, 'everyone'), 'deleted', 'Bob (administrateur) supprime le groupe');
select ok(not pg_temp.listed('g'), 'disparu chez Bob');
select is_empty($$ select * from public.list_group_deletion_notices() $$, 'pas d''avis pour l''auteur');
select pg_temp.as_user('a');
select ok(not pg_temp.listed('g'), 'disparu chez Alice');
select results_eq($$ select title from public.list_group_deletion_notices() $$, $$ values ('Voisins'::text) $$,
  'Alice voit « Le groupe Voisins a été supprimé »');
select pg_temp.as_user('d');
select is_empty($$ select * from public.list_group_deletion_notices() $$, 'pas d''avis pour une invitée qui n''avait pas répondu');
select is_empty($$ select * from public.list_my_invitations() $$, 'son invitation a disparu');
reset role;
select is((select count(*)::int from public.messages where conversation_id = pg_temp.v('g')::uuid), 0, 'messages effacés');
select is((select count(*)::int from public.conversations where id = pg_temp.v('g')::uuid), 0, 'groupe effacé');

select pg_temp.as_user('a');
set local role authenticated;
select lives_ok(format($$ select public.dismiss_group_deletion_notice(%L) $$,
  (select id from public.list_group_deletion_notices() limit 1)), 'Alice ferme l''avis');
select is_empty($$ select * from public.list_group_deletion_notices() $$, 'avis fermé');
select throws_ok($$ select * from private.group_deletion_notices $$, '42501', null, 'avis illisibles directement');

select * from finish();
rollback;
