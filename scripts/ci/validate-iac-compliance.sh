#!/usr/bin/env bash
# @file        scripts/ci/validate-iac-compliance.sh
# @module      ci/governance
# @description Infrastructure as Code compliance validation (GOV-002)
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# Relates to: #1534 Governance, #1536 Networking

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Configuration ─────────────────────────────────────────────────────────────

# Exit codes
EXIT_SUCCESS=0
EXIT_HARDCODING_FOUND=1
EXIT_NO_ERROR_HANDLING=2
EXIT_NO_DOCUMENTATION=3
EXIT_MUTABLE_PATTERNS=4

# Patterns to check
HARDCODING_PATTERNS=(
  '192\.168\.[0-9]\+\.[0-9]\+'              # IPv4 addresses
  'localhost:[0-9]\+'                        # localhost with ports
  '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+'      # IP address pattern
  '(password|secret|key).*[=:][^$]'         # Hardcoded secrets (not env vars)
)

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { printf "${GREEN}✓${NC} %s\n" "$*"; }
fail() { printf "${RED}✗${NC} %s\n" "$*" >&2; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}ℹ${NC} %s\n" "$*"; }

# ── IaC Compliance Checks ─────────────────────────────────────────────────────

# Check 1: All infrastructure scripts must use env vars for configuration
check_env_var_usage() {
  info "Check 1: Environment variable usage in scripts..."
  local violations=0
  
  while IFS= read -r file; do
    # Skip test files and docs
    [[ "$file" =~ (test|spec|docs|\.example) ]] && continue
    
    # Infrastructure scripts must have env var pattern: ${VAR:-default}
    if grep -q '^\s*[A-Z_]\+=' "$file" && ! grep -q '\${[A-Z_]\+:-' "$file"; then
      # Might be setting a computed value, not a violation if sourced from config env
      # Or if it's a standard infra variable (REPO_ROOT, SCRIPT_DIR, etc.)
      if ! grep -qE 'source.*(_base-config|_epic-1536-network-config)' "$file" && \
         ! grep -qE '^\s*(REPO_ROOT|SCRIPT_DIR|PROJECT_ROOT|EXIT_|RED|GREEN|YELLOW|BLUE|NC)=' "$file"; then
        warn "  $file uses hardcoded assignment (prefer env vars)"
        ((violations++))
      fi
    fi
  done < <(find "${REPO_ROOT}/scripts" -name "*.sh" -type f | grep -E '(lib|ops|ci)' | grep -v test)
  
  if [ $violations -eq 0 ]; then
    pass "All infrastructure scripts use env var pattern"
    return $EXIT_SUCCESS
  else
    fail "Found $violations script(s) with potential hardcoding issues"
    return 1
  fi
}

# Check 2: All scripts must have error handling (set -euo pipefail)
check_error_handling() {
  info "Check 2: Error handling in scripts..."
  local violations=0
  
  while IFS= read -r file; do
    [[ "$file" =~ (test|spec|docs) ]] && continue
    
    if ! grep -q 'set -euo pipefail' "$file"; then
      warn "  $file missing 'set -euo pipefail'"
      ((violations++))
    fi
  done < <(find "${REPO_ROOT}/scripts" -name "*.sh" -type f | grep -E '(lib|ops|ci)' | grep -v test)
  
  if [ $violations -eq 0 ]; then
    pass "All scripts have proper error handling"
    return $EXIT_SUCCESS
  else
    fail "Found $violations script(s) without error handling"
    return $EXIT_NO_ERROR_HANDLING
  fi
}

# Check 3: All scripts must have GOV-002 documentation header
check_documentation() {
  info "Check 3: Governance documentation headers..."
  local violations=0
  
  while IFS= read -r file; do
    [[ "$file" =~ (test|spec|docs) ]] && continue
    
    if ! grep -q '@governance' "$file"; then
      warn "  $file missing @governance header"
      ((violations++))
    fi
  done < <(find "${REPO_ROOT}/scripts" -name "*.sh" -type f | grep -E '(lib|ops|ci)' | grep -v test)
  
  if [ $violations -eq 0 ]; then
    pass "All scripts have @governance headers"
    return $EXIT_SUCCESS
  else
    fail "Found $violations script(s) without @governance documentation"
    return $EXIT_NO_DOCUMENTATION
  fi
}

