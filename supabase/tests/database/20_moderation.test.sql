-- Lot 5.3 — Modération : file des signalements, copie jointe, décisions (classer, avertir,
-- suspendre, supprimer le message, fermer un groupe), réactivation, contestation, protection
-- du compte administrateur, notification à l'administration.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';
insert into private.runtime_settings (key, value) values ('functions_url', 'http://fonctions.test/functions/v1')
on conflict (key) do update set value = excluded.value;

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
  ('00000000-0000-0000-0000-0000000000a1', 'admin_privio', 'Admin'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob'),
  ('00000000-0000-0000-0000-0000000000c1', 'carla', 'Carla'),
  ('00000000-0000-0000-0000-0000000000d1', 'dani', 'Dani');

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
-- Chemin de la requête, comme le pose l'API.
create function pg_temp.path(p text) returns void language sql as $$
  select set_config('request.path', '/rpc/' || p, true) $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text), pg_temp.path(text)
  to authenticated;

create temporary table q0 on commit drop as select coalesce(max(id), 0) as id from net.http_request_queue;

-- ---------------------------------------------------------------------------
-- Signalements : Carla et Dani signalent Bob (un avec copie du message), Carla signale un groupe.
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
insert into t values ('conv_bc', public.start_direct_conversation(pg_temp.uid('c'))::text);
insert into t values ('conv_bd', public.start_direct_conversation(pg_temp.uid('d'))::text);
insert into t select 'm1', id::text from public.send_message(pg_temp.v('conv_bc')::uuid, gen_random_uuid(), 'Message insultant');
insert into t values ('g', public.create_group('Arnaque', null, array[pg_temp.uid('c')])::text);
select pg_temp.as_user('c');
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);
insert into t values ('r1', public.report('harassment', pg_temp.uid('b'), pg_temp.v('conv_bc')::uuid,
  pg_temp.v('m1')::uuid, 'Il m''insulte', true)::text);
insert into t values ('rg', public.report('spam', null, pg_temp.v('g')::uuid, null, 'Groupe d''arnaque', false)::text);
select pg_temp.as_user('d');
insert into t values ('r2', public.report('harassment', pg_temp.uid('b'), pg_temp.v('conv_bd')::uuid, null, null, false)::text);
reset role;

select is((select count(*)::int from net.http_request_queue q
            where q.id > (select id from q0) and convert_from(q.body, 'utf8')::jsonb ->> 'admin_event' = 'report'), 3,
  'administration notifiée à chaque signalement');
select is((select count(*)::int from net.http_request_queue q
            where q.id > (select id from q0) and convert_from(q.body, 'utf8') like '%insult%'), 0,
  'notification sans contenu');

-- ---------------------------------------------------------------------------
-- Réservé à l'administration
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok($$ select * from public.console_reports() $$, 'P0001', 'ADMIN_REQUIRED', 'file refusée');
select throws_ok(format($$ select public.console_moderate(array[%L]::uuid[], 'dismiss', 'Rien') $$, pg_temp.v('r1')),
  'P0001', 'ADMIN_REQUIRED', 'décision refusée');
select throws_ok(format($$ select public.console_report_evidence(%L) $$, pg_temp.v('r1')),
  'P0001', 'ADMIN_REQUIRED', 'copie refusée');

-- ---------------------------------------------------------------------------
-- File
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
select is((select count(*)::int from public.console_reports('open')), 3, '3 signalements à traiter');
select results_eq(format($$ select kind, reporter_handle, reported_handle, reports_90d, reporters_90d, evidence_kind
                              from public.console_reports('open') where id = %L $$, pg_temp.v('r1')),
  $$ values ('message'::text, 'carla'::text, 'bob_ouaga'::text, 2, 2, 'text'::text) $$,
  'fiche : message signalé par @carla contre @bob_ouaga, 2 signalements de 2 personnes, copie jointe');
select results_eq(format($$ select kind, group_title from public.console_reports('open') where id = %L $$, pg_temp.v('rg')),
  $$ values ('group'::text, 'Arnaque'::text) $$, 'signalement de groupe');
select ok((select bool_and(r::text not like '%2267000%') from public.console_reports('open') r),
  'aucun numéro de téléphone dans la file');

select is(public.console_take_reports(array[pg_temp.v('r1'), pg_temp.v('r2')]::uuid[]), 2, 'pris en charge');
select is((select count(*)::int from public.console_reports('reviewing')), 2, '2 en cours');

select results_eq(format($$ select e ->> 'kind', e ->> 'body' from public.console_report_evidence(%L) e $$, pg_temp.v('r1')),
  $$ values ('text'::text, 'Message insultant'::text) $$, 'copie jointe lisible');
select throws_ok(format($$ select public.console_report_evidence(%L) $$, pg_temp.v('r2')),
  'P0001', 'REPORT_NOT_FOUND', 'pas de copie : rien à lire');
