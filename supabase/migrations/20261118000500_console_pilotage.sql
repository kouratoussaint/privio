-- PRIVIO — lot 5.9 : console, pilotage (ADR-054, décisions du 18/11/2026).
--
-- A. Inscriptions : « Ouvertes », « Sur liste » (numéros autorisés ou code d'invitation)
--    ou « Fermées ». Les comptes existants ne sont pas touchés.
-- B. Exceptions par compte (photos par jour, création de groupes, appels vidéo) et par
--    groupe (taille jusqu'à 500, photos, aperçus des liens), avec date de fin facultative ;
--    portées « user » et « group » de private.policies (prévues dès la migration 2).
-- C. Préréglages « Mode pilote » / « Mode normal » : changements montrés avant d'appliquer.
-- D. Message d'information programmé (début, fin), en plus du message immédiat ; pendant
--    sa période, il est affiché à la place du message immédiat.
-- E. Statistiques : rétention par semaine d'inscription, langue choisie, usage des
--    fonctions par jour (nombres seulement).
-- F. Export CSV des statistiques (fait par l'application) : journalisé.
-- G. Console ouverte sur un téléphone jamais vu pour la console : alerte au propriétaire.
-- Tout est réservé au propriétaire de la console.

-- ---------------------------------------------------------------------------
-- A. Inscriptions
-- ---------------------------------------------------------------------------
insert into private.policy_definitions
  (key, value_type, default_value, allowed_values, client_visible, implemented, description_fr,
   category, label_fr, sort_order)
values ('signups_mode', 'string', '"open"', '["open", "list"]', false, true,
        'Inscriptions ouvertes à tous, ou seulement aux numéros autorisés et codes d’invitation.',
        'signups', 'Inscriptions', 10)
on conflict (key) do nothing;

create table private.signup_allowed_phones (
  phone_e164 text        primary key check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  added_by   uuid        references auth.users (id) on delete set null,
  added_at   timestamptz not null default now()
);
create table private.signup_codes (
  code       text        primary key check (code ~ '^[A-Z2-9]{8}$'),
  label      text        check (char_length(label) <= 60),
  max_uses   integer     not null check (max_uses between 1 and 1000),
  uses       integer     not null default 0,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_by uuid        references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
-- Code accepté pour un compte pas encore créé.
create table private.signup_passes (
  user_id uuid        primary key references auth.users (id) on delete cascade,
  code    text        not null,
  at      timestamptz not null default now()
);
revoke all on private.signup_allowed_phones, private.signup_codes, private.signup_passes
  from public, anon, authenticated;

-- Mode effectif : 'open', 'list' ou 'closed'.
create or replace function private.signups_mode()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when not private.policy_bool('signups_enabled') then 'closed'
              else coalesce(private.policy_value('signups_mode') #>> '{}', 'open') end;
$$;

create or replace function private.signup_allowed(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.signup_passes s where s.user_id = p_uid)
      or exists (select 1 from auth.users u
                   join private.signup_allowed_phones a on a.phone_e164 = '+' || ltrim(u.phone, '+')
                  where u.id = p_uid);
$$;

create or replace function private.feature_guard_profiles()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  case private.signups_mode()
    when 'closed' then raise exception 'SIGNUPS_CLOSED' using errcode = 'P0001';
    when 'list' then
      if not private.signup_allowed(new.id) then
        raise exception 'SIGNUPS_LIST_ONLY' using errcode = 'P0001';
      end if;
    else null;
  end case;
  return new;
end;
$$;

-- Avant la création du profil : l'inscription est-elle possible pour ce numéro ?
create or replace function public.signup_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_mode text := private.signups_mode();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  return jsonb_build_object('mode', v_mode,
    'allowed', v_mode = 'open' or (v_mode = 'list' and private.signup_allowed(v_uid)));
end;
$$;

-- Code d'invitation (8 caractères, sans 0/O ni 1/I). 10 essais par heure.
create or replace function public.redeem_signup_code(p_code text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.profiles p where p.id = v_uid) then
    return true;
  end if;
  perform private.consume_rate_limit(v_uid, 'signup_code', 10, interval '1 hour');
  update private.signup_codes set uses = uses + 1
   where code = v_code and revoked_at is null and expires_at > now() and uses < max_uses
     and not exists (select 1 from private.signup_passes s where s.user_id = v_uid);
  if not found then
    if exists (select 1 from private.signup_passes s where s.user_id = v_uid) then
      return true;
    end if;
    raise exception 'SIGNUP_CODE_INVALID' using errcode = 'P0001';
  end if;
  insert into private.signup_passes (user_id, code) values (v_uid, v_code);
  return true;
end;
$$;

create or replace function public.console_signups()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console('{owner}');
begin
  perform private.admin_log(v_uid, 'signups', null);
  return jsonb_build_object(
    'mode', private.signups_mode(),
    'phones', coalesce((select jsonb_agg(a.phone_e164 order by a.added_at desc)
                          from private.signup_allowed_phones a), '[]'::jsonb),
    'codes', coalesce((select jsonb_agg(jsonb_build_object(
                         'code', c.code, 'label', c.label, 'max_uses', c.max_uses, 'uses', c.uses,
                         'expires_at', c.expires_at, 'created_at', c.created_at,
                         'active', c.revoked_at is null and c.expires_at > now() and c.uses < c.max_uses)
                         order by c.created_at desc)
                         from private.signup_codes c
                        where c.revoked_at is null and c.created_at > now() - interval '90 days'),
                      '[]'::jsonb),
    'passes_7d', (select count(*) from private.signup_passes s where s.at > now() - interval '7 days'));
end;
$$;

create or replace function public.console_set_signups(p_mode text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_console('{owner}');
  if p_mode not in ('open', 'list', 'closed') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  perform public.console_set_policy('signups_enabled', to_jsonb(p_mode <> 'closed'));
  if p_mode <> 'closed' then
    perform public.console_set_policy('signups_mode', to_jsonb(p_mode));
  end if;
  return private.signups_mode();
end;
$$;

-- Ajoute ou retire des numéros (un par ligne, ou séparés par des virgules ; 8 chiffres :
-- Burkina Faso). Renvoie le nombre de numéros pris en compte et les lignes refusées.
create or replace function public.console_signup_phones(p_text text, p_add boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := private.require_console('{owner}');
  v_raw     text;
  v_phone   text;
  v_ok      integer := 0;
  v_bad     text[] := '{}';
begin
  if char_length(coalesce(p_text, '')) > 20000 then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  for v_raw in select btrim(x) from regexp_split_to_table(coalesce(p_text, ''), '[\n,;]+') x loop
    continue when v_raw = '';
    v_phone := regexp_replace(v_raw, '[^0-9+]', '', 'g');
    v_phone := case when v_phone ~ '^[0-9]{8}$' then '+226' || v_phone
                    when v_phone ~ '^00[1-9][0-9]{7,14}$' then '+' || substr(v_phone, 3)
                    else v_phone end;
    if v_phone !~ '^\+[1-9][0-9]{7,14}$' then
      v_bad := v_bad || v_raw;
      continue;
    end if;
    if p_add then
      insert into private.signup_allowed_phones (phone_e164, added_by) values (v_phone, v_uid)
      on conflict do nothing;
    else
      delete from private.signup_allowed_phones where phone_e164 = v_phone;
    end if;
    v_ok := v_ok + 1;
  end loop;
  if (select count(*) from private.signup_allowed_phones) > 5000 then
    raise exception 'RATE_LIMITED' using errcode = 'P0001';
  end if;
  perform private.admin_log(v_uid, 'signup_phones', jsonb_build_object('count', v_ok, 'added', p_add));
  return jsonb_build_object('count', v_ok, 'rejected', to_jsonb(v_bad[1:20]));
end;
$$;

create or replace function public.console_signup_code_create(p_label text, p_max_uses integer, p_days integer)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_console('{owner}');
  v_code text;
  v_abc  text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if coalesce(p_max_uses, 0) not between 1 and 1000 or coalesce(p_days, 0) not between 1 and 90
     or char_length(coalesce(p_label, '')) > 60 then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  loop
    select string_agg(substr(v_abc, 1 + (get_byte(b, i) % 32), 1), '')
      into v_code
      from (select extensions.gen_random_bytes(8) as b) r, generate_series(0, 7) i;
    exit when not exists (select 1 from private.signup_codes c where c.code = v_code);
  end loop;
  insert into private.signup_codes (code, label, max_uses, expires_at, created_by)
  values (v_code, nullif(btrim(p_label), ''), p_max_uses, now() + make_interval(days => p_days), v_uid);
  perform private.admin_log(v_uid, 'signup_code', jsonb_build_object(
    'label', nullif(btrim(p_label), ''), 'max_uses', p_max_uses, 'days', p_days));
  return v_code;
end;
$$;

create or replace function public.console_signup_code_revoke(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console('{owner}');
begin
  update private.signup_codes set revoked_at = now() where code = upper(p_code) and revoked_at is null;
  if found then
    perform private.admin_log(v_uid, 'signup_code', jsonb_build_object('revoked', true));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- B. Exceptions par compte et par groupe
-- ---------------------------------------------------------------------------
alter table private.policies add column if not exists expires_at timestamptz;
alter table private.policies add column if not exists note text check (char_length(note) <= 500);

-- Taille d'un groupe : une exception peut aller jusqu'à 500 (au-delà de la borne globale).
create or replace function private.validate_policy()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  d private.policy_definitions%rowtype;
  v_num numeric;
begin
  select * into d from private.policy_definitions where key = new.key;

  if (d.value_type = 'boolean' and jsonb_typeof(new.value) <> 'boolean')
     or (d.value_type = 'integer' and (jsonb_typeof(new.value) <> 'number'
                                       or (new.value #>> '{}')::numeric <> trunc((new.value #>> '{}')::numeric)))
     or (d.value_type = 'string' and jsonb_typeof(new.value) <> 'string') then
    raise exception 'POLICY_TYPE_INVALID' using errcode = 'P0001';
  end if;

  if d.value_type = 'integer' then
    v_num := (new.value #>> '{}')::numeric;
    if (d.min_value is not null and v_num < d.min_value)
       or (case when new.scope_type = 'group' and new.key = 'group_max_members' then v_num > 500
                else d.max_value is not null and v_num > d.max_value end) then
      raise exception 'POLICY_OUT_OF_BOUNDS' using errcode = 'P0001';
    end if;
  end if;

  if d.allowed_values is not null and not (d.allowed_values @> jsonb_build_array(new.value)) then
    raise exception 'POLICY_OUT_OF_BOUNDS' using errcode = 'P0001';
  end if;

  if not d.implemented and new.value <> d.default_value then
    raise exception 'FEATURE_NOT_IMPLEMENTED' using errcode = 'P0001';
  end if;

  if tg_op = 'UPDATE' then
    new.version := old.version + 1;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Valeur pour un compte : son exception en cours, sinon la valeur globale.
create or replace function private.user_policy(p_uid uuid, p_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.value from private.policies p
      where p.key = p_key and p.scope_type = 'user' and p.scope_id = p_uid and p.enabled
        and (p.expires_at is null or p.expires_at > now())),
    private.policy_value(p_key));
$$;

-- Valeur pour une discussion (groupe) : son exception en cours, sinon la valeur globale.
create or replace function private.group_policy(p_conversation_id uuid, p_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.value from private.policies p
      where p.key = p_key and p.scope_type = 'group' and p.scope_id = p_conversation_id and p.enabled
        and (p.expires_at is null or p.expires_at > now())),
    private.policy_value(p_key));
$$;

create or replace function private.feature_guard_calls()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  -- Appel à deux : la personne qui appelle ; appel de groupe : celle qui le lance.
  v_uid uuid := coalesce(to_jsonb(new) ->> 'caller_id', to_jsonb(new) ->> 'started_by')::uuid;
begin
  perform private.require_feature('calls_audio_enabled');
  if new.kind = 'video' and not (private.user_policy(v_uid, 'calls_video_enabled') #>> '{}')::boolean then
    raise exception 'FEATURE_DISABLED' using errcode = 'P0001', detail = 'calls_video_enabled';
  end if;
  return new;
end;
$$;

create or replace function private.feature_guard_messages()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  case new.kind
    when 'voice' then perform private.require_feature('voice_enabled');
    when 'photo' then
      if not (private.group_policy(new.conversation_id, 'photo_enabled') #>> '{}')::boolean then
        raise exception 'FEATURE_DISABLED' using errcode = 'P0001', detail = 'photo_enabled';
      end if;
    when 'gif' then perform private.require_feature('gif_enabled');
    else null;
  end case;
  return new;
end;
$$;

create or replace function private.feature_guard_groups()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.kind = 'group'
     and not (private.user_policy(coalesce(new.created_by, auth.uid()), 'group_create_enabled') #>> '{}')::boolean then
    raise exception 'FEATURE_DISABLED' using errcode = 'P0001', detail = 'group_create_enabled';
  end if;
  return new;
end;
$$;

create or replace function private.group_member_cap(p_conversation_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select (p.value #>> '{}')::integer from private.policies p
      where p.key = 'group_max_members' and p.scope_type = 'group' and p.scope_id = p_conversation_id
        and p.enabled and (p.expires_at is null or p.expires_at > now())),
    case when coalesce((select c.announcement from public.conversations c
                         where c.id = p_conversation_id), false)
         then private.policy_int('announcement_max_members')
         else private.policy_int('group_max_members') end);
$$;

-- Exceptions en cours (toutes, ou d'un compte, ou d'un groupe).
create or replace function public.console_overrides(p_user_id uuid default null,
                                                    p_conversation_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_console('{owner}');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'scope', p.scope_type, 'id', p.scope_id, 'key', p.key,
             'label', coalesce(d.label_fr, d.description_fr), 'value', p.value,
             'global', private.policy_value(p.key), 'expires_at', p.expires_at, 'note', p.note,
             'updated_at', p.updated_at,
             'target', case p.scope_type
                         when 'user' then (select '@' || pr.handle from public.profiles pr where pr.id = p.scope_id)
                         else (select c.title from public.conversations c where c.id = p.scope_id) end)
             order by p.updated_at desc)
      from private.policies p
      join private.policy_definitions d on d.key = p.key
     where p.scope_type in ('user', 'group') and p.enabled
       and (p.expires_at is null or p.expires_at > now())
       and (p_user_id is null or (p.scope_type = 'user' and p.scope_id = p_user_id))
       and (p_conversation_id is null or (p.scope_type = 'group' and p.scope_id = p_conversation_id))),
    '[]'::jsonb);
end;
$$;

-- Pose (p_value) ou retire (p_value null) une exception. p_days : durée (null : sans fin).
create or replace function public.console_set_override(p_scope text, p_id uuid, p_key text, p_value jsonb,
                                                       p_days integer, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_console('{owner}');
  v_target text;
begin
  if not ((p_scope = 'user' and p_key in ('photo_daily_limit', 'group_create_enabled', 'calls_video_enabled'))
          or (p_scope = 'group' and p_key in ('group_max_members', 'photo_enabled', 'link_preview_enabled')))
     or (p_days is not null and p_days not between 1 and 365)
     or char_length(coalesce(p_note, '')) > 500 then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  if p_scope = 'user' then
    select '@' || pr.handle into v_target from public.profiles pr where pr.id = p_id and pr.deleted_at is null;
  else
    select c.title into v_target from public.conversations c where c.id = p_id and c.kind = 'group';
  end if;
  if v_target is null then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_value is null then
    update private.policies set enabled = false, updated_by = v_uid
     where key = p_key and scope_type = p_scope and scope_id = p_id and enabled;
  else
    insert into private.policies (key, scope_type, scope_id, value, enabled, updated_by, expires_at, note)
    values (p_key, p_scope, p_id, p_value, true, v_uid,
            case when p_days is null then null else now() + make_interval(days => p_days) end,
            nullif(btrim(coalesce(p_note, '')), ''))
    on conflict (key, scope_type, scope_id) do update
      set value = excluded.value, enabled = true, updated_by = excluded.updated_by,
          expires_at = excluded.expires_at, note = excluded.note;
  end if;
  perform private.admin_log(v_uid, 'override', jsonb_build_object(
    'scope', p_scope, 'target', v_target, 'key', p_key, 'value', p_value, 'days', p_days));
  if p_scope = 'user' then
    -- Son application relit ses réglages.
    perform private.signal_user(p_id, null, 'moderation');
  end if;
end;
$$;

-- Exceptions expirées : désactivées (les réglages ne s'effacent jamais ; l'historique
-- garde leur trace).
create or replace function private.expire_overrides()
returns void
language sql
security definer
set search_path = ''
as $$
  update private.policies set enabled = false
   where scope_type in ('user', 'group') and enabled and expires_at is not null and expires_at <= now();
$$;

-- ---------------------------------------------------------------------------
-- C. Préréglages
-- ---------------------------------------------------------------------------
create or replace function private.preset_values(p_name text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case p_name
    when 'pilot' then '{"signups_enabled": true, "signups_mode": "list", "group_max_members": 25,
                        "announcement_max_members": 200, "group_invite_links_enabled": false,
                        "connection_requests_required": true, "health_alerts_enabled": true}'::jsonb
    when 'normal' then '{"signups_enabled": true, "signups_mode": "open", "group_max_members": 50,
                         "announcement_max_members": 500, "group_invite_links_enabled": true,
                         "connection_requests_required": true, "health_alerts_enabled": true}'::jsonb
  end;
$$;

-- Changements qu'apporterait le préréglage ; appliqués si p_apply.
create or replace function public.console_preset(p_name text, p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := private.require_console('{owner}');
  v_values  jsonb := private.preset_values(p_name);
  v_changes jsonb;
  e         record;
begin
  if v_values is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', x.key, 'label', coalesce(d.label_fr, d.description_fr),
           'before', private.policy_value(x.key), 'after', x.value) order by d.category, d.sort_order), '[]'::jsonb)
    into v_changes
    from jsonb_each(v_values) x
    join private.policy_definitions d on d.key = x.key
   where private.policy_value(x.key) is distinct from x.value;
  if p_apply then
    for e in select x.key, x.value from jsonb_each(v_values) x
              where private.policy_value(x.key) is distinct from x.value loop
      perform public.console_set_policy(e.key, e.value);
    end loop;
    perform private.admin_log(v_uid, 'preset', jsonb_build_object(
      'name', p_name, 'changes', jsonb_array_length(v_changes)));
  end if;
  return v_changes;
end;
$$;

-- ---------------------------------------------------------------------------
-- D. Message d'information programmé
-- ---------------------------------------------------------------------------
create table private.scheduled_announcement (
  id        smallint    primary key default 1 check (id = 1),
  text      text        not null check (char_length(text) between 1 and 200),
  starts_at timestamptz not null,
  ends_at   timestamptz not null check (ends_at > starts_at),
  set_by    uuid        references auth.users (id) on delete set null,
  set_at    timestamptz not null default now()
);
revoke all on private.scheduled_announcement from public, anon, authenticated;

create or replace function public.console_scheduled_announcement()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_console('{owner}');
  return (select jsonb_build_object('text', s.text, 'starts_at', s.starts_at, 'ends_at', s.ends_at,
                                    'live', now() between s.starts_at and s.ends_at)
            from private.scheduled_announcement s where s.ends_at > now());
end;
$$;

-- Programme (texte, début, fin) ou retire (texte vide) le message. 30 jours au plus.
create or replace function public.console_set_scheduled_announcement(p_text text, p_starts timestamptz,
                                                                     p_ends timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_console('{owner}');
  v_text text := btrim(coalesce(p_text, ''));
begin
  if v_text = '' then
    delete from private.scheduled_announcement;
    perform private.admin_log(v_uid, 'scheduled_announcement', jsonb_build_object('removed', true));
    return;
  end if;
  if char_length(v_text) > 200 or p_starts is null or p_ends is null or p_ends <= p_starts
     or p_ends <= now() or p_ends > p_starts + interval '30 days' or p_starts > now() + interval '90 days' then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  insert into private.scheduled_announcement (id, text, starts_at, ends_at, set_by)
  values (1, v_text, p_starts, p_ends, v_uid)
  on conflict (id) do update set text = excluded.text, starts_at = excluded.starts_at,
                                 ends_at = excluded.ends_at, set_by = excluded.set_by, set_at = now();
  perform private.admin_log(v_uid, 'scheduled_announcement', jsonb_build_object(
    'starts_at', p_starts, 'ends_at', p_ends));
end;
$$;

-- Réglages lus par l'application : exceptions du compte, message programmé en cours.
create or replace function public.get_client_policies()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_active_user();
  v_values jsonb;
  v_text   text := (select s.text from private.scheduled_announcement s
                     where now() between s.starts_at and s.ends_at);
begin
  select coalesce(jsonb_object_agg(d.key, private.user_policy(v_uid, d.key)), '{}'::jsonb)
    into v_values
    from private.policy_definitions d
   where d.client_visible;
  if v_text is not null then
    v_values := v_values || jsonb_build_object('announcement_text', v_text);
  end if;
  return jsonb_build_object('version', md5(v_values::text), 'values', v_values);
end;
$$;

-- ---------------------------------------------------------------------------
-- E. Statistiques
-- ---------------------------------------------------------------------------
alter table public.devices add column if not exists language text check (language in ('fr', 'mos', 'dyu'));

-- Langue choisie dans l'application (statistiques seulement).
create or replace function public.set_device_language(p_language text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_active_user();
  if p_language not in ('fr', 'mos', 'dyu') then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  update public.devices set language = p_language where id = private.current_device_id();
end;
$$;

create or replace function private.stats_on_group_call()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.bump_stat('group_calls_' || new.kind);
  return null;
end;
$$;
create trigger group_calls_stats after insert on private.group_calls
  for each row execute function private.stats_on_group_call();

create or replace function public.console_stats_extra(p_days integer default 30)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_console('{owner}');
  v_days  integer := least(greatest(coalesce(p_days, 30), 7), 90);
  v_today date := (now() at time zone 'utc')::date;
begin
  perform private.admin_log(v_uid, 'stats_extra', null);
  return jsonb_build_object(
    -- Rétention : comptes revenus au moins 1, 7, 30 jours après l'inscription (parmi ceux
    -- inscrits depuis assez longtemps), par semaine d'inscription (8 dernières semaines).
    'retention', (
      with u as (
        select pr.id, pr.created_at,
               greatest(coalesce((select max(d.last_seen_at) from public.devices d where d.user_id = pr.id), pr.created_at),
                        coalesce((select p.last_seen_at from private.presence p where p.user_id = pr.id), pr.created_at)) as seen
          from public.profiles pr
         where pr.deleted_at is null and pr.created_at > date_trunc('week', now()) - interval '7 weeks'
      )
      select coalesce(jsonb_agg(jsonb_build_object(
               'week', w.week, 'signups', w.n,
               'd1', w.e1, 'r1', w.r1, 'd7', w.e7, 'r7', w.r7, 'd30', w.e30, 'r30', w.r30) order by w.week desc), '[]'::jsonb)
        from (select (date_trunc('week', u.created_at at time zone 'utc'))::date as week, count(*) as n,
                     count(*) filter (where u.created_at <= now() - interval '1 day') as e1,
                     count(*) filter (where u.created_at <= now() - interval '1 day' and u.seen >= u.created_at + interval '1 day') as r1,
                     count(*) filter (where u.created_at <= now() - interval '7 days') as e7,
                     count(*) filter (where u.created_at <= now() - interval '7 days' and u.seen >= u.created_at + interval '7 days') as r7,
                     count(*) filter (where u.created_at <= now() - interval '30 days') as e30,
                     count(*) filter (where u.created_at <= now() - interval '30 days' and u.seen >= u.created_at + interval '30 days') as r30
                from u group by 1) w),
    -- Langue des téléphones actifs ces 30 derniers jours.
    'languages', coalesce((select jsonb_object_agg(x.lang, x.n) from (
        select coalesce(d.language, 'unknown') as lang, count(*) as n
          from public.devices d
          join public.profiles pr on pr.id = d.user_id and pr.deleted_at is null
         where d.revoked_at is null and d.last_seen_at > now() - interval '30 days'
         group by 1) x), '{}'::jsonb),
    -- Usage des fonctions par jour.
    'usage', (
      with days as (
        select generate_series(v_today - (v_days - 1), v_today, interval '1 day')::date as day)
      select jsonb_agg(jsonb_build_object('day', d.day, 'values', coalesce((
               select jsonb_object_agg(st.metric, st.value) from private.daily_stats st
                where st.day = d.day and st.metric in (
                  'messages_text', 'messages_voice', 'messages_photo', 'messages_gif',
                  'messages_sticker', 'messages_poll', 'calls_audio', 'calls_video',
                  'group_calls_audio', 'group_calls_video')), '{}'::jsonb)) order by d.day)
        from days d));
end;
$$;

-- F. Export (fait par l'application, nombres seulement) : journalisé.
create or replace function public.console_log_export(p_days integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_console('{owner}');
begin
  perform private.admin_log(v_uid, 'export', jsonb_build_object('days', p_days));
end;
$$;

-- ---------------------------------------------------------------------------
-- G. Console ouverte sur un nouveau téléphone
-- ---------------------------------------------------------------------------
alter table private.admin_alerts drop constraint admin_alerts_kind_check;
alter table private.admin_alerts add constraint admin_alerts_kind_check
  check (kind in ('purge', 'sms', 'failures', 'relay', 'test', 'console_device'));

create table private.console_devices (
  user_id    uuid        not null references auth.users (id) on delete cascade,
  device_id  uuid        not null,
  first_seen timestamptz not null default now(),
  primary key (user_id, device_id)
);
revoke all on private.console_devices from public, anon, authenticated;

create or replace function public.console_me()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_role text := private.console_role(v_uid);
  v_dev  uuid := private.current_device_id();
  v_alert uuid;
begin
  if v_role is null then
    raise exception 'ADMIN_REQUIRED' using errcode = 'P0001';
  end if;
  -- Lot 5.9 : téléphone jamais vu pour la console → alerte au propriétaire et journal.
  if v_dev is not null then
    insert into private.console_devices (user_id, device_id) values (v_uid, v_dev)
    on conflict do nothing;
    if found then
      perform private.admin_log(v_uid, 'console_device', jsonb_build_object(
        'model', (select d.model from public.devices d where d.id = v_dev)));
      insert into private.admin_alerts (kind, detail)
      values ('console_device', jsonb_build_object(
        'name', (select coalesce(p.display_name, '@' || p.handle) from public.profiles p where p.id = v_uid),
        'role', v_role, 'model', (select d.model from public.devices d where d.id = v_dev)))
      returning id into v_alert;
      perform private.notify_admin('alert_console_device', v_alert);
    end if;
  end if;
  return jsonb_build_object(
    'role', v_role,
    'two_step', exists (select 1 from private.two_step t where t.user_id = v_uid),
    'two_step_required', v_role <> 'owner');
end;
$$;

-- Journal : nouvelles actions.
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
    when p_action in ('policy', 'reserved_handle', 'template', 'site', 'signup_phones', 'signup_code',
                      'override', 'preset', 'scheduled_announcement') then 'settings'
    when p_action in ('two_step_reset', 'disconnect', 'console_device', 'export') then 'security'
    when p_action in ('team_add', 'team_role', 'team_remove') then 'team'
    when p_action = 'reply' then 'support'
    else 'views'
  end;
$$;

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'privio_expire_overrides';
    perform cron.schedule('privio_expire_overrides', '7 * * * *', 'select private.expire_overrides()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- B. Exceptions : quotas de photos (compte) et aperçus des liens (groupe)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prepare_photo_message(p_conversation_id uuid, p_client_msg_id uuid)
 RETURNS TABLE(path text, state text, message_id uuid, remaining integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_member(p_conversation_id);
  v_msg   public.messages%rowtype;
  v_row   private.media_objects%rowtype;
  v_path  text;
  v_day   date := private.quota_day();
  v_limit integer := (private.user_policy(auth.uid(), 'photo_daily_limit') #>> '{}')::integer;
  v_used  integer;
begin
  if p_client_msg_id is null then
    raise exception 'BODY_INVALID' using errcode = 'P0001';
  end if;
  select * into v_msg from public.messages m
   where m.sender_id = v_uid and m.client_msg_id = p_client_msg_id;
  if found then
    if v_msg.conversation_id <> p_conversation_id then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
    end if;
    return query select null::text, 'sent'::text, v_msg.id, null::integer;
    return;
  end if;
  perform private.check_can_post(p_conversation_id, v_uid);

  insert into private.media_objects (path, bucket, owner_id, conversation_id, client_msg_id, quota_day)
  values (p_conversation_id::text || '/' || gen_random_uuid()::text || '.jpg', 'photos',
          v_uid, p_conversation_id, p_client_msg_id, v_day)
  on conflict (owner_id, client_msg_id) do nothing
  returning private.media_objects.path into v_path;

  if v_path is not null then
    insert into private.photo_quota_daily as q (user_id, quota_day, used)
    values (v_uid, v_day, 1)
    on conflict (user_id, quota_day) do update
      set used = q.used + 1, updated_at = now()
      where q.used < v_limit
    returning q.used into v_used;
    if v_used is null or v_used > v_limit then
      raise exception 'PHOTO_QUOTA_REACHED' using errcode = 'P0001';
    end if;
  end if;

  select * into v_row from private.media_objects o
   where o.owner_id = v_uid and o.client_msg_id = p_client_msg_id;
  if v_row.conversation_id is distinct from p_conversation_id or v_row.bucket <> 'photos' then
    raise exception 'IDEMPOTENCY_CONFLICT' using errcode = 'P0001';
  end if;
  return query
    select v_row.path, v_row.state, null::uuid,
           greatest(v_limit - coalesce((select q.used from private.photo_quota_daily q
                                         where q.user_id = v_uid and q.quota_day = v_day), 0), 0);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_photo_quota()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid   uuid := private.require_active_user();
  v_day   date := private.quota_day();
  v_limit integer := (private.user_policy(v_uid, 'photo_daily_limit') #>> '{}')::integer;
  v_used  integer := coalesce((select q.used from private.photo_quota_daily q
                                where q.user_id = v_uid and q.quota_day = v_day), 0);
  v_tz    text := private.policy_value('quota_timezone') #>> '{}';
begin
  return jsonb_build_object(
    'limit', v_limit,
    'used', v_used,
    'remaining', greatest(v_limit - v_used, 0),
    'day', v_day,
    'resets_at', ((v_day + 1)::timestamp at time zone v_tz));
end;
$function$;

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
  if not (private.group_policy(v.conversation_id, 'link_preview_enabled') #>> '{}')::boolean then
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
grant execute on function public.signup_status() to authenticated;
grant execute on function public.redeem_signup_code(text) to authenticated;
grant execute on function public.console_signups() to authenticated;
grant execute on function public.console_set_signups(text) to authenticated;
grant execute on function public.console_signup_phones(text, boolean) to authenticated;
grant execute on function public.console_signup_code_create(text, integer, integer) to authenticated;
grant execute on function public.console_signup_code_revoke(text) to authenticated;
grant execute on function public.console_overrides(uuid, uuid) to authenticated;
grant execute on function public.console_set_override(text, uuid, text, jsonb, integer, text) to authenticated;
grant execute on function public.console_preset(text, boolean) to authenticated;
grant execute on function public.console_scheduled_announcement() to authenticated;
grant execute on function public.console_set_scheduled_announcement(text, timestamptz, timestamptz) to authenticated;
grant execute on function public.get_client_policies() to authenticated;
grant execute on function public.set_device_language(text) to authenticated;
grant execute on function public.console_stats_extra(integer) to authenticated;
grant execute on function public.console_log_export(integer) to authenticated;
grant execute on function public.console_me() to authenticated;
grant execute on function public.prepare_photo_message(uuid, uuid) to authenticated;
grant execute on function public.get_photo_quota() to authenticated;
grant execute on function public.link_preview_target(uuid) to authenticated;
