-- PRIVIO — lot 7.1b (amendement 12) : rejoindre un groupe par code ou QR code, demandes
-- d'adhésion, @mentions.
--
-- Invariants :
--   * un code d'invitation (PRV-XXXXXX) n'est visible que des administrateurs ; il peut être
--     réinitialisé (l'ancien cesse aussitôt de fonctionner). Aucun lien web : le code se
--     transmet hors de l'application, ou se scanne (QR code affiché par un administrateur) ;
--   * par défaut, entrer avec un code crée une DEMANDE que les administrateurs acceptent ou
--     refusent (réglable par groupe). Une personne retirée par un administrateur repasse
--     toujours par une demande ;
--   * essais de code limités par heure ; un code faux NE lève PAS d'erreur (le compteur
--     d'essais doit être enregistré : une erreur annulerait la transaction) ;
--   * un groupe fermé par Privio n'accepte plus personne ; un code ne révèle rien à une
--     personne bloquée par un administrateur (même réponse qu'un code faux) ;
--   * @mentions : la personne mentionnée reçoit une notification SANS CONTENU (« Vous avez
--     été mentionné dans un groupe »), même si elle a mis le groupe en sourdine.

-- ---------------------------------------------------------------------------
-- Réglage anti-abus
-- ---------------------------------------------------------------------------
insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented,
   description_fr, category, label_fr, unit, admin_locked, advanced, sort_order, effect_fr)
values
  ('group_code_hourly_limit', 'integer', '20', 5, 200, null, false, true,
   'Essais de code d''invitation de groupe par compte et par heure (contre les codes devinés).',
   'abuse', 'Essais de code d’invitation de groupe, par heure', 'nb', false, false, 45, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
alter table public.conversations
  add column join_approval boolean not null default true;

create table private.group_invite_codes (
  conversation_id uuid        primary key references public.conversations (id) on delete cascade,
  code            text        not null unique check (code ~ '^PRV-[2-9A-HJ-NP-Z]{6}$'),
  created_by      uuid        references auth.users (id) on delete set null,
  created_at      timestamptz not null default now()
);

create table private.group_join_requests (
  id              uuid        primary key default gen_random_uuid(),
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  user_id         uuid        not null references auth.users (id) on delete cascade,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  status          text        not null default 'pending'
                    check (status in ('pending', 'approved', 'declined', 'cancelled')),
  decided_by      uuid        references auth.users (id) on delete set null,
  decided_at      timestamptz
);
create unique index group_join_requests_one_pending
  on private.group_join_requests (conversation_id, user_id) where status = 'pending';
create index group_join_requests_group_idx
  on private.group_join_requests (conversation_id) where status = 'pending';
create index group_join_requests_user_idx on private.group_join_requests (user_id);

-- Personnes retirées par un administrateur : elles repassent par une demande.
create table private.group_removals (
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  user_id         uuid        not null references auth.users (id) on delete cascade,
  removed_at      timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table private.message_mentions (
  message_id uuid not null references public.messages (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  primary key (message_id, user_id)
);
create index message_mentions_user_idx on private.message_mentions (user_id);

revoke all on private.group_invite_codes, private.group_join_requests, private.group_removals,
  private.message_mentions from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Codes
-- ---------------------------------------------------------------------------
-- 32 signes sans ambiguïté (ni 0/O, ni 1/I) : 32^6 ≈ 1 milliard de codes.
create or replace function private.new_invite_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  -- Les 6 premiers octets d'un UUID v4 sont aléatoires ; 256 est un multiple de 32.
  v_bytes bytea := uuid_send(gen_random_uuid());
  v_code  text := 'PRV-';
begin
  for i in 0..5 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_code;
end;
$$;

-- Saisie tolérante : minuscules, espaces, tirets, avec ou sans « PRV ».
create or replace function private.normalize_invite_code(p_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
           -- 6 signes sans préfixe ; « PRV » suivi de 3 signes est un code incomplet.
           when char_length(v) = 6 and v ~ '^[2-9A-HJ-NP-Z]{6}$' and v !~ '^PRV' then 'PRV-' || v
           when char_length(v) = 9 and v ~ '^PRV[2-9A-HJ-NP-Z]{6}$' then 'PRV-' || right(v, 6)
         end
    from (select regexp_replace(upper(coalesce(p_code, '')), '[^A-Z0-9]', '', 'g') as v) s;
$$;

create or replace function private.require_open_group(p_conversation_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.conversations c where c.id = p_conversation_id and c.posting = 'closed') then
    raise exception 'GROUP_CLOSED' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function private.set_invite_code(p_conversation_id uuid, p_uid uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  loop
    v_code := private.new_invite_code();
    begin
      insert into private.group_invite_codes (conversation_id, code, created_by)
      values (p_conversation_id, v_code, p_uid)
      on conflict (conversation_id) do update
        set code = excluded.code, created_by = excluded.created_by, created_at = now();
      return v_code;
    exception when unique_violation then
      -- Code déjà pris par un autre groupe (rarissime) : on en tire un autre.
    end;
  end loop;
end;
$$;

-- Code du groupe (administrateurs) ; créé à la première demande.
create or replace function public.get_group_invite_code(p_conversation_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_group_role(p_conversation_id, array['owner', 'admin']);
  v_code text;
begin
  perform private.require_open_group(p_conversation_id);
  select c.code into v_code from private.group_invite_codes c where c.conversation_id = p_conversation_id;
  return coalesce(v_code, private.set_invite_code(p_conversation_id, v_uid));
end;
$$;

-- Nouveau code : l'ancien cesse aussitôt de fonctionner.
create or replace function public.reset_group_invite_code(p_conversation_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_group_role(p_conversation_id, array['owner', 'admin']);
begin
  perform private.require_open_group(p_conversation_id);
  return private.set_invite_code(p_conversation_id, v_uid);
end;
$$;

create or replace function public.set_group_join_approval(p_conversation_id uuid, p_required boolean)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_group_role(p_conversation_id, array['owner', 'admin']);
begin
  perform private.require_open_group(p_conversation_id);
  if p_required is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  update public.conversations set join_approval = p_required where id = p_conversation_id;
  perform private.signal_members(p_conversation_id, 'message_changed');
end;
$$;

-- Réglages d'entrée du groupe (administrateurs).
create or replace function public.get_group_join_settings(p_conversation_id uuid)
returns table (join_approval boolean, has_code boolean, pending_requests integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_group_role(p_conversation_id, array['owner', 'admin']);
begin
  return query
  select c.join_approval,
         exists (select 1 from private.group_invite_codes k where k.conversation_id = c.id),
         (select count(*)::int from private.group_join_requests r
           where r.conversation_id = c.id and r.status = 'pending' and r.expires_at > now())
    from public.conversations c where c.id = p_conversation_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Entrer avec un code
-- ---------------------------------------------------------------------------
-- Membre ajouté (même chemin qu'une invitation acceptée).
create or replace function private.add_group_member(p_conversation_id uuid, p_user uuid, p_added_by uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  insert into public.conversation_members (conversation_id, user_id, role, added_by, joined_at)
  values (p_conversation_id, p_user, 'member', p_added_by, now())
  on conflict (conversation_id, user_id) do update
    set left_at = null, joined_at = now(), role = 'member', added_by = excluded.added_by,
        delivered_up_to = null, read_up_to = null, pinned_at = null, archived_at = null,
        muted_until = null;
  update private.group_invitations set status = 'accepted'
   where conversation_id = p_conversation_id and invitee_id = p_user and status = 'pending';
  delete from private.group_removals where conversation_id = p_conversation_id and user_id = p_user;
  perform private.group_event(p_conversation_id, p_user, 'joined');
end;
$$;

-- Groupe désigné par un code, pour cette personne ; null : code faux, groupe fermé, ou
-- blocage avec un administrateur (indiscernables pour elle).
create or replace function private.group_of_code(p_code text, p_uid uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select k.conversation_id into v_id
    from private.group_invite_codes k
    join public.conversations c on c.id = k.conversation_id
   where k.code = private.normalize_invite_code(p_code)
     and c.kind = 'group' and c.posting <> 'closed';
  if v_id is null or exists (
    select 1 from public.conversation_members m
     where m.conversation_id = v_id and m.left_at is null and m.role in ('owner', 'admin')
       and private.is_blocked_between(m.user_id, p_uid)) then
    return null;
  end if;
  return v_id;
end;
$$;

-- Situation de cette personne face au groupe : member, pending, declined (refus de moins
-- de 24 h), full, open (entrée directe) ou approval (une demande sera envoyée).
create or replace function private.join_status(p_conversation_id uuid, p_uid uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
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
  if private.active_member_count(p_conversation_id) >= private.policy_int('group_max_members') then
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
$$;

create or replace function public.preview_group_by_code(p_code text)
returns table (status text, conversation_id uuid, title text, member_count integer)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid    uuid := private.require_active_user();
  v_id     uuid;
  v_status text;
begin
  perform private.consume_rate_limit(v_uid, 'group_code',
    private.policy_int('group_code_hourly_limit'), interval '1 hour');
  v_id := private.group_of_code(p_code, v_uid);
  if v_id is null then
    return query select 'invalid'::text, null::uuid, null::text, null::integer;
    return;
  end if;
  v_status := private.join_status(v_id, v_uid);
  return query
  -- Identifiant du groupe seulement pour un membre (ouvrir) ou une demande déjà envoyée
  -- (l'annuler) : un simple code ne le révèle pas.
  select v_status, case when v_status in ('member', 'pending') then c.id end, c.title,
         private.active_member_count(c.id)
    from public.conversations c where c.id = v_id;
end;
$$;

-- Entrer (open) ou demander à entrer (approval). Renvoie joined / requested, ou la
-- situation qui l'empêche (invalid, member, pending, declined, full).
create or replace function public.join_group_by_code(p_code text)
returns table (status text, conversation_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid    uuid := private.require_active_user();
  v_id     uuid;
  v_status text;
  v_req    uuid;
  v_admin  uuid;
begin
  perform private.consume_rate_limit(v_uid, 'group_code',
    private.policy_int('group_code_hourly_limit'), interval '1 hour');
  v_id := private.group_of_code(p_code, v_uid);
  if v_id is null then
    return query select 'invalid'::text, null::uuid;
    return;
  end if;
  -- Verrou sur le groupe : deux entrées simultanées ne dépassent pas la limite.
  perform 1 from public.conversations c where c.id = v_id for update;
  v_status := private.join_status(v_id, v_uid);
  if v_status = 'open' then
    perform private.add_group_member(v_id, v_uid,
      (select i.inviter_id from private.group_invitations i
        where i.conversation_id = v_id and i.invitee_id = v_uid and i.status = 'pending'
          and i.expires_at > now() limit 1));
    return query select 'joined'::text, v_id;
    return;
  end if;
  if v_status <> 'approval' then
    return query select v_status, case when v_status in ('member', 'pending') then v_id end;
    return;
  end if;
  insert into private.group_join_requests (conversation_id, user_id, expires_at)
  values (v_id, v_uid, now() + make_interval(days => private.policy_int('group_invitation_ttl_days')))
  returning id into v_req;
  for v_admin in
    select m.user_id from public.conversation_members m
     where m.conversation_id = v_id and m.left_at is null and m.role in ('owner', 'admin')
  loop
    perform private.signal_user(v_admin, v_id, 'join_request');
  end loop;
  perform private.notify_join_request(v_req);
  return query select 'requested'::text, v_id;
end;
$$;

create or replace function public.cancel_join_request(p_conversation_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_active_user();
  v_admin uuid;
begin
  update private.group_join_requests set status = 'cancelled', decided_at = now()
   where conversation_id = p_conversation_id and user_id = v_uid and status = 'pending';
  if found then
    for v_admin in
      select m.user_id from public.conversation_members m
       where m.conversation_id = p_conversation_id and m.left_at is null and m.role in ('owner', 'admin')
    loop
      perform private.signal_user(v_admin, p_conversation_id, 'join_request');
    end loop;
  end if;
end;
$$;

-- Mes demandes en attente (onglet Groupes).
create or replace function public.list_my_join_requests()
returns table (conversation_id uuid, title text, created_at timestamptz, expires_at timestamptz)
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
  select c.id, c.title, r.created_at, r.expires_at
    from private.group_join_requests r
    join public.conversations c on c.id = r.conversation_id and c.posting <> 'closed'
   where r.user_id = v_uid and r.status = 'pending' and r.expires_at > now()
   order by r.created_at desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Demandes, côté administrateurs
-- ---------------------------------------------------------------------------
create or replace function public.list_group_join_requests(p_conversation_id uuid)
returns table (
  request_id    uuid,
  user_id       uuid,
  display_name  text,
  handle        text,
  created_at    timestamptz,
  was_removed   boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_group_role(p_conversation_id, array['owner', 'admin']);
begin
  return query
  select r.id, r.user_id, p.display_name, p.handle, r.created_at,
         exists (select 1 from private.group_removals g
                  where g.conversation_id = r.conversation_id and g.user_id = r.user_id)
    from private.group_join_requests r
    join public.profiles p on p.id = r.user_id and p.deleted_at is null
   where r.conversation_id = p_conversation_id and r.status = 'pending' and r.expires_at > now()
     and not private.is_blocked_between(v_uid, r.user_id)
   order by r.created_at;
end;
$$;

create or replace function public.respond_to_join_request(p_request_id uuid, p_approve boolean)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
    if private.active_member_count(v.conversation_id) >= private.policy_int('group_max_members') then
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
$$;

-- Retrait par un administrateur : inchangé, plus la trace (repasse par une demande).
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
  insert into private.group_removals (conversation_id, user_id) values (p_conversation_id, p_user_id)
  on conflict (conversation_id, user_id) do update set removed_at = now();
  perform private.signal_user(p_user_id, p_conversation_id, 'removed');
end;
$$;

-- ---------------------------------------------------------------------------
-- Notifications des demandes (sans contenu)
-- ---------------------------------------------------------------------------
create or replace function private.notify_join_request(p_request_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_url   text := (select s.value from private.runtime_settings s where s.key = 'functions_url');
  v_token text := (select s.value from private.runtime_settings s where s.key = 'push_dispatch_token');
begin
  if v_url is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
    using v_url || '/push-dispatch', jsonb_build_object('join_request_id', p_request_id),
          jsonb_build_object('Content-Type', 'application/json', 'x-privio-push', v_token), 10000;
end;
$$;

-- Pour push-dispatch : demande en attente → administrateurs (event join_request) ;
-- demande acceptée → la personne entrée (event join_approved). Jamais de nom.
create or replace function public.push_join_request_targets(p_token text, p_request_id uuid)
returns table (token text, event text, conversation_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  r private.group_join_requests%rowtype;
begin
  perform private.check_push_token(p_token);
  select * into r from private.group_join_requests g where g.id = p_request_id;
  if not found then
    return;
  end if;
  if r.status = 'pending' and r.expires_at > now() then
    return query
    select t.token, 'join_request'::text, r.conversation_id
      from public.conversation_members m
      join private.push_tokens t on t.user_id = m.user_id
      join public.devices d on d.id = t.device_id and d.revoked_at is null
     where m.conversation_id = r.conversation_id and m.left_at is null
       and m.role in ('owner', 'admin')
       and not private.is_blocked_between(m.user_id, r.user_id);
  elsif r.status = 'approved' and private.is_member(r.conversation_id, r.user_id) then
    return query
    select t.token, 'join_approved'::text, r.conversation_id
      from private.push_tokens t
      join public.devices d on d.id = t.device_id and d.revoked_at is null
     where t.user_id = r.user_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- @mentions
-- ---------------------------------------------------------------------------
drop function if exists public.send_message(uuid, uuid, text, uuid, integer);

-- Texte : inchangé, plus les personnes mentionnées (membres actifs du groupe seulement ;
-- les autres identifiants sont ignorés sans erreur).
create or replace function public.send_message(
  p_conversation_id uuid,
  p_client_msg_id   uuid,
  p_body            text,
  p_reply_to_id     uuid default null,
  p_ttl_seconds     integer default null,
  p_mentions        uuid[] default null
)
returns table (id uuid, sent_at timestamptz, expires_at timestamptz)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_member(p_conversation_id);
  v     public.messages%rowtype;
begin
  if coalesce(cardinality(p_mentions), 0) > 50 then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  v := private.post_message(v_uid, p_conversation_id, p_client_msg_id, 'text', p_body,
                            p_reply_to_id, p_ttl_seconds);
  if coalesce(cardinality(p_mentions), 0) > 0
     and exists (select 1 from public.conversations c where c.id = p_conversation_id and c.kind = 'group') then
    -- Même transaction que le message : les mentions sont lues par push-dispatch après
    -- validation (pg_net n'envoie qu'une fois la transaction terminée).
    insert into private.message_mentions (message_id, user_id)
    select distinct v.id, u
      from unnest(p_mentions) as u
     where u is not null and u <> v_uid and private.is_member(p_conversation_id, u)
    on conflict do nothing;
  end if;
  return query select v.id, v.sent_at, v.expires_at;
end;
$$;

-- Destinataires d'un message : inchangé, plus la colonne « mentioned ». Une personne
-- mentionnée est prévenue même si elle a mis le groupe en sourdine.
drop function if exists public.push_targets(text, uuid);

create or replace function public.push_targets(p_token text, p_message_id uuid)
returns table (token text, conversation_id uuid, is_group boolean, mentioned boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
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
  select t.token, v.conversation_id, c.kind = 'group', x.mentioned
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
     and (x.mentioned or m.muted_until is null or m.muted_until <= now())
     and (v.sender_id is null or not private.is_blocked_between(m.user_id, v.sender_id));
end;
$$;

-- Messages : inchangé (lot 4.5), plus les personnes mentionnées.
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
  media_height      integer,
  media_waveform    smallint[],
  mentions          uuid[]
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
         m.media_path, m.media_duration_ms, m.media_width, m.media_height, m.media_waveform,
         case when m.deleted_at is null then
           coalesce((select array_agg(mm.user_id order by mm.user_id)
                       from private.message_mentions mm where mm.message_id = m.id), '{}'::uuid[])
         else '{}'::uuid[] end
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
-- Nettoyage : demandes traitées après 30 jours, demandes échues après 1 jour.
-- ---------------------------------------------------------------------------
create or replace function private.purge_join_requests()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.group_join_requests
   where (status <> 'pending' and coalesce(decided_at, created_at) < now() - interval '30 days')
      or (status = 'pending' and expires_at < now() - interval '1 day');
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_purge_join_requests';
    perform cron.schedule('privio_purge_join_requests', '41 3 * * *', 'select private.purge_join_requests()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.get_group_invite_code(uuid) to authenticated;
grant execute on function public.reset_group_invite_code(uuid) to authenticated;
grant execute on function public.set_group_join_approval(uuid, boolean) to authenticated;
grant execute on function public.get_group_join_settings(uuid) to authenticated;
grant execute on function public.preview_group_by_code(text) to authenticated;
grant execute on function public.join_group_by_code(text) to authenticated;
grant execute on function public.cancel_join_request(uuid) to authenticated;
grant execute on function public.list_my_join_requests() to authenticated;
grant execute on function public.list_group_join_requests(uuid) to authenticated;
grant execute on function public.respond_to_join_request(uuid, boolean) to authenticated;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated;
grant execute on function public.send_message(uuid, uuid, text, uuid, integer, uuid[]) to authenticated;
grant execute on function public.get_messages(uuid, timestamptz, timestamptz, integer) to authenticated;
revoke all on function public.push_targets(text, uuid) from authenticated;
revoke all on function public.push_join_request_targets(text, uuid) from authenticated;
grant execute on function public.push_targets(text, uuid) to service_role;
grant execute on function public.push_join_request_targets(text, uuid) to service_role;
