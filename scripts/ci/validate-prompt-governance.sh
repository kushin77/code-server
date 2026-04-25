#!/bin/bash
# @file validate-prompt-governance.sh
# @module governance/ai-prompts
# @description P1-1823: Enforce prompt governance - standardize sections, token budgets, and formats
# @governance GOV-003: All system prompts must follow canonical structure with versioning and token budgeting
# @usage validate-prompt-governance.sh [--check] [--fix] [--report]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_FILE="${REPO_ROOT}/artifacts/prompt-governance-report.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

# ============================================================================
# Required Prompt Sections (Canonical Structure)
# ============================================================================
# All system prompts MUST include:
# 1. Role/Identity - who/what the agent is
# 2. Constraints - behavioral guardrails
# 3. Token Budget - max tokens for this prompt
# 4. Version - semantic versioning (MAJOR.MINOR.PATCH)
# 5. Last Updated - ISO 8601 timestamp
# 6. Approved By - governance approval marker

declare -a REQUIRED_SECTIONS=(
  "role"
  "constraints"
  "token_budget"
  "version"
  "last_updated"
  "approved_by"
)

# ============================================================================
# Prompt Files to Validate
# ============================================================================
# Pattern: Files with .instructions.md, .prompt.md, .system.md extensions
# Located in: Root level, scripts/, apps/, config/

find_prompt_files() {
  find "${REPO_ROOT}" \
    -type f \
    \( -name "*.instructions.md" -o -name "*.prompt.md" -o -name "*.system.md" \) \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    ! -path "*/htmlcov/*" \
    2>/dev/null | sort
}

# ============================================================================
# Validate Single Prompt File
# ============================================================================
validate_prompt_file() {
  local file="$1"
  local violations=0
  local warnings=0

  log_info "Validating: ${file#$REPO_ROOT/}"

  # Check if file is readable
  if [[ ! -r "$file" ]]; then
    log_error "  Cannot read file"
    return 1
  fi

  # Check file is not empty
  if [[ ! -s "$file" ]]; then
    log_error "  File is empty"
    return 1
  fi

  # Validate required sections
  for section in "${REQUIRED_SECTIONS[@]}"; do
    # Allow case-insensitive matching for section headers
    if ! grep -iq "^#.*$section" "$file" && ! grep -iq "^$section:" "$file"; then
      log_error "  Missing required section: $section"
      ((violations++))
    else
      log_info "  ✓ Found section: $section"
    fi
  done

  # Validate version format (MAJOR.MINOR.PATCH)
  if grep -iq "version:" "$file"; then
    local version=$(grep -i "version:" "$file" | head -1 | sed 's/.*version:\s*//i' | sed 's/\s*#.*//' | tr -d ' ')
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      log_warning "  Version format invalid (expected MAJOR.MINOR.PATCH): $version"
      ((warnings++))
    fi
  fi

  # Validate token budget is numeric
  if grep -iq "token.budget\|token_budget" "$file"; then
    local budget=$(grep -i "token.budget\|token_budget" "$file" | head -1 | sed 's/.*[^0-9]\([0-9]*\)[^0-9]*$/\1/')
    if [[ -z "$budget" ]]; then
      log_warning "  Token budget appears empty or unparseable"
      ((warnings++))
    elif [[ ! "$budget" =~ ^[0-9]+$ ]]; then
      log_warning "  Token budget not numeric: $budget"
      ((warnings++))
    else
      log_info "  ✓ Token budget: $budget tokens"
      # Warn if token budget seems unrealistic
      if [[ $budget -lt 100 ]]; then
        log_warning "  Token budget unusually low ($budget < 100)"
        ((warnings++))
      elif [[ $budget -gt 100000 ]]; then
        log_warning "  Token budget unusually high ($budget > 100000)"
        ((warnings++))
      fi
    fi
  fi

  # Validate approved_by contains at least a marker
  if grep -iq "approved_by:" "$file"; then
    local approver=$(grep -i "approved_by:" "$file" | head -1 | sed 's/.*approved_by:\s*//i' | sed 's/\s*#.*//')
    if [[ -z "$approver" || "$approver" == "TODO" || "$approver" == "PENDING" ]]; then
      log_warning "  Approval status missing or pending: $approver"
      ((warnings++))
    fi
  else
    log_error "  Missing governance approval marker (approved_by)"
    ((violations++))
  fi

  # Return non-zero if violations found
  if [[ $violations -gt 0 ]]; then
    log_error "  FAILED: $violations critical violations, $warnings warnings"
    return 1
  elif [[ $warnings -gt 0 ]]; then
    log_warning "  PASSED with $warnings warnings"
    return 0
  else
    log_info "  ✓ PASSED all checks"
    return 0
  fi
}

# ============================================================================
# Main Validation Logic
# ============================================================================
main() {
  local mode="${1:---check}"
  local failed_files=0
  local passed_files=0
  local total_files=0

  log_info "Prompt Governance Validation"
  log_info "Mode: $mode"
  log_info ""

  # Find all prompt files
  mapfile -t prompt_files < <(find_prompt_files)

  if [[ ${#prompt_files[@]} -eq 0 ]]; then
    log_info "No prompt files found to validate (this is OK for initial setup)"
    # Create minimal report
    mkdir -p "${REPORT_FILE%/*}"
    cat > "${REPORT_FILE}" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "status": "PASS",
  "reason": "No prompts found (baseline pass)",
  "total_files": 0,
  "passed": 0,
  "failed": 0,
  "warnings": 0
}
EOF
    return 0
  fi

  # Validate each prompt file
  for file in "${prompt_files[@]}"; do
    ((total_files++))
    if validate_prompt_file "$file"; then
      ((passed_files++))
    else
      ((failed_files++))
    fi
    echo ""
  done

  log_info "Validation Summary"
  log_info "  Total files: $total_files"
  log_info "  Passed: $passed_files"
  log_info "  Failed: $failed_files"

  # Create report
  mkdir -p "${REPORT_FILE%/*}"
  cat > "${REPORT_FILE}" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "status": "$([ $failed_files -eq 0 ] && echo "PASS" || echo "FAIL")",
  "total_files": $total_files,
  "passed": $passed_files,
  "failed": $failed_files,
  "report_file": "${REPORT_FILE}"
}
EOF

  log_info ""
  log_info "Report saved to: ${REPORT_FILE}"

  # Return failure if any files failed validation
  if [[ $failed_files -gt 0 ]]; then
    log_error "Prompt governance validation FAILED ($failed_files file(s))"
    return 1
  else
    log_info "Prompt governance validation PASSED"
    return 0
  fi
}

# ============================================================================
# Entry Point
# ============================================================================
main "$@"
exit $?