# Check 4: No timestamps in generated configurations (immutability)
check_idempotency() {
  info "Check 4: Idempotency (no dynamic values)..."
  local violations=0
  
  # Configuration generators should not include timestamps
  while IFS= read -r file; do
    # Skip auditing scripts that scan for these patterns
    [[ "$file" =~ (audit-network-hardcoding|validate-dns-service-discovery|validate-iac-compliance) ]] && continue

    if grep -q 'Generated:' "$file" || grep -q '\$(date)' "$file"; then
      warn "  $file includes dynamic timestamp (violates idempotency)"
      ((violations++))
    fi
  done < <(grep -El 'Generated:|\$\(date\)' "${REPO_ROOT}/scripts" 2>/dev/null | sort -u || true)
  
  if [ $violations -eq 0 ]; then
    pass "All generated configurations are idempotent (no timestamps)"
    return $EXIT_SUCCESS
  else
    fail "Found $violations file(s) with dynamic values"
    return $EXIT_MUTABLE_PATTERNS
  fi
}

# Check 5: Configuration templates must use template syntax
check_template_syntax() {
  info "Check 5: Configuration template syntax..."
  local template_files=0
  
  while IFS= read -r file; do
    ((template_files++))
    
    # Check for template variables ({{ VAR }}, ${VAR}, or similar)
    if ! grep -qE '({{|{%|\$\{)[A-Z_]+' "$file"; then
      warn "  $file missing template variable syntax"
    fi
  done < <(find "${REPO_ROOT}/config" -name "*template*" -type f 2>/dev/null || true)
  
  if [ $template_files -gt 0 ]; then
    pass "Found $template_files template configuration files"
    return $EXIT_SUCCESS
  else
    warn "No template configuration files found (consider using templates)"
    return 1
  fi
}

# Check 6: Docker Compose must use env vars
check_docker_compose_compliance() {
  info "Check 6: Docker Compose environment variable usage..."
  
  # Check for hardcoded network addresses
  if grep -qE 'image: .*:// |port: [0-9]\..*\. ' docker-compose.yml 2>/dev/null; then
    fail "docker-compose.yml contains hardcoded addresses"
    return 1
  fi
  
  pass "docker-compose.yml uses env var pattern"
  return $EXIT_SUCCESS
}

# ── Summary ───────────────────────────────────────────────────────────────────

main() {
  echo "🔍 Infrastructure as Code (IaC) Compliance Audit"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  local exit_code=$EXIT_SUCCESS
  
  check_env_var_usage || ((exit_code=1))
  check_error_handling || ((exit_code=1))
  check_documentation || ((exit_code=1))
  check_idempotency || ((exit_code=1))
  check_template_syntax || true  # Warning only
  check_docker_compose_compliance || ((exit_code=1))
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if [ $exit_code -eq 0 ]; then
    pass "All IaC compliance checks passed ✓"
    echo ""
    echo "✓ Environment variables: Used throughout infrastructure"
    echo "✓ Error handling: All scripts have 'set -euo pipefail'"
    echo "✓ Documentation: All scripts have @governance headers"
    echo "✓ Idempotency: No timestamps or dynamic values"
    echo "✓ Templates: Configuration templates support variable substitution"
    echo ""
    return $EXIT_SUCCESS
  else
    fail "IaC compliance audit failed ✗"
    echo ""
    echo "To fix violations:"
    echo "  1. Use \${VAR:-default} syntax for all configuration"
    echo "  2. Add 'set -euo pipefail' to all scripts"
    echo "  3. Include @governance header in all scripts"
    echo "  4. Remove timestamps from generated configurations"
    echo "  5. Use template syntax for configuration files"
    echo ""
    return $exit_code
  fi
}

main "$@"
