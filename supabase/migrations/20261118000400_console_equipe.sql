-- PRIVIO — lot 5.8 : console, équipe et modération (ADR-053, décisions du 18/11/2026).
--
-- A. Plusieurs personnes dans l'équipe, trois rôles :
--    * Propriétaire : le compte dont le numéro est `admin_phone_e164` (inchangé) ; tout ;
--    * Modérateur : signalements (hors assistance), sanctions, contestations, groupes, sites
--      sans aperçu, suivi de la modération ;
--    * Assistance : demandes d'assistance, fiches des comptes sans pouvoir sanctionner,
--      déconnexion d'un téléphone, réinitialisation des deux étapes.
--    Tableau de bord (chiffres seulement) et réponses types : toute l'équipe. Réglages,
--    fonctionnalités, statistiques, santé du service, journal, équipe : propriétaire seul.
-- B. Le propriétaire ajoute une personne par le numéro d'un compte Privio existant ; la
--    vérification en deux étapes est obligatoire pour l'équipe (CONSOLE_TWO_STEP_REQUIRED sinon) ;
--    ajouts, changements de rôle et retraits sont inscrits au journal. 10 personnes au plus.
-- C. Liste des groupes : titre, type, nombre de membres, création, signalements ; jamais
--    les messages. Fermer, rouvrir ou supprimer un groupe, avec un motif journalisé.
-- D. Réponses types : réponses d'assistance et motifs de décision, gérés par le
--    propriétaire, utilisés par l'équipe.
-- E. Sites sans aperçu : le lien reste envoyé, sans aperçu.
-- F. Suivi de la modération : reçus, traités, délai, motifs, par personne (7 ou 30 jours).
-- Toute fonction de la console non redéfinie ici reste réservée au propriétaire.

create table private.console_staff (
  user_id  uuid        primary key references auth.users (id) on delete cascade,
  role     text        not null check (role in ('moderator', 'support')),
  added_by uuid        references auth.users (id) on delete set null,
  added_at timestamptz not null default now()
);
revoke all on private.console_staff from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Rôles
-- ---------------------------------------------------------------------------
create or replace function private.console_owner(p_uid uuid)
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

