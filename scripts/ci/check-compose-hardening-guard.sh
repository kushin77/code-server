#!/usr/bin/env bash
# @file        scripts/ci/check-compose-hardening-guard.sh
# @module      ci/security
# @description enforce secure compose baseline invariants for on-prem code-server redeploy
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

has_failure=0

check_absent() {
  local file_path="$1"
  local pattern="$2"
  local description="$3"
  local matches

  matches="$(grep -nE -- "$pattern" "$file_path" || true)"
  if [[ -n "$matches" ]]; then
    log_error "FAIL: ${description} found in ${file_path}"
    echo "$matches"
    has_failure=1
  else
    log_info "PASS: ${description} absent in ${file_path}"
  fi
}

check_present() {
  local file_path="$1"
  local pattern="$2"
  local description="$3"

  if grep -qE -- "$pattern" "$file_path"; then
    log_info "PASS: ${description} present in ${file_path}"
  else
    log_error "FAIL: ${description} missing in ${file_path}"
    has_failure=1
  fi
}

BASE_COMPOSE="docker-compose.yml"
TEMPLATE_COMPOSE="docker-compose.tpl"

check_absent "$BASE_COMPOSE" 'NODE_TLS_REJECT_UNAUTHORIZED=0' 'TLS verification bypass'
check_absent "$BASE_COMPOSE" '/var/run/docker.sock:/var/run/docker.sock' 'docker socket host mount in baseline compose'
check_absent "$BASE_COMPOSE" 'CODE_SERVER_PASSWORD:-' 'weak fallback password syntax'
check_present "$BASE_COMPOSE" 'CODE_SERVER_PASSWORD:\?CODE_SERVER_PASSWORD must be set' 'required CODE_SERVER_PASSWORD guard'

check_absent "$TEMPLATE_COMPOSE" '--auth=none' 'unauthenticated code-server mode in template'
check_absent "$TEMPLATE_COMPOSE" 'CODE_SERVER_PASSWORD:-' 'weak fallback password syntax in template'
check_present "$TEMPLATE_COMPOSE" 'CODE_SERVER_PASSWORD:\?CODE_SERVER_PASSWORD must be set' 'required CODE_SERVER_PASSWORD guard in template'

# ── NAS-backed volume invariants ──────────────────────────────────────────────
# Ensure key stateful volumes use NFS and the workspace is not a host bind-mount
check_present "$BASE_COMPOSE" 'NAS_HOST.*192\.168\.168\.56|addr=.*192\.168\.168\.56' 'NAS host .56 referenced in volume driver_opts'
check_present "$BASE_COMPOSE" 'type: nfs' 'NFS volume type declared'
check_absent "$BASE_COMPOSE" '^\s*- \./workspace:' 'host-local workspace bind-mount (must use NFS volume)'

check_present "$TEMPLATE_COMPOSE" 'type: nfs' 'NFS volume type in template'

# ── Legacy compose stub invariants ───────────────────────────────────────────
# These files must be retired stubs (comment-only) — not active compose configs
LEGACY_SCRIPTS_COMPOSE="scripts/docker-compose.yml"
LEGACY_DOCKER_COMPOSE="docker/docker-compose.yml"

for legacy_file in "$LEGACY_SCRIPTS_COMPOSE" "$LEGACY_DOCKER_COMPOSE"; do
  if [[ -f "$legacy_file" ]]; then
    check_absent "$legacy_file" '^[^#].*image:|^[^#].*services:' "active service definitions in retired legacy file ${legacy_file}"
  fi
done

if [[ "$has_failure" -ne 0 ]]; then
  log_fatal "Compose hardening guard failed"
fi

log_info "Compose hardening guard passed"
