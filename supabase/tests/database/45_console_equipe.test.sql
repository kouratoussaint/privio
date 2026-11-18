-- Lot 5.8 — Console : équipe et rôles (propriétaire, modérateur, assistance), deux étapes
-- obligatoires, groupes, réponses types, sites sans aperçu, suivi de la modération.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';

insert into auth.users (id, phone, phone_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '2267000000' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3), ('d', 4), ('e', 5)) as x(p, n);
insert into auth.sessions (id, user_id)
select ('00000000-0000-0000-0000-00000000' || repeat(p, 4))::uuid,
       ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid
  from (values ('a'), ('b'), ('c'), ('d'), ('e')) as x(p);
insert into public.profiles (id, handle, display_name)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, h, n
  from (values ('a', 'admin_privio', 'Admin'), ('b', 'modo_bf', 'Modo'), ('c', 'aide_bf', 'Aide'),
               ('d', 'dani', 'Dani'), ('e', 'eli_bf', 'Eli')) as x(p, h, n);
insert into private.user_contacts (user_id, phone_e164, phone_verified_at)
select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid, '+2267000000' || n, now()
  from (values ('a', 1), ('b', 2), ('c', 3), ('d', 4), ('e', 5)) as x(p, n)
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
create function pg_temp.tok() returns text language sql as $$
  select value from private.runtime_settings where key = 'push_dispatch_token' $$;
grant execute on function pg_temp.as_user(char), pg_temp.uid(char), pg_temp.v(text) to authenticated;

-- Groupe de Dani avec Eli ; signalements : un compte (Eli), le groupe, une demande d'assistance.
select pg_temp.as_user('d');
set local role authenticated;
insert into t values ('g', public.create_group('Marché du soir', null, array[pg_temp.uid('e')])::text);
select pg_temp.as_user('e');
select public.respond_to_invitation(i.invitation_id, true) from public.list_my_invitations() i;
reset role;
insert into private.reports (id, reporter_id, reported_user_id, conversation_id, reason, details, purge_after)
values ('00000000-0000-0000-0000-00000000f001', pg_temp.uid('d'), pg_temp.uid('e'), null, 'spam', null, now() + interval '90 days'),
       ('00000000-0000-0000-0000-00000000f002', pg_temp.uid('e'), null, pg_temp.v('g')::uuid, 'inappropriate', null, now() + interval '90 days'),
       ('00000000-0000-0000-0000-00000000f003', pg_temp.uid('d'), null, null, 'support', 'Je ne reçois rien', now() + interval '90 days');

-- ---------------------------------------------------------------------------
-- B. Équipe : le propriétaire ajoute un modérateur et une personne d'assistance
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
select is(public.console_access(), false, 'avant : pas d''accès');
select throws_ok($$ select public.console_team() $$, 'P0001', 'ADMIN_REQUIRED', 'hors équipe : refusé');
select pg_temp.as_user('a');
select is((public.console_me() ->> 'role'), 'owner', 'propriétaire');
select throws_ok($$ select public.console_team_add('+22670009999', 'moderator') $$, 'P0001', 'STAFF_NOT_FOUND',
  'numéro sans compte Privio');
select throws_ok($$ select public.console_team_add('+22670000001', 'moderator') $$, 'P0001', 'STAFF_OWNER',
  'le propriétaire n''est pas ajouté');
select throws_ok($$ select public.console_team_add('+22670000002', 'admin') $$, 'P0001', 'BODY_INVALID',
  'rôle inconnu');
select is((public.console_team_add('+22670000002', 'moderator') ->> 'role'), 'moderator', 'Modo ajouté');
select is((public.console_team_add('+22670000003', 'support') ->> 'role'), 'support', 'Aide ajoutée');
select is(jsonb_array_length(public.console_team()), 3, 'équipe : 3 personnes');
select is((select x ->> 'role' from jsonb_array_elements(public.console_team()) x
            where x ->> 'user_id' = pg_temp.uid('a')::text), 'owner', 'le propriétaire en tête');
reset role;
select is((select count(*)::int from private.admin_audit where action = 'team_add'), 2, 'ajouts journalisés');

-- Deux étapes obligatoires pour l'équipe.
select pg_temp.as_user('b');
set local role authenticated;
select is(public.console_access(), true, 'Modo voit l''entrée Administration');
select is((public.console_me() ->> 'two_step')::boolean, false, 'deux étapes à activer');
select throws_ok($$ select public.console_dashboard() $$, 'P0001', 'CONSOLE_TWO_STEP_REQUIRED',
  'sans deux étapes : console fermée');