-- 'owner', 'moderator', 'support' ou null.
create or replace function private.console_role(p_uid uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when private.console_owner(p_uid) then 'owner'
              else (select s.role from private.console_staff s
                      join public.profiles p on p.id = s.user_id and p.deleted_at is null
                     where s.user_id = p_uid) end;
$$;

-- Toute personne de l'équipe (protégée des sanctions, alertes, accès à la console).
create or replace function private.is_console_admin(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.console_role(p_uid) is not null;
$$;

-- Session active, rôle parmi [p_roles], deux étapes activées (sauf propriétaire) ;
-- sinon ADMIN_REQUIRED (même réponse pour tous) ou CONSOLE_TWO_STEP_REQUIRED.
create or replace function private.require_console(p_roles text[])
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_role text := private.console_role(v_uid);
begin
  if v_role is null or not (v_role = any (p_roles)) then
    raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
  end if;
  if v_role <> 'owner' and not exists (select 1 from private.two_step t where t.user_id = v_uid) then
    raise exception 'CONSOLE_TWO_STEP_REQUIRED' using errcode = 'P0001';
  end if;
  return v_uid;
end;
$$;

-- Ancienne vérification : désormais le propriétaire seul (tout ce qui n'est pas redéfini).
create or replace function private.require_console_admin()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select private.require_console('{owner}');
$$;

-- Assistance : les demandes d'assistance ; modérateur : le reste ; propriétaire : tout.
create or replace function private.report_for_role(p_reason text, p_role text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_role when 'owner' then true
                     when 'support' then p_reason = 'support'
                     when 'moderator' then p_reason <> 'support'
                     else false end;
$$;

create or replace function public.console_access()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and private.session_is_active() and private.is_console_admin(auth.uid());
$$;

-- Mon rôle dans la console (et ce qui manque pour l'ouvrir).
create or replace function public.console_me()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_role text := private.console_role(v_uid);
begin
  if v_role is null then
    raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'role', v_role,
    'two_step', exists (select 1 from private.two_step t where t.user_id = v_uid),
    'two_step_required', v_role <> 'owner');
end;
$$;

-- Preuves (photo, vocal signalés) : propriétaire et modérateurs.
create or replace function private.can_read_evidence(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.session_is_active()
     and private.console_role(auth.uid()) in ('owner', 'moderator')
     and (private.console_role(auth.uid()) = 'owner'
          or exists (select 1 from private.two_step t where t.user_id = auth.uid()))
     and (exists (select 1 from private.reports r
                   where r.evidence ->> 'media_path' = p_name and r.purge_after > now())
          or exists (select 1 from public.profiles p where p.avatar_path = p_name));
$$;

-- Alertes de la console, selon le rôle : signalements et contestations → propriétaire et
-- modérateurs ; assistance → propriétaire et assistance ; le reste → propriétaire.
create or replace function public.push_admin_targets(p_token text, p_event text)
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
   where private.console_role(t.user_id) = 'owner'
      or (p_event in ('report', 'appeal') and private.console_role(t.user_id) = 'moderator')
      or (p_event = 'support' and private.console_role(t.user_id) = 'support');
end;
$$;

-- Journal : nouveaux types « équipe » et « groupes ».
create or replace function private.journal_type(p_action text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_action in ('account', 'account_search', 'account_list', 'lift',
                      'avatar_remove', 'handle_reset') then 'accounts'
    when p_action in ('moderation', 'evidence', 'appeal') then 'reports'
    when p_action in ('group_close', 'group_reopen', 'group_delete') then 'groups'
    when p_action in ('policy', 'reserved_handle', 'template', 'site') then 'settings'
    when p_action in ('two_step_reset', 'disconnect') then 'security'
    when p_action in ('team_add', 'team_role', 'team_remove') then 'team'
    when p_action = 'reply' then 'support'
    else 'views'
  end;
$$;

-- ---------------------------------------------------------------------------
-- B. Équipe (propriétaire)
-- ---------------------------------------------------------------------------
create or replace function public.console_team()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console('{owner}');
begin
  perform private.admin_log(v_uid, 'team', null);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'user_id', x.user_id, 'role', x.role, 'name', p.display_name, 'handle', p.handle,
             'avatar', p.avatar_path, 'phone', c.phone_e164, 'added_at', x.added_at,
             'two_step', exists (select 1 from private.two_step t where t.user_id = x.user_id),
             'last_action_at', (select max(a.created_at) from private.admin_audit a
                                 where a.admin_id = x.user_id))
             order by x.role = 'owner' desc, p.display_name)
      from (select s.user_id, s.role, s.added_at from private.console_staff s
            union all
            select v_uid, 'owner', null) x
      join public.profiles p on p.id = x.user_id and p.deleted_at is null
      left join private.user_contacts c on c.user_id = x.user_id), '[]'::jsonb);
end;
$$;

create or replace function public.console_team_add(p_phone text, p_role text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_console('{owner}');
  v_target uuid;
begin
  if p_role not in ('moderator', 'support') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  select c.user_id into v_target from private.user_contacts c
    join public.profiles p on p.id = c.user_id and p.deleted_at is null
   where c.phone_e164 = btrim(coalesce(p_phone, ''));
  if v_target is null then
    raise exception 'STAFF_NOT_FOUND' using errcode = 'P0001';
  end if;
  if private.console_owner(v_target) then
    raise exception 'STAFF_OWNER' using errcode = 'P0001';
  end if;
  if not exists (select 1 from private.console_staff s where s.user_id = v_target)
     and (select count(*) from private.console_staff) >= 10 then
    raise exception 'STAFF_LIMIT' using errcode = 'P0001';
  end if;
  insert into private.console_staff (user_id, role, added_by) values (v_target, p_role, v_uid)
  on conflict (user_id) do update set role = excluded.role;
  perform private.admin_log(v_uid, 'team_add', jsonb_build_object(
    'handle', (select p.handle from public.profiles p where p.id = v_target), 'role', p_role));
  -- Son application affiche l'entrée « Administration ».
  perform private.signal_user(v_target, null, 'moderation');
  return jsonb_build_object('user_id', v_target, 'role', p_role);
end;
$$;

create or replace function public.console_team_set_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console('{owner}');
begin
  if p_role not in ('moderator', 'support') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  update private.console_staff set role = p_role where user_id = p_user_id;
  if not found then
    raise exception 'STAFF_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'team_role', jsonb_build_object(
    'handle', (select p.handle from public.profiles p where p.id = p_user_id), 'role', p_role));
end;
$$;

create or replace function public.console_team_remove(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console('{owner}');
begin
  delete from private.console_staff where user_id = p_user_id;
  if not found then
    raise exception 'STAFF_NOT_FOUND' using errcode = 'P0001';
  end if;
  -- Dossiers pris en charge par cette personne : de nouveau à traiter.
  perform private.admin_log(v_uid, 'team_remove', jsonb_build_object(
    'handle', (select p.handle from public.profiles p where p.id = p_user_id)));
  perform private.signal_user(p_user_id, null, 'moderation');
end;
$$;

-- ---------------------------------------------------------------------------
-- C. Groupes (propriétaire et modérateurs) — jamais les messages
-- ---------------------------------------------------------------------------
alter table private.reports drop constraint reports_decision_check;
alter table private.reports add constraint reports_decision_check
  check (decision in ('dismissed', 'warned', 'suspended', 'message_deleted', 'group_closed',
                      'answered', 'group_deleted'));

create or replace function private.console_group_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', c.id, 'title', c.title, 'announcement', c.announcement, 'posting', c.posting,
    'closed', c.posting = 'closed', 'created_at', c.created_at,
    'last_activity', (c.last_message_at at time zone 'utc')::date,
    'members', (select count(*) from public.conversation_members m
                 where m.conversation_id = c.id and m.left_at is null),
    'admins', (select count(*) from public.conversation_members m
                where m.conversation_id = c.id and m.left_at is null and m.role in ('owner', 'admin')),
    'owner_id', (select m.user_id from public.conversation_members m
                  where m.conversation_id = c.id and m.left_at is null and m.role = 'owner' limit 1),
    'owner_handle', (select p.handle from public.conversation_members m
                       join public.profiles p on p.id = m.user_id
                      where m.conversation_id = c.id and m.left_at is null and m.role = 'owner' limit 1),
    'reports_open', (select count(*) from private.reports r
                      where r.conversation_id = c.id and r.status in ('open', 'reviewing')
                        and r.reason <> 'support'),
    'reports_90d', (select count(*) from private.reports r
                     where r.conversation_id = c.id and r.reason <> 'support'
                       and r.created_at > now() - interval '90 days'))
    from public.conversations c
   where c.id = p_id and c.kind = 'group';
$$;

-- p_filter : 'all', 'reported' (signalements en attente), 'closed', 'announcement'.
create or replace function public.console_groups_page(p_query text default null, p_filter text default 'all',
                                                      p_page integer default 1, p_size integer default 30)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_console('{owner,moderator}');
  v_size  integer := least(greatest(coalesce(p_size, 30), 5), 100);
  v_page  integer := greatest(coalesce(p_page, 1), 1);
  v_q     text := nullif(lower(btrim(coalesce(p_query, ''))), '');
  v_total integer;
  v_rows  jsonb;
begin
  if coalesce(p_filter, 'all') not in ('all', 'reported', 'closed', 'announcement') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'groups', jsonb_build_object('filter', p_filter));
  with g as (
    select c.id, c.created_at as created from public.conversations c
     where c.kind = 'group'
       and (v_q is null or position(v_q in lower(c.title)) > 0)
       and case coalesce(p_filter, 'all')
             when 'reported' then exists (select 1 from private.reports r where r.conversation_id = c.id
                                           and r.status in ('open', 'reviewing') and r.reason <> 'support')
             when 'closed' then c.posting = 'closed'
             when 'announcement' then c.announcement
             else true end)
  select (select count(*) from g),
         (select coalesce(jsonb_agg(private.console_group_json(x.id) order by x.created desc), '[]'::jsonb)
            from (select * from g order by created desc offset (v_page - 1) * v_size limit v_size) x)
    into v_total, v_rows;
  return jsonb_build_object('total', v_total, 'page', v_page, 'size', v_size, 'rows', v_rows);
