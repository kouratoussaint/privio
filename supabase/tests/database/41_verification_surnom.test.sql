-- Lot 10.4 — « Vérifié en personne » et surnom privé : code temporaire lié à une personne,
-- usage unique, vérification des deux côtés ; badge qui tombe au changement de téléphone ou
-- de numéro (avis fermable, qui revient si la situation change encore) ; surnom propre à
-- chaque compte, jamais visible de l'autre.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');

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
  ('00000000-0000-0000-0000-0000000000c1', 'carine_bobo', 'Carine');

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated;
create function pg_temp.as_user(p char, s text default null) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '00000000-0000-0000-0000-0000000000' || p || '1',
    'session_id', coalesce(s, '00000000-0000-0000-0000-00000000' || repeat(p, 4)),
    'role', 'authenticated')::text, true);
$$;
create function pg_temp.uid(p char) returns uuid language sql as $$
  select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;
create function pg_temp.v(p_k text) returns text language sql as $$ select v from t where k = p_k $$;
grant execute on function pg_temp.as_user(char, text), pg_temp.uid(char), pg_temp.v(text) to authenticated;

-- Chacun a un téléphone ; Alice et Bob sont contacts ; Carine partage un groupe avec Alice.
select pg_temp.as_user('a');
set local role authenticated;
select public.register_device('android', '0.1.0+74');
insert into t values ('ab', public.start_direct_conversation(pg_temp.uid('b'))::text);
reset role;
select pg_temp.as_user('b');
set local role authenticated;
select public.register_device('android', '0.1.0+74');
reset role;
select pg_temp.as_user('c');
set local role authenticated;
select public.register_device('android', '0.1.0+74');
insert into t values ('g', (public.create_group('Famille', null, array[pg_temp.uid('a')]))::text);
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select public.respond_to_invitation((select invitation_id from public.list_my_invitations() limit 1), true);

-- ------------------------------------------------------------------ Code de vérification
select throws_ok(format($$ select public.create_verification_code(%L) $$, pg_temp.uid('c')),
  'P0001', 'VERIFY_NOT_CONTACT', 'pas de vérification avec un simple membre de groupe');
select throws_ok(format($$ select public.create_verification_code(%L) $$, pg_temp.uid('a')),
  'P0001', 'VERIFY_NOT_CONTACT', 'pas avec soi-même');
insert into t select 'code', public.create_verification_code(pg_temp.uid('b')) ->> 'code';
select ok(pg_temp.v('code') ~ '^[0-9a-f]{32}$', 'code aléatoire de 128 bits');
select is(public.verification_code_status(pg_temp.v('code')), 'pending', 'code en attente');
reset role;
select is((select count(*)::int from private.verification_codes
            where code_hash = extensions.digest(pg_temp.v('code'), 'sha256')
              and expires_at between now() + interval '119 seconds' and now() + interval '121 seconds'),
  1, 'seule l''empreinte est gardée, valable 2 minutes');

-- Carine ne peut pas utiliser le code créé pour Bob.
select pg_temp.as_user('c');
set local role authenticated;
select throws_ok(format($$ select public.confirm_verification_code(%L, %L) $$, pg_temp.v('code'), pg_temp.uid('a')),
  'P0001', 'VERIFY_WRONG_PERSON', 'code créé pour une autre personne : refusé');
reset role;

-- Bob scanne en croyant avoir la fiche de Carine : refusé, le code reste utilisable.
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok(format($$ select public.confirm_verification_code(%L, %L) $$, pg_temp.v('code'), pg_temp.uid('c')),
  'P0001', 'VERIFY_WRONG_PERSON', 'code d''une autre personne que celle attendue : refusé');
select throws_ok(format($$ select public.confirm_verification_code(%L, %L) $$, repeat('0', 32), pg_temp.uid('a')),
  'P0001', 'VERIFY_CODE_INVALID', 'code inconnu : refusé');
select is((public.confirm_verification_code(pg_temp.v('code'), pg_temp.uid('a')) ->> 'user_id')::uuid,
  pg_temp.uid('a'), 'Bob scanne le code d''Alice');
select throws_ok(format($$ select public.confirm_verification_code(%L, %L) $$, pg_temp.v('code'), pg_temp.uid('a')),
  'P0001', 'VERIFY_CODE_EXPIRED', 'usage unique');
select results_eq($$ select user_id, verification, notice from public.my_contact_labels() $$,
  format($$ values (%L::uuid, 'verified'::text, false) $$, pg_temp.uid('a')),
  'Bob voit Alice « Vérifiée en personne »');
reset role;

select pg_temp.as_user('a');
set local role authenticated;
select is(public.verification_code_status(pg_temp.v('code')), 'verified', 'Alice voit le résultat');
select results_eq($$ select user_id, verification, lapse, notice from public.my_contact_labels() $$,
  format($$ values (%L::uuid, 'verified'::text, null::text, false) $$, pg_temp.uid('b')),
  'les deux téléphones voient « Vérifié en personne »');

-- Code expiré.
insert into t select 'code2', public.create_verification_code(pg_temp.uid('b')) ->> 'code';
reset role;
update private.verification_codes set expires_at = now() - interval '1 second'
 where code_hash = extensions.digest(pg_temp.v('code2'), 'sha256');
select pg_temp.as_user('b');
set local role authenticated;
select throws_ok(format($$ select public.confirm_verification_code(%L, %L) $$, pg_temp.v('code2'), pg_temp.uid('a')),
  'P0001', 'VERIFY_CODE_EXPIRED', 'code de plus de 2 minutes : refusé');
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select is(public.verification_code_status(pg_temp.v('code2')), 'expired', 'Alice voit « expiré »');
reset role;

