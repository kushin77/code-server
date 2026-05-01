#!/bin/bash
###############################################################################
# @file        scripts/integration/gitlab-sync.sh
# @module      integration/gitlab-sync
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
#
# @file scripts/integration/gitlab-sync.sh
# @description Idempotent GitHub → GitLab issue synchronization
# @governance GOV-002: Version-controlled, audit-logged, reversible
# @author GitHub Copilot
# @created 2026-04-25
#
# Usage:
#   bash scripts/integration/gitlab-sync.sh [--dry-run] [--force] [--full-reset]
#
# Environment Variables:
#   GITLAB_INSTANCE    - GitLab instance URL (default: https://gitlab.com)
#   GITLAB_TOKEN       - GitLab personal access token (required)
#   GITLAB_PROJECT_ID  - GitLab project ID (required)
#   GITHUB_TOKEN       - GitHub personal access token (default: gh auth token)
#

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Configuration
readonly SCRIPT_VERSION="1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly LOG_DIR="${REPO_ROOT}/artifacts/sync-logs"
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly LOG_FILE="${LOG_DIR}/gitlab-sync-${TIMESTAMP}.log"

# Environment variables
readonly GITLAB_INSTANCE="${GITLAB_INSTANCE:-https://gitlab.com}"
readonly GITLAB_TOKEN="${GITLAB_TOKEN:-}"
readonly GITLAB_PROJECT_ID="${GITLAB_PROJECT_ID:-}"
readonly SYNC_BATCH_SIZE="${SYNC_BATCH_SIZE:-100}"
readonly SYNC_RETRY_COUNT="${SYNC_RETRY_COUNT:-3}"
readonly DRY_RUN="${DRY_RUN:-false}"

# Parse command line arguments
FORCE_SYNC=false
FULL_RESET=false
MODE="sync"

for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        --force) FORCE_SYNC=true ;;
        --full-reset) FULL_RESET=true; FORCE_SYNC=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# Logging functions
mkdir -p "$LOG_DIR"

log_info() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg" | tee -a "$LOG_FILE" >&2
}

log_success() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

# Validation functions
validate_environment() {
    log_info "Validating environment..."
    
    [ -n "$GITLAB_TOKEN" ] || { log_error "GITLAB_TOKEN not set"; exit 1; }
    [ -n "$GITLAB_PROJECT_ID" ] || { log_error "GITLAB_PROJECT_ID not set"; exit 1; }
    
    # Verify GitHub access
    if ! gh auth status &>/dev/null; then
        log_error "GitHub authentication failed"
        exit 1
    fi
    
    # Verify GitLab access
    local gitlab_response
    gitlab_response=$(curl -s -o /dev/null -w "%{http_code}" \
        "${GITLAB_INSTANCE}/api/v4/projects/${GITLAB_PROJECT_ID}" \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}")
    
    if [ "$gitlab_response" != "200" ]; then
        log_error "GitLab authentication failed (HTTP $gitlab_response)"
        exit 1
    fi
    
    log_success "Environment validated"
}

# Fetch functions
fetch_github_issues() {
    log_info "Fetching GitHub issues..."
    
    local output_file="${LOG_DIR}/github-issues-${TIMESTAMP}.json"
    
    # Fetch all open and closed issues (limit 10000)
    gh issue list \
        --repo kushin77/code-server \
        --limit 10000 \
        --state all \
        --json number,title,body,state,labels,createdAt,updatedAt,author \
        > "$output_file"
    
    local count=$(jq 'length' "$output_file")
    log_info "Fetched $count GitHub issues"
    echo "$output_file"
}

fetch_gitlab_issues() {
    log_info "Fetching GitLab issues..."
    
    local output_file="${LOG_DIR}/gitlab-issues-${TIMESTAMP}.json"
    local page=1
    local per_page=200
    > "$output_file"  # Clear file
    
    # Paginate through all issues
    while true; do
        local response
        response=$(curl -s \
            "${GITLAB_INSTANCE}/api/v4/projects/${GITLAB_PROJECT_ID}/issues?page=${page}&per_page=${per_page}" \
            --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}")
        
        local count=$(echo "$response" | jq 'length')
        if [ "$count" -eq 0 ]; then
            break
        fi
        
        echo "$response" | jq -s 'add' >> "$output_file"
        page=$((page + 1))
    done
    
    local total=$(jq 'length' "$output_file" 2>/dev/null || echo 0)
    log_info "Fetched $total GitLab issues"
    echo "$output_file"
}