end;
$$;

create or replace function public.console_group(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console('{owner,moderator}');
  v     jsonb := private.console_group_json(p_id);
begin
  if v is null then
    raise exception 'GROUP_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'group', jsonb_build_object('group', v ->> 'title'));
  return v;
end;
$$;

-- p_action : 'close' (plus personne n'écrit), 'reopen', 'delete'. Motif obligatoire.
create or replace function public.console_group_action(p_id uuid, p_action text, p_note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_console('{owner,moderator}');
  v_note text := btrim(coalesce(p_note, ''));
  c      public.conversations%rowtype;
begin
  if p_action not in ('close', 'reopen', 'delete') then
    raise exception 'MODERATION_INVALID' using errcode = 'P0001';
  end if;
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  select * into c from public.conversations x where x.id = p_id and x.kind = 'group' for update;
  if not found then
    raise exception 'GROUP_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'group_' || p_action, jsonb_build_object('group', c.title, 'note', v_note));
  if p_action = 'close' then
    if c.posting <> 'closed' then
      update public.conversations set posting = 'closed' where id = p_id;
      update private.group_invitations set status = 'revoked'
       where conversation_id = p_id and status = 'pending';
      perform private.group_event(p_id, null, 'closed');
    end if;
  elsif p_action = 'reopen' then
    if c.posting = 'closed' then
      -- Un groupe fermé ne se rouvre que par la console.
      perform set_config('privio.reopen_group', 'on', true);
      update public.conversations set posting = case when c.announcement then 'admins' else 'all' end
       where id = p_id;
      perform set_config('privio.reopen_group', '', true);
      perform private.group_event(p_id, null, 'reopened');
    end if;
  end if;
  -- Signalements en attente sur ce groupe : traités par cette décision.
  if p_action in ('close', 'delete') then
    update private.reports
       set status = 'closed', taken_at = coalesce(taken_at, now()),
           decision = case when p_action = 'close' then 'group_closed' else 'group_deleted' end,
           decision_note = v_note, decided_at = clock_timestamp(), decided_by = v_uid
     where conversation_id = p_id and status in ('open', 'reviewing') and reason <> 'support';
  end if;
  if p_action = 'delete' then
    perform private.delete_group(p_id, null);
    return null;
  end if;
  return private.console_group_json(p_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- D. Réponses types
-- ---------------------------------------------------------------------------
create table private.console_templates (
  id         uuid        primary key default gen_random_uuid(),
  kind       text        not null check (kind in ('support', 'decision')),
  title      text        not null check (char_length(title) between 1 and 60),
  body       text        not null check (char_length(body) between 2 and 1000),
  updated_at timestamptz not null default now(),
  updated_by uuid        references auth.users (id) on delete set null
);
revoke all on private.console_templates from public, anon, authenticated;

insert into private.console_templates (kind, title, body) values
  ('support', 'Problème corrigé', 'Merci, le problème est corrigé.'),
  ('support', 'Mettre à jour', 'Mettez à jour l’application puis réessayez.'),
  ('support', 'Plus de détails', 'Nous avons besoin de plus de détails : que voyez-vous à l’écran ?'),
  ('decision', 'Insultes confirmées', 'Propos insultants confirmés par la preuve.'),
  ('decision', 'Arnaque confirmée', 'Arnaque confirmée : même message envoyé à plusieurs personnes.'),
  ('decision', 'Sans fondement', 'Signalement non fondé après vérification.');

create or replace function public.console_templates()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_console('{owner,moderator,support}');
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.kind, 'title', t.title,
                                                       'body', t.body, 'updated_at', t.updated_at)
                                    order by t.kind, t.title)
                     from private.console_templates t), '[]'::jsonb);
