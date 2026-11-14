-- PRIVIO — lot 5.4 : comptes et assistance dans la console (ADR-018).
--
-- Décisions du 14/11/2026 : recherche par @identifiant, par nom, ou par numéro COMPLET
-- (jamais affiché, recherche journalisée) ; fiche d'un compte sans numéro ni contenu ;
-- avertir / suspendre / réactiver sans signalement ; « Déconnecter le téléphone » ; une
-- réponse par demande d'assistance, notifiée sans contenu, visible dans Aide → Mes demandes ;
-- modèles de réponse modifiables (dans l'application de la console).

-- ---------------------------------------------------------------------------
-- 1. Réponse aux demandes d'assistance
-- ---------------------------------------------------------------------------
alter table private.reports
  add column reply      text check (reply is null or char_length(reply) between 2 and 1000),
  add column replied_at timestamptz,
  add column replied_by uuid references auth.users (id) on delete set null;
alter table private.reports drop constraint if exists reports_decision_check;
alter table private.reports add constraint reports_decision_check check (decision in
  ('dismissed', 'warned', 'suspended', 'message_deleted', 'group_closed', 'answered'));

drop function if exists public.console_reports(text);
create or replace function public.console_reports(p_status text default 'open')
returns table (
  id                uuid,
  kind              text,
  reason            text,
  details           text,
  status            text,
  created_at        timestamptz,
  taken_at          timestamptz,
  decision          text,
  decision_note     text,
  decided_at        timestamptz,
  reporter_handle   text,
  reported_user_id  uuid,
  reported_handle   text,
  reported_name     text,
  reported_since    timestamptz,
  conversation_id   uuid,
  group_title       text,
  group_closed      boolean,
  message_id        uuid,
  evidence_kind     text,
  reports_90d       integer,
  reporters_90d     integer,
  suspended         boolean,
  suspended_until   timestamptz,
  sanctions_count   integer,
  protected         boolean,
  reply             text,
  replied_at        timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_console_admin();
begin
  if p_status not in ('open', 'reviewing', 'closed') then
    raise exception 'MODERATION_INVALID' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'reports', jsonb_build_object('status', p_status));
  return query
  select r.id,
         case when r.reason = 'support' then 'support'
              when r.message_id is not null then 'message'
              when r.reported_user_id is null then 'group'
              else 'account' end,
         r.reason, r.details, r.status, r.created_at, r.taken_at, r.decision, r.decision_note, r.decided_at,
         rp.handle,
         r.reported_user_id, tp.handle, tp.display_name, tp.created_at,
         r.conversation_id,
         case when c.kind = 'group' then c.title end,
         coalesce(c.kind = 'group' and c.posting = 'closed', false),
         r.message_id,
         case when r.evidence is null then null else coalesce(r.evidence ->> 'kind', 'text') end,
         (select count(*)::int from private.reports x
           where x.reported_user_id = r.reported_user_id and x.created_at > now() - interval '90 days'),
         (select count(distinct x.reporter_id)::int from private.reports x
           where x.reported_user_id = r.reported_user_id and x.created_at > now() - interval '90 days'),
         r.reported_user_id is not null and private.is_suspended(r.reported_user_id),
         (private.active_suspension(r.reported_user_id)).until,
         (select count(*)::int from private.sanctions s where s.user_id = r.reported_user_id),
         r.reported_user_id is not null and private.is_console_admin(r.reported_user_id),
         r.reply, r.replied_at
    from private.reports r
    left join public.profiles rp on rp.id = r.reporter_id
    left join public.profiles tp on tp.id = r.reported_user_id
    left join public.conversations c on c.id = r.conversation_id
   where r.status = p_status
   order by case when p_status = 'closed' then extract(epoch from r.decided_at) * -1
                 else extract(epoch from r.created_at) end
   limit 300;
end;
$$;


create or replace function private.notify_support_reply(p_user uuid, p_report_id uuid)
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
  perform private.signal_user(p_user, null, 'support');
  if v_url is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null
     or not exists (select 1 from private.push_tokens t where t.user_id = p_user) then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
    using v_url || '/push-dispatch', jsonb_build_object('support_reply_id', p_report_id),
          jsonb_build_object('Content-Type', 'application/json', 'x-privio-push', v_token), 10000;
end;
$$;

-- Répondre à une demande d'assistance (une réponse par demande).
create or replace function public.console_reply_support(p_report_id uuid, p_reply text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_console_admin();
  v_reply text := btrim(coalesce(p_reply, ''));
  r       private.reports%rowtype;
begin
  if char_length(v_reply) < 2 or char_length(v_reply) > 1000 then
    raise exception 'SUPPORT_REPLY_INVALID' using errcode = 'P0001';
  end if;
  select * into r from private.reports where id = p_report_id for update;
  if not found or r.reason <> 'support' or r.reply is not null then
    raise exception 'REPORT_NOT_FOUND' using errcode = 'P0001';
  end if;
  update private.reports
     set reply = v_reply, replied_at = now(), replied_by = v_uid,
         status = 'closed', decision = 'answered', decided_at = clock_timestamp(), decided_by = v_uid,
         taken_at = coalesce(taken_at, now())
   where id = p_report_id;
  perform private.admin_log(v_uid, 'reply', jsonb_build_object(
    'handle', (select p.handle from public.profiles p where p.id = r.reporter_id)));
  if r.reporter_id is not null then
    perform private.notify_support_reply(r.reporter_id, p_report_id);
  end if;
end;
$$;

-- Jetons à notifier (réservé à push-dispatch) : l'auteur de la demande, appareils actifs.
create or replace function public.push_support_targets(p_token text, p_report_id uuid)
returns table (token text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.check_push_token(p_token);
  return query
  select t.token
    from private.reports r
    join private.push_tokens t on t.user_id = r.reporter_id
    join public.devices d on d.id = t.device_id and d.revoked_at is null
   where r.id = p_report_id and r.reason = 'support' and r.reply is not null;
end;
$$;

-- Mes demandes d'assistance (90 jours), avec la réponse de l'équipe.
create or replace function public.my_support_requests()
returns table (
  id         uuid,
  details    text,
  created_at timestamptz,
  reply      text,
  replied_at timestamptz
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
  select r.id, r.details, r.created_at, r.reply, r.replied_at
    from private.reports r
   where r.reporter_id = v_uid and r.reason = 'support' and r.purge_after > now()
   order by r.created_at desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Comptes : recherche et fiche
-- ---------------------------------------------------------------------------
create or replace function public.console_search_accounts(p_query text)
returns table (
  user_id      uuid,
  handle       text,
  display_name text,
  created_at   timestamptz,
  deleted      boolean,
  suspended    boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid    uuid := private.require_console_admin();
  v_q      text := btrim(coalesce(p_query, ''));
  v_digits text := regexp_replace(v_q, '[^0-9]', '', 'g');
  v_phone  text;
begin
  -- Numéro COMPLET seulement (8 chiffres burkinabè ou format international) ; jamais affiché.
  if v_q ~ '^[+0-9 .-]+$' then
    v_phone := case when char_length(v_digits) = 8 then '+226' || v_digits
                    when char_length(v_digits) between 10 and 15 then '+' || v_digits end;
    perform private.admin_log(v_uid, 'account_search', jsonb_build_object('by', 'phone'));
    if v_phone is null then
      raise exception 'SEARCH_PHONE_INCOMPLETE' using errcode = 'P0001';
    end if;
    return query
    select p.id, p.handle, p.display_name, p.created_at, p.deleted_at is not null,
           private.is_suspended(p.id)
      from private.user_contacts c
      join public.profiles p on p.id = c.user_id
     where c.phone_e164 = v_phone;
    return;
  end if;
  v_q := lower(ltrim(v_q, '@'));
  if char_length(v_q) < 2 then
    raise exception 'SEARCH_TOO_SHORT' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'account_search', jsonb_build_object('by', 'name'));
  return query
  select p.id, p.handle, p.display_name, p.created_at, p.deleted_at is not null,
         private.is_suspended(p.id)
    from public.profiles p
   where p.handle like replace(replace(v_q, '%', ''), '_', '\_') || '%'
      or lower(p.display_name) like '%' || replace(v_q, '%', '') || '%'
   order by (p.handle = v_q) desc, p.handle
   limit 30;
end;
$$;

-- Fiche d'un compte : aucun numéro, aucun contact, aucune discussion, aucun message.
create or replace function public.console_account(p_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console_admin();
  p     public.profiles%rowtype;
  d     public.devices%rowtype;
  s     private.sanctions%rowtype;
begin
  select * into p from public.profiles where id = p_user_id;
  if not found then
    raise exception 'ACCOUNT_NOT_FOUND' using errcode = 'P0001';
  end if;
  select * into d from public.devices x
   where x.user_id = p_user_id and x.revoked_at is null
   order by x.created_at desc limit 1;
  s := private.active_suspension(p_user_id);
  perform private.admin_log(v_uid, 'account', jsonb_build_object('handle', p.handle));
  return jsonb_build_object(
    'user_id', p.id,
    'handle', p.handle,
    'display_name', p.display_name,
    'avatar_path', p.avatar_path,
    'created_at', p.created_at,
    'deleted', p.deleted_at is not null,
    'last_seen_day', (select (max(x.seen) at time zone 'utc')::date from (
        select pr.last_seen_at as seen from private.presence pr where pr.user_id = p_user_id
        union all
        select dv.last_seen_at from public.devices dv where dv.user_id = p_user_id) x),
    'suspended', s.id is not null,
    'suspended_until', s.until,
    'protected', private.is_console_admin(p_user_id),
    'device', case when d.id is null then null else jsonb_build_object(
      'platform', d.platform, 'app_version', d.app_version, 'since', d.created_at,
      'push', exists (select 1 from private.push_tokens t where t.device_id = d.id)) end,
    'directs', (select count(*) from public.conversation_members m
                  join public.conversations c on c.id = m.conversation_id and c.kind = 'direct'
                 where m.user_id = p_user_id and m.left_at is null),
    'groups', (select count(*) from public.conversation_members m
                 join public.conversations c on c.id = m.conversation_id and c.kind = 'group'
                where m.user_id = p_user_id and m.left_at is null),
    'reports_received_90d', (select count(*) from private.reports r
                              where r.reported_user_id = p_user_id and r.created_at > now() - interval '90 days'),
    'reports_made_90d', (select count(*) from private.reports r
                          where r.reporter_id = p_user_id and r.reason <> 'support'
                            and r.created_at > now() - interval '90 days'),
    'support', (select coalesce(jsonb_agg(jsonb_build_object(
                    'id', r.id, 'details', r.details, 'created_at', r.created_at,
                    'reply', r.reply, 'replied_at', r.replied_at) order by r.created_at desc), '[]'::jsonb)
                  from private.reports r
                 where r.reporter_id = p_user_id and r.reason = 'support' and r.purge_after > now()));
end;
$$;

-- Photo de profil d'un compte : lisible par l'administration (fiche).
create or replace function private.can_read_evidence(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and private.is_console_admin(auth.uid())
     and (exists (select 1 from private.reports r
                   where r.evidence ->> 'media_path' = p_name and r.purge_after > now())
          or exists (select 1 from public.profiles p where p.avatar_path = p_name));
$$;

do $$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists privio_evidence_read on storage.objects';
    execute $p$
      create policy privio_evidence_read on storage.objects
        for select to authenticated
        using (bucket_id in ('voice', 'photos', 'avatars') and private.can_read_evidence(name))
    $p$;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Sanction depuis la fiche (sans signalement)
-- ---------------------------------------------------------------------------
create or replace function public.console_sanction_user(
  p_user_id uuid, p_action text, p_reason text, p_note text, p_days integer default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_console_admin();
  v_note text := btrim(coalesce(p_note, ''));
begin
  if p_action not in ('warn', 'suspend')
     or p_reason not in ('spam', 'harassment', 'inappropriate', 'threat', 'impersonation', 'other')
     or (p_action = 'suspend' and p_days is not null and p_days not in (1, 7, 30)) then
    raise exception 'MODERATION_INVALID' using errcode = 'P0001';
  end if;
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user_id and p.deleted_at is null) then
    raise exception 'ACCOUNT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if private.is_console_admin(p_user_id) then
    raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
  end if;
  if p_action = 'warn' then
    insert into private.sanctions (user_id, kind, user_reason, note, created_by)
    values (p_user_id, 'warning', p_reason, v_note, v_uid);
  else
    update private.sanctions set lifted_at = now(), lift_note = 'Remplacée par une nouvelle suspension'
     where user_id = p_user_id and kind = 'suspension' and lifted_at is null;
    insert into private.sanctions (user_id, kind, until, user_reason, note, created_by)
    values (p_user_id, 'suspension',
            case when p_days is null then null else now() + make_interval(days => p_days) end,
            p_reason, v_note, v_uid);
  end if;
  perform private.signal_user(p_user_id, null, 'moderation');
  perform private.admin_log(v_uid, 'moderation', jsonb_build_object(
    'action', p_action, 'days', p_days, 'reports', 0,
    'handle', (select p.handle from public.profiles p where p.id = p_user_id)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Déconnecter le téléphone (perdu ou volé) : session coupée, reconnexion par code SMS.
-- ---------------------------------------------------------------------------
create or replace function public.console_disconnect_device(p_user_id uuid, p_note text)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_console_admin();
  v_note text := btrim(coalesce(p_note, ''));
  v_n    integer;
begin
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  if private.is_console_admin(p_user_id) then
    raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
  end if;
  -- Prévenir l'application ouverte avant de couper (message dédié à l'écran de connexion).
  perform private.signal_user(p_user_id, null, 'disconnected');
  update public.devices set revoked_at = now(), revoked_reason = 'admin'
   where user_id = p_user_id and revoked_at is null;
  get diagnostics v_n = row_count;
  delete from auth.sessions where user_id = p_user_id;
  perform private.admin_log(v_uid, 'disconnect', jsonb_build_object(
    'handle', (select p.handle from public.profiles p where p.id = p_user_id), 'devices', v_n));
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits (la lecture de la photo de profil passe par can_read_evidence, déjà autorisée).
-- ---------------------------------------------------------------------------
select private.harden_privileges();

grant execute on function public.console_reports(text) to authenticated;
grant execute on function public.console_reply_support(uuid, text) to authenticated;
grant execute on function public.my_support_requests() to authenticated;
grant execute on function public.console_search_accounts(text) to authenticated;
grant execute on function public.console_account(uuid) to authenticated;
grant execute on function public.console_sanction_user(uuid, text, text, text, integer) to authenticated;
grant execute on function public.console_disconnect_device(uuid, text) to authenticated;
revoke all on function public.push_support_targets(text, uuid) from authenticated;
grant execute on function public.push_support_targets(text, uuid) to service_role;
