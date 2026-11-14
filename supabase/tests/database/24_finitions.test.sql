-- Lot 7.2a — nom affiché modifiable ; confidentialité propre à une discussion ou un groupe.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

insert into auth.users (id, phone, phone_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '2267000000' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3)) as x(p, n);
insert into auth.sessions (id, user_id)
select ('00000000-0000-0000-0000-00000000' || repeat(p, 4))::uuid,
       ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid
  from (values ('a'), ('b'), ('c')) as x(p);
insert into public.profiles (id, handle, display_name, about, avatar_path) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice', 'Au travail', 'a/1.jpg'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob', null, null),
  ('00000000-0000-0000-0000-0000000000c1', 'carla', 'Carla', null, null);

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
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Nom affiché
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select is(public.set_my_display_name('  Alice   Ouédraogo '), 'Alice Ouédraogo', 'espaces nettoyés');
select is((select display_name from public.profiles where id = pg_temp.uid('a')), 'Alice Ouédraogo', 'nom changé');
select throws_ok($$ select public.set_my_display_name('   ') $$, 'P0001', 'DISPLAY_NAME_INVALID', 'vide : refusé');
select throws_ok(format($$ select public.set_my_display_name(%L) $$, repeat('x', 41)), 'P0001',
  'DISPLAY_NAME_INVALID', '41 caractères : refusé');
reset role;
insert into private.policies (key, value) values ('display_name_daily_limit', '2');
select pg_temp.as_user('a');
set local role authenticated;
select lives_ok($$ select public.set_my_display_name('Alice Ouédraogo') $$, 'même nom : rien n''est compté');
select lives_ok($$ select public.set_my_display_name('Alice O.') $$, '2e changement du jour');
select throws_ok($$ select public.set_my_display_name('Alice') $$, 'P0001', 'RATE_LIMITED', '3e : limité');
reset role;
update private.policies set value = '5' where key = 'display_name_daily_limit';

-- Discussions : Alice–Bob, Alice–Carla ; groupe Alice, Bob, Carla.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t values ('ac', public.start_direct_conversation(pg_temp.uid('c'))::text);
insert into t values ('g', public.create_group('Voisins', null, array[pg_temp.uid('b'), pg_temp.uid('c')])::text);
select pg_temp.as_user('b');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
select pg_temp.as_user('c');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);

-- ---------------------------------------------------------------------------
-- Réglages de la discussion
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
select results_eq(format($$ select * from public.get_conversation_privacy(%L) $$, pg_temp.v('ab')),
  $$ values (null::boolean, null::boolean, null::boolean, null::boolean, null::boolean) $$,
  'par défaut : comme dans mes réglages');
select throws_ok(format($$ select public.set_conversation_privacy(%L, null, null, true) $$, pg_temp.v('g')),
  'P0001', 'PRIVACY_SETTING_INVALID', 'groupe : pas de réglage « en ligne / photo / À propos »');
select pg_temp.as_user('b');
select throws_ok(format($$ select * from public.get_conversation_privacy(%L) $$, pg_temp.v('ac')),
  'P0001', 'NOT_MEMBER', 'hors de la discussion : refusé');

