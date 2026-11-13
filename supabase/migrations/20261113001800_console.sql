-- PRIVIO — lot 5.1 : console d'administration dans l'application (amendement 6).
--
-- - Accès réservé au compte dont le numéro VÉRIFIÉ est celui enregistré dans le réglage privé
--   `admin_phone_e164` (modifiable par déploiement, jamais écrit dans l'application).
--   Chaque fonction de la console le vérifie elle-même (session active comprise).
-- - Tableau de bord : des NOMBRES seulement. Aucun contenu, aucun nom, aucun numéro.
-- - Les messages s'effacent en 72 h au plus : l'activité (messages, vocaux, photos, groupes,
--   demandes, invitations) est donc comptée au fil de l'eau dans des compteurs journaliers
--   anonymes (`private.daily_stats`), à partir de ce déploiement.
-- - Chaque consultation est inscrite au journal de la console (`private.admin_audit`),
--   conservé `admin_audit_retention_days` jours (90 par défaut).
-- - Protection à l'ouverture (décision du 13/11/2026) : code Privio ou empreinte, côté
--   application ; la console se referme après 5 min sans action.

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------
insert into private.runtime_settings (key, value) values ('admin_phone_e164', '+22675493518')
on conflict (key) do nothing;

insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('admin_audit_retention_days', 'integer', '90', 30, 365, null, false, true,
   'Durée de conservation du journal des consultations et actions de la console (jours).')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Administrateur
-- ---------------------------------------------------------------------------
create or replace function private.is_console_admin(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_uid is not null and exists (
    select 1 from private.user_contacts c
     where c.user_id = p_uid
       and c.phone_e164 = (select s.value from private.runtime_settings s where s.key = 'admin_phone_e164'));
$$;

-- Session active ET compte administrateur ; sinon ADMIN_REQUIRED (même réponse pour tous).
create or replace function private.require_console_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  if not private.is_console_admin(v_uid) then
    raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
  end if;
  return v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Journal de la console
-- ---------------------------------------------------------------------------
create table private.admin_audit (
  id         bigint      generated always as identity primary key,
  admin_id   uuid        references auth.users (id) on delete set null,
  action     text        not null check (char_length(action) between 1 and 60),
  created_at timestamptz not null default now()
);
create index admin_audit_created_idx on private.admin_audit (created_at);
revoke all on private.admin_audit from public, anon, authenticated;

create or replace function private.admin_log(p_admin uuid, p_action text)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.admin_audit (admin_id, action) values (p_admin, p_action);
$$;

-- ---------------------------------------------------------------------------
-- Compteurs journaliers anonymes (aucun identifiant, aucun contenu)
-- ---------------------------------------------------------------------------
create table private.daily_stats (
  day    date   not null,
  metric text   not null,
  value  bigint not null default 0,
  primary key (day, metric)
);
revoke all on private.daily_stats from public, anon, authenticated;

create or replace function private.bump_stat(p_metric text)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.daily_stats (day, metric, value)
  values ((now() at time zone 'utc')::date, p_metric, 1)
  on conflict (day, metric) do update set value = private.daily_stats.value + 1;
$$;

create or replace function private.stats_on_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind <> 'system' then
    perform private.bump_stat('messages_' || new.kind);
  end if;
  return null;
end;
$$;
create trigger messages_stats after insert on public.messages
  for each row execute function private.stats_on_message();

create or replace function private.stats_on_conversation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.bump_stat(case when new.kind = 'group' then 'groups_created' else 'directs_created' end);
  return null;
end;
$$;
create trigger conversations_stats after insert on public.conversations
  for each row execute function private.stats_on_conversation();

create or replace function private.stats_on_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.bump_stat('group_invitations');
  return null;
end;
$$;
create trigger group_invitations_stats after insert on private.group_invitations
  for each row execute function private.stats_on_invitation();

create or replace function private.stats_on_connection_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.bump_stat('connection_requests');
  elsif new.status is distinct from old.status and new.status in ('accepted', 'refused') then
    perform private.bump_stat('connection_' || new.status);
  end if;
  return null;
end;
$$;
create trigger connection_requests_stats after insert or update of status on private.connection_requests
  for each row execute function private.stats_on_connection_request();

-- Nettoyage quotidien : journal de la console (90 jours par défaut), compteurs de plus de 400 jours.
create or replace function private.purge_console_data()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  delete from private.admin_audit
   where created_at < now() - make_interval(days => private.policy_int('admin_audit_retention_days'));
  delete from private.daily_stats where day < (now() at time zone 'utc')::date - 400;
end;
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_purge_console';
    perform cron.schedule('privio_purge_console', '29 3 * * *', 'select private.purge_console_data()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- API de la console
-- ---------------------------------------------------------------------------
-- L'application affiche l'entrée « Administration » seulement si vrai. Ne lève jamais
-- d'erreur et ne dit rien de plus (aucune indication sur le compte administrateur).
create or replace function public.console_access()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and private.session_is_active() and private.is_console_admin(auth.uid());
$$;

-- Dernier passage d'une tâche planifiée (pg_cron) : heure de fin et statut.
create or replace function private.cron_last_run(p_job text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if to_regclass('cron.job_run_details') is null then
    return null;
  end if;
  execute $q$
    select jsonb_build_object('at', d.end_time, 'status', d.status)
      from cron.job_run_details d join cron.job j on j.jobid = d.jobid
     where j.jobname = $1
     order by d.runid desc limit 1 $q$
    into v using p_job;
  return v;
end;
$$;

create or replace function public.console_dashboard()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_console_admin();
  v_today date := (now() at time zone 'utc')::date;
  v_since date := (select min(s.day) from private.daily_stats s);
  r       jsonb;
begin
  perform private.admin_log(v_uid, 'dashboard');

  with active as (
    select p.user_id, p.last_seen_at as seen from private.presence p
    union all
    select d.user_id, d.last_seen_at from public.devices d where d.revoked_at is null
  ), last_seen as (
    select a.user_id, max(a.seen) as seen from active a
      join public.profiles pr on pr.id = a.user_id and pr.deleted_at is null
     group by a.user_id
  ), stat as (
    select s.metric,
           coalesce(sum(s.value) filter (where s.day = v_today), 0)       as today,
           coalesce(sum(s.value) filter (where s.day > v_today - 7), 0)   as week
      from private.daily_stats s
     where s.day > v_today - 7
     group by s.metric
  ), push as (
    select coalesce(sum(l.sent), 0)                                 as sent,
           coalesce(sum(l.failed), 0)                               as failed,
           count(*) filter (where l.status = 'not_configured')      as not_configured
      from private.push_log l
     where l.created_at > now() - interval '24 hours'
  )
  select jsonb_build_object(
    'generated_at', now(),
    'counting_since', v_since,
    'accounts', jsonb_build_object(
      'total',     (select count(*) from public.profiles p where p.deleted_at is null),
      'active_24h', (select count(*) from last_seen l where l.seen > now() - interval '24 hours'),
      'active_7d',  (select count(*) from last_seen l where l.seen > now() - interval '7 days'),
      'new_7d',    (select count(*) from public.profiles p
                     where p.deleted_at is null and p.created_at > now() - interval '7 days')),
    'activity', jsonb_build_object(
      'messages_today', (select coalesce(sum(s.today), 0) from stat s where s.metric like 'messages\_%'),
      'messages_7d',    (select coalesce(sum(s.week), 0) from stat s where s.metric like 'messages\_%'),
      'voice_7d',       (select coalesce(sum(s.week), 0) from stat s where s.metric = 'messages_voice'),
      'photos_7d',      (select coalesce(sum(s.week), 0) from stat s where s.metric = 'messages_photo'),
      'messages_live',  (select count(*) from public.messages m where m.kind <> 'system')),
    'groups', jsonb_build_object(
      'total',               (select count(*) from public.conversations c where c.kind = 'group'),
      'created_7d',          (select coalesce(sum(s.week), 0) from stat s where s.metric = 'groups_created'),
      'invitations_pending', (select count(*) from private.group_invitations i
                               where i.status = 'pending' and i.expires_at > now()),
      'invitations_7d',      (select coalesce(sum(s.week), 0) from stat s where s.metric = 'group_invitations')),
    'requests', jsonb_build_object(
      'pending',     (select count(*) from private.connection_requests c
                       where c.status = 'pending' and c.expires_at > now()),
      'sent_7d',     (select coalesce(sum(s.week), 0) from stat s where s.metric = 'connection_requests'),
      'accepted_7d', (select coalesce(sum(s.week), 0) from stat s where s.metric = 'connection_accepted'),
      'refused_7d',  (select coalesce(sum(s.week), 0) from stat s where s.metric = 'connection_refused')),
    'health', jsonb_build_object(
      'push_sent_24h',           (select p.sent from push p),
      'push_failed_24h',         (select p.failed from push p),
      'push_not_configured_24h', (select p.not_configured from push p),
      'purge_messages_last',     private.cron_last_run('privio_purge_expired'),
      'purge_media_last',        private.cron_last_run('privio_media_purge'),
      'expired_waiting',         (select count(*) from public.messages m
                                   where m.expires_at < now() - interval '5 minutes'),
      'files_waiting',           (select count(*) from private.media_objects o where o.state = 'purge'),
      'storage_voice_bytes',     (select coalesce(sum(o.bytes), 0) from private.media_objects o
                                   where o.bucket = 'voice' and o.state in ('uploaded', 'attached')),
      'storage_photo_bytes',     (select coalesce(sum(o.bytes), 0) from private.media_objects o
                                   where o.bucket in ('photos', 'avatars') and o.state in ('uploaded', 'attached'))),
    'reports', jsonb_build_object(
      'open', (select count(*) from private.reports r where r.status = 'open'))
  ) into r;
  return r;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();

grant execute on function public.console_access() to authenticated;
grant execute on function public.console_dashboard() to authenticated;
