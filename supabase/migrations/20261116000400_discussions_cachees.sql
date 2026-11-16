-- Lot 10.2 : discussions cachées (décisions du 16/11/2026).
--   A. ouvertes par un appui long sur le logo Privio ; B. code Privio (jamais l'empreinte),
--   gardé sur le téléphone seulement ; C. masquer / ne plus masquer ; D. absentes des listes,
--   de la recherche, des favoris de toutes les discussions, des contacts et des non-lus ;
--   E. notifications neutres (« Nouveau message », sans discussion à ouvrir) ;
--   F. sonnerie neutre ; G. liste refermée dès qu'on la quitte ; H. état gardé sur le
--   serveur pour mon compte seulement (l'autre personne n'en sait rien).

alter table public.conversation_members add column if not exists secret_at timestamptz;

create or replace function public.set_conversation_secret(p_conversation_id uuid, p_secret boolean)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_member(p_conversation_id);
begin
  update public.conversation_members
     set secret_at = case when coalesce(p_secret, false) then coalesce(secret_at, now()) end
   where conversation_id = p_conversation_id and user_id = v_uid;
  return coalesce(p_secret, false);
end;
$$;

drop function if exists public.list_conversations();
CREATE OR REPLACE FUNCTION public.list_conversations()
 RETURNS TABLE(conversation_id uuid, kind text, peer_id uuid, peer_handle text, peer_display_name text, peer_avatar_path text, peer_deleted boolean, blocked boolean, last_message_id uuid, last_sender_id uuid, last_sender_name text, last_body text, last_deleted boolean, last_sent_at timestamp with time zone, last_expires_at timestamp with time zone, last_kind text, ttl_seconds integer, unread_count integer, pinned boolean, archived boolean, muted_until timestamp with time zone, peer_delivered_up_to timestamp with time zone, peer_read_up_to timestamp with time zone, sort_at timestamp with time zone, title text, description text, avatar_path text, member_count integer, my_role text, posting text, info_editing text, cleared_before timestamp with time zone, clear_request_by uuid, clear_request_expires_at timestamp with time zone, clear_request_delete boolean, read_erase_seconds integer, secret boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid uuid := private.require_active_user();
  v_max integer := private.policy_int('message_ttl_hours') * 3600;
begin
  return query
  with mine as (
    select c.id, c.kind, c.created_by, c.created_at, c.ttl_seconds, c.title, c.description,
           c.avatar_path, c.posting, c.info_editing, c.cleared_at, c.read_erase_seconds,
           me.joined_at, me.read_up_to, me.pinned_at, me.archived_at, me.muted_until, me.role,
           me.cleared_before, me.hidden_at, me.secret_at,
           private.member_since(c.id, v_uid) as since
      from public.conversation_members me
      join public.conversations c on c.id = me.conversation_id
     where me.user_id = v_uid and me.left_at is null
  ),
  visible as (
    select m.*, er.erase_at from public.messages m
      join mine on mine.id = m.conversation_id
      left join private.read_erasures er on er.message_id = m.id and er.user_id = v_uid
     where m.expires_at > now() and m.sent_at >= mine.since
       and (er.erase_at is null or er.erase_at > now())
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
       and v.kind in ('text', 'voice', 'photo', 'sticker', 'gif')
       and (mine.read_up_to is null or v.sent_at > mine.read_up_to)
     group by v.conversation_id
  ),
  others as (
    -- Accusés agrégés d'un groupe : « lu » ne tient compte que des membres qui partagent
    -- leurs accusés de lecture.
    select o.conversation_id,
           count(*)::int as n,
           case when bool_or(o.delivered_up_to is null) then null else min(o.delivered_up_to) end as delivered,
           case when count(*) filter (where private.read_receipts_on(o.conversation_id, o.user_id)) = 0 then null
                when bool_or(o.read_up_to is null)
                       filter (where private.read_receipts_on(o.conversation_id, o.user_id)) then null
                else min(o.read_up_to) filter (where private.read_receipts_on(o.conversation_id, o.user_id)) end as read
      from public.conversation_members o
      join mine on mine.id = o.conversation_id
     where o.user_id <> v_uid and o.left_at is null
     group by o.conversation_id
  ),
  direct_peer as (
    select peer.conversation_id, peer.user_id, peer.delivered_up_to,
           case when private.read_receipts_on(peer.conversation_id, peer.user_id) then peer.read_up_to end as read_up_to
      from public.conversation_members peer
      join mine on mine.id = peer.conversation_id and mine.kind = 'direct'
     where peer.user_id <> v_uid
  )
  select mine.id, mine.kind,
         dp.user_id, p.handle, p.display_name,
         case when mine.kind = 'direct' and p.deleted_at is null
              then private.avatar_for(dp.user_id, v_uid, p.avatar_path) end,
         mine.kind = 'direct' and (p.id is null or p.deleted_at is not null),
         mine.kind = 'direct' and coalesce(private.is_blocked_between(v_uid, dp.user_id), false),
         lm.id, lm.sender_id,
         case when lm.sender_id = v_uid then null
              else (select sp.display_name from public.profiles sp where sp.id = lm.sender_id) end,
         lm.body, lm.deleted_at is not null, lm.sent_at, least(lm.expires_at, lm.erase_at), lm.kind,
         least(coalesce(mine.ttl_seconds, v_max), v_max),
         coalesce(u.n, 0),
         mine.pinned_at is not null, mine.archived_at is not null,
         case when mine.muted_until > now() then mine.muted_until end,
         case when mine.kind = 'direct' then dp.delivered_up_to else o.delivered end,
         case when mine.kind = 'direct' then dp.read_up_to else o.read end,
         coalesce(lm.sent_at, mine.created_at),
         mine.title, mine.description, mine.avatar_path,
         coalesce(o.n, 0) + 1,
         case when mine.kind = 'group' then mine.role end,
         mine.posting, mine.info_editing,
         nullif(greatest(coalesce(mine.cleared_before, '-infinity'::timestamptz),
                         coalesce(mine.cleared_at, '-infinity'::timestamptz)), '-infinity'::timestamptz),
         cr.requested_by, cr.expires_at, coalesce(cr.then_delete, false),
         mine.read_erase_seconds,
         mine.secret_at is not null
    from mine
    left join direct_peer dp on dp.conversation_id = mine.id
    left join public.profiles p on p.id = dp.user_id
    left join last_msg lm on lm.conversation_id = mine.id
    left join unread u on u.conversation_id = mine.id
    left join others o on o.conversation_id = mine.id
    left join private.clear_requests cr on cr.conversation_id = mine.id and cr.expires_at > now()
   -- Une discussion 1:1 vide n'apparaît que chez la personne qui l'a créée, sauf si elle a
   -- été vidée ou qu'une demande est en cours ; un groupe apparaît toujours.
   -- Lot 7.2b1 : une discussion supprimée chez moi ne revient qu'avec un nouveau message.
   where (lm.id is not null or mine.created_by = v_uid or mine.kind = 'group'
      or mine.cleared_before is not null or mine.cleared_at is not null or cr.conversation_id is not null)
     and (mine.hidden_at is null or lm.id is not null)
   order by (mine.pinned_at is not null) desc, coalesce(lm.sent_at, mine.created_at) desc;
end;
$function$;

-- Notifications : la discussion cachée est signalée au service d'envoi (texte neutre).
drop function if exists public.push_targets(text, uuid);
CREATE OR REPLACE FUNCTION public.push_targets(p_token text, p_message_id uuid)
 RETURNS TABLE(token text, conversation_id uuid, is_group boolean, mentioned boolean, secret boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v public.messages%rowtype;
begin
  perform private.check_push_token(p_token);
  select * into v from public.messages m where m.id = p_message_id;
  if not found or v.expires_at <= now() or v.kind = 'system' or v.deleted_at is not null then
    return;
  end if;
  return query
  select t.token, v.conversation_id, c.kind = 'group', x.mentioned, m.secret_at is not null
    from public.conversation_members m
    join public.conversations c on c.id = m.conversation_id
    join private.push_tokens t on t.user_id = m.user_id
    join public.devices d on d.id = t.device_id and d.revoked_at is null
    cross join lateral (
      select exists (select 1 from private.message_mentions mm
                      where mm.message_id = v.id and mm.user_id = m.user_id) as mentioned
    ) x
   where m.conversation_id = v.conversation_id
     and m.left_at is null
     and m.user_id is distinct from v.sender_id
     and (x.mentioned
          or ((m.muted_until is null or m.muted_until <= now()) and m.notify_mode = 'all'))
     and (v.sender_id is null or not private.is_blocked_between(m.user_id, v.sender_id));
end;
$function$;

drop function if exists public.push_call_targets(text, uuid, text);
CREATE OR REPLACE FUNCTION public.push_call_targets(p_token text, p_call_id uuid, p_event text)
 RETURNS TABLE(token text, conversation_id uuid, created_at timestamp with time zone, kind text, secret boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  perform private.check_push_token(p_token);
  return query
  select t.token, c.conversation_id, c.created_at, c.kind, m.secret_at is not null
    from private.calls c
    join private.push_tokens t on t.user_id = c.callee_id
    join public.devices d on d.id = t.device_id and d.revoked_at is null
    join public.conversation_members m on m.conversation_id = c.conversation_id and m.user_id = c.callee_id
   where c.id = p_call_id
     and ((p_event = 'ring' and c.status = 'ringing')
       or (p_event = 'missed' and c.status in ('missed', 'cancelled')));
end;
$function$;

-- Rappel « messages bientôt effacés » : jamais pour une discussion cachée.
CREATE OR REPLACE FUNCTION private.expiry_reminder_candidates()
 RETURNS TABLE(user_id uuid, conversation_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select distinct m.user_id, m.conversation_id
    from public.conversation_members m
    join public.messages x on x.conversation_id = m.conversation_id
   where m.left_at is null
     and m.secret_at is null
     and x.sender_id is not null and x.sender_id <> m.user_id
     and x.kind <> 'system' and x.deleted_at is null
     and x.expires_at > now() and x.expires_at <= now() + interval '4 hours'
     and x.expires_at - x.sent_at >= interval '12 hours'
     and x.sent_at > coalesce(m.read_up_to, '-infinity'::timestamptz)
     and x.sent_at >= private.member_since(m.conversation_id, m.user_id)
     and (m.cleared_before is null or x.sent_at > m.cleared_before)
     and not exists (select 1 from public.message_hidden h
                      where h.message_id = x.id and h.user_id = m.user_id)
     and (m.muted_until is null or m.muted_until <= now())
     and m.notify_mode = 'all'
     and coalesce((select s.expiry_reminder from private.reminder_settings s
                    where s.user_id = m.user_id), true)
     and not private.is_blocked_between(m.user_id, x.sender_id)
     and exists (select 1 from private.push_tokens t where t.user_id = m.user_id)
     and not exists (select 1 from private.expiry_reminders r
                      where r.user_id = m.user_id and r.conversation_id = m.conversation_id
                        and r.created_at > now() - interval '12 hours');
$function$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.list_conversations() to authenticated;
grant execute on function public.set_conversation_secret(uuid, boolean) to authenticated;
revoke all on function public.push_targets(text, uuid) from public, anon, authenticated;
grant execute on function public.push_targets(text, uuid) to service_role;
revoke all on function public.push_call_targets(text, uuid, text) from public, anon, authenticated;
grant execute on function public.push_call_targets(text, uuid, text) to service_role;
