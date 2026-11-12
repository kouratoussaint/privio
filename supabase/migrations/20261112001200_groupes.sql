-- PRIVIO — Migration 12 (lot 3.3) : groupes (discussions à plusieurs, rien de plus)
-- Invariants :
--   * on n'entre dans un groupe QUE sur invitation ACCEPTÉE (personne n'est ajouté de force) ;
--     les blocages empêchent l'invitation ; invitations limitées et valables 7 jours ;
--   * rôles : un seul propriétaire, des administrateurs, des membres ; le propriétaire qui part
--     (ou supprime son compte) est remplacé automatiquement ;
--   * taille maximale administrable (group_max_members, 100 provisoire — décision B2) ;
--   * un membre ne voit que les messages envoyés depuis son arrivée (ni avant, ni après son
--     départ) : appliqué par la RLS, les RPC et la lecture des fichiers ;
--   * restrictions : publication réservée aux administrateurs, modification des informations
--     réservée aux administrateurs (par défaut) ;
--   * chaque événement (arrivée, départ, rôle, titre…) est annoncé par un message système, qui
--     expire comme les autres.

-- ---------------------------------------------------------------------------
-- Politiques
-- ---------------------------------------------------------------------------
update private.policy_definitions set implemented = true where key = 'group_max_members';

insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('group_create_daily_limit', 'integer', '10', 1, 100, null, false, true,
   'Groupes créés par compte et par jour (anti-abus).'),
  ('group_invite_hourly_limit', 'integer', '60', 5, 500, null, false, true,
   'Invitations envoyées par compte et par heure (anti-abus).'),
  ('group_invitation_ttl_days', 'integer', '7', 1, 30, null, true, true,
   'Durée de validité d''une invitation à un groupe (jours).');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
alter table public.conversations drop constraint if exists conversations_kind_check;
alter table public.conversations drop constraint if exists conversations_check;
alter table public.conversations
  add constraint conversations_kind_check check (kind in ('direct', 'group')),
  add column title        text check (title is null or char_length(btrim(title)) between 1 and 60),
  add column description  text check (description is null or char_length(description) <= 300),
  add column avatar_path  text,
  -- Qui peut écrire : tout le monde, ou seulement les administrateurs (GROUP-005).
  add column posting      text not null default 'all' check (posting in ('all', 'admins')),
  -- Qui peut modifier titre, description, photo et durée des messages.
  add column info_editing text not null default 'admins' check (info_editing in ('all', 'admins'));
alter table public.conversations add constraint conversations_shape check (
  case kind
    when 'direct' then direct_key is not null and title is null
    else direct_key is null and title is not null
  end
);
grant select on public.conversations to authenticated;

alter table public.conversation_members
  add column role        text not null default 'member' check (role in ('owner', 'admin', 'member')),
  add column muted_until timestamptz,
  add column added_by    uuid references auth.users (id) on delete set null;
create unique index conversation_members_one_owner
  on public.conversation_members (conversation_id) where role = 'owner' and left_at is null;

create table private.group_invitations (
  id              uuid        primary key default gen_random_uuid(),
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  invitee_id      uuid        not null references auth.users (id) on delete cascade,
  inviter_id      uuid        references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  status          text        not null default 'pending'
                    check (status in ('pending', 'accepted', 'declined', 'revoked'))
);
create unique index group_invitations_one_pending
  on private.group_invitations (conversation_id, invitee_id) where status = 'pending';
