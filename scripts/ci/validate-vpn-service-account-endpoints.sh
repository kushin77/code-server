#!/usr/bin/env bash
# @file        scripts/ci/validate-vpn-service-account-endpoints.sh
# @module      ci/e2e
# @description Validate IDE/portal auth endpoints over VPN using QA service-account OAuth token.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

MODE="${MODE:-ssh}"
HOSTS="${HOSTS:-192.168.168.31,192.168.168.42}"
REMOTE_REPO_DIR="${REMOTE_REPO_DIR:-~/code-server-enterprise}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ci/validate-vpn-service-account-endpoints.sh [--mode ssh|local]

Modes:
  ssh   (default) validates from each host in HOSTS by sourcing remote .env
  local validates from current machine using local E2E_OAUTH_TOKEN env var

Environment:
  MODE             Validation mode (ssh|local), default: ssh
  HOSTS            Comma-separated hosts for ssh mode, default: 192.168.168.31,192.168.168.42
  REMOTE_REPO_DIR  Repo path on remote hosts, default: ~/code-server-enterprise
  E2E_OAUTH_TOKEN  Required only for local mode
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

validate_with_token() {
  local host_label="$1"
  local auth_header="$2"

  log_info "[$host_label] Checking IDE oauth2 auth endpoint"
  local ide_status
  ide_status="$(curl -ksS -o /dev/null -w '%{http_code}' -H "$auth_header" 'https://ide.kushnir.cloud/oauth2/auth')"

  log_info "[$host_label] Checking portal oauth2 auth endpoint"
  local portal_status
  portal_status="$(curl -ksS -o /dev/null -w '%{http_code}' -H "$auth_header" 'https://kushnir.cloud/oauth2/auth')"

  if [[ "$ide_status" != "202" ]]; then
    log_error "[$host_label] ide oauth2/auth returned $ide_status (expected 202)"
    return 1
  fi

  if [[ "$portal_status" != "202" ]]; then
    log_error "[$host_label] portal oauth2/auth returned $portal_status (expected 202)"
    return 1
  fi

  log_info "[$host_label] PASS: ide=$ide_status portal=$portal_status"
}

validate_remote_host() {
  local host="$1"
  log_info "[$host] Running remote VPN validation"

  ssh "akushnir@$host" "set -euo pipefail; cd $REMOTE_REPO_DIR; set -a; source .env; set +a; AUTH_HEADER=\"Authorization: Bearer \$E2E_OAUTH_TOKEN\"; IDE_STATUS=\"\$(curl -ksS -o /dev/null -w '%{http_code}' -H \"\$AUTH_HEADER\" 'https://ide.kushnir.cloud/oauth2/auth')\"; PORTAL_STATUS=\"\$(curl -ksS -o /dev/null -w '%{http_code}' -H \"\$AUTH_HEADER\" 'https://kushnir.cloud/oauth2/auth')\"; echo \"IDE_STATUS=\$IDE_STATUS PORTAL_STATUS=\$PORTAL_STATUS\"" | {
    read -r line
    log_info "[$host] $line"
    local ide_status portal_status
    ide_status="$(echo "$line" | sed -n 's/.*IDE_STATUS=\([0-9]*\).*/\1/p')"
    portal_status="$(echo "$line" | sed -n 's/.*PORTAL_STATUS=\([0-9]*\).*/\1/p')"

    if [[ "$ide_status" != "202" || "$portal_status" != "202" ]]; then
      log_error "[$host] FAIL: ide=$ide_status portal=$portal_status (expected 202/202)"
      return 1
    fi

    log_info "[$host] PASS: ide=$ide_status portal=$portal_status"
  }
}

if [[ "$MODE" == "local" ]]; then
  if [[ -z "${E2E_OAUTH_TOKEN:-}" ]]; then
    log_fatal "E2E_OAUTH_TOKEN is required for local mode"
  fi
  validate_with_token "local" "Authorization: Bearer $E2E_OAUTH_TOKEN"
  log_info "Validation completed (mode=local)"
  exit 0
fi

if [[ "$MODE" != "ssh" ]]; then
  log_fatal "Unsupported MODE='$MODE' (use ssh or local)"
fi

IFS=',' read -r -a host_array <<< "$HOSTS"
for host in "${host_array[@]}"; do
  validate_remote_host "$host"
done

log_info "Validation completed (mode=ssh)"