reset role;
insert into private.two_step (user_id, pin_hash) values (pg_temp.uid('b'), 'x'), (pg_temp.uid('c'), 'x');
insert into private.two_step_sessions (session_id, user_id) values
  ('00000000-0000-0000-0000-00000000bbbb', pg_temp.uid('b')),
  ('00000000-0000-0000-0000-00000000cccc', pg_temp.uid('c'));

-- ---------------------------------------------------------------------------
-- A. Ce que chaque rôle peut faire
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
select lives_ok($$ select public.console_dashboard() $$, 'modérateur : tableau de bord');
select is((select array_agg(id::text order by id) from public.console_reports('open')),
  array['00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000f002'],
  'modérateur : signalements, pas l''assistance');
select throws_ok($$ select public.console_policies() $$, 'P0001', 'ADMIN_REQUIRED', 'modérateur : pas les réglages');
select throws_ok($$ select public.console_journal_page() $$, 'P0001', 'ADMIN_REQUIRED', 'ni le journal');
select throws_ok($$ select public.console_team() $$, 'P0001', 'ADMIN_REQUIRED', 'ni l''équipe');
select throws_ok($$ select public.console_reply_support('00000000-0000-0000-0000-00000000f003', 'Bonjour') $$,
  'P0001', 'ADMIN_REQUIRED', 'modérateur : pas de réponse d''assistance');
select throws_ok(format($$ select public.console_moderate(array['00000000-0000-0000-0000-00000000f003']::uuid[],
  'dismiss', 'Pas pour moi') $$), 'P0001', 'ADMIN_REQUIRED', 'ni classer une demande d''assistance');
select is(public.console_moderate(array['00000000-0000-0000-0000-00000000f001']::uuid[], 'warn',
  'Spam confirmé'), 1, 'modérateur : avertit Eli');
select throws_ok(format($$ select public.console_sanction_user(%L, 'warn', 'spam', 'Encore', null) $$,
  pg_temp.uid('c')), 'P0001', 'ADMIN_PROTECTED', 'une personne de l''équipe est protégée');

select pg_temp.as_user('c');
select is((select array_agg(id::text) from public.console_reports('open')),
  array['00000000-0000-0000-0000-00000000f003'], 'assistance : ses demandes seulement');
select lives_ok($$ select public.console_account('00000000-0000-0000-0000-0000000000e1') $$,
  'assistance : fiche d''un compte');
select throws_ok(format($$ select public.console_sanction_user(%L, 'warn', 'spam', 'Non', null) $$,
  pg_temp.uid('e')), 'P0001', 'ADMIN_REQUIRED', 'assistance : pas de sanction');
select throws_ok($$ select public.console_groups_page() $$, 'P0001', 'ADMIN_REQUIRED', 'ni les groupes');
select throws_ok(format($$ select public.console_moderate(array['00000000-0000-0000-0000-00000000f003']::uuid[],
  'warn', 'Non') $$), 'P0001', 'ADMIN_REQUIRED', 'assistance : classer seulement');
select lives_ok($$ select public.console_reply_support('00000000-0000-0000-0000-00000000f003',
  'Mettez à jour l''application.') $$, 'assistance : répond');
select is(jsonb_array_length(public.console_templates()) >= 6, true, 'assistance : réponses types');
select throws_ok($$ select public.console_template_save(null, 'support', 'Test', 'Bonjour') $$, 'P0001',
  'ADMIN_REQUIRED', 'seul le propriétaire écrit les réponses types');
reset role;

-- Alertes selon le rôle.
select is((select count(*)::int from public.push_admin_targets(pg_temp.tok(), 'report')), 0,
  'sans jeton enregistré : personne (contrôle de forme)');
select is(has_function_privilege('authenticated', 'public.push_admin_targets(text, text)', 'execute'), false,
  'cibles réservées à push-dispatch');

-- ---------------------------------------------------------------------------
-- C. Groupes
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
set local role authenticated;
select is((public.console_groups_page(null, 'reported') ->> 'total')::int, 1, 'groupes signalés : 1');
select is((public.console_groups_page('marché') -> 'rows' -> 0 ->> 'members')::int, 2, 'recherche, membres');
select is((public.console_group(pg_temp.v('g')::uuid) ->> 'owner_handle'), 'dani', 'propriétaire du groupe');
select ok(not (public.console_group(pg_temp.v('g')::uuid) ? 'messages'), 'aucun message');
select throws_ok(format($$ select public.console_group_action(%L, 'close', '') $$, pg_temp.v('g')), 'P0001',
  'MODERATION_NOTE_REQUIRED', 'motif obligatoire');
select is((public.console_group_action(pg_temp.v('g')::uuid, 'close', 'Ventes interdites') ->> 'closed')::boolean,
  true, 'groupe fermé');