-- Accusés de lecture : Bob écrit, Alice lit ; elle les coupe pour Bob seulement.
select * from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Salut Alice');
select * from public.send_message(pg_temp.v('g')::uuid, gen_random_uuid(), 'Salut le groupe');
select pg_temp.as_user('c');
select public.mark_conversation(pg_temp.v('g')::uuid, now(), now());
select pg_temp.as_user('a');
select public.mark_conversation(pg_temp.v('ab')::uuid, now(), now());
select public.mark_conversation(pg_temp.v('g')::uuid, now(), now());
select pg_temp.as_user('b');
select isnt((select peer_read_up_to from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  null, 'avant : Bob voit qu''Alice a lu');
select isnt((select peer_read_up_to from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid),
  null, 'avant : groupe lu par tous');
select pg_temp.as_user('a');
select public.set_conversation_privacy(pg_temp.v('ab')::uuid, false, null);
select public.set_conversation_privacy(pg_temp.v('g')::uuid, false, false);
select results_eq(format($$ select read_receipts, typing_indicator from public.get_conversation_privacy(%L) $$, pg_temp.v('g')),
  $$ values (false, false) $$, 'réglages du groupe enregistrés');
select pg_temp.as_user('b');
select is((select peer_read_up_to from public.list_conversations() where conversation_id = pg_temp.v('ab')::uuid),
  null, 'accusés coupés pour cette discussion');
select isnt((select peer_read_up_to from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid),
  null, 'groupe : « lu » ne tient plus compte d''Alice (Carla a lu)');

-- En train d'écrire : coupé dans le groupe, rien n'est envoyé ni compté.
select pg_temp.as_user('a');
select public.signal_typing(pg_temp.v('g')::uuid);
reset role;
select is((select count(*)::int from private.rate_limit_hits where user_id = pg_temp.uid('a') and bucket = 'typing'),
  0, 'groupe : aucun signal « en train d''écrire »');
select pg_temp.as_user('a');
set local role authenticated;
select public.signal_typing(pg_temp.v('ab')::uuid);
reset role;
select is((select count(*)::int from private.rate_limit_hits where user_id = pg_temp.uid('a') and bucket = 'typing'),
  1, 'discussion avec Bob : le réglage du compte s''applique');

-- En ligne : « personne » dans le compte, mais montré à Bob.
update private.privacy_settings set presence_visibility = 'nobody' where user_id = pg_temp.uid('a');
insert into private.privacy_settings (user_id, presence_visibility)
select pg_temp.uid('a'), 'nobody' where not exists (select 1 from private.privacy_settings where user_id = pg_temp.uid('a'));
select pg_temp.as_user('a');
set local role authenticated;
select public.set_conversation_privacy(pg_temp.v('ab')::uuid, false, null, true);
select pg_temp.as_user('b');
select is((select visible from public.get_presence(pg_temp.uid('a'))), true, 'Bob voit « en ligne » (exception)');
select pg_temp.as_user('c');
select is((select visible from public.get_presence(pg_temp.uid('a'))), false, 'Carla non (réglage du compte)');

-- Photo et À propos cachés à Carla seulement (y compris dans le groupe commun).
select pg_temp.as_user('a');
select public.set_conversation_privacy(pg_temp.v('ac')::uuid, null, null, null, false, false);
select pg_temp.as_user('c');
select is((select peer_avatar_path from public.list_conversations() where conversation_id = pg_temp.v('ac')::uuid),
  null, 'Carla : photo cachée dans la liste');
select is((select avatar_path from public.get_conversation_members(pg_temp.v('g')::uuid) where user_id = pg_temp.uid('a')),
  null, 'Carla : photo cachée aussi parmi les membres du groupe');
select is((select about from public.get_contact_profile(pg_temp.uid('a'))), null, 'Carla : À propos caché');
select pg_temp.as_user('b');
select is((select avatar_path from public.get_contact_profile(pg_temp.uid('a'))), 'a/1.jpg', 'Bob voit toujours la photo');
select pg_temp.as_user('a');
select is((select avatar_path from public.get_contact_profile(pg_temp.uid('a'))), 'a/1.jpg', 'on voit toujours la sienne');

-- Tout remis « comme dans mes réglages » : la ligne disparaît.
select public.set_conversation_privacy(pg_temp.v('ac')::uuid, null, null, null, null, null);
reset role;
select is((select count(*)::int from private.conversation_privacy where conversation_id = pg_temp.v('ac')::uuid),
  0, 'réglages par défaut : rien n''est gardé');

-- Blocage : une exception ne passe jamais au-dessus d'un blocage.
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('b'), pg_temp.uid('a'));
select pg_temp.as_user('b');
set local role authenticated;
select is((select visible from public.get_presence(pg_temp.uid('a'))), false, 'blocage : plus rien');
reset role;
delete from public.blocks;

select pg_temp.as_user('a');
set local role authenticated;
select throws_ok($$ select * from private.conversation_privacy $$, '42501', null, 'table illisible');

select * from finish();
rollback;
