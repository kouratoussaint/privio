-- Lot 10.5 : groupes « Annonces » et sondages éphémères (décisions du 17/11/2026, ADR-049).
--   Annonces : un vrai type de groupe, choisi à la création et définitif ; seuls les
--   administrateurs écrivent ; les membres réagissent et votent ; un membre ne voit ni la
--   liste ni les arrivées et départs des autres membres, ni qui a réagi ; plafond propre
--   (`announcement_max_members`, 500, réglable dans la console).
--   Sondages : dans les groupes, par toute personne qui peut y écrire ; 2 à 10 choix, une ou
--   plusieurs réponses ; vote anonyme (par défaut : totaux seulement) ou votes visibles ;
--   vote modifiable tant que le sondage est ouvert ; fermeture par le créateur ; effacé avec
--   le message (72 h au plus), jamais par « Effacer après lecture ».

-- ---------------------------------------------------------------------------
-- 1. Groupes « Annonces »
-- ---------------------------------------------------------------------------
alter table public.conversations
  add column if not exists announcement boolean not null default false;

-- Le type ne change jamais, et un groupe « Annonces » reste réservé aux administrateurs.
create or replace function private.conversations_announcement_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.announcement is distinct from old.announcement
     or (new.announcement and new.posting = 'all') then
    raise exception 'ANNOUNCEMENT_LOCKED' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists conversations_announcement_guard on public.conversations;
create trigger conversations_announcement_guard before update on public.conversations
  for each row execute function private.conversations_announcement_guard();

insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, client_visible, implemented,
   description_fr, category, label_fr, unit, sort_order, effect_fr)
values
  ('announcement_max_members', 'integer', '500', 2, 1000, true, true,
   'Nombre maximal de membres d''un groupe « Annonces » (lot 10.5).', 'groups',
   'Membres au plus par groupe « Annonces »', 'nb', 11,
   'Les groupes déjà plus grands gardent leurs membres ; seules les nouvelles arrivées sont bloquées.')
on conflict (key) do nothing;

-- Plafond de membres d'un groupe selon son type.
create or replace function private.group_member_cap(p_conversation_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case when coalesce((select c.announcement from public.conversations c
                              where c.id = p_conversation_id), false)
              then private.policy_int('announcement_max_members')
              else private.policy_int('group_max_members') end;
$$;

-- Vrai si [p_uid] est un simple membre d'un groupe « Annonces » (liste des membres cachée).
create or replace function private.hides_members(p_conversation_id uuid, p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select c.announcement from public.conversations c
                    where c.id = p_conversation_id), false)
     and coalesce(private.member_role(p_conversation_id, p_uid), 'member') not in ('owner', 'admin');
$$;

