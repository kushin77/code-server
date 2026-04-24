#!/usr/bin/env bash
# @file        scripts/_common/issue-lifecycle-governor.sh
# @module      github/issue-lifecycle-governor
# @description GitHub issue lifecycle governance enforcement
#
# Enforces:
# - Every closed issue has linked PR or documented reason
# - Every issue has priority label (P0/P1/P2/P3)
# - Stale issues labeled and eventually closed
# - No PR merged without issue reference
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
source "$SCRIPT_DIR/_common/github-api-client.sh"

# ============================================================================
# Configuration
# ============================================================================

readonly STALE_DAYS=30
readonly STALE_AUTO_CLOSE_DAYS=14
readonly REQUIRED_PRIORITY_LABELS=("P0" "P1" "P2" "P3")

# ============================================================================
# Issue Validation
# ============================================================================

#
# Verify issue has required labels (priority)
#
issue_has_priority_label() {
  local issue_number="$1"
  local repo="${2:-kushin77/code-server}"
  
  local token
  token=$(github_get_token)
  
  local labels_response
  labels_response=$(github_api_call GET "/repos/$repo/issues/$issue_number/labels" || echo "[]")
  
  local has_priority=false
  for priority in "${REQUIRED_PRIORITY_LABELS[@]}"; do
    if echo "$labels_response" | jq -e ".[] | select(.name == \"$priority\")" >/dev/null 2>&1; then
      has_priority=true
      break
    fi
  done
  
  if ! $has_priority; then
    log_warn "Issue #$issue_number missing priority label (P0/P1/P2/P3)"
    return 1
  fi
  
  return 0
}

#
# Verify closed issue has linked PR or close reason
#
closed_issue_has_resolution() {
  local issue_number="$1"
  local repo="${2:-kushin77/code-server}"
  
  local token
  token=$(github_get_token)
  
  # Get issue state and body
  local issue_response
  issue_response=$(github_api_call GET "/repos/$repo/issues/$issue_number" || echo "{}")
  
  local state body
  state=$(echo "$issue_response" | jq -r '.state // "open"')
  body=$(echo "$issue_response" | jq -r '.body // ""')
  
  if [[ "$state" != "closed" ]]; then
    return 0  # Not closed, skip check
  fi
  
  # Check if body contains close reason pattern
  if echo "$body" | grep -qiE "(closed|fixed|resolved|wontfix|duplicate)"; then
    return 0
  fi
  
  # Check for linked PRs
  local prs_response
  prs_response=$(github_api_call GET "/repos/$repo/issues/$issue_number/timeline" || echo "[]")
  
  if echo "$prs_response" | jq -e ".[] | select(.event == \"cross-referenced\" and .source.type == \"pull_request\")" >/dev/null 2>&1; then
    return 0
  fi
  
  log_warn "Closed issue #$issue_number has no linked PR or close reason documented"
  return 1
}

#
# Verify PR has issue reference in title or description
#
pr_has_issue_reference() {
  local pr_number="$1"
  local repo="${2:-kushin77/code-server}"
  
  local token
  token=$(github_get_token)
  
  local pr_response
  pr_response=$(github_api_call GET "/repos/$repo/pulls/$pr_number" || echo "{}")
  
  local title body
  title=$(echo "$pr_response" | jq -r '.title // ""')
  body=$(echo "$pr_response" | jq -r '.body // ""')
  
  # Check for issue references (#N, Fixes #N, etc.)
  if echo "$title $body" | grep -qE "#[0-9]+|Fixes|Closes|Resolves"; then
    return 0
  fi
  
  log_warn "PR #$pr_number missing issue reference (use #N or 'Fixes #N')"
  return 1
}

# ============================================================================
# Stale Issue Detection & Automation
# ============================================================================

