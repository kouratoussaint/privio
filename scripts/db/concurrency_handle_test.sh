#!/usr/bin/env bash
# Scénario AUTH n°4 : deux comptes réclament simultanément le même identifiant.
# Attendu : exactement un succès, l'autre reçoit HANDLE_TAKEN.
# Usage : DATABASE_URL=postgresql://... scripts/db/concurrency_handle_test.sh
set -euo pipefail
DB="${DATABASE_URL:?DATABASE_URL requis}"
U1=00000000-0000-0000-0000-00000000c0c1; S1=00000000-0000-0000-0000-00000000c1c1
U2=00000000-0000-0000-0000-00000000c0c2; S2=00000000-0000-0000-0000-00000000c2c2
cleanup() { psql "$DB" -q -c "delete from auth.users where id in ('$U1','$U2');" >/dev/null; }
trap cleanup EXIT
cleanup
psql "$DB" -q -v ON_ERROR_STOP=1 >/dev/null <<SQL
insert into auth.users (id, phone, phone_confirmed_at) values
  ('$U1','22679990001',now()), ('$U2','22679990002',now());
insert into auth.sessions (id, user_id) values ('$S1','$U1'), ('$S2','$U2');
SQL
claim() { psql "$DB" -qAt 2>&1 <<SQL
begin;
select set_config('request.jwt.claims','{"sub":"$1","session_id":"$2","role":"authenticated"}', true);
set local role authenticated;
select pg_sleep(1);
select handle from public.create_profile('meme_nom', 'Test');
select pg_sleep(1);
commit;
SQL
}
claim "$U1" "$S1" > /tmp/c1.out & claim "$U2" "$S2" > /tmp/c2.out & wait
OK=$(grep -h -c '^meme_nom$' /tmp/c1.out /tmp/c2.out | paste -sd+ | bc)
TAKEN=$(grep -h -c 'HANDLE_TAKEN' /tmp/c1.out /tmp/c2.out | paste -sd+ | bc)
ROWS=$(psql "$DB" -qAt -c "select count(*) from public.profiles where handle='meme_nom';")
echo "succès=$OK, HANDLE_TAKEN=$TAKEN, lignes=$ROWS"
[ "$OK" = 1 ] && [ "$TAKEN" = 1 ] && [ "$ROWS" = 1 ] && echo "CONCURRENCE OK" || { echo "ÉCHEC"; exit 1; }
