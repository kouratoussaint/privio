-- PRIVIO — lot 5.5 : console complète (ADR-042).
--
-- Décisions du 16/11/2026 : G menu latéral et accueil en tuiles ; H rubrique
-- « Fonctionnalités » (interrupteurs appliqués tout de suite à tous, vérifiés par le
-- serveur, l'application masque les boutons) et message d'information ; I comptes A–Z en
-- pages numérotées ; J journal filtrable par type d'action et par période.
-- Copie, transfert, partage, export et galerie restent des engagements de Privio (fixés,
-- affichés avec un cadenas) ; les documents ne sont pas développés.

-- ---------------------------------------------------------------------------
-- Fonctionnalités activables
-- ---------------------------------------------------------------------------
insert into private.policy_definitions
  (key, value_type, default_value, client_visible, implemented, description_fr,
   category, label_fr, unit, admin_locked, advanced, sort_order, effect_fr)
values
  ('signups_enabled', 'boolean', 'true', true, true, 'Création de nouveaux comptes.',
   'features', 'Inscriptions ouvertes', 'bool', false, false, 10,
   'Fermées : les nouveaux numéros ne peuvent plus créer de compte ; les comptes existants ne changent pas.'),
  ('calls_audio_enabled', 'boolean', 'true', true, true, 'Appels audio.',
   'features', 'Appels audio', 'bool', false, false, 20,
   'Désactivés : plus de nouvel appel ; un appel en cours continue jusqu’à la fin.'),
  ('calls_video_enabled', 'boolean', 'true', true, true, 'Appels vidéo.',
   'features', 'Appels vidéo', 'bool', false, false, 30,
   'Désactivés : plus de nouvel appel vidéo ; les appels audio ne changent pas.'),
  ('voice_enabled', 'boolean', 'true', true, true, 'Messages vocaux.',
   'features', 'Messages vocaux', 'bool', false, false, 40,
   'Désactivés : plus d’envoi de vocaux ; ceux déjà envoyés restent lisibles.'),
  ('photo_enabled', 'boolean', 'true', true, true, 'Envoi de photos.',
   'features', 'Photos', 'bool', false, false, 50,
   'Désactivées : plus d’envoi de photos ; celles déjà envoyées restent visibles.'),
  ('gif_enabled', 'boolean', 'true', true, true, 'GIF.',
   'features', 'GIF', 'bool', false, false, 60,
   'Désactivés : plus de recherche ni d’envoi de GIF.'),
  ('link_preview_enabled', 'boolean', 'true', true, true, 'Aperçus des liens.',
   'features', 'Aperçus des liens', 'bool', false, false, 70,
   'Désactivés : les nouveaux liens s’affichent sans aperçu.'),
  ('group_create_enabled', 'boolean', 'true', true, true, 'Création de groupes.',
   'features', 'Création de groupes', 'bool', false, false, 80,
   'Désactivée : plus de nouveau groupe ; les groupes existants ne changent pas.'),
  ('group_invite_links_enabled', 'boolean', 'true', true, true, 'Liens et codes d’invitation de groupe.',
   'features', 'Liens d’invitation de groupe', 'bool', false, false, 90,
   'Désactivés : plus de nouveau lien ni d’entrée par code ou QR code ; les invitations directes restent possibles.'),
  ('announcement_text', 'string', '""', true, true, 'Message d’information affiché à tous.',
   'features', 'Message d’information', 'text', false, false, 100,
   'Affiché en haut des listes Discussions et Groupes, pour tous. Vide : aucun message.');

-- Message d'information : 200 caractères au plus.
create or replace function private.check_announcement()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.key = 'announcement_text' and char_length(new.value #>> '{}') > 200 then
    raise exception 'POLICY_OUT_OF_BOUNDS' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger policies_announcement_length
  before insert or update on private.policies
  for each row execute function private.check_announcement();

create or replace function private.require_feature(p_key text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.policy_bool(p_key) then
    raise exception 'FEATURE_DISABLED' using errcode = 'P0001', detail = p_key;
  end if;
end;
$$;

-- Vérifications par le serveur (déclencheurs : quelle que soit la fonction appelée).
create or replace function private.feature_guard_profiles()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.policy_bool('signups_enabled') then
    raise exception 'SIGNUPS_CLOSED' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger profiles_signups_guard
  before insert on public.profiles
  for each row execute function private.feature_guard_profiles();

create or replace function private.feature_guard_calls()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform private.require_feature(
    case when new.kind = 'video' then 'calls_video_enabled' else 'calls_audio_enabled' end);
  -- Un appel vidéo suppose aussi les appels.
  if new.kind = 'video' then
    perform private.require_feature('calls_audio_enabled');
  end if;
  return new;
end;
$$;
create trigger calls_feature_guard
  before insert on private.calls
  for each row execute function private.feature_guard_calls();

create or replace function private.feature_guard_messages()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  case new.kind
    when 'voice' then perform private.require_feature('voice_enabled');
    when 'photo' then perform private.require_feature('photo_enabled');
    when 'gif' then perform private.require_feature('gif_enabled');
    else null;
  end case;
  return new;
end;
$$;
create trigger messages_feature_guard
  before insert on public.messages
  for each row execute function private.feature_guard_messages();

create or replace function private.feature_guard_groups()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.kind = 'group' then
    perform private.require_feature('group_create_enabled');
  end if;
  return new;
end;
$$;
create trigger conversations_group_guard
  before insert on public.conversations
  for each row execute function private.feature_guard_groups();

create or replace function private.feature_guard_invite_codes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform private.require_feature('group_invite_links_enabled');
  return new;
end;
$$;
create trigger group_invite_codes_guard
  before insert or update of code on private.group_invite_codes
  for each row execute function private.feature_guard_invite_codes();

-- Entrée par code ou QR code : refusée quand les liens d'invitation sont désactivés.
create or replace function private.group_of_code(p_code text, p_uid uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform private.require_feature('group_invite_links_enabled');
  select k.conversation_id into v_id
    from private.group_invite_codes k
    join public.conversations c on c.id = k.conversation_id
   where k.code = private.normalize_invite_code(p_code)
     and c.kind = 'group' and c.posting <> 'closed';
  if v_id is null or exists (
    select 1 from public.conversation_members m
     where m.conversation_id = v_id and m.left_at is null and m.role in ('owner', 'admin')
       and private.is_blocked_between(m.user_id, p_uid)) then
    return null;
  end if;
  return v_id;
end;
$$;

-- GIF : recherche refusée quand ils sont désactivés.
create or replace function public.gif_customer_id()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  perform private.require_feature('gif_enabled');
  perform private.consume_rate_limit(v_uid, 'gif_search', 300, interval '1 hour');
  return md5('privio-gif:' || v_uid::text);
end;
$$;

-- Aperçus des liens : aucun lien à prévisualiser quand ils sont désactivés.
create or replace function public.link_preview_target(p_message_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
  return v_url;
end;
$$;

-- ---------------------------------------------------------------------------
-- Comptes : liste complète, ordre alphabétique, pages numérotées, index A–Z
-- ---------------------------------------------------------------------------
create or replace function private.name_sort_key(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select upper(translate(btrim(coalesce(p_name, '')),
    'ÀÂÄÁÃÅÉÈÊËÍÎÏÌÓÔÖÒÕÚÛÜÙÇÑàâäáãåéèêëíîïìóôöòõúûüùçñ',
    'AAAAAAEEEEIIIIOOOOOUUUUCNaaaaaaeeeeiiiiooooouuuucn'));
$$;

create or replace function public.console_accounts_page(p_page integer default 1, p_size integer default 25)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := private.require_console_admin();
  v_size  integer := least(greatest(coalesce(p_size, 25), 5), 100);
  v_page  integer := greatest(coalesce(p_page, 1), 1);
  v_total integer;
  v_rows  jsonb;
  v_letters jsonb;
begin
  perform private.admin_log(v_uid, 'account_list', jsonb_build_object('page', v_page));
  select count(*) into v_total from public.profiles;
  with ordered as (
    select p.id, p.handle, p.display_name, p.created_at, p.deleted_at is not null as deleted,
           private.is_suspended(p.id) as suspended,
           row_number() over (order by private.name_sort_key(p.display_name), p.handle) - 1 as pos,
           left(private.name_sort_key(p.display_name), 1) as initial
      from public.profiles p
  )
  select
    (select coalesce(jsonb_agg(jsonb_build_object(
              'user_id', o.id, 'handle', o.handle, 'display_name', o.display_name,
              'created_at', o.created_at, 'deleted', o.deleted, 'suspended', o.suspended)
            order by o.pos), '[]'::jsonb)
       from ordered o
      where o.pos >= (v_page - 1) * v_size and o.pos < v_page * v_size),
    (select coalesce(jsonb_object_agg(l.letter, l.first_pos), '{}'::jsonb)
       from (select case when o.initial ~ '^[A-Z]$' then o.initial else '#' end as letter,
                    min(o.pos) as first_pos
               from ordered o group by 1) l)
    into v_rows, v_letters;
  return jsonb_build_object('total', v_total, 'page', v_page, 'size', v_size,
                            'rows', v_rows, 'letters', v_letters);
end;
$$;

-- ---------------------------------------------------------------------------
-- Journal : par type d'action et par période, pages numérotées
-- ---------------------------------------------------------------------------
create or replace function private.journal_type(p_action text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_action in ('account', 'account_search', 'account_list', 'lift') then 'accounts'
    when p_action in ('moderation', 'evidence', 'appeal') then 'reports'
    when p_action = 'policy' then 'settings'
    when p_action in ('two_step_reset', 'disconnect') then 'security'
    when p_action = 'reply' then 'support'
    else 'views'
  end;
$$;

create or replace function public.console_journal_page(
  p_type text default null,
  p_days integer default null,
  p_page integer default 1,
  p_size integer default 30
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_size  integer := least(greatest(coalesce(p_size, 30), 5), 100);
  v_page  integer := greatest(coalesce(p_page, 1), 1);
  v_since timestamptz := case when p_days is null then null else now() - make_interval(days => p_days) end;
  v_total integer;
  v_rows  jsonb;
begin
  perform private.require_console_admin();
  if p_type is not null
     and p_type not in ('accounts', 'reports', 'settings', 'security', 'support', 'views') then
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
               'detail', a.detail, 'created_at', a.created_at) as r
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
$$;

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.console_accounts_page(integer, integer) to authenticated;
grant execute on function public.console_journal_page(text, integer, integer, integer) to authenticated;
grant execute on function public.gif_customer_id() to authenticated;
grant execute on function public.link_preview_target(uuid) to authenticated;