-- Arrivée, départ ou retrait d'un autre membre, caché à un simple membre d'un groupe
-- « Annonces » (ses propres arrivée et départ restent visibles).
create or replace function private.hidden_member_event(
  p_conversation_id uuid, p_sender uuid, p_body text, p_uid uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_event text;
begin
  if not private.hides_members(p_conversation_id, p_uid) then
    return false;
  end if;
  begin
    v_event := (p_body::jsonb) ->> 'e';
  exception when others then
    return false;
  end;
  return v_event = 'removed'
      or (v_event in ('joined', 'left') and p_sender is distinct from p_uid);
end;
$$;

-- Créer un groupe, ou un groupe « Annonces » ([p_announcement]).
drop function if exists public.create_group(text, text, uuid[]);
create or replace function public.create_group(
  p_title text, p_description text default null, p_invitee_ids uuid[] default '{}',
  p_announcement boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_active_user();
  v_title text := btrim(coalesce(p_title, ''));
  v_desc  text := nullif(btrim(coalesce(p_description, '')), '');
  v_ann   boolean := coalesce(p_announcement, false);
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

  insert into public.conversations
    (kind, title, description, created_by, last_message_at, ttl_seconds, announcement, posting)
  values ('group', v_title, v_desc, v_uid, now(), private.default_ttl_for(v_uid), v_ann,
          case when v_ann then 'admins' else 'all' end)
  returning id into v_id;
  insert into public.conversation_members (conversation_id, user_id, role, added_by)
  values (v_id, v_uid, 'owner', v_uid);
  perform private.group_event(v_id, v_uid, 'created', null, v_title);
  foreach v_other in array coalesce(p_invitee_ids, '{}') loop
    perform private.invite(v_id, v_uid, v_other);
  end loop;
  if v_ann then
    perform private.bump_stat('groups_announcement');
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Sondages
-- ---------------------------------------------------------------------------
alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check
  check (kind in ('text', 'system', 'voice', 'photo', 'sticker', 'gif', 'poll'));

-- La question est le corps du message ; les choix et les votes sont ici.
create table if not exists private.polls (
  message_id uuid        primary key references public.messages (id) on delete cascade,
  options    text[]      not null check (array_length(options, 1) between 2 and 10),
  multi      boolean     not null default false,
  anonymous  boolean     not null default true,
  closed_at  timestamptz
);

create table if not exists private.poll_votes (
  message_id uuid        not null references private.polls (message_id) on delete cascade,
  user_id    uuid        not null references auth.users (id) on delete cascade,
  option     smallint    not null check (option between 0 and 9),
  voted_at   timestamptz not null default now(),
  primary key (message_id, user_id, option)
);
create index if not exists poll_votes_user_idx on private.poll_votes (user_id);

alter table private.polls enable row level security;
alter table private.poll_votes enable row level security;

-- Un sondage ne se modifie pas ; supprimé pour tous, ses votes partent aussi.
create or replace function private.messages_poll_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.kind = 'poll' then
    if new.deleted_at is null and new.body is distinct from old.body then
      raise exception 'MESSAGE_NOT_EDITABLE' using errcode = 'P0001';
    end if;
    if new.deleted_at is not null and old.deleted_at is null then
      delete from private.polls where message_id = old.id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists messages_poll_guard on public.messages;
create trigger messages_poll_guard before update on public.messages
  for each row execute function private.messages_poll_guard();

-- État d'un sondage pour [p_uid] : choix, totaux, mes votes ; votants seulement pour un
-- vote visible (jamais pour un vote anonyme, même pour son créateur).
create or replace function private.poll_state(p_message_id uuid, p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'options', to_jsonb(p.options),
    'multi', p.multi,
    'anonymous', p.anonymous,
    'closed_at', p.closed_at,
    'counts', (select jsonb_agg((select count(*) from private.poll_votes v
                                  where v.message_id = p.message_id and v.option = i - 1)
                                order by i)
                 from generate_subscripts(p.options, 1) i),
    'voters', (select count(distinct v.user_id) from private.poll_votes v
                where v.message_id = p.message_id),
    'mine', coalesce((select jsonb_agg(v.option order by v.option) from private.poll_votes v
                       where v.message_id = p.message_id and v.user_id = p_uid), '[]'::jsonb),
    -- Dans un groupe « Annonces », seuls les administrateurs voient les votants.
    'by_option', case when not p.anonymous
                       and not private.hides_members(m.conversation_id, p_uid) then
       (select jsonb_agg(coalesce((select jsonb_agg(v.user_id order by v.voted_at)
                                     from private.poll_votes v
                                    where v.message_id = p.message_id and v.option = i - 1),
                                  '[]'::jsonb) order by i)
          from generate_subscripts(p.options, 1) i) end)
    from private.polls p
    join public.messages m on m.id = p.message_id
   where p.message_id = p_message_id;
$$;

-- Envoyer un sondage dans un groupe (toute personne qui peut y écrire).
create or replace function public.send_poll(
  p_conversation_id uuid, p_client_msg_id uuid, p_question text, p_options text[],
  p_multi boolean default false, p_anonymous boolean default true, p_ttl_seconds integer default null
)
returns table (id uuid, sent_at timestamptz, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid      uuid := private.require_member(p_conversation_id);
  v_question text := btrim(regexp_replace(coalesce(p_question, ''), '\s+', ' ', 'g'));
  v_options  text[] := '{}';
  v_opt      text;
  v_existing public.messages%rowtype;
  v_row      public.messages%rowtype;
  v_ttl      integer;
begin
  if p_client_msg_id is null then
    raise exception 'POLL_INVALID' using errcode = 'P0001';
  end if;
  select * into v_existing from public.messages m
   where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
  if found then
    if v_existing.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    return query select v_existing.id, v_existing.sent_at, v_existing.expires_at;
    return;
  end if;
  if (select c.kind from public.conversations c where c.id = p_conversation_id) <> 'group' then
    raise exception 'POLL_GROUP_ONLY' using errcode = 'P0001';
  end if;
  perform private.check_can_post(p_conversation_id, v_uid);
  foreach v_opt in array coalesce(p_options, '{}') loop
    v_opt := btrim(regexp_replace(coalesce(v_opt, ''), '\s+', ' ', 'g'));
    if v_opt <> '' then
      v_options := v_options || v_opt;
    end if;
  end loop;
  if char_length(v_question) not between 1 and 200
     or cardinality(v_options) not between 2 and 10
     or exists (select 1 from unnest(v_options) o where char_length(o) > 80)
     or (select count(distinct lower(o)) from unnest(v_options) o) <> cardinality(v_options) then
    raise exception 'POLL_INVALID' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(v_uid, 'message_send',
    private.policy_int('message_send_hourly_limit'), interval '1 hour');

  v_ttl := private.effective_ttl(p_conversation_id);
  if p_ttl_seconds is not null then
    if p_ttl_seconds < private.policy_int('message_ttl_min_minutes') * 60 then
      raise exception 'TTL_INVALID' using errcode = 'P0001';
    end if;
    v_ttl := least(p_ttl_seconds, v_ttl);
  end if;

  insert into public.messages
    (conversation_id, sender_id, client_msg_id, kind, body, sent_at, expires_at)
  values (p_conversation_id, v_uid, p_client_msg_id, 'poll', v_question, now(),
          now() + make_interval(secs => v_ttl))
  returning * into v_row;
  insert into private.polls (message_id, options, multi, anonymous)
  values (v_row.id, v_options, coalesce(p_multi, false), coalesce(p_anonymous, true));

  update public.conversations set last_message_at = v_row.sent_at where id = p_conversation_id;
  update public.conversation_members
     set delivered_up_to = greatest(coalesce(delivered_up_to, v_row.sent_at), v_row.sent_at),
         read_up_to      = greatest(coalesce(read_up_to, v_row.sent_at), v_row.sent_at),
         archived_at     = null
   where conversation_id = p_conversation_id and user_id = v_uid;
  update public.conversation_members set archived_at = null
   where conversation_id = p_conversation_id and user_id <> v_uid;
  perform private.signal_members(p_conversation_id, 'message');
  return query select v_row.id, v_row.sent_at, v_row.expires_at;
end;
$$;

-- Voter (remplace mes votes) ; une liste vide retire mon vote.
create or replace function public.vote_poll(p_message_id uuid, p_options integer[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v      public.messages%rowtype := private.require_visible_message(p_message_id, v_uid);
  p      private.polls%rowtype;
  v_opts integer[] := (select coalesce(array_agg(distinct o order by o), '{}')
                         from unnest(coalesce(p_options, '{}')) o);
begin
  select * into p from private.polls where message_id = v.id for update;
  if v.kind <> 'poll' or not found then
    raise exception 'POLL_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p.closed_at is not null then
    raise exception 'POLL_CLOSED' using errcode = 'P0001';
  end if;
  if exists (select 1 from unnest(v_opts) o where o < 0 or o >= cardinality(p.options))
     or (not p.multi and cardinality(v_opts) > 1) then
    raise exception 'POLL_INVALID' using errcode = 'P0001';
  end if;
  if (select c.posting from public.conversations c where c.id = v.conversation_id) = 'closed' then
    raise exception 'GROUP_CLOSED' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(v_uid, 'poll_vote', 120, interval '1 hour');
  delete from private.poll_votes where message_id = v.id and user_id = v_uid;
  insert into private.poll_votes (message_id, user_id, option)
  select v.id, v_uid, o from unnest(v_opts) o;
  update public.messages set updated_at = now() where id = v.id;
  perform private.signal_members(v.conversation_id, 'message_changed');
  return private.poll_state(v.id, v_uid);
end;
$$;

-- Fermer un sondage (son créateur seulement) : les résultats sont figés.
create or replace function public.close_poll(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype := private.require_visible_message(p_message_id, v_uid);
begin
  if v.kind <> 'poll' then
    raise exception 'POLL_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v.sender_id is distinct from v_uid then
    raise exception 'NOT_SENDER' using errcode = 'P0001';
  end if;
  update private.polls set closed_at = coalesce(closed_at, now()) where message_id = v.id;
  update public.messages set updated_at = now() where id = v.id;
  perform private.signal_members(v.conversation_id, 'message_changed');
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Fonctions existantes ajustées (plafond, membres visibles, liste, messages)
-- ---------------------------------------------------------------------------
-- public.respond_to_invitation(uuid,boolean) : plafond selon le type de groupe.
CREATE OR REPLACE FUNCTION public.respond_to_invitation(p_invitation_id uuid, p_accept boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if private.active_member_count(v.conversation_id) >= private.group_member_cap(v.conversation_id) then
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
$function$;

-- public.respond_to_join_request(uuid,boolean) : plafond selon le type de groupe.
CREATE OR REPLACE FUNCTION public.respond_to_join_request(p_request_id uuid, p_approve boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v       private.group_join_requests%rowtype;
  v_uid   uuid;
  v_admin uuid;
begin
  select * into v from private.group_join_requests r where r.id = p_request_id for update;
  if not found then
    raise exception 'JOIN_REQUEST_NOT_FOUND' using errcode = 'P0001';
  end if;
  v_uid := private.require_group_role(v.conversation_id, array['owner', 'admin']);
  if v.status <> 'pending' or v.expires_at <= now() then
    raise exception 'JOIN_REQUEST_NOT_FOUND' using errcode = 'P0001';
  end if;
  if coalesce(p_approve, false) then
    perform private.require_open_group(v.conversation_id);
    perform 1 from public.conversations c where c.id = v.conversation_id for update;
    if private.active_member_count(v.conversation_id) >= private.group_member_cap(v.conversation_id) then
      raise exception 'GROUP_FULL' using errcode = 'P0001';
    end if;
    update private.group_join_requests
       set status = 'approved', decided_by = v_uid, decided_at = clock_timestamp()
     where id = v.id;
    if not private.is_member(v.conversation_id, v.user_id) then
      perform private.add_group_member(v.conversation_id, v.user_id, v_uid);
    end if;
    perform private.notify_join_request(v.id);
  else
    update private.group_join_requests
       set status = 'declined', decided_by = v_uid, decided_at = clock_timestamp()
     where id = v.id;
  end if;
  perform private.signal_user(v.user_id, v.conversation_id, 'join_request');
  for v_admin in
    select m.user_id from public.conversation_members m
     where m.conversation_id = v.conversation_id and m.left_at is null and m.role in ('owner', 'admin')
  loop
    perform private.signal_user(v_admin, v.conversation_id, 'join_request');
  end loop;
end;
$function$;

-- private.invite(uuid,uuid,uuid) : plafond selon le type de groupe.
CREATE OR REPLACE FUNCTION private.invite(p_conversation_id uuid, p_inviter uuid, p_invitee uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_max     integer := private.group_member_cap(p_conversation_id);
  v_pending integer;
  v_id      uuid;
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
          now() + make_interval(days => private.policy_int('group_invitation_ttl_days')))
  returning id into v_id;
  perform private.signal_user(p_invitee, p_conversation_id, 'invitation');
  perform private.notify_invitation(p_invitee, v_id);
  return true;
end;
$function$;

-- private.join_status(uuid,uuid) : plafond selon le type de groupe.
CREATE OR REPLACE FUNCTION private.join_status(p_conversation_id uuid, p_uid uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if private.is_member(p_conversation_id, p_uid) then
    return 'member';
  end if;
  if exists (select 1 from private.group_join_requests r
              where r.conversation_id = p_conversation_id and r.user_id = p_uid
                and r.status = 'pending' and r.expires_at > now()) then
    return 'pending';
  end if;
  if exists (select 1 from private.group_join_requests r
              where r.conversation_id = p_conversation_id and r.user_id = p_uid
                and r.status = 'declined' and r.decided_at > now() - interval '24 hours') then
    return 'declined';
  end if;
  if private.active_member_count(p_conversation_id) >= private.group_member_cap(p_conversation_id) then
    return 'full';
  end if;
  -- Une invitation en attente vaut accord des administrateurs.
  if exists (select 1 from private.group_invitations i
              where i.conversation_id = p_conversation_id and i.invitee_id = p_uid
                and i.status = 'pending' and i.expires_at > now()) then
    return 'open';
  end if;
  if (select c.join_approval from public.conversations c where c.id = p_conversation_id)
     or exists (select 1 from private.group_removals g
                 where g.conversation_id = p_conversation_id and g.user_id = p_uid) then
    return 'approval';
  end if;
  return 'open';
end;
$function$;

-- Membres visibles (lot 10.5).
CREATE OR REPLACE FUNCTION public.get_conversation_members(p_conversation_id uuid)
 RETURNS TABLE(user_id uuid, handle text, display_name text, avatar_path text, role text, joined_at timestamp with time zone, invited boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
     -- Lot 10.5 : dans un groupe « Annonces », un membre ne voit que les administrateurs.
     and (not private.hides_members(p_conversation_id, v_uid)
          or m.role in ('owner', 'admin') or m.user_id = v_uid)
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
$function$;

-- Groupes en commun (lot 10.5).
CREATE OR REPLACE FUNCTION public.list_common_groups(p_user_id uuid)
 RETURNS TABLE(conversation_id uuid, title text, member_count integer, avatar_path text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
     and (not private.hides_members(c.id, v_uid)
          or private.member_role(c.id, p_user_id) in ('owner', 'admin'))
   order by c.last_message_at desc nulls last, c.created_at desc
   limit 50;
end;
$function$;

-- Réglages d'un groupe (lot 10.5).
CREATE OR REPLACE FUNCTION public.set_group_settings(p_conversation_id uuid, p_posting text DEFAULT NULL::text, p_info_editing text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := private.require_group_role(p_conversation_id, array['owner', 'admin']);
  v_conv public.conversations%rowtype;
begin
  if (p_posting is not null and p_posting not in ('all', 'admins'))
     or (p_info_editing is not null and p_info_editing not in ('all', 'admins')) then
    raise exception 'SETTING_INVALID' using errcode = 'P0001';
  end if;
  select * into v_conv from public.conversations where id = p_conversation_id for update;
  if v_conv.announcement and p_posting is not null and p_posting <> 'admins' then
    raise exception 'ANNOUNCEMENT_LOCKED' using errcode = 'P0001';
  end if;
  if p_posting is not null and p_posting <> v_conv.posting then
    update public.conversations set posting = p_posting where id = p_conversation_id;
    perform private.group_event(p_conversation_id, v_uid, 'posting', null, p_posting);
  end if;
  if p_info_editing is not null and p_info_editing <> v_conv.info_editing then
    update public.conversations set info_editing = p_info_editing where id = p_conversation_id;
    perform private.group_event(p_conversation_id, v_uid, 'info_editing', null, p_info_editing);
  end if;
end;
$function$;

-- Effacer après lecture : pas pour un sondage (lot 10.5).
CREATE OR REPLACE FUNCTION private.messages_read_erase()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.kind not in ('system', 'poll') then
    new.read_erase_seconds := (select c.read_erase_seconds from public.conversations c
                                where c.id = new.conversation_id);
  else
    new.read_erase_seconds := null;
  end if;
  return new;
end;
$function$;

-- Liste des discussions (lot 10.5).
drop function if exists public.list_conversations();
CREATE OR REPLACE FUNCTION public.list_conversations()
 RETURNS TABLE(conversation_id uuid, kind text, peer_id uuid, peer_handle text, peer_display_name text, peer_avatar_path text, peer_deleted boolean, blocked boolean, last_message_id uuid, last_sender_id uuid, last_sender_name text, last_body text, last_deleted boolean, last_sent_at timestamp with time zone, last_expires_at timestamp with time zone, last_kind text, ttl_seconds integer, unread_count integer, pinned boolean, archived boolean, muted_until timestamp with time zone, peer_delivered_up_to timestamp with time zone, peer_read_up_to timestamp with time zone, sort_at timestamp with time zone, title text, description text, avatar_path text, member_count integer, my_role text, posting text, info_editing text, cleared_before timestamp with time zone, clear_request_by uuid, clear_request_expires_at timestamp with time zone, clear_request_delete boolean, read_erase_seconds integer, secret boolean, announcement boolean)
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
           c.avatar_path, c.posting, c.info_editing, c.cleared_at, c.read_erase_seconds, c.announcement,
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
       and not (m.kind = 'system' and private.hidden_member_event(m.conversation_id, m.sender_id, m.body, v_uid))
  ),
  last_msg as (
    select distinct on (v.conversation_id) v.* from visible v
     order by v.conversation_id, v.sent_at desc
  ),
  unread as (
    select v.conversation_id, count(*)::int as n from visible v
      join mine on mine.id = v.conversation_id
     where v.sender_id is distinct from v_uid and v.deleted_at is null
       and v.kind in ('text', 'voice', 'photo', 'sticker', 'gif', 'poll')
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
         mine.secret_at is not null,
         coalesce(mine.announcement, false)
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

-- Messages (lot 10.5).
drop function if exists public.get_messages(uuid, timestamptz, timestamptz, integer);
CREATE OR REPLACE FUNCTION public.get_messages(p_conversation_id uuid, p_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 50)
 RETURNS TABLE(id uuid, sender_id uuid, sender_name text, kind text, body text, reply_to_id uuid, reply_preview text, reply_kind text, sent_at timestamp with time zone, expires_at timestamp with time zone, edited_at timestamp with time zone, deleted_at timestamp with time zone, updated_at timestamp with time zone, reactions jsonb, media_path text, media_duration_ms integer, media_width integer, media_height integer, media_waveform smallint[], mentions uuid[], view_once boolean, opened boolean, opened_count integer, link_preview jsonb, read_erase_seconds integer, poll jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_member(p_conversation_id);
  v_since timestamptz := private.member_since(p_conversation_id, v_uid);
  v_limit int  := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_hide  boolean := private.hides_members(p_conversation_id, v_uid);
begin
  return query
  select m.id, m.sender_id, sp.display_name, m.kind, m.body, m.reply_to_id,
         case when r.id is not null and r.expires_at > now() and r.deleted_at is null
                   and r.sent_at >= v_since
              then left(r.body, 120) end,
         case when r.id is not null and r.expires_at > now() and r.deleted_at is null
                   and r.sent_at >= v_since
              then r.kind end,
         m.sent_at, least(m.expires_at, er.erase_at), m.edited_at, m.deleted_at, m.updated_at,
         coalesce((select jsonb_agg(jsonb_build_object(
                    -- Lot 10.5 : dans un groupe « Annonces », un membre ne voit pas qui a réagi.
                    'user_id', case when v_hide and x.user_id <> v_uid
                                         and private.member_role(p_conversation_id, x.user_id) not in ('owner', 'admin')
                                    then null else x.user_id end,
                    'emoji', x.emoji)
                                    order by x.created_at)
                     from public.message_reactions x where x.message_id = m.id), '[]'::jsonb),
         -- Vue unique : le fichier n'est lisible que par un destinataire qui vient de l'ouvrir.
         case when m.view_once and not private.view_once_readable(m.id, m.sender_id, v_uid)
              then null else m.media_path end,
         m.media_duration_ms, m.media_width, m.media_height, m.media_waveform,
         case when m.deleted_at is null then
           coalesce((select array_agg(mm.user_id order by mm.user_id)
                       from private.message_mentions mm where mm.message_id = m.id), '{}'::uuid[])
         else '{}'::uuid[] end,
         m.view_once,
         exists (select 1 from private.view_once_opens o where o.message_id = m.id and o.user_id = v_uid),
         case when m.view_once and m.sender_id = v_uid then
           (select count(*)::int from private.view_once_opens o where o.message_id = m.id)
         end,
         case when m.deleted_at is null then
           (select jsonb_build_object('url', lp.url, 'title', lp.title, 'description', lp.description,
                                      'site', lp.site, 'image_path', lp.image_path,
                                      'image_width', lp.image_width, 'image_height', lp.image_height)
              from private.link_previews lp where lp.message_id = m.id)
         end,
         m.read_erase_seconds,
         case when m.kind = 'poll' and m.deleted_at is null then private.poll_state(m.id, v_uid) end
    from public.messages m
    left join private.read_erasures er on er.message_id = m.id and er.user_id = v_uid
    left join public.messages r on r.id = m.reply_to_id
    left join public.profiles sp on sp.id = m.sender_id and sp.deleted_at is null
   where m.conversation_id = p_conversation_id
     and m.expires_at > now()
     and (er.erase_at is null or er.erase_at > now())
     and m.sent_at >= v_since
     and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
     and not (v_hide and m.kind = 'system'
              and private.hidden_member_event(m.conversation_id, m.sender_id, m.body, v_uid))
     and (p_since is null or m.updated_at > p_since)
     and (p_before is null or m.sent_at < p_before)
   order by
     case when p_since is not null then m.updated_at end asc,
     case when p_since is null then m.sent_at end desc
   limit v_limit;
end;
$function$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.create_group(text, text, uuid[], boolean) to authenticated;
grant execute on function public.send_poll(uuid, uuid, text, text[], boolean, boolean, integer) to authenticated;
grant execute on function public.vote_poll(uuid, integer[]) to authenticated;
grant execute on function public.close_poll(uuid) to authenticated;
grant execute on function public.list_conversations() to authenticated;
grant execute on function public.get_messages(uuid, timestamptz, timestamptz, integer) to authenticated;
grant execute on function public.get_conversation_members(uuid) to authenticated;
grant execute on function public.list_common_groups(uuid) to authenticated;
grant execute on function public.set_group_settings(uuid, text, text) to authenticated;
grant execute on function public.respond_to_invitation(uuid, boolean) to authenticated;
grant execute on function public.respond_to_join_request(uuid, boolean) to authenticated;
