-- PRIVIO — lot 5.7 : santé du service (ADR-047, décisions du 17/11/2026).
--
-- A Versions : « version conseillée » (bandeau « Mise à jour disponible ») et « version
--   minimale » (écran bloquant), comparées au numéro de compilation (après le « + ») ;
--   lien de téléchargement réglable dans la console.
-- B Alertes de l'administration par notification, sans contenu, au plus une par type
--   toutes les 6 h : effacements automatiques en retard, pic de codes SMS, échecs de
--   notifications ou d'appels, relais des appels au-delà de 80 % du volume gratuit.
-- C Parcours d'inscription compté par le serveur : codes SMS envoyés (connexion et
--   changement de numéro), codes vérifiés, profils créés ; coût estimé = codes × prix.
-- Santé des appels : chaque téléphone signale à la fin d'un appel décroché s'il passait
-- par le relais et le volume échangé. Diagnostics : notification de test, test du relais
-- (fonction call-ice), état des tâches automatiques.
-- Aucun numéro, aucun contenu : des compteurs et des horodatages seulement.

-- ---------------------------------------------------------------------------
-- 1. Réglages (thème « health », affichés dans la rubrique Santé de la console)
-- ---------------------------------------------------------------------------
insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, client_visible, implemented, description_fr,
   category, label_fr, unit, admin_locked, advanced, sort_order, effect_fr)
values
  ('app_recommended_build', 'integer', '0', 0, 1000000, true, true,
   'Version conseillée de l’application (numéro de compilation).',
   'health', 'Version conseillée', 'build', false, false, 10,
   'En dessous : bandeau « Mise à jour disponible » en haut des listes, que la personne peut fermer. 0 : aucun bandeau.'),
  ('app_min_build', 'integer', '0', 0, 1000000, true, true,
   'Version minimale de l’application (numéro de compilation).',
   'health', 'Version minimale', 'build', false, false, 20,
   'En dessous : écran « Mettez Privio à jour », l’application ne s’utilise plus avant la mise à jour. 0 : aucun blocage.'),
  ('app_update_url', 'string', '""', null, null, true, true,
   'Lien de téléchargement de la nouvelle version.',
   'health', 'Lien de mise à jour', 'text', false, false, 30,
   'Ouvert par le bouton « Mettre à jour ». Vide : la personne est invitée à demander la nouvelle version à l’équipe Privio.'),
  ('sms_unit_cost', 'integer', '0', 0, 10000, false, true,
   'Prix d’un SMS de code, en FCFA (estimation du coût dans la console).',
   'health', 'Prix d’un SMS', 'fcfa', false, false, 40,
   'Sert seulement à estimer le coût des codes dans la console.'),
  ('health_alerts_enabled', 'boolean', 'true', null, null, false, true,
   'Alertes de l’administration par notification.',
   'health', 'Alertes par notification', 'bool', false, false, 50,
   'Activées : une notification sans contenu quand un problème est détecté, au plus une par type toutes les 6 h.'),
  ('sms_alert_per_hour', 'integer', '30', 5, 10000, false, true,
   'Seuil d’alerte : codes SMS demandés en une heure.',
   'health', 'Alerte codes SMS (par heure)', 'nb', false, false, 60,
   'Alerte au-delà de ce nombre de codes en une heure, ou de 3 fois la moyenne des 7 derniers jours si elle est plus haute.')
on conflict (key) do nothing;

-- Lien de mise à jour : vide ou https, 300 caractères au plus.
create or replace function private.check_update_url()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v text;
begin
  if new.key = 'app_update_url' then
    v := new.value #>> '{}';
    if char_length(v) > 300 or (v <> '' and v !~ '^https://[^[:space:]]+$') then
      raise exception 'POLICY_OUT_OF_BOUNDS' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;
create trigger policies_update_url
  before insert or update on private.policies
  for each row execute function private.check_update_url();

