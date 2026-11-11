#!/usr/bin/env bash
# Exécute migrations + tests pgTAP sur un PostgreSQL local (sans Docker).
# Usage : scripts/db/run_local_tests.sh   (nécessite psql, pg_prove, pgTAP)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB="${PRIVIO_TEST_DB:-privio_test}"
PSQL="psql -v ON_ERROR_STOP=1 -q"
dropdb --if-exists "$DB" && createdb "$DB"
$PSQL -d "$DB" -c "create extension if not exists pgtap;" >/dev/null
$PSQL -d "$DB" -f "$ROOT/scripts/db/local_auth_stub.sql" >/dev/null
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "→ migration $(basename "$f")"
  $PSQL -d "$DB" -f "$f" >/dev/null
done
pg_prove -d "$DB" "$ROOT"/supabase/tests/database/*.test.sql
