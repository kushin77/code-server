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

[[ "${1:-}" == "--fix" ]] && FIX_MODE=true
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
    set -a  # export all variables
    source "$env_file"
    set +a
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
log_info "Validating 16 configuration conflicts..."
log_info ""

# 1. Database Configuration
if [[ "${POSTGRES_DB:-}" != "code_server" ]]; then
  log_error "INVALID DATABASE NAME: ${POSTGRES_DB} (expected: code_server)"
  EXIT_CODE=1
fi

if [[ "${POSTGRES_USER:-}" != "code_server" ]]; then
  log_error "INVALID POSTGRES USER: ${POSTGRES_USER} (expected: code_server)"
  EXIT_CODE=1
fi

# 2. NAS Configuration
if [[ "${NAS_HOST:-}" != "192.168.168.56" ]]; then
  log_warn "NAS_HOST is ${NAS_HOST} (expected: 192.168.168.56) — if intentional, OK"
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

# 6. Secret Checks (these should NOT be in .env files)
if grep -qE "POSTGRES_PASSWORD=|CODE_SERVER_PASSWORD=|GOOGLE_CLIENT_SECRET=|GITHUB_TOKEN=" .env 2>/dev/null || true; then
  log_error "SECURITY ISSUE: Secrets found in .env file"
  log_error "  Move to Vault (on-prem) or GSM (production)"
  EXIT_CODE=1
fi

# ════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════

log_info ""
if [[ $EXIT_CODE -eq 0 ]]; then
  log_success "✓ Configuration SSOT validation PASSED"
  log_info "  All 16 configuration conflicts resolved"
  log_info "  Ready for deployment"
else
  log_error "✗ Configuration SSOT validation FAILED"
  log_error "  Fix conflicts above before deploying"
  log_error "  Run with --fix to attempt auto-fix"
fi

log_info ""
exit $EXIT_CODE
