-- Lot 5.1 — Console d'administration : accès réservé au numéro vérifié enregistré côté
-- serveur, tableau de bord en nombres seulement, compteurs anonymes, journal de la console.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

-- Administrateur de test : le réglage privé désigne le numéro d'Alice.
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob');

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated;
create function pg_temp.as_user(p char) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p || '1',
    'session_id', '00000000-0000-0000-0000-00000000' || repeat(p, 4),
    'role', 'authenticated')::text, true);
$$;
create function pg_temp.v(p_k text) returns text language sql as $$ select v from t where k = p_k $$;
grant execute on function pg_temp.as_user(char), pg_temp.v(text) to authenticated;

select is((select value from private.runtime_settings where key = 'admin_phone_e164'), '+22670000001',
  'numéro administrateur : réglage privé du serveur');
select is(private.policy_int('admin_audit_retention_days'), 90, 'journal de la console : 90 jours par défaut');

-- ---------------------------------------------------------------------------
-- Accès
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
select is(public.console_access(), false, 'un autre compte : pas de console');
select throws_ok($$ select public.console_dashboard() $$, 'P0001', 'ADMIN_REQUIRED',
  'un autre compte : tableau de bord refusé par le serveur');
select throws_ok($$ select * from private.runtime_settings $$, '42501', null,
  'le numéro administrateur est illisible depuis l''application');
select throws_ok($$ select * from private.admin_audit $$, '42501', null, 'journal illisible');
select throws_ok($$ select * from private.daily_stats $$, '42501', null, 'compteurs illisibles');

select pg_temp.as_user('a');
select is(public.console_access(), true, 'le compte administrateur voit la console');

-- Session révoquée (nouvel appareil) : plus d'accès, même pour l'administrateur.
reset role;
delete from auth.sessions where id = '00000000-0000-0000-0000-00000000aaaa';
set local role authenticated;
select is(public.console_access(), false, 'session révoquée : pas de console');
select throws_ok($$ select public.console_dashboard() $$, 'P0001', 'AUTH_REQUIRED',
  'session révoquée : tableau de bord refusé');
reset role;
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1');

-- Numéro non vérifié pour le même compte : changer le réglage suffit à retirer l'accès.
update private.runtime_settings set value = '+22670000009' where key = 'admin_phone_e164';
set local role authenticated;
select is(public.console_access(), false, 'réglage changé au déploiement : accès retiré');
reset role;
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';

select ok(not has_function_privilege('anon', 'public.console_dashboard()', 'execute'),
  'anonyme : tableau de bord interdit');
select ok(not has_function_privilege('anon', 'public.console_access()', 'execute'),
  'anonyme : accès interdit');

-- ---------------------------------------------------------------------------
-- Activité comptée au fil de l'eau (compteurs anonymes)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('conv', public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1')::text);
select public.send_message(pg_temp.v('conv')::uuid, gen_random_uuid(), 'Message 1');
select public.send_message(pg_temp.v('conv')::uuid, gen_random_uuid(), 'Message 2');
insert into t values ('g', public.create_group('Club', null, array['00000000-0000-0000-0000-0000000000b1'::uuid])::text);
reset role;

select is((select value from private.daily_stats where metric = 'messages_text'
            and day = (now() at time zone 'utc')::date), 2::bigint, '2 messages comptés');
select is((select value from private.daily_stats where metric = 'groups_created'), 1::bigint, '1 groupe compté');
select is((select value from private.daily_stats where metric = 'group_invitations'), 1::bigint, '1 invitation comptée');
select is((select count(*)::int from private.daily_stats where metric = 'messages_system'), 0,
  'messages système non comptés');
select is((select count(*)::int from information_schema.columns
            where table_schema = 'private' and table_name = 'daily_stats'), 3,
  'compteurs : jour, nom, valeur (aucun identifiant)');

-- ---------------------------------------------------------------------------
-- Tableau de bord : nombres seulement
-- ---------------------------------------------------------------------------
insert into private.reports (reporter_id, reported_user_id, reason, purge_after)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'spam',
        now() + interval '90 days');
insert into private.push_log (message_id, recipients, sent, failed, status)
values (gen_random_uuid(), 2, 1, 1, 'partial');

select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('d', public.console_dashboard()::text);
reset role;

select is((pg_temp.v('d')::jsonb #>> '{accounts,total}')::int, 2, 'comptes : 2');
select is((pg_temp.v('d')::jsonb #>> '{activity,messages_today}')::int, 2, 'messages du jour : 2');
select is((pg_temp.v('d')::jsonb #>> '{activity,messages_7d}')::int, 2, 'messages sur 7 jours : 2');
select is((pg_temp.v('d')::jsonb #>> '{groups,total}')::int, 1, 'groupes : 1');
select is((pg_temp.v('d')::jsonb #>> '{groups,invitations_pending}')::int, 1, 'invitations en attente : 1');
select is((pg_temp.v('d')::jsonb #>> '{reports,open}')::int, 1, 'signalements en attente : 1');
select is((pg_temp.v('d')::jsonb #>> '{health,push_sent_24h}')::int, 1, 'notifications envoyées : 1');
select is((pg_temp.v('d')::jsonb #>> '{health,push_failed_24h}')::int, 1, 'notifications en échec : 1');
select ok(pg_temp.v('d') not like '%Message 1%' and pg_temp.v('d') not like '%Alice%'
          and pg_temp.v('d') not like '%Club%' and pg_temp.v('d') not like '%2267000%'
          and pg_temp.v('d') not like '%alice_bf%',
  'aucun contenu, nom, identifiant ni numéro dans le tableau de bord');
select is((select count(*)::int from private.admin_audit
            where admin_id = '00000000-0000-0000-0000-0000000000a1' and action = 'dashboard'), 1,
  'consultation inscrite au journal de la console');

-- Nettoyage : journal au-delà de 90 jours effacé.
update private.admin_audit set created_at = now() - interval '91 days';
select private.purge_console_data();
select is((select count(*)::int from private.admin_audit), 0, 'journal de plus de 90 jours effacé');

select * from finish();
rollback;
