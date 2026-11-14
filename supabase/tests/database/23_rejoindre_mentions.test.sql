-- Lot 7.1b — rejoindre un groupe par code (ou QR code), demandes d'adhésion, @mentions.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

insert into auth.users (id, phone, phone_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '2267000000' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3), ('d', 4), ('e', 5), ('f', 6), ('9', 7)) as x(p, n);
insert into auth.sessions (id, user_id)
select ('00000000-0000-0000-0000-00000000' || repeat(p, 4))::uuid,
       ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid
  from (values ('a'), ('b'), ('c'), ('d'), ('e'), ('f'), ('9')) as x(p);
insert into public.profiles (id, handle, display_name)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, h, n
  from (values ('a', 'alice_bf', 'Alice'), ('b', 'bob_ouaga', 'Bob'), ('c', 'carla', 'Carla'),
               ('d', 'dani', 'Dani'), ('e', 'eli', 'Eli'), ('f', 'fati', 'Fati'), ('9', 'gael', 'Gaël')) as x(p, h, n);

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
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text) to authenticated;

-- Alice crée « Voisins » ; Bob accepte son invitation ; Carla est invitée sans avoir répondu.
select pg_temp.as_user('a');
set local role authenticated;
select public.register_device('android', 'test');
select public.register_push_token('jeton-fcm-d-alice-00000000001');
insert into t values ('g', public.create_group('Voisins', null, array[pg_temp.uid('b'), pg_temp.uid('c')])::text);
select pg_temp.as_user('b');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);

-- ---------------------------------------------------------------------------
-- Code du groupe
-- ---------------------------------------------------------------------------
select throws_ok(format($$ select public.get_group_invite_code(%L) $$, pg_temp.v('g')),
  'P0001', 'NOT_ADMIN', 'un membre ne voit pas le code');
select pg_temp.as_user('a');
insert into t values ('code1', public.get_group_invite_code(pg_temp.v('g')::uuid));
select matches(pg_temp.v('code1'), '^PRV-[2-9A-HJ-NP-Z]{6}$', 'code au format PRV-XXXXXX');
select is(public.get_group_invite_code(pg_temp.v('g')::uuid), pg_temp.v('code1'), 'le même code à chaque fois');
select is((select join_approval from public.get_group_join_settings(pg_temp.v('g')::uuid)), true,
  'par défaut : approbation des administrateurs');
insert into t values ('code', public.reset_group_invite_code(pg_temp.v('g')::uuid));
select isnt(pg_temp.v('code'), pg_temp.v('code1'), 'réinitialisé : nouveau code');

select pg_temp.as_user('d');
select is((select status from public.preview_group_by_code(pg_temp.v('code1'))), 'invalid',
  'l''ancien code ne marche plus');
select is((select status from public.preview_group_by_code('PRV-0000OO')), 'invalid', 'code faux');
select results_eq(
  format($$ select status, conversation_id, title, member_count from public.preview_group_by_code(%L) $$,
         lower(replace(pg_temp.v('code'), '-', ' '))),
  $$ values ('approval'::text, null::uuid, 'Voisins'::text, 2) $$,
  'saisie tolérante ; aperçu : nom et membres, sans identifiant du groupe');

-- ---------------------------------------------------------------------------
-- Demande d'adhésion
-- ---------------------------------------------------------------------------
select public.register_device('android', 'test');
select public.register_push_token('jeton-fcm-de-dani-000000000001');
select results_eq(format($$ select status, conversation_id from public.join_group_by_code(%L) $$, pg_temp.v('code')),
  format($$ values ('requested'::text, %L::uuid) $$, pg_temp.v('g')), 'Dani demande à entrer');
select results_eq(format($$ select status, conversation_id from public.preview_group_by_code(%L) $$, pg_temp.v('code')),
  format($$ values ('pending'::text, %L::uuid) $$, pg_temp.v('g')), 'demande en attente (elle peut l''annuler)');
select is((select status from public.join_group_by_code(pg_temp.v('code'))), 'pending', 'pas de seconde demande');
select is((select title from public.list_my_join_requests()), 'Voisins', 'Dani voit sa demande en attente');
select ok(not private.is_member(pg_temp.v('g')::uuid, pg_temp.uid('d')), 'Dani n''est pas encore membre');

select pg_temp.as_user('b');
select throws_ok(format($$ select * from public.list_group_join_requests(%L) $$, pg_temp.v('g')),
  'P0001', 'NOT_ADMIN', 'un membre ne voit pas les demandes');
select pg_temp.as_user('a');
select results_eq(format($$ select display_name, handle, was_removed from public.list_group_join_requests(%L) $$, pg_temp.v('g')),
  $$ values ('Dani'::text, 'dani'::text, false) $$, 'Alice (administratrice) voit la demande');
