-- Lot 5.4 — Comptes et assistance : recherche (identifiant, nom, numéro complet jamais
-- affiché), fiche sans contenu, sanction sans signalement, « Déconnecter le téléphone »,
-- réponse aux demandes d'assistance (notifiée sans contenu) et « Mes demandes ».
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
  ('00000000-0000-0000-0000-0000000000c1', '22670000003', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-00000000cccc', '00000000-0000-0000-0000-0000000000c1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin_privio', 'Admin'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob Ouédraogo'),
  ('00000000-0000-0000-0000-0000000000c1', 'carla', 'Carla');
insert into private.user_contacts (user_id, phone_e164, phone_verified_at) values
  ('00000000-0000-0000-0000-0000000000b1', '+22670000002', now())
on conflict (user_id) do update set phone_e164 = excluded.phone_e164;

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

-- Bob : un appareil avec notifications, une discussion, une demande d'assistance.
select pg_temp.as_user('b');
set local role authenticated;
select public.register_device('android', '0.1.0+30');
select public.register_push_token('jeton-fcm-de-bob-000000000001');
select public.start_direct_conversation(pg_temp.uid('c'));
insert into t values ('sup', public.report('support', null, null, null, 'Je ne reçois plus les vocaux', false)::text);
reset role;

-- ---------------------------------------------------------------------------
-- Réservé à l'administration
-- ---------------------------------------------------------------------------
select pg_temp.as_user('c');
set local role authenticated;
select throws_ok($$ select * from public.console_search_accounts('bob') $$, 'P0001', 'ADMIN_REQUIRED', 'recherche refusée');
select throws_ok(format($$ select public.console_account(%L) $$, pg_temp.uid('b')), 'P0001', 'ADMIN_REQUIRED', 'fiche refusée');
select throws_ok(format($$ select public.console_disconnect_device(%L, 'Vol') $$, pg_temp.uid('b')),
  'P0001', 'ADMIN_REQUIRED', 'déconnexion refusée');
select throws_ok(format($$ select public.console_reply_support(%L, 'Bonjour') $$, pg_temp.v('sup')),
  'P0001', 'ADMIN_REQUIRED', 'réponse refusée');

-- ---------------------------------------------------------------------------
-- Recherche
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
select results_eq($$ select handle from public.console_search_accounts('@bob') $$,
  $$ values ('bob_ouaga'::text) $$, 'par @identifiant');
select results_eq($$ select handle from public.console_search_accounts('ouédraogo') $$,
  $$ values ('bob_ouaga'::text) $$, 'par nom');
select results_eq($$ select handle from public.console_search_accounts('70 00 00 02') $$,
  $$ values ('bob_ouaga'::text) $$, 'par numéro complet (8 chiffres)');
select results_eq($$ select handle from public.console_search_accounts('+226 70000002') $$,
  $$ values ('bob_ouaga'::text) $$, 'par numéro international');
select throws_ok($$ select * from public.console_search_accounts('7000') $$, 'P0001', 'SEARCH_PHONE_INCOMPLETE',
  'numéro partiel refusé');
select throws_ok($$ select * from public.console_search_accounts('b') $$, 'P0001', 'SEARCH_TOO_SHORT',
  'recherche trop courte');
select is((select count(*)::int from information_schema.columns
            where table_schema = 'public' and table_name = 'console_search_accounts'), 0, 'fonction, pas une vue');
reset role;
select is((select count(*)::int from private.admin_audit where action = 'account_search'), 4,
  'recherches abouties journalisées');
select ok((select bool_and(coalesce(detail::text, '') not like '%7000%') from private.admin_audit),
  'le numéro recherché n''est jamais inscrit au journal');

