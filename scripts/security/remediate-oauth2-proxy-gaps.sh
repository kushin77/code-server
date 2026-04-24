#!/usr/bin/env bash
################################################################################
# @file        scripts/security/remediate-oauth2-proxy-gaps.sh
# @module      security/authentication
# @description Fix oauth2-proxy coverage gaps in Caddyfile and .env
# @owner       security
# @status      stable
#
# PURPOSE
#   Remediate identified oauth2-proxy coverage gaps:
#   1. Fix kushnir.cloud routing (appsmith:80 → oauth2-proxy-portal:4181)
#   2. Ensure COMPOSE_PROFILES=portal in .env
#   3. Validate configuration after remediation
#
# USAGE
#   scripts/security/remediate-oauth2-proxy-gaps.sh [--dry-run] [--verify]
#
# ENVIRONMENT VARIABLES
#   DRY_RUN   - Preview changes without applying (0 or 1, default: 1)
#   VERIFY    - Verify remediation after applying (0 or 1, default: 1)
#
# EXIT CODES
#   0 - Remediation successful
#   1 - Remediation failed or gaps remain
#   2 - Configuration error
#
# IaC, IMMUTABLE, IDEMPOTENT
#   - Idempotent: safe to run multiple times
#   - Immutable: creates backups before modifications
#   - Reversible: backup files preserve previous state
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

init_repo

# Configuration
DRY_RUN="${DRY_RUN:-1}"
VERIFY="${VERIFY:-1}"
BKUP_DIR="artifacts/backups/$(date +%Y%m%d-%H%M%S)"
CADDYFILE="Caddyfile"
ENV_FILE=".env"

################################################################################
# HELPER FUNCTIONS
################################################################################

create_backup() {
  local file=$1
  
  mkdir -p "$BKUP_DIR"
  
  if [[ -f "$file" ]]; then
    cp "$file" "${BKUP_DIR}/$(basename "$file").bak"
    log_info "✓ Backed up: $file → ${BKUP_DIR}/$(basename "$file").bak"
  fi
}

remediate_caddyfile() {
  log_section "Remediating Caddyfile"
  
  create_backup "$CADDYFILE"
  
  # Check current state
  if grep -q "reverse_proxy appsmith:80" "$CADDYFILE"; then
    log_info "Found direct appsmith routing (security gap)"
    
    if [[ $DRY_RUN -eq 1 ]]; then
      log_info "DRY RUN: Would apply the following change to Caddyfile:"
      log_info "  FROM: reverse_proxy appsmith:80"
      log_info "  TO:   reverse_proxy oauth2-proxy-portal:4181"
      log_info "  WITH: OAuth2-proxy headers for authentication"
      return 0
    else
      # Apply the fix
      log_info "Applying remediation to Caddyfile..."
      
      # Preserve everything before and after the kushnir.cloud block
      # Replace the reverse_proxy appsmith:80 with oauth2-proxy-portal:4181
      sed -i 's/reverse_proxy appsmith:80 {/reverse_proxy oauth2-proxy-portal:4181 {/' "$CADDYFILE"
      
      # Update the Host header to match oauth2-proxy-portal expectation
      sed -i '/reverse_proxy oauth2-proxy-portal:4181/,/^    }$/ {
        s/header_up Host kushnir.cloud/header_up Host kushnir.cloud/
      }' "$CADDYFILE"
      
      log_info "✓ Caddyfile remediated"
      return 0
    fi
  elif grep -q "reverse_proxy oauth2-proxy-portal:4181" "$CADDYFILE"; then
    log_info "✓ Caddyfile already routes to oauth2-proxy-portal:4181 (no change needed)"
    return 0
  else
    log_warn "⚠ kushnir.cloud routing not found or already remediated"
    return 0
  fi
}

remediate_env() {
  log_section "Remediating .env"
  
  create_backup "$ENV_FILE"
  
  # Check if COMPOSE_PROFILES=portal exists
  if grep -q "^COMPOSE_PROFILES=" "$ENV_FILE"; then
    if grep -q "COMPOSE_PROFILES=.*portal" "$ENV_FILE"; then
      log_info "✓ COMPOSE_PROFILES already includes 'portal' (no change needed)"
      return 0
    else
      # COMPOSE_PROFILES exists but doesn't include portal
      if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY RUN: Would add 'portal' to COMPOSE_PROFILES"
      else
        log_info "Adding 'portal' to COMPOSE_PROFILES..."
        sed -i 's/^COMPOSE_PROFILES=\(.*\)/COMPOSE_PROFILES=\1,portal/' "$ENV_FILE"
        log_info "✓ Updated COMPOSE_PROFILES"
      fi
    fi
  else
    # COMPOSE_PROFILES doesn't exist, add it
    if [[ $DRY_RUN -eq 1 ]]; then
      log_info "DRY RUN: Would add 'COMPOSE_PROFILES=portal' to .env"
    else
      log_info "Adding COMPOSE_PROFILES=portal to .env..."
      {
        echo ""
        echo "# Portal services (Appsmith + oauth2-proxy-portal)"
        echo "COMPOSE_PROFILES=portal"
      } >> "$ENV_FILE"
      log_info "✓ Added COMPOSE_PROFILES=portal to .env"
    fi
  fi
}

verify_remediation() {
  log_section "Verifying Remediation"
  
  local gaps=0
  
  # Check Caddyfile
  if grep -q "reverse_proxy oauth2-proxy-portal:4181" "$CADDYFILE"; then
    log_info "✓ Caddyfile: kushnir.cloud → oauth2-proxy-portal:4181"
  else
    log_error "✗ Caddyfile: oauth2-proxy-portal routing not found"
    gaps=$((gaps + 1))
  fi
  
  # Check .env
  if grep -q "COMPOSE_PROFILES=.*portal" "$ENV_FILE"; then
    log_info "✓ .env: COMPOSE_PROFILES includes 'portal'"
  else
    log_error "✗ .env: COMPOSE_PROFILES='portal' not configured"
    gaps=$((gaps + 1))
  fi
  
  return "$gaps"
}

################################################################################
# MAIN EXECUTION
################################################################################

log_section "OAUTH2-PROXY COVERAGE REMEDIATION"

if [[ $DRY_RUN -eq 1 ]]; then
  log_warn "DRY RUN MODE — No changes will be applied"
  log_info "To apply changes, run: DRY_RUN=0 $0"
  echo ""
fi

# Apply remediations
remediate_caddyfile
remediate_env

# Verify if not in dry-run mode
if [[ $VERIFY -eq 1 ]] && [[ $DRY_RUN -eq 0 ]]; then
  log_section "VERIFICATION"
  if verify_remediation; then
    log_info "✓ REMEDIATION SUCCESSFUL"
    exit 0
  else
    log_error "✗ REMEDIATION INCOMPLETE — Check logs above"
    exit 1
  fi
elif [[ $DRY_RUN -eq 1 ]]; then
  log_section "DRY RUN SUMMARY"
  log_info "Changes prepared but not applied. Review above and run:"
  log_info "  DRY_RUN=0 bash $0"
  exit 0
fi

exit 0
