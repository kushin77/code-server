#!/usr/bin/env bash
# @file        scripts/ops/entitlement-sync.sh
# @module      ops/auth
# @description Auto-entitlement sync: map GitHub repo/team membership to workspace service access.
#              Detects current user's GitHub access and provisions corresponding GCP/GSM credentials.
#              Implements policy-driven: repo access → service credential set.
#
# Usage: bash scripts/ops/entitlement-sync.sh [--user <email>] [--dry-run]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_log()  { echo "[entitlement-sync] $*"; }
_warn() { echo "[entitlement-sync] WARN: $*" >&2; }

DRY_RUN="${DRY_RUN:-0}"
USER_EMAIL="${USER_EMAIL:-${WORKSPACE_USER:-}}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
GSM_PROJECT="${GSM_PROJECT:-gcp-eiq}"

# ── Entitlement mapping (repo/team → credentials) ─────────────────────────────
# Pattern: "repo_pattern" → space-separated GSM secret names to provision
declare -A ENTITLEMENT_MAP
ENTITLEMENT_MAP["kushin77/code-server"]="github-token"
ENTITLEMENT_MAP["kushin77/*"]="github-token"

# ── Detect GitHub access ──────────────────────────────────────────────────────
detect_github_teams() {
  local user="${1:-}"
  if [[ -z "$GH_TOKEN" ]]; then
    _warn "GH_TOKEN not set — cannot detect GitHub team membership"
    return 1
  fi

  if command -v gh >/dev/null 2>&1; then
    gh api /user/teams --paginate --jq '.[].full_name' 2>/dev/null || echo ""
  else
    curl -sf -H "Authorization: Bearer $GH_TOKEN" \
      "https://api.github.com/user/teams?per_page=100" 2>/dev/null | \
      python3 -c "import sys,json; [print(t['organization']['login']+'/'+t['slug']) for t in json.load(sys.stdin)]" \
      2>/dev/null || echo ""
  fi
}

detect_github_repos() {
  if command -v gh >/dev/null 2>&1; then
    gh repo list --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null | head -50 || echo ""
  else
    curl -sf -H "Authorization: Bearer $GH_TOKEN" \
      "https://api.github.com/user/repos?per_page=50" 2>/dev/null | \
      python3 -c "import sys,json; [print(r['full_name']) for r in json.load(sys.stdin)]" \
      2>/dev/null || echo ""
  fi
}

# ── Provision credential from GSM ─────────────────────────────────────────────
provision_secret() {
  local secret_name="$1"
  _log "provisioning: $secret_name (project=$GSM_PROJECT)"

  if [[ "$DRY_RUN" == "1" ]]; then
    _log "DRY_RUN: would provision $secret_name"
    return 0
  fi

  if ! command -v gcloud >/dev/null 2>&1; then
    _warn "gcloud not available — cannot provision $secret_name"
    return 1
  fi

  local value
  value=$(CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud --quiet secrets versions access latest \
    --secret="$secret_name" --project="$GSM_PROJECT" 2>/dev/null || echo "")

  if [[ -n "$value" ]]; then
    # Export into session env
    local env_var
    env_var=$(echo "$secret_name" | tr '[:lower:]-' '[:upper:]_')
    export "${env_var}=${value}"
    _log "provisioned: $env_var"
    return 0
  else
    _warn "secret not found or access denied: $secret_name"
    return 1
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  _log "starting entitlement sync (user=${USER_EMAIL:-unknown}, dry_run=$DRY_RUN)"

  local provisioned=0 skipped=0

  # Get accessible repos
  local repos
  repos=$(detect_github_repos 2>/dev/null || echo "")

  for entry in "${!ENTITLEMENT_MAP[@]}"; do
    local pattern="$entry"
    local secrets="${ENTITLEMENT_MAP[$entry]}"

    # Check if any accessible repo matches this pattern
    local matches=false
    while IFS= read -r repo; do
      # Use glob-style match
      if [[ "$repo" == $pattern ]]; then
        matches=true
        break
      fi
    done <<< "$repos"

    # Always provision for current repo if pattern matches
    local current_repo="${GITHUB_REPOSITORY:-kushin77/code-server}"
    if [[ "$current_repo" == $pattern ]]; then
      matches=true
    fi

    if [[ "$matches" == "true" ]]; then
      for secret in $secrets; do
        provision_secret "$secret" && provisioned=$(( provisioned + 1 )) || skipped=$(( skipped + 1 ))
      done
    fi
  done

  _log "entitlement sync complete: provisioned=$provisioned, skipped=$skipped"
}

# Parse args
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --user) shift; USER_EMAIL="${1:-}" ;;
  esac
done

main