create index group_invitations_invitee_idx on private.group_invitations (invitee_id) where status = 'pending';
revoke all on private.group_invitations from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Fonctions d'appartenance
-- ---------------------------------------------------------------------------
-- Depuis quand un membre actif voit les messages (null s'il n'est pas membre) : son arrivée
-- dans un groupe ; tout l'historique d'une discussion 1:1 (présent depuis la création).
create or replace function private.member_since(p_conversation_id uuid, p_user_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select case when c.kind = 'group' then m.joined_at else '-infinity'::timestamptz end
    from public.conversation_members m
    join public.conversations c on c.id = m.conversation_id
   where m.conversation_id = p_conversation_id and m.user_id = p_user_id and m.left_at is null;
$$;

-- Un message est lisible par un membre actif arrivé avant son envoi.
create or replace function private.can_see_message(p_conversation_id uuid, p_sent_at timestamptz, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.member_since(p_conversation_id, p_user_id) <= p_sent_at, false);
$$;

create or replace function private.member_role(p_conversation_id uuid, p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role from public.conversation_members m
   where m.conversation_id = p_conversation_id and m.user_id = p_user_id and m.left_at is null;
$$;

create or replace function private.active_member_count(p_conversation_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int from public.conversation_members m
   where m.conversation_id = p_conversation_id and m.left_at is null;
$$;

-- Membre d'un GROUPE ayant l'un des rôles demandés ; renvoie son identifiant.
create or replace function private.require_group_role(p_conversation_id uuid, p_roles text[])
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_role text := private.member_role(p_conversation_id, v_uid);
begin
  if not exists (select 1 from public.conversations c where c.id = p_conversation_id and c.kind = 'group') then
    raise exception 'NOT_GROUP' using errcode = 'P0001';
  end if;
  if not (v_role = any (p_roles)) then
    raise exception 'NOT_ADMIN' using errcode = 'P0001';
  end if;
  return v_uid;
end;
$$;

-- Modifier les informations du groupe : selon le réglage info_editing.
create or replace function private.require_info_editor(p_conversation_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_mode text := (select c.info_editing from public.conversations c where c.id = p_conversation_id);
begin
  return private.require_group_role(p_conversation_id,
    case when v_mode = 'all' then array['owner', 'admin', 'member'] else array['owner', 'admin'] end);
end;
$$;

-- Peut-on écrire dans cette discussion ? (blocage en 1:1, restriction en groupe)
create or replace function private.check_can_post(p_conversation_id uuid, p_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_conv public.conversations%rowtype;
  v_peer uuid;
begin
  select * into v_conv from public.conversations c where c.id = p_conversation_id;
  if v_conv.kind = 'direct' then
    v_peer := private.direct_peer(p_conversation_id, p_user_id);
    if v_peer is not null and private.is_blocked_between(p_user_id, v_peer) then
      raise exception 'BLOCKED' using errcode = 'P0001';
    end if;
  elsif v_conv.posting = 'admins'
        and private.member_role(p_conversation_id, p_user_id) not in ('owner', 'admin') then
    raise exception 'POSTING_RESTRICTED' using errcode = 'P0001';
  end if;
end;
$$;

-- Signal temps réel vers UNE personne (ex. retirée d'un groupe : son app se met à jour).
create or replace function private.signal_user(p_user_id uuid, p_conversation_id uuid, p_event text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    return;
  end if;
  execute 'select realtime.send($1, $2, $3, true)'
    using jsonb_build_object('conversation_id', p_conversation_id), p_event, 'user:' || p_user_id::text;
end;
$$;

-- Message système d'un groupe : corps JSON {"e": événement, "a": acteur, "t": cible, "v": valeur}
-- (noms au moment de l'événement ; jamais de numéro de téléphone).
create or replace function private.group_event(
  p_conversation_id uuid, p_actor uuid, p_event text, p_target uuid default null, p_value text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ttl  integer := private.effective_ttl(p_conversation_id);
  v_body jsonb := jsonb_build_object('e', p_event);
  v_at   timestamptz := clock_timestamp();
begin
  if p_actor is not null then
    v_body := v_body || jsonb_build_object('a',
      coalesce((select p.display_name from public.profiles p where p.id = p_actor), 'Un membre'));
  end if;
  if p_target is not null then
    v_body := v_body || jsonb_build_object('t',
      coalesce((select p.display_name from public.profiles p where p.id = p_target), 'Un membre'));
  end if;
  if p_value is not null then
    v_body := v_body || jsonb_build_object('v', p_value);
  end if;
  -- Heure réelle (et non celle du début de transaction) : plusieurs événements d'une même
  -- action (départ puis nouveau propriétaire) gardent leur ordre.
  insert into public.messages (conversation_id, sender_id, client_msg_id, kind, body, sent_at, expires_at)
  values (p_conversation_id, p_actor, gen_random_uuid(), 'system', v_body::text, v_at,
          v_at + make_interval(secs => v_ttl));
  update public.conversations set last_message_at = v_at where id = p_conversation_id;
  perform private.signal_members(p_conversation_id, 'message');
end;
$$;

-- Toujours un propriétaire tant qu'il reste quelqu'un : le plus ancien administrateur,
-- sinon le plus ancien membre.
create or replace function private.ensure_group_owner(p_conversation_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_next uuid;
begin
  if not exists (select 1 from public.conversations c where c.id = p_conversation_id and c.kind = 'group')
     or exists (select 1 from public.conversation_members m
                 where m.conversation_id = p_conversation_id and m.role = 'owner' and m.left_at is null) then
    return;
  end if;
  select m.user_id into v_next from public.conversation_members m
   where m.conversation_id = p_conversation_id and m.left_at is null
   order by (m.role = 'admin') desc, m.joined_at, m.user_id
   limit 1;
  if v_next is null then
    return;
  end if;
  update public.conversation_members set role = 'owner'
   where conversation_id = p_conversation_id and user_id = v_next;
  perform private.group_event(p_conversation_id, null, 'owner_changed', v_next);
end;
$$;

create or replace function private.members_owner_release()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'owner' and old.left_at is null then
    perform private.ensure_group_owner(old.conversation_id);
  end if;
  return old;
end;
$$;

-- Compte supprimé : son appartenance disparaît (cascade) ; le groupe garde un propriétaire.
create trigger members_owner_release after delete on public.conversation_members
  for each row execute function private.members_owner_release();

-- ---------------------------------------------------------------------------
-- RLS : historique visible depuis l'arrivée seulement
-- ---------------------------------------------------------------------------
drop policy if exists messages_select_member_unexpired on public.messages;
create policy messages_select_member_unexpired on public.messages
  for select to authenticated
  using (
    expires_at > now()
    and (select private.session_is_active())
    and private.can_see_message(conversation_id, sent_at, (select auth.uid()))
  );

drop policy if exists reactions_select_member on public.message_reactions;
create policy reactions_select_member on public.message_reactions
  for select to authenticated
  using (
    (select private.session_is_active())
    and exists (select 1 from public.messages m
                 where m.id = message_id and m.expires_at > now()
                   and private.can_see_message(m.conversation_id, m.sent_at, (select auth.uid())))
  );

create or replace function private.visible_message(p_message_id uuid, p_user_id uuid)
returns public.messages
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.messages%rowtype;
begin
  select * into v from public.messages where id = p_message_id;
  if not found or not private.can_see_message(v.conversation_id, v.sent_at, p_user_id) then
    raise exception 'MESSAGE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v.expires_at <= now() then
    raise exception 'MESSAGE_EXPIRED' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

create or replace function private.can_read_voice(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and exists (
    select 1 from public.messages m
     where m.media_path = p_name and m.kind = 'voice' and m.deleted_at is null
       and m.expires_at > now()
       and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
  );
$$;

create or replace function private.can_read_photo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and exists (
    select 1 from public.messages m
     where m.media_path = p_name and m.kind = 'photo' and m.deleted_at is null
       and m.expires_at > now()
       and private.can_see_message(m.conversation_id, m.sent_at, auth.uid())
  );
$$;

-- Photo de profil d'une personne (non bloquée) OU photo d'un groupe dont on est membre.
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
         and (p.id = auth.uid() or not private.is_blocked_between(auth.uid(), p.id)))
    or exists (
      select 1 from public.conversations c
       where c.avatar_path = p_name and c.kind = 'group'
         and private.is_member(c.id, auth.uid()))
  );
$$;

-- Ancienne photo de groupe effacée au remplacement ou au retrait.
create or replace function private.conversations_avatar_release()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.avatar_path is not null and (tg_op = 'DELETE' or new.avatar_path is distinct from old.avatar_path) then
    perform private.mark_media_for_purge(old.avatar_path);
  end if;
  return coalesce(new, old);
end;
$$;
create trigger conversations_avatar_release after update of avatar_path or delete
  on public.conversations for each row execute function private.conversations_avatar_release();

-- Photos de groupe : rattachées à une discussion (registre des médias).
alter table private.media_objects drop constraint if exists media_objects_kind_shape;
alter table private.media_objects add constraint media_objects_kind_shape check (
  case bucket
    when 'avatars' then client_msg_id is null
    else (state = 'purge' or (conversation_id is not null and client_msg_id is not null))
  end
);

-- ---------------------------------------------------------------------------
-- Envoi : restriction de publication (texte, vocal, photo).
-- ---------------------------------------------------------------------------
create or replace function private.post_message(
  p_uid             uuid,
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_kind            text,
  p_body            text,
  p_reply_to_id     uuid,
  p_ttl_seconds     integer,
  p_media_path      text default null,
  p_duration_ms     integer default null,
  p_width           integer default null,
  p_height          integer default null
)
returns public.messages
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_body     text := case p_kind
                       when 'text'  then btrim(coalesce(p_body, ''))
                       when 'photo' then nullif(btrim(coalesce(p_body, '')), '')
                     end;
  v_existing public.messages%rowtype;
  v_reply    public.messages%rowtype;
  v_row      public.messages%rowtype;
  v_ttl      integer;
begin
  if p_client_msg_id is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;

  -- Idempotence : un renvoi (réseau instable) renvoie le message déjà créé.
  select * into v_existing from public.messages m
   where m.sender_id = p_uid and m.client_msg_id = p_client_msg_id;
  if found then
    if v_existing.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    return v_existing;
  end if;

  perform private.check_can_post(p_conversation_id, p_uid);
  if p_kind = 'text'
     and (char_length(v_body) = 0 or char_length(v_body) > private.policy_int('message_max_chars')) then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if p_kind = 'photo' and v_body is not null
     and char_length(v_body) > private.policy_int('photo_caption_max_chars') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if p_reply_to_id is not null then
    select * into v_reply from public.messages m where m.id = p_reply_to_id;
    if not found or v_reply.conversation_id <> p_conversation_id or v_reply.expires_at <= now()
       or v_reply.kind not in ('text', 'voice', 'photo')
       or not private.can_see_message(p_conversation_id, v_reply.sent_at, p_uid) then
      raise exception 'REPLY_NOT_FOUND' using errcode = 'P0001';
    end if;
  end if;

  perform private.consume_rate_limit(p_uid, 'message_send',
    private.policy_int('message_send_hourly_limit'), interval '1 hour');

  -- Durée : celle choisie pour ce message, jamais au-delà de celle de la discussion.
  v_ttl := private.effective_ttl(p_conversation_id);
  if p_ttl_seconds is not null then
    if p_ttl_seconds < private.policy_int('message_ttl_min_minutes') * 60 then
      raise exception 'TTL_INVALID' using errcode = 'P0001';
    end if;
    v_ttl := least(p_ttl_seconds, v_ttl);
  end if;

  begin
    insert into public.messages
      (conversation_id, sender_id, client_msg_id, kind, body, reply_to_id, sent_at, expires_at,
       media_path, media_duration_ms, media_width, media_height)
    values
      (p_conversation_id, p_uid, p_client_msg_id, p_kind, v_body, p_reply_to_id, now(),
       now() + make_interval(secs => v_ttl), p_media_path, p_duration_ms, p_width, p_height)
    returning * into v_row;
  exception when unique_violation then
    -- Même message envoyé deux fois au même instant : on renvoie le premier.
    select * into v_existing from public.messages m
     where m.sender_id = p_uid and m.client_msg_id = p_client_msg_id;
    return v_existing;
  end;

  update public.conversations set last_message_at = v_row.sent_at where id = p_conversation_id;
  -- L'expéditeur a forcément reçu et lu son propre message.
  update public.conversation_members
     set delivered_up_to = greatest(coalesce(delivered_up_to, v_row.sent_at), v_row.sent_at),
         read_up_to      = greatest(coalesce(read_up_to, v_row.sent_at), v_row.sent_at),
         archived_at     = null
   where conversation_id = p_conversation_id and user_id = p_uid;
  -- Un nouveau message désarchive la discussion chez les autres membres.
  update public.conversation_members set archived_at = null
   where conversation_id = p_conversation_id and user_id <> p_uid;

  perform private.signal_members(p_conversation_id, 'message');
  return v_row;
end;
$$;

-- Vocal et photo : la restriction s'applique dès la réservation (aucune photo débitée).
create or replace function public.prepare_voice_message(p_conversation_id uuid, p_client_msg_id uuid)
returns table (path text, state text, message_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_msg  public.messages%rowtype;
  v_row  private.media_objects%rowtype;
begin
  if p_client_msg_id is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  select * into v_msg from public.messages m
   where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
  if found then
    if v_msg.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    return query select null::text, 'sent'::text, v_msg.id;
    return;
  end if;
  perform private.check_can_post(p_conversation_id, v_uid);

  select * into v_row from private.media_objects o
   where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id;
  if not found then
    perform private.consume_rate_limit(v_uid, 'voice_upload',
      private.policy_int('voice_upload_hourly_limit'), interval '1 hour');
    insert into private.media_objects (path, owner_id, conversation_id, client_msg_id)
    values (p_conversation_id::text || '/' || gen_random_uuid()::text || '.m4a',
            v_uid, p_conversation_id, p_client_msg_id)
    on conflict (owner_id, client_msg_id) do nothing;
    select * into v_row from private.media_objects o
     where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id;
  end if;
  if v_row.conversation_id <> p_conversation_id then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query select v_row.path, v_row.state, null::uuid;
end;
$$;

create or replace function public.prepare_photo_message(p_conversation_id uuid, p_client_msg_id uuid)
returns table (path text, state text, message_id uuid, remaining integer)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_member(p_conversation_id);
  v_msg   public.messages%rowtype;
  v_row   private.media_objects%rowtype;
  v_path  text;
  v_day   date := private.quota_day();
  v_limit integer := private.policy_int('photo_daily_limit');
  v_used  integer;
begin
  if p_client_msg_id is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  select * into v_msg from public.messages m
   where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
  if found then
    if v_msg.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    return query select null::text, 'sent'::text, v_msg.id, null::integer;
    return;
  end if;
  perform private.check_can_post(p_conversation_id, v_uid);

  insert into private.media_objects (path, bucket, owner_id, conversation_id, client_msg_id, quota_day)
  values (p_conversation_id::text || '/' || gen_random_uuid()::text || '.jpg', 'photos',
          v_uid, p_conversation_id, p_client_msg_id, v_day)
  on conflict (owner_id, client_msg_id) do nothing
  returning private.media_objects.path into v_path;

  if v_path is not null then
    insert into private.photo_quota_daily as q (user_id, quota_day, used)
    values (v_uid, v_day, 1)
    on conflict (user_id, quota_day) do update
      set used = q.used + 1, updated_at = now()
      where q.used < v_limit
    returning q.used into v_used;
    if v_used is null or v_used > v_limit then
      raise exception 'PHOTO_QUOTA_REACHED' using errcode = 'P0001';
    end if;
  end if;

  select * into v_row from private.media_objects o
   where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id;
  if v_row.conversation_id is distinct from p_conversation_id or v_row.bucket <> 'photos' then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query
    select v_row.path, v_row.state, null::uuid,
           greatest(v_limit - coalesce((select q.used from private.photo_quota_daily q
                                         where q.user_id = v_uid and q.quota_day = v_day), 0), 0);
end;
$$;

-- Durée des messages : en groupe, selon le réglage info_editing.
create or replace function public.set_conversation_ttl(p_conversation_id uuid, p_ttl_seconds integer)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_max  integer := private.policy_int('message_ttl_hours') * 3600;
  v_min  integer := private.policy_int('message_ttl_min_minutes') * 60;
  v_peer uuid;
begin
  if p_ttl_seconds is null or p_ttl_seconds < v_min or p_ttl_seconds > v_max then
    raise exception 'TTL_INVALID' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.conversations c where c.id = p_conversation_id and c.kind = 'group') then
    perform private.require_info_editor(p_conversation_id);
  else
    v_peer := private.direct_peer(p_conversation_id, v_uid);
    if v_peer is not null and private.is_blocked_between(v_uid, v_peer) then
      raise exception 'BLOCKED' using errcode = 'P0001';
    end if;
  end if;
  if private.effective_ttl(p_conversation_id) = p_ttl_seconds then
    return p_ttl_seconds;
  end if;

  update public.conversations set ttl_seconds = p_ttl_seconds, last_message_at = now()
   where id = p_conversation_id;
  insert into public.messages (conversation_id, sender_id, client_msg_id, kind, body, sent_at, expires_at)
  values (p_conversation_id, v_uid, gen_random_uuid(), 'system', 'ttl:' || p_ttl_seconds, now(),
          now() + make_interval(secs => p_ttl_seconds));
  perform private.signal_members(p_conversation_id, 'message');
  return p_ttl_seconds;
end;
$$;

-- Suppression pour tous : l'expéditeur, ou un administrateur du groupe (modération).
create or replace function public.delete_message_for_everyone(p_message_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_active_user();
  v       public.messages%rowtype := private.visible_message(p_message_id, v_uid);
  v_admin boolean;
begin
  v_admin := v.kind <> 'system'
             and exists (select 1 from public.conversations c where c.id = v.conversation_id and c.kind = 'group')
             and private.member_role(v.conversation_id, v_uid) in ('owner', 'admin');
  if v.sender_id is distinct from v_uid and not v_admin then
    raise exception 'NOT_SENDER' using errcode = 'P0001';
  end if;
  if v.deleted_at is not null then
    return;
  end if;
  if v.sender_id = v_uid
     and now() > v.sent_at + make_interval(hours => private.policy_int('message_delete_for_all_hours')) then
    raise exception 'DELETE_WINDOW_EXPIRED' using errcode = 'P0001';
  end if;
  update public.messages set body = null, deleted_at = now(), edited_at = null, updated_at = now()
   where id = p_message_id;
  delete from public.message_reactions where message_id = p_message_id;
  perform private.signal_members(v.conversation_id, 'message_changed');
end;
$$;

-- ---------------------------------------------------------------------------
-- Groupes : création, invitations
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
  -- Une ancienne invitation échue ne bloque pas une nouvelle.
  update private.group_invitations set status = 'revoked'
   where conversation_id = p_conversation_id and invitee_id = p_invitee and status = 'pending';
  insert into private.group_invitations (conversation_id, invitee_id, inviter_id, expires_at)
  values (p_conversation_id, p_invitee, p_inviter,
          now() + make_interval(days => private.policy_int('group_invitation_ttl_days')));
  perform private.signal_user(p_invitee, p_conversation_id, 'invitation');
  return true;
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

  insert into public.conversations (kind, title, description, created_by, last_message_at)
  values ('group', v_title, v_desc, v_uid, now())
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

-- Inviter (administrateurs). Renvoie le nombre d'invitations envoyées (les personnes déjà
-- membres, déjà invitées ou bloquées sont ignorées sans le révéler).
create or replace function public.invite_to_group(p_conversation_id uuid, p_user_ids uuid[])
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_group_role(p_conversation_id, array['owner', 'admin']);
  v_other uuid;
  v_count integer := 0;
begin
  foreach v_other in array coalesce(p_user_ids, '{}') loop
    if private.invite(p_conversation_id, v_uid, v_other) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

create or replace function public.list_my_invitations()
returns table (
  invitation_id   uuid,
  conversation_id uuid,
  title           text,
  description     text,
  avatar_path     text,
  inviter_name    text,
  member_count    integer,
  created_at      timestamptz,
  expires_at      timestamptz
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
  select i.id, c.id, c.title, c.description, c.avatar_path, p.display_name,
         private.active_member_count(c.id), i.created_at, i.expires_at
    from private.group_invitations i
    join public.conversations c on c.id = i.conversation_id
    left join public.profiles p on p.id = i.inviter_id and p.deleted_at is null
   where i.invitee_id = v_uid and i.status = 'pending' and i.expires_at > now()
     and not private.is_member(c.id, v_uid)
     and (i.inviter_id is null or not private.is_blocked_between(v_uid, i.inviter_id))
   order by i.created_at desc;
end;
$$;

-- Accepter (le groupe s'ouvre) ou refuser une invitation.
create or replace function public.respond_to_invitation(p_invitation_id uuid, p_accept boolean)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v     private.group_invitations%rowtype;
begin
  select * into v from private.group_invitations i
   where i.id = p_invitation_id and i.invitee_id = v_uid
   for update;
  if not found or v.status <> 'pending' or v.expires_at <= now() then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'P0001';
  end if;
  if not coalesce(p_accept, false) then
    update private.group_invitations set status = 'declined' where id = v.id;
    return null;
  end if;
  -- Verrou sur le groupe : deux acceptations simultanées ne dépassent pas la limite.
  perform 1 from public.conversations c where c.id = v.conversation_id for update;
  if private.active_member_count(v.conversation_id) >= private.policy_int('group_max_members') then
    raise exception 'GROUP_FULL' using errcode = 'P0001';
  end if;
  update private.group_invitations set status = 'accepted' where id = v.id;
  insert into public.conversation_members (conversation_id, user_id, role, added_by, joined_at)
  values (v.conversation_id, v_uid, 'member', v.inviter_id, now())
  on conflict (conversation_id, user_id) do update
    set left_at = null, joined_at = now(), role = 'member', added_by = excluded.added_by,
        delivered_up_to = null, read_up_to = null, pinned_at = null, archived_at = null,
        muted_until = null;
  perform private.group_event(v.conversation_id, v_uid, 'joined');
  return v.conversation_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Groupes : membres, rôles, départ
-- ---------------------------------------------------------------------------
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
         case when p.deleted_at is null and (m.user_id = v_uid or not private.is_blocked_between(v_uid, m.user_id))
              then p.avatar_path end,
         m.role, m.joined_at, false
    from public.conversation_members m
    left join public.profiles p on p.id = m.user_id
   where m.conversation_id = p_conversation_id and m.left_at is null
  union all
  -- Invitations en attente : visibles des seuls administrateurs.
  select i.invitee_id, p.handle, p.display_name, null::text, 'invited'::text, i.created_at, true
    from private.group_invitations i
    join public.profiles p on p.id = i.invitee_id and p.deleted_at is null
   where v_role in ('owner', 'admin') and i.conversation_id = p_conversation_id
     and i.status = 'pending' and i.expires_at > now()
  ) x (user_id, handle, display_name, avatar_path, role, joined_at, invited)
  -- Propriétaire, administrateurs, membres, puis invitations ; par nom.
  order by x.invited, case x.role when 'owner' then 0 when 'admin' then 1 when 'member' then 2 else 3 end,
           x.display_name;
end;
$$;

-- Nommer ou retirer un administrateur : nommer (propriétaire, administrateurs) ;
-- retirer le rôle (propriétaire uniquement).
create or replace function public.set_member_role(p_conversation_id uuid, p_user_id uuid, p_role text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := private.require_group_role(p_conversation_id, array['owner', 'admin']);
  v_current text := private.member_role(p_conversation_id, p_user_id);
begin
  if p_role not in ('admin', 'member') or v_current is null or v_current = 'owner' then
    raise exception 'ROLE_INVALID' using errcode = 'P0001';
  end if;
  if v_current = p_role then
    return;
  end if;
  if p_role = 'member' and private.member_role(p_conversation_id, v_uid) <> 'owner' then
    raise exception 'NOT_OWNER' using errcode = 'P0001';
  end if;
  update public.conversation_members set role = p_role
   where conversation_id = p_conversation_id and user_id = p_user_id;
  perform private.group_event(p_conversation_id, v_uid,
    case p_role when 'admin' then 'admin_added' else 'admin_removed' end, p_user_id);
end;
$$;

create or replace function public.transfer_group_ownership(p_conversation_id uuid, p_user_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_group_role(p_conversation_id, array['owner']);
begin
  if p_user_id = v_uid or private.member_role(p_conversation_id, p_user_id) is null then
    raise exception 'ROLE_INVALID' using errcode = 'P0001';
  end if;
  update public.conversation_members set role = 'admin'
   where conversation_id = p_conversation_id and user_id = v_uid;
  update public.conversation_members set role = 'owner'
   where conversation_id = p_conversation_id and user_id = p_user_id;
  perform private.group_event(p_conversation_id, v_uid, 'owner_changed', p_user_id);
end;
$$;

-- Retirer un membre : administrateurs ; un administrateur ne peut être retiré que par le
-- propriétaire ; le propriétaire ne peut pas être retiré.
create or replace function public.remove_group_member(p_conversation_id uuid, p_user_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_group_role(p_conversation_id, array['owner', 'admin']);
  v_target text := private.member_role(p_conversation_id, p_user_id);
begin
  if v_target is null or p_user_id = v_uid or v_target = 'owner' then
    raise exception 'ROLE_INVALID' using errcode = 'P0001';
  end if;
  if v_target = 'admin' and private.member_role(p_conversation_id, v_uid) <> 'owner' then
    raise exception 'NOT_OWNER' using errcode = 'P0001';
  end if;
  perform private.group_event(p_conversation_id, v_uid, 'removed', p_user_id);
  update public.conversation_members set left_at = now(), role = 'member'
   where conversation_id = p_conversation_id and user_id = p_user_id;
  perform private.signal_user(p_user_id, p_conversation_id, 'removed');
end;
$$;

-- Quitter un groupe (GROUP-008). Le propriétaire est remplacé automatiquement.
create or replace function public.leave_group(p_conversation_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_group_role(p_conversation_id, array['owner', 'admin', 'member']);
begin
  perform private.group_event(p_conversation_id, v_uid, 'left');
  update public.conversation_members set left_at = now(), role = 'member'
   where conversation_id = p_conversation_id and user_id = v_uid;
  perform private.ensure_group_owner(p_conversation_id);
  perform private.signal_user(v_uid, p_conversation_id, 'removed');
end;
$$;

-- ---------------------------------------------------------------------------
-- Groupes : informations et réglages
-- ---------------------------------------------------------------------------
create or replace function public.update_group_info(
  p_conversation_id uuid, p_title text default null, p_description text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_info_editor(p_conversation_id);
  v_conv  public.conversations%rowtype;
  v_title text := nullif(btrim(coalesce(p_title, '')), '');
  v_desc  text := btrim(coalesce(p_description, ''));
begin
  select * into v_conv from public.conversations where id = p_conversation_id for update;
  if v_title is not null and v_title is distinct from v_conv.title then
    if char_length(v_title) > 60 then
      raise exception 'GROUP_TITLE_INVALID' using errcode = 'P0001';
    end if;
    update public.conversations set title = v_title where id = p_conversation_id;
    perform private.group_event(p_conversation_id, v_uid, 'title', null, v_title);
  end if;
  if p_description is not null and nullif(v_desc, '') is distinct from v_conv.description then
    if char_length(v_desc) > 300 then
      raise exception 'GROUP_DESCRIPTION_INVALID' using errcode = 'P0001';
    end if;
    update public.conversations set description = nullif(v_desc, '') where id = p_conversation_id;
    perform private.group_event(p_conversation_id, v_uid, 'description');
  end if;
end;
$$;

-- Restrictions (GROUP-005) : propriétaire et administrateurs.
create or replace function public.set_group_settings(
  p_conversation_id uuid, p_posting text default null, p_info_editing text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_group_role(p_conversation_id, array['owner', 'admin']);
  v_conv public.conversations%rowtype;
begin
  if (p_posting is not null and p_posting not in ('all', 'admins'))
     or (p_info_editing is not null and p_info_editing not in ('all', 'admins')) then
    raise exception 'SETTING_INVALID' using errcode = 'P0001';
  end if;
  select * into v_conv from public.conversations where id = p_conversation_id for update;
  if p_posting is not null and p_posting <> v_conv.posting then
    update public.conversations set posting = p_posting where id = p_conversation_id;
    perform private.group_event(p_conversation_id, v_uid, 'posting', null, p_posting);
  end if;
  if p_info_editing is not null and p_info_editing <> v_conv.info_editing then
    update public.conversations set info_editing = p_info_editing where id = p_conversation_id;
    perform private.group_event(p_conversation_id, v_uid, 'info_editing', null, p_info_editing);
  end if;
end;
$$;

-- Sourdine (groupes et discussions 1:1) : jusqu'à une date, ou null pour la lever.
-- Utilisée par les notifications (lot 4.1).
create or replace function public.set_conversation_mute(p_conversation_id uuid, p_until timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_member(p_conversation_id);
begin
  update public.conversation_members
     set muted_until = case when p_until is null or p_until <= now() then null else p_until end
   where conversation_id = p_conversation_id and user_id = v_uid;
end;
$$;

-- Photo de groupe : réservation (selon info_editing), puis validation par avatar-set.
create or replace function public.prepare_group_avatar_upload(p_conversation_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_info_editor(p_conversation_id);
  v_path text := 'groups/' || p_conversation_id::text || '/' || gen_random_uuid()::text || '.jpg';
begin
  perform private.consume_rate_limit(v_uid, 'avatar_upload',
    private.policy_int('avatar_upload_daily_limit'), interval '1 day');
  insert into private.media_objects (path, bucket, owner_id, conversation_id)
  values (v_path, 'avatars', v_uid, p_conversation_id);
  return v_path;
end;
$$;

-- SERVICE : la photo vérifiée devient celle du groupe.
create or replace function public.commit_group_avatar(
  p_path text, p_width integer, p_height integer, p_bytes integer
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v private.media_objects%rowtype;
begin
  perform private.require_service();
  if p_width is null or p_height is null or p_width < 1 or p_height < 1
     or greatest(p_width, p_height) > 1024 then
    raise exception 'MEDIA_INVALID' using errcode = 'P0001';
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > private.policy_int('avatar_max_bytes') then
    raise exception 'MEDIA_TOO_LARGE' using errcode = 'P0001';
  end if;
  select * into v from private.media_objects
   where path = p_path and bucket = 'avatars' and state = 'reserved'
     and conversation_id is not null and owner_id is not null
   for update;
  if not found then
    raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
  end if;
  update private.media_objects
     set state = 'attached', width = p_width, height = p_height, bytes = p_bytes
   where path = p_path;
  update public.conversations set avatar_path = p_path where id = v.conversation_id;
  perform private.group_event(v.conversation_id, v.owner_id, 'photo');
end;
$$;

-- Personnel : la photo de profil n'est jamais rattachée à une discussion.
create or replace function public.commit_avatar(
  p_path text, p_width integer, p_height integer, p_bytes integer
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v private.media_objects%rowtype;
begin
  perform private.require_service();
  if p_width is null or p_height is null or p_width < 1 or p_height < 1
     or greatest(p_width, p_height) > 1024 then
    raise exception 'MEDIA_INVALID' using errcode = 'P0001';
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > private.policy_int('avatar_max_bytes') then
    raise exception 'MEDIA_TOO_LARGE' using errcode = 'P0001';
  end if;
  select * into v from private.media_objects
   where path = p_path and bucket = 'avatars' and state = 'reserved'
     and conversation_id is null and owner_id is not null
   for update;
  if not found then
    raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0001';
  end if;
  update private.media_objects
     set state = 'attached', width = p_width, height = p_height, bytes = p_bytes
   where path = p_path;
  update public.profiles set avatar_path = p_path where id = v.owner_id and deleted_at is null;
end;
$$;

create or replace function public.remove_group_avatar(p_conversation_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_info_editor(p_conversation_id);
begin
  update public.conversations set avatar_path = null
   where id = p_conversation_id and avatar_path is not null;
  if found then
    perform private.group_event(p_conversation_id, v_uid, 'photo_removed');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Liste des discussions : + groupes (titre, photo, membres, rôle, réglages, sourdine).
-- Accusés en groupe : « reçu » / « lu » quand TOUS les autres membres l'ont reçu / lu.
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
  info_editing         text
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
           c.avatar_path, c.posting, c.info_editing,
           me.joined_at, me.read_up_to, me.pinned_at, me.archived_at, me.muted_until, me.role
      from public.conversation_members me
      join public.conversations c on c.id = me.conversation_id
     where me.user_id = v_uid and me.left_at is null
  ),
  visible as (
    select m.* from public.messages m
      join mine on mine.id = m.conversation_id
     where m.expires_at > now() and (mine.kind = 'direct' or m.sent_at >= mine.joined_at)
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
    select o.conversation_id,
           count(*)::int as n,
           case when bool_or(o.delivered_up_to is null) then null else min(o.delivered_up_to) end as delivered,
           case when bool_or(o.read_up_to is null) then null else min(o.read_up_to) end as read
      from public.conversation_members o
      join mine on mine.id = o.conversation_id
     where o.user_id <> v_uid and o.left_at is null
     group by o.conversation_id
  ),
  direct_peer as (
    select peer.conversation_id, peer.user_id, peer.delivered_up_to, peer.read_up_to
      from public.conversation_members peer
      join mine on mine.id = peer.conversation_id and mine.kind = 'direct'
     where peer.user_id <> v_uid
  )
  select mine.id, mine.kind,
         dp.user_id, p.handle, p.display_name,
         case when mine.kind = 'direct' and p.deleted_at is null
                   and not coalesce(private.is_blocked_between(v_uid, dp.user_id), false)
              then p.avatar_path end,
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
         mine.posting, mine.info_editing
    from mine
    left join direct_peer dp on dp.conversation_id = mine.id
    left join public.profiles p on p.id = dp.user_id
    left join last_msg lm on lm.conversation_id = mine.id
    left join unread u on u.conversation_id = mine.id
    left join others o on o.conversation_id = mine.id
   -- Une discussion 1:1 vide n'apparaît que chez la personne qui l'a créée ; un groupe
   -- apparaît toujours chez ses membres.
   where lm.id is not null or mine.created_by = v_uid or mine.kind = 'group'
   order by (mine.pinned_at is not null) desc, coalesce(lm.sent_at, mine.created_at) desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Messages : + nom de l'expéditeur (groupes), historique depuis l'arrivée.
-- ---------------------------------------------------------------------------
drop function if exists public.get_messages(uuid, timestamptz, timestamptz, integer);

create or replace function public.get_messages(
  p_conversation_id uuid,
  p_since           timestamptz default null,
  p_before          timestamptz default null,
  p_limit           integer default 50
)
returns table (
  id                uuid,
  sender_id         uuid,
  sender_name       text,
  kind              text,
  body              text,
  reply_to_id       uuid,
  reply_preview     text,
  reply_kind        text,
  sent_at           timestamptz,
  expires_at        timestamptz,
  edited_at         timestamptz,
  deleted_at        timestamptz,
  updated_at        timestamptz,
  reactions         jsonb,
  media_path        text,
  media_duration_ms integer,
  media_width       integer,
  media_height      integer
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
  v_limit int  := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  return query
  select m.id, m.sender_id, sp.display_name, m.kind, m.body, m.reply_to_id,
         case when r.id is not null and r.expires_at > now() and r.deleted_at is null
                   and r.sent_at >= v_since
              then left(r.body, 120) end,
         case when r.id is not null and r.expires_at > now() and r.deleted_at is null
                   and r.sent_at >= v_since
              then r.kind end,
         m.sent_at, m.expires_at, m.edited_at, m.deleted_at, m.updated_at,
         coalesce((select jsonb_agg(jsonb_build_object('user_id', x.user_id, 'emoji', x.emoji)
                                    order by x.created_at)
                     from public.message_reactions x where x.message_id = m.id), '[]'::jsonb),
         m.media_path, m.media_duration_ms, m.media_width, m.media_height
    from public.messages m
    left join public.messages r on r.id = m.reply_to_id
    left join public.profiles sp on sp.id = m.sender_id and sp.deleted_at is null
   where m.conversation_id = p_conversation_id
     and m.expires_at > now()
     and m.sent_at >= v_since
     and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
     and (p_since is null or m.updated_at > p_since)
     and (p_before is null or m.sent_at < p_before)
   order by
     case when p_since is not null then m.updated_at end asc,
     case when p_since is null then m.sent_at end desc
   limit v_limit;
end;
$$;

-- ---------------------------------------------------------------------------
-- Signalement : + un groupe entier (motif, sans personne visée).
-- ---------------------------------------------------------------------------
alter table private.reports drop constraint if exists reports_check;
-- (Une personne visée peut disparaître ensuite : compte supprimé, référence effacée.)
alter table private.reports add constraint reports_target_check check (
  reason <> 'support' or (reported_user_id is null and message_id is null)
);

create or replace function public.report(
  p_reason           text,
  p_reported_user_id uuid default null,
  p_conversation_id  uuid default null,
  p_message_id       uuid default null,
  p_details          text default null,
  p_include_message  boolean default false
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := private.require_active_user();
  v_msg      public.messages%rowtype;
  v_evidence jsonb;
  v_id       uuid;
  v_details  text := nullif(btrim(coalesce(p_details, '')), '');
  v_purge    timestamptz := now() + make_interval(days => private.policy_int('report_retention_days'));
begin
  perform private.consume_rate_limit(v_uid, 'report',
    private.policy_int('report_daily_limit'), interval '1 day');

  if p_reason is null or p_reason not in
     ('spam', 'harassment', 'inappropriate', 'threat', 'impersonation', 'other', 'support') then
    raise exception 'REPORT_INVALID' using errcode = 'P0001';
  end if;
  if v_details is not null and char_length(v_details) > 1000 then
    raise exception 'REPORT_INVALID' using errcode = 'P0001';
  end if;

  if p_reason = 'support' then
    if p_reported_user_id is not null or p_message_id is not null or v_details is null then
      raise exception 'REPORT_INVALID' using errcode = 'P0001';
    end if;
  elsif p_reported_user_id is null then
    -- Signaler un groupe : en être membre ; ni message ni personne visée.
    if p_conversation_id is null or p_message_id is not null
       or not exists (select 1 from public.conversations c where c.id = p_conversation_id and c.kind = 'group')
       or not private.is_member(p_conversation_id, v_uid) then
      raise exception 'REPORT_INVALID' using errcode = 'P0001';
    end if;
  else
    if p_reported_user_id = v_uid then
      raise exception 'REPORT_INVALID' using errcode = 'P0001';
    end if;
    if p_conversation_id is not null and not private.is_member(p_conversation_id, v_uid) then
      raise exception 'NOT_MEMBER' using errcode = 'P0001';
    end if;
    if p_message_id is not null then
      v_msg := private.visible_message(p_message_id, v_uid);
      if v_msg.kind not in ('text', 'voice', 'photo') or v_msg.sender_id is distinct from p_reported_user_id
         or v_msg.conversation_id is distinct from p_conversation_id then
        raise exception 'REPORT_INVALID' using errcode = 'P0001';
      end if;
      select r.id into v_id from private.reports r
       where r.reporter_id = v_uid and r.message_id = p_message_id;
      if v_id is not null then
        return v_id;
      end if;
      if coalesce(p_include_message, false) and v_msg.deleted_at is null then
        v_evidence := jsonb_build_object(
          'kind', v_msg.kind, 'body', v_msg.body, 'sent_at', v_msg.sent_at,
          'sender_id', v_msg.sender_id, 'conversation_id', v_msg.conversation_id,
          'copied_at', now());
        if v_msg.media_path is not null then
          v_evidence := v_evidence || jsonb_build_object(
            'media_path', v_msg.media_path, 'duration_ms', v_msg.media_duration_ms);
          update private.media_objects
             set report_hold_until = greatest(coalesce(report_hold_until, v_purge), v_purge)
           where path = v_msg.media_path;
        end if;
      end if;
    end if;
  end if;

  insert into private.reports
    (reporter_id, reported_user_id, conversation_id, message_id, reason, details, evidence, purge_after)
  values
    (v_uid, p_reported_user_id, p_conversation_id, p_message_id, p_reason, v_details, v_evidence, v_purge)
  returning id into v_id;
  return v_id;
end;
$$;

-- Purge : + invitations échues depuis plus de 30 jours.
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
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits. harden_privileges() : + private.can_see_message (RLS des messages).
-- ---------------------------------------------------------------------------
create or replace function private.harden_privileges()
returns void
language plpgsql
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig, n.nspname
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private')
       and not exists (select 1 from pg_catalog.pg_depend d
                        where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    if r.nspname = 'private' then
      execute format('revoke all on function %s from authenticated', r.sig);
    end if;
  end loop;
  grant execute on function private.session_is_active() to authenticated;
  grant execute on function private.is_member(uuid, uuid) to authenticated;
  grant execute on function private.shares_conversation(uuid, uuid) to authenticated;
  grant execute on function private.can_see_message(uuid, timestamptz, uuid) to authenticated;
  grant execute on function private.can_read_voice(text) to authenticated;
  grant execute on function private.can_read_photo(text) to authenticated;
  grant execute on function private.can_read_avatar(text) to authenticated;
  execute 'revoke all on all tables in schema private from public, anon, authenticated';
end;
$$;

select private.harden_privileges();

-- Les colonnes de conversations sont lisibles par les membres (titre, description, photo,
-- réglages) ; aucune écriture directe.
revoke all on public.conversations from authenticated;
grant select on public.conversations to authenticated;

grant execute on function public.create_group(text, text, uuid[]) to authenticated;
grant execute on function public.invite_to_group(uuid, uuid[]) to authenticated;
grant execute on function public.list_my_invitations() to authenticated;
grant execute on function public.respond_to_invitation(uuid, boolean) to authenticated;
grant execute on function public.get_conversation_members(uuid) to authenticated;
grant execute on function public.set_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.transfer_group_ownership(uuid, uuid) to authenticated;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;
grant execute on function public.update_group_info(uuid, text, text) to authenticated;
grant execute on function public.set_group_settings(uuid, text, text) to authenticated;
grant execute on function public.set_conversation_mute(uuid, timestamptz) to authenticated;
grant execute on function public.prepare_group_avatar_upload(uuid) to authenticated;
grant execute on function public.remove_group_avatar(uuid) to authenticated;
grant execute on function public.list_conversations() to authenticated;
grant execute on function public.get_messages(uuid, timestamptz, timestamptz, integer) to authenticated;
grant execute on function public.prepare_voice_message(uuid, uuid) to authenticated;
grant execute on function public.prepare_photo_message(uuid, uuid) to authenticated;
grant execute on function public.set_conversation_ttl(uuid, integer) to authenticated;
grant execute on function public.delete_message_for_everyone(uuid) to authenticated;
grant execute on function public.report(text, uuid, uuid, uuid, text, boolean) to authenticated;

revoke all on function public.commit_group_avatar(text, integer, integer, integer) from authenticated;
grant execute on function public.commit_group_avatar(text, integer, integer, integer) to service_role;
