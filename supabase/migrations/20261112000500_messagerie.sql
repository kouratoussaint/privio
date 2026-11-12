-- PRIVIO — Migration 5 : messagerie 1:1 (lot 2.1)
-- Invariants :
--   * un message n'est JAMAIS visible après expires_at (filtré à la source : RLS + RPC) ;
--   * expires_at est fixé par le serveur à l'envoi (heure serveur + politique en vigueur) ;
--   * aucune écriture directe : tout passe par des RPC qui vérifient appartenance et blocages ;
--   * les signaux temps réel ne transportent aucun contenu (identifiant de conversation seul).

-- ---------------------------------------------------------------------------
-- Politiques (décision B1 : modification 60 min, suppression pour tous jusqu'à expiration)
-- ---------------------------------------------------------------------------
update private.policy_definitions set implemented = true where key = 'message_ttl_hours';

insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('message_edit_window_minutes', 'integer', '60', 0, 1440, null, true, true,
   'Délai pendant lequel l''expéditeur peut modifier son message (0 = jamais).'),
  ('message_delete_for_all_hours', 'integer', '72', 0, 72, null, true, true,
   'Délai pour supprimer un message pour tout le monde (72 = jusqu''à expiration).'),
  ('message_max_chars', 'integer', '4000', 1, 4000, null, true, true,
   'Longueur maximale d''un message texte.'),
  ('message_send_hourly_limit', 'integer', '600', 10, 5000, null, false, true,
   'Messages envoyés par compte et par heure (anti-abus).'),
  ('conversation_create_hourly_limit', 'integer', '30', 1, 200, null, false, true,
   'Nouvelles discussions par compte et par heure (anti-abus).');

create or replace function private.policy_int(p_key text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select (private.policy_value(p_key) #>> '{}')::integer;
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.conversations (
  id              uuid        primary key default gen_random_uuid(),
  kind            text        not null default 'direct' check (kind in ('direct')),
  -- Paire triée « uuidA:uuidB » : une seule discussion directe par paire.
  direct_key      text        unique,
  created_by      uuid        references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz,
  check ((kind = 'direct') = (direct_key is not null))
);

create table public.conversation_members (
  conversation_id  uuid        not null references public.conversations (id) on delete cascade,
  user_id          uuid        not null references auth.users (id) on delete cascade,
  joined_at        timestamptz not null default now(),
  left_at          timestamptz,
  -- Accusés : pointeurs monotones (tout message envoyé avant est reçu / lu).
  delivered_up_to  timestamptz,
  read_up_to       timestamptz,
  pinned_at        timestamptz,
  archived_at      timestamptz,
  primary key (conversation_id, user_id)
);
create index conversation_members_user_idx on public.conversation_members (user_id) where left_at is null;

create table public.messages (
  id              uuid        primary key default gen_random_uuid(),
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  sender_id       uuid        references auth.users (id) on delete set null,
  client_msg_id   uuid        not null,
  kind            text        not null default 'text' check (kind in ('text')),
  body            text,
  reply_to_id     uuid        references public.messages (id) on delete set null,
  sent_at         timestamptz not null default now(),
  expires_at      timestamptz not null,
  edited_at       timestamptz,
  deleted_at      timestamptz,
  updated_at      timestamptz not null default now(),
  unique (sender_id, client_msg_id),
  check (expires_at > sent_at and expires_at <= sent_at + interval '72 hours'),
  check ((deleted_at is null) = (body is not null))
);
create index messages_conv_sent_idx on public.messages (conversation_id, sent_at desc);
create index messages_conv_updated_idx on public.messages (conversation_id, updated_at);
create index messages_expires_idx on public.messages (expires_at);

create table public.message_reactions (
  message_id uuid        not null references public.messages (id) on delete cascade,
  user_id    uuid        not null references auth.users (id) on delete cascade,
  emoji      text        not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

-- « Supprimer pour moi » : masquage individuel.
create table public.message_hidden (
  message_id uuid not null references public.messages (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  primary key (message_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Fonctions d'appartenance (SECURITY DEFINER : utilisables dans la RLS sans récursion)
-- ---------------------------------------------------------------------------
create or replace function private.is_member(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members m
     where m.conversation_id = p_conversation_id and m.user_id = p_user_id and m.left_at is null
  );
$$;

create or replace function private.shares_conversation(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.conversation_members m1
      join public.conversation_members m2 on m2.conversation_id = m1.conversation_id
     where m1.user_id = a and m2.user_id = b and m1.left_at is null and m2.left_at is null
  );
$$;

create or replace function private.require_member(p_conversation_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  if not private.is_member(p_conversation_id, v_uid) then
    raise exception 'NOT_MEMBER' using errcode = 'P0001';
  end if;
  return v_uid;
end;
$$;

-- Pair d'une discussion directe (null pour les autres types).
create or replace function private.direct_peer(p_conversation_id uuid, p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.user_id from public.conversation_members m
   join public.conversations c on c.id = m.conversation_id and c.kind = 'direct'
   where m.conversation_id = p_conversation_id and m.user_id <> p_user_id
   limit 1;
$$;

-- Message lisible : existant, non expiré, l'appelant est membre.
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
  if not found or not private.is_member(v.conversation_id, p_user_id) then
    raise exception 'MESSAGE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v.expires_at <= now() then
    raise exception 'MESSAGE_EXPIRED' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Signal temps réel sans contenu, vers le canal privé « user:<id> » de chaque membre.
-- Sans effet si Realtime n'est pas installé (tests locaux sans Supabase).
-- ---------------------------------------------------------------------------
create or replace function private.signal_members(p_conversation_id uuid, p_event text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    return;
  end if;
  for r in
    select user_id from public.conversation_members
     where conversation_id = p_conversation_id and left_at is null
  loop
    execute 'select realtime.send($1, $2, $3, true)'
      using jsonb_build_object('conversation_id', p_conversation_id), p_event, 'user:' || r.user_id::text;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS : lecture réservée aux membres, messages expirés invisibles. Aucune écriture directe.
-- ---------------------------------------------------------------------------
alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;
alter table public.message_reactions    enable row level security;
alter table public.message_hidden       enable row level security;

revoke all on public.conversations, public.conversation_members, public.messages,
              public.message_reactions, public.message_hidden from public, anon, authenticated;
grant select on public.conversations, public.conversation_members, public.message_reactions,
                public.message_hidden to authenticated;
grant select (id, conversation_id, sender_id, kind, body, reply_to_id, sent_at, expires_at,
              edited_at, deleted_at, updated_at) on public.messages to authenticated;

create policy conversations_select_member on public.conversations
  for select to authenticated
  using ((select private.session_is_active()) and private.is_member(id, (select auth.uid())));

create policy members_select_member on public.conversation_members
  for select to authenticated
  using ((select private.session_is_active()) and private.is_member(conversation_id, (select auth.uid())));

create policy messages_select_member_unexpired on public.messages
  for select to authenticated
  using (
    expires_at > now()
    and (select private.session_is_active())
    and private.is_member(conversation_id, (select auth.uid()))
  );

create policy reactions_select_member on public.message_reactions
  for select to authenticated
  using (
    (select private.session_is_active())
    and exists (select 1 from public.messages m
                 where m.id = message_id and m.expires_at > now()
                   and private.is_member(m.conversation_id, (select auth.uid())))
  );

create policy hidden_select_own on public.message_hidden
  for select to authenticated
  using (user_id = (select auth.uid()) and (select private.session_is_active()));

-- Profils : visibles aussi entre membres d'une même discussion.
create policy profiles_select_conversation_peer on public.profiles
  for select to authenticated
  using ((select private.session_is_active()) and private.shares_conversation((select auth.uid()), id));

-- ---------------------------------------------------------------------------
-- RPC : démarrer une discussion directe
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

  insert into public.conversations (kind, direct_key, created_by)
  values ('direct', v_key, v_uid)
  on conflict (direct_key) do nothing
  returning id into v_id;

  if v_id is null then  -- créée au même instant par l'autre personne
    select c.id into v_id from public.conversations c where c.direct_key = v_key;
    return v_id;
  end if;

  insert into public.conversation_members (conversation_id, user_id)
  values (v_id, v_uid), (v_id, p_other_user_id);
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : envoyer un message texte (idempotent par client_msg_id)
-- ---------------------------------------------------------------------------
create or replace function public.send_message(
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_body            text,
  p_reply_to_id     uuid default null
)
returns table (id uuid, sent_at timestamptz, expires_at timestamptz)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid  uuid := private.require_member(p_conversation_id);
  v_body text := btrim(coalesce(p_body, ''));
  v_peer uuid;
  v_existing public.messages%rowtype;
  v_reply public.messages%rowtype;
  v_row  public.messages%rowtype;
begin
  if p_client_msg_id is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;

  -- Idempotence : un renvoi (réseau instable) renvoie le message déjà créé.
  select * into v_existing from public.messages m
   where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
  if found then
    if v_existing.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    return query select v_existing.id, v_existing.sent_at, v_existing.expires_at;
    return;
  end if;

  v_peer := private.direct_peer(p_conversation_id, v_uid);
  if v_peer is not null and private.is_blocked_between(v_uid, v_peer) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;
  if char_length(v_body) = 0 or char_length(v_body) > private.policy_int('message_max_chars') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if p_reply_to_id is not null then
    select * into v_reply from public.messages m where m.id = p_reply_to_id;
    if not found or v_reply.conversation_id <> p_conversation_id or v_reply.expires_at <= now() then
      raise exception 'REPLY_NOT_FOUND' using errcode = 'P0001';
    end if;
  end if;

  perform private.consume_rate_limit(v_uid, 'message_send',
    private.policy_int('message_send_hourly_limit'), interval '1 hour');

  begin
    insert into public.messages (conversation_id, sender_id, client_msg_id, body, reply_to_id, sent_at, expires_at)
    values (p_conversation_id, v_uid, p_client_msg_id, v_body, p_reply_to_id, now(),
            now() + make_interval(hours => private.policy_int('message_ttl_hours')))
    returning * into v_row;
  exception when unique_violation then
    -- Même message envoyé deux fois au même instant : on renvoie le premier.
    select * into v_existing from public.messages m
     where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
    return query select v_existing.id, v_existing.sent_at, v_existing.expires_at;
    return;
  end;

  update public.conversations set last_message_at = v_row.sent_at where conversations.id = p_conversation_id;
  -- L'expéditeur a forcément reçu et lu son propre message.
  update public.conversation_members
     set delivered_up_to = greatest(coalesce(delivered_up_to, v_row.sent_at), v_row.sent_at),
         read_up_to      = greatest(coalesce(read_up_to, v_row.sent_at), v_row.sent_at),
         archived_at     = null
   where conversation_id = p_conversation_id and user_id = v_uid;
  -- Un nouveau message désarchive la discussion chez le destinataire.
  update public.conversation_members set archived_at = null
   where conversation_id = p_conversation_id and user_id <> v_uid;

  perform private.signal_members(p_conversation_id, 'message');
  return query select v_row.id, v_row.sent_at, v_row.expires_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : modifier, supprimer pour tous, supprimer pour moi
-- ---------------------------------------------------------------------------
create or replace function public.edit_message(p_message_id uuid, p_body text)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v      public.messages%rowtype := private.visible_message(p_message_id, v_uid);
  v_body text := btrim(coalesce(p_body, ''));
begin
  if v.sender_id is distinct from v_uid then
    raise exception 'NOT_SENDER' using errcode = 'P0001';
  end if;
  if v.deleted_at is not null then
    raise exception 'MESSAGE_DELETED' using errcode = 'P0001';
  end if;
  if now() > v.sent_at + make_interval(mins => private.policy_int('message_edit_window_minutes')) then
    raise exception 'EDIT_WINDOW_EXPIRED' using errcode = 'P0001';
  end if;
  if char_length(v_body) = 0 or char_length(v_body) > private.policy_int('message_max_chars') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  update public.messages set body = v_body, edited_at = now(), updated_at = now()
   where id = p_message_id;
  perform private.signal_members(v.conversation_id, 'message_changed');
  return now();
end;
$$;

create or replace function public.delete_message_for_everyone(p_message_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype := private.visible_message(p_message_id, v_uid);
begin
  if v.sender_id is distinct from v_uid then
    raise exception 'NOT_SENDER' using errcode = 'P0001';
  end if;
  if v.deleted_at is not null then
    return;
  end if;
  if now() > v.sent_at + make_interval(hours => private.policy_int('message_delete_for_all_hours')) then
    raise exception 'DELETE_WINDOW_EXPIRED' using errcode = 'P0001';
  end if;
  -- Le contenu est effacé immédiatement ; une trace vide reste jusqu'à l'expiration
  -- pour que chaque appareil retire le message.
  update public.messages set body = null, deleted_at = now(), edited_at = null, updated_at = now()
   where id = p_message_id;
  delete from public.message_reactions where message_id = p_message_id;
  perform private.signal_members(v.conversation_id, 'message_changed');
end;
$$;

create or replace function public.delete_message_for_me(p_message_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype := private.visible_message(p_message_id, v_uid);
begin
  insert into public.message_hidden (message_id, user_id) values (v.id, v_uid)
  on conflict do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : réactions (une par personne et par message)
-- ---------------------------------------------------------------------------
create or replace function public.set_reaction(p_message_id uuid, p_emoji text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_active_user();
  v       public.messages%rowtype := private.visible_message(p_message_id, v_uid);
  v_emoji text := btrim(coalesce(p_emoji, ''));
begin
  if v.deleted_at is not null then
    raise exception 'MESSAGE_DELETED' using errcode = 'P0001';
  end if;
  if char_length(v_emoji) not between 1 and 16 or v_emoji ~ '[[:alnum:][:space:]]' then
    raise exception 'REACTION_INVALID' using errcode = 'P0001';
  end if;
  insert into public.message_reactions (message_id, user_id, emoji) values (v.id, v_uid, v_emoji)
  on conflict (message_id, user_id) do update set emoji = excluded.emoji, created_at = now();
  update public.messages set updated_at = now() where id = v.id;
  perform private.signal_members(v.conversation_id, 'message_changed');
end;
$$;

create or replace function public.remove_reaction(p_message_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype := private.visible_message(p_message_id, v_uid);
begin
  delete from public.message_reactions where message_id = v.id and user_id = v_uid;
  if found then
    update public.messages set updated_at = now() where id = v.id;
    perform private.signal_members(v.conversation_id, 'message_changed');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : accusés de réception / lecture (pointeurs monotones, jamais dans le futur)
-- ---------------------------------------------------------------------------
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
  v_read      timestamptz := least(p_read_up_to, now());
  v_delivered timestamptz := least(greatest(p_delivered_up_to, p_read_up_to), now());
  v_changed   int;
begin
  update public.conversation_members
     set delivered_up_to = greatest(coalesce(delivered_up_to, v_delivered), v_delivered),
         read_up_to      = greatest(coalesce(read_up_to, v_read), v_read)
   where conversation_id = p_conversation_id and user_id = v_uid
     and (v_delivered is not null or v_read is not null)
     and (delivered_up_to is distinct from greatest(coalesce(delivered_up_to, v_delivered), v_delivered)
          or read_up_to is distinct from greatest(coalesce(read_up_to, v_read), v_read));
  get diagnostics v_changed = row_count;
  if v_changed > 0 then
    perform private.signal_members(p_conversation_id, 'receipt');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : épingler / archiver (état personnel)
-- ---------------------------------------------------------------------------
create or replace function public.set_conversation_flags(
  p_conversation_id uuid,
  p_pinned          boolean default null,
  p_archived        boolean default null
)
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
     set pinned_at   = case when p_pinned is null then pinned_at
                            when p_pinned then coalesce(pinned_at, now()) end,
         archived_at = case when p_archived is null then archived_at
                            when p_archived then coalesce(archived_at, now()) end
   where conversation_id = p_conversation_id and user_id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC : liste des discussions (écran 08)
-- ---------------------------------------------------------------------------
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
         lm.id, lm.sender_id, lm.body, lm.deleted_at is not null, lm.sent_at,
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

-- ---------------------------------------------------------------------------
-- RPC : messages d'une discussion (écran 10)
--   p_since  : synchronisation incrémentale (modifiés après ce curseur, ordre croissant)
--   p_before : pagination arrière (plus récents d'abord)
-- ---------------------------------------------------------------------------
create or replace function public.get_messages(
  p_conversation_id uuid,
  p_since           timestamptz default null,
  p_before          timestamptz default null,
  p_limit           integer default 50
)
returns table (
  id            uuid,
  sender_id     uuid,
  kind          text,
  body          text,
  reply_to_id   uuid,
  reply_preview text,
  sent_at       timestamptz,
  expires_at    timestamptz,
  edited_at     timestamptz,
  deleted_at    timestamptz,
  updated_at    timestamptz,
  reactions     jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_member(p_conversation_id);
  v_limit int  := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  return query
  select m.id, m.sender_id, m.kind, m.body, m.reply_to_id,
         case when r.id is not null and r.expires_at > now() and r.deleted_at is null
              then left(r.body, 120) end,
         m.sent_at, m.expires_at, m.edited_at, m.deleted_at, m.updated_at,
         coalesce((select jsonb_agg(jsonb_build_object('user_id', x.user_id, 'emoji', x.emoji)
                                    order by x.created_at)
                     from public.message_reactions x where x.message_id = m.id), '[]'::jsonb)
    from public.messages m
    left join public.messages r on r.id = m.reply_to_id
   where m.conversation_id = p_conversation_id
     and m.expires_at > now()
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
-- RPC : liste des personnes bloquées (écran Paramètres)
-- ---------------------------------------------------------------------------
create or replace function public.list_blocked_users()
returns table (id uuid, handle text, display_name text, blocked_at timestamptz)
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
  select p.id, p.handle, p.display_name, b.created_at
    from public.blocks b join public.profiles p on p.id = b.blocked_id
   where b.blocker_id = v_uid
   order by b.created_at desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Purge : messages expirés + compteurs de limitation échus (toutes les minutes).
-- La visibilité ne dépend PAS de la purge : un message expiré est déjà invisible.
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
begin
  -- Les réponses perdent leur lien (on delete set null) avant la suppression.
  delete from public.messages where expires_at <= now();
  get diagnostics v_count = row_count;
  delete from private.rate_limit_hits where window_start < now() - interval '1 day';
  return v_count;
end;
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_purge_expired';
    perform cron.schedule('privio_purge_expired', '* * * * *', 'select private.purge_expired()');
  else
    raise notice 'pg_cron indisponible : purge planifiée non installée (environnement de test local)';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Realtime : chaque utilisateur ne peut écouter que son propre canal privé.
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('realtime.messages') is not null then
    execute 'drop policy if exists privio_own_user_topic on realtime.messages';
    execute $p$
      create policy privio_own_user_topic on realtime.messages
        for select to authenticated
        using (
          (select realtime.topic()) = 'user:' || (select auth.uid())::text
          and realtime.messages.extension = 'broadcast'
        )
    $p$;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits d'exécution. harden_privileges() gagne une liste explicite des fonctions
-- privées autorisées au rôle authenticated (utilisées dans des politiques RLS).
-- ---------------------------------------------------------------------------
create or replace function private.harden_privileges()
returns void
language plpgsql
set search_path = ''
as $$
declare
  r record;
  allowed text[] := array[
    'private.session_is_active()',
    'private.is_member(uuid,uuid)',
    'private.shares_conversation(uuid,uuid)'
  ];
  f text;
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
  foreach f in array allowed loop
    if to_regprocedure(f) is not null then
      execute format('grant execute on function %s to authenticated', f);
    end if;
  end loop;
  execute 'revoke all on all tables in schema private from public, anon, authenticated';
end;
$$;

select private.harden_privileges();

grant execute on function public.start_direct_conversation(uuid) to authenticated;
grant execute on function public.send_message(uuid, uuid, text, uuid) to authenticated;
grant execute on function public.edit_message(uuid, text) to authenticated;
grant execute on function public.delete_message_for_everyone(uuid) to authenticated;
grant execute on function public.delete_message_for_me(uuid) to authenticated;
grant execute on function public.set_reaction(uuid, text) to authenticated;
grant execute on function public.remove_reaction(uuid) to authenticated;
grant execute on function public.mark_conversation(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.set_conversation_flags(uuid, boolean, boolean) to authenticated;
grant execute on function public.list_conversations() to authenticated;
grant execute on function public.get_messages(uuid, timestamptz, timestamptz, integer) to authenticated;
grant execute on function public.list_blocked_users() to authenticated;
