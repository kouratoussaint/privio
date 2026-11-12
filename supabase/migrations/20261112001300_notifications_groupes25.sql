-- PRIVIO — Migration 13
--   1. Décision B2 (12/11/2026) : 25 membres par groupe par défaut, réglable 2 à 100.
--   2. Lot 4.1 : notifications FCM SANS contenu.
--      * un jeton par appareil ACTIF (supprimé dès que l'appareil est révoqué) ;
--      * la base calcule les destinataires (jamais l'expéditeur, ni sourdine, ni blocage) ;
--      * la base appelle push-dispatch (pg_net) avec un jeton interne ; aucune donnée du
--        message ne quitte la base : ni texte, ni nom de l'expéditeur.

-- ---------------------------------------------------------------------------
-- 1. B2
-- ---------------------------------------------------------------------------
update private.policy_definitions
   set default_value = '25', min_value = 2, max_value = 100,
       description_fr = 'Nombre maximal de membres par groupe (décision B2 : 25 par défaut, réglable).'
 where key = 'group_max_members';

-- ---------------------------------------------------------------------------
-- 2. Jetons de notification
-- ---------------------------------------------------------------------------
insert into private.runtime_settings (key, value)
values ('push_dispatch_token',
        replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''))
on conflict (key) do nothing;

create table private.push_tokens (
  token      text        primary key check (char_length(token) between 20 and 4096),
  user_id    uuid        not null references auth.users (id) on delete cascade,
  device_id  uuid        not null references public.devices (id) on delete cascade,
  updated_at timestamptz not null default now()
);
create unique index push_tokens_one_per_device on private.push_tokens (device_id);

-- Journal d'envoi (sans contenu), conservé 7 jours : preuve de fonctionnement et diagnostic.
create table private.push_log (
  id          bigint      generated always as identity primary key,
  message_id  uuid        not null,
  recipients  integer     not null,
  sent        integer     not null default 0,
  failed      integer     not null default 0,
  status      text        not null,
  created_at  timestamptz not null default now()
);
create index push_log_message_idx on private.push_log (message_id);

-- Appareil actif courant (celui de la session du jeton).
create or replace function private.current_device_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select d.id from public.devices d
   where d.user_id = auth.uid()
     and d.session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid
     and d.revoked_at is null;
$$;

create or replace function public.register_push_token(p_token text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_active_user();
  v_device uuid := private.current_device_id();
begin
  if v_device is null then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  if p_token is null or char_length(p_token) not between 20 and 4096 then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  -- Un jeton ne sert qu'un appareil ; un appareil n'a qu'un jeton.
  delete from private.push_tokens where device_id = v_device and token <> p_token;
  insert into private.push_tokens (token, user_id, device_id) values (p_token, v_uid, v_device)
  on conflict (token) do update
    set user_id = excluded.user_id, device_id = excluded.device_id, updated_at = now();
end;
$$;

-- Notifications coupées par l'utilisateur, ou déconnexion.
create or replace function public.unregister_push_token()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  delete from private.push_tokens
   where user_id = v_uid and device_id = private.current_device_id();
end;
$$;

-- Appareil révoqué (nouvel appareil, déconnexion, admin) : plus aucune notification.
create or replace function private.drop_tokens_of_revoked_device()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.revoked_at is not null and old.revoked_at is null then
    delete from private.push_tokens where device_id = new.id;
  end if;
  return new;
end;
$$;

create trigger devices_drop_push_tokens after update of revoked_at on public.devices
  for each row execute function private.drop_tokens_of_revoked_device();

-- ---------------------------------------------------------------------------
-- 3. Destinataires et appel de push-dispatch
-- ---------------------------------------------------------------------------
create or replace function private.check_push_token(p_token text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_token is null or p_token is distinct from
     (select s.value from private.runtime_settings s where s.key = 'push_dispatch_token') then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
end;
$$;

-- Pour push-dispatch : jetons des destinataires d'un message (aucun contenu renvoyé).
create or replace function public.push_targets(p_token text, p_message_id uuid)
returns table (token text, conversation_id uuid, is_group boolean)
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
  select t.token, v.conversation_id, c.kind = 'group'
    from public.conversation_members m
    join public.conversations c on c.id = m.conversation_id
    join private.push_tokens t on t.user_id = m.user_id
    join public.devices d on d.id = t.device_id and d.revoked_at is null
   where m.conversation_id = v.conversation_id
     and m.left_at is null
     and m.user_id is distinct from v.sender_id
     and (m.muted_until is null or m.muted_until <= now())
     and (v.sender_id is null or not private.is_blocked_between(m.user_id, v.sender_id));
end;
$$;

-- Pour push-dispatch : compte rendu, et jetons refusés par FCM supprimés.
create or replace function public.push_report(
  p_token text, p_message_id uuid, p_recipients integer, p_sent integer, p_failed integer,
  p_status text, p_invalid_tokens text[] default '{}'
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.check_push_token(p_token);
  insert into private.push_log (message_id, recipients, sent, failed, status)
  values (p_message_id, coalesce(p_recipients, 0), coalesce(p_sent, 0), coalesce(p_failed, 0),
          left(coalesce(p_status, 'unknown'), 40));
  delete from private.push_tokens where token = any (coalesce(p_invalid_tokens, '{}'));
end;
$$;

-- Nouveau message : la base demande l'envoi des notifications (non bloquant).
create or replace function private.request_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url   text := (select s.value from private.runtime_settings s where s.key = 'functions_url');
  v_token text := (select s.value from private.runtime_settings s where s.key = 'push_dispatch_token');
begin
  if new.kind = 'system' then
    return new;
  end if;
  -- Personne à prévenir : aucun appel.
  if not exists (
    select 1 from public.conversation_members m
      join private.push_tokens t on t.user_id = m.user_id
     where m.conversation_id = new.conversation_id and m.left_at is null
       and m.user_id is distinct from new.sender_id) then
    return new;
  end if;
  if v_url is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    return new;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
    using v_url || '/push-dispatch', jsonb_build_object('message_id', new.id),
          jsonb_build_object('Content-Type', 'application/json', 'x-privio-push', v_token), 10000;
  return new;
end;
$$;

create trigger messages_request_push after insert on public.messages
  for each row execute function private.request_push();

-- Purge : + journal d'envoi de plus de 7 jours.
create or replace function private.purge_push_log()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.push_log where created_at < now() - interval '7 days';
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_purge_push_log';
    perform cron.schedule('privio_purge_push_log', '17 3 * * *', 'select private.purge_push_log()');
  end if;
end;
$$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.register_push_token(text) to authenticated;
grant execute on function public.unregister_push_token() to authenticated;
revoke all on function public.push_targets(text, uuid) from authenticated;
revoke all on function public.push_report(text, uuid, integer, integer, integer, text, text[]) from authenticated;
grant execute on function public.push_targets(text, uuid) to service_role;
grant execute on function public.push_report(text, uuid, integer, integer, integer, text, text[]) to service_role;
