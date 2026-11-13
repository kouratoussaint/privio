-- Lot 4.8 — Invitations de groupe notifiées : une notification sans contenu par invitation,
-- à l'invité seulement, tant que l'invitation est en attente ; réservée au service.
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
  select value from private.runtime_settings where key = 'push_dispatch_token';
$$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text) to authenticated;

-- Adresse des fonctions (posée au déploiement) : nécessaire pour l'appel pg_net.
insert into private.runtime_settings (key, value) values ('functions_url', 'http://fonctions.test/functions/v1')
on conflict (key) do update set value = excluded.value;

-- Bob a un appareil et un jeton ; Carla n'en a pas.
select pg_temp.as_user('b');
set local role authenticated;
select public.register_device('android', 'test');
select public.register_push_token('jeton-fcm-de-bob-000000000001');
reset role;

create temporary table q0 on commit drop as select coalesce(max(id), 0) as id from net.http_request_queue;

-- Alice crée un groupe et invite Bob et Carla.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('g', public.create_group('Voisins', null,
  array[pg_temp.uid('b'), pg_temp.uid('c')])::text);
reset role;

insert into t select 'ib', id::text from private.group_invitations
 where conversation_id = pg_temp.v('g')::uuid and invitee_id = pg_temp.uid('b');
insert into t select 'ic', id::text from private.group_invitations
 where conversation_id = pg_temp.v('g')::uuid and invitee_id = pg_temp.uid('c');

select results_eq(
  $$ select convert_from(q.body, 'utf8')::jsonb from net.http_request_queue q
      where q.id > (select id from q0) and q.url like '%/push-dispatch' $$,
  $$ select jsonb_build_object('invitation_id', pg_temp.v('ib')) $$,
  'création du groupe : une notification demandée pour Bob, avec le seul identifiant');
select is((select count(*)::int from net.http_request_queue q
            where q.id > (select id from q0) and convert_from(q.body, 'utf8') like '%' || pg_temp.v('ic') || '%'), 0,
  'Carla n''a pas de jeton : aucun appel inutile');
select is((select count(*)::int from net.http_request_queue q
            where q.id > (select id from q0)
              and (convert_from(q.body, 'utf8') like '%Voisins%' or convert_from(q.body, 'utf8') like '%Alice%')), 0,
  'ni le nom du groupe ni celui d''Alice ne sortent de la base');

-- Cibles : l'invité seulement, avec le jeton du service.
select results_eq(format($$ select token from public.push_invitation_targets(%L, %L) $$, pg_temp.tok(), pg_temp.v('ib')),
  $$ values ('jeton-fcm-de-bob-000000000001'::text) $$, 'cible : le jeton de Bob');
select throws_ok(format($$ select * from public.push_invitation_targets('mauvais', %L) $$, pg_temp.v('ib')),
  'P0001', 'AUTH_REQUIRED', 'jeton du service obligatoire');
select ok(not has_function_privilege('authenticated', 'public.push_invitation_targets(text, uuid)', 'execute'),
  'cibles interdites aux utilisateurs');
select is((select count(*)::int from information_schema.parameters
            where specific_schema = 'public' and specific_name like 'push_invitation_targets%'
              and parameter_mode = 'OUT'), 1, 'seul le jeton est renvoyé (aucun nom, aucun titre)');

-- Blocage entre l'invitant et l'invité : rien.
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('b'), pg_temp.uid('a'));
select is_empty(format($$ select * from public.push_invitation_targets(%L, %L) $$, pg_temp.tok(), pg_temp.v('ib')),
  'blocage : aucune notification');
delete from public.blocks;

-- Appareil révoqué : rien.
update public.devices set revoked_at = now(), revoked_reason = 'new_device' where user_id = pg_temp.uid('b');
select is_empty(format($$ select * from public.push_invitation_targets(%L, %L) $$, pg_temp.tok(), pg_temp.v('ib')),
  'appareil révoqué : aucune notification');
update public.devices set revoked_at = null, revoked_reason = null where user_id = pg_temp.uid('b');

-- Invitation acceptée (ou échue) : plus rien à notifier.
select pg_temp.as_user('b');
set local role authenticated;
select is(public.respond_to_invitation(pg_temp.v('ib')::uuid, true)::text, pg_temp.v('g'),
  'Bob accepte et rejoint le groupe');
reset role;
select is_empty(format($$ select * from public.push_invitation_targets(%L, %L) $$, pg_temp.tok(), pg_temp.v('ib')),
  'invitation acceptée : aucune notification');
update private.group_invitations set expires_at = now() - interval '1 second' where id = pg_temp.v('ic')::uuid;
select is_empty(format($$ select * from public.push_invitation_targets(%L, %L) $$, pg_temp.tok(), pg_temp.v('ic')),
  'invitation échue : aucune notification');

-- Invitation depuis la fiche du groupe : même notification.
delete from net.http_request_queue where id > (select id from q0);
insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000d1', '22670000004', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000dddd', '00000000-0000-0000-0000-0000000000d1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000d1', 'dani', 'Dani');
select pg_temp.as_user('d');
set local role authenticated;
select public.register_device('android', 'test');
select public.register_push_token('jeton-fcm-de-dani-00000000001');
select pg_temp.as_user('a');
select is(public.invite_to_group(pg_temp.v('g')::uuid, array[pg_temp.uid('d')]), 1, 'Alice invite Dani');
reset role;
select is((select count(*)::int from net.http_request_queue q
            where q.id > (select id from q0) and q.url like '%/push-dispatch'
              and convert_from(q.body, 'utf8')::jsonb ? 'invitation_id'), 1,
  'invitation depuis la fiche : notification demandée');

select * from finish();
rollback;
