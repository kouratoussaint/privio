-- PRIVIO — Migration 14 (lot 4.3) : confidentialité avancée, présence, vider une discussion.
--
--   * réglages de confidentialité par compte (private.privacy_settings), appliqués par la base :
--     statut « en ligne » / « vu à », accusés de lecture, indicateur d'écriture, photo de
--     profil, invitations dans les groupes (tout le monde / mes contacts / personne), durée
--     par défaut des nouvelles discussions ; non réciproques (décision du 13/11/2026) ;
--   * présence : battement de l'application (touch_presence), lecture filtrée (get_presence) ;
--   * vider une discussion : « chez moi » (cleared_before, rien n'est supprimé chez l'autre) ou
--     « pour tout le monde » : suppression définitive, sans trace ; en 1:1 avec l'accord de
--     l'autre (demande valable 24 h), dans un groupe par un administrateur.
-- « Mes contacts » = personnes avec qui l'on a une discussion à deux.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table private.privacy_settings (
  user_id             uuid        primary key references auth.users (id) on delete cascade,
  presence_visibility text        not null default 'contacts'
                                  check (presence_visibility in ('everyone', 'contacts', 'nobody')),
  read_receipts       boolean     not null default true,
  typing_indicator    boolean     not null default true,
  avatar_visibility   text        not null default 'everyone'
                                  check (avatar_visibility in ('everyone', 'contacts', 'nobody')),
  group_invites       text        not null default 'everyone'
                                  check (group_invites in ('everyone', 'contacts', 'nobody')),
  default_ttl_seconds integer     check (default_ttl_seconds is null or default_ttl_seconds > 0),
  updated_at          timestamptz not null default now()
);

create table private.presence (
  user_id      uuid        primary key references auth.users (id) on delete cascade,
  online_until timestamptz not null,
  last_seen_at timestamptz not null
);

create table private.clear_requests (
  conversation_id uuid        primary key references public.conversations (id) on delete cascade,
  requested_by    uuid        not null references auth.users (id) on delete cascade,
  requested_at    timestamptz not null default now(),
  expires_at      timestamptz not null
);

-- « Vider chez moi » : messages envoyés avant cet instant masqués pour ce membre seulement.
alter table public.conversation_members add column if not exists cleared_before timestamptz;
-- « Vider pour tout le monde » : instant de la suppression (les téléphones effacent leur copie).
alter table public.conversations add column if not exists cleared_at timestamptz;

revoke all on private.privacy_settings, private.presence, private.clear_requests
  from public, anon, authenticated;

insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('clear_request_daily_limit', 'integer', '10', 1, 100, null, false, true,
   'Demandes « vider la discussion pour nous deux » par compte et par jour (anti-abus).'),
  ('clear_request_ttl_hours', 'integer', '24', 1, 168, null, true, true,
   'Durée de validité d''une demande « vider la discussion pour nous deux » (heures).'),
  ('presence_online_seconds', 'integer', '75', 30, 600, null, true, true,
   'Durée « en ligne » après le dernier signe de l''application (secondes).');

-- ---------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------
-- Réglages d'un compte (valeurs par défaut si jamais modifiés).
create or replace function private.privacy_of(p_user_id uuid)
returns private.privacy_settings
language sql
stable
security definer
set search_path = ''
as $$
  select s.* from private.privacy_settings s where s.user_id = p_user_id
  union all
  select p_user_id, 'contacts', true, true, 'everyone', 'everyone', null::integer, now()
   where not exists (select 1 from private.privacy_settings s where s.user_id = p_user_id)
  limit 1;
$$;