#
# Find stale issues (no activity in STALE_DAYS)
#
find_stale_issues() {
  local repo="${1:-kushin77/code-server}"
  
  local token
  token=$(github_get_token)
  
  log_info "Finding stale issues (no activity in last $STALE_DAYS days)..."
  
  local cutoff_date
  cutoff_date=$(date -u -d "$STALE_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)
  
  local query="repo:$repo is:open updated:<$cutoff_date sort:updated-asc"
  
  github_api_call GET "/search/issues?q=$query&per_page=100" | jq '.items[] | {number, title, updated_at, labels}'
}

#
# Label issue as stale and add comment
#
mark_issue_stale() {
  local issue_number="$1"
  local repo="${2:-kushin77/code-server}"
  
  local token
  token=$(github_get_token)
  
  log_info "Marking issue #$issue_number as stale..."
  
  # Add stale label
  github_api_call PATCH "/repos/$repo/issues/$issue_number" \
    "{\"labels\": [\"stale\"]}" || log_error "Failed to add stale label"
  
  # Add comment
  local comment="⏰ This issue has had no activity for $STALE_DAYS days. It will be automatically closed in $STALE_AUTO_CLOSE_DAYS days unless there is new activity."
  github_api_call POST "/repos/$repo/issues/$issue_number/comments" \
    "{\"body\": \"$comment\"}" || log_error "Failed to add stale comment"
  
  log_info "✓ Issue #$issue_number marked as stale"
}

#
# Auto-close stale issues that have been stale for STALE_AUTO_CLOSE_DAYS
#
auto_close_stale_issues() {
  local repo="${1:-kushin77/code-server}"
  
  local token
  token=$(github_get_token)
  
  log_info "Auto-closing stale issues (stale for $STALE_AUTO_CLOSE_DAYS days)..."
  
  local cutoff_date
  cutoff_date=$(date -u -d "$((STALE_DAYS + STALE_AUTO_CLOSE_DAYS)) days ago" +%Y-%m-%dT%H:%M:%SZ)
  
  local query="repo:$repo is:open label:stale updated:<$cutoff_date sort:updated-asc"
  
  local issue_numbers
  issue_numbers=$(github_api_call GET "/search/issues?q=$query&per_page=100" | jq -r '.items[].number')
  
  local count=0
  while IFS= read -r issue_number; do
    if [[ -n "$issue_number" ]]; then
      log_info "Auto-closing stale issue #$issue_number..."
      
      github_api_call PATCH "/repos/$repo/issues/$issue_number" \
        "{\"state\": \"closed\", \"state_reason\": \"not_planned\"}" || log_error "Failed to close issue #$issue_number"
      
      (( count++ ))
    fi
  done <<< "$issue_numbers"
  
  log_info "✓ Auto-closed $count stale issues"
}

# ============================================================================
# Lifecycle Governance Reports
# ============================================================================

#
# Generate lifecycle compliance report
#
generate_lifecycle_report() {
  local repo="${1:-kushin77/code-server}"
  
  local token
  token=$(github_get_token)
  
  log_info "Generating issue lifecycle compliance report..."
  
  # Count issues without priority labels
  local query_no_priority="repo:$repo is:issue -label:P0 -label:P1 -label:P2 -label:P3"
  local no_priority_count
  no_priority_count=$(github_api_call GET "/search/issues?q=$query_no_priority" | jq '.total_count')
  
  # Count closed issues without linked PR
  local query_no_pr="repo:$repo is:closed -linked:pr"
  local no_pr_count
  no_pr_count=$(github_api_call GET "/search/issues?q=$query_no_pr" | jq '.total_count')
  
  # Count stale issues
  local query_stale="repo:$repo label:stale"
  local stale_count
  stale_count=$(github_api_call GET "/search/issues?q=$query_stale" | jq '.total_count')
  
  cat <<EOF
# Issue Lifecycle Governance Report
Generated: $(date)
Repository: $repo

## Compliance Status
- Issues without priority label: $no_priority_count ⚠️
- Closed issues without linked PR: $no_pr_count ⚠️
- Stale issues: $stale_count

## Recommendations
1. Review and label $no_priority_count issues with priority (P0/P1/P2/P3)
2. Link PRs to $no_pr_count closed issues or document close reason
3. Review $stale_count stale issues for closure or re-engagement
EOF
}

# ============================================================================
# Exports
# ============================================================================

export -f issue_has_priority_label
export -f closed_issue_has_resolution
export -f pr_has_issue_reference
export -f find_stale_issues
export -f mark_issue_stale
export -f auto_close_stale_issues
export -f generate_lifecycle_report

# ============================================================================
# Main Entry Point
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-help}" in
    check-priority)
      # Usage: ./issue-lifecycle-governor.sh check-priority <issue_number>
      issue_has_priority_label "${2:?Issue number required}"
      ;;
    check-resolution)
      # Usage: ./issue-lifecycle-governor.sh check-resolution <issue_number>
      closed_issue_has_resolution "${2:?Issue number required}"
      ;;
    check-pr-reference)
      # Usage: ./issue-lifecycle-governor.sh check-pr-reference <pr_number>
      pr_has_issue_reference "${2:?PR number required}"
      ;;
    find-stale)
      find_stale_issues "${2:-kushin77/code-server}"
      ;;
    mark-stale)
      mark_issue_stale "${2:?Issue number required}" "${3:-kushin77/code-server}"
      ;;
    auto-close-stale)
      auto_close_stale_issues "${2:-kushin77/code-server}"
      ;;
    report)
      generate_lifecycle_report "${2:-kushin77/code-server}"
      ;;
    help|*)
      cat <<EOF
Issue Lifecycle Governor

Usage:
  ./issue-lifecycle-governor.sh check-priority <issue_num>   Check priority label
  ./issue-lifecycle-governor.sh check-resolution <issue_num> Check closed issue has resolution
  ./issue-lifecycle-governor.sh check-pr-reference <pr_num>  Check PR has issue reference
  ./issue-lifecycle-governor.sh find-stale [repo]            Find stale issues
  ./issue-lifecycle-governor.sh mark-stale <issue_num> [repo] Mark issue as stale
  ./issue-lifecycle-governor.sh auto-close-stale [repo]      Auto-close stale issues
  ./issue-lifecycle-governor.sh report [repo]                Generate compliance report
EOF
      ;;
  esac
fi
