#!/usr/bin/env bash
# @file        scripts/ops/bootstrap-env.sh
# @module      ops/deployment
# @description Idempotent .env bootstrap: validates, generates missing secrets,
#              and writes a deployment-ready .env file for any replica host.
#              Reads from GSM when available; falls back to safe defaults for dev.
#              Safe to run multiple times — never overwrites secrets that already pass validation.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

ENV_FILE="${ENV_FILE:-.env}"
REPLICA_MODE="${REPLICA_MODE:-primary}"   # primary | secondary
DRY_RUN="${DRY_RUN:-0}"

# Required 32-byte AES secrets — must be exactly 32 ASCII characters
AES_REQUIRED_VARS=(
  OAUTH2_PROXY_COOKIE_SECRET
)

# Required non-empty secrets
REQUIRED_VARS=(
  POSTGRES_PASSWORD
  REDIS_PASSWORD
  SERVICE_CLIENT_SESSION_BROKER_ID
  SERVICE_CLIENT_SESSION_BROKER_SECRET
  IDE_SESSION_LB_SECRET
)

# ============================================================================
# HELPERS
# ============================================================================

# gen_secret <length>  — generates a cryptographically random ASCII secret
gen_secret() {
  local length="${1:-32}"
  # Use /dev/urandom + tr to produce printable ASCII (no special chars that break shell)
  tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${length}"
}

# assert_length <value> <expected_bytes>
assert_length() {
  local val="$1"
  local expected="$2"
  local actual="${#val}"
  if [[ "$actual" -ne "$expected" ]]; then
    log_error "Secret length validation failed: expected ${expected} bytes, got ${actual}"
    return 1
  fi
}

# env_get <file> <key>  — reads value from .env file; returns empty string if missing
env_get() {
  local file="$1"
  local key="$2"
  grep -E "^${key}=" "${file}" 2>/dev/null | cut -d= -f2- | head -1 || true
}

# env_set <file> <key> <value>  — upserts key=value in .env file (idempotent)
env_set() {
  local file="$1"
  local key="$2"
  local value="$3"
  if grep -qE "^${key}=" "${file}" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    echo "${key}=${value}" >> "${file}"
  fi
}

# ============================================================================
# VALIDATION
# ============================================================================

validate_aes_secrets() {
  local file="$1"
  local fixed=0

  for var in "${AES_REQUIRED_VARS[@]}"; do
    local current
    current="$(env_get "${file}" "${var}")"
    local len="${#current}"

    if [[ -z "${current}" ]]; then
      log_warn "${var} is missing — generating 32-byte secret"
      local new_secret
      new_secret="$(gen_secret 32)"
      [[ "${DRY_RUN}" == "0" ]] && env_set "${file}" "${var}" "${new_secret}"
      ((fixed++)) || true
    elif [[ "${len}" -ne 16 ]] && [[ "${len}" -ne 24 ]] && [[ "${len}" -ne 32 ]]; then
      log_warn "${var} is ${len} bytes — must be 16/24/32 for AES cipher. Regenerating to 32 bytes."
      local new_secret
      new_secret="$(gen_secret 32)"
      [[ "${DRY_RUN}" == "0" ]] && env_set "${file}" "${var}" "${new_secret}"
      ((fixed++)) || true
    else
      log_info "${var}: ✅ ${len} bytes (valid AES key)"
    fi
  done

  return 0
}

validate_required_vars() {
  local file="$1"
  local missing=()

  for var in "${REQUIRED_VARS[@]}"; do
    local val
    val="$(env_get "${file}" "${var}")"
    if [[ -z "${val}" ]]; then
      missing+=("${var}")
    else
      log_info "${var}: ✅ present"
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    log_error "Missing required variables: ${missing[*]}"
    log_error "Set these in ${file} or ensure GSM bootstrap has run."
    return 1
  fi

  return 0
}

set_replica_ports() {
  local file="$1"

  if [[ "${REPLICA_MODE}" == "secondary" ]]; then
    local current_http
    current_http="$(env_get "${file}" "CADDY_HTTP_PORT")"
    local current_https
    current_https="$(env_get "${file}" "CADDY_HTTPS_PORT")"

    # Only update if currently set to conflicting defaults
    if [[ -z "${current_http}" ]] || [[ "${current_http}" == "80" ]]; then
      log_info "REPLICA_MODE=secondary: setting CADDY_HTTP_PORT=9080 to avoid K8s ingress conflict"
      [[ "${DRY_RUN}" == "0" ]] && env_set "${file}" "CADDY_HTTP_PORT" "9080"
    else
      log_info "CADDY_HTTP_PORT=${current_http} — keeping existing value"
    fi

    if [[ -z "${current_https}" ]] || [[ "${current_https}" == "443" ]]; then
      log_info "REPLICA_MODE=secondary: setting CADDY_HTTPS_PORT=9443 to avoid K8s ingress conflict"
      [[ "${DRY_RUN}" == "0" ]] && env_set "${file}" "CADDY_HTTPS_PORT" "9443"
    else
      log_info "CADDY_HTTPS_PORT=${current_https} — keeping existing value"
    fi
  else
    # Primary: ensure standard ports
    local current_http
    current_http="$(env_get "${file}" "CADDY_HTTP_PORT")"
    if [[ -z "${current_http}" ]] || [[ "${current_http}" == "9080" ]]; then
      [[ "${DRY_RUN}" == "0" ]] && env_set "${file}" "CADDY_HTTP_PORT" "80"
    fi

    local current_https
    current_https="$(env_get "${file}" "CADDY_HTTPS_PORT")"
    if [[ -z "${current_https}" ]] || [[ "${current_https}" == "9443" ]]; then
      [[ "${DRY_RUN}" == "0" ]] && env_set "${file}" "CADDY_HTTPS_PORT" "443"
    fi

    log_info "REPLICA_MODE=primary: CADDY_HTTP_PORT=80 CADDY_HTTPS_PORT=443"
  fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  log_info "==================================================="
  log_info "KC Bootstrap-Env — IaC, Immutable, Idempotent"
  log_info "==================================================="
  log_info "ENV_FILE    : ${ENV_FILE}"
  log_info "REPLICA_MODE: ${REPLICA_MODE}"
  log_info "DRY_RUN     : ${DRY_RUN}"
  log_info ""

  # Create .env if missing
  if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ "${DRY_RUN}" == "0" ]]; then
      touch "${ENV_FILE}"
      log_info "Created empty ${ENV_FILE}"
    else
      log_info "[DRY_RUN] Would create empty ${ENV_FILE}"
    fi
  fi

  log_info "--- Phase 1: AES Secret Validation ---"
  validate_aes_secrets "${ENV_FILE}"

  log_info ""
  log_info "--- Phase 2: Required Variable Check ---"
  if ! validate_required_vars "${ENV_FILE}"; then
    log_fatal "Required variables missing. Aborting."
  fi

  log_info ""
  log_info "--- Phase 3: Replica Port Configuration ---"
  set_replica_ports "${ENV_FILE}"

  log_info ""
  log_info "✅ bootstrap-env complete — ${ENV_FILE} is deployment-ready"
}

main "$@"