-- Contacts : une discussion à deux existe entre les deux comptes.
create or replace function private.are_contacts(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select a is not null and b is not null and exists (
    select 1 from public.conversations c
     where c.kind = 'direct'
       and c.direct_key = least(a::text, b::text) || ':' || greatest(a::text, b::text)
  );
$$;

-- Un réglage « tout le monde / mes contacts / personne » autorise-t-il ce lecteur ?
create or replace function private.visible_to(p_setting text, p_owner uuid, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_owner = p_viewer then true
    when p_viewer is null or private.is_blocked_between(p_owner, p_viewer) then false
    when p_setting = 'everyone' then true
    when p_setting = 'contacts' then private.are_contacts(p_owner, p_viewer)
    else false
  end;
$$;

-- Chemin de la photo de profil, ou null si son propriétaire ne la montre pas à ce lecteur.
create or replace function private.avatar_for(p_owner uuid, p_viewer uuid, p_path text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_path is not null
         and private.visible_to((private.privacy_of(p_owner)).avatar_visibility, p_owner, p_viewer)
    then p_path end;
$$;

-- Durée par défaut d'un compte, si elle respecte encore les bornes en vigueur.
create or replace function private.default_ttl_for(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when t between private.policy_int('message_ttl_min_minutes') * 60
               and private.policy_int('message_ttl_hours') * 3600
    then t end
    from (select (private.privacy_of(p_user_id)).default_ttl_seconds as t) x;
$$;

-- Historique visible : depuis l'arrivée (groupes), et après les « vider » éventuels.
create or replace function private.member_since(p_conversation_id uuid, p_user_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
           case when c.kind = 'group' then m.joined_at else '-infinity'::timestamptz end,
           coalesce(m.cleared_before, '-infinity'::timestamptz),
           coalesce(c.cleared_at, '-infinity'::timestamptz))
    from public.conversation_members m
    join public.conversations c on c.id = m.conversation_id
   where m.conversation_id = p_conversation_id and m.user_id = p_user_id and m.left_at is null;
$$;

-- ---------------------------------------------------------------------------
-- Photo de profil : lecture selon le réglage de son propriétaire.
-- ---------------------------------------------------------------------------
create or replace function private.can_read_avatar(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and (
    exists (
      select 1 from public.profiles p
       where p.avatar_path = p_name and p.deleted_at is null
         and private.avatar_for(p.id, auth.uid(), p.avatar_path) is not null)
    or exists (
      select 1 from public.conversations c
       where c.avatar_path = p_name and c.kind = 'group'
         and private.is_member(c.id, auth.uid()))
  );
$$;

create or replace function public.find_user_by_handle(p_handle text)
returns table (id uuid, handle text, display_name text, avatar_path text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  perform private.consume_rate_limit(v_uid, 'search_handle',
    (private.policy_value('search_handle_hourly_limit') #>> '{}')::integer, interval '1 hour');

  return query
    select p.id, p.handle, p.display_name, private.avatar_for(p.id, v_uid, p.avatar_path)
      from public.profiles p
     where p.handle = private.normalize_handle(p_handle)
       and p.deleted_at is null
       and p.id <> v_uid
       and not private.is_blocked_between(v_uid, p.id);
end;
$$;

create or replace function public.find_user_by_phone(p_phone text)
returns table (id uuid, handle text, display_name text, avatar_path text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  perform private.consume_rate_limit(v_uid, 'search_phone',
    (private.policy_value('search_phone_hourly_limit') #>> '{}')::integer, interval '1 hour');

  return query
    select p.id, p.handle, p.display_name, private.avatar_for(p.id, v_uid, p.avatar_path)
      from private.user_contacts c
      join public.profiles p on p.id = c.user_id
     where c.phone_e164 = private.normalize_phone_e164(p_phone)
       and c.phone_discoverable
       and p.deleted_at is null
       and p.id <> v_uid
       and not private.is_blocked_between(v_uid, p.id);
end;
$$;

create or replace function public.get_conversation_members(p_conversation_id uuid)
returns table (
  user_id      uuid,
  handle       text,
  display_name text,
  avatar_path  text,
  role         text,
  joined_at    timestamptz,
  invited      boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_role text := private.member_role(p_conversation_id, v_uid);
begin
  return query
  select x.* from (
  select m.user_id, p.handle, coalesce(p.display_name, 'Compte supprimé'),
         case when p.deleted_at is null then private.avatar_for(m.user_id, v_uid, p.avatar_path) end,
         m.role, m.joined_at, false
    from public.conversation_members m
    left join public.profiles p on p.id = m.user_id
   where m.conversation_id = p_conversation_id and m.left_at is null
  union all
  select i.invitee_id, p.handle, p.display_name, null::text, 'invited'::text, i.created_at, true
    from private.group_invitations i
    join public.profiles p on p.id = i.invitee_id and p.deleted_at is null
   where v_role in ('owner', 'admin') and i.conversation_id = p_conversation_id
     and i.status = 'pending' and i.expires_at > now()
  ) x (user_id, handle, display_name, avatar_path, role, joined_at, invited)
  order by x.invited, case x.role when 'owner' then 0 when 'admin' then 1 when 'member' then 2 else 3 end,
           x.display_name;
end;
$$;

-- ---------------------------------------------------------------------------
-- Invitations dans les groupes : selon le réglage de la personne invitée (ignorée sans le
-- révéler, comme une personne bloquée).
-- ---------------------------------------------------------------------------
create or replace function private.invite(p_conversation_id uuid, p_inviter uuid, p_invitee uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_max     integer := private.policy_int('group_max_members');
  v_pending integer;
begin
  if p_invitee is null or p_invitee = p_inviter
     or not exists (select 1 from public.profiles p where p.id = p_invitee and p.deleted_at is null)
     or private.is_member(p_conversation_id, p_invitee)
     or private.is_blocked_between(p_inviter, p_invitee)
     or not private.visible_to((private.privacy_of(p_invitee)).group_invites, p_invitee, p_inviter)
     or exists (select 1 from private.group_invitations i
                 where i.conversation_id = p_conversation_id and i.invitee_id = p_invitee
                   and i.status = 'pending' and i.expires_at > now()) then
    return false;
  end if;
  select count(*)::int into v_pending from private.group_invitations i
   where i.conversation_id = p_conversation_id and i.status = 'pending' and i.expires_at > now();
  if private.active_member_count(p_conversation_id) + v_pending >= v_max then
    raise exception 'GROUP_FULL' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(p_inviter, 'group_invite',
    private.policy_int('group_invite_hourly_limit'), interval '1 hour');
  update private.group_invitations set status = 'revoked'
   where conversation_id = p_conversation_id and invitee_id = p_invitee and status = 'pending';
  insert into private.group_invitations (conversation_id, invitee_id, inviter_id, expires_at)
  values (p_conversation_id, p_invitee, p_inviter,
          now() + make_interval(days => private.policy_int('group_invitation_ttl_days')));
  perform private.signal_user(p_invitee, p_conversation_id, 'invitation');
  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- Durée par défaut des nouvelles discussions (celle de la personne qui crée).
-- ---------------------------------------------------------------------------
create or replace function public.start_direct_conversation(p_other_user_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_key text;
  v_id  uuid;
begin
  if p_other_user_id is null or p_other_user_id = v_uid then
    raise exception 'SELF_CONVERSATION' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_other_user_id and p.deleted_at is null) then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if private.is_blocked_between(v_uid, p_other_user_id) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;

  v_key := least(v_uid::text, p_other_user_id::text) || ':' || greatest(v_uid::text, p_other_user_id::text);
  select c.id into v_id from public.conversations c where c.direct_key = v_key;
  if v_id is not null then
    return v_id;
  end if;

  perform private.consume_rate_limit(v_uid, 'conversation_create',
    private.policy_int('conversation_create_hourly_limit'), interval '1 hour');

  insert into public.conversations (kind, direct_key, created_by, ttl_seconds)
  values ('direct', v_key, v_uid, private.default_ttl_for(v_uid))
  on conflict (direct_key) do nothing
  returning id into v_id;

  if v_id is null then
    select c.id into v_id from public.conversations c where c.direct_key = v_key;
    return v_id;
  end if;

  insert into public.conversation_members (conversation_id, user_id)
  values (v_id, v_uid), (v_id, p_other_user_id);
  return v_id;
end;
$$;

create or replace function public.create_group(
  p_title       text,
  p_description text default null,
  p_invitee_ids uuid[] default '{}'
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_active_user();
  v_title text := btrim(coalesce(p_title, ''));
  v_desc  text := nullif(btrim(coalesce(p_description, '')), '');
  v_id    uuid;
  v_other uuid;
begin
  if char_length(v_title) not between 1 and 60 then
    raise exception 'GROUP_TITLE_INVALID' using errcode = 'P0001';
  end if;
  if v_desc is not null and char_length(v_desc) > 300 then
    raise exception 'GROUP_DESCRIPTION_INVALID' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.deleted_at is null) then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(v_uid, 'group_create',
    private.policy_int('group_create_daily_limit'), interval '1 day');

  insert into public.conversations (kind, title, description, created_by, last_message_at, ttl_seconds)
  values ('group', v_title, v_desc, v_uid, now(), private.default_ttl_for(v_uid))
  returning id into v_id;
  insert into public.conversation_members (conversation_id, user_id, role, added_by)
  values (v_id, v_uid, 'owner', v_uid);
  perform private.group_event(v_id, v_uid, 'created', null, v_title);
  foreach v_other in array coalesce(p_invitee_ids, '{}') loop
    perform private.invite(v_id, v_uid, v_other);
  end loop;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Indicateur d'écriture : rien n'est envoyé si la personne l'a désactivé.
-- ---------------------------------------------------------------------------
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
  if not (private.privacy_of(v_uid)).typing_indicator then
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

-- ---------------------------------------------------------------------------
-- Réglages : lecture et écriture (tous les champs à chaque fois).
-- ---------------------------------------------------------------------------
create or replace function public.get_my_privacy()
returns table (
  presence_visibility text,
  read_receipts       boolean,
  typing_indicator    boolean,
  avatar_visibility   text,
  group_invites       text,
  default_ttl_seconds integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  s     private.privacy_settings;
begin
  s := private.privacy_of(v_uid);
  return query select s.presence_visibility, s.read_receipts, s.typing_indicator,
                      s.avatar_visibility, s.group_invites, s.default_ttl_seconds;
end;
$$;

create or replace function public.set_my_privacy(
  p_presence_visibility text,
  p_read_receipts       boolean,
  p_typing_indicator    boolean,
  p_avatar_visibility   text,
  p_group_invites       text,
  p_default_ttl_seconds integer default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_ok  text[] := array['everyone', 'contacts', 'nobody'];
begin
  if p_presence_visibility is null or not (p_presence_visibility = any (v_ok))
     or p_avatar_visibility is null or not (p_avatar_visibility = any (v_ok))
     or p_group_invites is null or not (p_group_invites = any (v_ok))
     or p_read_receipts is null or p_typing_indicator is null then
    raise exception 'PRIVACY_SETTING_INVALID' using errcode = 'P0001';
  end if;
  if p_default_ttl_seconds is not null
     and (p_default_ttl_seconds < private.policy_int('message_ttl_min_minutes') * 60
          or p_default_ttl_seconds > private.policy_int('message_ttl_hours') * 3600) then
    raise exception 'TTL_INVALID' using errcode = 'P0001';
  end if;
  insert into private.privacy_settings as s
    (user_id, presence_visibility, read_receipts, typing_indicator, avatar_visibility,
     group_invites, default_ttl_seconds, updated_at)
  values (v_uid, p_presence_visibility, p_read_receipts, p_typing_indicator, p_avatar_visibility,
          p_group_invites, p_default_ttl_seconds, now())
  on conflict (user_id) do update set
    presence_visibility = excluded.presence_visibility,
    read_receipts       = excluded.read_receipts,
    typing_indicator    = excluded.typing_indicator,
    avatar_visibility   = excluded.avatar_visibility,
    group_invites       = excluded.group_invites,
    default_ttl_seconds = excluded.default_ttl_seconds,
    updated_at          = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Présence : l'application signale qu'elle est ouverte (≈ toutes les minutes) ou fermée.
-- ---------------------------------------------------------------------------
create or replace function public.touch_presence(p_online boolean default true)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_active_user();
  v_until timestamptz := case when coalesce(p_online, true)
                              then now() + make_interval(secs => private.policy_int('presence_online_seconds'))
                              else now() end;
begin
  insert into private.presence as p (user_id, online_until, last_seen_at)
  values (v_uid, v_until, now())
  on conflict (user_id) do update set online_until = excluded.online_until, last_seen_at = now();
end;
$$;

-- Statut d'une personne avec qui l'on partage une discussion, si elle le montre.
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
     or not private.visible_to((private.privacy_of(p_user_id)).presence_visibility, p_user_id, v_uid) then
    return query select false, false, null::timestamptz;
    return;
  end if;
  select * into v_p from private.presence where user_id = p_user_id;
  return query select true, coalesce(v_p.online_until > now(), false), v_p.last_seen_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- Vider une discussion
-- ---------------------------------------------------------------------------
-- Suppression définitive de tous les messages (vocaux et photos effacés par le déclencheur
-- messages_media_release), sans aucun message système.
create or replace function private.wipe_conversation(p_conversation_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  delete from public.messages where conversation_id = p_conversation_id;
  delete from private.clear_requests where conversation_id = p_conversation_id;
  update public.conversations set cleared_at = now() where id = p_conversation_id;
  perform private.signal_members(p_conversation_id, 'message');
end;
$$;

-- p_scope : 'me' (vider chez moi) ou 'everyone'. Renvoie 'cleared' ou 'requested'.
create or replace function public.clear_conversation(p_conversation_id uuid, p_scope text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_kind text;
  v_peer uuid;
  v_req  private.clear_requests;
begin
  if p_scope = 'me' then
    update public.conversation_members set cleared_before = now()
     where conversation_id = p_conversation_id and user_id = v_uid;
    perform private.signal_user(v_uid, p_conversation_id, 'message');
    return 'cleared';
  elsif p_scope is distinct from 'everyone' then
    raise exception 'CLEAR_SCOPE_INVALID' using errcode = 'P0001';
  end if;

  select c.kind into v_kind from public.conversations c where c.id = p_conversation_id for update;
  if v_kind = 'group' then
    perform private.require_group_role(p_conversation_id, array['owner', 'admin']);
    perform private.wipe_conversation(p_conversation_id);
    return 'cleared';
  end if;

  -- Discussion à deux : l'accord de l'autre personne est nécessaire.
  v_peer := private.direct_peer(p_conversation_id, v_uid);
  if v_peer is null or private.is_blocked_between(v_uid, v_peer)
     or not exists (select 1 from public.profiles p where p.id = v_peer and p.deleted_at is null) then
    raise exception 'CLEAR_NOT_ALLOWED' using errcode = 'P0001';
  end if;
  select * into v_req from private.clear_requests
   where conversation_id = p_conversation_id and expires_at > now();
  if found and v_req.requested_by = v_peer then
    -- L'autre l'avait déjà demandé : c'est un accord.
    perform private.wipe_conversation(p_conversation_id);
    return 'cleared';
  end if;
  if found and v_req.requested_by = v_uid then
    return 'requested';
  end if;
  perform private.consume_rate_limit(v_uid, 'clear_request',
    private.policy_int('clear_request_daily_limit'), interval '1 day');
  insert into private.clear_requests (conversation_id, requested_by, requested_at, expires_at)
  values (p_conversation_id, v_uid, now(),
          now() + make_interval(hours => private.policy_int('clear_request_ttl_hours')))
  on conflict (conversation_id) do update
    set requested_by = excluded.requested_by, requested_at = excluded.requested_at,
        expires_at = excluded.expires_at;
  perform private.signal_members(p_conversation_id, 'message');
  return 'requested';
end;
$$;

-- Réponse de l'autre personne. Renvoie 'cleared' ou 'refused'.
create or replace function public.respond_clear_request(p_conversation_id uuid, p_accept boolean)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_member(p_conversation_id);
  v_req private.clear_requests;
begin
  select * into v_req from private.clear_requests
   where conversation_id = p_conversation_id and expires_at > now()
   for update;
  if not found or v_req.requested_by = v_uid then
    raise exception 'CLEAR_REQUEST_NOT_FOUND' using errcode = 'P0001';
  end if;
  if coalesce(p_accept, false) then
    if private.is_blocked_between(v_uid, v_req.requested_by) then
      raise exception 'CLEAR_NOT_ALLOWED' using errcode = 'P0001';
    end if;
    perform private.wipe_conversation(p_conversation_id);
    return 'cleared';
  end if;
  delete from private.clear_requests where conversation_id = p_conversation_id;
  perform private.signal_members(p_conversation_id, 'message');
  return 'refused';
end;
$$;

create or replace function public.cancel_clear_request(p_conversation_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_member(p_conversation_id);
begin
  delete from private.clear_requests
   where conversation_id = p_conversation_id and requested_by = v_uid;
  if found then
    perform private.signal_members(p_conversation_id, 'message');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Liste des discussions : + vidage, demande en cours ; photo et accusés selon les réglages.
-- ---------------------------------------------------------------------------
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
           case when count(*) filter (where (private.privacy_of(o.user_id)).read_receipts) = 0 then null
                when bool_or(o.read_up_to is null)
                       filter (where (private.privacy_of(o.user_id)).read_receipts) then null
                else min(o.read_up_to) filter (where (private.privacy_of(o.user_id)).read_receipts) end as read
      from public.conversation_members o
      join mine on mine.id = o.conversation_id
     where o.user_id <> v_uid and o.left_at is null
     group by o.conversation_id
  ),
  direct_peer as (
    select peer.conversation_id, peer.user_id, peer.delivered_up_to,
           case when (private.privacy_of(peer.user_id)).read_receipts then peer.read_up_to end as read_up_to
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
-- Purge : + demandes échues.
-- ---------------------------------------------------------------------------
create or replace function private.purge_expired()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_count integer;
  r       record;
begin
  delete from public.messages where expires_at <= now();
  get diagnostics v_count = row_count;
  for r in
    select o.path from private.media_objects o
     where o.state in ('reserved', 'uploaded') and o.created_at < now() - interval '1 hour'
  loop
    perform private.abandon_reservation(r.path);
  end loop;
  delete from private.rate_limit_hits where window_start < now() - interval '1 day';
  delete from private.reports where purge_after <= now();
  delete from private.photo_quota_daily where quota_day < private.quota_day() - 7;
  delete from private.group_invitations
   where (status <> 'pending' or expires_at <= now()) and created_at < now() - interval '30 days';
  delete from private.clear_requests where expires_at <= now();
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();

grant execute on function public.find_user_by_handle(text) to authenticated;
grant execute on function public.find_user_by_phone(text) to authenticated;
grant execute on function public.get_conversation_members(uuid) to authenticated;
grant execute on function public.start_direct_conversation(uuid) to authenticated;
grant execute on function public.create_group(text, text, uuid[]) to authenticated;
grant execute on function public.signal_typing(uuid) to authenticated;
grant execute on function public.get_my_privacy() to authenticated;
grant execute on function public.set_my_privacy(text, boolean, boolean, text, text, integer) to authenticated;
grant execute on function public.touch_presence(boolean) to authenticated;
grant execute on function public.get_presence(uuid) to authenticated;
grant execute on function public.clear_conversation(uuid, text) to authenticated;
grant execute on function public.respond_clear_request(uuid, boolean) to authenticated;
grant execute on function public.cancel_clear_request(uuid) to authenticated;
grant execute on function public.list_conversations() to authenticated;
