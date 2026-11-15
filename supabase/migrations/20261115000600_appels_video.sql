-- PRIVIO — lot 9.2 : appels vidéo à deux (ADR-038).
--
-- La mise en relation est celle de l'audio (ADR-036/037) : seul le type d'appel change.
-- Chacun allume ou coupe sa caméra à tout moment, sans demande (la caméra passe dans la
-- même liaison, sans nouvelle négociation) ; on décroche toujours caméra coupée.
-- Le message de réveil indique le type (« Appel vidéo Privio entrant », sans nom).

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
  if p_kind not in ('audio', 'video') then
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

drop function if exists public.push_call_targets(text, uuid, text);
-- Jetons à réveiller (réservé à push-dispatch) : l'appelé, appareils actifs.
create or replace function public.push_call_targets(p_token text, p_call_id uuid, p_event text)
returns table (token text, conversation_id uuid, created_at timestamptz, kind text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.check_push_token(p_token);
  return query
  select t.token, c.conversation_id, c.created_at, c.kind
    from private.calls c
    join private.push_tokens t on t.user_id = c.callee_id
    join public.devices d on d.id = t.device_id and d.revoked_at is null
    join public.conversation_members m on m.conversation_id = c.conversation_id and m.user_id = c.callee_id
   where c.id = p_call_id
     and ((p_event = 'ring' and c.status = 'ringing')
       or (p_event = 'missed' and c.status in ('missed', 'cancelled')));
end;
$$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.start_call(uuid, text) to authenticated;
revoke all on function public.push_call_targets(text, uuid, text) from authenticated;
grant execute on function public.push_call_targets(text, uuid, text) to service_role;
