-- PRIVIO — lot 9.1b : appels reçus application fermée ou téléphone verrouillé (ADR-037).
--
-- La base confie à push-dispatch un identifiant d'appel seul : « ring » (message de données
-- prioritaire, valable 45 s, qui fait sonner l'écran d'appel du téléphone) et « missed »
-- (arrêt de la sonnerie + notification « Appel manqué », sans nom). La sourdine d'une
-- discussion coupe la notification d'appel manqué, pas la sonnerie.

create or replace function private.notify_call(p_call_id uuid, p_event text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_url    text := (select s.value from private.runtime_settings s where s.key = 'functions_url');
  v_token  text := (select s.value from private.runtime_settings s where s.key = 'push_dispatch_token');
  v_callee uuid := (select c.callee_id from private.calls c where c.id = p_call_id);
begin
  if v_url is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null
     or not exists (select 1 from private.push_tokens t where t.user_id = v_callee) then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
    using v_url || '/push-dispatch', jsonb_build_object('call_event', p_event, 'call_id', p_call_id),
          jsonb_build_object('Content-Type', 'application/json', 'x-privio-push', v_token), 10000;
end;
$$;

-- Jetons à réveiller (réservé à push-dispatch) : l'appelé, appareils actifs.
create or replace function public.push_call_targets(p_token text, p_call_id uuid, p_event text)
returns table (token text, conversation_id uuid, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.check_push_token(p_token);
  return query
  select t.token, c.conversation_id, c.created_at
    from private.calls c
    join private.push_tokens t on t.user_id = c.callee_id
    join public.devices d on d.id = t.device_id and d.revoked_at is null
    join public.conversation_members m on m.conversation_id = c.conversation_id and m.user_id = c.callee_id
   where c.id = p_call_id
     and ((p_event = 'ring' and c.status = 'ringing')
       or (p_event = 'missed' and c.status in ('missed', 'cancelled')));
end;
$$;

-- Sourdine : pas de notification « Appel manqué » (la sonnerie, elle, passe).
create or replace function public.push_call_muted(p_token text, p_call_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.check_push_token(p_token);
  return exists (select 1 from private.calls c
                   join public.conversation_members m
                     on m.conversation_id = c.conversation_id and m.user_id = c.callee_id
                  where c.id = p_call_id and m.muted_until is not null and m.muted_until > now());
end;
$$;

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
  -- Lot 9.1b : appel non décroché : la sonnerie s'arrête chez l'appelé, « Appel manqué ».
  if c.status in ('missed', 'cancelled') and c.end_reason is distinct from 'busy' then
    perform private.notify_call(c.id, 'missed');
  end if;
  perform private.signal_call(c.caller_id, c);
  perform private.signal_call(c.callee_id, c);
  delete from private.call_signals where call_id = p_id;
  return c;
end;
$$;

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
  -- Lot 9.1b : réveille le téléphone de l'appelé (application fermée ou en arrière-plan).
  perform private.notify_call(c.id, 'ring');
  return private.call_json(c, v_uid);
end;
$$;

-- Renégociation après un changement de réseau (Wi-Fi ↔ données) : plus de signaux par appel.
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
  if (select count(*) from private.call_signals s where s.call_id = c.id) >= 500 then
    raise exception 'RATE_LIMITED' using errcode = 'P0001';
  end if;
  insert into private.call_signals (call_id, from_user, kind, payload)
  values (c.id, auth.uid(), p_kind, p_payload)
  returning id into v_id;
  perform private.signal_call(case when c.caller_id = auth.uid() then c.callee_id else c.caller_id end, c);
  return v_id;
end;
$$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.start_call(uuid, text) to authenticated;
grant execute on function public.send_call_signal(uuid, text, jsonb) to authenticated;
revoke all on function public.push_call_targets(text, uuid, text) from authenticated;
revoke all on function public.push_call_muted(text, uuid) from authenticated;
grant execute on function public.push_call_targets(text, uuid, text) to service_role;
grant execute on function public.push_call_muted(text, uuid) to service_role;
