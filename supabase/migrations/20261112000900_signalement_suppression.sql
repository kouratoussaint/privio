-- PRIVIO — Migration 9 (lot 2.5) : signalement, assistance, suppression de compte.
-- Décision B3 (proposition appliquée par défaut, administrable) : copie d'un message signalé
-- conservée 90 jours, puis effacée automatiquement par la purge.

insert into private.policy_definitions
  (key, value_type, default_value, min_value, max_value, allowed_values, client_visible, implemented, description_fr)
values
  ('report_retention_days', 'integer', '90', 7, 365, null, false, true,
   'Durée de conservation des signalements et de la copie des messages signalés (jours).'),
  ('report_daily_limit', 'integer', '20', 1, 200, null, false, true,
   'Signalements et demandes d''assistance par compte et par jour.');

-- Schéma privé : jamais exposé à l'application ; lu par la console d'administration (lot 5).
create table private.reports (
  id               uuid        primary key default gen_random_uuid(),
  reporter_id      uuid        references auth.users (id) on delete set null,
  reported_user_id uuid        references auth.users (id) on delete set null,
  conversation_id  uuid,
  message_id       uuid,
  reason           text        not null check (reason in
                     ('spam', 'harassment', 'inappropriate', 'threat', 'impersonation', 'other', 'support')),
  details          text        check (details is null or char_length(details) <= 1000),
  -- Copie du message, uniquement si la personne qui signale l'a explicitement acceptée.
  evidence         jsonb,
  status           text        not null default 'open' check (status in ('open', 'reviewing', 'closed')),
  created_at       timestamptz not null default now(),
  purge_after      timestamptz not null,
  unique (reporter_id, message_id),
  check ((reason = 'support') = (reported_user_id is null and message_id is null))
);
create index reports_purge_idx on private.reports (purge_after);
revoke all on private.reports from public, anon, authenticated;

