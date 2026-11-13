-- PRIVIO — lot 4.8 : invitations de groupe notifiées.
--
-- Constat : une invitation à rejoindre un groupe ne déclenchait aucune notification (seuls
-- les messages et les demandes de connexion en ont). Hors de l'application, l'invité
-- n'était prévenu de rien ; il ne la voyait qu'en rouvrant l'app.
--
-- Désormais, chaque invitation envoie une notification SANS CONTENU (« Nouvelle invitation
-- à rejoindre un groupe » : ni nom du groupe, ni nom de la personne qui invite). Un appui
-- ouvre l'onglet Groupes. Même chemin que les demandes de connexion : pg_net appelle
-- push-dispatch avec le seul identifiant, la base renvoie les jetons du destinataire.

-- ---------------------------------------------------------------------------
-- Notification d'une invitation (après validation de la transaction, via pg_net)
-- ---------------------------------------------------------------------------
create or replace function private.notify_invitation(p_user uuid, p_invitation_id uuid)
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
  if v_url is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null
     or not exists (select 1 from private.push_tokens t where t.user_id = p_user) then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)'
    using v_url || '/push-dispatch', jsonb_build_object('invitation_id', p_invitation_id),
          jsonb_build_object('Content-Type', 'application/json', 'x-privio-push', v_token), 10000;
end;
$$;

-- Inviter : inchangé (lot 4.3), plus la notification.
create or replace function private.invite(p_conversation_id uuid, p_inviter uuid, p_invitee uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_max     integer := private.policy_int('group_max_members');
  v_pending integer;
  v_id      uuid;
begin
  if p_invitee is null or p_invitee = p_inviter
     or not exists (select 1 from public.profiles p where p.id = p_invitee and p.deleted_at is null)
     or private.is_member(p_conversation_id, p_invitee)
     or private.is_blocked_between(p_inviter, p_invitee)
     or not private.visible_to((private.privacy_of(p_invitee)).group_invites, p_invitee, p_inviter)
     or exists (select 1 from private.group_invitations i
                 where i.conversation_id = p_conversation_id and i.invitee_id = p_invitee
                   and i.status = 'pending' and i.expires_at > now()) then
    return false;
  end if;
  select count(*)::int into v_pending from private.group_invitations i
   where i.conversation_id = p_conversation_id and i.status = 'pending' and i.expires_at > now();
  if private.active_member_count(p_conversation_id) + v_pending >= v_max then
    raise exception 'GROUP_FULL' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(p_inviter, 'group_invite',
    private.policy_int('group_invite_hourly_limit'), interval '1 hour');
  update private.group_invitations set status = 'revoked'
   where conversation_id = p_conversation_id and invitee_id = p_invitee and status = 'pending';
  insert into private.group_invitations (conversation_id, invitee_id, inviter_id, expires_at)
  values (p_conversation_id, p_invitee, p_inviter,
          now() + make_interval(days => private.policy_int('group_invitation_ttl_days')))
  returning id into v_id;
  perform private.signal_user(p_invitee, p_conversation_id, 'invitation');
  perform private.notify_invitation(p_invitee, v_id);
  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- Jetons à notifier (réservé à push-dispatch) : l'invité, si l'invitation est encore
-- en attente, sans blocage entre les deux, sur ses appareils non révoqués.
-- ---------------------------------------------------------------------------
create or replace function public.push_invitation_targets(p_token text, p_invitation_id uuid)
returns table (token text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  i private.group_invitations%rowtype;
begin
  perform private.check_push_token(p_token);
  select * into i from private.group_invitations g where g.id = p_invitation_id;
  if not found or i.status <> 'pending' or i.expires_at <= now() then
    return;
  end if;
  if i.inviter_id is not null and private.is_blocked_between(i.inviter_id, i.invitee_id) then
    return;
  end if;
  return query
  select t.token
    from private.push_tokens t
    join public.devices d on d.id = t.device_id and d.revoked_at is null
   where t.user_id = i.invitee_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------------
select private.harden_privileges();

revoke all on function public.push_invitation_targets(text, uuid) from authenticated;
grant execute on function public.push_invitation_targets(text, uuid) to service_role;
