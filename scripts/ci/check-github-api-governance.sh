#!/usr/bin/env bash
# @file        scripts/ci/check-github-api-governance.sh
# @module      ci/github-api-governance
# @description CI guard to enforce GitHub API stability and governance rules
#
# Blocks commits that violate:
# - Direct `gh` CLI calls without --repo flag
# - Classic PAT tokens (must use fine-grained)
# - Missing error handling on GitHub API calls
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/_common/init.sh"

# ============================================================================
# Configuration
# ============================================================================

readonly VIOLATIONS_FOUND=0
readonly VIOLATIONS_MAX=10  # Fail if more than this

# ============================================================================
# Governance Checks
# ============================================================================

#
# Check for direct `gh` calls without --repo flag
#
check_gh_repo_flag() {
  log_info "Checking for gh CLI --repo flag compliance..."
  
  local violations=0
  
  # Find all gh/github_gh CLI calls in changed files
  while IFS= read -r file; do
    if grep -nE "(gh |github_gh )" "$file" | grep -v "^[[:space:]]*#" | grep -v "\-\-repo" >/dev/null 2>&1; then
      log_warn "❌ $file: gh CLI call without --repo flag"
      grep -nE "(gh |github_gh )" "$file" | grep -v "\-\-repo" | head -3
      (( violations++ ))
    fi
  done < <(git diff --cached --name-only --diff-filter=ACM | grep -E "\.(sh|bash|py)$" || true)
  
  return $violations
}

#
# Check for classic PAT tokens (ghp_*)
#
check_no_classic_pat() {
  log_info "Checking for classic PAT tokens..."
  
  local violations=0
  
  while IFS= read -r file; do
    if grep -n "ghp_\|GITHUB_TOKEN.*ghp_" "$file" >/dev/null 2>&1; then
      log_warn "❌ $file: Classic PAT token detected (ghp_*). Use fine-grained token (github_pat_*)"
      grep -n "ghp_" "$file" | head -3
      (( violations++ ))
    fi
  done < <(git diff --cached --name-only --diff-filter=ACM | grep -v ".git" || true)
  
  return $violations
}

#
# Check for hardcoded credentials
#
check_no_hardcoded_credentials() {
  log_info "Checking for hardcoded credentials..."
  
  local violations=0
  local patterns=(
    "GITHUB_TOKEN="
    "GH_TOKEN="
    "AWS_SECRET"
    "API_KEY="
    "api_key:"
    "password:"
    "secret:"
  )
  
  while IFS= read -r file; do
    for pattern in "${patterns[@]}"; do
      if grep -n "$pattern" "$file" | grep -v "^[[:space:]]*#" | grep -v "env\|ENV\|GSM\|gcloud\|secrets" >/dev/null 2>&1; then
        log_warn "❌ $file: Potential hardcoded credential ($pattern)"
        grep -n "$pattern" "$file" | head -2
        (( violations++ ))
      fi
    done
  done < <(git diff --cached --name-only --diff-filter=ACM | grep -E "\.(sh|bash|js|ts|py|env|yaml|yml)$" || true)
  
  return $violations
}

#
# Check for missing error handling on GitHub API calls
#
check_github_api_error_handling() {
  log_info "Checking for error handling on GitHub API calls..."
  
  local violations=0
  
  while IFS= read -r file; do
    # Look for curl/github_api_call without error handling
    if grep -n "github_api_call\|curl.*github.com" "$file" | grep -v "|| \||| \|if \||| {" >/dev/null 2>&1; then
      log_warn "❌ $file: GitHub API call without error handling"
      grep -n "github_api_call\|curl.*github.com" "$file" | grep -v "|| \||| \|if \||| {" | head -2
      (( violations++ ))
    fi
  done < <(git diff --cached --name-only --diff-filter=ACM | grep -E "\.(sh|bash|py)$" || true)
  
  return $violations
}

#
# Check for __common library usage
#
check_shared_library_usage() {
  log_info "Checking for use of shared libraries (github-api-client.sh, etc.)..."
  
  local violations=0
  
  # Warn if creating duplicate GitHub API handling instead of using shared lib
  while IFS= read -r file; do
    if grep -n "function github_\|def github_" "$file" | grep -v "_common/" >/dev/null 2>&1; then
      log_warn "⚠️  $file: Possible duplicate GitHub function (should use _common/github-api-client.sh)"
      grep -n "function github_\|def github_" "$file" | head -2
      # Not a hard violation, just warning
    fi
  done < <(git diff --cached --name-only --diff-filter=ACM | grep -E "\.(sh|bash|py)$" || true)
  
  return $violations
}

# ============================================================================
# Report Generation
# ============================================================================

#
# Generate governance violation report
#
generate_violation_report() {
  local total_violations=$1
  
  if (( total_violations == 0 )); then
    log_info "✅ All GitHub API governance checks passed!"
    return 0
  fi
  
  log_error "❌ GitHub API governance violations found: $total_violations"
  log_error ""
  log_error "Violations must be fixed before commit. Use:"
  log_error "  source scripts/_common/github-api-client.sh"
  log_error "  github_get_token          # Retrieve fine-grained token from GSM"
  log_error "  github_api_call GET/POST  # Make API calls with retry logic"
  log_error "  github_gh issue|pr        # Use gh CLI with wrapped error handling"
  log_error ""
  log_error "See: scripts/_common/github-api-client.sh for full API"
  
  return 1
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
  log_info "Running GitHub API governance checks..."
  
  local total_violations=0
  
  check_gh_repo_flag || (( total_violations += $? ))
  check_no_classic_pat || (( total_violations += $? ))
  check_no_hardcoded_credentials || (( total_violations += $? ))
  check_github_api_error_handling || (( total_violations += $? ))
  check_shared_library_usage || (( total_violations += $? ))
  
  generate_violation_report "$total_violations"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
