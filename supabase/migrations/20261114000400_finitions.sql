-- PRIVIO — lot 7.2a : finitions (décisions du 14/11/2026).
--   1. « Ma fiche » : le nom affiché se modifie (1 à 40 caractères, quelques fois par jour).
--      L'@identifiant ne change pas (décision : non, pour le pilote).
--   2. Confidentialité par discussion ou par groupe. Chaque réglage vaut « comme dans mes
--      réglages » (null), activé (true) ou désactivé (false) :
--        * accusés de lecture et « en train d'écrire » : discussions et groupes ;
--        * en ligne / vu à, photo de profil, À propos : discussions à deux seulement ; le
--          réglage vaut pour ce contact partout (fiche, liste, membres d'un groupe commun).
--      Tout est appliqué par la base, comme les réglages du compte.

-- ---------------------------------------------------------------------------
-- 1. Nom affiché
-- ---------------------------------------------------------------------------
insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented,
   description_fr, category, label_fr, unit, admin_locked, advanced, sort_order, effect_fr)
values
  ('display_name_daily_limit', 'integer', '5', 1, 50, null, false, true,
   'Changements du nom affiché par compte et par jour.',
   'abuse', 'Changements de nom, par jour', 'nb', false, false, 85, null)
on conflict (key) do nothing;

create or replace function public.set_my_display_name(p_display_name text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_name text := btrim(regexp_replace(coalesce(p_display_name, ''), '\s+', ' ', 'g'));
begin
  if char_length(v_name) not between 1 and 40 then
    raise exception 'DISPLAY_NAME_INVALID' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.deleted_at is null) then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if (select p.display_name from public.profiles p where p.id = v_uid) = v_name then
    return v_name;
  end if;
  perform private.consume_rate_limit(v_uid, 'display_name',
    private.policy_int('display_name_daily_limit'), interval '1 day');
  update public.profiles set display_name = v_name where id = v_uid;
  return v_name;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Confidentialité par discussion
