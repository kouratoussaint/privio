-- Lot 9.4 — appels de groupe : lancer, sonner (≤ 16 membres), rejoindre (8 au plus),
-- refuser, quitter, relais (sessions et pistes), occupé pour les appels à deux, fin et trace.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

insert into auth.users (id, phone, phone_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '2267000001' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3), ('d', 4), ('e', 5), ('f', 6), ('2', 7), ('3', 8),
               ('4', 9)) as x(p, n);
insert into auth.sessions (id, user_id)
select ('00000000-0000-0000-0000-00000000' || repeat(p, 4))::uuid,
       ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid
  from (values ('a'), ('b'), ('c'), ('d'), ('e'), ('f'), ('2'), ('3'), ('4')) as x(p);
insert into public.profiles (id, handle, display_name)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, h, n
  from (values ('a', 'alice_bf', 'Alice'), ('b', 'bob_ouaga', 'Bob'), ('c', 'carla', 'Carla'),
               ('d', 'dani', 'Dani'), ('e', 'eli_bf', 'Eli'), ('f', 'fati', 'Fati'),
               ('2', 'gael', 'Gaël'), ('3', 'hawa', 'Hawa'), ('4', 'issa', 'Issa')) as x(p, h, n);

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
create function pg_temp.accept_all() returns void language sql as $$
  select public.respond_to_invitation(i.invitation_id, true) from public.list_my_invitations() i $$;
create function pg_temp.st(p_k text) returns jsonb language sql as $$
  select public.group_call_state(pg_temp.v(p_k)::uuid) $$;
create function pg_temp.mine(p_k text, p_who char) returns text language sql as $$
  select x.state from private.group_call_participants x
   where x.call_id = pg_temp.v(p_k)::uuid and x.user_id = pg_temp.uid(p_who) $$;
create function pg_temp.tok() returns text language sql as $$
  select value from private.runtime_settings where key = 'push_dispatch_token' $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text),
  pg_temp.accept_all(), pg_temp.st(text), pg_temp.mine(text, char) to authenticated;

-- Groupe « Voisins » (Alice, Bob, Carla, Dani), groupe « Annonces » (Alice admin, Bob),
-- discussion Alice–Bob et Bob–Carla.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('g', public.create_group('Voisins', null,
  array[pg_temp.uid('b'), pg_temp.uid('c'), pg_temp.uid('d')])::text);
insert into t values ('ann', public.create_group('Infos', null, array[pg_temp.uid('b')], true)::text);
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
select pg_temp.as_user('b');
select pg_temp.accept_all();
insert into t values ('bc', public.start_direct_conversation(pg_temp.uid('c'))::text);
select pg_temp.as_user('c');
select public.register_device('android', '0.1.0+81');
select public.register_push_token('jeton-fcm-de-carla-00000000001');
select pg_temp.accept_all();
select pg_temp.as_user('d');
select public.register_device('android', '0.1.0+81');
select public.register_push_token('jeton-fcm-de-dani-000000000001');
select pg_temp.accept_all();
-- Dani a mis le groupe en sourdine : son téléphone ne sonnera pas.
reset role;
update public.conversation_members set muted_until = now() + interval '8 hours'
 where conversation_id = pg_temp.v('g')::uuid and user_id = pg_temp.uid('d');

-- ---------------------------------------------------------------------------
-- Règles
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select public.start_group_call(%L) $$, pg_temp.v('ab')), 'P0001',
  'GROUP_CALL_GROUP_ONLY', 'discussion à deux : pas d''appel de groupe');
select throws_ok(format($$ select public.start_group_call(%L, 'ecran') $$, pg_temp.v('g')), 'P0001',
  'CALL_KIND_UNAVAILABLE', 'type inconnu refusé');
select pg_temp.as_user('b');
select throws_ok(format($$ select public.start_group_call(%L) $$, pg_temp.v('ann')), 'P0001',
  'POSTING_RESTRICTED', 'groupe « Annonces » : un simple membre ne lance pas d''appel');
