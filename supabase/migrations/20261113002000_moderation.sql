-- PRIVIO — lot 5.3 : signalements et modération dans la console (ADR-017).
--
-- Décisions du 13/11/2026 : décisions classer / avertir / suspendre (24 h, 7 j, 30 j, sans
-- limite) / réactiver / supprimer le message signalé / fermer un groupe ; la console montre
-- l'@identifiant de la personne qui signale ; notification à l'administration à chaque
-- nouveau signalement ; une contestation par sanction. Le compte administrateur ne peut pas
-- être sanctionné. Sanctions gardées 1 an (sauf suspension sans limite encore active).

-- ---------------------------------------------------------------------------
-- 1. Signalements : traitement et décision
-- ---------------------------------------------------------------------------
alter table private.reports
  add column taken_at      timestamptz,
  add column decision      text check (decision in
                             ('dismissed', 'warned', 'suspended', 'message_deleted', 'group_closed')),
  add column decision_note text check (decision_note is null or char_length(decision_note) <= 500),
  add column decided_at    timestamptz,
  add column decided_by    uuid references auth.users (id) on delete set null;
create index reports_status_idx on private.reports (status, created_at);
create index reports_target_idx on private.reports (reported_user_id, created_at);

-- ---------------------------------------------------------------------------
-- 2. Sanctions
-- ---------------------------------------------------------------------------
create table private.sanctions (
  id                 uuid        primary key default gen_random_uuid(),
  user_id            uuid        not null references auth.users (id) on delete cascade,
  kind               text        not null check (kind in ('warning', 'suspension')),
  -- Suspension : fin (null = sans limite). Avertissement : null.
  until              timestamptz,
  -- Motif montré à la personne (motif des signalements : spam, harcèlement…).
  user_reason        text        not null,
  -- Motif interne de l'administration (jamais montré à la personne).
  note               text        not null check (char_length(note) between 3 and 500),
  created_by         uuid        references auth.users (id) on delete set null,
  created_at         timestamptz not null default now(),
  acknowledged_at    timestamptz,
  lifted_at          timestamptz,
  lift_note          text        check (lift_note is null or char_length(lift_note) <= 500),
  appeal_text        text        check (appeal_text is null or char_length(appeal_text) between 3 and 500),
  appeal_at          timestamptz,
  appeal_decision    text        check (appeal_decision in ('upheld', 'lifted')),
  appeal_answered_at timestamptz,
  check (kind = 'suspension' or until is null)
);
create index sanctions_user_idx on private.sanctions (user_id, created_at desc);
revoke all on private.sanctions from public, anon, authenticated;

create or replace function private.active_suspension(p_uid uuid)
returns private.sanctions
language sql
stable
security definer
set search_path = ''
as $$
  select s.* from private.sanctions s
   where s.user_id = p_uid and s.kind = 'suspension' and s.lifted_at is null
     and (s.until is null or s.until > now())
   order by s.created_at desc
   limit 1;
$$;

create or replace function private.is_suspended(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.sanctions s
                  where s.user_id = p_uid and s.kind = 'suspension' and s.lifted_at is null
                    and (s.until is null or s.until > now()));
$$;

-- Compte suspendu : toutes les fonctions refusent ACCOUNT_SUSPENDED, sauf celles qui
-- servent à voir sa situation, contester, se déconnecter ou supprimer son compte. La liste
-- s'appuie sur le chemin de la requête, posé par l'API (PostgREST) et non par l'application.
create or replace function private.require_active_user()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_fn  text;
begin
  if v_uid is null or not private.session_is_active() then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  if private.is_suspended(v_uid) then
    v_fn := substring(coalesce(current_setting('request.path', true), '') from '/rpc/([a-z_]+)$');
    if v_fn is null or v_fn not in ('get_my_account', 'register_device', 'register_push_token',
                                    'unregister_push_token', 'unregister_current_device',
                                    'delete_my_account', 'my_moderation_status', 'submit_appeal',
                                    'acknowledge_warning', 'get_client_policies') then
      raise exception 'ACCOUNT_SUSPENDED' using errcode = 'P0001';
    end if;
  end if;
  return v_uid;
