#!/usr/bin/env bash
# Run Strix (usestrix/strix) — an autonomous AI penetration-testing agent — against the
# Waad source code, locally and safely. Scanning the SOURCE DIRECTORY (not a live URL) means
# no traffic ever touches GitHub Pages or Supabase, so there is no third-party-infrastructure
# or terms-of-service concern. Results are written to ./strix_runs/<run-name>.
#
# Prerequisites (on your own machine, once):
#   1. Docker Desktop installed and RUNNING.
#   2. pipx:  python3 -m pip install --user pipx && python3 -m pipx ensurepath
#   3. An LLM API key from any provider Strix supports (OpenAI, Anthropic, Google, OpenRouter…).
#      This is billed to YOUR account; Waad never sees it.
#
# Usage:
#   export STRIX_LLM="openrouter/z-ai/glm-5.3"     # or openai/gpt-5.4, anthropic/..., etc.
#   export LLM_API_KEY="sk-..."                      # your key
#   ./security/run-strix.sh
set -euo pipefail
cd "$(dirname "$0")/.."                               # repo root (the Waad source)

if ! docker info >/dev/null 2>&1; then
  echo "✗ Docker is not running. Start Docker Desktop first." >&2; exit 1
fi
if [ -z "${LLM_API_KEY:-}" ] || [ -z "${STRIX_LLM:-}" ]; then
  echo "✗ Set STRIX_LLM and LLM_API_KEY first (see the header of this script)." >&2; exit 1
fi

# install once; upgrades are a no-op if already present
if ! command -v strix >/dev/null 2>&1; then
  echo "Installing Strix (one-time)…"; pipx install strix-agent
fi

# Scan the Waad source tree. We exclude the single-file build artifact and node/test noise so
# the agents focus on the real source under app/src and the database policies under supabase/.
echo "Scanning the Waad source with Strix… (first run pulls the sandbox image)"
strix --target . \
  --instruction "This is Waad, a bilingual Arabic/English HR+ERP for Saudi SMEs: a static single-page app (app/src/*.js, built into app/waad-app.html) backed by Supabase with the real security enforced in PostgreSQL row-level-security policies and SECURITY DEFINER functions under supabase/migrations/. Focus on: tenant isolation between companies, privilege escalation across roles, package/module access control, the two-factor (aal) gate, and any RPC that trusts a company_id argument. Do NOT send traffic to the public site or to Supabase; analyse the source only."

echo "Done. See ./strix_runs/ for the report."