select pg_temp.as_user('e');
select throws_ok(format($$ select public.start_group_call(%L) $$, pg_temp.v('g')), 'P0001',
  'NOT_MEMBER', 'hors du groupe : refusé');

-- ---------------------------------------------------------------------------
-- Lancer : sonnerie des membres (groupe de 4)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
insert into t select 'c1', r ->> 'id' from public.start_group_call(pg_temp.v('g')::uuid, 'video') r;
reset role;
select is(pg_temp.mine('c1', 'a'), 'joined', 'Alice est dans l''appel');
select is(pg_temp.mine('c1', 'b'), 'ringing', 'le téléphone de Bob sonne');
select is(pg_temp.mine('c1', 'c'), 'ringing', 'celui de Carla aussi');
select is(pg_temp.mine('c1', 'd'), null, 'sourdine : Dani ne sonne pas');
select is((select rings from private.group_calls where id = pg_temp.v('c1')::uuid), true,
  '4 membres : l''appel sonne');
select is((select count(*)::int from public.push_group_call_targets(pg_temp.tok(), pg_temp.v('c1')::uuid,
  'ring', array[pg_temp.uid('b'), pg_temp.uid('c'), pg_temp.uid('d')])), 1,
  'réveil : seulement les téléphones qui sonnent et ont un jeton (Carla)');
select is((select count(*)::int from public.push_group_call_targets(pg_temp.tok(), pg_temp.v('c1')::uuid,
  'live', null)), 1, 'notification « appel en cours » : Carla, pas Dani (sourdine)');
select throws_ok(format($$ select * from public.push_group_call_targets('faux', %L, 'ring', null) $$,
  pg_temp.v('c1')), 'P0001', null, 'jeton de push-dispatch exigé');
select is(has_function_privilege('authenticated', 'public.push_group_call_targets(text, uuid, text, uuid[])',
  'execute'), false, 'cibles réservées à push-dispatch');
select is(has_function_privilege('authenticated', 'public.group_call_set_sfu(uuid, uuid, text, jsonb)',
  'execute'), false, 'sessions du relais enregistrées par la fonction call-sfu seulement');

select pg_temp.as_user('a');
set local role authenticated;
select is((pg_temp.st('c1') ->> 'kind'), 'video', 'appel vidéo');
select is((pg_temp.st('c1') ->> 'joined_count')::int, 1, 'une personne dans l''appel');
select is(public.can_use_call_relay(), true, 'relais réseau autorisé pendant l''appel de groupe');
select throws_ok(format($$ select public.start_call(%L) $$, pg_temp.v('ab')), 'P0001',
  'CALL_ALREADY_ACTIVE', 'pas d''appel à deux pendant un appel de groupe');

select pg_temp.as_user('c');
select is((select (x ->> 'my_state') from jsonb_array_elements(public.my_group_calls()) x), 'ringing',
  'Carla voit l''appel qui sonne');
select is((public.decline_group_call(pg_temp.v('c1')::uuid) ->> 'my_state'), 'declined', 'Carla refuse');
select is((select count(*)::int from jsonb_array_elements(pg_temp.st('c1') -> 'participants') p
            where p ->> 'state' = 'ringing'), 1, 'seul Bob sonne encore');

-- Bob appuie sur « Appeler » dans le groupe : il rejoint l'appel en cours.
select pg_temp.as_user('b');
select is((public.start_group_call(pg_temp.v('g')::uuid) ->> 'existing')::boolean, true,
  'appel déjà en cours : on le rejoint');
select is((pg_temp.st('c1') ->> 'joined_count')::int, 2, 'deux personnes dans l''appel');
reset role;
select isnt((select answered_at from private.group_calls where id = pg_temp.v('c1')::uuid), null,
  'appel décroché');
select pg_temp.as_user('c');
set local role authenticated;
select is((public.start_call(pg_temp.v('bc')::uuid) ->> 'end_reason'), 'busy',
  'Bob est dans un appel de groupe : occupé pour un appel à deux');