reset role;
select is((select count(*)::int from private.admin_audit where action = 'evidence'), 1, 'lecture de la copie journalisée');

-- ---------------------------------------------------------------------------
-- Décisions
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select public.console_moderate(array[%L]::uuid[], 'suspend', '') $$, pg_temp.v('r1')),
  'P0001', 'MODERATION_NOTE_REQUIRED', 'motif obligatoire');
select throws_ok(format($$ select public.console_moderate(array[%L]::uuid[], 'suspend', 'Insultes', 3) $$, pg_temp.v('r1')),
  'P0001', 'MODERATION_INVALID', 'durée hors choix refusée');
select throws_ok(format($$ select public.console_moderate(array[%L, %L]::uuid[], 'suspend', 'Insultes') $$,
                        pg_temp.v('r1'), pg_temp.v('rg')),
  'P0001', 'MODERATION_INVALID', 'suspension : un seul compte visé');

-- Supprimer le message signalé.
select is(public.console_moderate(array[pg_temp.v('r1')]::uuid[], 'delete_message', 'Insulte'), 1, 'message supprimé');
reset role;
select ok((select deleted_at is not null and body is null from public.messages where id = pg_temp.v('m1')::uuid),
  'le message est effacé pour tout le monde');
select results_eq(format($$ select status, decision from private.reports where id = %L $$, pg_temp.v('r1')),
  $$ values ('closed'::text, 'message_deleted'::text) $$, 'signalement traité');

-- Suspendre 7 jours.
select pg_temp.as_user('a');
set local role authenticated;
select is(public.console_moderate(array[pg_temp.v('r2')]::uuid[], 'suspend', 'Harcèlement répété', 7), 1,
  'Bob suspendu 7 jours');
reset role;
select ok((select until between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour'
             from private.sanctions where user_id = pg_temp.uid('b') and kind = 'suspension'),
  'fin de la suspension dans 7 jours');

-- Bob suspendu : plus rien ne passe, sauf voir sa situation et contester.
select pg_temp.as_user('b');
set local role authenticated;
select pg_temp.path('send_message');
select throws_ok(format($$ select public.send_message(%L, gen_random_uuid(), 'Encore') $$, pg_temp.v('conv_bc')),
  'P0001', 'ACCOUNT_SUSPENDED', 'suspendu : envoi refusé');
select pg_temp.path('list_conversations');
select throws_ok($$ select * from public.list_conversations() $$, 'P0001', 'ACCOUNT_SUSPENDED',
  'suspendu : discussions inaccessibles');
select pg_temp.path('get_my_account');
select lives_ok($$ select public.get_my_account() $$, 'suspendu : son compte reste lisible');
select pg_temp.path('my_moderation_status');
select results_eq($$ select (s -> 'suspension' ->> 'reason'), (s -> 'suspension' ->> 'appealed')::boolean
                       from public.my_moderation_status() s $$,
  $$ values ('harassment'::text, false) $$, 'il voit sa suspension et le motif (pas la note interne)');
select ok(public.my_moderation_status()::text not like '%répété%', 'note interne jamais montrée');
select pg_temp.path('submit_appeal');
select throws_ok($$ select public.submit_appeal((select (s -> 'suspension' ->> 'id')::uuid from public.my_moderation_status() s), 'x') $$,
  'P0001', 'APPEAL_INVALID', 'contestation trop courte');
insert into t select 'sb', (s -> 'suspension' ->> 'id') from public.my_moderation_status() s;
select lives_ok(format($$ select public.submit_appeal(%L, 'Je n''ai insulté personne') $$, pg_temp.v('sb')),
  'Bob conteste');
select throws_ok(format($$ select public.submit_appeal(%L, 'Encore une fois') $$, pg_temp.v('sb')),
  'P0001', 'APPEAL_NOT_ALLOWED', 'une seule contestation par sanction');
select pg_temp.path('');
reset role;
select is((select count(*)::int from net.http_request_queue q
            where q.id > (select id from q0) and convert_from(q.body, 'utf8')::jsonb ->> 'admin_event' = 'appeal'), 1,
  'administration notifiée de la contestation');

-- Contestation examinée : suspension maintenue, puis réactivation.
select pg_temp.as_user('a');
set local role authenticated;
select results_eq($$ select handle, appeal_text from public.console_appeals() $$,
  $$ values ('bob_ouaga'::text, 'Je n''ai insulté personne'::text) $$, 'contestation dans la console');
select lives_ok(format($$ select public.console_answer_appeal(%L, false, 'Faits confirmés') $$, pg_temp.v('sb')),
  'suspension maintenue');
