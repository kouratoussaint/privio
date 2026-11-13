-- PRIVIO — lot 5.2 : réglages, statistiques et journal dans la console (ADR-016).
--
-- Décisions du 13/11/2026 : tous les réglages en service sont modifiables (les techniques
-- rangés dans « Avancé ») ; simple confirmation avant chaque changement ; statistiques sur
-- 30 jours en nombres anonymes ; réglages par groupe ou par compte reportés.
-- Les invariants (72 h, captures, copie, transfert, partage, export, galerie) et les
-- fonctionnalités non développées sont affichés avec un cadenas et refusés par le serveur.

-- ---------------------------------------------------------------------------
-- Présentation des réglages dans la console
-- ---------------------------------------------------------------------------
alter table private.policy_definitions
  add column category     text,
  add column label_fr     text,
  add column unit         text,
  add column admin_locked boolean not null default false,
  add column advanced     boolean not null default false,
  add column sort_order   integer not null default 0,
  add column effect_fr    text;

update private.policy_definitions d
   set category = m.category, label_fr = m.label, unit = m.unit, admin_locked = m.locked,
       advanced = m.advanced, sort_order = m.ord, effect_fr = m.effect
  from (values
    -- Messages
    ('message_edit_window_minutes', 'messages', 'Délai pour modifier un message', 'min', false, false, 10,
     'S’applique tout de suite, aussi aux messages déjà envoyés (0 = modification impossible).'),
    ('message_delete_for_all_hours', 'messages', 'Délai pour supprimer pour tout le monde', 'h', false, false, 20,
     'S’applique tout de suite, aussi aux messages déjà envoyés.'),
    ('message_max_chars', 'messages', 'Longueur maximale d’un message', 'car', false, false, 30,
     'S’applique aux prochains messages.'),
    ('message_ttl_min_minutes', 'messages', 'Durée de vie la plus courte proposée', 'min', false, false, 40,
     'S’applique aux prochains réglages de durée ; les durées déjà choisies ne changent pas.'),
    ('clear_request_ttl_hours', 'messages', 'Validité d’une demande « vider pour nous deux »', 'h', false, false, 50,
     'S’applique aux prochaines demandes.'),
    -- Médias
    ('photo_daily_limit', 'media', 'Photos par compte et par jour', 'nb', false, false, 10,
     'Compté sur la journée en cours (heure de Ouagadougou), groupes compris. 0 = envoi de photos impossible.'),
    ('voice_max_seconds', 'media', 'Durée maximale d’un vocal', 's', false, false, 20,
     'S’applique aux prochains vocaux.'),
    ('photo_caption_max_chars', 'media', 'Longueur maximale d’une légende', 'car', false, false, 30,
     'S’applique aux prochaines photos.'),
    -- Groupes
    ('group_max_members', 'groups', 'Membres au plus par groupe', 'nb', false, false, 10,
     'Les groupes déjà plus grands gardent leurs membres ; seules les nouvelles invitations sont bloquées.'),
    ('group_invitation_ttl_days', 'groups', 'Validité d’une invitation', 'j', false, false, 20,
     'S’applique aux nouvelles invitations ; celles déjà envoyées gardent leur durée.'),
    -- Demandes de connexion
    ('connection_requests_required', 'requests', 'Premier contact par demande de connexion', 'bool', false, false, 10,
     'Désactivé : on peut de nouveau écrire directement à quelqu’un qu’on trouve.'),
    ('connection_request_expiry_hours', 'requests', 'Expiration d’une demande sans réponse', 'h', false, false, 20,
     'S’applique aux nouvelles demandes.'),
    ('connection_request_retry_minutes', 'requests', 'Attente avant de redemander après un refus', 'min', false, false, 30,
     'S’applique tout de suite.'),
    ('connection_request_daily_per_person', 'requests', 'Demandes au plus vers une même personne par jour', 'nb', false, false, 40,
     'S’applique tout de suite.'),
    ('connection_note_max_chars', 'requests', 'Longueur maximale du petit mot', 'car', false, false, 50,
     'S’applique aux prochaines demandes.'),
    ('connection_note_ttl_minutes', 'requests', 'Durée du petit mot après acceptation', 'min', false, false, 60,
     'S’applique aux prochaines acceptations.'),
    -- Anti-abus
    ('message_send_hourly_limit', 'abuse', 'Messages par compte et par heure', 'nb', false, false, 10, null),
    ('conversation_create_hourly_limit', 'abuse', 'Nouvelles discussions par compte et par heure', 'nb', false, false, 20, null),
    ('group_create_daily_limit', 'abuse', 'Groupes créés par compte et par jour', 'nb', false, false, 30, null),
    ('group_invite_hourly_limit', 'abuse', 'Invitations de groupe par compte et par heure', 'nb', false, false, 40, null),
    ('search_handle_hourly_limit', 'abuse', 'Recherches par identifiant, par heure', 'nb', false, false, 50, null),
    ('search_phone_hourly_limit', 'abuse', 'Recherches par numéro, par heure', 'nb', false, false, 60, null),
    ('handle_check_hourly_limit', 'abuse', 'Vérifications d’identifiant, par heure', 'nb', false, false, 70, null),
    ('profile_write_hourly_limit', 'abuse', 'Modifications du profil, par heure', 'nb', false, false, 80, null),
    ('avatar_upload_daily_limit', 'abuse', 'Changements de photo de profil, par jour', 'nb', false, false, 90, null),
    ('voice_upload_hourly_limit', 'abuse', 'Vocaux préparés par compte et par heure', 'nb', false, false, 100, null),
    ('typing_signal_hourly_limit', 'abuse', 'Signaux « en train d’écrire », par heure', 'nb', false, false, 110, null),
    ('report_daily_limit', 'abuse', 'Signalements et demandes d’aide, par jour', 'nb', false, false, 120, null),
    ('clear_request_daily_limit', 'abuse', 'Demandes « vider pour nous deux », par jour', 'nb', false, false, 130, null),
    -- Conservation
    ('report_retention_days', 'retention', 'Conservation des signalements', 'j', false, false, 10,
     'Les signalements plus anciens sont effacés au prochain nettoyage.'),
    ('admin_audit_retention_days', 'retention', 'Conservation du journal de la console', 'j', false, false, 20,
     'Les entrées plus anciennes sont effacées au prochain nettoyage (chaque nuit). L’historique des réglages est gardé sans limite.'),
    -- Avancé (technique)
    ('voice_max_bytes', 'advanced', 'Taille maximale d’un vocal', 'o', false, true, 10, 'S’applique aux prochains vocaux.'),
    ('photo_max_bytes', 'advanced', 'Taille maximale d’une photo', 'o', false, true, 20, 'S’applique aux prochaines photos.'),
    ('photo_max_dimension', 'advanced', 'Plus grand côté d’une photo', 'px', false, true, 30, 'S’applique aux prochaines photos.'),
    ('avatar_max_bytes', 'advanced', 'Taille maximale d’une photo de profil', 'o', false, true, 40, 'S’applique aux prochaines photos de profil.'),
    ('presence_online_seconds', 'advanced', 'Durée « en ligne » après le dernier signe de l’app', 's', false, true, 50, null),
    -- Fixés (invariants de sécurité)
    ('message_ttl_hours', 'locked', 'Durée de vie maximale d’un message : 72 h', 'h', true, false, 10, null),
    ('screen_capture_allowed', 'locked', 'Captures d’écran interdites', 'bool', true, false, 20, null),
    ('message_copy_enabled', 'locked', 'Copie du texte des messages interdite', 'bool', true, false, 30, null),
    ('internal_forward_enabled', 'locked', 'Transfert de messages interdit', 'bool', true, false, 40, null),
    ('external_share_enabled', 'locked', 'Partage vers d’autres applications interdit', 'bool', true, false, 50, null),
    ('conversation_export_enabled', 'locked', 'Export des discussions interdit', 'bool', true, false, 60, null),
    ('save_media_to_gallery_enabled', 'locked', 'Enregistrement dans la galerie interdit', 'bool', true, false, 70, null),
    ('quota_timezone', 'locked', 'Fuseau des quotas : Ouagadougou', 'text', true, false, 80, null),
    -- Pas encore développés
    ('video_upload_enabled', 'future', 'Envoi de vidéos', 'bool', true, false, 10, null),
    ('document_upload_enabled', 'future', 'Envoi de documents', 'bool', true, false, 20, null),
    ('video_call_max_minutes', 'future', 'Durée maximale d’un appel vidéo', 'min', true, false, 30, null)
  ) as m(key, category, label, unit, locked, advanced, ord, effect)
 where d.key = m.key;