select is((select count(*)::int from jsonb_array_elements(pg_temp.st('c1') -> 'participants') p
            where p ? 'session'), 0, 'hors de l''appel : pas de session du relais');

-- ---------------------------------------------------------------------------
-- Relais : sessions et pistes
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
select is((public.group_call_sfu(pg_temp.v('c1')::uuid) ->> 'session'), null, 'pas encore de session');
select throws_ok(format($$ select public.group_call_sfu(%L, array['session-inconnue']) $$, pg_temp.v('c1')),
  'P0001', 'SFU_FORBIDDEN', 'pistes d''une session hors de l''appel : refusé');
reset role;
select public.group_call_set_sfu(pg_temp.uid('a'), pg_temp.v('c1')::uuid, 'sessA', '{"audio":"a-micro"}');
select public.group_call_set_sfu(pg_temp.uid('a'), pg_temp.v('c1')::uuid, 'sessA', '{"video":"a-camera"}');
select public.group_call_set_sfu(pg_temp.uid('b'), pg_temp.v('c1')::uuid, 'sessB', '{"audio":"b-micro"}');
select throws_ok(format($$ select public.group_call_set_sfu(%L, %L, 'sessB', '{"ecran":"x"}') $$,
  pg_temp.uid('b'), pg_temp.v('c1')), 'P0001', 'BODY_INVALID', 'piste inconnue refusée');
select throws_ok(format($$ select public.group_call_set_sfu(%L, %L, 'sessC', '{}') $$,
  pg_temp.uid('c'), pg_temp.v('c1')), 'P0001', 'CALL_NOT_FOUND', 'hors de l''appel : refusé');
select is((select tracks from private.group_call_participants
            where call_id = pg_temp.v('c1')::uuid and user_id = pg_temp.uid('a')),
  '{"audio":"a-micro","video":"a-camera"}'::jsonb, 'pistes cumulées dans la même session');
select pg_temp.as_user('b');
set local role authenticated;
select is((public.group_call_sfu(pg_temp.v('c1')::uuid, array['sessA']) ->> 'session'), 'sessB',
  'Bob peut recevoir les pistes d''Alice');
select throws_ok(format($$ select public.group_call_sfu(%L, array['sessB']) $$, pg_temp.v('c1')),
  'P0001', 'SFU_FORBIDDEN', 'pas ses propres pistes');
select is((select p -> 'tracks' ->> 'video' from jsonb_array_elements(pg_temp.st('c1') -> 'participants') p
            where p ->> 'user_id' = pg_temp.uid('a')::text), 'a-camera', 'Bob voit les pistes d''Alice');
select is((public.set_group_call_media(pg_temp.v('c1')::uuid, true, true) -> 'participants') @>
  jsonb_build_array(jsonb_build_object('user_id', pg_temp.uid('b'), 'camera', true, 'muted', true)), true,
  'caméra et micro affichés aux autres');

-- ---------------------------------------------------------------------------
-- 8 participants au plus
-- ---------------------------------------------------------------------------
reset role;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.v('g')::uuid, pg_temp.uid(p), 'member' from unnest(array['e', 'f', '2', '3', '4']) p;
insert into private.group_call_participants (call_id, user_id, state, joined_at)
select pg_temp.v('c1')::uuid, pg_temp.uid(p), 'joined', now() from unnest(array['e', 'f', '2', '3', '4']) p;
insert into private.group_call_participants (call_id, user_id, state, joined_at)
select pg_temp.v('c1')::uuid, pg_temp.uid('c'), 'joined', now()
on conflict (call_id, user_id) do update set state = 'joined';
select pg_temp.as_user('d');
set local role authenticated;
select throws_ok(format($$ select public.join_group_call(%L) $$, pg_temp.v('c1')), 'P0001',
  'GROUP_CALL_FULL', '8 personnes dans l''appel : complet');