-- ------------------------------------------------------------------ Le badge tombe
-- Bob se connecte sur un nouveau téléphone.
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-0000000bbbb2', '00000000-0000-0000-0000-0000000000b1');
select pg_temp.as_user('b', '00000000-0000-0000-0000-0000000bbbb2');
set local role authenticated;
select public.register_device('android', '0.1.0+74');
select results_eq($$ select verification from public.my_contact_labels() $$, $$ values ('verified'::text) $$,
  'Bob, lui, voit toujours Alice vérifiée (elle n''a pas changé)');
reset role;

select pg_temp.as_user('a');
set local role authenticated;
select results_eq($$ select verification, lapse, notice from public.my_contact_labels() $$,
  $$ values ('lapsed'::text, 'device'::text, true) $$, 'nouveau téléphone : vérification à refaire, avis');
select public.dismiss_verification_notice(pg_temp.uid('b'));
select results_eq($$ select verification, notice from public.my_contact_labels() $$,
  $$ values ('lapsed'::text, false) $$, 'avis fermé, badge toujours retiré');
reset role;

-- Bob change de numéro : l'avis revient.
update auth.users set phone = '22670000009' where id = pg_temp.uid('b');
select pg_temp.as_user('a');
set local role authenticated;
select results_eq($$ select verification, lapse, notice from public.my_contact_labels() $$,
  $$ values ('lapsed'::text, 'both'::text, true) $$, 'nouveau numéro en plus : l''avis revient');
reset role;
select is((select count(*)::int from private.in_person_verifications
            where phone_hi::text like '%22670000%' or phone_lo::text like '%22670000%'), 0,
  'aucun numéro en clair dans les vérifications');

-- Revérifier : tout redevient vert.
select pg_temp.as_user('b', '00000000-0000-0000-0000-0000000bbbb2');
set local role authenticated;
insert into t select 'code3', public.create_verification_code(pg_temp.uid('a')) ->> 'code';
reset role;
select pg_temp.as_user('a');
set local role authenticated;
select lives_ok(format($$ select public.confirm_verification_code(%L, %L) $$, pg_temp.v('code3'), pg_temp.uid('b')),
  'Alice scanne le nouveau code de Bob');
select results_eq($$ select verification, lapse, notice from public.my_contact_labels() $$,
  $$ values ('verified'::text, null::text, false) $$, 'revérifié');
reset role;

-- Seul le changement de numéro : « phone ».
update auth.users set phone = '22670000002' where id = pg_temp.uid('b');
select pg_temp.as_user('a');
set local role authenticated;
select results_eq($$ select lapse from public.my_contact_labels() $$, $$ values ('phone'::text) $$,
  'changement de numéro seul');
reset role;

-- ------------------------------------------------------------------ Surnom privé
select pg_temp.as_user('a');
set local role authenticated;
select is(public.set_contact_nickname(pg_temp.uid('b'), '  Bobo   le  grand '), 'Bobo le grand',
  'surnom enregistré (espaces nettoyés)');
select is(public.set_contact_nickname(pg_temp.uid('c'), 'Tantie'), 'Tantie',
  'surnom pour un membre d''un groupe commun');
select throws_ok(format($$ select public.set_contact_nickname(%L, %L) $$, pg_temp.uid('b'), repeat('x', 41)),
  'P0001', 'NICKNAME_INVALID', 'plus de 40 caractères : refusé');
select throws_ok(format($$ select public.set_contact_nickname(%L, 'Moi') $$, pg_temp.uid('a')),
  'P0001', 'NICKNAME_NOT_ALLOWED', 'pas de surnom pour soi-même');
select results_eq($$ select user_id, nickname from public.my_contact_labels() order by nickname $$,
  format($$ values (%L::uuid, 'Bobo le grand'::text), (%L::uuid, 'Tantie'::text) $$, pg_temp.uid('b'), pg_temp.uid('c')),
  'Alice retrouve ses surnoms (vérification et surnom sur la même ligne)');
reset role;

select pg_temp.as_user('b', '00000000-0000-0000-0000-0000000bbbb2');
set local role authenticated;
select is((select count(*)::int from public.my_contact_labels() where nickname is not null), 0,
  'Bob ne voit pas le surnom qu''Alice lui donne');
select throws_ok(format($$ select public.set_contact_nickname(%L, 'Inconnue') $$, pg_temp.uid('c')),
  'P0001', 'NICKNAME_NOT_ALLOWED', 'pas de surnom pour quelqu''un sans discussion commune');
reset role;

select pg_temp.as_user('a');
set local role authenticated;
select is(public.set_contact_nickname(pg_temp.uid('c'), '   '), null, 'surnom retiré');
select is((select count(*)::int from public.my_contact_labels() where user_id = pg_temp.uid('c')), 0,
  'plus rien pour Carine');
reset role;

-- Aucun accès direct aux tables.
set local role authenticated;
select throws_ok($$ select count(*) from private.contact_nicknames $$, '42501', null,
  'tables privées inaccessibles');
reset role;

-- Blocage : plus de nouveau code.
select pg_temp.as_user('a');
set local role authenticated;
insert into public.blocks (blocker_id, blocked_id) values (pg_temp.uid('a'), pg_temp.uid('b'));
select throws_ok(format($$ select public.create_verification_code(%L) $$, pg_temp.uid('b')),
  'P0001', 'BLOCKED', 'blocage : pas de vérification');
reset role;

select * from finish();
rollback;
