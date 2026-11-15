-- Lot 8.3a — « Messages favoris » de toutes les discussions (menu ⋮ de la liste).
-- Mêmes règles que list_favorite_messages (lot 7.2c2), discussion par discussion :
-- membre actif, message non expiré, non supprimé, non masqué chez moi, envoyé après mon
-- arrivée dans le groupe.

create or replace function public.list_all_favorite_messages()
returns table (
  conversation_id uuid,
  message_id      uuid,
  sender_id       uuid,
  sender_name     text,
  kind            text,
  body            text,
  sent_at         timestamptz,
  expires_at      timestamptz,
  created_at      timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_active_user();
begin
  return query
  select f.conversation_id, m.id, m.sender_id, sp.display_name, m.kind, left(m.body, 500),
         m.sent_at, m.expires_at, f.created_at
    from private.message_favorites f
    join public.conversation_members cm
      on cm.conversation_id = f.conversation_id and cm.user_id = v_uid and cm.left_at is null
    join public.messages m on m.id = f.message_id
    left join public.profiles sp on sp.id = m.sender_id and sp.deleted_at is null
   where f.user_id = v_uid
     and m.expires_at > now() and m.deleted_at is null
     and m.sent_at >= private.member_since(f.conversation_id, v_uid)
     and not exists (select 1 from public.message_hidden h
                      where h.message_id = m.id and h.user_id = v_uid)
   order by m.sent_at desc
   limit 500;
end;
$$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.list_all_favorite_messages() to authenticated;