create or replace function public.report(
  p_reason           text,
  p_reported_user_id uuid default null,
  p_conversation_id  uuid default null,
  p_message_id       uuid default null,
  p_details          text default null,
  p_include_message  boolean default false
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := private.require_active_user();
  v_msg      public.messages%rowtype;
  v_evidence jsonb;
  v_id       uuid;
  v_details  text := nullif(btrim(coalesce(p_details, '')), '');
begin
  perform private.consume_rate_limit(v_uid, 'report',
    private.policy_int('report_daily_limit'), interval '1 day');

  if p_reason is null or p_reason not in
     ('spam', 'harassment', 'inappropriate', 'threat', 'impersonation', 'other', 'support') then
    raise exception 'REPORT_INVALID' using errcode = 'P0001';
  end if;
  if v_details is not null and char_length(v_details) > 1000 then
    raise exception 'REPORT_INVALID' using errcode = 'P0001';
  end if;

  if p_reason = 'support' then
    -- Demande d'assistance : aucune cible, un texte obligatoire.
    if p_reported_user_id is not null or p_message_id is not null or v_details is null then
      raise exception 'REPORT_INVALID' using errcode = 'P0001';
    end if;
  else
    if p_reported_user_id is null or p_reported_user_id = v_uid then
      raise exception 'REPORT_INVALID' using errcode = 'P0001';
    end if;
    if p_conversation_id is not null and not private.is_member(p_conversation_id, v_uid) then
      raise exception 'NOT_MEMBER' using errcode = 'P0001';
    end if;
    if p_message_id is not null then
      v_msg := private.visible_message(p_message_id, v_uid);
      if v_msg.kind <> 'text' or v_msg.sender_id is distinct from p_reported_user_id
         or v_msg.conversation_id is distinct from p_conversation_id then
        raise exception 'REPORT_INVALID' using errcode = 'P0001';
      end if;
      -- Déjà signalé par cette personne : on renvoie le signalement existant.
      select r.id into v_id from private.reports r
       where r.reporter_id = v_uid and r.message_id = p_message_id;
      if v_id is not null then
        return v_id;
      end if;
      if coalesce(p_include_message, false) and v_msg.deleted_at is null then
        v_evidence := jsonb_build_object(
          'body', v_msg.body, 'sent_at', v_msg.sent_at, 'sender_id', v_msg.sender_id,
          'conversation_id', v_msg.conversation_id, 'copied_at', now());
      end if;
    end if;
  end if;

  insert into private.reports
    (reporter_id, reported_user_id, conversation_id, message_id, reason, details, evidence, purge_after)
  values
    (v_uid, p_reported_user_id, p_conversation_id, p_message_id, p_reason, v_details, v_evidence,
     now() + make_interval(days => private.policy_int('report_retention_days')))
  returning id into v_id;
  return v_id;
end;
$$;

-- Suppression définitive du compte : messages envoyés effacés chez tous les correspondants,
-- puis compte Auth supprimé (profil, numéro, appareils, blocages, appartenances en cascade).
create or replace function public.delete_my_account(p_confirmation text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  r     record;
begin
  if p_confirmation is distinct from 'SUPPRIMER' then
    raise exception 'CONFIRMATION_REQUIRED' using errcode = 'P0001';
  end if;
  -- Prévenir les correspondants (leur liste se met à jour), avant l'effacement.
  for r in
    select distinct m.conversation_id from public.conversation_members m where m.user_id = v_uid
  loop
    perform private.signal_members(r.conversation_id, 'message_changed');
  end loop;
  delete from public.messages where sender_id = v_uid;
  delete from auth.users where id = v_uid;
end;
$$;

-- Purge : + signalements échus.
create or replace function private.purge_expired()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  -- Les réponses perdent leur lien (on delete set null) avant la suppression.
  delete from public.messages where expires_at <= now();
  get diagnostics v_count = row_count;
  delete from private.rate_limit_hits where window_start < now() - interval '1 day';
  delete from private.reports where purge_after <= now();
  return v_count;
end;
$$;

-- Correctif : un correspondant dont le compte n'existe plus est bien signalé « supprimé »
-- (le contrôle précédent ne regardait que deleted_at, pas l'absence du profil).
create or replace function public.list_conversations()
returns table (
  conversation_id      uuid,
  kind                 text,
  peer_id              uuid,
  peer_handle          text,
  peer_display_name    text,
  peer_avatar_path     text,
  peer_deleted         boolean,
  blocked              boolean,
  last_message_id      uuid,
  last_sender_id       uuid,
  last_body            text,
  last_deleted         boolean,
  last_sent_at         timestamptz,
  last_expires_at      timestamptz,
  last_kind            text,
  ttl_seconds          integer,
  unread_count         integer,
  pinned               boolean,
  archived             boolean,
  peer_delivered_up_to timestamptz,
  peer_read_up_to      timestamptz,
  sort_at              timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_active_user();
  v_max integer := private.policy_int('message_ttl_hours') * 3600;
begin
  return query
  with mine as (
    select c.id, c.kind, c.created_by, c.created_at, c.ttl_seconds, me.read_up_to, me.pinned_at, me.archived_at
      from public.conversation_members me
      join public.conversations c on c.id = me.conversation_id
     where me.user_id = v_uid and me.left_at is null
  ),
  visible as (
    select m.* from public.messages m
      join mine on mine.id = m.conversation_id
     where m.expires_at > now()
       and not exists (select 1 from public.message_hidden h where h.message_id = m.id and h.user_id = v_uid)
  ),
  last_msg as (
    select distinct on (v.conversation_id) v.* from visible v
     order by v.conversation_id, v.sent_at desc
  ),
  unread as (
    select v.conversation_id, count(*)::int as n from visible v
      join mine on mine.id = v.conversation_id
     where v.sender_id is distinct from v_uid and v.deleted_at is null and v.kind = 'text'
       and (mine.read_up_to is null or v.sent_at > mine.read_up_to)
     group by v.conversation_id
  )
  select mine.id, mine.kind,
         peer.user_id, p.handle, p.display_name, p.avatar_path,
         (p.id is null or p.deleted_at is not null),
         coalesce(private.is_blocked_between(v_uid, peer.user_id), false),
         lm.id, lm.sender_id, lm.body, lm.deleted_at is not null, lm.sent_at, lm.expires_at, lm.kind,
         least(coalesce(mine.ttl_seconds, v_max), v_max),
         coalesce(u.n, 0),
         mine.pinned_at is not null, mine.archived_at is not null,
         peer.delivered_up_to, peer.read_up_to,
         coalesce(lm.sent_at, mine.created_at)
    from mine
    left join public.conversation_members peer
           on peer.conversation_id = mine.id and peer.user_id <> v_uid
    left join public.profiles p on p.id = peer.user_id
    left join last_msg lm on lm.conversation_id = mine.id
    left join unread u on u.conversation_id = mine.id
   -- Une discussion vide n'apparaît que chez la personne qui l'a créée.
   where lm.id is not null or mine.created_by = v_uid
   order by (mine.pinned_at is not null) desc, coalesce(lm.sent_at, mine.created_at) desc;
end;
$$;




select private.harden_privileges();
grant execute on function public.list_conversations() to authenticated;
grant execute on function public.report(text, uuid, uuid, uuid, text, boolean) to authenticated;
grant execute on function public.delete_my_account(text) to authenticated;
