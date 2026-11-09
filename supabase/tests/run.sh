#!/usr/bin/env bash
# Runs all migrations + tests against a throwaway local Postgres (16+). Usage: supabase/tests/run.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
DATA="$(mktemp -d)"; PORT="${PG_PORT:-55432}"; RUNAS=""
if [ "$(id -u)" = "0" ]; then chown -R postgres "$DATA"; RUNAS="runuser -u postgres --"; fi
$RUNAS "$BIN/initdb" -D "$DATA" -A trust -U postgres -E UTF8 --locale=C.UTF-8 >/dev/null
$RUNAS "$BIN/pg_ctl" -D "$DATA" -o "-p $PORT -k /tmp" -l "$DATA/log" -w start >/dev/null
trap '$RUNAS "$BIN/pg_ctl" -D "$DATA" -m immediate stop >/dev/null; rm -rf "$DATA"' EXIT
PSQL="psql -h /tmp -p $PORT -U postgres -d postgres -v ON_ERROR_STOP=1 -q"
$PSQL -f "$ROOT/supabase/tests/00_supabase_shim.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do $PSQL -f "$f"; done
$PSQL -f "$ROOT/supabase/tests/10_test_all.sql" 2>&1 >/dev/null  | sed -e "s/^psql:[^:]*:[0-9]*: //" -e "s/^NOTICE:  //"
$PSQL -f "$ROOT/supabase/tests/20_pentest.sql" 2>&1 >/dev/null  | sed -e "s/^psql:[^:]*:[0-9]*: //" -e "s/^NOTICE:  //"
$PSQL -f "$ROOT/supabase/tests/30_demo.sql" 2>&1 >/dev/null  | sed -e "s/^psql:[^:]*:[0-9]*: //" -e "s/^NOTICE:  //"
