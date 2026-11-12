#!/usr/bin/env bash
# Concurrence réelle (deux connexions simultanées) :
#  1. A et B démarrent la même discussion au même instant → une seule discussion ;
#  2. le même message (même identifiant client) envoyé deux fois en parallèle → un seul message.
# Usage : DATABASE_URL=postgresql://... scripts/db/concurrency_messaging_test.sh
set -euo pipefail
DB="${DATABASE_URL:?DATABASE_URL requis}"
A=00000000-0000-0000-0000-00000000d0a1; SA=00000000-0000-0000-0000-00000000d1a1
B=00000000-0000-0000-0000-00000000d0b1; SB=00000000-0000-0000-0000-00000000d1b1
CID=33333333-3333-3333-3333-333333333333
cleanup() {
  psql "$DB" -q >/dev/null <<SQL
delete from public.conversations where direct_key = least('$A','$B') || ':' || greatest('$A','$B');
delete from auth.users where id in ('$A','$B');
SQL
}
trap cleanup EXIT
cleanup
psql "$DB" -q -v ON_ERROR_STOP=1 >/dev/null <<SQL
insert into auth.users (id, phone, phone_confirmed_at) values ('$A','22679990011',now()), ('$B','22679990012',now());
insert into auth.sessions (id, user_id) values ('$SA','$A'), ('$SB','$B');
insert into public.profiles (id, handle, display_name) values ('$A','conc_a','A'), ('$B','conc_b','B');
SQL
as_user() { # as_user <uid> <session> <sql>
  psql "$DB" -qAt 2>&1 <<SQL
begin;
select set_config('request.jwt.claims','{"sub":"$1","session_id":"$2","role":"authenticated"}', true);
set local role authenticated;
select pg_sleep(1);
$3
select pg_sleep(1);
commit;
SQL
}
as_user "$A" "$SA" "select public.start_direct_conversation('$B');" > /tmp/cc1 &
as_user "$B" "$SB" "select public.start_direct_conversation('$A');" > /tmp/cc2 &
wait
C1=$(grep -E '^[0-9a-f-]{36}$' /tmp/cc1 || true); C2=$(grep -E '^[0-9a-f-]{36}$' /tmp/cc2 || true)
N=$(psql "$DB" -qAt -c "select count(*) from public.conversations where direct_key = least('$A','$B') || ':' || greatest('$A','$B');")
echo "discussion : A=$C1 B=$C2 en base=$N"
[ -n "$C1" ] && [ "$C1" = "$C2" ] && [ "$N" = 1 ] || { echo "ÉCHEC : discussions en double"; cat /tmp/cc1 /tmp/cc2; exit 1; }

as_user "$A" "$SA" "select id from public.send_message('$C1', '$CID', 'parallèle');" > /tmp/cs1 &
as_user "$A" "$SA" "select id from public.send_message('$C1', '$CID', 'parallèle');" > /tmp/cs2 &
wait
M1=$(grep -E '^[0-9a-f-]{36}$' /tmp/cs1 || true); M2=$(grep -E '^[0-9a-f-]{36}$' /tmp/cs2 || true)
N=$(psql "$DB" -qAt -c "select count(*) from public.messages where client_msg_id = '$CID';")
echo "message : envoi1=$M1 envoi2=$M2 en base=$N"
[ -n "$M1" ] && [ "$M1" = "$M2" ] && [ "$N" = 1 ] || { echo "ÉCHEC : message en double"; cat /tmp/cs1 /tmp/cs2; exit 1; }
echo "CONCURRENCE MESSAGERIE OK"
