-- Lot 7.2c2 — messages épinglés, favoris, infos d'un message, « Mentions seulement ».
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
create function pg_temp.tok() returns text language sql as $$
  select value from private.runtime_settings where key = 'push_dispatch_token' $$;
create function pg_temp.send(p_conv text, p_body text) returns text language sql as $$
  select id::text from public.send_message(pg_temp.v(p_conv)::uuid, gen_random_uuid(), p_body) $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text),
  pg_temp.send(text, text) to authenticated;

-- Discussion Alice–Bob ; groupe d'Alice avec Bob et Carla (membres).
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t values ('g', public.create_group('Voisins', null,
  array[pg_temp.uid('b'), pg_temp.uid('c')])::text);
select pg_temp.as_user('b');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
select pg_temp.as_user('c');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
select pg_temp.as_user('a');
insert into t values ('m1', pg_temp.send('ab', 'Un'));
insert into t values ('m2', pg_temp.send('ab', 'Deux'));
insert into t values ('m3', pg_temp.send('ab', 'Trois'));
insert into t values ('m4', pg_temp.send('ab', 'Quatre'));
insert into t values ('g1', pg_temp.send('g', 'Bonjour le groupe'));

-- ---------------------------------------------------------------------------
-- Épingler
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
select lives_ok(format($$ select public.pin_message(%L, true) $$, pg_temp.v('m1')),
  'discussion à deux : Bob épingle un message d''Alice');
select lives_ok(format($$ select public.pin_message(%L, true) $$, pg_temp.v('m1')),
  'épingler deux fois : sans effet');
select pg_temp.as_user('a');
select public.pin_message(pg_temp.v('m2')::uuid, true);
select public.pin_message(pg_temp.v('m3')::uuid, true);
select is((select count(*)::int from public.list_pinned_messages(pg_temp.v('ab')::uuid)), 3,
  'trois messages épinglés, visibles par Alice');
select throws_ok(format($$ select public.pin_message(%L, true) $$, pg_temp.v('m4')),
  'P0001', 'PIN_LIMIT_REACHED', 'un quatrième : refusé (3 au plus)');
select pg_temp.as_user('b');
select is((select array_agg(body order by body) from public.list_pinned_messages(pg_temp.v('ab')::uuid)),
  array['Deux', 'Trois', 'Un'], 'Bob voit les mêmes épinglés');
select public.pin_message(pg_temp.v('m3')::uuid, false);
select is((select count(*)::int from public.list_pinned_messages(pg_temp.v('ab')::uuid)), 2,
  'désépinglé pour les deux');
select pg_temp.as_user('c');
select throws_ok(format($$ select public.list_pinned_messages(%L) $$, pg_temp.v('ab')),
  'P0001', 'NOT_MEMBER', 'une personne extérieure ne voit rien');
select throws_ok(format($$ select public.pin_message(%L, true) $$, pg_temp.v('g1')),
  'P0001', 'NOT_ADMIN', 'groupe : un membre ne peut pas épingler');
select pg_temp.as_user('a');
select lives_ok(format($$ select public.pin_message(%L, true) $$, pg_temp.v('g1')),
  'groupe : la créatrice épingle');
select pg_temp.as_user('c');
select is((select body from public.list_pinned_messages(pg_temp.v('g')::uuid)), 'Bonjour le groupe',
  'le membre voit le message épinglé');

-- Supprimé pour tous : il disparaît des épinglés (et libère la place).
select pg_temp.as_user('a');
select public.delete_message_for_everyone(pg_temp.v('m2')::uuid);
select is((select count(*)::int from public.list_pinned_messages(pg_temp.v('ab')::uuid)), 1,
  'message supprimé pour tous : plus épinglé');
select throws_ok(format($$ select public.pin_message(%L, true) $$, pg_temp.v('m2')),
  'P0001', 'MESSAGE_DELETED', 'un message supprimé ne s''épingle pas');

-- ---------------------------------------------------------------------------
-- Favoris
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
select is(public.set_message_favorites(array[pg_temp.v('m1')::uuid, pg_temp.v('m4')::uuid], true), 2,
  'deux favoris d''un coup (sélection multiple)');
select is((select array_agg(body order by body) from public.list_favorite_messages(pg_temp.v('ab')::uuid)),
  array['Quatre', 'Un'], 'liste des favoris de Bob');
select pg_temp.as_user('a');
select is((select count(*)::int from public.list_favorite_messages(pg_temp.v('ab')::uuid)), 0,
  'les favoris sont personnels');
select pg_temp.as_user('b');
select is(public.set_message_favorites(array[pg_temp.v('m4')::uuid], false), 1, 'retiré des favoris');
select public.delete_message_for_me(pg_temp.v('m3')::uuid);
select throws_ok(format($$ select public.set_message_favorites(array[%L::uuid], true) $$, pg_temp.v('m3')),
  'P0001', 'MESSAGE_NOT_FOUND', 'un message supprimé chez moi : refusé');
select pg_temp.as_user('d');
select throws_ok(format($$ select public.set_message_favorites(array[%L::uuid], true) $$, pg_temp.v('m1')),
  'P0001', 'MESSAGE_NOT_FOUND', 'une personne extérieure : refusé');