reset role;
select is((select decision from private.reports where id = '00000000-0000-0000-0000-00000000f002'),
  'group_closed', 'son signalement est traité');
select pg_temp.as_user('b');
set local role authenticated;
select is((public.console_group_action(pg_temp.v('g')::uuid, 'reopen', 'Erreur de ma part') ->> 'posting'),
  'all', 'groupe rouvert');
select is(public.console_group_action(pg_temp.v('g')::uuid, 'delete', 'Groupe d''arnaque'), null,
  'groupe supprimé');
reset role;
select is((select count(*)::int from public.conversations where id = pg_temp.v('g')::uuid), 0, 'il n''existe plus');
select is((select count(*)::int from private.admin_audit where action like 'group\_%'), 3,
  'fermer, rouvrir, supprimer : journalisés');

-- ---------------------------------------------------------------------------
-- D. Réponses types (propriétaire)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
set local role authenticated;
insert into t values ('tpl', public.console_template_save(null, 'decision', 'Menaces', 'Menaces confirmées.')::text);
select is((select x ->> 'body' from jsonb_array_elements(public.console_templates()) x
            where x ->> 'id' = pg_temp.v('tpl')), 'Menaces confirmées.', 'réponse type ajoutée');
select throws_ok($$ select public.console_template_save(null, 'autre', 'X', 'Bonjour') $$, 'P0001', 'BODY_INVALID',
  'type inconnu');
select public.console_template_delete(pg_temp.v('tpl')::uuid);
select is((select count(*)::int from jsonb_array_elements(public.console_templates()) x
            where x ->> 'id' = pg_temp.v('tpl')), 0, 'réponse type retirée');

-- ---------------------------------------------------------------------------
-- E. Sites sans aperçu
-- ---------------------------------------------------------------------------
select pg_temp.as_user('b');
select is(public.console_block_site('https://www.Arnaque.example/promo?x=1', true), 'arnaque.example',
  'adresse complète : domaine retenu');
select throws_ok($$ select public.console_block_site('pas un site', true) $$, 'P0001', 'SITE_INVALID',
  'site invalide');
select is((public.console_blocked_sites() -> 0 ->> 'domain'), 'arnaque.example', 'liste');
reset role;
select is(private.preview_blocked('http://promo.arnaque.example/a'), true, 'sous-domaine bloqué');
select is(private.preview_blocked('https://arnaque.example.com/a'), false, 'autre domaine : aperçu');
select pg_temp.as_user('d');
set local role authenticated;
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('e'))::text);
insert into t select 'm1', id::text from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(),
  'Regarde https://arnaque.example/gain');
insert into t select 'm2', id::text from public.send_message(pg_temp.v('ab')::uuid, gen_random_uuid(),
  'Regarde https://lefaso.net/article');
select is(public.link_preview_target(pg_temp.v('m1')::uuid), null, 'site bloqué : pas d''aperçu');
select is(public.link_preview_target(pg_temp.v('m2')::uuid), 'https://lefaso.net/article', 'autre site : aperçu');
select pg_temp.as_user('b');
select public.console_block_site('arnaque.example', false);
select is(jsonb_array_length(public.console_blocked_sites()), 0, 'site retiré');

-- ---------------------------------------------------------------------------
-- F. Suivi de la modération
-- ---------------------------------------------------------------------------
select is((public.console_moderation_stats(7) ->> 'decided')::int, 2, 'décisions sur 7 jours');
select is((public.console_moderation_stats(7) -> 'by_decision' ->> 'warned')::int, 1, 'par décision');
select is((select count(*)::int from jsonb_array_elements(public.console_moderation_stats(30) -> 'by_person')), 2,
  'par personne (modération et assistance)');
select throws_ok($$ select public.console_moderation_stats(3) $$, 'P0001', 'BODY_INVALID', '7 ou 30 jours');

-- ---------------------------------------------------------------------------
-- Journal : qui a agi ; retrait de l'équipe
-- ---------------------------------------------------------------------------
select pg_temp.as_user('a');
select is((select r ->> 'by' from jsonb_array_elements(public.console_journal_page('groups') -> 'rows') r limit 1),
  'Modo', 'journal : nom de la personne');
select is((public.console_journal_page('team') ->> 'total')::int, 2, 'type « équipe »');
select public.console_team_set_role(pg_temp.uid('b'), 'support');
select public.console_team_remove(pg_temp.uid('c'));
select pg_temp.as_user('c');
select is(public.console_access(), false, 'retirée : plus d''accès');
select pg_temp.as_user('b');
select throws_ok($$ select public.console_groups_page() $$, 'P0001', 'ADMIN_REQUIRED',
  'devenu assistance : plus les groupes');

select * from finish();
rollback;
