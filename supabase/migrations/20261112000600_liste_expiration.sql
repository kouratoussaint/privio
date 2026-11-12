-- PRIVIO — Migration 6 (lot 2.D) : la liste des discussions expose l'expiration du
-- dernier message, pour afficher « s'efface dans 2 h » sans calcul côté client.
-- Le type de retour change : la fonction est supprimée puis recréée.

drop function if exists public.list_conversations();

create or replace function public.list_conversations()
returns table (
  conversation_id      uuid,
  kind                 text,
  peer_id              uuid,
  peer_handle          text,
  peer_display_name    text,
  peer_avatar_path     text,
  peer_deleted         boolean,
  blocked              boolean,
  last_message_id      uuid,
  last_sender_id       uuid,
  last_body            text,
  last_deleted         boolean,
  last_sent_at         timestamptz,
  last_expires_at      timestamptz,
  unread_count         integer,
  pinned               boolean,
  archived             boolean,
  peer_delivered_up_to timestamptz,
  peer_read_up_to      timestamptz,
  sort_at              timestamptz
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
  with mine as (
    select c.id, c.kind, c.created_by, c.created_at, me.read_up_to, me.pinned_at, me.archived_at
      from public.conversation_members me
      join public.conversations c on c.id = me.conversation_id
     where me.user_id = v_uid and me.left_at is null
  ),
  visible as (
    select m.* from public.messages m
      join mine on mine.id = m.conversation_id
     where m.expires_at > now()
       and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
  ),
  last_msg as (
    select distinct on (v.conversation_id) v.* from visible v
     order by v.conversation_id, v.sent_at desc
  ),
  unread as (
    select v.conversation_id, count(*)::int as n from visible v
      join mine on mine.id = v.conversation_id
     where v.sender_id is distinct from v_uid and v.deleted_at is null
       and (mine.read_up_to is null or v.sent_at > mine.read_up_to)
     group by v.conversation_id
  )
  select mine.id, mine.kind,
         peer.user_id, p.handle, p.display_name, p.avatar_path,
         coalesce(p.deleted_at is not null, true),
         coalesce(private.is_blocked_between(v_uid, peer.user_id), false),
         lm.id, lm.sender_id, lm.body, lm.deleted_at is not null, lm.sent_at, lm.expires_at,
         coalesce(u.n, 0),
         mine.pinned_at is not null, mine.archived_at is not null,
         peer.delivered_up_to, peer.read_up_to,
         coalesce(lm.sent_at, mine.created_at)
    from mine
    left join public.conversation_members peer
           on peer.conversation_id = mine.id and peer.user_id <> v_uid
    left join public.profiles p on p.id = peer.user_id
    left join last_msg lm on lm.conversation_id = mine.id
    left join unread u on u.conversation_id = mine.id
   -- Une discussion vide n'apparaît que chez la personne qui l'a créée.
   where lm.id is not null or mine.created_by = v_uid
   order by (mine.pinned_at is not null) desc, coalesce(lm.sent_at, mine.created_at) desc;
end;
$$;


select private.harden_privileges();
grant execute on function public.list_conversations() to authenticated;
