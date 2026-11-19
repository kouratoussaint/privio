-- Lot 6.1 (ADR-055) : données des mesures de vitesse sur émulateur, base LOCALE seulement.
-- « Discussion longue » est la plus récente (en haut de la liste).
-- Compte « Mesure » (+226 70 00 00 03, code de test local, créé auparavant par une
-- connexion Auth) : 300 discussions, dont une de 1 000 messages avec « Discussion longue ».
-- Jamais exécuté ailleurs qu'en CI locale.
begin;
do $$
declare
  v_me uuid := (select id from auth.users where phone = '22670000003');
  v_peer uuid;
  v_conv uuid;
  v_long uuid;
  i int;
begin
  if current_setting('privio.seed_local', true) is distinct from 'oui' then
    raise exception 'Données de mesure : base locale seulement (set privio.seed_local = oui).';
  end if;
  if v_me is null then
    raise exception 'Compte de mesure absent : connectez d''abord +22670000003 (code de test).';
  end if;
  insert into public.profiles (id, handle, display_name) values (v_me, 'mesure_vitesse', 'Mesure');

  for i in 1..300 loop
    v_peer := gen_random_uuid();
    insert into auth.users (id, instance_id, aud, role, phone, phone_confirmed_at, created_at, updated_at)
    values (v_peer, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            '2267100' || lpad(i::text, 4, '0'), now(), now(), now());
    insert into public.profiles (id, handle, display_name)
    values (v_peer, 'contact_' || lpad(i::text, 3, '0'),
            case when i = 1 then 'Discussion longue' else 'Contact ' || i end);
    v_conv := private.create_direct_conversation(v_me, v_peer);
    if i = 1 then v_long := v_conv; end if;
    insert into public.messages (conversation_id, sender_id, client_msg_id, body, sent_at, expires_at)
    values (v_conv, v_peer, gen_random_uuid(), 'Bonjour, message n° ' || i,
            now() - interval '2 hours' + make_interval(secs => i), now() + interval '24 hours');
  end loop;

  insert into public.messages (conversation_id, sender_id, client_msg_id, body, sent_at, expires_at)
  select v_long, case when n % 3 = 0 then v_me else
           (select user_id from public.conversation_members where conversation_id = v_long and user_id <> v_me) end,
         gen_random_uuid(),
         'Message ' || n || case when n % 7 = 0 then ' : un texte un peu plus long pour varier la hauteur des bulles, comme dans une vraie discussion.' else '' end,
         now() - make_interval(secs => 1001 - n), now() + interval '24 hours'
    from generate_series(1, 1000) n;
  update public.conversations set last_message_at = now() where id = v_long;
end $$;
commit;
analyze public.messages, public.conversations, public.conversation_members, public.profiles;
