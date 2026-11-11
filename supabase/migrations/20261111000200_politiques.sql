-- PRIVIO — Migration 2 : politiques administrables
-- Hiérarchie : invariant système (bornes des définitions) > politique globale > groupe > utilisateur.
-- Une fonctionnalité non implémentée ne peut pas être activée par simple changement de valeur.
-- Écriture : uniquement migrations / service (console admin à l'étape 5). Lecture client : RPC filtrée.

create table private.policy_definitions (
  key            text primary key,
  value_type     text    not null check (value_type in ('boolean', 'integer', 'string')),
  default_value  jsonb   not null,
  min_value      numeric,
  max_value      numeric,
  allowed_values jsonb,
  client_visible boolean not null default false,
  implemented    boolean not null default false,
  description_fr text    not null
);

create table private.policies (
  id         uuid        primary key default gen_random_uuid(),
  key        text        not null references private.policy_definitions (key),
  scope_type text        not null default 'global' check (scope_type in ('global', 'group', 'user')),
  scope_id   uuid,
  value      jsonb       not null,
  enabled    boolean     not null default true,
  version    integer     not null default 1,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  check ((scope_type = 'global') = (scope_id is null))
);
create unique index policies_scope_uniq
  on private.policies (key, scope_type, scope_id) nulls not distinct;

create table private.policy_history (
  id          bigint      generated always as identity primary key,
  policy_key  text        not null,
  scope_type  text        not null,
  scope_id    uuid,
  before_json jsonb,
  after_json  jsonb       not null,
  actor_id    uuid,
  created_at  timestamptz not null default now()
);

-- Validation : type, bornes, valeurs autorisées, fonctionnalité implémentée.
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
       or (d.max_value is not null and v_num > d.max_value) then
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

create trigger policies_validate
  before insert or update on private.policies
  for each row execute function private.validate_policy();

create or replace function private.record_policy_history()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into private.policy_history (policy_key, scope_type, scope_id, before_json, after_json, actor_id)
  values (
    new.key, new.scope_type, new.scope_id,
    case when tg_op = 'UPDATE' then jsonb_build_object('value', old.value, 'enabled', old.enabled, 'version', old.version) end,
    jsonb_build_object('value', new.value, 'enabled', new.enabled, 'version', new.version),
    new.updated_by
  );
  return new;
end;
$$;

create trigger policies_history
  after insert or update on private.policies
  for each row execute function private.record_policy_history();

-- Historique en ajout seul.
create or replace function private.forbid_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'APPEND_ONLY' using errcode = 'P0001';
end;
$$;

create trigger policy_history_append_only
  before update or delete on private.policy_history
  for each row execute function private.forbid_mutation();

-- Une politique ne se supprime pas : on la désactive (traçabilité).
create trigger policies_no_delete
  before delete on private.policies
  for each row execute function private.forbid_mutation();

-- Valeur effective globale d'une politique (globale active, sinon défaut).
create or replace function private.policy_value(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.value from private.policies p
      where p.key = p_key and p.scope_type = 'global' and p.enabled),
    (select d.default_value from private.policy_definitions d where d.key = p_key)
  );
$$;
revoke all on function private.policy_value(text) from public;

-- Lecture côté application : uniquement les clés visibles par le client.
create or replace function public.get_client_policies()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_values jsonb;
begin
  perform private.require_active_user();
  select coalesce(jsonb_object_agg(d.key, private.policy_value(d.key)), '{}'::jsonb)
    into v_values
    from private.policy_definitions d
   where d.client_visible;
  return jsonb_build_object('version', md5(v_values::text), 'values', v_values);
end;
$$;
revoke all on function public.get_client_policies() from public, anon;
grant execute on function public.get_client_policies() to authenticated;

-- ---------------------------------------------------------------------------
-- Définitions initiales (dossier 02). `implemented` passe à true au fil des étapes,
-- par migration, quand la fonctionnalité correspondante est livrée et testée.
-- ---------------------------------------------------------------------------
insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('message_ttl_hours',          'integer', '72',    1,   72,  null, true,  false, 'Durée de vie des messages. Invariant : jamais plus de 72 h.'),
  ('voice_max_seconds',          'integer', '30',    5,   30,  null, true,  false, 'Durée maximale d''un message vocal.'),
  ('photo_daily_limit',          'integer', '5',     0,   10,  null, true,  false, 'Photos par compte et par jour, groupes inclus.'),
  ('quota_timezone',             'string',  '"Africa/Ouagadougou"', null, null, '["Africa/Ouagadougou"]', false, true, 'Fuseau de calcul des quotas journaliers.'),
  ('group_max_members',          'integer', '100',   2,   100, null, true,  false, 'Nombre maximal de membres par groupe (hypothèse B2).'),
  ('internal_forward_enabled',   'boolean', 'false', null, null, null, true, false, 'Transfert interne de messages.'),
  ('external_share_enabled',     'boolean', 'false', null, null, null, true, false, 'Partage vers d''autres applications.'),
  ('message_copy_enabled',       'boolean', 'false', null, null, null, true, false, 'Copie du texte des messages.'),
  ('conversation_export_enabled','boolean', 'false', null, null, null, true, false, 'Export de conversation.'),
  ('save_media_to_gallery_enabled','boolean','false', null, null, null, true, false, 'Enregistrement des médias dans la galerie.'),
  ('screen_capture_allowed',     'boolean', 'false', null, null, null, true, false, 'Captures d''écran (FLAG_SECURE actif si false).'),
  ('video_upload_enabled',       'boolean', 'false', null, null, null, true, false, 'Envoi de vidéos (non développé au MVP).'),
  ('document_upload_enabled',    'boolean', 'false', null, null, null, true, false, 'Envoi de documents (non développé au MVP).'),
  ('video_call_max_minutes',     'integer', '7',     1,   7,   null, true,  false, 'Durée maximale d''un appel vidéo (V2).'),
  ('search_handle_hourly_limit', 'integer', '60',    5,   300, null, false, true,  'Recherches par identifiant Privio, par compte et par heure.'),
  ('search_phone_hourly_limit',  'integer', '20',    1,   100, null, false, true,  'Recherches par numéro, par compte et par heure.'),
  ('handle_check_hourly_limit',  'integer', '120',   10,  600, null, false, true,  'Vérifications de disponibilité d''identifiant, par heure.'),
  ('profile_write_hourly_limit', 'integer', '20',    1,   100, null, false, true,  'Écritures de profil, par compte et par heure.');

-- Aucun accès client direct aux tables de politiques.
revoke all on all tables in schema private from public, anon, authenticated;

select private.harden_privileges();