select is((select pending_requests from public.get_group_join_settings(pg_temp.v('g')::uuid)), 1, 'compteur : 1');

reset role;
insert into t select 'req', id::text from private.group_join_requests where user_id = pg_temp.uid('d');
select results_eq(format($$ select token, event from public.push_join_request_targets(%L, %L) $$, pg_temp.tok(), pg_temp.v('req')),
  $$ values ('jeton-fcm-d-alice-00000000001'::text, 'join_request'::text) $$,
  'notification sans contenu aux administrateurs');
select throws_ok(format($$ select * from public.push_join_request_targets('mauvais', %L) $$, pg_temp.v('req')),
  'P0001', 'AUTH_REQUIRED', 'jeton interne exigé');

select pg_temp.as_user('a');
set local role authenticated;
select lives_ok(format($$ select public.respond_to_join_request(%L, false) $$, pg_temp.v('req')), 'refus');
select throws_ok(format($$ select public.respond_to_join_request(%L, true) $$, pg_temp.v('req')),
  'P0001', 'JOIN_REQUEST_NOT_FOUND', 'une demande traitée ne se traite plus');
select pg_temp.as_user('d');
select is((select status from public.preview_group_by_code(pg_temp.v('code'))), 'declined',
  'refus récent : pas de nouvelle demande pendant 24 h');
select is_empty($$ select * from public.list_my_join_requests() $$, 'plus de demande en attente');

reset role;
update private.group_join_requests set decided_at = now() - interval '25 hours' where id = pg_temp.v('req')::uuid;
select pg_temp.as_user('d');
set local role authenticated;
select is((select status from public.join_group_by_code(pg_temp.v('code'))), 'requested', 'après 24 h : nouvelle demande');
select lives_ok(format($$ select public.cancel_join_request(%L) $$, pg_temp.v('g')), 'Dani annule');
select is((select status from public.join_group_by_code(pg_temp.v('code'))), 'requested', 'puis redemande');
reset role;
delete from t where k = 'req';
insert into t select 'req', id::text from private.group_join_requests
 where user_id = pg_temp.uid('d') and status = 'pending';
select pg_temp.as_user('a');
set local role authenticated;
select lives_ok(format($$ select public.respond_to_join_request(%L, true) $$, pg_temp.v('req')), 'acceptée');
select ok(private.is_member(pg_temp.v('g')::uuid, pg_temp.uid('d')), 'Dani est membre');
select is((select body::jsonb ->> 'e' from public.messages
            where conversation_id = pg_temp.v('g')::uuid and kind = 'system' and sender_id = pg_temp.uid('d')),
  'joined', 'message système « a rejoint le groupe »');
reset role;
select results_eq(format($$ select token, event from public.push_join_request_targets(%L, %L) $$, pg_temp.tok(), pg_temp.v('req')),
  $$ values ('jeton-fcm-de-dani-000000000001'::text, 'join_approved'::text) $$,
  'Dani est prévenue (sans contenu)');
select pg_temp.as_user('d');
set local role authenticated;
select results_eq(format($$ select status, conversation_id from public.preview_group_by_code(%L) $$, pg_temp.v('code')),
  format($$ values ('member'::text, %L::uuid) $$, pg_temp.v('g')), 'déjà membre : le groupe s''ouvre');

-- ---------------------------------------------------------------------------
-- Invitation en attente, entrée libre, personne retirée
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c');
select is((select status from public.join_group_by_code(pg_temp.v('code'))), 'joined',
  'Carla (invitée) entre sans demande');
select is_empty($$ select * from public.list_my_invitations() $$, 'son invitation est acceptée');

select pg_temp.as_user('e');
select is((select status from public.preview_group_by_code(pg_temp.v('code'))), 'approval', 'Eli : demande requise');
select pg_temp.as_user('b');
select throws_ok(format($$ select public.set_group_join_approval(%L, false) $$, pg_temp.v('g')),
  'P0001', 'NOT_ADMIN', 'un membre ne change pas le réglage');
select pg_temp.as_user('a');
select public.set_group_join_approval(pg_temp.v('g')::uuid, false);
select pg_temp.as_user('e');
select results_eq(format($$ select status, conversation_id from public.join_group_by_code(%L) $$, pg_temp.v('code')),
  format($$ values ('joined'::text, %L::uuid) $$, pg_temp.v('g')), 'entrée libre : Eli entre directement');
select pg_temp.as_user('a');
select public.remove_group_member(pg_temp.v('g')::uuid, pg_temp.uid('e'));
select pg_temp.as_user('e');
select is((select status from public.join_group_by_code(pg_temp.v('code'))), 'requested',
  'retiré par un administrateur : repasse par une demande');
