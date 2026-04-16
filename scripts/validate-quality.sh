#!/bin/bash
# Quality Gates Validation Script — Local Pre-Commit Enforcement
# Run before committing: ./scripts/validate-quality.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
EXIT_CODE=0
VERBOSE="${VERBOSE:-0}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log_info() { echo -e "${BLUE}ℹ️ $*${NC}"; }
log_pass() { echo -e "${GREEN}✅ $*${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_fail() { echo -e "${RED}❌ $*${NC}"; EXIT_CODE=1; }

# ============================================================================
# 1. SHELL SCRIPT VALIDATION
# ============================================================================
validate_shell_scripts() {
  log_info "Validating shell scripts..."
  
  if ! command -v shellcheck &> /dev/null; then
    log_warn "shellcheck not installed (install via: apt-get install shellcheck)"
    return 0
  fi
  
  local script_count=0
  local violation_count=0
  
  while IFS= read -r script; do
    ((script_count++))
    if ! shellcheck -x "$script" 2>&1; then
      ((violation_count++))
    fi
  done < <(find "$REPO_ROOT" -name "*.sh" -type f ! -path "./.git/*" ! -path "./.terraform/*")
  
  if [ "$violation_count" -gt 0 ]; then
    log_fail "Found $violation_count shell script violations in $script_count scripts"
  else
    log_pass "All $script_count shell scripts valid"
  fi
}

# ============================================================================
# 2. YAML VALIDATION
# ============================================================================
validate_yaml() {
  log_info "Validating YAML files..."
  
  if ! command -v yamllint &> /dev/null; then
    log_warn "yamllint not installed (install via: pip install yamllint)"
    return 0
  fi
  
  local violation_count=0
  
  while IFS= read -r yaml_file; do
    if ! yamllint -c '{extends: default, rules: {line-length: {max: 200}, indentation: {spaces: 2}}}' "$yaml_file" 2>&1; then
      ((violation_count++))
    fi
  done < <(find "$REPO_ROOT" \( -name "*.yml" -o -name "*.yaml" \) -type f ! -path "./.git/*" ! -path "./.terraform/*" ! -path "./node_modules/*")
  
  if [ "$violation_count" -gt 0 ]; then
    log_fail "Found $violation_count YAML validation errors"
  else
    log_pass "All YAML files valid"
  fi
}

# ============================================================================
# 3. DOCKERFILE VALIDATION
# ============================================================================
validate_dockerfiles() {
  log_info "Validating Dockerfiles..."
  
  if ! command -v hadolint &> /dev/null; then
    log_warn "hadolint not installed (install via: docker pull hadolint/hadolint)"
    return 0
  fi
  
  local violation_count=0
  
  while IFS= read -r dockerfile; do
    if ! hadolint "$dockerfile" 2>&1; then
      ((violation_count++))
    fi
  done < <(find "$REPO_ROOT" -name "Dockerfile*" -type f ! -path "./.git/*")
  
  if [ "$violation_count" -gt 0 ]; then
    log_fail "Found violations in $violation_count Dockerfiles"
  else
    log_pass "All Dockerfiles valid"
  fi
}

# ============================================================================
# 4. SECRET SCANNING
# ============================================================================
validate_secrets() {
  log_info "Scanning for hardcoded secrets..."
  
  local secret_patterns=(
    "password[[:space:]]*=['\"]"
    "secret[[:space:]]*=['\"]"
    "api[_-]?key[[:space:]]*=['\"]"
    "private[_-]?key[[:space:]]*=['\"]"
    "token[[:space:]]*=['\"]"
    "aws[_-]?secret"
    "github[_-]?token"
  )
  
  local violation_count=0
  
  for pattern in "${secret_patterns[@]}"; do
    while IFS= read -r file; do
      if grep -E "$pattern" "$file" 2>/dev/null | grep -v "PLACEHOLDER\|REDACTED\|changeme\|example" > /dev/null; then
        log_fail "Potential secret in: $file"
        ((violation_count++))
      fi
    done < <(find "$REPO_ROOT" \( -name "*.sh" -o -name "*.tf" -o -name "*.yml" -o -name "*.yaml" \) -type f ! -path "./.git/*" ! -path "./.terraform/*")
  done
  
  if [ "$violation_count" -eq 0 ]; then
    log_pass "No hardcoded secrets detected"
  fi
}

# ============================================================================
# 5. CODE DUPLICATION DETECTION
# ============================================================================
validate_duplication() {
  log_info "Checking for code duplication..."
  
  if ! command -v jscpd &> /dev/null; then
    log_warn "jscpd not installed (install via: npm install -g jscpd)"
    return 0
  fi
  
  if ! jscpd --exclude "node_modules/**,archived/**,.terraform/**,config/**" \
             --threshold 10 \
             --reporters=console \
             "$REPO_ROOT" 2>&1; then
    log_warn "Code duplication exceeds threshold (>10%)"
  else
    log_pass "Code duplication within acceptable limits"
  fi
}

# ============================================================================
# 6. TERRAFORM VALIDATION
# ============================================================================
validate_terraform() {
  log_info "Validating Terraform configuration..."
  
  if [ ! -d "$REPO_ROOT/terraform" ]; then
    log_info "No Terraform directory found (skipping)"
    return 0
  fi
  
  if ! command -v terraform &> /dev/null; then
    log_warn "terraform not installed"
    return 0
  fi
  
  cd "$REPO_ROOT/terraform"
  
  if ! terraform init -backend=false -upgrade -no-color 2>&1 | head -20; then
    log_fail "Terraform init failed"
  elif ! terraform validate 2>&1; then
    log_fail "Terraform validation failed"
  else
    log_pass "Terraform configuration valid"
  fi
  
  cd "$REPO_ROOT"
}

# ============================================================================
# 7. DEPENDENCY AUDIT
# ============================================================================
validate_dependencies() {
  log_info "Auditing dependencies..."
  
  # npm audit
  if [ -f "$REPO_ROOT/package.json" ]; then
    log_info "Running npm audit..."
    if command -v npm &> /dev/null; then
      npm audit --audit-level=moderate || log_warn "npm audit detected vulnerabilities"
    fi
  fi
  
  # pip audit
  if [ -f "$REPO_ROOT/requirements.txt" ]; then
    log_info "Running pip audit..."
    if command -v pip &> /dev/null; then
      pip install -q safety 2>/dev/null || true
      safety check --file "$REPO_ROOT/requirements.txt" || log_warn "pip audit detected vulnerabilities"
    fi
  fi
  
  log_pass "Dependency audit complete"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
  echo "════════════════════════════════════════════════════════════════"
  echo "QUALITY GATES VALIDATION — Production-First Mandate"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  
  cd "$REPO_ROOT"
  
  # Run all validations
  validate_shell_scripts
  validate_yaml
  validate_dockerfiles
  validate_secrets
  validate_duplication
  validate_terraform
  validate_dependencies
  
  # Summary
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  if [ "$EXIT_CODE" -eq 0 ]; then
    log_pass "All quality gates PASSED ✅"
    echo ""
    echo "Ready to commit!"
  else
    log_fail "Quality gates FAILED — commit blocked"
    echo ""
    echo "Fix violations and run again: ./scripts/validate-quality.sh"
    echo ""
    echo "Quality gates policy: docs/QUALITY-GATES.md"
  fi
  echo "════════════════════════════════════════════════════════════════"
  
  exit "$EXIT_CODE"
}

# Run main
main "$@"
