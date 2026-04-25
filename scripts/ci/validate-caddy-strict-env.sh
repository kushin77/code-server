#!/bin/bash
# @file scripts/ci/validate-caddy-strict-env.sh
# @module infrastructure/validation
# @description Enforce strict Caddy environment-variable usage (no fallback defaults)
# @governance GOV-002: Immutable, version-controlled, idempotent infrastructure
# @usage validate-caddy-strict-env.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly REPORT_FILE="${REPORT_FILE:-${REPO_ROOT}/artifacts/caddy-strict-env-report.txt}"

mkdir -p "$(dirname "${REPORT_FILE}")"

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_success() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"
}

main() {
  log_info "Validating Caddy strict environment variable usage"

  local targets=()
  local candidates=(
    "${REPO_ROOT}/Caddyfile"
    "${REPO_ROOT}/config/caddy/Caddyfile"
    "${REPO_ROOT}/config/caddy/Caddyfile.tpl"
    "${REPO_ROOT}/config/caddy/Caddyfile.http-prod"
    "${REPO_ROOT}/config/caddy/Caddyfile.example"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      targets+=("${candidate}")
    fi
  done

  if [[ ${#targets[@]} -eq 0 ]]; then
    log_info "No Caddy configuration files found in this snapshot"
    {
      echo "status=SKIPPED"
      echo "reason=No Caddy files found"
    } > "${REPORT_FILE}"
    return 0
  fi

  local fallback_matches
  fallback_matches="$(grep -RInE "\{\$[A-Za-z_][A-Za-z0-9_]*:[^}]+\}" "${targets[@]}" 2>/dev/null || true)"

  if [[ -n "${fallback_matches}" ]]; then
    log_error "Found fallback syntax in Caddy config ({$VAR:default})"
    echo "${fallback_matches}" >&2
    {
      echo "status=FAIL"
      echo "reason=Fallback syntax detected"
      echo "matches_start"
      echo "${fallback_matches}"
      echo "matches_end"
    } > "${REPORT_FILE}"
    return 1
  fi

  {
    echo "status=PASS"
    echo "reason=No fallback syntax detected"
    echo "files_checked=${#targets[@]}"
  } > "${REPORT_FILE}"

  log_success "Caddy strict env validation passed"
}

main "$@"
