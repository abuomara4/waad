# Waad (وعد) — bilingual HR + ERP for Saudi SMEs

Owner: Abdulaziz Al-Fawzan (HR professional, Riyadh). Reply in Arabic, concise, direct, show trade-offs.
Everything is bilingual Arabic (RTL, default) + English, must follow Saudi Labor Law, work on desktop + mobile.
Free-tier only (Supabase free plan + GitHub). One account = one company. Platform admin sees only subscription metadata, never company data.

## What this is
A single-file vanilla-JS web app (no framework, no bundler) with a Supabase (Postgres + PostgREST + Auth) backend.
The whole frontend is concatenated into ONE self-contained HTML file and hosted statically.

## Layout
- `app/src/*.js` + `app/src/style.css` — the source. Each module registers routes on `VIEWS['#/...']`.
- `app/build.py` — concatenates `app/i18n/en.tsv` (as a `const EN = {...}`) + an EXPLICIT list of `src/*.js` into `app/waad-app.html`. The file list is hard-coded in build.py (not a glob) — add new src files there.
- `app/i18n/en.tsv` — Arabic→English, one pair per `\t` line. UI is authored in Arabic; `tr()` translates each Arabic run at render time. Add entries with `echo 'arabic|english' | python3 app/i18n/add.py` (it re-sorts). `python3 app/i18n/extract.py` MUST print `0 missing`.
- `supabase/migrations/NNNN_*.sql` — ordered DB migrations (RLS on every table; `has_role(company, roles[])` gates access).
- `supabase/tests/run.sh` — spins a throwaway Postgres, applies all migrations + test files, must end `… 0 failed`.
- `app/tests/e2e_app.py` — Playwright end-to-end against the dev server.
- `devserver/start.sh app` — serves the built app on port 54321 with a mock Supabase; needs a FRESH DB each run (restart between runs).
- `site/` — the published output dir. Website = 4 pages built by `python3 site/build.py` from `site/layout.html` (shared head/header/footer/script) + `site/pages/{home,modules,trust,contact}.html` → `site/index.html`, `modules.html`, `trust.html`, `contact.html`. Edit the layout/pages, never the built files. System = `site/app/index.html` (copied from the app build by CI). Admin site = `site/admin/index.html` (CI copies `app/waad-admin.html`: build.py's second output, core.js + legal.js + platform.js with `ADMIN_SITE`; platform admins only — companies/subscriptions, system numbers, website visitors, website texts, announcements, team). The Waad team signs in with a username (`<user>@admin.waad.app`, 0063); admins add each other from «فريق وعد»; `?setup` only creates an account, which a migration or an admin must activate. New companies start as `pending` (0068, `platform_settings.require_approval`, off in dev/tests) until an admin accepts them as a trial or a subscription for N days (`trial_ends` / `sub_ends`). `.github/workflows/notify.yml` (every 10 min) e-mails/WhatsApps the team about new requests — optional secrets `NOTIFY_GMAIL_USER`, `NOTIFY_GMAIL_APP_PASSWORD`, `NOTIFY_EMAIL_TO`, `CALLMEBOT_PHONE`, `CALLMEBOT_APIKEY`. The same job e-mails each customer 3 days before its trial/subscription ends (`reminded_end`). The admin site requires two-step verification (`platform_settings.require_admin_mfa`, 0071; off in dev/tests). `.github/workflows/backup.yml` makes a daily AES-encrypted dump (secret `BACKUP_PASSPHRASE`, 30-day artifacts); restore steps in `docs/BACKUP.md`. Support: customers' managers write from «الدعم الفني» (`app/src/support.js`, `#/support`) and the team answers in the admin site «طلبات الدعم» (0072); the notify job e-mails new requests to the team, replies to the customer, and a welcome e-mail after acceptance (`welcomed_at`). «أخطاء النظام» shows `client_errors` grouped. Customers start with their real data (no sample-data offer; `demo_seed` stays for `site/screens.py`); creating a company requires consent to storage outside the Kingdom (`companies.xfer_consent_at`, 0075) and the privacy/terms say so. Owners/admins see a trial/subscription countdown bar (`drawSubBar`). Forms («النماذج», `#/forms`): 42 bilingual ready-made forms in `app/src/forms_lib.js` (excluded from i18n extract; placeholders {e.*} {p.*} {c.*} {f:key}), auto-fill per form in `FORM_PRE` (forms.js), company templates in `form_templates`, every print numbered F-YYYY-NNNN in `form_issues` (0076). The website's own counter and its admin-editable texts (contact, notice bar, FAQ) are anon RPCs `site_hit` / `site_content` (0062); Cloudflare Web Analytics runs alongside. Share image `site/og.png` from `site/og.py`. Module screenshots `site/img/*.webp` (AR+EN, sample data only) from `site/screens.py` — run it on a fresh `devserver/start.sh app` after UI changes.
- `docs/RULES.md` — Saudi Labor Law rules; any change needs a cited source.

## Build / test (run before every commit)
```
python3 app/build.py                 # -> app/waad-app.html  (print is code-point count, not bytes)
python3 app/i18n/extract.py          # must say "0 missing"
bash supabase/tests/run.sh           # must say "0 failed"   (needs docker/postgres)
```

## Deploy — automated by CI (this replaces all manual steps)
`.github/workflows/deploy.yml`: on push to `main` it runs the DB tests + i18n check + build + browser tests, then (main only) applies NEW Supabase migrations and publishes the app.
One repository secret the owner adds once (Settings → Secrets and variables → Actions):
- `SUPABASE_DB_URL` — Supabase → Project Settings → Database → connection string (URI, session pooler).
Publishing needs no token: the deploy job commits the built app to `site/app/index.html` on `main` with its own `GITHUB_TOKEN` (commit tagged `[skip ci]`), and GitHub Pages serves `main` /.
First deploy treats migrations up to `supabase/BASELINE` as already applied by hand and applies the rest.
After that: edit source → build + tests green → commit → push. CI migrates Supabase and deploys. No manual SQL editor, no manual file upload.

## Conventions
- Money/legal logic = pure functions with tests. Never invent legal facts or rates; verify and cite.
- Keep the app one self-contained file; external scripts only from allowed CDNs; inline CSS/JS.
- Roles: owner/admin/hr/finance/accountant/storekeeper/sales/purch + employee. Modules gated by `company_subscriptions.modules`.

## Live
Hosted via GitHub Pages: system at `abuomara4.github.io/waad/site/app/`, landing page at `/waad/site/`, admin site at `/waad/site/admin/`. The repo-root `index.html` only redirects to `site/app/` (keeps query + hash). Cloudflare Pages `waad-4k1.pages.dev` serves the landing page.
Local testing on macOS: `brew install postgresql@16`, then run tests with `LC_ALL=en_US.UTF-8 PG_BIN=/opt/homebrew/opt/postgresql@16/bin PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH`. Browser tests need `pip install playwright==1.49.1 openpyxl pillow numpy opencv-python-headless`. Current built app SHA is in the repo's latest commit on `site/app/index.html`.
