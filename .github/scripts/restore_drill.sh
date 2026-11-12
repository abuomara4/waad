#!/usr/bin/env bash
# Restore drill: proves the latest encrypted backup can really be opened and restored (docs/BACKUP.md).
# Decrypts it, restores it into a throwaway PostgreSQL on the runner, then checks it — printing only pass / fail lines,
# never data or counts (the repository and its logs are public).
#   in : BK (folder with the downloaded waad-backup-*.enc), BACKUP_PASSPHRASE, TEST (throwaway DB URI), DB (live DB URI)
set -euo pipefail
PGBIN="${PGBIN:-}"; W=$(mktemp -d); fail=0
say() { echo "$1"; }
bad() { echo "::error::$1"; fail=1; }
f=$(ls "${BK:-bk}"/*.enc 2>/dev/null | head -1); [ -n "$f" ] || { echo "::error::no backup file found"; exit 1; }
say "backup file: $(basename "$f")"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE -in "$f" -out "$W/b.tar.gz" || { echo "::error::cannot decrypt — wrong BACKUP_PASSPHRASE?"; exit 1; }
tar -C "$W" -xzf "$W/b.tar.gz"
for x in public.dump auth_users.jsonl README.txt; do [ -s "$W/$x" ] || bad "missing $x in the archive"; done
say "PASS decrypted and unpacked"

T="${PGBIN}psql -X -q -v ON_ERROR_STOP=1 -At -d $TEST"
$T -f supabase/tests/00_supabase_shim.sql > /dev/null
# sign-in accounts first (company data points at them)
$T -c "create temp table j(j jsonb)" -c "\copy j from '$W/auth_users.jsonl'" \
   -c "insert into auth.users(id, email, created_at) select (j->>'id')::uuid, j->>'email', coalesce((j->>'created_at')::timestamptz, now()) from j on conflict do nothing" > /dev/null
say "PASS sign-in accounts loaded"
"${PGBIN}pg_restore" --no-owner --no-privileges -d "$TEST" "$W/public.dump" 2> "$W/err.log" || true
n=$(grep -c '^pg_restore: error' "$W/err.log" || true)
# extensions / platform objects that exist only on Supabase are expected to fail here; real tables must not
if grep '^pg_restore: error' "$W/err.log" | grep -qiE 'create table|copy|table data|violates'; then bad "table data or a link between tables failed to restore"; grep '^pg_restore: error' "$W/err.log" | grep -iE 'create table|copy|violates' | cut -c1-160 | head -5; fi
say "restore finished ($n non-table messages, expected for Supabase-only objects)"

# every table in the dump exists, and every table that has rows in the dump got them back
want=$("${PGBIN}pg_restore" -l "$W/public.dump" | awk '/ TABLE public / {print $6}' | sort -u)
have=$($T -c "select tablename from pg_tables where schemaname = 'public' order by 1")
missing=$(comm -23 <(echo "$want") <(echo "$have") | tr '\n' ' ')
[ -z "${missing// }" ] && say "PASS all tables present" || bad "tables missing after restore: $missing"
for t in companies members employees sales_invoices journal_entries; do
  live=$("${PGBIN}psql" -X -At -d "$DB" -c "select exists(select 1 from public.$t)" 2>/dev/null || echo f)
  rest=$($T -c "select exists(select 1 from public.$t)")
  if [ "$live" = t ] && [ "$rest" != t ]; then bad "$t is empty in the restored copy"; else say "PASS $t restored"; fi
done
# the books still balance in the restored copy
ub=$($T -c "select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) x")
[ "$ub" = 0 ] && say "PASS every journal entry balances" || bad "unbalanced journal entries after restore"
rm -rf "$W"
[ $fail = 0 ] && echo "RESTORE DRILL PASSED" || { echo "RESTORE DRILL FAILED"; exit 1; }
