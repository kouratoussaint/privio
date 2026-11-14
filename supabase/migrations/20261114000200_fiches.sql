-- PRIVIO — lot 7.1a : fiches contact et groupe (décisions du 14/11/2026).
--
-- - « À propos » (140 caractères, déjà prévu dans profiles) : modifiable par la personne,
--   visible selon le nouveau réglage « Qui voit mon À propos » (par défaut : mes contacts).
-- - Fiche d'un contact : nom, @identifiant, À propos et photo selon ses réglages.
-- - Groupes en commun, médias encore présents dans une discussion (72 h au plus).
-- La sourdine d'une discussion à deux utilise set_conversation_mute (déjà valable pour tous).

-- ---------------------------------------------------------------------------
-- 1. Réglage « Qui voit mon À propos »
-- ---------------------------------------------------------------------------
alter table private.privacy_settings
  add column about_visibility text not null default 'contacts'
    check (about_visibility in ('everyone', 'contacts', 'nobody'));

-- Valeurs par défaut quand aucun réglage n'est enregistré (même ordre que la table).
create or replace function private.privacy_of(p_user_id uuid)
returns private.privacy_settings
language sql
stable
security definer
set search_path = ''
as $$
  select s.* from private.privacy_settings s where s.user_id = p_user_id
  union all
  select p_user_id, 'contacts', true, true, 'everyone', 'everyone', null::integer, now(), 'contacts'
   where not exists (select 1 from private.privacy_settings s where s.user_id = p_user_id)
  limit 1;
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
         and private.visible_to((private.privacy_of(p_owner)).about_visibility, p_owner, p_viewer)
    then p_about end;
$$;

drop function if exists public.get_my_privacy();
create or replace function public.get_my_privacy()
returns table (
  presence_visibility text,
  read_receipts       boolean,
  typing_indicator    boolean,
  avatar_visibility   text,
  group_invites       text,
  default_ttl_seconds integer,
  about_visibility    text
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
                      s.avatar_visibility, s.group_invites, s.default_ttl_seconds, s.about_visibility;
end;
$$;

-- Écriture de tous les réglages ; p_about_visibility absent (anciennes versions) : inchangé.
drop function if exists public.set_my_privacy(text, boolean, boolean, text, text, integer);
create or replace function public.set_my_privacy(
  p_presence_visibility text,
  p_read_receipts       boolean,
  p_typing_indicator    boolean,
  p_avatar_visibility   text,
  p_group_invites       text,
  p_default_ttl_seconds integer default null,
  p_about_visibility    text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_active_user();
  v_ok    text[] := array['everyone', 'contacts', 'nobody'];
  v_about text := coalesce(p_about_visibility, (private.privacy_of(v_uid)).about_visibility);
begin
  if p_presence_visibility is null or not (p_presence_visibility = any (v_ok))
     or p_avatar_visibility is null or not (p_avatar_visibility = any (v_ok))
     or p_group_invites is null or not (p_group_invites = any (v_ok))
     or not (v_about = any (v_ok))
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
     group_invites, default_ttl_seconds, about_visibility, updated_at)
  values (v_uid, p_presence_visibility, p_read_receipts, p_typing_indicator, p_avatar_visibility,
          p_group_invites, p_default_ttl_seconds, v_about, now())
  on conflict (user_id) do update set
    presence_visibility = excluded.presence_visibility,
    read_receipts       = excluded.read_receipts,
    typing_indicator    = excluded.typing_indicator,
    avatar_visibility   = excluded.avatar_visibility,
    group_invites       = excluded.group_invites,
    default_ttl_seconds = excluded.default_ttl_seconds,
    about_visibility    = excluded.about_visibility,
    updated_at          = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. « À propos » : écriture (140 caractères, vide = retiré)
-- ---------------------------------------------------------------------------
create or replace function public.set_my_about(p_about text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_active_user();
  v_about text := nullif(btrim(regexp_replace(coalesce(p_about, ''), '\s+', ' ', 'g')), '');
begin
  if v_about is not null and char_length(v_about) > 140 then
    raise exception 'ABOUT_TOO_LONG' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(v_uid, 'profile_write',
    private.policy_int('profile_write_hourly_limit'), interval '1 hour');
  update public.profiles set about = v_about where id = v_uid;
  return v_about;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Fiche d'un contact (personne avec qui l'on partage une discussion)
-- ---------------------------------------------------------------------------
create or replace function public.get_contact_profile(p_user_id uuid)
returns table (
  user_id      uuid,
  handle       text,
  display_name text,
  about        text,
  avatar_path  text
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
  if p_user_id <> v_uid and not private.shares_conversation(v_uid, p_user_id) then
    return;
  end if;
  return query
  select p.id, p.handle, p.display_name,
         private.about_for(p.id, v_uid, p.about),
         private.avatar_for(p.id, v_uid, p.avatar_path)
    from public.profiles p
   where p.id = p_user_id and p.deleted_at is null;
end;
$$;

-- Groupes dont les deux comptes sont membres actifs.
create or replace function public.list_common_groups(p_user_id uuid)
returns table (
  conversation_id uuid,
  title           text,
  member_count    integer,
  avatar_path     text
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
  select c.id, c.title, private.active_member_count(c.id), c.avatar_path
    from public.conversations c
   where c.kind = 'group'
     and private.is_member(c.id, v_uid)
     and private.is_member(c.id, p_user_id)
     and p_user_id <> v_uid
   order by c.last_message_at desc nulls last, c.created_at desc
   limit 50;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Médias encore présents dans une discussion (photos et vocaux, 72 h au plus)
-- ---------------------------------------------------------------------------
create or replace function public.list_conversation_media(p_conversation_id uuid)
returns table (
  message_id        uuid,
  sender_id         uuid,
  kind              text,
  media_path        text,
  media_duration_ms integer,
  media_width       integer,
  media_height      integer,
  sent_at           timestamptz,
  expires_at        timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_member(p_conversation_id);
  v_since timestamptz := private.member_since(p_conversation_id, v_uid);
begin
  return query
  select m.id, m.sender_id, m.kind, m.media_path, m.media_duration_ms, m.media_width, m.media_height,
         m.sent_at, m.expires_at
    from public.messages m
   where m.conversation_id = p_conversation_id
     and m.kind in ('photo', 'voice')
     and m.media_path is not null
     and m.deleted_at is null
     and m.expires_at > now()
     and m.sent_at >= v_since
     and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
   order by m.sent_at desc
   limit 200;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();

grant execute on function public.get_my_privacy() to authenticated;
grant execute on function public.set_my_privacy(text, boolean, boolean, text, text, integer, text) to authenticated;
grant execute on function public.set_my_about(text) to authenticated;
grant execute on function public.get_contact_profile(uuid) to authenticated;
grant execute on function public.list_common_groups(uuid) to authenticated;
grant execute on function public.list_conversation_media(uuid) to authenticated;
