-- PRIVIO — lot 9.4 : appels de groupe audio et vidéo (ADR-052, décisions du 17/11/2026).
--
-- Le son et l'image passent par le relais Cloudflare Realtime (SFU) : chaque téléphone
-- envoie une seule fois sa voix (et son image) au relais, qui la redistribue aux autres.
-- La base ne fait que la mise en relation : qui est dans l'appel, sessions et noms des
-- pistes au relais (pour que chacun reçoive celles des autres), micro et caméra, trace.
-- Aucun enregistrement, aucun contenu audio ou vidéo sur le serveur de Privio.
--
-- Règles (amendement 23) :
--   * groupe seulement ; lancé par tout membre qui peut écrire (groupe « Annonces » :
--     les administrateurs) ; tout membre du groupe peut rejoindre ;
--   * 8 participants au plus en même temps (GROUP_CALL_FULL) ;
--   * groupe de 16 membres ou moins : le téléphone des autres membres sonne (sauf
--     sourdine, « Recevoir des appels » coupé, blocage avec l'appelant) ; plus grand : une
--     notification neutre « Un appel de groupe a commencé » et un bandeau « Rejoindre » ;
--   * un seul appel de groupe en cours par groupe ; un seul appel à la fois par personne
--     (appel à deux ou appel de groupe) ;
--   * fin : quand plus personne n'est dans l'appel ; sonnerie sans réponse en 45 s ;
--     participant sans nouvelles pendant 40 s : sorti ;
--   * trace dans la discussion : {"e":"group_call","k":"audio","v":"ended:183"} (auteur :
--     la personne qui a lancé l'appel), ou « v »: « missed » si personne n'a rejoint.

create table private.group_calls (
  id              uuid        primary key default gen_random_uuid(),
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  started_by      uuid        not null references auth.users (id) on delete cascade,
  kind            text        not null default 'audio' check (kind in ('audio', 'video')),
  status          text        not null default 'active' check (status in ('active', 'ended')),
  rings           boolean     not null default false,
  created_at      timestamptz not null default now(),
  -- Quelqu'un d'autre que l'appelant a rejoint (appel « décroché »).
  answered_at     timestamptz,
  ended_at        timestamptz,
  peak            integer     not null default 1
);
create unique index group_calls_one_active on private.group_calls (conversation_id)
  where status = 'active';
create index group_calls_status_idx on private.group_calls (status, created_at);
revoke all on private.group_calls from public, anon, authenticated;

create table private.group_call_participants (
  call_id     uuid        not null references private.group_calls (id) on delete cascade,
  user_id     uuid        not null references auth.users (id) on delete cascade,
  state       text        not null check (state in ('ringing', 'joined', 'left', 'declined', 'missed')),
  rang_at     timestamptz,
  joined_at   timestamptz,
  left_at     timestamptz,
  seen_at     timestamptz not null default now(),
  -- Session au relais Cloudflare et noms des pistes publiées ({"audio": …, "video": …}).
  sfu_session text        check (sfu_session ~ '^[A-Za-z0-9_-]{1,128}$'),
  tracks      jsonb       not null default '{}'::jsonb check (octet_length(tracks::text) <= 512),
  camera      boolean     not null default false,
  muted       boolean     not null default false,
  primary key (call_id, user_id)
);
create index group_call_participants_user_idx on private.group_call_participants (user_id, state);
revoke all on private.group_call_participants from public, anon, authenticated;

-- Réglages de la console (lot 5.8) : mêmes interrupteurs que les appels à deux.
create trigger group_calls_feature_guard
  before insert on private.group_calls
  for each row execute function private.feature_guard_calls();

-- ---------------------------------------------------------------------------
-- Outils
-- ---------------------------------------------------------------------------
-- Signal « group_call » : à tous les membres du groupe (bandeau « Rejoindre ») ou aux seules
-- personnes de l'appel (micro, caméra, pistes).
create or replace function private.signal_group_call(p_call_id uuid, p_all boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r      record;
  v_conv uuid := (select g.conversation_id from private.group_calls g where g.id = p_call_id);
begin
  if v_conv is null or to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    return;
  end if;
  for r in
    select m.user_id from public.conversation_members m
     where m.conversation_id = v_conv and m.left_at is null
       and (p_all or exists (select 1 from private.group_call_participants p
                              where p.call_id = p_call_id and p.user_id = m.user_id
                                and p.state in ('ringing', 'joined')))
  loop
    execute 'select realtime.send($1, $2, $3, true)'
      using jsonb_build_object('conversation_id', v_conv, 'call_id', p_call_id),
            'group_call', 'user:' || r.user_id::text;
  end loop;
end;
$$;

-- Notification par push-dispatch : « ring » (sonnerie), « missed » (arrêt + « Appel de
-- groupe manqué »), « live » (« Un appel de groupe a commencé », grands groupes).
create or replace function private.notify_group_call(p_call_id uuid, p_event text, p_users uuid[])
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
  if v_url is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null
     or (p_users is not null and cardinality(p_users) = 0) then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
    using v_url || '/push-dispatch',
          jsonb_build_object('group_call_event', p_event, 'call_id', p_call_id,
                             'user_ids', coalesce(to_jsonb(p_users), '[]'::jsonb)),
          jsonb_build_object('Content-Type', 'application/json', 'x-privio-push', v_token), 10000;
end;
$$;

-- Déjà dans un appel (à deux, ou dans un autre appel de groupe) ?
create or replace function private.in_other_call(p_uid uuid, p_group_call uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.calls x
                  where x.status in ('ringing', 'accepted') and p_uid in (x.caller_id, x.callee_id))
      or exists (select 1 from private.group_call_participants p
                   join private.group_calls g on g.id = p.call_id and g.status = 'active'
                  where p.user_id = p_uid and p.state = 'joined'
                    and p.call_id is distinct from p_group_call);
$$;

create or replace function private.group_call_json(p_call_id uuid, p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', g.id, 'conversation_id', g.conversation_id, 'kind', g.kind, 'status', g.status,
    'started_by', g.started_by, 'rings', g.rings, 'created_at', g.created_at,
    'answered_at', g.answered_at, 'ended_at', g.ended_at,
    'my_state', (select p.state from private.group_call_participants p
                  where p.call_id = g.id and p.user_id = p_uid),
    'joined_count', (select count(*) from private.group_call_participants p
                      where p.call_id = g.id and p.state = 'joined'),
    'max', 8,
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', p.user_id, 'state', p.state,
               'name', pr.display_name,
               'avatar', private.avatar_for(pr.id, p_uid, pr.avatar_path),
               'camera', p.camera, 'muted', p.muted, 'joined_at', p.joined_at)
             -- Session et pistes : seulement pour les personnes dans l'appel.
             || case when me.state = 'joined' and p.state = 'joined'
                     then jsonb_build_object('session', p.sfu_session, 'tracks', p.tracks)
                     else '{}'::jsonb end
             order by p.joined_at nulls last, p.rang_at)
        from private.group_call_participants p
        join public.profiles pr on pr.id = p.user_id
       where p.call_id = g.id
         and (p.state = 'joined'
              -- Groupe « Annonces » : qui sonne reste caché aux simples membres.
              or (p.state = 'ringing' and not private.hides_members(g.conversation_id, p_uid)))),
      '[]'::jsonb))
    from private.group_calls g
    left join private.group_call_participants me on me.call_id = g.id and me.user_id = p_uid
   where g.id = p_call_id;