# Sync functions
sync_issues() {
    local github_issues_file=$1
    local gitlab_issues_file=$2
    
    log_info "Starting issue synchronization..."
    
    local github_count=$(jq 'length' "$github_issues_file")
    local stats_created=0
    local stats_updated=0
    local stats_skipped=0
    local stats_failed=0
    
    # Process each GitHub issue
    jq -c '.[]' "$github_issues_file" | while read -r issue; do
        local github_number=$(echo "$issue" | jq -r '.number')
        local github_title=$(echo "$issue" | jq -r '.title')
        local github_state=$(echo "$issue" | jq -r '.state')
        
        log_info "Processing GitHub issue #$github_number..."
        
        # Check if already in GitLab
        local gitlab_issue=$(jq --arg title "$github_title" '.[] | select(.title == $title)' "$gitlab_issues_file" 2>/dev/null)
        
        if [ -z "$gitlab_issue" ]; then
            # Create new issue
            if create_gitlab_issue "$issue"; then
                stats_created+=1
            else
                stats_failed+=1
            fi
        else
            # Update existing issue
            if update_gitlab_issue "$gitlab_issue" "$issue"; then
                stats_updated+=1
            else
                stats_failed+=1
            fi
        fi
    done
    
    log_success "Synchronization complete: $stats_created created, $stats_updated updated, $stats_skipped skipped, $stats_failed failed"
}

create_gitlab_issue() {
    local issue=$1
    
    local title=$(echo "$issue" | jq -r '.title')
    local description=$(echo "$issue" | jq -r '.body // "No description"')
    local state=$(echo "$issue" | jq -r '.state')
    local gitlab_state=$([ "$state" = "OPEN" ] && echo "opened" || echo "closed")
    
    local payload=$(jq -n \
        --arg title "$title" \
        --arg description "$description" \
        --arg state "$gitlab_state" \
        '{title: $title, description: $description, state: $state}')
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create issue: $title"
        return 0
    fi
    
    local response
    response=$(curl -s -X POST \
        "${GITLAB_INSTANCE}/api/v4/projects/${GITLAB_PROJECT_ID}/issues" \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "$payload")
    
    local http_code=$(echo "$response" | jq -r '.id // empty')
    if [ -n "$http_code" ]; then
        log_info "Created GitLab issue from $title"
        return 0
    else
        log_error "Failed to create GitLab issue: $title"
        return 1
    fi
}

update_gitlab_issue() {
    local gitlab_issue=$1
    local github_issue=$2
    
    local gitlab_id=$(echo "$gitlab_issue" | jq -r '.id')
    local github_state=$(echo "$github_issue" | jq -r '.state')
    local gitlab_state=$([ "$github_state" = "OPEN" ] && echo "opened" || echo "closed")
    
    # Check if update needed
    local current_gitlab_state=$(echo "$gitlab_issue" | jq -r '.state')
    if [ "$current_gitlab_state" = "$gitlab_state" ]; then
        log_info "GitLab issue #$gitlab_id already up-to-date, skipping"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would update issue #$gitlab_id to state: $gitlab_state"
        return 0
    fi
    
    local payload=$(jq -n \
        --arg state "$gitlab_state" \
        '{state_event: ($state == "closed" ? "close" : "reopen")}')
    
    local response
    response=$(curl -s -X PUT \
        "${GITLAB_INSTANCE}/api/v4/projects/${GITLAB_PROJECT_ID}/issues/${gitlab_id}" \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "$payload")
    
    local updated=$(echo "$response" | jq -r '.state // empty')
    if [ -n "$updated" ]; then
        log_info "Updated GitLab issue #$gitlab_id to state: $updated"
        return 0
    else
        log_error "Failed to update GitLab issue #$gitlab_id"
        return 1
    fi
}

# Full reset (warning: destructive)
full_reset() {
    if [ "$DRY_RUN" = false ]; then
        log_info "WARNING: Full reset will delete all GitLab issues. Proceeding in 10 seconds..."
        sleep 10
    fi
    
    log_info "Fetching all GitLab issues for deletion..."
    local issues=$(curl -s \
        "${GITLAB_INSTANCE}/api/v4/projects/${GITLAB_PROJECT_ID}/issues?per_page=500" \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" | jq -r '.[].id')
    
    local count=0
    for issue_id in $issues; do
        if [ "$DRY_RUN" = false ]; then
            curl -s -X DELETE \
                "${GITLAB_INSTANCE}/api/v4/projects/${GITLAB_PROJECT_ID}/issues/${issue_id}" \
                --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" > /dev/null
        fi
        count+=1
    done
    
    log_success "Full reset complete: deleted $count GitLab issues"
}

# Main
main() {
    log_info "=== GitLab Synchronization Started ==="
    log_info "Version: $SCRIPT_VERSION"
    log_info "Mode: $([ "$DRY_RUN" = true ] && echo "DRY-RUN" || echo "LIVE")"
    log_info "Log file: $LOG_FILE"
    
    validate_environment
    
    if [ "$FULL_RESET" = true ]; then
        full_reset
    fi
    
    local github_issues_file=$(fetch_github_issues)
    local gitlab_issues_file=$(fetch_gitlab_issues)
    
    sync_issues "$github_issues_file" "$gitlab_issues_file"
    
    log_info "=== GitLab Synchronization Complete ==="
    log_success "Sync artifacts: $LOG_DIR"
}

# Run main
main "$@"
