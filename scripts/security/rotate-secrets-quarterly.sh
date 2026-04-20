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

missing=0
for secret_ref in "${required_secret_refs[@]}"; do
  if [[ -z "${!secret_ref:-}" ]]; then
    log_warn "Missing expected secret reference env var: $secret_ref"
    missing=$((missing + 1))
  fi
done

if [[ "$MODE" == "execute" && "$missing" -gt 0 ]]; then
  log_fatal "Cannot execute rotation with missing secret references"
fi

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$REPORT_FILE" <<EOF
{
  "timestamp_utc": "$timestamp",
  "mode": "$MODE",
  "missing_reference_count": $missing,
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
