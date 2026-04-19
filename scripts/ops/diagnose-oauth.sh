#!/usr/bin/env bash
# @file        scripts/ops/diagnose-oauth.sh
# @module      ops/auth
# @description Diagnose oauth2-proxy access issues: check allowed-emails, env config, and account eligibility.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" 2>/dev/null || true

log_info() { echo "[oauth:diag] $*"; }
log_warn() { echo "[oauth:warn] $*" >&2; }
log_error() { echo "[oauth:error] $*" >&2; }

ALLOWED_EMAILS_FILE="${ALLOWED_EMAILS_FILE:-/etc/oauth2-proxy/allowed-emails.txt}"
LOCAL_EMAILS_FILE="${LOCAL_EMAILS_FILE:-$(dirname "$SCRIPT_DIR")/../allowed-emails.txt}"

usage() {
  echo "Usage: $0 [--email <email>] [--list] [--add <email>]"
  echo "  --list         List all currently allowed emails"
  echo "  --check <email> Check if <email> is in the allowed list"
  echo "  --add <email>  Add <email> to the allowed-emails.txt file (requires write access)"
  exit 0
}

cmd_list() {
  local file="${1:-$LOCAL_EMAILS_FILE}"
  if [[ ! -f "$file" ]]; then
    log_error "allowed-emails file not found: $file"
    exit 2
  fi
  log_info "Allowed emails (from $file):"
  grep -v '^#' "$file" | grep -v '^$' | while read -r email; do
    echo "  - $email"
  done
}

cmd_check() {
  local email="$1"
  local file="${2:-$LOCAL_EMAILS_FILE}"
  if [[ ! -f "$file" ]]; then
    log_error "allowed-emails file not found: $file"
    exit 2
  fi
  if grep -qiFx "$email" "$file"; then
    log_info "ALLOWED: $email is in the access list"
    return 0
  else
    log_warn "DENIED:  $email is NOT in the access list at $file"
    log_warn "To add: echo '$email' >> $file"
    return 1
  fi
}

cmd_add() {
  local email="$1"
  local file="${2:-$LOCAL_EMAILS_FILE}"
  if grep -qiFx "$email" "$file" 2>/dev/null; then
    log_info "$email already present in $file"
    return 0
  fi
  echo "$email" >> "$file"
  log_info "Added $email to $file"
  log_warn "Restart oauth2-proxy container to apply: docker compose restart oauth2-proxy"
}

cmd_env() {
  log_info "=== OAuth environment check ==="
  local vars=(OAUTH2_PROXY_CLIENT_ID OAUTH2_PROXY_CLIENT_SECRET OAUTH2_PROXY_COOKIE_SECRET OAUTH2_PROXY_PROVIDER OAUTH2_PROXY_EMAIL_DOMAINS)
  for var in "${vars[@]}"; do
    if [[ -n "${!var:-}" ]]; then
      if [[ "$var" == *SECRET* ]]; then
        log_info "  $var = [set]"
      else
        log_info "  $var = ${!var}"
      fi
    else
      log_warn "  $var = [NOT SET]"
    fi
  done
}

# ── Main ──────────────────────────────────────────────────────────────────────
case "${1:-help}" in
  --list|-l)      cmd_list; cmd_env ;;
  --check|-c)     cmd_check "${2:?'--check requires an email argument'}" ;;
  --add|-a)       cmd_add "${2:?'--add requires an email argument'}" ;;
  --env|-e)       cmd_env ;;
  help|--help|-h) usage ;;
  *) log_error "Unknown command: ${1:-}"; usage ;;
esac
