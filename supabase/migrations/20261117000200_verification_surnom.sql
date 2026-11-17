-- Lot 10.4 : « Vérifié en personne » et surnom privé (décisions du 17/11/2026, ADR-048).
--   Vérification : un QR code temporaire (2 min), créé par l'un POUR un contact précis et
--   scanné face à face par ce contact ; un seul scan vérifie les deux personnes. Le badge
--   tombe pour moi quand le contact se connecte sur un nouveau téléphone (toute nouvelle
--   session, déconnexion par la console comprise) ou change de numéro ; un avis propose de
--   revérifier, jusqu'à ce que je le ferme.
--   Surnom : visible par moi seul, gardé ici pour mon compte ; l'autre personne n'en sait
--   rien. Seulement pour une personne avec qui je partage une discussion.

-- ---------------------------------------------------------------------------
-- Tables (schéma private : jamais lues directement par l'application).
-- ---------------------------------------------------------------------------
create table if not exists private.contact_nicknames (
  owner_id   uuid        not null references auth.users (id) on delete cascade,
  target_id  uuid        not null references auth.users (id) on delete cascade,
  nickname   text        not null check (char_length(nickname) between 1 and 40),
  updated_at timestamptz not null default now(),
  primary key (owner_id, target_id),
  check (owner_id <> target_id)
);

-- Codes de vérification : seule l'empreinte du code est gardée ; usage unique.
create table if not exists private.verification_codes (
  code_hash  bytea       primary key,
  created_by uuid        not null references auth.users (id) on delete cascade,
  for_user   uuid        not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at    timestamptz
);
create index if not exists verification_codes_creator_idx on private.verification_codes (created_by);

-- Une ligne par paire (lo < hi). Pour chaque côté : le téléphone (ligne devices active) et
-- l'empreinte du numéro au moment de la vérification ; « seen_* » : la situation dont
-- l'avis a été fermé par l'AUTRE personne (lo a fermé l'avis concernant hi : seen_by_lo_*).
create table if not exists private.in_person_verifications (
  user_lo            uuid        not null references auth.users (id) on delete cascade,
  user_hi            uuid        not null references auth.users (id) on delete cascade,
  device_lo          uuid,
  device_hi          uuid,
  phone_lo           bytea,
  phone_hi           bytea,
  verified_at        timestamptz not null default now(),
  seen_by_lo_device  uuid,
  seen_by_lo_phone   bytea,
  seen_by_hi_device  uuid,
  seen_by_hi_phone   bytea,
  primary key (user_lo, user_hi),
  check (user_lo < user_hi)
);

alter table private.contact_nicknames enable row level security;
alter table private.verification_codes enable row level security;
alter table private.in_person_verifications enable row level security;

-- ---------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------
-- Téléphone actuellement connecté (ligne devices active), ou null.
create or replace function private.active_device(p_user uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select d.id from public.devices d
   where d.user_id = p_user and d.revoked_at is null
   order by d.created_at desc limit 1;
$$;

-- Empreinte du numéro (jamais le numéro lui-même dans les tables de vérification).
create or replace function private.phone_fingerprint(p_user uuid)
returns bytea
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.digest('privio-verif:' || coalesce(u.phone, ''), 'sha256')
    from auth.users u where u.id = p_user;
$$;

-- Vérification possible entre deux personnes : contacts (discussion à deux), aucun blocage,
-- comptes existants.
create or replace function private.require_verifiable(p_me uuid, p_other uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_other is null or p_other = p_me then
    raise exception 'VERIFY_NOT_CONTACT' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_other and p.deleted_at is null)
     or not private.are_contacts(p_me, p_other) then
    raise exception 'VERIFY_NOT_CONTACT' using errcode = 'P0001';
  end if;
  if coalesce(private.is_blocked_between(p_me, p_other), false) then
    raise exception 'BLOCKED' using errcode = 'P0001';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Vérification en personne
-- ---------------------------------------------------------------------------
-- Code à montrer à [p_user_id] (QR « privio:v:<code> »), valable 2 minutes, usage unique.
create or replace function public.create_verification_code(p_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := private.require_active_user();
  v_code    text;
  v_expires timestamptz := now() + interval '2 minutes';
begin
  perform private.require_verifiable(v_uid, p_user_id);
  perform private.consume_rate_limit(v_uid, 'verify_code', 10, interval '1 hour');
  -- Un seul code en cours par contact ; les vieux codes partent.
  delete from private.verification_codes
   where (created_by = v_uid and for_user = p_user_id and used_at is null)
      or expires_at < now() - interval '1 day';
  v_code := encode(extensions.gen_random_bytes(16), 'hex');
  insert into private.verification_codes (code_hash, created_by, for_user, expires_at)
  values (extensions.digest(v_code, 'sha256'), v_uid, p_user_id, v_expires);
  return jsonb_build_object('code', v_code, 'expires_at', v_expires, 'seconds', 120);
end;
$$;

-- Scanner le code de [p_user_id] (la personne dont j'ai ouvert la fiche). Vérifie les deux.
create or replace function public.confirm_verification_code(p_code text, p_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  c     private.verification_codes%rowtype;
  v_lo  uuid;
  v_hi  uuid;
  v_at  timestamptz := now();
begin
  perform private.consume_rate_limit(v_uid, 'verify_scan', 30, interval '1 hour');
  if p_code is null or p_code !~ '^[0-9a-f]{32}$' then
    raise exception 'VERIFY_CODE_INVALID' using errcode = 'P0001';
  end if;
  select * into c from private.verification_codes
   where code_hash = extensions.digest(p_code, 'sha256')
   for update;
  if not found then
    raise exception 'VERIFY_CODE_INVALID' using errcode = 'P0001';
  end if;
  -- Code créé pour une autre personne, ou par quelqu'un d'autre que la personne attendue.
  if c.for_user <> v_uid or c.created_by is distinct from p_user_id then
    raise exception 'VERIFY_WRONG_PERSON' using errcode = 'P0001';
  end if;
  if c.used_at is not null or c.expires_at <= now() then
    raise exception 'VERIFY_CODE_EXPIRED' using errcode = 'P0001';
  end if;
  perform private.require_verifiable(v_uid, c.created_by);
  update private.verification_codes set used_at = v_at where code_hash = c.code_hash;

  v_lo := least(v_uid, c.created_by);
  v_hi := greatest(v_uid, c.created_by);
  insert into private.in_person_verifications as v
    (user_lo, user_hi, device_lo, device_hi, phone_lo, phone_hi, verified_at)
  values (v_lo, v_hi, private.active_device(v_lo), private.active_device(v_hi),
          private.phone_fingerprint(v_lo), private.phone_fingerprint(v_hi), v_at)
  on conflict (user_lo, user_hi) do update
     set device_lo = excluded.device_lo, device_hi = excluded.device_hi,
         phone_lo = excluded.phone_lo, phone_hi = excluded.phone_hi,
         verified_at = excluded.verified_at,
         seen_by_lo_device = null, seen_by_lo_phone = null,
         seen_by_hi_device = null, seen_by_hi_phone = null;
  -- La personne qui montre le code voit le résultat aussitôt (sa liste se recharge).
  perform private.signal_user(c.created_by,
                              private.direct_conversation_between(v_uid, c.created_by),
                              'labels_changed');
  return jsonb_build_object('user_id', c.created_by, 'verified_at', v_at);
end;
$$;

-- État d'un code que j'ai créé : « pending », « verified » ou « expired ».
create or replace function public.verification_code_status(p_code text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
  c     private.verification_codes%rowtype;
begin
  select * into c from private.verification_codes
   where code_hash = extensions.digest(coalesce(p_code, ''), 'sha256') and created_by = v_uid;
  if not found then return 'expired'; end if;
  if c.used_at is not null then return 'verified'; end if;
  if c.expires_at <= now() then return 'expired'; end if;
  return 'pending';
end;
$$;

-- Fermer l'avis « vérification à refaire » (il revient si la situation change encore).
create or replace function public.dismiss_verification_notice(p_user_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_active_user();
begin
  if v_uid < p_user_id then
    update private.in_person_verifications
       set seen_by_lo_device = private.active_device(p_user_id),
           seen_by_lo_phone  = private.phone_fingerprint(p_user_id)
     where user_lo = v_uid and user_hi = p_user_id;
  else
    update private.in_person_verifications
       set seen_by_hi_device = private.active_device(p_user_id),
           seen_by_hi_phone  = private.phone_fingerprint(p_user_id)
     where user_lo = p_user_id and user_hi = v_uid;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Surnom privé
-- ---------------------------------------------------------------------------
create or replace function public.set_contact_nickname(p_user_id uuid, p_nickname text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_active_user();
  v_name text := btrim(regexp_replace(coalesce(p_nickname, ''), '\s+', ' ', 'g'));
begin
  if p_user_id is null or p_user_id = v_uid
     or not (private.shares_conversation(v_uid, p_user_id) or private.are_contacts(v_uid, p_user_id)) then
    raise exception 'NICKNAME_NOT_ALLOWED' using errcode = 'P0001';
  end if;
  perform private.consume_rate_limit(v_uid, 'nickname', 60, interval '1 hour');
  if v_name = '' then
    delete from private.contact_nicknames where owner_id = v_uid and target_id = p_user_id;
    return null;
  end if;
  if char_length(v_name) > 40 or v_name ~ '[[:cntrl:]]' then
    raise exception 'NICKNAME_INVALID' using errcode = 'P0001';
  end if;
  insert into private.contact_nicknames (owner_id, target_id, nickname)
  values (v_uid, p_user_id, v_name)
  on conflict (owner_id, target_id) do update set nickname = excluded.nickname, updated_at = now();
  return v_name;
end;
$$;

-- ---------------------------------------------------------------------------
-- Mes étiquettes : surnoms et vérifications, pour mon compte seulement.
--   verification : « verified », « lapsed » (à refaire) ou null ;
--   lapse : « device », « phone » ou « both » ; notice : avis à montrer.
-- ---------------------------------------------------------------------------
create or replace function public.my_contact_labels()
returns table (
  user_id      uuid,
  nickname     text,
  verification text,
  verified_at  timestamptz,
  lapse        text,
  notice       boolean
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
  with ver as (
    select case when v.user_lo = v_uid then v.user_hi else v.user_lo end as other,
           case when v.user_lo = v_uid then v.device_hi else v.device_lo end as dev,
           case when v.user_lo = v_uid then v.phone_hi else v.phone_lo end as ph,
           case when v.user_lo = v_uid then v.seen_by_lo_device else v.seen_by_hi_device end as seen_dev,
           case when v.user_lo = v_uid then v.seen_by_lo_phone else v.seen_by_hi_phone end as seen_ph,
           v.verified_at
      from private.in_person_verifications v
     where v.user_lo = v_uid or v.user_hi = v_uid
  ),
  st as (
    select ver.*, private.active_device(ver.other) as cur_dev,
           private.phone_fingerprint(ver.other) as cur_ph
      from ver
  ),
  lab as (
    select st.other,
           (st.cur_dev is distinct from st.dev) as dev_changed,
           (st.cur_ph is distinct from st.ph) as ph_changed,
           st.verified_at,
           (st.seen_dev is not distinct from st.cur_dev and st.seen_ph is not distinct from st.cur_ph) as seen
      from st
  )
  select coalesce(n.target_id, l.other),
         n.nickname,
         case when l.other is null then null
              when l.dev_changed or l.ph_changed then 'lapsed' else 'verified' end,
         l.verified_at,
         case when l.dev_changed and l.ph_changed then 'both'
              when l.dev_changed then 'device'
              when l.ph_changed then 'phone' end,
         coalesce((l.dev_changed or l.ph_changed) and not l.seen, false)
    from (select * from private.contact_nicknames where owner_id = v_uid) n
    full join lab l on l.other = n.target_id
    join public.profiles p on p.id = coalesce(n.target_id, l.other) and p.deleted_at is null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Nouveau téléphone : les personnes qui m'ont vérifié rechargent leurs étiquettes tout de
-- suite (le badge tombe, l'avis apparaît) ; sinon au prochain retour dans l'application.
-- ---------------------------------------------------------------------------
create or replace function private.on_device_verified_peers()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_other uuid;
begin
  for v_other in
    select case when v.user_lo = new.user_id then v.user_hi else v.user_lo end
      from private.in_person_verifications v
     where v.user_lo = new.user_id or v.user_hi = new.user_id
  loop
    perform private.signal_user(v_other, private.direct_conversation_between(new.user_id, v_other),
                                'labels_changed');
  end loop;
  return null;
end;
$$;

drop trigger if exists devices_verified_peers on public.devices;
create trigger devices_verified_peers
  after insert on public.devices
  for each row execute function private.on_device_verified_peers();

select private.harden_privileges();
revoke all on all tables in schema private from public, anon, authenticated;
grant execute on function public.create_verification_code(uuid) to authenticated;
grant execute on function public.confirm_verification_code(text, uuid) to authenticated;
grant execute on function public.verification_code_status(text) to authenticated;
grant execute on function public.dismiss_verification_notice(uuid) to authenticated;
grant execute on function public.set_contact_nickname(uuid, text) to authenticated;
grant execute on function public.my_contact_labels() to authenticated;
