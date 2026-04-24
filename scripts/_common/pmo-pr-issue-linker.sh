#!/usr/bin/env bash
# @file        scripts/_common/pmo-pr-issue-linker.sh
# @module      pmo/pr-issue-linker
# @description Auto-link PRs to issues and auto-close on merge
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
source "$SCRIPT_DIR/_common/github-api-client.sh"

readonly REPO="${REPO:-kushin77/code-server}"

# Extract issue number from PR title or branch name
extract_issue_number() {
  local pr_number="$1"
  local token pr_response title body head_ref issue_num
  token=$(github_get_token)
  
  pr_response=$(github_api_call GET "/repos/$REPO/pulls/$pr_number" || echo "{}")
  title=$(echo "$pr_response" | jq -r '.title // ""')
  body=$(echo "$pr_response" | jq -r '.body // ""')
  head_ref=$(echo "$pr_response" | jq -r '.head.ref // ""')
  
  issue_num=$(echo "$title $body $head_ref" | grep -oE '#[0-9]+' | head -1 | sed 's/#//' || echo "")
  [[ -n "$issue_num" ]] && echo "$issue_num" && return 0 || return 1
}

# Link PR to issue
link_pr_to_issue() {
  local pr_number="$1" issue_number="$2"
  local token issue_response current_body
  token=$(github_get_token)
  
  log_info "Linking PR #$pr_number to Issue #$issue_number..."
  
  issue_response=$(github_api_call GET "/repos/$REPO/issues/$issue_number" || echo "{}")
  current_body=$(echo "$issue_response" | jq -r '.body // ""')
  
  if ! echo "$current_body" | grep -q "PR #$pr_number\|#$pr_number"; then
    local new_body="$current_body

---
**Related PR:** https://github.com/$REPO/pull/$pr_number"
    
    github_api_call PATCH "/repos/$REPO/issues/$issue_number" \
      "{\"body\": \"$new_body\"}" || log_error "Failed to link PR to issue"
  fi
  
  log_info "✓ PR #$pr_number linked to Issue #$issue_number"
}

# Auto-close issue when PR merges
auto_close_on_merge() {
  local pr_number="$1"
  local token pr_response merged_at state issue_number
  token=$(github_get_token)
  
  pr_response=$(github_api_call GET "/repos/$REPO/pulls/$pr_number" || echo "{}")
  merged_at=$(echo "$pr_response" | jq -r '.merged_at // "null"')
  state=$(echo "$pr_response" | jq -r '.state // "open"')
  
  [[ "$merged_at" == "null" ]] || [[ "$state" == "open" ]] && {
    log_info "PR #$pr_number not merged yet"
    return 0
  }
  
  issue_number=$(extract_issue_number "$pr_number") || {
    log_info "No linked issue for PR #$pr_number"
    return 0
  }
  
  log_info "Closing Issue #$issue_number (linked to merged PR #$pr_number)..."
  github_api_call PATCH "/repos/$REPO/issues/$issue_number" \
    "{\"state\": \"closed\", \"state_reason\": \"completed\"}" || log_error "Failed to close issue"
  
  log_info "✓ Issue #$issue_number closed"
}

# Link all open PRs
link_all_open_prs() {
  log_info "Processing all open PRs..."
  local token prs_response
  token=$(github_get_token)
  
  prs_response=$(github_api_call GET "/repos/$REPO/pulls?state=open&per_page=100" || echo "[]")
  echo "$prs_response" | jq -r '.[] | .number' | while read -r pr_number; do
    issue_number=$(extract_issue_number "$pr_number") && link_pr_to_issue "$pr_number" "$issue_number"
  done
  
  log_info "✓ All open PRs processed"
}

# Auto-close linked issues for recently merged PRs
auto_close_linked_issues() {
  log_info "Checking recently merged PRs..."
  local token since prs_response
  token=$(github_get_token)
  
  since=$(date -u -d "1 day ago" +%Y-%m-%dT%H:%M:%SZ)
  prs_response=$(github_api_call GET "/search/issues?q=repo:$REPO%20is:pr%20is:merged%20merged:>$since&per_page=100" || echo "{}")
  
  echo "$prs_response" | jq -r '.items[].number' | while read -r pr_number; do
    auto_close_on_merge "$pr_number"
  done
  
  log_info "✓ Recently merged PRs processed"
}

export -f extract_issue_number link_pr_to_issue auto_close_on_merge link_all_open_prs auto_close_linked_issues

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-help}" in
    link-pr) pr_number="${2:?PR number required}"; issue_number=$(extract_issue_number "$pr_number") || exit 1; link_pr_to_issue "$pr_number" "$issue_number" ;;
    auto-close) pr_number="${2:?PR number required}"; auto_close_on_merge "$pr_number" ;;
    link-all) link_all_open_prs ;;
    auto-close-all) auto_close_linked_issues ;;
    *) echo "Usage: $0 {link-pr|auto-close|link-all|auto-close-all}" ;;
  esac
fi