-- ---------------------------------------------------------------------------
create table private.conversation_privacy (
  conversation_id  uuid        not null references public.conversations (id) on delete cascade,
  user_id          uuid        not null references auth.users (id) on delete cascade,
  read_receipts    boolean,
  typing_indicator boolean,
  show_presence    boolean,
  show_avatar      boolean,
  show_about       boolean,
  updated_at       timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
revoke all on private.conversation_privacy from public, anon, authenticated;

-- Réglages propres à une discussion (nulls : comme dans les réglages du compte).
create or replace function private.conv_privacy(p_conversation_id uuid, p_user_id uuid)
returns private.conversation_privacy
language sql
stable
security definer
set search_path = ''
as $$
  select s.* from private.conversation_privacy s
   where s.conversation_id = p_conversation_id and s.user_id = p_user_id
  union all
  select p_conversation_id, p_user_id, null::boolean, null::boolean, null::boolean, null::boolean,
         null::boolean, now()
   where not exists (select 1 from private.conversation_privacy s
                      where s.conversation_id = p_conversation_id and s.user_id = p_user_id)
  limit 1;
$$;

-- Réglages de [p_owner] dans sa discussion à deux avec [p_viewer] (s'il y en a une).
create or replace function private.peer_privacy(p_owner uuid, p_viewer uuid)
returns private.conversation_privacy
language sql
stable
security definer
set search_path = ''
as $$
  select s.* from private.conversation_privacy s
    join public.conversations c on c.id = s.conversation_id and c.kind = 'direct'
   where s.user_id = p_owner and p_viewer is not null
     and c.direct_key = least(p_owner::text, p_viewer::text) || ':' || greatest(p_owner::text, p_viewer::text)
  limit 1;
$$;

-- Accusés de lecture de [p_user] dans cette discussion.
create or replace function private.read_receipts_on(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((private.conv_privacy(p_conversation_id, p_user_id)).read_receipts,
                  (private.privacy_of(p_user_id)).read_receipts);
$$;

-- Un réglage « tout le monde / mes contacts / personne », corrigé par le choix fait dans
-- la discussion à deux (true : montré à ce contact ; false : caché ; null : le réglage).
create or replace function private.visible_with(p_setting text, p_override boolean, p_owner uuid, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_owner = p_viewer then true
    when p_viewer is null or private.is_blocked_between(p_owner, p_viewer) then false
    when p_override is not null then p_override
    else private.visible_to(p_setting, p_owner, p_viewer)
  end;
$$;

create or replace function private.avatar_for(p_owner uuid, p_viewer uuid, p_path text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_path is not null
         and private.visible_with((private.privacy_of(p_owner)).avatar_visibility,
                                  (private.peer_privacy(p_owner, p_viewer)).show_avatar, p_owner, p_viewer)
    then p_path end;
$$;

create or replace function private.about_for(p_owner uuid, p_viewer uuid, p_about text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_about is not null
         and private.visible_with((private.privacy_of(p_owner)).about_visibility,
                                  (private.peer_privacy(p_owner, p_viewer)).show_about, p_owner, p_viewer)
    then p_about end;
$$;

-- Statut en ligne / vu à : inchangé (lot 4.3), plus le choix fait pour ce contact.
create or replace function public.get_presence(p_user_id uuid)
returns table (visible boolean, online boolean, last_seen_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_p   private.presence;
begin
  if p_user_id is null or p_user_id = v_uid
     or not private.shares_conversation(v_uid, p_user_id)
     or not exists (select 1 from public.profiles pr where pr.id = p_user_id and pr.deleted_at is null)
     or not private.visible_with((private.privacy_of(p_user_id)).presence_visibility,
                                 (private.peer_privacy(p_user_id, v_uid)).show_presence, p_user_id, v_uid) then
    return query select false, false, null::timestamptz;
    return;
  end if;
  select * into v_p from private.presence where user_id = p_user_id;
  return query select true, coalesce(v_p.online_until > now(), false), v_p.last_seen_at;
end;
$$;

-- « En train d'écrire » : inchangé, plus le choix fait dans cette discussion.
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
  if not coalesce((private.conv_privacy(p_conversation_id, v_uid)).typing_indicator,
                  (private.privacy_of(v_uid)).typing_indicator) then
    return;
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

-- Lecture et écriture (fiche de la discussion).
create or replace function public.get_conversation_privacy(p_conversation_id uuid)
returns table (
  read_receipts    boolean,
  typing_indicator boolean,
  show_presence    boolean,
  show_avatar      boolean,
  show_about       boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_member(p_conversation_id);
  s     private.conversation_privacy := private.conv_privacy(p_conversation_id, v_uid);
begin
  return query select s.read_receipts, s.typing_indicator, s.show_presence, s.show_avatar, s.show_about;
end;
$$;

-- Tous les champs à chaque fois (null : comme dans mes réglages). Groupe : seuls les
-- accusés de lecture et « en train d'écrire » ont un sens.
create or replace function public.set_conversation_privacy(
  p_conversation_id  uuid,
  p_read_receipts    boolean,
  p_typing_indicator boolean,
  p_show_presence    boolean default null,
  p_show_avatar      boolean default null,
  p_show_about       boolean default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_kind text := (select c.kind from public.conversations c where c.id = p_conversation_id);
begin
  if v_kind = 'group' and (p_show_presence is not null or p_show_avatar is not null or p_show_about is not null) then
    raise exception 'PRIVACY_SETTING_INVALID' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(v_uid, 'profile_write',
    private.policy_int('profile_write_hourly_limit'), interval '1 hour');
  if p_read_receipts is null and p_typing_indicator is null and p_show_presence is null
     and p_show_avatar is null and p_show_about is null then
    delete from private.conversation_privacy where conversation_id = p_conversation_id and user_id = v_uid;
  else
    insert into private.conversation_privacy
      (conversation_id, user_id, read_receipts, typing_indicator, show_presence, show_avatar, show_about)
    values (p_conversation_id, v_uid, p_read_receipts, p_typing_indicator, p_show_presence, p_show_avatar,
            p_show_about)
    on conflict (conversation_id, user_id) do update set
      read_receipts = excluded.read_receipts, typing_indicator = excluded.typing_indicator,
      show_presence = excluded.show_presence, show_avatar = excluded.show_avatar,
      show_about = excluded.show_about, updated_at = now();
  end if;
  -- Les accusés affichés chez les autres membres changent : leurs listes se mettent à jour.
  perform private.signal_members(p_conversation_id, 'receipt');
end;
$$;

-- Liste des discussions : inchangée (lot 4.3), accusés de lecture selon la discussion.
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
  last_sender_name     text,
  last_body            text,
  last_deleted         boolean,
  last_sent_at         timestamptz,
  last_expires_at      timestamptz,
  last_kind            text,
  ttl_seconds          integer,
  unread_count         integer,
  pinned               boolean,
  archived             boolean,
  muted_until          timestamptz,
  peer_delivered_up_to timestamptz,
  peer_read_up_to      timestamptz,
  sort_at              timestamptz,
  title                text,
  description          text,
  avatar_path          text,
  member_count         integer,
  my_role              text,
  posting              text,
  info_editing         text,
  cleared_before       timestamptz,
  clear_request_by     uuid,
  clear_request_expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_active_user();
  v_max integer := private.policy_int('message_ttl_hours') * 3600;
begin
  return query
  with mine as (
    select c.id, c.kind, c.created_by, c.created_at, c.ttl_seconds, c.title, c.description,
           c.avatar_path, c.posting, c.info_editing, c.cleared_at,
           me.joined_at, me.read_up_to, me.pinned_at, me.archived_at, me.muted_until, me.role,
           me.cleared_before,
           private.member_since(c.id, v_uid) as since
      from public.conversation_members me
      join public.conversations c on c.id = me.conversation_id
     where me.user_id = v_uid and me.left_at is null
  ),
  visible as (
    select m.* from public.messages m
      join mine on mine.id = m.conversation_id
     where m.expires_at > now() and m.sent_at >= mine.since
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
       and v.kind in ('text', 'voice', 'photo')
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
         lm.body, lm.deleted_at is not null, lm.sent_at, lm.expires_at, lm.kind,
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
         cr.requested_by, cr.expires_at
    from mine
    left join direct_peer dp on dp.conversation_id = mine.id
    left join public.profiles p on p.id = dp.user_id
    left join last_msg lm on lm.conversation_id = mine.id
    left join unread u on u.conversation_id = mine.id
    left join others o on o.conversation_id = mine.id
    left join private.clear_requests cr on cr.conversation_id = mine.id and cr.expires_at > now()
   -- Une discussion 1:1 vide n'apparaît que chez la personne qui l'a créée, sauf si elle a
   -- été vidée ou qu'une demande est en cours ; un groupe apparaît toujours.
   where lm.id is not null or mine.created_by = v_uid or mine.kind = 'group'
      or mine.cleared_before is not null or mine.cleared_at is not null or cr.conversation_id is not null
   order by (mine.pinned_at is not null) desc, coalesce(lm.sent_at, mine.created_at) desc;
end;
$$;


-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.set_my_display_name(text) to authenticated;
grant execute on function public.get_conversation_privacy(uuid) to authenticated;
grant execute on function public.set_conversation_privacy(uuid, boolean, boolean, boolean, boolean, boolean) to authenticated;
grant execute on function public.get_presence(uuid) to authenticated;
grant execute on function public.signal_typing(uuid) to authenticated;
grant execute on function public.list_conversations() to authenticated;
