-- PRIVIO — lot 8.4b : rappel avant effacement (décisions du 15/11/2026 : 4 h avant,
-- messages de 12 h ou plus, activé par défaut).
--
-- Toutes les 10 minutes : pour chaque membre qui a, dans une discussion, des messages NON
-- LUS reçus d'autres personnes, d'une durée de 12 h ou plus, qui s'effacent dans moins de
-- 4 h, une notification SANS CONTENU (« Des messages non lus vont bientôt s'effacer »).
-- Au plus une par discussion et par 12 h. Respecte la sourdine, « Mentions seulement »,
-- les blocages et le réglage « Rappel avant effacement ».

create table private.reminder_settings (
  user_id         uuid        primary key references auth.users (id) on delete cascade,
  expiry_reminder boolean     not null default true,
  updated_at      timestamptz not null default now()
);
revoke all on private.reminder_settings from public, anon, authenticated;

create table private.expiry_reminders (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references auth.users (id) on delete cascade,
  conversation_id uuid        not null references public.conversations (id) on delete cascade,
  created_at      timestamptz not null default now()
);
create index expiry_reminders_user_conv_idx on private.expiry_reminders (user_id, conversation_id, created_at);
revoke all on private.expiry_reminders from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Réglage
-- ---------------------------------------------------------------------------
create or replace function public.get_expiry_reminder()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  return coalesce((select s.expiry_reminder from private.reminder_settings s where s.user_id = v_uid), true);
end;
$$;

create or replace function public.set_expiry_reminder(p_on boolean)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  if p_on is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  insert into private.reminder_settings (user_id, expiry_reminder) values (v_uid, p_on)
  on conflict (user_id) do update set expiry_reminder = excluded.expiry_reminder, updated_at = now();
  return p_on;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tâche : repérer les rappels à envoyer et les confier à push-dispatch
-- ---------------------------------------------------------------------------
create or replace function private.expiry_reminder_candidates()
returns table (user_id uuid, conversation_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct m.user_id, m.conversation_id
    from public.conversation_members m
    join public.messages x on x.conversation_id = m.conversation_id
   where m.left_at is null
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
$$;

create or replace function private.send_expiry_reminders()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_url   text := (select s.value from private.runtime_settings s where s.key = 'functions_url');
  v_token text := (select s.value from private.runtime_settings s where s.key = 'push_dispatch_token');
  v_net   boolean := to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null;
  r       record;
  v_id    uuid;
  v_n     integer := 0;
begin
  delete from private.expiry_reminders where created_at < now() - interval '7 days';
  for r in select * from private.expiry_reminder_candidates() loop
    insert into private.expiry_reminders (user_id, conversation_id)
    values (r.user_id, r.conversation_id)
    returning id into v_id;
    v_n := v_n + 1;
    if v_url is not null and v_net then
      execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
        using v_url || '/push-dispatch', jsonb_build_object('expiry_reminder_id', v_id),
              jsonb_build_object('Content-Type', 'application/json', 'x-privio-push', v_token), 10000;
    end if;
  end loop;
  return v_n;
end;
$$;

-- Jetons à notifier (réservé à push-dispatch) : appareils actifs de la personne.
create or replace function public.push_expiry_reminder_targets(p_token text, p_reminder_id uuid)
returns table (token text, conversation_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.check_push_token(p_token);
  return query
  select t.token, r.conversation_id
    from private.expiry_reminders r
    join private.push_tokens t on t.user_id = r.user_id
    join public.devices d on d.id = t.device_id and d.revoked_at is null
   where r.id = p_reminder_id and r.created_at > now() - interval '1 hour';
end;
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_expiry_reminders';
    perform cron.schedule('privio_expiry_reminders', '*/10 * * * *',
                          'select private.send_expiry_reminders()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.get_expiry_reminder() to authenticated;
grant execute on function public.set_expiry_reminder(boolean) to authenticated;
revoke all on function public.push_expiry_reminder_targets(text, uuid) from authenticated;
grant execute on function public.push_expiry_reminder_targets(text, uuid) to service_role;
