#!/usr/bin/env bash
# @file        scripts/ci/check-root-hygiene.sh
# @module      ci/repo
# @description Enforce repository folder taxonomy and root hygiene.
#              Blocks root-level clutter and non-entrypoint files. Exits non-zero on violations.
#
# Usage: bash scripts/ci/check-root-hygiene.sh [--warn-only]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

WARN_ONLY="${1:-}"
VIOLATIONS=0

warn_or_fail() {
  local msg="$1"
  if [[ "$WARN_ONLY" == "--warn-only" ]]; then
    log_warn "$msg"
  else
    log_error "$msg"
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  fi
}

pass() { log_info "$1"; }

# ── Allowed root entries ───────────────────────────────────────────────────────
# Every file/directory at root must be in this set.
ALLOWED_ROOT_ENTRIES=(
  # Standard entrypoints
  README.md LICENSE CONTRIBUTING.md MANIFEST.md ARCHITECTURE.md
  Makefile Makefile.remote-access Makefile.192.168.168.31
  # Docker / Compose
  Dockerfile Dockerfile.caddy Dockerfile.code-server
  Dockerfile.ssh-proxy Dockerfile.token-microservice
  docker-compose.yml docker-compose.base.yml docker-compose.dev.yml
  docker-compose.production.yml docker-compose.tpl
  docker-compose.yml.remote
  # Config entrypoints
  .env.defaults .env.example .env.template .env
  Caddyfile Caddyfile.clean Caddyfile.known-good Caddyfile.production Caddyfile.tpl
  code-server-config.yaml oauth2-proxy.cfg allowed-emails.txt
  # Infrastructure
  main.tf variables.tf .terraform.lock.hcl terraform.phase-14.tfvars
  package.json pnpm-lock.yaml pnpm-workspace.yaml
  # GitHub Actions/Meta
  .github .gitignore .gitattributes .hadolint.yaml .editorconfig
  # Canonical root directories
  scripts docs terraform config k8s kubernetes extensions
  apps backend frontend src environments opa docker deprecated grafana
  lib packages infra policies workspace services operations ansible
  .vscode
  # Monitoring/alerting config entrypoints
  prometheus.yml
  prometheus-production.yml alert-rules.yml alertmanager.yml
  alertmanager-base.yml alertmanager-production.yml
  loki-config.yml otel-config.yml grafana-datasources.yml
  prometheus-rules-alerts-operational.yml
  prometheus-rules-slo-phase-8.yml
  prometheus-rules-phase-23.yml
  alerts-phase-23.yml
  # Postgres
  postgres-init.sql
  # OTEL / tracing
  patch-product.js
  # Legacy (tracked, allowed temporarily)
  k8s-serviceaccounts.yaml
)

# ── Blocked filename patterns (root-level only) ────────────────────────────────
declare -a BLOCKED_PATTERNS=(
  "PHASE-*.md"
  "FINAL-*.md"
  "MIGRATION-*.md"
  "ISSUE-TRIAGE-*.md"
  "DEPLOYMENT-CHECKLIST-*.md"
  "IMPLEMENTATION_SUMMARY_*.md"
  "IMPLEMENTATION-ROADMAP-*.md"
  "ELITE-*.md"
  "CHAT-SANITIZATION-*.md"
  "FORCE-CI-RERUN.txt"
  "GPU-UPGRADE-*.txt"
  "*-COMPLETE.md"
  "*-SUMMARY.md"
  "*-ACTIVE.txt"
  "phase-*.yml"
  "docker-compose-phase-*.yml"
  "docker-compose-p0-*.yml"
  "fix-*.py"
  "fix-*.sh"
  "issue_update.txt"
  "launch-isolated.bat"
  "branch-protection.json"
)

# ── Check blocked patterns ────────────────────────────────────────────────────
log_info ""
log_info "Checking for blocked root-level file patterns..."
for pattern in "${BLOCKED_PATTERNS[@]}"; do
  while IFS= read -r -d '' f; do
    name=$(basename "$f")
    warn_or_fail "root-level file should be moved to docs/ or removed: $name (matches pattern: $pattern)"
  done < <(find . -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
done

# ── Check for unexpected root-level files ────────────────────────────────────
log_info ""
log_info "Checking for unexpected root-level entries..."

# Build lookup set from ALLOWED_ROOT_ENTRIES
declare -A allowed_set
for entry in "${ALLOWED_ROOT_ENTRIES[@]}"; do
  allowed_set["$entry"]=1
done

while IFS= read -r -d '' entry; do
  name=$(basename "$entry")
  # Skip hidden files not explicitly allowed (warn only)
  if [[ "$name" == .* && -z "${allowed_set[$name]:-}" ]]; then
    log_info "hidden entry $name (review if intentional)"
    continue
  fi
  if [[ -z "${allowed_set[$name]:-}" ]]; then
    warn_or_fail "unexpected root-level entry: $name (add to allowed list or move to docs/scripts/config/)"
  fi
done < <(find . -maxdepth 1 \( -type f -o -type d \) ! -name '.' -print0 2>/dev/null)

# ── Summary ────────────────────────────────────────────────────────────────────
log_info ""
if (( VIOLATIONS > 0 )); then
  log_error "$VIOLATIONS violation(s) found."
  log_error "Move status reports and draft files to docs/ — root is for entrypoints only."
  exit 1
else
  log_info "root is clean."
  exit 0
fi