-- ---------------------------------------------------------------------------
-- Fiche
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('fiche', public.console_account(pg_temp.uid('b'))::text);
reset role;
select is(pg_temp.v('fiche')::jsonb ->> 'handle', 'bob_ouaga', 'fiche : identifiant');
select is((pg_temp.v('fiche')::jsonb ->> 'directs')::int, 1, 'fiche : 1 discussion (un nombre)');
select is(pg_temp.v('fiche')::jsonb #>> '{device,app_version}', '0.1.0+30', 'fiche : version de l''app');
select is((pg_temp.v('fiche')::jsonb #>> '{device,push}')::boolean, true, 'fiche : notifications activées');
select is(jsonb_array_length(pg_temp.v('fiche')::jsonb -> 'support'), 1, 'fiche : 1 demande d''assistance');
select ok(pg_temp.v('fiche') not like '%2267000%' and pg_temp.v('fiche') not like '%carla%',
  'fiche : ni numéro ni correspondant');
select is((select count(*)::int from private.admin_audit where action = 'account'), 1, 'fiche ouverte : journalisée');

-- ---------------------------------------------------------------------------
-- Répondre à la demande d'assistance
-- ---------------------------------------------------------------------------
create temporary table q0 on commit drop as select coalesce(max(id), 0) as id from net.http_request_queue;
select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select public.console_reply_support(%L, 'x') $$, pg_temp.v('sup')),
  'P0001', 'SUPPORT_REPLY_INVALID', 'réponse trop courte');
select lives_ok(format($$ select public.console_reply_support(%L, 'Mettez à jour l''application puis réessayez.') $$,
  pg_temp.v('sup')), 'réponse envoyée');
select throws_ok(format($$ select public.console_reply_support(%L, 'Encore') $$, pg_temp.v('sup')),
  'P0001', 'REPORT_NOT_FOUND', 'une seule réponse par demande');
select results_eq(format($$ select status, decision from public.console_reports('closed') where id = %L $$, pg_temp.v('sup')),
  $$ values ('closed'::text, 'answered'::text) $$, 'demande classée « répondue »');
reset role;
select results_eq($$ select convert_from(q.body, 'utf8')::jsonb from net.http_request_queue q
                    where q.id > (select id from q0) and q.url like '%/push-dispatch' $$,
  $$ select jsonb_build_object('support_reply_id', pg_temp.v('sup')) $$,
  'Bob notifié, avec le seul identifiant');
select results_eq(format($$ select token from public.push_support_targets(%L, %L) $$,
                         (select value from private.runtime_settings where key = 'push_dispatch_token'), pg_temp.v('sup')),
  $$ values ('jeton-fcm-de-bob-000000000001'::text) $$, 'cible : le téléphone de Bob');

select pg_temp.as_user('b');
set local role authenticated;
select results_eq($$ select details, reply from public.my_support_requests() $$,
  $$ values ('Je ne reçois plus les vocaux'::text, 'Mettez à jour l''application puis réessayez.'::text) $$,
  'Mes demandes : la demande et la réponse');
select pg_temp.as_user('c');
select is_empty($$ select * from public.my_support_requests() $$, 'chacun ne voit que ses demandes');

-- ---------------------------------------------------------------------------
-- Sanction depuis la fiche, puis « Déconnecter le téléphone »
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
select throws_ok(format($$ select public.console_sanction_user(%L, 'suspend', 'spam', 'Test', 3) $$, pg_temp.uid('b')),
  'P0001', 'MODERATION_INVALID', 'durée hors choix refusée');
select throws_ok(format($$ select public.console_sanction_user(%L, 'warn', 'spam', 'Moi') $$, pg_temp.uid('a')),
  'P0001', 'ADMIN_PROTECTED', 'le compte administrateur est protégé');
select lives_ok(format($$ select public.console_sanction_user(%L, 'warn', 'spam', 'Publicité') $$, pg_temp.uid('b')),
  'avertissement sans signalement');
reset role;
select is((select user_reason from private.sanctions where user_id = pg_temp.uid('b')), 'spam', 'motif choisi');

select pg_temp.as_user('a');
set local role authenticated;
select throws_ok(format($$ select public.console_disconnect_device(%L, 'Vol') $$, pg_temp.uid('a')),
  'P0001', 'ADMIN_PROTECTED', 'pas de déconnexion du compte administrateur');
select is(public.console_disconnect_device(pg_temp.uid('b'), 'Téléphone volé'), 1, 'téléphone de Bob déconnecté');
reset role;
select is((select count(*)::int from auth.sessions where user_id = pg_temp.uid('b')), 0, 'session coupée');
select is((select revoked_reason from public.devices where user_id = pg_temp.uid('b')), 'admin', 'appareil révoqué');
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok($$ select public.get_my_account() $$, 'P0001', 'AUTH_REQUIRED', 'Bob doit se reconnecter');
reset role;
select is((select count(*)::int from private.admin_audit where action = 'disconnect'), 1, 'déconnexion journalisée');

select * from finish();
rollback;