select pg_temp.as_user('a');
select is((select was_removed from public.list_group_join_requests(pg_temp.v('g')::uuid)), true,
  'les administrateurs voient qu''il avait été retiré');

-- Complet.
reset role;
insert into private.policies (key, value) values ('group_max_members', '4');
select pg_temp.as_user('f');
set local role authenticated;
select is((select status from public.preview_group_by_code(pg_temp.v('code'))), 'full', 'groupe complet');
reset role;
update private.policies set value = '25' where key = 'group_max_members';

-- Blocage par une administratrice : même réponse qu'un code faux.
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('a'), pg_temp.uid('9'));
select pg_temp.as_user('9');
set local role authenticated;
select is((select status from public.preview_group_by_code(pg_temp.v('code'))), 'invalid',
  'bloqué par une administratrice : code « faux »');
reset role;
delete from public.blocks;

-- Essais limités : la limite tient malgré les codes faux (pas d'erreur, donc pas d'annulation).
insert into private.policies (key, value) values ('group_code_hourly_limit', '5');
select pg_temp.as_user('f');
set local role authenticated;
select public.preview_group_by_code('PRV-22222' || n) from generate_series(2, 5) n;
select throws_ok($$ select public.preview_group_by_code('PRV-222229') $$, 'P0001', 'RATE_LIMITED',
  'au-delà de la limite : refusé');
reset role;
update private.policies set value = '20' where key = 'group_code_hourly_limit';

-- ---------------------------------------------------------------------------
-- @mentions
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select public.set_conversation_mute(pg_temp.v('g')::uuid, now() + interval '8 hours');
select pg_temp.as_user('d');
select public.set_conversation_mute(pg_temp.v('g')::uuid, now() + interval '8 hours');
select pg_temp.as_user('b');
insert into t select 'm1', id::text from public.send_message(pg_temp.v('g')::uuid, gen_random_uuid(),
  '@Alice tu viens ?', null, null, array[pg_temp.uid('a'), pg_temp.uid('b'), pg_temp.uid('f')]);
select results_eq(format($$ select mentions from public.get_messages(%L) where id = %L $$, pg_temp.v('g'), pg_temp.v('m1')),
  format($$ values (array[%L::uuid]) $$, pg_temp.uid('a')),
  'seuls les membres sont retenus (ni l''expéditeur, ni une personne extérieure)');
select throws_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), 'x', null, null,
                            array(select gen_random_uuid() from generate_series(1, 51))) $$, pg_temp.v('g')),
  'P0001', 'BODY_INVALID', 'plus de 50 mentions : refusé');
select lives_ok(format($$ select * from public.send_message(%L, gen_random_uuid(), 'sans mention') $$, pg_temp.v('g')),
  'ancienne version (sans mentions) : inchangée');
reset role;
select results_eq(format($$ select token, mentioned from public.push_targets(%L, %L) $$, pg_temp.tok(), pg_temp.v('m1')),
  $$ values ('jeton-fcm-d-alice-00000000001'::text, true) $$,
  'Alice (sourdine) prévenue car mentionnée ; Dani (sourdine) non');

-- Discussion à deux : pas de mention.
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
insert into t select 'm2', id::text from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(),
  'salut', null, null, array[pg_temp.uid('b')]);
select is((select mentions from public.get_messages(pg_temp.v('ab')::uuid) where id = pg_temp.v('m2')::uuid),
  '{}'::uuid[], 'discussion à deux : mentions ignorées');

-- ---------------------------------------------------------------------------
-- Groupe fermé par Privio, droits
-- ---------------------------------------------------------------------------
reset role;
update public.conversations set posting = 'closed' where id = pg_temp.v('g')::uuid;
select pg_temp.as_user('f');
set local role authenticated;
select is((select status from public.preview_group_by_code(pg_temp.v('code'))), 'invalid', 'groupe fermé : code « faux »');
select pg_temp.as_user('a');
select throws_ok(format($$ select public.reset_group_invite_code(%L) $$, pg_temp.v('g')),
  'P0001', 'GROUP_CLOSED', 'groupe fermé : plus de code');
select is_empty(format($$ select * from public.list_my_join_requests() $$), 'rien côté Alice');
select pg_temp.as_user('e');
select is_empty($$ select * from public.list_my_join_requests() $$, 'groupe fermé : demande masquée');

select throws_ok($$ select * from private.group_invite_codes $$, '42501', null, 'codes illisibles');
select throws_ok($$ select * from private.group_join_requests $$, '42501', null, 'demandes illisibles');
select throws_ok($$ select * from private.message_mentions $$, '42501', null, 'mentions illisibles');
select throws_ok(format($$ select * from public.push_join_request_targets('x', %L) $$, pg_temp.v('req')),
  '42501', null, 'push_join_request_targets réservé au service');

select * from finish();
rollback;
