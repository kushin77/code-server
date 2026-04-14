#!/usr/bin/env bash
# Verifies key-only SSH access to external deployment hosts.
# Usage:
#   ./scripts/verify-passwordless-access.sh
#   INCLUDE_STANDBY=1 ./scripts/verify-passwordless-access.sh
#   EXTRA_EXTERNAL_SERVERS="user@10.0.0.5,user@10.0.0.6" ./scripts/verify-passwordless-access.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

parse_csv_targets() {
  local csv="${1:-}"
  local arr=()
  if [[ -n "$csv" ]]; then
    IFS=',' read -r -a arr <<< "$csv"
  fi
  printf '%s\n' "${arr[@]}"
}

main() {
  log_section "Passwordless SSH Verification"
  log_info "Default deploy host: ${DEPLOY_USER}@${DEPLOY_HOST}"
  log_info "Standby host (optional): ${STANDBY_USER}@${STANDBY_HOST}"
  log_info "NAS host: ${NAS_USER}@${NAS_HOST}"

  local targets=(
    "${DEPLOY_USER}@${DEPLOY_HOST}"
    "${NAS_USER}@${NAS_HOST}"
  )

  if [[ "${INCLUDE_STANDBY:-0}" == "1" ]]; then
    targets+=("${STANDBY_USER}@${STANDBY_HOST}")
  fi

  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$target")
  done < <(parse_csv_targets "${EXTRA_EXTERNAL_SERVERS:-}")

  verify_passwordless_ssh "${targets[@]}"

  log_success "All configured external servers are reachable via key-only SSH"
}

main "$@"
