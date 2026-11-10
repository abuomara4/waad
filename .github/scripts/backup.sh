#!/usr/bin/env bash
# Daily database backup, encrypted before it leaves the runner (the repository is public; artifacts can be downloaded
# by any signed-in GitHub user, so nothing is ever stored unencrypted).
#   in : DB (connection URI), BACKUP_PASSPHRASE (the owner's own passphrase, kept in a password manager), OUT (folder)
#   out: $OUT/waad-backup-<date>.tar.gz.enc  =  public schema (pg_dump custom format) + sign-in accounts (JSON lines)
# Restore: see docs/BACKUP.md.
set -euo pipefail
DB="$(printf '%s' "${DB:-}" | tr -d '[:space:]')"
case "$DB" in postgres://*|postgresql://*) ;; *) echo "::error::SUPABASE_DB_URL is missing or not a connection URI"; exit 1;; esac
[ -n "${BACKUP_PASSPHRASE:-}" ] || { echo "::error::Add the BACKUP_PASSPHRASE secret first — the backup is never stored unencrypted"; exit 1; }
[ ${#BACKUP_PASSPHRASE} -ge 12 ] || { echo "::error::BACKUP_PASSPHRASE must be 12 characters or more"; exit 1; }
PGBIN="${PGBIN:-}"; OUT="${OUT:-backup}"; D=$(date -u +%Y-%m-%d); W=$(mktemp -d)
mkdir -p "$OUT"
"${PGBIN}pg_dump" -d "$DB" -Fc --schema=public --no-owner --no-privileges -f "$W/public.dump"
"${PGBIN}psql" -X -q -d "$DB" -v ON_ERROR_STOP=1 -c "\copy (select row_to_json(u) from auth.users u order by u.created_at) to '$W/auth_users.jsonl'"
printf 'Waad backup %s (UTC)\npublic.dump: pg_restore --no-owner --no-privileges -d <db> public.dump\nauth_users.jsonl: sign-in accounts, one JSON per line (password hashes only)\n' "$D" > "$W/README.txt"
tar -C "$W" -czf "$W/b.tar.gz" public.dump auth_users.jsonl README.txt
openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:BACKUP_PASSPHRASE -in "$W/b.tar.gz" -out "$OUT/waad-backup-$D.tar.gz.enc"
rm -rf "$W"
echo "backup ready: $OUT/waad-backup-$D.tar.gz.enc ($(du -h "$OUT/waad-backup-$D.tar.gz.enc" | cut -f1))"
