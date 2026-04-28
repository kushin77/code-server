#!/usr/bin/env bash
###############################################################################
# @file scripts/ci/validate-trap-handlers.sh
# @module validation
# @description Comprehensive validation of trap handler implementation
# @governance GOV-002: All scripts MUST have proper error handling
# @author Infrastructure Audit Bot
# @date 2026-04-28
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NC='\033[0m'

# Counters
SCRIPTS_CHECKED=0
SCRIPTS_PASS=0
SCRIPTS_FAIL=0
SCRIPTS_WARN=0

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_fail() {
  echo -e "${RED}[✗]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[!]${NC} $*"
}

###############################################################################
# validate_trap_handlers: Check if a script has proper trap handlers
###############################################################################
validate_trap_handlers() {
  local script_path="$1"
  local script_name=$(basename "$script_path")
  
  ((SCRIPTS_CHECKED++))
  
  # Skip non-bash scripts
  if ! head -1 "$script_path" | grep -q "bash"; then
    return 0
  fi
  
  # Check for ERR trap
  if ! grep -q "trap.*ERR\|trap.*'.*ERR\|trap.*\".*ERR" "$script_path"; then
    log_fail "$script_name: Missing ERR trap handler"
    ((SCRIPTS_FAIL++))
    return 1
  fi
  
  # Check for EXIT trap
  if ! grep -q "trap.*EXIT\|trap.*'.*EXIT\|trap.*\".*EXIT" "$script_path"; then
    log_fail "$script_name: Missing EXIT trap handler"
    ((SCRIPTS_FAIL++))
    return 1
  fi
  
  # Check that trap uses log functions or cleanup code
  local err_trap=$(grep "trap.*ERR" "$script_path" | head -1)
  if ! echo "$err_trap" | grep -qE "log_error|exit|return"; then
    log_warn "$script_name: ERR trap might not handle errors properly"
    ((SCRIPTS_WARN++))
  fi
  
  log_pass "$script_name: Trap handlers validated"
  ((SCRIPTS_PASS++))
  return 0
}

###############################################################################
# test_trap_handlers: Test that trap handlers actually work
###############################################################################
test_trap_handlers() {
  local test_script=$(mktemp)
  
  cat > "$test_script" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

ERROR_TRIGGERED=0
EXIT_TRIGGERED=0

trap 'ERROR_TRIGGERED=1' ERR
trap 'EXIT_TRIGGERED=1' EXIT

# Simulate error
(exit 1) || true

# Check handlers worked
if [[ $ERROR_TRIGGERED -eq 1 && $EXIT_TRIGGERED -eq 1 ]]; then
  echo "PASS"
  exit 0
else
  echo "FAIL"
  exit 1
fi
TESTEOF

  if bash "$test_script" 2>/dev/null | grep -q "PASS"; then
    log_pass "Trap handler execution: PASS"
  else
    log_fail "Trap handler execution: FAIL"
    ((SCRIPTS_FAIL++))
  fi
  
  rm -f "$test_script"
}

###############################################################################
# Main validation loop
###############################################################################
main() {
  log_info "=== Trap Handler Validation Report ==="
  echo ""
  
  log_info "Validating trap handlers in critical scripts..."
  
  # Check scripts/ops
  log_info "Checking scripts/ops/..."
  while IFS= read -r script; do
    validate_trap_handlers "$script"
  done < <(find "${REPO_ROOT}/scripts/ops" -name "*.sh" -type f)
  
  # Check scripts/ci
  log_info "Checking scripts/ci/..."
  while IFS= read -r script; do
    validate_trap_handlers "$script"
  done < <(find "${REPO_ROOT}/scripts/ci" -name "*.sh" -type f)
  
  # Check scripts/edge-agent
  if [[ -d "${REPO_ROOT}/scripts/edge-agent" ]]; then
    log_info "Checking scripts/edge-agent/..."
    while IFS= read -r script; do
      validate_trap_handlers "$script"
    done < <(find "${REPO_ROOT}/scripts/edge-agent" -name "*.sh" -type f 2>/dev/null || true)
  fi
  
  echo ""
  log_info "Running functional tests..."
  test_trap_handlers
  
  echo ""
  log_info "=== Validation Summary ==="
  log_info "Scripts checked: $SCRIPTS_CHECKED"
  log_pass "Scripts passing: $SCRIPTS_PASS"
  log_fail "Scripts failing: $SCRIPTS_FAIL"
  log_warn "Scripts with warnings: $SCRIPTS_WARN"
  
  echo ""
  if [[ $SCRIPTS_FAIL -eq 0 ]]; then
    log_pass "All trap handlers validated successfully!"
    return 0
  else
    log_fail "Trap handler validation FAILED"
    return 1
  fi
}

main