end;
$$;

-- Créer (p_id null) ou modifier une réponse type (propriétaire). 40 au plus.
create or replace function public.console_template_save(p_id uuid, p_kind text, p_title text, p_body text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_console('{owner}');
  v_title text := btrim(coalesce(p_title, ''));
  v_body  text := btrim(coalesce(p_body, ''));
  v_id    uuid;
begin
  if p_kind not in ('support', 'decision') or char_length(v_title) not between 1 and 60
     or char_length(v_body) not between 2 and (case when p_kind = 'decision' then 500 else 1000 end) then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if p_id is null then
    if (select count(*) from private.console_templates) >= 40 then
      raise exception 'RATE_LIMITED' using errcode = 'P0001';
    end if;
    insert into private.console_templates (kind, title, body, updated_by)
    values (p_kind, v_title, v_body, v_uid) returning id into v_id;
  else
    update private.console_templates
       set kind = p_kind, title = v_title, body = v_body, updated_at = now(), updated_by = v_uid
     where id = p_id returning id into v_id;
    if v_id is null then
      raise exception 'BODY_INVALID' using errcode = 'P0001';
    end if;
  end if;
  perform private.admin_log(v_uid, 'template', jsonb_build_object('title', v_title));
  return v_id;
end;
$$;

create or replace function public.console_template_delete(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_console('{owner}');
  v_title text;
begin
  delete from private.console_templates where id = p_id returning title into v_title;
  if v_title is not null then
    perform private.admin_log(v_uid, 'template', jsonb_build_object('title', v_title, 'deleted', true));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- E. Sites sans aperçu
-- ---------------------------------------------------------------------------
create table private.preview_blocked_sites (
  domain   text        primary key check (domain ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'
                                          and char_length(domain) <= 253),
  added_at timestamptz not null default now(),
  added_by uuid        references auth.users (id) on delete set null
);
revoke all on private.preview_blocked_sites from public, anon, authenticated;

-- Nom de domaine d'une adresse (sans « www. »).
create or replace function private.url_host(p_url text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(lower(substring(p_url from '^[a-zA-Z][a-zA-Z0-9+.-]*://(?:[^@/?#]*@)?([^:/?#]+)')),
                        '^www\.', '');
$$;

-- Site bloqué : le domaine lui-même ou l'un de ses sous-domaines.
create or replace function private.preview_blocked(p_url text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.preview_blocked_sites s
                  where private.url_host(p_url) = s.domain
                     or private.url_host(p_url) like '%.' || s.domain);
$$;

create or replace function public.console_blocked_sites()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_console('{owner,moderator}');
  return coalesce((select jsonb_agg(jsonb_build_object('domain', s.domain, 'added_at', s.added_at)
                                    order by s.domain)
                     from private.preview_blocked_sites s), '[]'::jsonb);
end;
$$;

-- Ajouter (p_blocked) ou retirer un site. Accepte une adresse complète ou un domaine.
create or replace function public.console_block_site(p_site text, p_blocked boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_console('{owner,moderator}');
  v_raw    text := lower(btrim(coalesce(p_site, '')));
  v_domain text;
begin
  v_domain := case when v_raw ~ '^[a-z][a-z0-9+.-]*://' then private.url_host(v_raw)
                   else regexp_replace(split_part(split_part(v_raw, '/', 1), ':', 1), '^www\.', '') end;
  if v_domain is null or v_domain !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'
     or char_length(v_domain) > 253 then
    raise exception 'SITE_INVALID' using errcode = 'P0001';
  end if;
  if p_blocked then
    if (select count(*) from private.preview_blocked_sites) >= 500 then
      raise exception 'RATE_LIMITED' using errcode = 'P0001';
    end if;
    insert into private.preview_blocked_sites (domain, added_by) values (v_domain, v_uid)
    on conflict (domain) do nothing;
  else
    delete from private.preview_blocked_sites where domain = v_domain;
  end if;
  perform private.admin_log(v_uid, 'site', jsonb_build_object('domain', v_domain, 'blocked', p_blocked));
  return v_domain;
end;
$$;

-- ---------------------------------------------------------------------------
-- F. Suivi de la modération (propriétaire et modérateurs)
-- ---------------------------------------------------------------------------
create or replace function public.console_moderation_stats(p_days integer default 7)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_console('{owner,moderator}');
  v_since timestamptz;
begin
  if p_days not in (7, 30) then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  v_since := now() - make_interval(days => p_days);
  perform private.admin_log(v_uid, 'moderation_stats', jsonb_build_object('days', p_days));
  return jsonb_build_object(
    'days', p_days,
    'received', (select count(*) from private.reports r where r.created_at >= v_since and r.reason <> 'support'),
    'decided', (select count(*) from private.reports r where r.decided_at >= v_since and r.reason <> 'support'),
    'support_received', (select count(*) from private.reports r where r.created_at >= v_since and r.reason = 'support'),
    'support_answered', (select count(*) from private.reports r where r.replied_at >= v_since and r.reason = 'support'),
    'open_now', (select count(*) from private.reports r where r.status in ('open', 'reviewing') and r.reason <> 'support'),
    'oldest_open_hours', (select floor(extract(epoch from now() - min(r.created_at)) / 3600)::int
                            from private.reports r where r.status in ('open', 'reviewing') and r.reason <> 'support'),
    'avg_hours', (select round((avg(extract(epoch from r.decided_at - r.created_at)) / 3600)::numeric, 1)
                    from private.reports r where r.decided_at >= v_since and r.reason <> 'support'),
    'appeals', (select count(*) from private.sanctions s where s.appeal_at >= v_since),
    'by_reason', coalesce((select jsonb_object_agg(x.reason, x.n) from (
                    select r.reason, count(*) as n from private.reports r
                     where r.created_at >= v_since and r.reason <> 'support' group by r.reason) x), '{}'::jsonb),
    'by_decision', coalesce((select jsonb_object_agg(x.decision, x.n) from (
                    select r.decision, count(*) as n from private.reports r
                     where r.decided_at >= v_since and r.reason <> 'support' and r.decision is not null
                     group by r.decision) x), '{}'::jsonb),
    'by_person', coalesce((select jsonb_agg(jsonb_build_object(
                    'name', coalesce(p.display_name, '@' || p.handle), 'role', private.console_role(x.who),
                    'decided', x.n, 'avg_hours', x.h) order by x.n desc) from (
                    select coalesce(r.decided_by, r.replied_by) as who, count(*) as n,
                           round((avg(extract(epoch from r.decided_at - r.created_at)) / 3600)::numeric, 1) as h
                      from private.reports r
                     where r.decided_at >= v_since and coalesce(r.decided_by, r.replied_by) is not null
                     group by 1) x
                    left join public.profiles p on p.id = x.who), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- Fonctions existantes ouvertes à l'équipe selon le rôle (le reste : propriétaire)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.console_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid   uuid := private.require_console('{owner,moderator,support}');
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
$function$;

CREATE OR REPLACE FUNCTION public.console_search_accounts(p_query text)
 RETURNS TABLE(user_id uuid, handle text, display_name text, avatar_path text, phone_e164 text, created_at timestamp with time zone, deleted boolean, suspended boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid    uuid := private.require_console('{owner,moderator,support}');
  v_q      text := btrim(coalesce(p_query, ''));
  v_digits text := regexp_replace(v_q, '[^0-9]', '', 'g');
begin
  if v_q ~ '^[+0-9 .-]+$' then
    perform private.admin_log(v_uid, 'account_search', jsonb_build_object('by', 'phone'));
    if char_length(v_digits) < 4 then
      raise exception 'SEARCH_PHONE_INCOMPLETE' using errcode = 'P0001';
    end if;
    return query
    select p.id, p.handle, p.display_name,
           case when p.deleted_at is null then p.avatar_path end, c.phone_e164,
           p.created_at, p.deleted_at is not null, private.is_suspended(p.id)
      from private.user_contacts c
      join public.profiles p on p.id = c.user_id
     where c.phone_e164 like '%' || v_digits || '%'
     order by private.name_sort_key(p.display_name), p.handle
     limit 30;
    return;
  end if;
  v_q := lower(ltrim(v_q, '@'));
  if char_length(v_q) < 2 then
    raise exception 'SEARCH_TOO_SHORT' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'account_search', jsonb_build_object('by', 'name'));
  return query
  select p.id, p.handle, p.display_name,
         case when p.deleted_at is null then p.avatar_path end, c.phone_e164,
         p.created_at, p.deleted_at is not null, private.is_suspended(p.id)
    from public.profiles p
    left join private.user_contacts c on c.user_id = p.id
   where p.handle like replace(replace(v_q, '%', ''), '_', '\_') || '%'
      or lower(p.display_name) like '%' || replace(v_q, '%', '') || '%'
   order by (p.handle = v_q) desc, p.handle
   limit 30;
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_accounts_page(p_page integer DEFAULT 1, p_size integer DEFAULT 25, p_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid     uuid := private.require_console('{owner,moderator,support}');
  v_size    integer := least(greatest(coalesce(p_size, 25), 5), 100);
  v_page    integer := greatest(coalesce(p_page, 1), 1);
  v_filter  text := coalesce(p_filter, 'all');
  v_total   integer;
  v_rows    jsonb;
  v_letters jsonb;
  v_counts  jsonb;
begin
  if v_filter not in ('all', 'suspended', 'deleted', 'new', 'inactive', 'two_step') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'account_list',
    jsonb_build_object('page', v_page, 'filter', v_filter));
  with ordered as (
    select p.id,
           row_number() over (order by private.name_sort_key(p.display_name), p.handle) - 1 as pos,
           left(private.name_sort_key(p.display_name), 1) as initial
      from public.profiles p
     where private.account_matches(v_filter, p)
  )
  select
    (select count(*) from ordered),
    (select coalesce(jsonb_agg(private.account_row(p) order by o.pos), '[]'::jsonb)
       from ordered o join public.profiles p on p.id = o.id
      where o.pos >= (v_page - 1) * v_size and o.pos < v_page * v_size),
    (select coalesce(jsonb_object_agg(l.letter, l.first_pos), '{}'::jsonb)
       from (select case when o.initial ~ '^[A-Z]$' then o.initial else '#' end as letter,
                    min(o.pos) as first_pos
               from ordered o group by 1) l)
    into v_total, v_rows, v_letters;
  -- Nombre de comptes par filtre (pastilles).
  select jsonb_build_object(
           'all', count(*),
           'suspended', count(*) filter (where private.account_matches('suspended', p)),
           'deleted', count(*) filter (where p.deleted_at is not null),
           'new', count(*) filter (where p.created_at > now() - interval '7 days'),
           'inactive', count(*) filter (where private.account_matches('inactive', p)),
           'two_step', count(*) filter (where private.account_matches('two_step', p)))
    into v_counts
    from public.profiles p;
  return jsonb_build_object('total', v_total, 'page', v_page, 'size', v_size, 'filter', v_filter,
                            'rows', v_rows, 'letters', v_letters, 'counts', v_counts);
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_account(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := private.require_console('{owner,moderator,support}');
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
  perform private.admin_log(v_uid, 'account', jsonb_build_object('handle', p.handle, 'user_id', p.id));
  return jsonb_build_object(
    'user_id', p.id,
    'handle', p.handle,
    'display_name', p.display_name,
    'avatar_path', case when p.deleted_at is null then p.avatar_path end,
    'phone_e164', (select c.phone_e164 from private.user_contacts c where c.user_id = p.id),
    'created_at', p.created_at,
    'deleted', p.deleted_at is not null,
    'last_seen_day', (private.last_seen(p_user_id) at time zone 'utc')::date,
    'last_seen_at', private.last_seen(p_user_id),
    'suspended', s.id is not null,
    'suspended_until', s.until,
    'protected', private.is_console_admin(p_user_id),
    'handle_reset', p.handle_reset_at is not null,
    'two_step', exists (select 1 from private.two_step t where t.user_id = p_user_id),
    'device', case when d.id is null then null else jsonb_build_object(
      'platform', d.platform, 'app_version', d.app_version, 'since', d.created_at,
      'push', exists (select 1 from private.push_tokens t where t.device_id = d.id)) end,
    'devices', (select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb) from (
        select dv.created_at, jsonb_build_object(
                 'id', dv.id, 'platform', dv.platform, 'app_version', dv.app_version,
                 'model', dv.model, 'os_version', dv.os_version, 'created_at', dv.created_at,
                 'last_seen_at', dv.last_seen_at, 'revoked_at', dv.revoked_at,
                 'revoked_reason', dv.revoked_reason,
                 'push', dv.revoked_at is null
                         and exists (select 1 from private.push_tokens t where t.device_id = dv.id)) j
          from public.devices dv where dv.user_id = p_user_id
         order by dv.created_at desc limit 10) x),
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
                 where r.reporter_id = p_user_id and r.reason = 'support' and r.purge_after > now()),
    -- Actions de l'administration sur ce compte (hors sanctions, listées à part).
    'actions', (select coalesce(jsonb_agg(jsonb_build_object(
                    'action', a.action, 'created_at', a.created_at, 'detail', a.detail)
                  order by a.id desc), '[]'::jsonb)
                  from (select * from private.admin_audit a
                         where a.action in ('avatar_remove', 'handle_reset', 'disconnect', 'two_step_reset')
                           and (a.detail ->> 'user_id' = p_user_id::text
                                or (a.detail ->> 'user_id' is null and a.detail ->> 'handle' = p.handle))
                         order by a.id desc limit 20) a));
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_two_step(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := private.require_console('{owner,moderator,support}');
  t     private.two_step%rowtype;
begin
  select * into t from private.two_step where user_id = p_user_id;
  return jsonb_build_object(
    'enabled', found,
    'enabled_at', t.enabled_at,
    'reset_requested_at', t.reset_requested_at);
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_sanctions(p_user_id uuid)
 RETURNS TABLE(id uuid, kind text, until timestamp with time zone, user_reason text, note text, created_at timestamp with time zone, lifted_at timestamp with time zone, appeal_text text, appeal_decision text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  perform private.require_console('{owner,moderator,support}');
  return query
  select s.id, s.kind, s.until, s.user_reason, s.note, s.created_at, s.lifted_at, s.appeal_text, s.appeal_decision
    from private.sanctions s where s.user_id = p_user_id
   order by s.created_at desc;
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_reports(p_status text DEFAULT 'open'::text)
 RETURNS TABLE(id uuid, kind text, reason text, details text, status text, created_at timestamp with time zone, taken_at timestamp with time zone, decision text, decision_note text, decided_at timestamp with time zone, reporter_handle text, reported_user_id uuid, reported_handle text, reported_name text, reported_since timestamp with time zone, conversation_id uuid, group_title text, group_closed boolean, message_id uuid, evidence_kind text, reports_90d integer, reporters_90d integer, suspended boolean, suspended_until timestamp with time zone, sanctions_count integer, protected boolean, reply text, replied_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid uuid := private.require_console('{owner,moderator,support}');
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
     and private.report_for_role(r.reason, private.console_role(v_uid))
   order by case when p_status = 'closed' then extract(epoch from r.decided_at) * -1
                 else extract(epoch from r.created_at) end
   limit 300;
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_take_reports(p_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := private.require_console('{owner,moderator,support}');
  v_n   integer;
begin
  update private.reports set status = 'reviewing', taken_at = now()
   where id = any (coalesce(p_ids, '{}')) and status = 'open'
     and private.report_for_role(reason, private.console_role(v_uid));
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_moderate(p_report_ids uuid[], p_action text, p_note text, p_days integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid     uuid := private.require_console('{owner,moderator,support}');
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
  -- Lot 5.8 : chacun ses dossiers (assistance : classer seulement ses demandes).
  if exists (select 1 from private.reports r where r.id = any (v_ids)
              and not private.report_for_role(r.reason, private.console_role(v_uid)))
     or (private.console_role(v_uid) = 'support' and p_action <> 'dismiss') then
    raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
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
$function$;

CREATE OR REPLACE FUNCTION public.console_report_evidence(p_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := private.require_console('{owner,moderator}');
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
$function$;

CREATE OR REPLACE FUNCTION public.console_sanction_user(p_user_id uuid, p_action text, p_reason text, p_note text, p_days integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := private.require_console('{owner,moderator}');
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
$function$;

CREATE OR REPLACE FUNCTION public.console_lift_suspension(p_user_id uuid, p_note text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := private.require_console('{owner,moderator}');
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
$function$;

CREATE OR REPLACE FUNCTION public.console_appeals()
 RETURNS TABLE(sanction_id uuid, user_id uuid, handle text, display_name text, until timestamp with time zone, user_reason text, note text, created_at timestamp with time zone, appeal_text text, appeal_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  perform private.require_console('{owner,moderator}');
  return query
  select s.id, s.user_id, p.handle, p.display_name, s.until, s.user_reason, s.note, s.created_at,
         s.appeal_text, s.appeal_at
    from private.sanctions s
    left join public.profiles p on p.id = s.user_id
   where s.appeal_at is not null and s.appeal_decision is null
   order by s.appeal_at;
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_answer_appeal(p_sanction_id uuid, p_lift boolean, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := private.require_console('{owner,moderator}');
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
$function$;

CREATE OR REPLACE FUNCTION public.console_remove_avatar(p_user_id uuid, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := private.require_console('{owner,moderator}');
  v_note text := btrim(coalesce(p_note, ''));
begin
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  if private.is_console_admin(p_user_id) then
    raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
  end if;
  update public.profiles set avatar_path = null, updated_at = now()
   where id = p_user_id and deleted_at is null and avatar_path is not null;
  if not found then
    raise exception 'AVATAR_NOT_FOUND' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'avatar_remove', jsonb_build_object(
    'user_id', p_user_id, 'handle', (select p.handle from public.profiles p where p.id = p_user_id)));
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_reset_handle(p_user_id uuid, p_note text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := private.require_console('{owner,moderator}');
  v_note text := btrim(coalesce(p_note, ''));
  v_old  text;
  v_new  text;
  v_hex  text := replace(p_user_id::text, '-', '');
  v_len  integer := 8;
begin
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  select p.handle into v_old from public.profiles p where p.id = p_user_id and p.deleted_at is null;
  if not found then
    raise exception 'ACCOUNT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if private.is_console_admin(p_user_id) then
    raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
  end if;
  -- Identifiant neutre provisoire : l'ancien disparaît aussitôt de la recherche.
  loop
    v_new := 'compte_' || left(v_hex, v_len);
    exit when not exists (select 1 from public.profiles p where p.handle = v_new);
    v_len := v_len + 2;
  end loop;
  update public.profiles set handle = v_new, handle_reset_at = now(), updated_at = now()
   where id = p_user_id;
  perform private.signal_user(p_user_id, null, 'moderation');
  perform private.admin_log(v_uid, 'handle_reset', jsonb_build_object(
    'user_id', p_user_id, 'handle', v_new, 'old_handle', v_old));
  return v_new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_reply_support(p_report_id uuid, p_reply text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid   uuid := private.require_console('{owner,support}');
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
$function$;

CREATE OR REPLACE FUNCTION public.console_disconnect_device(p_user_id uuid, p_note text, p_device_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := private.require_console('{owner,support}');
  v_note text := btrim(coalesce(p_note, ''));
  v_n    integer;
begin
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  if private.is_console_admin(p_user_id) then
    raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
  end if;
  if p_device_id is not null and not exists (
       select 1 from public.devices d
        where d.id = p_device_id and d.user_id = p_user_id and d.revoked_at is null) then
    raise exception 'DEVICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  -- Prévenir l'application ouverte avant de couper (message dédié à l'écran de connexion).
  perform private.signal_user(p_user_id, null, 'disconnected');
  update public.devices set revoked_at = now(), revoked_reason = 'admin'
   where user_id = p_user_id and revoked_at is null
     and (p_device_id is null or id = p_device_id);
  get diagnostics v_n = row_count;
  delete from auth.sessions where user_id = p_user_id;
  perform private.admin_log(v_uid, 'disconnect', jsonb_build_object(
    'user_id', p_user_id, 'devices', v_n,
    'handle', (select p.handle from public.profiles p where p.id = p_user_id)));
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION public.console_reset_two_step(p_user_id uuid, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := private.require_console('{owner,support}');
  v_note text := btrim(coalesce(p_note, ''));
begin
  if char_length(v_note) < 3 or char_length(v_note) > 500 then
    raise exception 'MODERATION_NOTE_REQUIRED' using errcode = 'P0001';
  end if;
  if private.is_console_admin(p_user_id) and p_user_id <> v_uid then
    raise exception 'ADMIN_PROTECTED' using errcode = 'P0001';
  end if;
  delete from private.two_step where user_id = p_user_id;
  if not found then
    raise exception 'TWO_STEP_NOT_ENABLED' using errcode = 'P0001';
  end if;
  delete from private.two_step_sessions where user_id = p_user_id;
  perform private.admin_log(v_uid, 'two_step_reset', jsonb_build_object(
    'handle', (select p.handle from public.profiles p where p.id = p_user_id), 'note', v_note));
end;
$function$;

-- Journal : qui a agi, nouveaux types.
CREATE OR REPLACE FUNCTION public.console_journal_page(p_type text DEFAULT NULL::text, p_days integer DEFAULT NULL::integer, p_page integer DEFAULT 1, p_size integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_size  integer := least(greatest(coalesce(p_size, 30), 5), 100);
  v_page  integer := greatest(coalesce(p_page, 1), 1);
  v_since timestamptz := case when p_days is null then null else now() - make_interval(days => p_days) end;
  v_total integer;
  v_rows  jsonb;
begin
  perform private.require_console_admin();
  if p_type is not null
     and p_type not in ('accounts', 'reports', 'groups', 'settings', 'security', 'support', 'team', 'views') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  select count(*) into v_total
    from private.admin_audit a
   where a.action <> 'reports'
     and (p_type is null or private.journal_type(a.action) = p_type)
     and (v_since is null or a.created_at >= v_since);
  select coalesce(jsonb_agg(r order by (r ->> 'id')::bigint desc), '[]'::jsonb) into v_rows
    from (
      select jsonb_build_object(
               'id', a.id, 'action', a.action, 'type', private.journal_type(a.action),
               'key', a.detail ->> 'key',
               'label', (select coalesce(d.label_fr, d.description_fr)
                           from private.policy_definitions d where d.key = a.detail ->> 'key'),
               'before', a.detail -> 'before', 'after', a.detail -> 'after',
               'detail', a.detail, 'created_at', a.created_at,
               -- Lot 5.8 : qui a agi (plusieurs personnes dans l'équipe).
               'by', (select coalesce(p.display_name, '@' || p.handle) from public.profiles p
                       where p.id = a.admin_id),
               'by_role', private.console_role(a.admin_id)) as r
        from private.admin_audit a
       where a.action <> 'reports'
         and (p_type is null or private.journal_type(a.action) = p_type)
         and (v_since is null or a.created_at >= v_since)
       order by a.id desc
       offset (v_page - 1) * v_size
       limit v_size
    ) x;
  return jsonb_build_object('total', v_total, 'page', v_page, 'size', v_size, 'rows', v_rows);
end;
$function$;

-- Aperçus : sites sans aperçu.
CREATE OR REPLACE FUNCTION public.link_preview_target(p_message_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := private.require_active_user();
  v     public.messages%rowtype := private.require_visible_message(p_message_id, v_uid);
  v_url text;
begin
  if v.sender_id is distinct from v_uid then
    raise exception 'NOT_SENDER' using errcode = 'P0001';
  end if;
  if not private.policy_bool('link_preview_enabled') then
    return null;
  end if;
  if v.kind <> 'text' or exists (select 1 from private.link_previews lp where lp.message_id = v.id) then
    return null;
  end if;
  perform private.consume_rate_limit(v_uid, 'link_preview', 60, interval '1 hour');
  v_url := substring(v.body from '(https?://[^[:space:]<>"]+)');
  v_url := regexp_replace(v_url, '[.,;:!?)\]»’'']+$', '');
  if v_url is null or char_length(v_url) > 2000 then
    return null;
  end if;
  -- Lot 5.8 : site sans aperçu (liste de la console) ; le lien, lui, reste dans le message.
  if private.preview_blocked(v_url) then
    return null;
  end if;
  return v_url;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.console_access() to authenticated;
grant execute on function public.console_me() to authenticated;
grant execute on function public.console_team() to authenticated;
grant execute on function public.console_team_add(text, text) to authenticated;
grant execute on function public.console_team_set_role(uuid, text) to authenticated;
grant execute on function public.console_team_remove(uuid) to authenticated;
grant execute on function public.console_groups_page(text, text, integer, integer) to authenticated;
grant execute on function public.console_group(uuid) to authenticated;
grant execute on function public.console_group_action(uuid, text, text) to authenticated;
grant execute on function public.console_templates() to authenticated;
grant execute on function public.console_template_save(uuid, text, text, text) to authenticated;
grant execute on function public.console_template_delete(uuid) to authenticated;
grant execute on function public.console_blocked_sites() to authenticated;
grant execute on function public.console_block_site(text, boolean) to authenticated;
grant execute on function public.console_moderation_stats(integer) to authenticated;
grant execute on function public.console_journal_page(text, integer, integer, integer) to authenticated;
grant execute on function public.link_preview_target(uuid) to authenticated;
revoke all on function public.push_admin_targets(text, text) from authenticated;
grant execute on function public.push_admin_targets(text, text) to service_role;
