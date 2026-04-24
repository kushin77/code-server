#!/usr/bin/env bash
# @file        scripts/validate-config-ssot.sh
# @module      operations/validation
# @description Validate configuration SSOT — catch conflicts before deployment
# @owner       platform
# @status      active
#
# Purpose:  Ensure all configuration items come from their designated SSOT source
#           Prevents configuration conflicts and deployment failures
#
# Usage:    ./scripts/validate-config-ssot.sh [--fix]
#           ./scripts/validate-config-ssot.sh --check-only

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
# Initialization
# ════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

FIX_MODE=false
EXIT_CODE=0

EXPECTED_POSTGRES_DB="${EXPECTED_POSTGRES_DB:-code_server}"
EXPECTED_POSTGRES_USER="${EXPECTED_POSTGRES_USER:-code_server}"
EXPECTED_NAS_HOST="${EXPECTED_NAS_HOST:-$NAS_HOST}"
EXPECTED_NAS_MOUNT_POINT="${EXPECTED_NAS_MOUNT_POINT:-$NAS_MOUNT_POINT}"
EXPECTED_NAS_EXPORT_PATH="${EXPECTED_NAS_EXPORT_PATH:-$NAS_EXPORT_PATH}"
EXPECTED_NFS_VERSION="${EXPECTED_NFS_VERSION:-$NFS_VERSION}"
EXPECTED_DEPLOY_HOST="${EXPECTED_DEPLOY_HOST:-primary.prod.internal}"
EXPECTED_STANDBY_HOST="${EXPECTED_STANDBY_HOST:-replica.prod.internal}"

[[ "${1:-}" == "--fix" ]] && FIX_MODE=true
# shellcheck disable=SC2034
[[ "${1:-}" == "--check-only" ]] && FIX_MODE=false

# ════════════════════════════════════════════════════════════════════════════
# Configuration SSOT Validation Rules
# Format: check_config_conflict "ITEM_NAME" "SOURCE_1:VALUE_1" "SOURCE_2:VALUE_2" ["SOURCE_3:VALUE_3"]
# ════════════════════════════════════════════════════════════════════════════