-- Numéro de compilation d'une version « 0.1.0+69 » (null si illisible).
create or replace function private.build_of(p_version text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when split_part(coalesce(p_version, ''), '+', 2) ~ '^[0-9]{1,9}$'
              then split_part(p_version, '+', 2)::integer end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Parcours d'inscription : codes SMS envoyés et vérifiés (sans numéro)
-- ---------------------------------------------------------------------------
create table private.sms_log (
  id         bigint      generated always as identity primary key,
  kind       text        not null check (kind in ('code', 'verified')),
  purpose    text        not null check (purpose in ('login', 'phone_change')),
  created_at timestamptz not null default now()
);
create index sms_log_created_idx on private.sms_log (created_at);
revoke all on private.sms_log from public, anon, authenticated;

-- Auth enregistre l'heure de chaque code envoyé : confirmation (nouveau numéro),
-- recovery (numéro déjà inscrit), phone_change (changement de numéro). Une connexion
-- réussie met à jour last_sign_in_at ; on ne la compte que si un code a été envoyé dans
-- l'heure (les rafraîchissements de session ne sont pas des vérifications).
create or replace function private.track_sms()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.confirmation_sent_at is not null or new.recovery_sent_at is not null then
      insert into private.sms_log (kind, purpose) values ('code', 'login');
    end if;
    return null;
  end if;
  if (new.confirmation_sent_at is not null
      and new.confirmation_sent_at is distinct from old.confirmation_sent_at)
     or (new.recovery_sent_at is not null and new.recovery_sent_at is distinct from old.recovery_sent_at) then
    insert into private.sms_log (kind, purpose) values ('code', 'login');
  end if;
  if new.phone_change_sent_at is not null and new.phone_change_sent_at is distinct from old.phone_change_sent_at then
    insert into private.sms_log (kind, purpose) values ('code', 'phone_change');
  end if;
  if new.last_sign_in_at is not null and new.last_sign_in_at is distinct from old.last_sign_in_at
     and greatest(new.confirmation_sent_at, new.recovery_sent_at) > now() - interval '1 hour' then
    insert into private.sms_log (kind, purpose) values ('verified', 'login');
  end if;
  if old.phone is not null and new.phone is not null and new.phone is distinct from old.phone then
    insert into private.sms_log (kind, purpose) values ('verified', 'phone_change');
  end if;
  return null;
end;
$$;
create trigger on_auth_user_sms_stats
  after insert or update of confirmation_sent_at, recovery_sent_at, phone_change_sent_at, last_sign_in_at, phone
  on auth.users
  for each row execute function private.track_sms();

-- Profils créés (dernière étape du parcours), au fil de l'eau.
create or replace function private.stats_on_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.bump_stat('signup_profiles');
  return null;
end;
$$;
create trigger profiles_signup_stats after insert on public.profiles
  for each row execute function private.stats_on_profile();

-- ---------------------------------------------------------------------------
-- 3. Santé des appels
-- ---------------------------------------------------------------------------
-- Issue de chaque appel, comptée une fois quand il se termine (les appels sont effacés
-- après 7 jours ; les compteurs journaliers restent).
create or replace function private.stats_on_call()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status in ('ringing', 'accepted') and new.status not in ('ringing', 'accepted') then
    perform private.bump_stat('calls_' || new.kind);
    if coalesce(new.end_reason, '') in ('failed', 'lost') then
      perform private.bump_stat('calls_failed');
    elsif new.answered_at is not null then
      perform private.bump_stat('calls_ok');
      perform private.add_stat('calls_seconds',
        greatest(0, extract(epoch from coalesce(new.ended_at, now()) - new.answered_at))::bigint);
    else
      perform private.bump_stat('calls_unanswered');
    end if;
  end if;
  return null;
end;
$$;
create trigger calls_stats after update of status on private.calls
  for each row execute function private.stats_on_call();

-- Compte rendu d'un téléphone à la fin d'un appel décroché : relais ou non, octets échangés.
create table private.call_reports (
  call_id    uuid        not null references private.calls (id) on delete cascade,
  user_id    uuid        not null references auth.users (id) on delete cascade,
  relayed    boolean     not null,
  bytes      bigint      not null check (bytes >= 0),
  created_at timestamptz not null default now(),
  primary key (call_id, user_id)
);
revoke all on private.call_reports from public, anon, authenticated;

-- Le volume passé par le relais est estimé par le plus grand compte rendu de l'appel
-- (octets envoyés + reçus d'un côté ≈ ce que le relais distribue aux deux).
create or replace function public.report_call_quality(p_call_id uuid, p_relayed boolean, p_bytes bigint)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := private.require_active_user();
  v_bytes    bigint := least(greatest(coalesce(p_bytes, 0), 0), 20000000000);
  v_relayed  boolean := coalesce(p_relayed, false);
  v_first    boolean;
  v_relayed_before boolean;
  v_prev     bigint;
begin
  if p_call_id is null or not exists (
       select 1 from private.calls c
        where c.id = p_call_id and v_uid in (c.caller_id, c.callee_id)
          and c.answered_at is not null and c.created_at > now() - interval '1 day') then
    raise exception 'CALL_NOT_FOUND' using errcode = 'P0001';
  end if;
  if exists (select 1 from private.call_reports r where r.call_id = p_call_id and r.user_id = v_uid) then
    return; -- un seul compte rendu par téléphone
  end if;
  v_first := not exists (select 1 from private.call_reports r where r.call_id = p_call_id);
  v_relayed_before := exists (select 1 from private.call_reports r where r.call_id = p_call_id and r.relayed);
  v_prev := coalesce((select max(r.bytes) from private.call_reports r
                       where r.call_id = p_call_id and r.relayed), 0);
  insert into private.call_reports (call_id, user_id, relayed, bytes)
  values (p_call_id, v_uid, v_relayed, v_bytes);
  if v_first then
    perform private.bump_stat('calls_reported');
  end if;
  if v_relayed and not v_relayed_before then
    perform private.bump_stat('calls_relayed');
  end if;
  if v_relayed and v_bytes > v_prev then
    perform private.add_stat('relay_bytes', v_bytes - v_prev);
  end if;
end;
$$;

-- Diagnostic : la fonction call-ice vérifie que la personne est l'administration avant de
-- tester le relais (aucun accès au relais n'est renvoyé).
create or replace function public.console_relay_test()
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console_admin();
begin
  perform private.admin_log(v_uid, 'health_relay', '{}'::jsonb);
  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Alertes de l'administration
-- ---------------------------------------------------------------------------
create table private.admin_alerts (
  id         uuid        primary key default gen_random_uuid(),
  kind       text        not null check (kind in ('purge', 'sms', 'failures', 'relay', 'test')),
  detail     jsonb       not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index admin_alerts_kind_idx on private.admin_alerts (kind, created_at desc);
revoke all on private.admin_alerts from public, anon, authenticated;

-- Volume gratuit du relais Cloudflare (1 000 Go par mois) ; alerte à 80 %.
create or replace function private.relay_bytes_month()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(s.value), 0)::bigint from private.daily_stats s
   where s.metric = 'relay_bytes'
     and s.day >= date_trunc('month', now() at time zone 'utc')::date;
$$;

-- Une alerte (au plus une par type toutes les 6 h), puis notification à l'administration.
create or replace function private.raise_alert(p_kind text, p_detail jsonb)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if exists (select 1 from private.admin_alerts a
              where a.kind = p_kind and a.created_at > now() - interval '6 hours') then
    return false;
  end if;
  insert into private.admin_alerts (kind, detail) values (p_kind, p_detail) returning id into v_id;
  perform private.notify_admin('alert_' || p_kind, v_id);
  return true;
end;
$$;

-- Toutes les 10 minutes (pg_cron). Renvoie les types d'alerte levés.
create or replace function private.check_health_alerts()
returns text[]
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_raised    text[] := '{}';
  v_late      integer;
  v_waiting   integer;
  v_last      timestamptz;
  v_hour      integer;
  v_avg       numeric;
  v_threshold integer;
  v_push_ok   bigint;
  v_push_ko   bigint;
  v_calls_ko  bigint;
  v_calls_all bigint;
  v_relay     bigint;
begin
  if not private.policy_bool('health_alerts_enabled') then
    return v_raised;
  end if;

  -- Effacements automatiques : dernier passage de plus de 10 min, en échec, ou messages
  -- expirés depuis plus de 10 min encore présents.
  v_last := (private.cron_last_run('privio_purge_expired') ->> 'at')::timestamptz;
  v_waiting := (select count(*) from public.messages m where m.expires_at < now() - interval '10 minutes');
  v_late := case when v_last is null then null else floor(extract(epoch from now() - v_last) / 60)::integer end;
  if v_waiting > 0 or coalesce(v_late, 0) > 10
     or (private.cron_last_run('privio_purge_expired') ->> 'status') = 'failed' then
    if private.raise_alert('purge', jsonb_build_object('late_minutes', v_late, 'expired_waiting', v_waiting)) then
      v_raised := array_append(v_raised, 'purge');
    end if;
  end if;

  -- Codes SMS : plus que le seuil en 1 h (ou 3 fois la moyenne horaire des 7 derniers jours).
  v_hour := (select count(*) from private.sms_log l
              where l.kind = 'code' and l.created_at > now() - interval '1 hour');
  v_avg := (select count(*) from private.sms_log l
             where l.kind = 'code' and l.created_at > now() - interval '7 days') / 168.0;
  v_threshold := greatest(private.policy_int('sms_alert_per_hour'), ceil(v_avg * 3)::integer);
  if v_hour > v_threshold then
    if private.raise_alert('sms', jsonb_build_object('codes_hour', v_hour, 'threshold', v_threshold)) then
      v_raised := array_append(v_raised, 'sms');
    end if;
  end if;

  -- Notifications : plus de 20 % d'échecs sur 1 h (10 envois au moins) ; appels : plus de
  -- 30 % d'échecs sur 24 h (5 appels décrochés ou échoués au moins).
  select coalesce(sum(l.sent), 0), coalesce(sum(l.failed), 0) into v_push_ok, v_push_ko
    from private.push_log l where l.created_at > now() - interval '1 hour';
  select count(*) filter (where coalesce(c.end_reason, '') in ('failed', 'lost')),
         count(*) filter (where c.answered_at is not null or coalesce(c.end_reason, '') in ('failed', 'lost'))
    into v_calls_ko, v_calls_all
    from private.calls c
   where c.status not in ('ringing', 'accepted') and c.ended_at > now() - interval '24 hours';
  if (v_push_ok + v_push_ko >= 10 and v_push_ko * 5 > v_push_ok + v_push_ko)
     or (v_calls_all >= 5 and v_calls_ko * 10 > v_calls_all * 3) then
    if private.raise_alert('failures', jsonb_build_object(
         'push_failed', v_push_ko, 'push_total', v_push_ok + v_push_ko,
         'calls_failed', v_calls_ko, 'calls_total', v_calls_all)) then
      v_raised := array_append(v_raised, 'failures');
    end if;
  end if;

  -- Relais : plus de 800 Go estimés ce mois-ci sur les 1 000 gratuits.
  v_relay := private.relay_bytes_month();
  if v_relay > 800::bigint * 1000 * 1000 * 1000 then
    if private.raise_alert('relay', jsonb_build_object('bytes', v_relay)) then
      v_raised := array_append(v_raised, 'relay');
    end if;
  end if;
  return v_raised;
end;
$$;

-- Diagnostic : notification de test vers les téléphones de l'administration.
create or replace function public.console_test_push()
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console_admin();
  v_id  uuid;
begin
  if exists (select 1 from private.admin_alerts a
              where a.kind = 'test' and a.created_at > now() - interval '30 seconds') then
    raise exception 'RATE_LIMITED' using errcode = 'P0001';
  end if;
  insert into private.admin_alerts (kind) values ('test') returning id into v_id;
  perform private.admin_log(v_uid, 'health_push', '{}'::jsonb);
  perform private.notify_admin('test', v_id);
  return v_id;
end;
$$;

-- Nettoyage quotidien : alertes 30 jours, journal des codes 35 jours.
create or replace function private.purge_health_data()
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from private.admin_alerts where created_at < now() - interval '30 days';
  delete from private.sms_log where created_at < now() - interval '35 days';
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job
     where jobname in ('privio_health_alerts', 'privio_purge_health');
    perform cron.schedule('privio_health_alerts', '*/10 * * * *', 'select private.check_health_alerts()');
    perform cron.schedule('privio_purge_health', '23 3 * * *', 'select private.purge_health_data()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Console : rubrique « Santé du service »
-- ---------------------------------------------------------------------------
-- Tâches automatiques de Privio : planification, dernier passage, retard.
create or replace function private.cron_overview()
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
    return '[]'::jsonb;
  end if;
  execute $q$
    select coalesce(jsonb_agg(jsonb_build_object(
             'job', j.jobname, 'schedule', j.schedule, 'active', j.active,
             'at', d.end_time, 'status', d.status) order by j.jobname), '[]'::jsonb)
      from cron.job j
      left join lateral (
        select x.end_time, x.status from cron.job_run_details x
         where x.jobid = j.jobid order by x.runid desc limit 1) d on true
     where j.jobname like 'privio\_%' $q$
    into v;
  return v;
end;
$$;

create or replace function public.console_health()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_console_admin();
  v_today  date := (now() at time zone 'utc')::date;
  v_month  date := date_trunc('month', now() at time zone 'utc')::date;
  v_min    integer := private.policy_int('app_min_build');
  v_rec    integer := private.policy_int('app_recommended_build');
  v_cost   integer := private.policy_int('sms_unit_cost');
  v_test   private.admin_alerts%rowtype;
  r        jsonb;
begin
  perform private.admin_log(v_uid, 'health', '{}'::jsonb);
  select * into v_test from private.admin_alerts a where a.kind = 'test' order by a.created_at desc limit 1;

  with dev as (
    select d.app_version, private.build_of(d.app_version) as build
      from public.devices d
      join public.profiles p on p.id = d.user_id and p.deleted_at is null
     where d.revoked_at is null and d.last_seen_at > now() - interval '30 days'
  ), stat as (
    select s.metric,
           coalesce(sum(s.value) filter (where s.day > v_today - 30), 0) as d30,
           coalesce(sum(s.value) filter (where s.day >= v_month), 0)     as month,
           coalesce(sum(s.value) filter (where s.day = v_today), 0)      as today
      from private.daily_stats s
     where s.day > v_today - 31 or s.day >= v_month
     group by s.metric
  ), sms as (
    select count(*) filter (where l.kind = 'code' and l.created_at > now() - interval '30 days')         as codes_30d,
           count(*) filter (where l.kind = 'code' and l.created_at >= v_month)                           as codes_month,
           count(*) filter (where l.kind = 'code' and l.created_at > now() - interval '24 hours')        as codes_24h,
           count(*) filter (where l.kind = 'code' and l.created_at > now() - interval '1 hour')          as codes_1h,
           count(*) filter (where l.kind = 'code' and l.purpose = 'phone_change'
                              and l.created_at > now() - interval '30 days')                             as phone_change_30d,
           count(*) filter (where l.kind = 'verified' and l.created_at > now() - interval '30 days')     as verified_30d
      from private.sms_log l
  )
  select jsonb_build_object(
    'generated_at', now(),
    'versions', jsonb_build_object(
      'min_build', v_min,
      'recommended_build', v_rec,
      'update_url', private.policy_value('app_update_url') #>> '{}',
      'devices', (select count(*) from dev),
      'below_min', (select count(*) from dev where v_min > 0 and coalesce(build, 0) < v_min),
      'below_recommended', (select count(*) from dev where v_rec > 0 and coalesce(build, 0) < v_rec),
      'installed', (select coalesce(jsonb_agg(jsonb_build_object('version', x.app_version, 'build', x.build,
                                                                  'devices', x.n)
                                              order by x.build desc nulls last, x.app_version desc), '[]'::jsonb)
                      from (select app_version, build, count(*) as n from dev group by app_version, build) x)),
    'calls', jsonb_build_object(
      'audio_30d',      (select coalesce(sum(d30), 0) from stat where metric = 'calls_audio'),
      'video_30d',      (select coalesce(sum(d30), 0) from stat where metric = 'calls_video'),
      'ok_30d',         (select coalesce(sum(d30), 0) from stat where metric = 'calls_ok'),
      'failed_30d',     (select coalesce(sum(d30), 0) from stat where metric = 'calls_failed'),
      'unanswered_30d', (select coalesce(sum(d30), 0) from stat where metric = 'calls_unanswered'),
      'seconds_30d',    (select coalesce(sum(d30), 0) from stat where metric = 'calls_seconds'),
      'reported_30d',   (select coalesce(sum(d30), 0) from stat where metric = 'calls_reported'),
      'relayed_30d',    (select coalesce(sum(d30), 0) from stat where metric = 'calls_relayed'),
      'relay_bytes_month', private.relay_bytes_month(),
      'relay_free_bytes', 1000::bigint * 1000 * 1000 * 1000),
    'signup', jsonb_build_object(
      'codes_30d',        (select codes_30d from sms),
      'codes_month',      (select codes_month from sms),
      'codes_24h',        (select codes_24h from sms),
      'codes_1h',         (select codes_1h from sms),
      'phone_change_30d', (select phone_change_30d from sms),
      'verified_30d',     (select verified_30d from sms),
      'profiles_30d',     (select coalesce(sum(d30), 0) from stat where metric = 'signup_profiles'),
      'unit_cost',        v_cost,
      'cost_month',       (select codes_month from sms) * v_cost,
      'cost_30d',         (select codes_30d from sms) * v_cost),
    'diagnostics', jsonb_build_object(
      'jobs', private.cron_overview(),
      'expired_waiting', (select count(*) from public.messages m where m.expires_at < now() - interval '5 minutes'),
      'files_waiting',   (select count(*) from private.media_objects o where o.state = 'purge'),
      'push_targets',    (select count(*) from private.push_tokens t
                           join public.devices d on d.id = t.device_id and d.revoked_at is null
                          where private.is_console_admin(t.user_id)),
      'last_test', case when v_test.id is null then null else jsonb_build_object(
        'at', v_test.created_at,
        'result', (select jsonb_build_object('status', l.status, 'sent', l.sent, 'failed', l.failed,
                                             'recipients', l.recipients)
                     from private.push_log l where l.message_id = v_test.id
                    order by l.id desc limit 1)) end),
    'alerts', jsonb_build_object(
      'enabled', private.policy_bool('health_alerts_enabled'),
      'sms_per_hour', private.policy_int('sms_alert_per_hour'),
      'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'detail', a.detail,
                                                              'at', a.created_at) order by a.created_at desc),
                                 '[]'::jsonb)
                   from (select * from private.admin_alerts x where x.kind <> 'test'
                          order by x.created_at desc limit 20) a))
  ) into r;
  return r;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.report_call_quality(uuid, boolean, bigint) to authenticated;
grant execute on function public.console_relay_test() to authenticated;
grant execute on function public.console_test_push() to authenticated;
grant execute on function public.console_health() to authenticated;
