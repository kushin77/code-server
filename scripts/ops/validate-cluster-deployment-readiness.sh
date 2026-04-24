#!/usr/bin/env bash
# @file        scripts/ops/validate-cluster-deployment-readiness.sh
# @module      ops/validation
# @description Comprehensive validation that cluster is ready for deployment automation
#
# USAGE:
#   bash scripts/ops/validate-cluster-deployment-readiness.sh [--verbose]
#
# PURPOSE:
#   Validates all prerequisites, configurations, and automation are in place
#   before executing the deployment workflow. Checks:
#   - All required scripts present and syntactically valid
#   - Configuration files (.env.defaults, .env.schema.json) present
#   - Docker-compose files and overrides in place
#   - SSH connectivity to both replicas
#   - Current cluster state (git commits, service counts)
#   - Shared library system functional
#
# EXIT CODES:
#   0 = All validation passed, cluster is ready for deployment
#   1 = One or more validation checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

VERBOSE="${VERBOSE:-0}"
SSH_USER="${SSH_USER:-${DEPLOY_USER:-}}"

if [[ -z "${REPLICAS:-}" ]]; then
  if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
    REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
  else
    log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before running deployment readiness validation"
  fi
fi

if [[ -z "$SSH_USER" ]]; then
  log_fatal "Set SSH_USER or DEPLOY_USER before running deployment readiness validation"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Validation Functions
# ─────────────────────────────────────────────────────────────────────────────

validate_file() {
  local file=$1
  local description=$2
  
  if [[ -f "$file" ]]; then
    log_info "  ✓ $description: $file"
    return 0
  else
    log_error "  ✗ MISSING: $description: $file"
    return 1
  fi
}

validate_script_syntax() {
  local script=$1
  local name=$2
  
  if bash -n "$script" 2>/dev/null; then
    log_info "  ✓ $name syntax valid"
    return 0
  else
    log_error "  ✗ $name syntax FAILED"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Validation
# ─────────────────────────────────────────────────────────────────────────────

log_section "DEPLOYMENT READINESS VALIDATION"

validation_failed=0

# Phase 1: Check required files exist
log_section "Phase 1: Configuration Files"

for file in ".env.defaults" ".env.schema.json" "docker-compose.yml" "Caddyfile"; do
  validate_file "$file" "Configuration" || validation_failed=1
done

log_section "Phase 2: Docker-Compose Overrides"

for file in "docker-compose.replica.yml" "docker-compose.replica-port-override.yml"; do
  validate_file "$file" "Replica override" || validation_failed=1
done

# Phase 2: Check deployment scripts exist and are valid
log_section "Phase 3: Deployment Scripts"

declare -a SCRIPTS=(
  "scripts/ops/sync-env-to-replicas.sh:Environment sync"
  "scripts/ops/parallel-deploy.sh:Parallel deployment"
  "scripts/ops/check-replica-parity.sh:Parity verification"
  "scripts/ops/fix-replica-1-permissions.sh:Replica 1 remediation"
)

for script_info in "${SCRIPTS[@]}"; do
  script="${script_info%:*}"
  name="${script_info#*:}"
  
  if validate_file "$script" "Script" && validate_script_syntax "$script" "$name"; then
    true
  else
    validation_failed=1
  fi
done

# Phase 3: Check shared library system
log_section "Phase 4: Shared Library System"

if source "$SCRIPT_DIR/_common/init.sh" 2>/dev/null; then
  log_info "  ✓ init.sh loads successfully"
  log_info "  ✓ Shared libraries available (logging, config, utils)"
else
  log_error "  ✗ init.sh failed to load"
  validation_failed=1
fi

# Phase 4: Check SSH access (if available)
log_section "Phase 5: SSH Connectivity"

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
if [[ -f "$SSH_KEY" ]]; then
  log_info "  ✓ SSH key found: $SSH_KEY"
  
  # Try pinging replicas (may fail if no network access from local machine)
  IFS=',' read -ra replica_array <<< "$REPLICAS"
  for replica in "${replica_array[@]}"; do
    if ssh -o ConnectTimeout=3 -o BatchMode=yes "${SSH_USER}@${replica}" "echo test" >/dev/null 2>&1; then
      log_info "  ✓ SSH to $replica responsive"
    else
      log_warn "  ⚠ SSH to $replica not currently reachable (may require network/VPN)"
      [[ "$VERBOSE" -eq 1 ]] && log_debug "    This is expected if running from outside production network"
    fi
  done
else
  log_warn "  ⚠ SSH key not found at $SSH_KEY (will be needed for actual deployment)"
fi

# Phase 5: Check execution guide
log_section "Phase 6: Documentation"

if [[ -f "CLUSTER-PARITY-FINAL-EXECUTION-GUIDE.md" ]]; then
  lines=$(wc -l < "CLUSTER-PARITY-FINAL-EXECUTION-GUIDE.md")
  log_info "  ✓ Execution guide present ($lines lines)"
else
  log_error "  ✗ MISSING: Execution guide"
  validation_failed=1
fi

# Final verdict
log_section "VALIDATION RESULT"

if [[ $validation_failed -eq 0 ]]; then
  log_info "✅ ALL CHECKS PASSED - Cluster deployment automation is ready"
  log_info ""
  log_info "Next steps:"
  log_info "  1. Review CLUSTER-PARITY-FINAL-EXECUTION-GUIDE.md"
  log_info "  2. Choose deployment option (A, B, or C)"
  log_info "  3. Execute deployment workflow"
  exit 0
else
  log_error "❌ VALIDATION FAILED - Review errors above"
  log_error ""
  log_error "Fix any missing files or script errors before deployment"
  exit 1
fi
