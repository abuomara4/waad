# Waad — daily backup and restore

**What:** `.github/workflows/backup.yml` runs every day at 05:00 Riyadh (and on demand: Actions → *daily backup* → *Run workflow*).
It dumps the `public` schema (all company data) and the sign-in accounts, **encrypts** the archive with the owner's
passphrase (`BACKUP_PASSPHRASE` secret, AES-256, PBKDF2) and keeps it 30 days as the run's artifact `waad-backup`.
The repository is public, so an unencrypted copy is never stored; without the passphrase the file is useless — keep the
passphrase in a password manager. If it is lost, old backups cannot be opened (set a new one; new backups use it).

**Restore** (on a computer with `openssl` and PostgreSQL 17 client tools):

```bash
# 1. download the artifact from the run page (Actions → daily backup → a run → waad-backup), unzip it
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in waad-backup-YYYY-MM-DD.tar.gz.enc -out backup.tar.gz   # asks for the passphrase
tar -xzf backup.tar.gz            # public.dump, auth_users.jsonl, README.txt
# 2. look before you restore: list what is inside
pg_restore -l public.dump | head
# 3. restore into a NEW, empty Supabase project (never over the live one without a reason):
#    apply supabase/migrations first is NOT needed — the dump carries the tables; then
pg_restore --no-owner --no-privileges --clean --if-exists -d "postgresql://…new project…" public.dump
```

`auth_users.jsonl` holds the sign-in accounts (one JSON per line, password hashes only); they are re-created in the new
project's `auth.users` only if the whole project has to be rebuilt — ask for help with that step.
