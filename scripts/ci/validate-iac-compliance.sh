#!/usr/bin/env bash
# @file        scripts/ci/validate-iac-compliance.sh
# @module      ci/governance
# @description Infrastructure as Code compliance validation (GOV-002)
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Exit codes
EXIT_SUCCESS=0
EXIT_HARDCODING_FOUND=1
EXIT_NO_ERROR_HANDLING=2
EXIT_NO_DOCUMENTATION=3
EXIT_MUTABLE_PATTERNS=4

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { printf "${GREEN}✓${NC} %s\n" "$*"; }
fail() { printf "${RED}✗${NC} %s\n" "$*" >&2; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}ℹ${NC} %s\n" "$*"; }

check_env_var_usage() {
  info "Check 1: Environment variable usage..."
  local violations=0
  while IFS= read -r file; do
    [[ "$file" =~ (test|spec|docs|\.example) ]] && continue
    if grep -q '^\s*[A-Z_]\+=' "$file" && ! grep -q '\${[A-Z_]\+:-' "$file"; then
      if ! grep -qE 'source.*(_base-config|_epic-1536-network-config)' "$file"; then
        warn "  $file uses hardcoded assignment"
        ((violations++))
      fi
    fi
  done < <(find "${REPO_ROOT}/scripts" -name "*.sh" -type f | grep -E '(lib|ops|ci)' | grep -v test)
  [[ $violations -eq 0 ]] && pass "OK" || return 1
}

check_error_handling() {
  info "Check 2: Error handling..."
  local violations=0
  while IFS= read -r file; do
    [[ "$file" =~ (test|spec|docs) ]] && continue
    grep -q 'set -euo pipefail' "$file" || { warn "  $file missing set -euo pipefail"; ((violations++)); }
  done < <(find "${REPO_ROOT}/scripts" -name "*.sh" -type f | grep -E '(lib|ops|ci)' | grep -v test)
  [[ $violations -eq 0 ]] && pass "OK" || return $EXIT_NO_ERROR_HANDLING
}

check_documentation() {
  info "Check 3: Governance documentation..."
  local violations=0
  while IFS= read -r file; do
    [[ "$file" =~ (test|spec|docs) ]] && continue
    grep -q '@governance' "$file" || { warn "  $file missing @governance"; ((violations++)); }
  done < <(find "${REPO_ROOT}/scripts" -name "*.sh" -type f | grep -E '(lib|ops|ci)' | grep -v test)
  [[ $violations -eq 0 ]] && pass "OK" || return $EXIT_NO_DOCUMENTATION
}

check_idempotency() {
  info "Check 4: Idempotency..."
  local violations=0
  while IFS= read -r file; do
    [[ "$file" =~ (audit-network-hardcoding|validate-dns-service-discovery|validate-iac-compliance) ]] && continue
    if grep -q 'Generated:' "$file" || grep -q '\$(date)' "$file"; then
      warn "  $file has dynamic values"
      ((violations++))
    fi
  done < <(grep -El 'Generated:|\$\(date\)' "${REPO_ROOT}/scripts" 2>/dev/null | sort -u || true)
  [[ $violations -eq 0 ]] && pass "OK" || return $EXIT_MUTABLE_PATTERNS
}

check_docker_compose() {
  info "Check 5: Docker Compose..."
  grep -qE 'image: .*:// |port: [0-9]\..*\. ' docker-compose.yml 2>/dev/null && return 1
  pass "OK"
  return $EXIT_SUCCESS
}

main() {
  echo "🔍 IaC Compliance Audit (GOV-002)"
  local exit_code=$EXIT_SUCCESS
  check_env_var_usage || exit_code=1
  check_error_handling || exit_code=1
  check_documentation || exit_code=1
  check_idempotency || exit_code=1
  check_docker_compose || exit_code=1
  [[ $exit_code -eq 0 ]] && pass "PASSED" || fail "FAILED"
  return $exit_code
}

main "$@"