end;
$$;
revoke all on function private.require_active_user() from public;

-- ---------------------------------------------------------------------------
-- 3. Groupe fermé par Privio
-- ---------------------------------------------------------------------------
alter table public.conversations drop constraint if exists conversations_posting_check;
alter table public.conversations
  add constraint conversations_posting_check check (posting in ('all', 'admins', 'closed'));

-- Un groupe fermé ne se rouvre pas depuis l'application.
create or replace function private.keep_group_closed()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.posting = 'closed' and new.posting is distinct from 'closed'
     and coalesce(current_setting('privio.reopen_group', true), '') <> 'on' then
    raise exception 'GROUP_CLOSED' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger conversations_keep_closed before update of posting on public.conversations
  for each row execute function private.keep_group_closed();

create or replace function private.check_can_post(p_conversation_id uuid, p_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_conv public.conversations%rowtype;
  v_peer uuid;
begin
  select * into v_conv from public.conversations c where c.id = p_conversation_id;
  if v_conv.kind = 'direct' then
    v_peer := private.direct_peer(p_conversation_id, p_user_id);
    if v_peer is not null and private.is_blocked_between(p_user_id, v_peer) then
      raise exception 'BLOCKED' using errcode = 'P0001';
    end if;
  elsif v_conv.posting = 'closed' then
    raise exception 'GROUP_CLOSED' using errcode = 'P0001';
  elsif v_conv.posting = 'admins'
        and private.member_role(p_conversation_id, p_user_id) not in ('owner', 'admin') then
    raise exception 'POSTING_RESTRICTED' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function private.no_invite_closed_group()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.conversations c where c.id = new.conversation_id and c.posting = 'closed') then
    raise exception 'GROUP_CLOSED' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger group_invitations_not_closed before insert on private.group_invitations
  for each row execute function private.no_invite_closed_group();

