-- PRIVIO — Migration 8 (lot 2.4) : indicateur « en train d'écrire… »
-- Signal temps réel SANS contenu vers les AUTRES membres (jamais vers soi-même),
-- refusé en cas de blocage, limité en fréquence. Aucune donnée n'est stockée.

insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('typing_signal_hourly_limit', 'integer', '900', 60, 3600, null, false, true,
   'Signaux « en train d''écrire » par compte et par heure.');

create or replace function public.signal_typing(p_conversation_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_peer uuid := private.direct_peer(p_conversation_id, v_uid);
  r      record;
begin
  if v_peer is not null and private.is_blocked_between(v_uid, v_peer) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(v_uid, 'typing',
    private.policy_int('typing_signal_hourly_limit'), interval '1 hour');
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    return;
  end if;
  for r in
    select user_id from public.conversation_members
     where conversation_id = p_conversation_id and left_at is null and user_id <> v_uid
  loop
    execute 'select realtime.send($1, $2, $3, true)'
      using jsonb_build_object('conversation_id', p_conversation_id, 'user_id', v_uid),
            'typing', 'user:' || r.user_id::text;
  end loop;
end;
$$;

select private.harden_privileges();
grant execute on function public.signal_typing(uuid) to authenticated;
