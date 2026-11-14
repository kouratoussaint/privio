-- Lot 7.2b1-bis — « distribué » ne doit jamais valoir « lu ».
--
-- least() et greatest() ignorent les valeurs NULL en PostgreSQL : least(NULL, now())
-- vaut now(). Un simple accusé « distribué » (p_read_up_to NULL, envoyé par la liste des
-- discussions ou par une discussion qui n'est pas à l'écran) enregistrait donc « lu jusqu'à
-- maintenant ». Les bornes ne sont désormais calculées que pour les valeurs fournies.
create or replace function public.mark_conversation(
  p_conversation_id uuid,
  p_delivered_up_to timestamptz default null,
  p_read_up_to      timestamptz default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := private.require_member(p_conversation_id);
  v_read      timestamptz := case when p_read_up_to is null then null
                                  else least(p_read_up_to, now()) end;
  -- « Lu » implique « distribué ».
  v_delivered timestamptz := case when p_delivered_up_to is null and p_read_up_to is null then null
                                  else least(greatest(p_delivered_up_to, p_read_up_to), now()) end;
  v_changed   int;
begin
  if v_delivered is null and v_read is null then
    return;
  end if;
  update public.conversation_members
     set delivered_up_to = greatest(delivered_up_to, v_delivered),
         read_up_to      = greatest(read_up_to, v_read)
   where conversation_id = p_conversation_id and user_id = v_uid
     and (delivered_up_to is distinct from greatest(delivered_up_to, v_delivered)
          or read_up_to is distinct from greatest(read_up_to, v_read));
  get diagnostics v_changed = row_count;
  if v_changed > 0 then
    perform private.signal_members(p_conversation_id, 'receipt');
  end if;
end;
$$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.mark_conversation(uuid, timestamptz, timestamptz) to authenticated;
