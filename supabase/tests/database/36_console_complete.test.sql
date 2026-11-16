-- Lot 5.5 — Console complète : fonctionnalités activables (vérifiées par le serveur),
-- message d'information, comptes A–Z paginés, journal filtrable.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';

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

-- ---------------------------------------------------------------------------
-- Fonctionnalités
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
select is((select count(*)::int from public.console_policies() where category = 'features'), 10,
  '10 réglages dans « Fonctionnalités »');
select is((select bool_and(not locked) from public.console_policies() where category = 'features'), true,
  'tous modifiables');
select is((select locked from public.console_policies() where key = 'message_copy_enabled'), true,
  'copie : engagement fixé (cadenas)');
select is(public.get_client_policies() -> 'values' -> 'calls_video_enabled', 'true'::jsonb,
  'les téléphones voient les interrupteurs');
insert into t values ('ab', public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1')::text);

-- Appels
select public.console_set_policy('calls_video_enabled', 'false');
select throws_ok(format($$ select public.start_call(%L, 'video') $$, pg_temp.v('ab')), 'P0001', 'FEATURE_DISABLED',
  'appel vidéo désactivé : refusé');
insert into t select 'c1', public.start_call(pg_temp.v('ab')::uuid, 'audio') ->> 'id';
select isnt(pg_temp.v('c1'), null, 'appel audio toujours possible');
select public.end_call(pg_temp.v('c1')::uuid);
select public.console_set_policy('calls_audio_enabled', 'false');
select throws_ok(format($$ select public.start_call(%L, 'audio') $$, pg_temp.v('ab')), 'P0001', 'FEATURE_DISABLED',
  'appels audio désactivés : refusé');
select public.console_set_policy('calls_audio_enabled', 'true');
select public.console_set_policy('calls_video_enabled', 'true');

-- Vocaux, photos, GIF (refusés à l'enregistrement du message, quel que soit le chemin)
reset role;
select public.console_set_policy('voice_enabled', 'false') from (select pg_temp.as_user('a')) x;
select throws_ok(format($$ insert into public.messages (conversation_id, sender_id, client_msg_id, kind, body, sent_at, expires_at)
  values (%L, '00000000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'voice', null, now(), now() + interval '1 hour') $$,
  pg_temp.v('ab')), 'P0001', 'FEATURE_DISABLED', 'vocaux désactivés : refusés');
select public.console_set_policy('photo_enabled', 'false');
select throws_ok(format($$ insert into public.messages (conversation_id, sender_id, client_msg_id, kind, body, sent_at, expires_at)
  values (%L, '00000000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'photo', null, now(), now() + interval '1 hour') $$,
  pg_temp.v('ab')), 'P0001', 'FEATURE_DISABLED', 'photos désactivées : refusées');
select public.console_set_policy('voice_enabled', 'true');
select public.console_set_policy('photo_enabled', 'true');
select public.console_set_policy('gif_enabled', 'false');
set local role authenticated;
select throws_ok($$ select public.gif_customer_id() $$, 'P0001', 'FEATURE_DISABLED', 'GIF désactivés : recherche refusée');
select public.console_set_policy('gif_enabled', 'true');

-- Aperçus des liens
select public.console_set_policy('link_preview_enabled', 'false');
insert into t select 'm', (to_jsonb(r) ->> 'id') from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(), 'Voir https://exemple.bf/page') r;
select is(public.link_preview_target(pg_temp.v('m')::uuid), null, 'aperçus désactivés : aucun lien prévisualisé');
select public.console_set_policy('link_preview_enabled', 'true');
select is(public.link_preview_target(pg_temp.v('m')::uuid), 'https://exemple.bf/page', 'réactivés : le lien est prévisualisé');

-- Groupes et liens d'invitation
select public.console_set_policy('group_create_enabled', 'false');
select throws_ok($$ select public.create_group('Famille') $$, 'P0001', 'FEATURE_DISABLED',
  'création de groupes désactivée');
select public.console_set_policy('group_create_enabled', 'true');
select public.console_set_policy('group_invite_links_enabled', 'false');
select throws_ok($$ select * from public.join_group_by_code('ABCD-EFGH') $$, 'P0001', 'FEATURE_DISABLED',
  'entrée par code refusée');
select public.console_set_policy('group_invite_links_enabled', 'true');

-- Message d'information
select is(public.console_set_policy('announcement_text', '"Maintenance ce soir à 22 h."'),
  '"Maintenance ce soir à 22 h."'::jsonb, 'message d''information enregistré');
select is(public.get_client_policies() -> 'values' ->> 'announcement_text', 'Maintenance ce soir à 22 h.',
  'les téléphones le reçoivent');
select throws_ok(format($$ select public.console_set_policy('announcement_text', %L) $$, to_jsonb(repeat('x', 201))),
  'P0001', 'POLICY_OUT_OF_BOUNDS', 'plus de 200 caractères : refusé');

-- Inscriptions
select public.console_set_policy('signups_enabled', 'false');
reset role;
select throws_ok($$ insert into public.profiles (id, handle, display_name)
  values ('00000000-0000-0000-0000-0000000000c1', 'chantal', 'Chantal') $$, 'P0001', 'SIGNUPS_CLOSED',
  'inscriptions fermées : nouveau compte refusé');
select pg_temp.as_user('a');
set local role authenticated;
select public.console_set_policy('signups_enabled', 'true');
reset role;
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000c1', 'chantal', 'Émilie');

-- ---------------------------------------------------------------------------
-- Comptes A–Z et journal
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok($$ select public.console_accounts_page(1, 25) $$, 'P0001', 'ADMIN_REQUIRED', 'liste refusée');
select throws_ok($$ select public.console_journal_page() $$, 'P0001', 'ADMIN_REQUIRED', 'journal refusé');
select pg_temp.as_user('a');
select is((select jsonb_agg(r ->> 'display_name') from jsonb_array_elements(public.console_accounts_page(1, 25) -> 'rows') r),
  '["Alice", "Bob", "Émilie"]'::jsonb, 'ordre alphabétique (Émilie avec les E)');
select is(public.console_accounts_page(1, 25) -> 'letters', '{"A": 0, "B": 1, "E": 2}'::jsonb, 'index A–Z');
select is((public.console_accounts_page(2, 5) -> 'rows'), '[]'::jsonb, 'page 2 vide');
select is((public.console_accounts_page(1, 5) ->> 'total')::int, 3, 'total');
select is((select bool_and(r ->> 'type' = 'settings')
             from jsonb_array_elements(public.console_journal_page('settings') -> 'rows') r), true,
  'journal filtré : réglages');
select cmp_ok((public.console_journal_page('settings', 1) ->> 'total')::int, '>=', 15, 'changements du jour');
select throws_ok($$ select public.console_journal_page('autre') $$, 'P0001', 'BODY_INVALID', 'type inconnu refusé');
select is((public.console_journal_page(null, null, 1, 5) -> 'rows' -> 0 ->> 'action'), 'account_list',
  'dernière action en tête');

select * from finish();
rollback;