reset role;
delete from private.group_call_participants
 where call_id = pg_temp.v('c1')::uuid and user_id in (select pg_temp.uid(p) from unnest(array['c', 'e', 'f', '2', '3', '4']) p);

-- ---------------------------------------------------------------------------
-- Quitter : l'appel se termine avec la dernière personne ; trace dans la discussion
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select is((public.leave_group_call(pg_temp.v('c1')::uuid) ->> 'status'), 'active',
  'Alice part, Bob reste : l''appel continue');
select pg_temp.as_user('b');
select is((public.leave_group_call(pg_temp.v('c1')::uuid) ->> 'status'), 'ended',
  'dernière personne partie : appel terminé');
reset role;
select is(pg_temp.mine('c1', 'b'), 'left', 'Bob est sorti');
set local role authenticated;
select is((select body::jsonb ->> 'e' from public.messages
            where conversation_id = pg_temp.v('g')::uuid and kind = 'system'
            order by sent_at desc limit 1), 'group_call', 'trace de l''appel de groupe');
select ok((select body::jsonb ->> 'v' from public.messages
            where conversation_id = pg_temp.v('g')::uuid and kind = 'system'
            order by sent_at desc limit 1) like 'ended:%', 'avec sa durée');
select is(public.my_group_calls(), '[]'::jsonb, 'plus d''appel en cours');
select is(public.can_use_call_relay(), false, 'relais fermé après l''appel');

-- ---------------------------------------------------------------------------
-- Sans réponse : sonnerie arrêtée après 45 s ; personne sans nouvelles 40 s : sortie
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
insert into t select 'c2', r ->> 'id' from public.start_group_call(pg_temp.v('g')::uuid) r;
reset role;
select is(pg_temp.mine('c2', 'a'), 'ringing', 'Alice sonne');
update private.group_call_participants set rang_at = now() - interval '1 minute'
 where call_id = pg_temp.v('c2')::uuid and state = 'ringing';
select private.expire_group_calls();
select is(pg_temp.mine('c2', 'a'), 'missed', 'sans réponse : manqué');
select is((select count(*)::int from public.push_group_call_targets(pg_temp.tok(), pg_temp.v('c2')::uuid,
  'missed', array[pg_temp.uid('c')])), 1, 'arrêt de la sonnerie chez Carla');
select is((select status from private.group_calls where id = pg_temp.v('c2')::uuid), 'active',
  'Bob est encore dans l''appel');
update private.group_call_participants set seen_at = now() - interval '1 minute'
 where call_id = pg_temp.v('c2')::uuid and user_id = pg_temp.uid('b');
select private.expire_group_calls();
select is((select status from private.group_calls where id = pg_temp.v('c2')::uuid), 'ended',
  'Bob sans nouvelles : appel terminé');
select is((select body::jsonb ->> 'v' from public.messages
            where conversation_id = pg_temp.v('g')::uuid and kind = 'system'
            order by sent_at desc limit 1), 'missed', 'trace : personne n''a rejoint');

-- Grand groupe (plus de 16 membres) : pas de sonnerie, notification « appel en cours ».
insert into auth.users (id, phone, phone_confirmed_at)
select gen_random_uuid(), '2267100' || lpad(n::text, 4, '0'), now() from generate_series(1, 13) n;
insert into public.conversation_members (conversation_id, user_id, role)
select pg_temp.v('g')::uuid, u.id, 'member' from auth.users u where u.phone like '2267100%';
select pg_temp.as_user('c');
set local role authenticated;
insert into t select 'c3', r ->> 'id' from public.start_group_call(pg_temp.v('g')::uuid) r;
reset role;
select is((select rings from private.group_calls where id = pg_temp.v('c3')::uuid), false,
  'plus de 16 membres : pas de sonnerie');
select is((select count(*)::int from private.group_call_participants
            where call_id = pg_temp.v('c3')::uuid and state = 'ringing'), 0, 'personne ne sonne');

select * from finish();
rollback;
