-- Lot 6.1 — Journal technique joint à une demande d'assistance (ADR-055).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into private.policies (key, value) values ('connection_requests_required', 'false');
update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164';

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000b1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin_privio', 'Admin'),
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

select pg_temp.as_user('b');
set local role authenticated;
insert into t values ('sup', public.report('support', null, null, null, 'L''application se ferme', false,
  'Privio 0.1.0+90 · Android 13
19/11 10:42 Erreur StateError · chat_screen.dart:812')::text);
select throws_ok($$ select public.report('spam', '00000000-0000-0000-0000-0000000000a1', null, null, null, false, 'journal') $$,
  'P0001', 'REPORT_INVALID', 'journal refusé hors assistance');
select throws_ok(format($$ select public.report('support', null, null, null, 'Trop long', false, %L) $$, repeat('x', 16001)),
  'P0001', 'REPORT_INVALID', 'journal limité à 16 000 caractères');
select lives_ok($$ select public.report('support', null, null, null, 'Sans journal', false) $$,
  'demande sans journal : comme avant');
reset role;

select pg_temp.as_user('a');
set local role authenticated;
select ok((select tech_log from public.console_reports('open') where id = pg_temp.v('sup')::uuid)
          like 'Privio 0.1.0+90%', 'la console lit le journal joint');
select is((select tech_log from public.console_reports('open') where details = 'Sans journal'), null,
  'pas de journal si la personne ne l''a pas joint');
reset role;

select * from finish();
rollback;
