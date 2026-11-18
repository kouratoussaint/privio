-- Lot 5.9 — Console : pilotage. Inscriptions sur liste (numéros, codes), exceptions par
-- compte et par groupe, préréglages, message programmé, statistiques, nouveau téléphone.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';

-- a : propriétaire de la console ; b : compte existant ; c, d, e, f : pas encore de profil.
insert into auth.users (id, phone, phone_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '2267000000' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3), ('d', 4), ('e', 5), ('f', 6)) as x(p, n);
insert into auth.sessions (id, user_id)
select ('00000000-0000-0000-0000-00000000' || repeat(p, 4))::uuid,
       ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid
  from (values ('a'), ('b'), ('c'), ('d'), ('e'), ('f')) as x(p);
insert into public.profiles (id, handle, display_name)
values ('00000000-0000-0000-0000-0000000000a1', 'admin_privio', 'Admin'),
       ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob');

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
-- A. Inscriptions sur liste
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok($$ select public.console_signups() $$, 'P0001', 'ADMIN_REQUIRED', 'propriétaire seulement');
select pg_temp.as_user('a');
select is(public.console_signups() ->> 'mode', 'open', 'au départ : ouvertes');
select is(public.console_set_signups('list'), 'list', 'passage « Sur liste »');
select is((public.console_signup_phones(E'70 00 00 03\n+22670000004, abc', true) ->> 'count')::int, 2,
  'deux numéros ajoutés');
select is((public.console_signup_phones('abc', true) -> 'rejected' ->> 0), 'abc', 'ligne refusée signalée');
insert into t values ('code', public.console_signup_code_create('Pilote Bobo', 1, 7));
select ok(pg_temp.v('code') ~ '^[A-Z2-9]{8}$', 'code de 8 caractères');
select throws_ok($$ select public.console_signup_code_create('X', 0, 7) $$, 'P0001', 'BODY_INVALID',
  'au moins une utilisation');

select pg_temp.as_user('c');
select is(public.signup_status() ->> 'allowed', 'true', 'numéro autorisé : inscription possible');
select lives_ok($$ select * from public.create_profile('carla_bf', 'Carla') $$, 'Carla s''inscrit');
select pg_temp.as_user('e');
select is(public.signup_status(), '{"mode": "list", "allowed": false}'::jsonb, 'pas sur la liste');
select throws_ok($$ select * from public.create_profile('eli_bf', 'Eli') $$, 'P0001', 'SIGNUPS_LIST_ONLY',
  'sans code : refusé');
select throws_ok($$ select public.redeem_signup_code('AAAA2222') $$, 'P0001', 'SIGNUP_CODE_INVALID',
  'code inconnu');
select is(public.redeem_signup_code(lower(pg_temp.v('code'))), true, 'bon code (minuscules acceptées)');
select lives_ok($$ select * from public.create_profile('eli_bf', 'Eli') $$, 'Eli s''inscrit avec le code');
select pg_temp.as_user('f');
select throws_ok(format($$ select public.redeem_signup_code(%L) $$, pg_temp.v('code')), 'P0001',
  'SIGNUP_CODE_INVALID', 'code à usage unique déjà utilisé');
select pg_temp.as_user('a');
select public.console_set_signups('closed');
select pg_temp.as_user('d');
select throws_ok($$ select * from public.create_profile('dani_bf', 'Dani') $$, 'P0001', 'SIGNUPS_CLOSED',
  'fermées : même un numéro autorisé attend');
select pg_temp.as_user('a');
select public.console_set_signups('open');
select pg_temp.as_user('f');
select lives_ok($$ select * from public.create_profile('fati_bf', 'Fati') $$, 'ouvertes : tout le monde');

-- ---------------------------------------------------------------------------
-- B. Exceptions par compte et par groupe
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
insert into t values ('g', public.create_group('Marché', null, '{}')::text);
insert into t values ('bc', public.start_direct_conversation(pg_temp.uid('c'))::text);
select pg_temp.as_user('a');
select public.console_set_override('user', pg_temp.uid('b'), 'photo_daily_limit', '0', 7, 'Abus de photos');
select public.console_set_override('user', pg_temp.uid('b'), 'calls_video_enabled', 'false', null, null);
select public.console_set_override('user', pg_temp.uid('b'), 'group_create_enabled', 'false', null, null);
select public.console_set_override('group', pg_temp.v('g')::uuid, 'group_max_members', '300', null, 'Grand marché');
select throws_ok(format($$ select public.console_set_override('group', %L, 'group_max_members', '600', null, null) $$,
  pg_temp.v('g')), 'P0001', 'POLICY_OUT_OF_BOUNDS', '500 au plus pour un groupe');
select throws_ok(format($$ select public.console_set_override('user', %L, 'message_ttl_hours', '1', null, null) $$,
  pg_temp.uid('b')), 'P0001', 'BODY_INVALID', 'réglage non prévu pour une exception');
select public.console_set_override('group', pg_temp.v('g')::uuid, 'link_preview_enabled', 'false', 1, null);
select is(jsonb_array_length(public.console_overrides()), 5, 'cinq exceptions en cours');
select is(jsonb_array_length(public.console_overrides(pg_temp.uid('b'))), 3, 'trois pour Bob');
reset role;
select is(private.group_member_cap(pg_temp.v('g')::uuid), 300, 'groupe : 300 membres');
select is(private.group_policy(pg_temp.v('bc')::uuid, 'link_preview_enabled'), 'true'::jsonb,
  'autre discussion : réglage global');

