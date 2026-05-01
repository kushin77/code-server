#!/bin/bash
###############################################################################
# @file scripts/ci/lint-error-handling.sh
# @module ci/lint
# @description CI/CD linting rule to enforce error handling in deployment scripts
# @governance GOV-002: All critical scripts must have error trap handlers
# @usage bash scripts/ci/lint-error-handling.sh [--fix] [--strict]
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Configuration
FIX_MODE="${1:-false}"
STRICT_MODE="${2:-false}"
EXIT_CODE=0

# Color output
red() { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }

echo "$(green "=== Error Handling Lint Check ===") "
echo ""

# List of critical scripts that MUST have trap handlers
declare -a CRITICAL_SCRIPTS=(
  "scripts/ops/deploy-production-fix.sh"
  "scripts/ops/deploy.sh"
  "scripts/ops/deployment-pipeline.sh"
  "scripts/ops/backup.sh"
  "scripts/ops/health-check-and-rollback.sh"
  "scripts/ops/test-rollback-procedures.sh"
  "scripts/ops/automated-rollback.sh"
  "scripts/ops/cleanup-uncommitted.sh"
  "scripts/edge-agent/register-edge-agent.sh"
  "scripts/edge-agent/monitor-edge-agent-health.sh"
)

# Check individual script
check_trap_handler() {
  local script="$1"
  local criticality="${2:-normal}"  # critical or normal
  
  if [[ ! -f "$REPO_ROOT/$script" ]]; then
    yellow "⚠ Script not found: $script"
    return 0
  fi
  
  if grep -q "^trap " "$REPO_ROOT/$script"; then
    green "✓ Has trap handler: $script"
    return 0
  else
    if [[ "$criticality" == "critical" ]]; then
      red "✗ MISSING trap handler (CRITICAL): $script"
      EXIT_CODE=1
      return 1
    else
      yellow "⚠ MISSING trap handler: $script"
      return 1
    fi
  fi
}

echo "$(green "Checking critical scripts:")  "
for script in "${CRITICAL_SCRIPTS[@]}"; do
  check_trap_handler "$script" "critical"
done

echo ""
echo "$(green "Checking all operational scripts:")  "

total=0
with_traps=0
missing_traps=0

for script in $(find "$REPO_ROOT/scripts/ops" -name "*.sh" -type f | sort); do
  total+=1
  if grep -q "^trap " "$script"; then
    with_traps+=1
  else
    missing_traps+=1
    if [[ "$STRICT_MODE" != "false" ]]; then
      red "✗ $script"
    fi
  fi
done

echo ""
echo "Summary:"
echo "  Total scripts: $total"
green "  With trap handlers: $with_traps ($(( (with_traps * 100) / total ))%)"
if [[ $missing_traps -gt 0 ]]; then
  yellow "  Without trap handlers: $missing_traps ($(( (missing_traps * 100) / total ))%)"
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
  green "✓ All critical scripts have error handling"
else
  red "✗ Some critical scripts are missing error handling"
  echo ""
  echo "To add trap handlers, see: scripts/_common/SSOT-PATTERN.md (Error Handling section)"
fi

echo ""
exit $EXIT_CODE