$$;

-- Appel de groupe visible par un membre du groupe (verrouillé pour mise à jour).
create or replace function private.require_group_call(p_call_id uuid)
returns private.group_calls
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  g     private.group_calls%rowtype;
begin
  select * into g from private.group_calls x where x.id = p_call_id for update;
  if not found or not private.is_member(g.conversation_id, v_uid) then
    raise exception 'CALL_NOT_FOUND' using errcode = 'P0001';
  end if;
  return g;
end;
$$;

-- Fin de l'appel : sonneries arrêtées (« manqué »), trace, signal à tout le groupe.
create or replace function private.finish_group_call(p_call_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  g      private.group_calls%rowtype;
  v_miss uuid[];
  v_ttl  integer;
  v_at   timestamptz := clock_timestamp();
  v_val  text;
begin
  update private.group_calls set status = 'ended', ended_at = now()
   where id = p_call_id and status = 'active'
  returning * into g;
  if not found then
    return;
  end if;
  with m as (
    update private.group_call_participants set state = 'missed'
     where call_id = g.id and state = 'ringing'
    returning user_id)
  select coalesce(array_agg(user_id), '{}') into v_miss from m;
  update private.group_call_participants
     set state = 'left', left_at = coalesce(left_at, now()), sfu_session = null, tracks = '{}'
   where call_id = g.id and state = 'joined';
  v_ttl := private.effective_ttl(g.conversation_id);
  v_val := case when g.answered_at is null then 'missed'
                else 'ended:' || greatest(0, extract(epoch from (g.ended_at - g.created_at))::int) end;
  insert into public.messages (conversation_id, sender_id, client_msg_id, kind, body, sent_at, expires_at)
  values (g.conversation_id, g.started_by, gen_random_uuid(), 'system',
          jsonb_build_object('e', 'group_call', 'k', g.kind, 'v', v_val)::text, v_at,
          v_at + make_interval(secs => v_ttl));
  update public.conversations set last_message_at = v_at where id = g.conversation_id;
  perform private.signal_members(g.conversation_id, 'message');
  perform private.signal_group_call(g.id, true);
  perform private.notify_group_call(g.id, 'missed', v_miss);
end;
$$;

-- Sonnerie sans réponse (45 s) : manqué ; participant sans nouvelles (40 s) : sorti ;
-- plus personne dans l'appel : fin.
create or replace function private.expire_group_calls()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r      record;
  v_n    integer := 0;
  v_miss uuid[];
begin
  for r in
    select g.id from private.group_calls g where g.status = 'active'
     for update skip locked
  loop
    with m as (
      update private.group_call_participants set state = 'missed'
       where call_id = r.id and state = 'ringing' and rang_at < now() - interval '45 seconds'
      returning user_id)
    select coalesce(array_agg(user_id), '{}') into v_miss from m;
    if cardinality(v_miss) > 0 then
      perform private.notify_group_call(r.id, 'missed', v_miss);
      perform private.signal_group_call(r.id, false);
    end if;
    update private.group_call_participants
       set state = 'left', left_at = now(), sfu_session = null, tracks = '{}'
     where call_id = r.id and state = 'joined' and seen_at < now() - interval '40 seconds';
    if found then
      perform private.signal_group_call(r.id, true);
    end if;
    if not exists (select 1 from private.group_call_participants p
                    where p.call_id = r.id and p.state = 'joined') then
      perform private.finish_group_call(r.id);
      v_n := v_n + 1;
    end if;
  end loop;
  -- Appels terminés : gardés 7 jours (diagnostic), sans contenu.
  delete from private.group_calls where status = 'ended' and created_at < now() - interval '7 days';
  return v_n;
end;
$$;

-- Rejoindre (interne) : place libre, un seul appel à la fois.
create or replace function private.join_group_call_as(g private.group_calls, p_uid uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_state text := (select p.state from private.group_call_participants p
                    where p.call_id = g.id and p.user_id = p_uid);
  v_count integer;
begin
  if g.status <> 'active' then
    raise exception 'CALL_ENDED' using errcode = 'P0001';
  end if;
  if v_state = 'joined' then
    update private.group_call_participants set seen_at = now()
     where call_id = g.id and user_id = p_uid;
    return;
  end if;
  if private.in_other_call(p_uid, g.id) then
    raise exception 'CALL_ALREADY_ACTIVE' using errcode = 'P0001';
  end if;
  select count(*) into v_count from private.group_call_participants p
   where p.call_id = g.id and p.state = 'joined';
  if v_count >= 8 then
    raise exception 'GROUP_CALL_FULL' using errcode = 'P0001';
  end if;
  insert into private.group_call_participants (call_id, user_id, state, joined_at, seen_at)
  values (g.id, p_uid, 'joined', now(), now())
  on conflict (call_id, user_id) do update
    set state = 'joined', joined_at = now(), left_at = null, seen_at = now(),
        sfu_session = null, tracks = '{}', camera = false, muted = false;
  update private.group_calls
     set peak = greatest(peak, v_count + 1),
         answered_at = case when p_uid <> started_by then coalesce(answered_at, now()) else answered_at end
   where id = g.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lancer, rejoindre, refuser, quitter
-- ---------------------------------------------------------------------------
create or replace function public.start_group_call(p_conversation_id uuid, p_kind text default 'audio')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := private.require_member(p_conversation_id);
  g         private.group_calls%rowtype;
  v_members integer;
  v_ring    uuid[];
begin
  if p_kind not in ('audio', 'video') then
    raise exception 'CALL_KIND_UNAVAILABLE' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.conversations x where x.id = p_conversation_id and x.kind = 'group') then
    raise exception 'GROUP_CALL_GROUP_ONLY' using errcode = 'P0001';
  end if;
  -- Groupe fermé, ou réservé aux administrateurs (dont « Annonces ») : POSTING_RESTRICTED.
  perform private.check_can_post(p_conversation_id, v_uid);
  perform private.expire_calls();
  perform private.expire_group_calls();
  perform pg_advisory_xact_lock(hashtextextended('group_call:' || p_conversation_id::text, 0));
  -- Un appel est déjà en cours dans ce groupe : on le rejoint.
  select * into g from private.group_calls x
   where x.conversation_id = p_conversation_id and x.status = 'active' for update;
  if found then
    perform private.join_group_call_as(g, v_uid);
    perform private.signal_group_call(g.id, true);
    return private.group_call_json(g.id, v_uid) || jsonb_build_object('existing', true);
  end if;
  if private.in_other_call(v_uid, null) then
    raise exception 'CALL_ALREADY_ACTIVE' using errcode = 'P0001';
  end if;
  select count(*) into v_members from public.conversation_members m
   where m.conversation_id = p_conversation_id and m.left_at is null;
  insert into private.group_calls (conversation_id, started_by, kind, rings)
  values (p_conversation_id, v_uid, p_kind, v_members <= 16)
  returning * into g;
  insert into private.group_call_participants (call_id, user_id, state, joined_at, seen_at)
  values (g.id, v_uid, 'joined', now(), now());
  if g.rings then
    -- Sonnerie : membres actifs, ni sourdine, ni appels coupés, ni blocage avec l'appelant.
    with r as (
      insert into private.group_call_participants (call_id, user_id, state, rang_at)
      select g.id, m.user_id, 'ringing', now()
        from public.conversation_members m
        join public.profiles pr on pr.id = m.user_id and pr.deleted_at is null
       where m.conversation_id = p_conversation_id and m.left_at is null and m.user_id <> v_uid
         and (m.muted_until is null or m.muted_until <= now())
         and coalesce((select s.accept_calls from private.call_settings s where s.user_id = m.user_id), true)
         and not private.is_blocked_between(m.user_id, v_uid)
      returning user_id)
    select coalesce(array_agg(user_id), '{}') into v_ring from r;
    perform private.notify_group_call(g.id, 'ring', v_ring);
  else
    perform private.notify_group_call(g.id, 'live', null);
  end if;
  perform private.signal_group_call(g.id, true);
  return private.group_call_json(g.id, v_uid) || jsonb_build_object('existing', false);
end;
$$;

create or replace function public.join_group_call(p_call_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  g private.group_calls%rowtype;
begin
  perform private.expire_calls();
  perform private.expire_group_calls();
  g := private.require_group_call(p_call_id);
  perform private.join_group_call_as(g, auth.uid());
  perform private.signal_group_call(g.id, true);
  return private.group_call_json(g.id, auth.uid());
end;
$$;

create or replace function public.decline_group_call(p_call_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  g private.group_calls%rowtype := private.require_group_call(p_call_id);
begin
  update private.group_call_participants set state = 'declined'
   where call_id = g.id and user_id = auth.uid() and state = 'ringing';
  if found then
    perform private.signal_group_call(g.id, false);
  end if;
  return private.group_call_json(g.id, auth.uid());
end;
$$;

create or replace function public.leave_group_call(p_call_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  g private.group_calls%rowtype := private.require_group_call(p_call_id);
begin
  update private.group_call_participants
     set state = 'left', left_at = now(), sfu_session = null, tracks = '{}'
   where call_id = g.id and user_id = auth.uid() and state = 'joined';
  if found then
    if not exists (select 1 from private.group_call_participants p
                    where p.call_id = g.id and p.state = 'joined') then
      perform private.finish_group_call(g.id);
    else
      perform private.signal_group_call(g.id, true);
    end if;
  end if;
  return private.group_call_json(g.id, auth.uid());
end;
$$;

-- État de l'appel ; pour une personne dans l'appel, sert aussi de présence (toutes les 4 s).
create or replace function public.group_call_state(p_call_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  g private.group_calls%rowtype;
begin
  perform private.expire_group_calls();
  g := private.require_group_call(p_call_id);
  update private.group_call_participants set seen_at = now()
   where call_id = g.id and user_id = auth.uid() and state = 'joined';
  return private.group_call_json(g.id, auth.uid());
end;
$$;

-- Micro coupé, caméra allumée : affichés aux autres personnes de l'appel.
create or replace function public.set_group_call_media(p_call_id uuid, p_camera boolean, p_muted boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  g private.group_calls%rowtype := private.require_group_call(p_call_id);
begin
  update private.group_call_participants
     set camera = coalesce(p_camera, camera), muted = coalesce(p_muted, muted), seen_at = now()
   where call_id = g.id and user_id = auth.uid() and state = 'joined';
  if not found then
    raise exception 'CALL_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.signal_group_call(g.id, false);
  return private.group_call_json(g.id, auth.uid());
end;
$$;

-- Appels de groupe en cours dans mes groupes (bandeaux, retour dans l'application) et
-- appel qui me fait sonner.
create or replace function public.my_group_calls()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  perform private.expire_group_calls();
  return coalesce((
    select jsonb_agg(private.group_call_json(g.id, v_uid) order by g.created_at desc)
      from private.group_calls g
      join public.conversation_members m
        on m.conversation_id = g.conversation_id and m.user_id = v_uid and m.left_at is null
     where g.status = 'active'), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- Relais Cloudflare (fonction call-sfu)
-- ---------------------------------------------------------------------------
-- Vérification sous le jeton de l'utilisateur : il est dans l'appel ; les sessions dont il
-- veut recevoir les pistes sont celles d'autres personnes du même appel. Renvoie sa session.
create or replace function public.group_call_sfu(p_call_id uuid, p_sessions text[] default '{}')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  v_me  private.group_call_participants%rowtype;
begin
  select p.* into v_me from private.group_call_participants p
    join private.group_calls g on g.id = p.call_id and g.status = 'active'
   where p.call_id = p_call_id and p.user_id = v_uid and p.state = 'joined';
  if not found then
    raise exception 'CALL_NOT_FOUND' using errcode = 'P0001';
  end if;
  if exists (select 1 from unnest(coalesce(p_sessions, '{}')) s
              where not exists (select 1 from private.group_call_participants p
                                 where p.call_id = p_call_id and p.state = 'joined'
                                   and p.user_id <> v_uid and p.sfu_session = s)) then
    raise exception 'SFU_FORBIDDEN' using errcode = 'P0001';
  end if;
  update private.group_call_participants set seen_at = now()
   where call_id = p_call_id and user_id = v_uid;
  return jsonb_build_object('session', v_me.sfu_session, 'user_id', v_uid);
end;
$$;

-- Enregistrement de la session et des pistes publiées (réservé à la fonction call-sfu, après
-- réponse du relais). Une nouvelle session efface les pistes de l'ancienne.
create or replace function public.group_call_set_sfu(p_user_id uuid, p_call_id uuid,
                                                     p_session text, p_tracks jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tracks jsonb := coalesce(p_tracks, '{}'::jsonb);
begin
  if jsonb_typeof(v_tracks) <> 'object'
     or exists (select 1 from jsonb_each(v_tracks) e
                 where e.key not in ('audio', 'video') or jsonb_typeof(e.value) <> 'string'
                    or (e.value #>> '{}') !~ '^[A-Za-z0-9_-]{1,64}$') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  update private.group_call_participants
     set tracks = case when sfu_session is distinct from p_session then v_tracks
                       else tracks || v_tracks end,
         sfu_session = p_session, seen_at = now()
   where call_id = p_call_id and user_id = p_user_id and state = 'joined';
  if not found then
    raise exception 'CALL_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.signal_group_call(p_call_id, false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Notifications (réservé à push-dispatch)
-- ---------------------------------------------------------------------------
create or replace function public.push_group_call_targets(p_token text, p_call_id uuid, p_event text,
                                                          p_users uuid[])
returns table (token text, conversation_id uuid, created_at timestamptz, kind text, secret boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.check_push_token(p_token);
  if p_event in ('ring', 'missed') then
    return query
    select t.token, g.conversation_id, g.created_at, g.kind, m.secret_at is not null
      from private.group_calls g
      join private.group_call_participants p on p.call_id = g.id
      join private.push_tokens t on t.user_id = p.user_id
      join public.devices d on d.id = t.device_id and d.revoked_at is null
      join public.conversation_members m
        on m.conversation_id = g.conversation_id and m.user_id = p.user_id and m.left_at is null
     where g.id = p_call_id
       and p.user_id = any (coalesce(p_users, '{}'))
       and ((p_event = 'ring' and g.status = 'active' and p.state = 'ringing')
         or (p_event = 'missed' and p.state = 'missed'));
  elsif p_event = 'live' then
    return query
    select t.token, g.conversation_id, g.created_at, g.kind, m.secret_at is not null
      from private.group_calls g
      join public.conversation_members m on m.conversation_id = g.conversation_id and m.left_at is null
      join private.push_tokens t on t.user_id = m.user_id
      join public.devices d on d.id = t.device_id and d.revoked_at is null
     where g.id = p_call_id and g.status = 'active'
       and m.user_id <> g.started_by
       and (m.muted_until is null or m.muted_until <= now()) and m.notify_mode = 'all'
       and not private.is_blocked_between(m.user_id, g.started_by);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Appels à deux : une personne dans un appel de groupe est « occupée », et ne peut pas
-- appeler ; le relais réseau sert aussi pendant un appel de groupe.
-- ---------------------------------------------------------------------------
create or replace function public.start_call(p_conversation_id uuid, p_kind text default 'audio')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_peer uuid;
  c      private.calls%rowtype;
begin
  if p_kind not in ('audio', 'video') then
    raise exception 'CALL_KIND_UNAVAILABLE' using errcode = 'P0001';
  end if;
  perform private.require_member(p_conversation_id);
  if not exists (select 1 from public.conversations x where x.id = p_conversation_id and x.kind = 'direct') then
    raise exception 'CALL_DIRECT_ONLY' using errcode = 'P0001';
  end if;
  select m.user_id into v_peer from public.conversation_members m
   where m.conversation_id = p_conversation_id and m.user_id <> v_uid and m.left_at is null;
  if v_peer is null or exists (select 1 from public.profiles p where p.id = v_peer and p.deleted_at is not null) then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if private.is_blocked_between(v_uid, v_peer) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;
  if not coalesce((select s.accept_calls from private.call_settings s where s.user_id = v_peer), true) then
    raise exception 'CALLS_DISABLED' using errcode = 'P0001';
  end if;
  perform private.expire_calls();
  perform private.expire_group_calls();
  -- Sérialise les appels vers une même personne.
  perform pg_advisory_xact_lock(hashtextextended('call:' || least(v_uid, v_peer)::text, 0));
  if exists (select 1 from private.calls x where x.status in ('ringing', 'accepted')
              and v_uid in (x.caller_id, x.callee_id))
     or private.in_other_call(v_uid, null) then
    raise exception 'CALL_ALREADY_ACTIVE' using errcode = 'P0001';
  end if;
  insert into private.calls (conversation_id, caller_id, callee_id, kind)
  values (p_conversation_id, v_uid, v_peer, p_kind)
  returning * into c;
  -- Correspondant déjà en appel (à deux, ou lot 9.4 : de groupe) : « occupé ».
  if exists (select 1 from private.calls x where x.id <> c.id and x.status in ('ringing', 'accepted')
              and v_peer in (x.caller_id, x.callee_id))
     or exists (select 1 from private.group_call_participants p
                  join private.group_calls g on g.id = p.call_id and g.status = 'active'
                 where p.user_id = v_peer and p.state = 'joined') then
    c := private.finish_call(c.id, 'missed', 'busy');
    return private.call_json(c, v_uid);
  end if;
  perform private.signal_call(v_peer, c);
  -- Lot 9.1b : réveille le téléphone de l'appelé (application fermée ou en arrière-plan).
  perform private.notify_call(c.id, 'ring');
  return private.call_json(c, v_uid);
end;
$$;

create or replace function public.can_use_call_relay()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  return exists (select 1 from private.calls x where x.status in ('ringing', 'accepted')
                  and v_uid in (x.caller_id, x.callee_id))
      or exists (select 1 from private.group_call_participants p
                   join private.group_calls g on g.id = p.call_id and g.status = 'active'
                  where p.user_id = v_uid and p.state in ('ringing', 'joined'));
end;
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_expire_group_calls';
    perform cron.schedule('privio_expire_group_calls', '* * * * *', 'select private.expire_group_calls()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.start_group_call(uuid, text) to authenticated;
grant execute on function public.join_group_call(uuid) to authenticated;
grant execute on function public.decline_group_call(uuid) to authenticated;
grant execute on function public.leave_group_call(uuid) to authenticated;
grant execute on function public.group_call_state(uuid) to authenticated;
grant execute on function public.set_group_call_media(uuid, boolean, boolean) to authenticated;
grant execute on function public.my_group_calls() to authenticated;
grant execute on function public.group_call_sfu(uuid, text[]) to authenticated;
grant execute on function public.start_call(uuid, text) to authenticated;
grant execute on function public.can_use_call_relay() to authenticated;
revoke all on function public.group_call_set_sfu(uuid, uuid, text, jsonb) from authenticated;
revoke all on function public.push_group_call_targets(text, uuid, text, uuid[]) from authenticated;
grant execute on function public.group_call_set_sfu(uuid, uuid, text, jsonb) to service_role;
grant execute on function public.push_group_call_targets(text, uuid, text, uuid[]) to service_role;
