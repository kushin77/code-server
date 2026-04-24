#!/usr/bin/env bash
# @file        scripts/security/rotate-secrets-quarterly.sh
# @module      security/rotation
# @description Validate and execute quarterly secret rotation workflow for GSM and Vault managed secrets
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

MODE="dry-run"
REPORT_DIR="${REPORT_DIR:-artifacts/security}"
REPORT_FILE="${REPORT_FILE:-$REPORT_DIR/secrets-rotation-report.json}"
GSM_BOOTSTRAP="$SCRIPT_DIR/../fetch-gsm-secrets.sh"
ENV_SCHEMA_FILE="${ENV_SCHEMA_FILE:-.env.schema.json}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/security/rotate-secrets-quarterly.sh --dry-run
  bash scripts/security/rotate-secrets-quarterly.sh --execute
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --execute) MODE="execute" ;;
    -h|--help) usage; exit 0 ;;
    *) log_fatal "Unknown argument: $arg" ;;
  esac
done

if [[ -f "$GSM_BOOTSTRAP" ]]; then
  # shellcheck source=/dev/null
  if ! source "$GSM_BOOTSTRAP" --non-interactive; then
    log_warn "GSM bootstrap was unavailable; continuing with existing secret references"
  fi
fi

export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-${VAULT_CLOUDFLARE_API_TOKEN:-}}"

mkdir -p "$REPORT_DIR"

required_secret_refs=(
  "GOOGLE_CLIENT_SECRET"
  "OAUTH2_PROXY_COOKIE_SECRET"
  "CODE_SERVER_PASSWORD"
  "POSTGRES_PASSWORD"
  "REDIS_PASSWORD"
  "CLOUDFLARE_API_TOKEN"
  "GITHUB_TOKEN"
)

has_schema_vault_path() {
  local secret_ref="$1"

  if [[ ! -f "$ENV_SCHEMA_FILE" ]]; then
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -e --arg ref "$secret_ref" '
      (.groups // .sections // {})
      | to_entries[]
      | .value.variables[$ref]? // empty
      | select(.secret == true and (.vault_path // "") != "")
    ' "$ENV_SCHEMA_FILE" >/dev/null 2>&1
    return $?
  fi

  if command -v python3 >/dev/null 2>&1; then
    ENV_SCHEMA_FILE="$ENV_SCHEMA_FILE" SECRET_REF="$secret_ref" python3 - <<'PY' >/dev/null 2>&1
import json
import os
from pathlib import Path

schema = json.loads(Path(os.environ["ENV_SCHEMA_FILE"]).read_text(encoding="utf-8"))
secret_ref = os.environ["SECRET_REF"]

found = False
groups = schema.get("groups") or schema.get("sections") or {}
for section in groups.values():
    variables = section.get("variables") or {}
    candidate = variables.get(secret_ref)
    if not isinstance(candidate, dict):
        continue
    if candidate.get("secret") and candidate.get("vault_path"):
        found = True
        break

raise SystemExit(0 if found else 1)
PY
    return $?
  fi

  return 1
}

missing=0
env_backed=0
schema_backed=0
declare -a missing_refs=()

for secret_ref in "${required_secret_refs[@]}"; do
  if [[ -n "${!secret_ref:-}" ]]; then
    env_backed=$((env_backed + 1))
    continue
  fi

  if has_schema_vault_path "$secret_ref"; then
    schema_backed=$((schema_backed + 1))
    continue
  fi

  log_warn "Missing secret reference in env and schema vault mapping: $secret_ref"
  missing=$((missing + 1))
  missing_refs+=("$secret_ref")
done

if [[ "$MODE" == "execute" && "$missing" -gt 0 ]]; then
  log_fatal "Cannot execute rotation with missing secret references"
fi

if [[ "$MODE" == "execute" ]]; then
  missing_env_values=0
  for secret_ref in "${required_secret_refs[@]}"; do
    if [[ -z "${!secret_ref:-}" ]]; then
      log_warn "Execute mode requires loaded secret value: $secret_ref"
      missing_env_values=$((missing_env_values + 1))
    fi
  done
  if [[ "$missing_env_values" -gt 0 ]]; then
    log_fatal "Cannot execute rotation with missing loaded secret values"
  fi
fi

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$REPORT_FILE" <<EOF
{
  "timestamp_utc": "$timestamp",
  "mode": "$MODE",
  "missing_reference_count": $missing,
  "reference_sources": {
    "env_backed": $env_backed,
    "schema_backed": $schema_backed
  },
  "missing_references": [
$(for ref in "${missing_refs[@]}"; do printf '    "%s",\n' "$ref"; done | sed '$ s/,$//')
  ],
  "required_secret_references": [
    "GOOGLE_CLIENT_SECRET",
    "OAUTH2_PROXY_COOKIE_SECRET",
    "CODE_SERVER_PASSWORD",
    "POSTGRES_PASSWORD",
    "REDIS_PASSWORD",
    "CLOUDFLARE_API_TOKEN",
    "GITHUB_TOKEN"
  ],
  "status": "$( [[ "$missing" -eq 0 ]] && echo ready || echo incomplete )"
}
EOF

if [[ "$MODE" == "dry-run" ]]; then
  log_info "Dry-run rotation validation complete. Report: $REPORT_FILE"
  exit 0
fi

log_info "Execution mode selected. Perform provider-specific secret rotation using GSM/Vault automation and attach this report to issue evidence."
log_info "Rotation report written: $REPORT_FILE"
