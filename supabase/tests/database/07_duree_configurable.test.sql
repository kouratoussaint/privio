-- Lot 2.E — Durée d'expiration configurable par discussion et par message.
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

select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('conv', public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1'));

select is((select ttl_seconds from public.list_conversations() where conversation_id = (select v from t where k = 'conv')),
  259200, 'par défaut : 72 h');
select throws_ok(format($$ select public.set_conversation_ttl(%L, 60) $$, (select v from t where k = 'conv')),
  'P0001', 'TTL_INVALID', 'en dessous du minimum (5 min) : refusé');
select throws_ok(format($$ select public.set_conversation_ttl(%L, 300000) $$, (select v from t where k = 'conv')),
  'P0001', 'TTL_INVALID', 'au-delà de 72 h : refusé');
select is(public.set_conversation_ttl((select v from t where k = 'conv'), 3600), 3600, 'A règle la discussion sur 1 h');
select is((select ttl_seconds from public.list_conversations() where conversation_id = (select v from t where k = 'conv')),
  3600, 'la liste expose la nouvelle durée');
select is((select body from public.get_messages((select v from t where k = 'conv')) where kind = 'system'), 'ttl:3600',
  'un message système annonce le changement');
select is((select expires_at - sent_at from public.get_messages((select v from t where k = 'conv')) where kind = 'system'),
  interval '1 hour', 'le message système suit lui aussi la nouvelle durée');

insert into t values ('m1', (select id from public.send_message((select v from t where k = 'conv'), gen_random_uuid(), 'Court')));
select is((select expires_at - sent_at from public.messages where id = (select v from t where k = 'm1')),
  interval '1 hour', 'un nouveau message suit la durée de la discussion');
insert into t values ('m2', (select id from public.send_message((select v from t where k = 'conv'), gen_random_uuid(), 'Très court', null, 300)));
select is((select expires_at - sent_at from public.messages where id = (select v from t where k = 'm2')),
  interval '5 minutes', 'durée choisie pour un seul message : 5 min');
insert into t values ('m3', (select id from public.send_message((select v from t where k = 'conv'), gen_random_uuid(), 'Trop long', null, 7200)));
select is((select expires_at - sent_at from public.messages where id = (select v from t where k = 'm3')),
  interval '1 hour', 'un message ne dépasse jamais la durée de la discussion');
select throws_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), 'x', null, 30) $$, (select v from t where k = 'conv')),
  'P0001', 'TTL_INVALID', 'durée de message trop courte refusée');

-- Le message système est intouchable.
select throws_ok(format($$ select public.edit_message(%L, 'piraté') $$,
  (select id from public.get_messages((select v from t where k = 'conv')) where kind = 'system')),
  'P0001', 'MESSAGE_NOT_EDITABLE', 'un message système ne se modifie pas');

reset role;
select pg_temp.as_user('b');
set local role authenticated;
select is((select unread_count from public.list_conversations()), 3, 'B : seuls les 3 messages texte comptent comme non lus');
select throws_ok(format($$ select public.set_reaction(%L, '👍') $$,
  (select id from public.get_messages((select v from t where k = 'conv')) where kind = 'system')),
  'P0001', 'MESSAGE_NOT_EDITABLE', 'pas de réaction sur un message système');
select is(public.set_conversation_ttl((select v from t where k = 'conv'), 86400), 86400,
  'B peut aussi régler la durée (24 h)');

reset role;
select pg_temp.as_user('c');
set local role authenticated;
select throws_ok(format($$ select public.set_conversation_ttl(%L, 3600) $$, (select v from t where k = 'conv')),
  'P0001', 'NOT_MEMBER', 'un non-membre ne peut pas régler la durée');

-- L'administration abaisse le maximum à 12 h : la discussion à 24 h est bornée.
reset role;
insert into private.policies (key, value) values ('message_ttl_hours', '12');
select pg_temp.as_user('a');
set local role authenticated;
select is((select ttl_seconds from public.list_conversations() where conversation_id = (select v from t where k = 'conv')),
  43200, 'la durée effective respecte le nouveau maximum (12 h)');

reset role;
select * from finish();
rollback;
