#!/usr/bin/env bash
# @file scripts/ops/rotate-secrets.sh
# @description Rotate all application credentials stored in Vault without downtime.
#              Re-issues: DB passwords, Redis auth, JWT signing key, API tokens.
# @usage rotate-secrets.sh [--service <name>|--all] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
SERVICE="--all"
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
ROTATION_LOG="${REPO_ROOT}/artifacts/secret-rotation-$(date +%s).log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --service)  SERVICE="$2"; shift 2 ;;
    --all)      SERVICE="--all"; shift ;;
    *)          shift ;;
  esac
done

mkdir -p "${REPO_ROOT}/artifacts"

vault_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] vault $*"
    return 0
  fi
  VAULT_ADDR="${VAULT_ADDR}" vault "$@"
}

generate_secret() {
  # 32-byte URL-safe random string
  head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '='
}

rotate_postgres() {
  log_info "Rotating PostgreSQL credentials..."
  local new_pass
  new_pass=$(generate_secret)

  # Update in Vault
  vault_cmd kv put secret/code-server/postgres \
    password="${new_pass}" \
    username="code_server" \
    host="${PRIMARY_HOST:-192.168.168.31}" \
    port="5432" \
    database="code_server"

  # Update in running PostgreSQL
  if [[ "${DRY_RUN}" != "true" ]]; then
    docker exec code-server-postgres psql -U postgres \
      -c "ALTER USER code_server PASSWORD '${new_pass}';"
    log_info "  ✅ PostgreSQL password rotated"
  fi

  # Reload services that use the DB
  log_info "  Reloading DB-dependent services..."
  for svc in code-server-api code-server-worker; do
    if [[ "${DRY_RUN}" != "true" ]]; then
      docker kill --signal=SIGHUP "${svc}" 2>/dev/null || \
        docker restart "${svc}" 2>/dev/null || true
    else
      log_info "[DRY-RUN] would reload ${svc}"
    fi
  done
}

rotate_redis() {
  log_info "Rotating Redis auth token..."
  local new_pass
  new_pass=$(generate_secret)

  vault_cmd kv put secret/code-server/redis \
    password="${new_pass}" \
    host="${PRIMARY_HOST:-192.168.168.31}" \
    port="6379"

  if [[ "${DRY_RUN}" != "true" ]]; then
    docker exec code-server-redis redis-cli CONFIG SET requirepass "${new_pass}"
    log_info "  ✅ Redis auth token rotated"
  fi
}

rotate_jwt() {
  log_info "Rotating JWT signing key..."
  local new_key
  new_key=$(generate_secret)

  vault_cmd kv put secret/code-server/jwt \
    signing_key="${new_key}" \
    algorithm="HS256"

  if [[ "${DRY_RUN}" != "true" ]]; then
    # Restart auth service to pick up new key (existing sessions will re-auth)
    docker restart code-server-oauth2-proxy 2>/dev/null || true
    log_info "  ✅ JWT signing key rotated (active sessions will re-authenticate)"
  fi
}

rotate_api_tokens() {
  log_info "Rotating internal API tokens..."
  local new_token
  new_token=$(generate_secret)

  vault_cmd kv put secret/code-server/api \
    internal_token="${new_token}" \
    issued_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  log_info "  ✅ API tokens rotated"
}

verify_rotation() {
  log_info "Verifying rotation: Vault secrets are readable..."
  for path in postgres redis jwt api; do
    if [[ "${DRY_RUN}" != "true" ]]; then
      VAULT_ADDR="${VAULT_ADDR}" vault kv get "secret/code-server/${path}" >/dev/null 2>&1 && \
        log_info "  ✅ secret/code-server/${path} readable" || \
        log_error "  ❌ secret/code-server/${path} unreadable after rotation"
    else
      log_info "[DRY-RUN] would verify secret/code-server/${path}"
    fi
  done
}

# Main
log_info "Secret Rotation — service=${SERVICE} dry-run=${DRY_RUN}" | tee -a "${ROTATION_LOG}"
log_info "======================================================"

if [[ "${SERVICE}" == "--all" ]]; then
  rotate_postgres
  rotate_redis
  rotate_jwt
  rotate_api_tokens
  verify_rotation
else
  case "${SERVICE}" in
    postgres)   rotate_postgres ;;
    redis)      rotate_redis ;;
    jwt)        rotate_jwt ;;
    api)        rotate_api_tokens ;;
    *)          log_error "Unknown service: ${SERVICE}"; exit 1 ;;
  esac
fi

log_info "======================================================"
log_info "Secret rotation complete — log: ${ROTATION_LOG}"