check_config_conflict() {
  local item_name="$1"
  shift
  local sources=("$@")
  local values=()
  local sources_str=""
  
  # Extract values from sources
  for source in "${sources[@]}"; do
    local source_name="${source%%:*}"
    local expected_value="${source#*:}"
    values+=("$expected_value")
    sources_str+="$source_name "
  done
  
  # Check if all values are the same
  local first_value="${values[0]}"
  local conflict_found=false
  
  for i in "${!values[@]}"; do
    if [[ "${values[$i]}" != "$first_value" ]]; then
      conflict_found=true
      break
    fi
  done
  
  if [[ "$conflict_found" == true ]]; then
    log_error "CONFIG CONFLICT: $item_name"
    log_error "  SSOT Sources: $sources_str"
    for source in "${sources[@]}"; do
      log_error "    - $source"
    done
    EXIT_CODE=1
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Load Configuration Files
# ════════════════════════════════════════════════════════════════════════════

load_env_file() {
  local env_file="$1"
  if [[ -f "$env_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ "$line" != *=* ]] && continue

      local key="${line%%=*}"
      local value="${line#*=}"

      key="$(echo "$key" | xargs)"
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"

      if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        if readonly -p 2>/dev/null | grep -q "[[:space:]]$key="; then
          continue
        fi
        export "$key=$value"
      fi
    done < "$env_file"
    log_info "Loaded: $env_file"
  else
    log_warn "Not found: $env_file"
  fi
}

log_info "=== Configuration SSOT Validation ==="

# Load environment files in order of precedence
load_env_file .env.defaults
load_env_file .env.template
load_env_file .env.production
load_env_file .env

# ════════════════════════════════════════════════════════════════════════════
# Validation Checks
# ════════════════════════════════════════════════════════════════════════════

log_info ""
log_info "Validating configuration conflicts..."
log_info ""

# 1. Database Configuration
if [[ "${POSTGRES_DB:-}" != "$EXPECTED_POSTGRES_DB" ]]; then
  log_error "INVALID DATABASE NAME: ${POSTGRES_DB:-<unset>} (expected: $EXPECTED_POSTGRES_DB)"
  EXIT_CODE=1
fi

if [[ "${POSTGRES_USER:-}" != "$EXPECTED_POSTGRES_USER" ]]; then
  log_error "INVALID POSTGRES USER: ${POSTGRES_USER:-<unset>} (expected: $EXPECTED_POSTGRES_USER)"
  EXIT_CODE=1
fi

# 2. NAS Configuration
if [[ "${NAS_HOST:-}" != "$EXPECTED_NAS_HOST" ]]; then
  log_error "NAS_HOST is ${NAS_HOST:-<unset>} (expected: $EXPECTED_NAS_HOST)"
  EXIT_CODE=1
fi

if [[ "${NAS_MOUNT_POINT:-}" != "$EXPECTED_NAS_MOUNT_POINT" ]]; then
  log_error "NAS_MOUNT_POINT is ${NAS_MOUNT_POINT:-<unset>} (expected: $EXPECTED_NAS_MOUNT_POINT)"
  EXIT_CODE=1
fi

if [[ "${NAS_EXPORT_PATH:-}" != "$EXPECTED_NAS_EXPORT_PATH" ]]; then
  log_error "NAS_EXPORT_PATH is ${NAS_EXPORT_PATH:-<unset>} (expected: $EXPECTED_NAS_EXPORT_PATH)"
  EXIT_CODE=1
fi

if [[ "${NFS_VERSION:-}" != "$EXPECTED_NFS_VERSION" ]]; then
  log_error "NFS_VERSION is ${NFS_VERSION:-<unset>} (expected: $EXPECTED_NFS_VERSION)"
  EXIT_CODE=1
fi

# 2b. Host Topology Configuration
if [[ -n "${DEPLOY_HOST:-}" && "${DEPLOY_HOST}" != "$EXPECTED_DEPLOY_HOST" ]]; then
  log_warn "DEPLOY_HOST is ${DEPLOY_HOST} (expected: $EXPECTED_DEPLOY_HOST)"
fi

if [[ -n "${STANDBY_HOST:-}" && "${STANDBY_HOST}" != "$EXPECTED_STANDBY_HOST" ]]; then
  log_warn "STANDBY_HOST is ${STANDBY_HOST} (expected: $EXPECTED_STANDBY_HOST)"
fi

# 3. Image Version Checks
check_ollama_version() {
  local version="${1:-}"
  if [[ "$version" == "latest" ]]; then
    log_error "FORBIDDEN IMAGE TAG: ollama:latest"
    log_error "  Use specific semver instead (e.g., ollama:0.1.27)"
    EXIT_CODE=1
  fi
}

check_ollama_version "${OLLAMA_VERSION:-0.1.27}"

# 4. Domain Configuration (not duplicated)
if grep -q "DOMAIN=" .env; then
  env_domain="$(grep "^DOMAIN=" .env | head -n1 | cut -d= -f2)"
  log_info "✓ DOMAIN configured: $env_domain"
fi

# 5. Hardcoded IP Check
if grep -R -nE "192\.168\.168\.(10|11|12)" scripts --include='*.sh' 2>/dev/null | grep -v "scripts/nas-mount-31.sh" >/dev/null; then
  log_warn "Found hardcoded IPs in scripts (should use env vars)"
fi

# 6. Secret Checks (these should NOT be in tracked .env files)
detect_real_secret_values() {
  local file_path="$1"
  [[ ! -f "$file_path" ]] && return 0

  while IFS= read -r secret_line; do
    local key_name="${secret_line%%=*}"
    local value="${secret_line#*=}"
    value="$(echo "$value" | xargs)"

    # Ignore secret reference metadata keys (identifier names, not secret values)
    if [[ "$key_name" =~ (_SECRET_NAME|_TOKEN_NAME|_KEY_NAME|_PROJECT|_PATH)$ ]]; then
      continue
    fi

    # Allowed placeholder styles and variable references
    if [[ -z "$value" ]] || [[ "$value" =~ ^(REDACTED|YOUR-|CHANGEME|example|placeholder) ]] || [[ "$value" =~ ^\$\{[A-Z0-9_]+\}$ ]]; then
      continue
    fi

    # Allow legacy test defaults only in defaults/template files
    if [[ "$file_path" =~ \.env\.(defaults|template)$ ]] && [[ "$value" =~ ^(postgres|minioadmin|0123456789abcdef0123456789abcdef)$ ]]; then
      continue
    fi

    log_error "SECURITY ISSUE: Possible real secret value in $file_path:$secret_line"
    EXIT_CODE=1
  done < <(grep -nE '^[A-Z0-9_]*(PASSWORD|SECRET|TOKEN|KEY)[A-Z0-9_]*=' "$file_path" 2>/dev/null || true)
}

detect_real_secret_values ".env"
detect_real_secret_values ".env.production"
detect_real_secret_values ".env.defaults"
detect_real_secret_values ".env.template"

# ════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════

log_info ""
if [[ $EXIT_CODE -eq 0 ]]; then
  log_success "✓ Configuration SSOT validation PASSED"
  log_info "  All configuration conflicts resolved"
  log_info "  Ready for deployment"
else
  log_error "✗ Configuration SSOT validation FAILED"
  log_error "  Fix conflicts above before deploying"
  log_error "  Run with --fix to attempt auto-fix"
fi

log_info ""
exit $EXIT_CODE