select pg_temp.as_user('b');
set local role authenticated;
select is((public.get_photo_quota() ->> 'limit')::int, 0, 'Bob : 0 photo par jour');
select is(public.get_client_policies() -> 'values' -> 'calls_video_enabled', 'false'::jsonb,
  'son application cache la vidéo');
select throws_ok(format($$ select public.start_call(%L, 'video') $$, pg_temp.v('bc')), 'P0001',
  'FEATURE_DISABLED', 'appel vidéo refusé pour Bob');
select is((public.start_call(pg_temp.v('bc')::uuid, 'audio') ->> 'status'), 'ringing', 'appel audio possible');
select throws_ok($$ select public.create_group('Autre', null, '{}') $$, 'P0001', 'FEATURE_DISABLED',
  'création de groupe refusée pour Bob');
select pg_temp.as_user('c');
select is(public.get_client_policies() -> 'values' -> 'calls_video_enabled', 'true'::jsonb,
  'Carla : réglage global');

-- Exception expirée : ignorée, puis effacée.
reset role;
update private.policies set expires_at = now() - interval '1 minute'
 where key = 'photo_daily_limit' and scope_type = 'user';
select is((private.user_policy(pg_temp.uid('b'), 'photo_daily_limit') #>> '{}')::int,
  (private.policy_value('photo_daily_limit') #>> '{}')::int, 'exception expirée : valeur globale');
select private.expire_overrides();
select is((select count(*)::int from private.policies where key = 'photo_daily_limit' and scope_type = 'user'
              and enabled), 0, 'exception expirée désactivée');
select pg_temp.as_user('a');
set local role authenticated;
select public.console_set_override('user', pg_temp.uid('b'), 'calls_video_enabled', null, null, null);
select is(jsonb_array_length(public.console_overrides(pg_temp.uid('b'))), 1, 'exception retirée');

-- ---------------------------------------------------------------------------
-- C. Préréglages
-- ---------------------------------------------------------------------------
select ok((select bool_or(x ->> 'key' = 'signups_mode') from jsonb_array_elements(public.console_preset('pilot')) x),
  'mode pilote : inscriptions sur liste annoncées');
select is(public.console_signups() ->> 'mode', 'open', 'aperçu : rien n''est changé');
select ok(jsonb_array_length(public.console_preset('pilot', true)) >= 3, 'mode pilote appliqué');
select is(public.console_signups() ->> 'mode', 'list', 'inscriptions sur liste');
reset role;
select is(private.policy_int('group_max_members'), 25, 'groupes de 25');
set local role authenticated;
select is(public.console_preset('pilot'), '[]'::jsonb, 'plus rien à changer');
select throws_ok($$ select public.console_preset('autre') $$, 'P0001', 'BODY_INVALID', 'préréglage inconnu');
select lives_ok($$ select public.console_preset('normal', true) $$, 'retour au mode normal');
select is(public.console_signups() ->> 'mode', 'open', 'inscriptions ouvertes');

-- ---------------------------------------------------------------------------
-- D. Message programmé
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.console_set_scheduled_announcement('Maintenance', now() + interval '2 hours',
  now() + interval '1 hour') $$, 'P0001', 'BODY_INVALID', 'fin avant le début');
select public.console_set_scheduled_announcement('Maintenance ce soir de 22 h à 23 h',
  now() + interval '1 hour', now() + interval '3 hours');
select is(public.console_scheduled_announcement() ->> 'live', 'false', 'programmé, pas encore affiché');
select pg_temp.as_user('b');
select is(public.get_client_policies() -> 'values' ->> 'announcement_text', '', 'pas encore');
reset role;
update private.scheduled_announcement set starts_at = now() - interval '1 minute';
select pg_temp.as_user('b');
set local role authenticated;
select is(public.get_client_policies() -> 'values' ->> 'announcement_text', 'Maintenance ce soir de 22 h à 23 h',
  'pendant sa période : affiché');
select pg_temp.as_user('a');
select public.console_set_scheduled_announcement('', null, null);
select is(public.console_scheduled_announcement(), null, 'retiré');

-- ---------------------------------------------------------------------------
-- E, F, G. Statistiques, export, nouveau téléphone
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
select public.register_device('android', '0.1.0+86', 'Tecno', '13');
select public.set_device_language('mos');
select throws_ok($$ select public.set_device_language('en') $$, 'P0001', 'BODY_INVALID', 'langue inconnue');
select pg_temp.as_user('a');
select is((public.console_stats_extra(7) -> 'languages' ->> 'mos')::int, 1, 'langues des téléphones');
select ok(jsonb_array_length(public.console_stats_extra(7) -> 'retention') >= 1, 'rétention par semaine');
select is(jsonb_array_length(public.console_stats_extra(7) -> 'usage'), 7, 'usage : 7 jours');
select lives_ok($$ select public.console_log_export(30) $$, 'export journalisé');
select pg_temp.as_user('b');
select throws_ok($$ select public.console_stats_extra(7) $$, 'P0001', 'ADMIN_REQUIRED', 'statistiques : propriétaire');

select pg_temp.as_user('a');
select public.register_device('android', '0.1.0+86', 'Itel', '12');
select public.console_me();
select public.console_me();
reset role;
select is((select count(*)::int from private.admin_alerts where kind = 'console_device'), 1,
  'nouveau téléphone : une alerte, une seule fois');
select is((select count(*)::int from private.admin_audit where action in ('export', 'console_device')), 2,
  'export et nouveau téléphone au journal');

select * from finish();
rollback;
