-- PRIVIO — lot 9.1a : appels audio à deux (ADR-036, décisions du 15/11/2026).
--
-- Le son passe d'un téléphone à l'autre (WebRTC) ; la base ne fait que la mise en relation :
-- état de l'appel, échange des descriptions de session et des candidats réseau (relayés au
-- correspondant par le canal privé user:<id>, événement « call »), trace dans la discussion
-- (message système qui s'efface comme les autres). Seuls les contacts (discussion à deux)
-- peuvent s'appeler, jamais en cas de blocage ; réglage « Recevoir des appels ».
-- Aucun enregistrement, aucun contenu audio sur le serveur.

create table private.calls (
  id              uuid        primary key default gen_random_uuid(),
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  caller_id       uuid        not null references auth.users (id) on delete cascade,
  callee_id       uuid        not null references auth.users (id) on delete cascade,
  kind            text        not null default 'audio' check (kind in ('audio', 'video')),
  status          text        not null default 'ringing'
                              check (status in ('ringing', 'accepted', 'declined', 'missed',
                                                'cancelled', 'ended')),
  created_at      timestamptz not null default now(),
  answered_at     timestamptz,
  ended_at        timestamptz,
  end_reason      text,
  caller_seen_at  timestamptz not null default now(),
  callee_seen_at  timestamptz
);
create index calls_caller_idx on private.calls (caller_id, status);
create index calls_callee_idx on private.calls (callee_id, status);
create index calls_open_idx on private.calls (status) where status in ('ringing', 'accepted');
revoke all on private.calls from public, anon, authenticated;

-- Descriptions de session (offer / answer) et candidats réseau (ice), le temps de l'appel.
create table private.call_signals (
  id         bigint      generated always as identity primary key,
  call_id    uuid        not null references private.calls (id) on delete cascade,
  from_user  uuid        not null references auth.users (id) on delete cascade,
  kind       text        not null check (kind in ('offer', 'answer', 'ice')),
  payload    jsonb       not null check (octet_length(payload::text) <= 16384),
  created_at timestamptz not null default now()
);
create index call_signals_call_idx on private.call_signals (call_id, id);
revoke all on private.call_signals from public, anon, authenticated;

create table private.call_settings (
  user_id      uuid        primary key references auth.users (id) on delete cascade,
  accept_calls boolean     not null default true,
  updated_at   timestamptz not null default now()
);
revoke all on private.call_settings from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Outils
-- ---------------------------------------------------------------------------
create or replace function private.signal_call(p_user uuid, p_call private.calls)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    return;
  end if;
  execute 'select realtime.send($1, $2, $3, true)'
    using jsonb_build_object('conversation_id', p_call.conversation_id, 'call_id', p_call.id),
          'call', 'user:' || p_user::text;
end;
$$;

-- Trace dans la discussion : {"e":"call","k":"audio","v":"ended:183"} (auteur : l'appelant).
create or replace function private.call_trace(p_call private.calls)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ttl  integer := private.effective_ttl(p_call.conversation_id);
  v_at   timestamptz := clock_timestamp();
  v_val  text := case when p_call.status = 'ended' and p_call.answered_at is not null
                      then 'ended:' || greatest(0, extract(epoch from (p_call.ended_at - p_call.answered_at))::int)
                      else p_call.status end;
begin
  insert into public.messages (conversation_id, sender_id, client_msg_id, kind, body, sent_at, expires_at)
  values (p_call.conversation_id, p_call.caller_id, gen_random_uuid(), 'system',
          jsonb_build_object('e', 'call', 'k', p_call.kind, 'v', v_val)::text, v_at,
          v_at + make_interval(secs => v_ttl));
  update public.conversations set last_message_at = v_at where id = p_call.conversation_id;
  perform private.signal_members(p_call.conversation_id, 'message');
end;
$$;

-- Fin d'un appel (statut final), trace et signal aux deux.
create or replace function private.finish_call(p_id uuid, p_status text, p_reason text)
returns private.calls
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c private.calls%rowtype;
begin
  update private.calls
     set status = p_status, ended_at = now(), end_reason = p_reason
   where id = p_id and status in ('ringing', 'accepted')
  returning * into c;
  if not found then
    select * into c from private.calls where id = p_id;
    return c;
  end if;
  perform private.call_trace(c);
  perform private.signal_call(c.caller_id, c);
  perform private.signal_call(c.callee_id, c);
  delete from private.call_signals where call_id = p_id;
  return c;
end;
$$;

create or replace function private.require_call_party(p_call_id uuid)
returns private.calls
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  c     private.calls%rowtype;
begin
  select * into c from private.calls where id = p_call_id for update;
  if not found or v_uid not in (c.caller_id, c.callee_id) then
    raise exception 'CALL_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_uid = c.caller_id then
    update private.calls set caller_seen_at = now() where id = c.id;
  else
    update private.calls set callee_seen_at = now() where id = c.id;
  end if;
  return c;
end;
$$;

create or replace function private.call_json(c private.calls, p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', c.id, 'conversation_id', c.conversation_id, 'kind', c.kind, 'status', c.status,
    'outgoing', c.caller_id = p_uid,
    'peer_id', case when c.caller_id = p_uid then c.callee_id else c.caller_id end,
    'peer_name', (select p.display_name from public.profiles p
                   where p.id = case when c.caller_id = p_uid then c.callee_id else c.caller_id end),
    'peer_avatar', (select private.avatar_for(p.id, p_uid, p.avatar_path) from public.profiles p
                     where p.id = case when c.caller_id = p_uid then c.callee_id else c.caller_id end),
    'created_at', c.created_at, 'answered_at', c.answered_at, 'ended_at', c.ended_at,
    'end_reason', c.end_reason);
$$;

-- ---------------------------------------------------------------------------
-- Réglage « Recevoir des appels » (activé par défaut)
-- ---------------------------------------------------------------------------
create or replace function public.get_accept_calls()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  return coalesce((select s.accept_calls from private.call_settings s where s.user_id = v_uid), true);
end;
$$;

create or replace function public.set_accept_calls(p_on boolean)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  if p_on is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  insert into private.call_settings (user_id, accept_calls) values (v_uid, p_on)
  on conflict (user_id) do update set accept_calls = excluded.accept_calls, updated_at = now();
  return p_on;
end;
$$;

-- ---------------------------------------------------------------------------
-- Appeler, répondre, refuser, raccrocher
-- ---------------------------------------------------------------------------
create or replace function public.start_call(p_conversation_id uuid, p_kind text default 'audio')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_peer uuid;
  c      private.calls%rowtype;
begin
  if p_kind not in ('audio') then
    raise exception 'CALL_KIND_UNAVAILABLE' using errcode = 'P0001';
  end if;
  perform private.require_member(p_conversation_id);
  if not exists (select 1 from public.conversations x where x.id = p_conversation_id and x.kind = 'direct') then
    raise exception 'CALL_DIRECT_ONLY' using errcode = 'P0001';
  end if;
  select m.user_id into v_peer from public.conversation_members m
   where m.conversation_id = p_conversation_id and m.user_id <> v_uid and m.left_at is null;
  if v_peer is null or exists (select 1 from public.profiles p where p.id = v_peer and p.deleted_at is not null) then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if private.is_blocked_between(v_uid, v_peer) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;
  if not coalesce((select s.accept_calls from private.call_settings s where s.user_id = v_peer), true) then
    raise exception 'CALLS_DISABLED' using errcode = 'P0001';
  end if;
  perform private.expire_calls();
  -- Sérialise les appels vers une même personne.
  perform pg_advisory_xact_lock(hashtextextended('call:' || least(v_uid, v_peer)::text, 0));
  if exists (select 1 from private.calls x where x.status in ('ringing', 'accepted')
              and v_uid in (x.caller_id, x.callee_id)) then
    raise exception 'CALL_ALREADY_ACTIVE' using errcode = 'P0001';
  end if;
  insert into private.calls (conversation_id, caller_id, callee_id, kind)
  values (p_conversation_id, v_uid, v_peer, p_kind)
  returning * into c;
  -- Correspondant déjà en appel : « occupé », tracé comme appel manqué.
  if exists (select 1 from private.calls x where x.id <> c.id and x.status in ('ringing', 'accepted')
              and v_peer in (x.caller_id, x.callee_id)) then
    c := private.finish_call(c.id, 'missed', 'busy');
    return private.call_json(c, v_uid);
  end if;
  perform private.signal_call(v_peer, c);
  return private.call_json(c, v_uid);
end;
$$;

create or replace function public.answer_call(p_call_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c private.calls%rowtype := private.require_call_party(p_call_id);
begin
  if c.callee_id <> auth.uid() then
    raise exception 'CALL_NOT_FOUND' using errcode = 'P0001';
  end if;
  if c.status <> 'ringing' then
    raise exception 'CALL_NOT_RINGING' using errcode = 'P0001';
  end if;
  update private.calls set status = 'accepted', answered_at = now(), callee_seen_at = now()
   where id = c.id returning * into c;
  perform private.signal_call(c.caller_id, c);
  return private.call_json(c, auth.uid());
end;
$$;

create or replace function public.decline_call(p_call_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c private.calls%rowtype := private.require_call_party(p_call_id);
begin
  if c.callee_id <> auth.uid() or c.status <> 'ringing' then
    return private.call_json(c, auth.uid());
  end if;
  c := private.finish_call(c.id, 'declined', 'declined');
  return private.call_json(c, auth.uid());
end;
$$;

-- Raccrocher (ou annuler avant la réponse ; l'appelé voit alors un appel manqué).
create or replace function public.end_call(p_call_id uuid, p_reason text default 'hangup')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c private.calls%rowtype := private.require_call_party(p_call_id);
  v_reason text := case when p_reason in ('hangup', 'failed', 'timeout') then p_reason else 'hangup' end;
begin
  if c.status = 'ringing' then
    c := private.finish_call(c.id,
           case when c.caller_id = auth.uid() then (case when v_reason = 'timeout' then 'missed' else 'cancelled' end)
                else 'declined' end, v_reason);
  elsif c.status = 'accepted' then
    c := private.finish_call(c.id, 'ended', v_reason);
  end if;
  return private.call_json(c, auth.uid());
end;
$$;

-- Envoi d'une description de session ou d'un candidat réseau au correspondant.
create or replace function public.send_call_signal(p_call_id uuid, p_kind text, p_payload jsonb)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c    private.calls%rowtype := private.require_call_party(p_call_id);
  v_id bigint;
begin
  if c.status not in ('ringing', 'accepted') then
    raise exception 'CALL_ENDED' using errcode = 'P0001';
  end if;
  if p_kind not in ('offer', 'answer', 'ice') or p_payload is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if (select count(*) from private.call_signals s where s.call_id = c.id) >= 200 then
    raise exception 'RATE_LIMITED' using errcode = 'P0001';
  end if;
  insert into private.call_signals (call_id, from_user, kind, payload)
  values (c.id, auth.uid(), p_kind, p_payload)
  returning id into v_id;
  perform private.signal_call(case when c.caller_id = auth.uid() then c.callee_id else c.caller_id end, c);
  return v_id;
end;
$$;

-- État d'un appel et signaux du correspondant reçus après p_after (sert aussi de présence).
create or replace function public.call_state(p_call_id uuid, p_after bigint default 0)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c private.calls%rowtype;
begin
  perform private.expire_calls();
  c := private.require_call_party(p_call_id);
  return private.call_json(c, auth.uid()) || jsonb_build_object('signals', coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'kind', s.kind, 'payload', s.payload) order by s.id)
      from private.call_signals s
     where s.call_id = c.id and s.from_user <> auth.uid() and s.id > coalesce(p_after, 0)), '[]'::jsonb));
end;
$$;

-- Appel qui me concerne encore ouvert (ouverture de l'application, retour au premier plan).
create or replace function public.my_open_call()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  c     private.calls%rowtype;
begin
  perform private.expire_calls();
  select * into c from private.calls x
   where x.status in ('ringing', 'accepted') and v_uid in (x.caller_id, x.callee_id)
   order by x.created_at desc limit 1;
  if not found then
    return null;
  end if;
  return private.call_json(c, v_uid);
end;
$$;

-- Sans réponse en 45 s : manqué ; plus de nouvelles d'un des deux pendant 60 s : terminé.
create or replace function private.expire_calls()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r   record;
  v_n integer := 0;
begin
  for r in
    select id, status from private.calls
     where (status = 'ringing' and created_at < now() - interval '45 seconds')
        or (status = 'accepted' and least(caller_seen_at, coalesce(callee_seen_at, answered_at)) < now() - interval '60 seconds')
     for update skip locked
  loop
    perform private.finish_call(r.id, case when r.status = 'ringing' then 'missed' else 'ended' end,
                                case when r.status = 'ringing' then 'timeout' else 'lost' end);
    v_n := v_n + 1;
  end loop;
  -- Appels terminés : gardés 7 jours (diagnostic), sans contenu.
  delete from private.calls where status not in ('ringing', 'accepted') and created_at < now() - interval '7 days';
  return v_n;
end;
$$;

-- Accès au relais réseau : seulement pendant un appel (fonction call-ice).
create or replace function public.can_use_call_relay()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  return exists (select 1 from private.calls x where x.status in ('ringing', 'accepted')
                  and v_uid in (x.caller_id, x.callee_id));
end;
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_expire_calls';
    perform cron.schedule('privio_expire_calls', '* * * * *', 'select private.expire_calls()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.get_accept_calls() to authenticated;
grant execute on function public.set_accept_calls(boolean) to authenticated;
grant execute on function public.start_call(uuid, text) to authenticated;
grant execute on function public.answer_call(uuid) to authenticated;
grant execute on function public.decline_call(uuid) to authenticated;
grant execute on function public.end_call(uuid, text) to authenticated;
grant execute on function public.send_call_signal(uuid, text, jsonb) to authenticated;
grant execute on function public.call_state(uuid, bigint) to authenticated;
grant execute on function public.my_open_call() to authenticated;
grant execute on function public.can_use_call_relay() to authenticated;