-- Expiré : favori et épinglé disparaissent avec le message.
reset role;
update public.messages set sent_at = now() - interval '73 hours', expires_at = now() - interval '1 hour'
 where id = pg_temp.v('m1')::uuid;
select pg_temp.as_user('b');
set local role authenticated;
select is((select count(*)::int from public.list_favorite_messages(pg_temp.v('ab')::uuid)), 0,
  'message expiré : plus dans les favoris');
select is((select count(*)::int from public.list_pinned_messages(pg_temp.v('ab')::uuid)), 0,
  'message expiré : plus épinglé');
reset role;
delete from public.messages where id = pg_temp.v('m1')::uuid;
select is((select count(*)::int from private.message_favorites where message_id = pg_temp.v('m1')::uuid), 0,
  'message purgé : favori effacé en cascade');
select is((select count(*)::int from private.message_pins where message_id = pg_temp.v('m1')::uuid), 0,
  'message purgé : épinglé effacé en cascade');

-- ---------------------------------------------------------------------------
-- Infos d'un message
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok(format($$ select * from public.get_message_info(%L) $$, pg_temp.v('m4')),
  'P0001', 'NOT_SENDER', 'seulement pour ses propres messages');
select pg_temp.as_user('a');
select results_eq(format($$ select display_name, delivered, read from public.get_message_info(%L) $$, pg_temp.v('m4')),
  $$ values ('Bob'::text, false, false) $$, 'pas encore distribué');
select pg_temp.as_user('b');
select public.mark_conversation(pg_temp.v('ab')::uuid, p_delivered_up_to => now());
select pg_temp.as_user('a');
select results_eq(format($$ select delivered, delivered_at is not null, read from public.get_message_info(%L) $$, pg_temp.v('m4')),
  $$ values (true, true, false) $$, 'distribué, avec l''heure ; pas lu');
select pg_temp.as_user('b');
select public.mark_conversation(pg_temp.v('ab')::uuid, now(), now());
select pg_temp.as_user('a');
select results_eq(format($$ select read, read_at is not null, receipts_hidden from public.get_message_info(%L) $$, pg_temp.v('m4')),
  $$ values (true, true, false) $$, 'lu, avec l''heure');
reset role;
select is((select count(*)::int from private.receipt_marks
            where conversation_id = pg_temp.v('ab')::uuid and user_id = pg_temp.uid('b')), 2,
  'une trace par avancée (distribué, puis lu)');
select pg_temp.as_user('b');
set local role authenticated;
select public.mark_conversation(pg_temp.v('ab')::uuid, now() - interval '1 hour');
reset role;
select is((select count(*)::int from private.receipt_marks
            where conversation_id = pg_temp.v('ab')::uuid and user_id = pg_temp.uid('b')), 2,
  'un accusé plus ancien : aucune trace');
set local role authenticated;
select pg_temp.as_user('b');
-- Bob désactive ses accusés de lecture dans cette discussion : la lecture est cachée.
select public.set_conversation_privacy(pg_temp.v('ab')::uuid, false, null, null, null, null);
select pg_temp.as_user('a');
select results_eq(format($$ select delivered, read, read_at, receipts_hidden from public.get_message_info(%L) $$, pg_temp.v('m4')),
  $$ values (true, false, null::timestamptz, true) $$, 'accusés désactivés : lecture cachée');

-- Groupe : une ligne par membre.
select is((select count(*)::int from public.get_message_info(pg_temp.v('g1')::uuid)), 2,
  'groupe : Bob et Carla');

-- ---------------------------------------------------------------------------
-- Mentions seulement
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c');
select public.register_device('android', 'test');
select public.register_push_token('jeton-fcm-c-carla-00000000001');
select is(public.get_notify_mode(pg_temp.v('g')::uuid), 'all', 'par défaut : tout');
select public.set_notify_mode(pg_temp.v('g')::uuid, 'mentions');
select is(public.get_notify_mode(pg_temp.v('g')::uuid), 'mentions', 'mentions seulement');
select throws_ok(format($$ select public.set_notify_mode(%L, 'rien') $$, pg_temp.v('g')),
  'P0001', 'SETTING_INVALID', 'valeur inconnue : refusée');
select pg_temp.as_user('a');
select throws_ok(format($$ select public.set_notify_mode(%L, 'mentions') $$, pg_temp.v('ab')),
  'P0001', 'NOT_GROUP', 'discussion à deux : pas de « mentions seulement »');
insert into t values ('g2', pg_temp.send('g', 'Sans mention'));
insert into t select 'g3', id::text from public.send_message(pg_temp.v('g')::uuid, gen_random_uuid(),
  '@Carla tu viens ?', null, null, array[pg_temp.uid('c')]);
reset role;
select is((select count(*)::int from public.push_targets(pg_temp.tok(), pg_temp.v('g2')::uuid)
            where token = 'jeton-fcm-c-carla-00000000001'), 0,
  'mentions seulement : pas de notification pour un message ordinaire');
select is((select count(*)::int from public.push_targets(pg_temp.tok(), pg_temp.v('g3')::uuid)
            where token = 'jeton-fcm-c-carla-00000000001' and mentioned), 1,
  'mentions seulement : notifiée quand on la mentionne');

select * from finish();
rollback;