-- Toute nouvelle définition devra être classée (garde-fou testé).
-- ---------------------------------------------------------------------------
-- Journal de la console : détail des changements
-- ---------------------------------------------------------------------------
alter table private.admin_audit add column detail jsonb;

create or replace function private.admin_log(p_admin uuid, p_action text, p_detail jsonb)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.admin_audit (admin_id, action, detail) values (p_admin, p_action, p_detail);
$$;

-- ---------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------
create or replace function public.console_policies()
returns table (
  key            text,
  category       text,
  label          text,
  unit           text,
  value_type     text,
  value          jsonb,
  default_value  jsonb,
  min_value      numeric,
  max_value      numeric,
  locked         boolean,
  advanced       boolean,
  sort_order     integer,
  effect         text,
  client_visible boolean,
  updated_at     timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.require_console_admin();
  return query
  select d.key, d.category, coalesce(d.label_fr, d.description_fr), d.unit, d.value_type,
         private.policy_value(d.key), d.default_value, d.min_value, d.max_value,
         d.admin_locked or not d.implemented, d.advanced, d.sort_order, d.effect_fr,
         d.client_visible,
         (select p.updated_at from private.policies p
           where p.key = d.key and p.scope_type = 'global' and p.enabled)
    from private.policy_definitions d
   order by d.category, d.sort_order, d.key;
end;
$$;

-- Modifier un réglage global (validation : type, bornes, fonctionnalité développée).
create or replace function public.console_set_policy(p_key text, p_value jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_console_admin();
  d        private.policy_definitions%rowtype;
  v_before jsonb;
begin
  select * into d from private.policy_definitions where key = p_key;
  if not found then
    raise exception 'POLICY_NOT_FOUND' using errcode = 'P0001';
  end if;
  if d.admin_locked or not d.implemented then
    raise exception 'POLICY_LOCKED' using errcode = 'P0001';
  end if;
  if p_value is null then
    raise exception 'POLICY_TYPE_INVALID' using errcode = 'P0001';
  end if;
  v_before := private.policy_value(p_key);
  insert into private.policies (key, scope_type, scope_id, value, enabled, updated_by)
  values (p_key, 'global', null, p_value, true, v_uid)
  on conflict (key, scope_type, scope_id) do update
     set value = excluded.value, enabled = true, updated_by = excluded.updated_by;
  perform private.admin_log(v_uid, 'policy',
    jsonb_build_object('key', p_key, 'before', v_before, 'after', p_value));
  return private.policy_value(p_key);
end;
$$;

-- Historique d'un réglage (ou de tous) : avant, après, date, auteur (console ou serveur).
create or replace function public.console_policy_history(p_key text default null, p_limit integer default 50)
returns table (
  key        text,
  label      text,
  before     jsonb,
  after      jsonb,
  by_console boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.require_console_admin();
  return query
  select h.policy_key, coalesce(d.label_fr, d.description_fr),
         h.before_json -> 'value', h.after_json -> 'value',
         h.actor_id is not null, h.created_at
    from private.policy_history h
    join private.policy_definitions d on d.key = h.policy_key
   where h.scope_type = 'global' and (p_key is null or h.policy_key = p_key)
   order by h.id desc
   limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

-- ---------------------------------------------------------------------------
-- Statistiques
-- ---------------------------------------------------------------------------
create or replace function private.add_stat(p_metric text, p_by bigint)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.daily_stats (day, metric, value)
  values ((now() at time zone 'utc')::date, p_metric, p_by)
  on conflict (day, metric) do update set value = private.daily_stats.value + excluded.value;
$$;

-- Notifications envoyées / en échec, par jour (le journal détaillé n'est gardé que 7 jours).
create or replace function private.stats_on_push_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.sent > 0 then perform private.add_stat('push_sent', new.sent); end if;
  if new.failed > 0 then perform private.add_stat('push_failed', new.failed); end if;
  return null;
end;
$$;
create trigger push_log_stats after insert on private.push_log
  for each row execute function private.stats_on_push_log();

-- Comptes actifs du jour : un NOMBRE, relevé chaque soir (aucun identifiant gardé).
create or replace function private.active_users_count(p_since timestamptz)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select count(distinct a.user_id) from (
    select p.user_id, p.last_seen_at as seen from private.presence p
    union all
    select d.user_id, d.last_seen_at from public.devices d where d.revoked_at is null
  ) a
  join public.profiles pr on pr.id = a.user_id and pr.deleted_at is null
  where a.seen >= p_since;
$$;

create or replace function private.snapshot_active_users()
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.daily_stats (day, metric, value)
  values ((now() at time zone 'utc')::date, 'active_users',
          private.active_users_count(date_trunc('day', now() at time zone 'utc') at time zone 'utc'))
  on conflict (day, metric) do update set value = excluded.value;
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_snapshot_active_users';
    perform cron.schedule('privio_snapshot_active_users', '55 23 * * *',
                          'select private.snapshot_active_users()');
  end if;
end;
$$;

-- 30 derniers jours (aujourd'hui compris) + versions de l'app sur les téléphones actifs.
create or replace function public.console_stats(p_days integer default 30)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_console_admin();
  v_days  integer := least(greatest(coalesce(p_days, 30), 7), 90);
  v_today date := (now() at time zone 'utc')::date;
  r       jsonb;
begin
  perform private.admin_log(v_uid, 'stats', null);
  -- Le relevé du jour est mis à jour à la consultation.
  perform private.snapshot_active_users();
  with days as (
    select generate_series(v_today - (v_days - 1), v_today, interval '1 day')::date as day
  ), s as (
    select st.day, st.metric, st.value from private.daily_stats st where st.day > v_today - v_days
  ), accounts as (
    select (p.created_at at time zone 'utc')::date as day, count(*) as n
      from public.profiles p
     where p.created_at >= (v_today - (v_days - 1))::timestamp at time zone 'utc'
     group by 1
  )
  select jsonb_build_object(
    'days', (select jsonb_agg(jsonb_build_object(
        'day', d.day,
        'text',      coalesce((select s.value from s where s.day = d.day and s.metric = 'messages_text'), 0),
        'voice',     coalesce((select s.value from s where s.day = d.day and s.metric = 'messages_voice'), 0),
        'photo',     coalesce((select s.value from s where s.day = d.day and s.metric = 'messages_photo'), 0),
        'active',    (select s.value from s where s.day = d.day and s.metric = 'active_users'),
        'new_accounts', coalesce((select a.n from accounts a where a.day = d.day), 0),
        'requests',  coalesce((select s.value from s where s.day = d.day and s.metric = 'connection_requests'), 0),
        'accepted',  coalesce((select s.value from s where s.day = d.day and s.metric = 'connection_accepted'), 0),
        'refused',   coalesce((select s.value from s where s.day = d.day and s.metric = 'connection_refused'), 0),
        'push_sent', coalesce((select s.value from s where s.day = d.day and s.metric = 'push_sent'), 0),
        'push_failed', coalesce((select s.value from s where s.day = d.day and s.metric = 'push_failed'), 0)
      ) order by d.day) from days d),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object('version', v.app_version, 'devices', v.n)
                                           order by v.n desc, v.app_version desc), '[]'::jsonb)
                   from (select d.app_version, count(*) as n
                           from public.devices d
                           join public.profiles pr on pr.id = d.user_id and pr.deleted_at is null
                          where d.revoked_at is null and d.last_seen_at > now() - interval '30 days'
                          group by d.app_version) v),
    'counting_since', (select min(st.day) from private.daily_stats st)
  ) into r;
  return r;
end;
$$;

-- ---------------------------------------------------------------------------
-- Journal de la console
-- ---------------------------------------------------------------------------
create or replace function public.console_journal(p_limit integer default 100)
returns table (
  id         bigint,
  action     text,
  key        text,
  label      text,
  before     jsonb,
  after      jsonb,
  created_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.require_console_admin();
  return query
  select a.id, a.action, a.detail ->> 'key',
         (select coalesce(d.label_fr, d.description_fr) from private.policy_definitions d
           where d.key = a.detail ->> 'key'),
         a.detail -> 'before', a.detail -> 'after', a.created_at
    from private.admin_audit a
   order by a.id desc
   limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();

grant execute on function public.console_policies() to authenticated;
grant execute on function public.console_set_policy(text, jsonb) to authenticated;
grant execute on function public.console_policy_history(text, integer) to authenticated;
grant execute on function public.console_stats(integer) to authenticated;
grant execute on function public.console_journal(integer) to authenticated;
