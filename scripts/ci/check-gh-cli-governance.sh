#!/usr/bin/env bash
# @file        scripts/ci/check-gh-cli-governance.sh
# @module      ci/gh-cli-governance
# @description GOV-002 guard: enforce unified gh CLI usage and block direct calls
# @governance  GOV-002: GitHub CLI calls must use shared wrappers and repo-scoped execution
# @usage       check-gh-cli-governance.sh [all|direct|wrappers|endpoints|report]
set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

readonly VIOLATIONS_FILE=".gh-cli-violations.json"

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

# Scan for direct gh CLI usage violations
check_direct_gh_usage() {
  log_info "Checking for direct gh CLI usage violations..."
  
  local violations=0
  local -a violation_list=()
  
  # Find all shell scripts and YAML files with "gh " usage
  local files
  files=$(find . -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.yaml" \) \
    -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./dist/*" 2>/dev/null)
  
  while IFS= read -r file; do
    # Skip this file itself
    [[ "$file" == *"check-gh-cli-governance.sh" ]] && continue
    # Skip the approved unified issue helper
    [[ "$file" == *"issue-create-unified.sh" ]] && continue
    # Skip the approved GH wrapper helper
    [[ "$file" == *"gh-wrapper.sh" ]] && continue
    # Skip the approved repo-flag governance helper
    [[ "$file" == *"check-gh-repo-flag.sh" ]] && continue
    # Skip the audit fixture that intentionally documents direct gh usage examples
    [[ "$file" == *"audit-github-cli-usage.sh" ]] && continue
    
    # Look for direct gh command usage (not in comments)
    while IFS= read -r line_num line_content; do
      # Skip comments and github_gh function calls (which are wrapped)
      if [[ "$line_content" =~ ^[[:space:]]*# ]] || [[ "$line_content" =~ github_gh ]]; then
        continue
      fi
      
      # Check if line has direct "gh " usage (not wrapped in error handling)
      if [[ "$line_content" =~ [^_]gh[[:space:]] || "$line_content" =~ ^gh[[:space:]] ]] && ! [[ "$line_content" =~ \|\| ]]; then
        log_warn "Direct gh usage at $file:$line_num: $line_content"
        violation_list+=("{\"file\": $(json_escape "$file"), \"line\": $line_num, \"content\": $(json_escape "$line_content")}")
        violations+=1
      fi
    done < <(grep -n "gh " "$file" 2>/dev/null || true)
  done <<< "$files"
  
  # Generate JSON report
  if [[ $violations -gt 0 ]]; then
    local repo timestamp json_violations
    repo="${REPO:-kushin77/code-server}"
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    json_violations=$(IFS=,; echo "${violation_list[*]}")

    cat > "$VIOLATIONS_FILE" <<EOF
{
  "timestamp": "$timestamp",
  "repo": "$repo",
  "violation_count": $violations,
  "violations": [${json_violations}]
}
EOF
    log_error "Found $violations direct gh CLI usage violations (see $VIOLATIONS_FILE)"
    return 1
  fi
  
  log_info "✓ No direct gh CLI violations found"
  return 0
}

# Verify unified wrapper functions exist
check_wrapper_functions() {
  log_info "Checking for unified wrapper functions..."
  
  local wrappers=(
    "github_gh"
    "github_api_call"
    "github_get_token"
  )
  
  local missing=0
  
  for wrapper in "${wrappers[@]}"; do
    if ! grep -q "^$wrapper()" scripts/_common/github-*.sh 2>/dev/null; then
      log_warn "Wrapper function not found: $wrapper"
      missing+=1
    else
      log_info "✓ Found wrapper: $wrapper"
    fi
  done
  
  [[ $missing -eq 0 ]] && return 0 || return 1
}

# Check for hardcoded GitHub endpoints (should use wrappers)
check_hardcoded_endpoints() {
  log_info "Checking for hardcoded GitHub API endpoints..."
  
  local violations=0
  
  # Look for direct curl/wget to api.github.com (should use github_api_call)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ github-api-client\.sh: ]] && continue
    [[ "$line" =~ github-token-rotation\.sh: ]] && continue
    [[ "$line" =~ ^[^:]+:[0-9]+:[[:space:]]*# ]] && continue
    log_warn "Hardcoded GitHub API endpoint: $line"
    violations+=1
  done < <(grep -rn "api\.github\.com\|https://github\.com/api" --include="*.sh" . 2>/dev/null || true)
  
  if [[ $violations -gt 0 ]]; then
    log_error "Found $violations hardcoded GitHub API endpoints"
    return 1
  fi
  
  log_info "✓ No hardcoded GitHub API endpoints found"
  return 0
}

# Generate governance report
generate_governance_report() {
  log_info "Generating gh CLI governance report..."
  
  local report_file="gh-cli-governance-report.json"
  
  # Run all checks and collect results
  local direct_check=0 wrapper_check=0 endpoints_check=0
  
  check_direct_gh_usage || direct_check=$?
  check_wrapper_functions || wrapper_check=$?
  check_hardcoded_endpoints || endpoints_check=$?
  
  local repo timestamp
  repo="${REPO:-kushin77/code-server}"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local passed="true"

  [[ $direct_check -eq 0 && $wrapper_check -eq 0 && $endpoints_check -eq 0 ]] || passed="false"

  cat > "$report_file" <<EOF
{
  "timestamp": "$timestamp",
  "repo": "$repo",
  "checks": {
    "direct_gh_usage": $direct_check,
    "wrapper_functions": $wrapper_check,
    "hardcoded_endpoints": $endpoints_check
  },
  "passed": $passed
}
EOF
  log_info "✓ Governance report: $report_file"
  
  # Return fail if any check failed
  [[ $direct_check -eq 0 ]] && [[ $wrapper_check -eq 0 ]] && [[ $endpoints_check -eq 0 ]]
}

export -f check_direct_gh_usage check_wrapper_functions check_hardcoded_endpoints generate_governance_report

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-all}" in
    all)
      check_direct_gh_usage && check_wrapper_functions && check_hardcoded_endpoints && generate_governance_report
      ;;
    direct) check_direct_gh_usage ;;
    wrappers) check_wrapper_functions ;;
    endpoints) check_hardcoded_endpoints ;;
    report) generate_governance_report ;;
    *) echo "Usage: $0 {all|direct|wrappers|endpoints|report}" ;;
  esac
fi