select is((select count(*)::int from public.console_appeals()), 0, 'plus de contestation en attente');
select is(public.console_lift_suspension(pg_temp.uid('b'), 'Erreur d''appréciation'), true, 'Bob réactivé');
select pg_temp.as_user('b');
select pg_temp.path('send_message');
select lives_ok(format($$ select public.send_message(%L, gen_random_uuid(), 'Merci') $$, pg_temp.v('conv_bc')),
  'réactivé : envoi de nouveau possible');
select pg_temp.path('');

-- Avertissement : affiché une fois, puis « J'ai compris ».
select pg_temp.as_user('a');
reset role;
insert into private.reports (reporter_id, reported_user_id, reason, purge_after)
values (pg_temp.uid('c'), pg_temp.uid('b'), 'spam', now() + interval '90 days');
insert into t select 'r3', id::text from private.reports where reason = 'spam' and reported_user_id = pg_temp.uid('b');
set local role authenticated;
select is(public.console_moderate(array[pg_temp.v('r3')]::uuid[], 'warn', 'Premier rappel'), 1, 'Bob averti');
select pg_temp.as_user('b');
select pg_temp.path('my_moderation_status');
select is((select s -> 'warning' ->> 'reason' from public.my_moderation_status() s), 'spam', 'avertissement visible');
select pg_temp.path('acknowledge_warning');
select public.acknowledge_warning((select (s -> 'warning' ->> 'id')::uuid from public.my_moderation_status() s));
select pg_temp.path('my_moderation_status');
select is(public.my_moderation_status() -> 'warning', 'null'::jsonb, 'avertissement lu : il ne revient plus');
select pg_temp.path('');

-- Fermer le groupe signalé.
select pg_temp.as_user('a');
select is(public.console_moderate(array[pg_temp.v('rg')]::uuid[], 'close_group', 'Groupe d''arnaque'), 1, 'groupe fermé');
select pg_temp.as_user('b');
select throws_ok(format($$ select public.send_message(%L, gen_random_uuid(), 'Encore') $$, pg_temp.v('g')),
  'P0001', 'GROUP_CLOSED', 'groupe fermé : plus personne n''écrit (même le propriétaire)');
select throws_ok(format($$ select public.set_group_settings(%L, 'all') $$, pg_temp.v('g')),
  'P0001', 'GROUP_CLOSED', 'le propriétaire ne peut pas le rouvrir');
select throws_ok(format($$ select public.invite_to_group(%L, array[%L]::uuid[]) $$, pg_temp.v('g'), pg_temp.uid('d')),
  'P0001', 'GROUP_CLOSED', 'plus d''invitation');
select is((select posting from public.list_conversations() where conversation_id = pg_temp.v('g')::uuid), 'closed',
  'l''application voit le groupe fermé');
select ok(exists (select 1 from public.get_messages(pg_temp.v('g')::uuid) m where m.body like '%"closed"%'),
  'message « fermé par Privio » dans le groupe');

-- Le compte administrateur ne peut pas être sanctionné.
select pg_temp.as_user('a');
reset role;
insert into private.reports (reporter_id, reported_user_id, reason, purge_after)
values (pg_temp.uid('d'), pg_temp.uid('a'), 'other', now() + interval '90 days');
insert into t select 'ra', id::text from private.reports where reported_user_id = pg_temp.uid('a');
set local role authenticated;
select is((select protected from public.console_reports('open') where id = pg_temp.v('ra')::uuid), true,
  'compte administrateur signalé : marqué protégé');
select throws_ok(format($$ select public.console_moderate(array[%L]::uuid[], 'suspend', 'Test') $$, pg_temp.v('ra')),
  'P0001', 'ADMIN_PROTECTED', 'le compte administrateur ne peut pas être suspendu');
select is(public.console_moderate(array[pg_temp.v('ra')]::uuid[], 'dismiss', 'Sans objet'), 1, 'classé sans suite');

-- Traités : du plus récent au plus ancien, avec la décision.
select is((select decision from public.console_reports('closed') limit 1), 'dismissed', 'traités : plus récent d''abord');
select ok(exists (select 1 from public.console_journal() where action = 'moderation'), 'décisions au journal');
reset role;

-- Nettoyage : sanctions de plus d'un an effacées (sauf suspension sans limite active).
insert into private.sanctions (user_id, kind, until, user_reason, note, created_at)
values (pg_temp.uid('d'), 'suspension', null, 'spam', 'Ancienne', now() - interval '2 years');
update private.sanctions set created_at = now() - interval '2 years' where user_id = pg_temp.uid('b');
select private.purge_console_data();
select is((select count(*)::int from private.sanctions where user_id = pg_temp.uid('b')), 0,
  'sanctions de plus d''un an effacées');
select is((select count(*)::int from private.sanctions where user_id = pg_temp.uid('d')), 1,
  'suspension sans limite encore active : gardée');

select * from finish();
rollback;