-- ---------------------------------------------------------------------------
-- 4. Copie d'un vocal ou d'une photo signalés : lisible par l'administration seulement,
--    tant que le signalement existe (fichier gardé par report_hold_until).
-- ---------------------------------------------------------------------------
create or replace function private.can_read_evidence(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active() and private.is_console_admin(auth.uid())
     and exists (select 1 from private.reports r
                  where r.evidence ->> 'media_path' = p_name and r.purge_after > now());
$$;

do $$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists privio_evidence_read on storage.objects';
    execute $p$
      create policy privio_evidence_read on storage.objects
        for select to authenticated
        using (bucket_id in ('voice', 'photos') and private.can_read_evidence(name))
    $p$;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Notification à l'administration (sans contenu) : signalement, assistance, contestation
-- ---------------------------------------------------------------------------
create or replace function private.notify_admin(p_event text, p_ref uuid)
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
    using v_url || '/push-dispatch', jsonb_build_object('admin_event', p_event, 'ref_id', p_ref),
          jsonb_build_object('Content-Type', 'application/json', 'x-privio-push', v_token), 10000;
end;
$$;

create or replace function private.reports_notify_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.notify_admin(case when new.reason = 'support' then 'support' else 'report' end, new.id);
  return null;
end;
$$;
create trigger reports_notify_admin after insert on private.reports
  for each row execute function private.reports_notify_admin();

-- Jetons des téléphones de l'administration (réservé à push-dispatch).
create or replace function public.push_admin_targets(p_token text)
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
    from private.push_tokens t
    join public.devices d on d.id = t.device_id and d.revoked_at is null
   where private.is_console_admin(t.user_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Console : file des signalements
-- ---------------------------------------------------------------------------
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
  protected         boolean
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
         r.reported_user_id is not null and private.is_console_admin(r.reported_user_id)
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

-- « En cours » : l'administration a commencé à examiner ces signalements.
create or replace function public.console_take_reports(p_ids uuid[])
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console_admin();
  v_n   integer;
begin
  update private.reports set status = 'reviewing', taken_at = now()
   where id = any (coalesce(p_ids, '{}')) and status = 'open';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Copie jointe par la personne qui signale : ouverture journalisée.
create or replace function public.console_report_evidence(p_report_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console_admin();
  r     private.reports%rowtype;
begin
  select * into r from private.reports where id = p_report_id;
  if not found or r.evidence is null then
    raise exception 'REPORT_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'evidence', jsonb_build_object(
    'report', p_report_id,
    'handle', (select p.handle from public.profiles p where p.id = r.reported_user_id)));
  return jsonb_build_object(
    'kind', coalesce(r.evidence ->> 'kind', 'text'),
    'body', r.evidence ->> 'body',
    'sent_at', r.evidence ->> 'sent_at',
    'media_path', r.evidence ->> 'media_path',
    'duration_ms', r.evidence -> 'duration_ms');
end;
$$;

-- Sanctions d'un compte (fiche).
create or replace function public.console_sanctions(p_user_id uuid)
returns table (
  id              uuid,
  kind            text,
  until           timestamptz,
  user_reason     text,
  note            text,
  created_at      timestamptz,
  lifted_at       timestamptz,
  appeal_text     text,
  appeal_decision text
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
  select s.id, s.kind, s.until, s.user_reason, s.note, s.created_at, s.lifted_at, s.appeal_text, s.appeal_decision
    from private.sanctions s where s.user_id = p_user_id
   order by s.created_at desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Console : décisions
-- ---------------------------------------------------------------------------
create or replace function public.console_moderate(
  p_report_ids uuid[], p_action text, p_note text, p_days integer default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := private.require_console_admin();
  v_note    text := btrim(coalesce(p_note, ''));
  v_ids     uuid[];
  v_targets uuid[];
  v_target  uuid;
  v_reason  text;
  v_msgs    uuid[];
  v_convs   uuid[];
  v_msg     public.messages%rowtype;
  v_n       integer;
  v_mixed   boolean;
begin
  if p_action not in ('dismiss', 'warn', 'suspend', 'delete_message', 'close_group') then
    raise exception 'MODERATION_INVALID' using errcode = 'P0001';
  end if;
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  select array_agg(r.id), array_agg(distinct r.reported_user_id) filter (where r.reported_user_id is not null),
         mode() within group (order by r.reason),
         array_agg(distinct r.message_id) filter (where r.message_id is not null),
         array_agg(distinct r.conversation_id) filter (where r.reported_user_id is null and r.reason <> 'support'),
         bool_or(r.reported_user_id is null)
    into v_ids, v_targets, v_reason, v_msgs, v_convs, v_mixed
    from private.reports r
   where r.id = any (coalesce(p_report_ids, '{}')) and r.status in ('open', 'reviewing');
  if v_ids is null then
    raise exception 'REPORT_NOT_FOUND' using errcode = 'P0001';
  end if;

  if p_action in ('warn', 'suspend') then
    if coalesce(array_length(v_targets, 1), 0) <> 1 or v_mixed then
      raise exception 'MODERATION_INVALID' using errcode = 'P0001';
    end if;
    v_target := v_targets[1];
    if private.is_console_admin(v_target) then
      raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
    end if;
    if p_action = 'warn' then
      insert into private.sanctions (user_id, kind, user_reason, note, created_by)
      values (v_target, 'warning', v_reason, v_note, v_uid);
    else
      if p_days is not null and p_days not in (1, 7, 30) then
        raise exception 'MODERATION_INVALID' using errcode = 'P0001';
      end if;
      -- Une nouvelle suspension remplace celle en cours.
      update private.sanctions set lifted_at = now(), lift_note = 'Remplacée par une nouvelle suspension'
       where user_id = v_target and kind = 'suspension' and lifted_at is null;
      insert into private.sanctions (user_id, kind, until, user_reason, note, created_by)
      values (v_target, 'suspension',
              case when p_days is null then null else now() + make_interval(days => p_days) end,
              v_reason, v_note, v_uid);
    end if;
    perform private.signal_user(v_target, null, 'moderation');
  elsif p_action = 'delete_message' then
    if coalesce(array_length(v_msgs, 1), 0) <> 1 then
      raise exception 'MODERATION_INVALID' using errcode = 'P0001';
    end if;
    select * into v_msg from public.messages m where m.id = v_msgs[1];
    if found and v_msg.deleted_at is null then
      update public.messages set body = null, deleted_at = now(), edited_at = null, updated_at = now()
       where id = v_msg.id;
      delete from public.message_reactions where message_id = v_msg.id;
      perform private.signal_members(v_msg.conversation_id, 'message_changed');
    end if;
  elsif p_action = 'close_group' then
    if coalesce(array_length(v_convs, 1), 0) <> 1 or v_targets is not null
       or not exists (select 1 from public.conversations c where c.id = v_convs[1] and c.kind = 'group') then
      raise exception 'MODERATION_INVALID' using errcode = 'P0001';
    end if;
    update public.conversations set posting = 'closed' where id = v_convs[1] and posting <> 'closed';
    if found then
      update private.group_invitations set status = 'revoked'
       where conversation_id = v_convs[1] and status = 'pending';
      perform private.group_event(v_convs[1], null, 'closed');
    end if;
  end if;

  update private.reports
     set status = 'closed', taken_at = coalesce(taken_at, now()),
         decision = case p_action when 'dismiss' then 'dismissed' when 'warn' then 'warned'
                                  when 'suspend' then 'suspended' when 'delete_message' then 'message_deleted'
                                  else 'group_closed' end,
         decision_note = v_note, decided_at = clock_timestamp(), decided_by = v_uid
   where id = any (v_ids);
  get diagnostics v_n = row_count;
  perform private.admin_log(v_uid, 'moderation', jsonb_build_object(
    'action', p_action, 'days', p_days, 'reports', v_n,
    'handle', (select p.handle from public.profiles p where p.id = v_target),
    'group', (select c.title from public.conversations c where c.id = v_convs[1])));
  return v_n;
end;
$$;

-- Réactiver un compte suspendu.
create or replace function public.console_lift_suspension(p_user_id uuid, p_note text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_console_admin();
  v_note text := btrim(coalesce(p_note, ''));
begin
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  update private.sanctions set lifted_at = now(), lift_note = v_note
   where user_id = p_user_id and kind = 'suspension' and lifted_at is null
     and (until is null or until > now());
  if not found then
    return false;
  end if;
  perform private.admin_log(v_uid, 'lift', jsonb_build_object(
    'handle', (select p.handle from public.profiles p where p.id = p_user_id)));
  perform private.signal_user(p_user_id, null, 'moderation');
  return true;
end;
$$;

-- Contestations en attente.
create or replace function public.console_appeals()
returns table (
  sanction_id  uuid,
  user_id      uuid,
  handle       text,
  display_name text,
  until        timestamptz,
  user_reason  text,
  note         text,
  created_at   timestamptz,
  appeal_text  text,
  appeal_at    timestamptz
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
  select s.id, s.user_id, p.handle, p.display_name, s.until, s.user_reason, s.note, s.created_at,
         s.appeal_text, s.appeal_at
    from private.sanctions s
    left join public.profiles p on p.id = s.user_id
   where s.appeal_at is not null and s.appeal_decision is null
   order by s.appeal_at;
end;
$$;

create or replace function public.console_answer_appeal(p_sanction_id uuid, p_lift boolean, p_note text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_console_admin();
  v_note text := btrim(coalesce(p_note, ''));
  s      private.sanctions%rowtype;
begin
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  select * into s from private.sanctions where id = p_sanction_id for update;
  if not found or s.appeal_at is null or s.appeal_decision is not null then
    raise exception 'APPEAL_NOT_FOUND' using errcode = 'P0001';
  end if;
  update private.sanctions
     set appeal_decision = case when p_lift then 'lifted' else 'upheld' end,
         appeal_answered_at = now(),
         lifted_at = case when p_lift and lifted_at is null then now() else lifted_at end,
         lift_note = case when p_lift and lifted_at is null then v_note else lift_note end
   where id = p_sanction_id;
  perform private.admin_log(v_uid, 'appeal', jsonb_build_object(
    'lift', p_lift, 'handle', (select p.handle from public.profiles p where p.id = s.user_id)));
  perform private.signal_user(s.user_id, null, 'moderation');
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Côté personne sanctionnée
-- ---------------------------------------------------------------------------
create or replace function public.my_moderation_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  s     private.sanctions%rowtype := private.active_suspension(v_uid);
  w     private.sanctions%rowtype;
begin
  select * into w from private.sanctions x
   where x.user_id = v_uid and x.kind = 'warning' and x.acknowledged_at is null
   order by x.created_at limit 1;
  return jsonb_build_object(
    'suspension', case when s.id is null then null else jsonb_build_object(
      'id', s.id, 'until', s.until, 'reason', s.user_reason, 'created_at', s.created_at,
      'appealed', s.appeal_at is not null, 'appeal_decision', s.appeal_decision) end,
    'warning', case when w.id is null then null else jsonb_build_object(
      'id', w.id, 'reason', w.user_reason, 'created_at', w.created_at) end);
end;
$$;

create or replace function public.submit_appeal(p_sanction_id uuid, p_text text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_text text := btrim(coalesce(p_text, ''));
begin
  if char_length(v_text) < 3 or char_length(v_text) > 500 then
    raise exception 'APPEAL_INVALID' using errcode = 'P0001';
  end if;
  update private.sanctions set appeal_text = v_text, appeal_at = now()
   where id = p_sanction_id and user_id = v_uid and kind = 'suspension' and appeal_at is null
     and lifted_at is null;
  if not found then
    raise exception 'APPEAL_NOT_ALLOWED' using errcode = 'P0001';
  end if;
  perform private.notify_admin('appeal', p_sanction_id);
end;
$$;

create or replace function public.acknowledge_warning(p_sanction_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  update private.sanctions set acknowledged_at = now()
   where id = p_sanction_id and user_id = v_uid and kind = 'warning' and acknowledged_at is null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Journal de la console : détail des actions de modération
-- ---------------------------------------------------------------------------
drop function if exists public.console_journal(integer);
create or replace function public.console_journal(p_limit integer default 100)
returns table (
  id         bigint,
  action     text,
  key        text,
  label      text,
  before     jsonb,
  after      jsonb,
  detail     jsonb,
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
         a.detail -> 'before', a.detail -> 'after', a.detail, a.created_at
    from private.admin_audit a
   where a.action <> 'reports'
   order by a.id desc
   limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Nettoyage : sanctions gardées 1 an (sauf suspension sans limite encore active)
-- ---------------------------------------------------------------------------
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
  delete from private.sanctions
   where created_at < now() - interval '1 year'
     and (kind = 'warning' or lifted_at is not null or (until is not null and until < now()));
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits : la lecture des copies signalées rejoint les fonctions utilisées par la RLS.
-- ---------------------------------------------------------------------------
create or replace function private.harden_privileges()
returns void
language plpgsql
set search_path = ''
as $$
declare
  r record;
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
  grant execute on function private.session_is_active() to authenticated;
  grant execute on function private.is_member(uuid, uuid) to authenticated;
  grant execute on function private.shares_conversation(uuid, uuid) to authenticated;
  grant execute on function private.can_see_message(uuid, timestamptz, uuid) to authenticated;
  grant execute on function private.can_read_voice(text) to authenticated;
  grant execute on function private.can_read_photo(text) to authenticated;
  grant execute on function private.can_read_avatar(text) to authenticated;
  grant execute on function private.can_read_evidence(text) to authenticated;
  execute 'revoke all on all tables in schema private from public, anon, authenticated';
end;
$$;

select private.harden_privileges();
grant execute on function public.console_reports(text) to authenticated;
grant execute on function public.console_take_reports(uuid[]) to authenticated;
grant execute on function public.console_report_evidence(uuid) to authenticated;
grant execute on function public.console_sanctions(uuid) to authenticated;
grant execute on function public.console_moderate(uuid[], text, text, integer) to authenticated;
grant execute on function public.console_lift_suspension(uuid, text) to authenticated;
grant execute on function public.console_appeals() to authenticated;
grant execute on function public.console_answer_appeal(uuid, boolean, text) to authenticated;
grant execute on function public.console_journal(integer) to authenticated;
grant execute on function public.my_moderation_status() to authenticated;
grant execute on function public.submit_appeal(uuid, text) to authenticated;
grant execute on function public.acknowledge_warning(uuid) to authenticated;
revoke all on function public.push_admin_targets(text) from authenticated;
grant execute on function public.push_admin_targets(text) to service_role;
