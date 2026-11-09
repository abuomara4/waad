#!/usr/bin/env bash
# Starts a throwaway Postgres with all migrations + the mock Supabase API. Usage: devserver/start.sh <static_dir> [autoconfirm=1]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)"; PORT=55440; HTTP=54321
DATA=/tmp/waad-dev-pg; [ -f /tmp/waad-mock.pid ] && kill "$(cat /tmp/waad-mock.pid)" 2>/dev/null || true
[ -d $DATA ] && { runuser -u postgres -- $BIN/pg_ctl -D $DATA -m immediate stop >/dev/null 2>&1 || true; rm -rf $DATA; }
mkdir -p $DATA; chown postgres $DATA
runuser -u postgres -- $BIN/initdb -D $DATA -A trust -U postgres -E UTF8 --locale=C.UTF-8 >/dev/null
runuser -u postgres -- $BIN/pg_ctl -D $DATA -o "-p $PORT -k /tmp" -l $DATA/log -w start >/dev/null
P="psql -X -q -h /tmp -p $PORT -U postgres -v ON_ERROR_STOP=1"
$P -f "$ROOT/supabase/tests/00_supabase_shim.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do $P -f "$f"; done
nohup python3 "$ROOT/devserver/mock_supabase.py" $PORT $HTTP "$1" "${2:-1}" > /tmp/waad-mock.log 2>&1 & echo $! > /tmp/waad-mock.pid
sleep 1; echo "ready: http://127.0.0.1:$HTTP"
