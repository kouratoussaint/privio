-- Lot 2.4 — « en train d'écrire » : membres seulement, jamais vers soi, blocage respecté.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Lot 4.7 : ce fichier ouvre des discussions directement (règles d'avant les demandes de
-- connexion, testées dans 16_demandes_connexion).
insert into private.policies (key, value) values ('connection_requests_required', 'false');

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '22670000001', now()),
  ('00000000-0000-0000-0000-0000000000b1', '22670000002', now()),
  ('00000000-0000-0000-0000-0000000000c1', '22670000003', now());
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000cccc', '00000000-0000-0000-0000-0000000000c1');
insert into public.profiles (id, handle, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice_bf', 'Alice'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob_ouaga', 'Bob'),
  ('00000000-0000-0000-0000-0000000000c1', 'carla', 'Carla');
create temporary table t (k text primary key, v uuid) on commit drop;
grant all on t to authenticated;
create function pg_temp.scalar(q text) returns text language plpgsql as $$
declare r text; begin execute q into r; return r; end; $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","session_id":"00000000-0000-0000-0000-00000000aaaa","role":"authenticated"}', true);
set local role authenticated;
insert into t values ('conv', public.start_direct_conversation('00000000-0000-0000-0000-0000000000b1'));
select lives_ok(format($$ select public.signal_typing(%L) $$, (select v from t where k = 'conv')),
  'un membre signale qu''il écrit');

reset role;
select case when to_regclass('realtime.messages') is not null then
  is(pg_temp.scalar($q$ select count(*)::text from realtime.messages where event = 'typing'
                       and topic = 'user:00000000-0000-0000-0000-0000000000b1' $q$), '1',
     'le correspondant reçoit le signal')
else skip('Realtime absent (environnement local sans Supabase)') end;
select case when to_regclass('realtime.messages') is not null then
  is(pg_temp.scalar($q$ select count(*)::text from realtime.messages where event = 'typing'
                       and topic = 'user:00000000-0000-0000-0000-0000000000a1' $q$), '0',
     'jamais de signal vers soi-même')
else skip('Realtime absent (environnement local sans Supabase)') end;

insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","session_id":"00000000-0000-0000-0000-00000000aaaa","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(format($$ select public.signal_typing(%L) $$, (select v from t where k = 'conv')),
  'P0001', 'BLOCKED', 'aucun signal en cas de blocage');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","session_id":"00000000-0000-0000-0000-00000000cccc","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(format($$ select public.signal_typing(%L) $$, (select v from t where k = 'conv')),
  'P0001', 'NOT_MEMBER', 'un non-membre ne peut rien signaler');

reset role;
select * from finish();
rollback;
