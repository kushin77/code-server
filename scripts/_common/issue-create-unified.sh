#!/usr/bin/env bash
# @file        scripts/_common/issue-create-unified.sh
# @module      governance/issue-management
# @description Unified, organization-wide GitHub issue creation with deduplication, label enforcement, and Copilot integration
#
# GOVERNANCE MANDATE (kushin77/code-server):
# - ALL issue creation MUST use this script (no direct 'gh issue create' calls)
# - Enforced across all repos/workspaces/users
# - Automatic deduplication prevents duplicate issues
# - Label validation prevents label-less issues
# - Seamless Copilot integration via copilot-issue-wrapper()
#
# USAGE:
#   source scripts/_common/issue-create-unified.sh
#   copilot_create_issue \
#     --title "Issue Title" \
#     --body "Issue description" \
#     --priority P1 \
#     --type "feature" \
#     [--labels "label1,label2"] \
#     [--repo "kushin77/code-server"] \
#     [--check-duplicates] \
#     [--dry-run]

set -euo pipefail

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/config.sh"

# ============================================================================
# CONFIGURATION & CONSTANTS
# ============================================================================

# Default repository (override via env var or parameter)
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"

# Priority levels and their corresponding labels
declare -A PRIORITY_LABELS=(
    [P0]="P0"
    [P1]="P1"
    [P2]="P2"
    [P3]="P3"
)

# Issue type to labels mapping
declare -A TYPE_LABELS=(
    [feature]="enhancement"
    [bug]="bug"
    [fix]="bug"
    [refactor]="refactor"
    [docs]="documentation"
    [infrastructure]="infrastructure"
    [security]="security"
    [ops]="ops"
    [testing]="testing"
    [performance]="performance"
    [accessibility]="accessibility"
)

# Production priority indicators (P0/P1 must be addressed before new features)
declare -a PRODUCTION_PRIORITIES=("P0" "P1")

# Maximum issue title length
MAX_TITLE_LENGTH=200

# Deduplication cache file (temporary, valid for 1 hour)
DEDUP_CACHE="/tmp/gh-issue-dedup-cache-$(date +%s | cut -c1-5).json"
DEDUP_CACHE_TTL=3600

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Validate GitHub CLI is installed and authenticated
ensure_gh_cli() {
    if ! command -v gh &>/dev/null; then
        log_fatal "GitHub CLI (gh) not found. Install with: brew install gh (macOS) or apt install gh (Linux)"
    fi
    
    if ! gh auth status &>/dev/null; then
        log_fatal "GitHub CLI not authenticated. Run: gh auth login"
    fi
}

# Validate issue parameters
validate_parameters() {
    local title="$1"
    local priority="$2"
    local issue_type="$3"
    
    # Title validation
    if [[ -z "$title" ]]; then
        log_fatal "Issue title is required"
    fi
    
    if [[ ${#title} -gt $MAX_TITLE_LENGTH ]]; then
        log_fatal "Issue title exceeds $MAX_TITLE_LENGTH characters: $title"
    fi
    
    # Priority validation
    if [[ -z "$priority" ]]; then
        log_fatal "Priority is required (P0, P1, P2, or P3)"
    fi
    
    if [[ ! -v PRIORITY_LABELS["$priority"] ]]; then
        local -a valid_priorities=("${!PRIORITY_LABELS[@]}")
        log_fatal "Invalid priority: $priority (valid: ${valid_priorities[*]})"
    fi
    
    # Type validation
    if [[ -n "$issue_type" && ! -v TYPE_LABELS["$issue_type"] ]]; then
        log_warn "Unknown issue type '$issue_type', will use as-is"
    fi
}

# Build label array from priority + type + custom labels
build_labels() {
    local priority="$1"
    local issue_type="$2"
    local custom_labels="$3"
    local -a labels=()
    
    # Add priority label
    labels+=("${PRIORITY_LABELS[$priority]}")
    
    # Add type label if specified
    if [[ -n "$issue_type" && -v TYPE_LABELS["$issue_type"] ]]; then
        labels+=("${TYPE_LABELS[$issue_type]}")
    fi
    
    # Add custom labels if provided
    if [[ -n "$custom_labels" ]]; then
        IFS=',' read -ra CUSTOM <<< "$custom_labels"
        for label in "${CUSTOM[@]}"; do
            label="${label// /}"  # Trim whitespace
            if [[ -n "$label" ]]; then
                labels+=("$label")
            fi
        done
    fi
    
    # Remove duplicates
    local -a unique_labels=()
    for label in "${labels[@]}"; do
        if [[ ! " ${unique_labels[*]} " =~ " ${label} " ]]; then
            unique_labels+=("$label")
        fi
    done
    
    # Output comma-separated labels
    (IFS=,; echo "${unique_labels[*]}")
}

# Check for duplicate issues before creation
check_for_duplicates() {
    local title="$1"
    local repo="$2"
    
    log_info "Checking for duplicate issues with title: $title"
    
    # Search for similar titles in open issues
    local search_result
    search_result=$(gh issue list \
        --repo "$repo" \
        --state open \
        --json title,number,url \
        --limit 100 \
        2>/dev/null || echo "[]")
    
    # Simple title matching (first 50 chars)
    local title_prefix="${title:0:50}"
    
    # Use jq to search if available, otherwise grep
    if command -v jq &>/dev/null; then
        local duplicates
        duplicates=$(echo "$search_result" | jq ".[] | select(.title | startswith(\"$title_prefix\")) | .number" 2>/dev/null | head -5)
        
        if [[ -n "$duplicates" ]]; then
            log_warn "Found similar open issues:"
            while read -r num; do
                log_warn "  - Issue #$num"
            done <<< "$duplicates"
            return 1  # Duplicate found
        fi
    fi
    
    return 0  # No duplicates found
}

# Create GitHub issue with validation
github_issue_create() {
    local title="$1"
    local body="$2"
    local labels="$3"
    local repo="$4"
    local check_dups="${5:-true}"
    local dry_run="${6:-false}"
    
    # Validate inputs
    validate_parameters "$title" "" ""
    
    # Check for duplicates if enabled
    if [[ "$check_dups" == "true" ]]; then
        if ! check_for_duplicates "$title" "$repo"; then
            log_warn "Skipping creation due to potential duplicates. Use --force-create to bypass."
            return 1
        fi
    fi
    
    # Build gh command
    local gh_cmd="gh issue create --repo $repo --title \"$title\""
    
    # Add body if provided
    if [[ -n "$body" ]]; then
        gh_cmd="$gh_cmd --body \"$body\""
    fi
    
    # Add labels
    if [[ -n "$labels" ]]; then
        gh_cmd="$gh_cmd --label \"$labels\""
    fi
    
    # Dry run: just show what would be executed
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $gh_cmd"
        return 0
    fi
    
    # Execute issue creation
    log_info "Creating issue in $repo: $title"
    local issue_url
    issue_url=$(eval "$gh_cmd" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log_info "✓ Issue created: $issue_url"
        echo "$issue_url"
        return 0
    else
        log_fatal "Failed to create issue: $issue_url"
    fi
}

# ============================================================================
# PUBLIC API: COPILOT INTEGRATION
# ============================================================================

# Main issue creation function (for Copilot wrapper)
copilot_create_issue() {
    local title=""
    local body=""
    local priority=""
    local type=""
    local labels=""
    local repo="$GITHUB_REPO"
    local check_dups="true"
    local force_create="false"
    local dry_run="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title)
                title="$2"
                shift 2
                ;;
            --body)
                body="$2"
                shift 2
                ;;
            --priority)
                priority="$2"
                shift 2
                ;;
            --type)
                type="$2"
                shift 2
                ;;
            --labels)
                labels="$2"
                shift 2
                ;;
            --repo)
                repo="$2"
                shift 2
                ;;
            --check-duplicates)
                check_dups="true"
                shift
                ;;
            --force-create)
                force_create="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            *)
                log_fatal "Unknown option: $1"
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$title" ]]; then
        log_fatal "Missing required parameter: --title"
    fi
    
    if [[ -z "$priority" ]]; then
        log_fatal "Missing required parameter: --priority (P0/P1/P2/P3)"
    fi
    
    # Validate priority
    validate_parameters "$title" "$priority" "$type"
    
    # Build final labels
    local final_labels
    final_labels=$(build_labels "$priority" "$type" "$labels")
    
    log_info "Issue Parameters:"
    log_info "  Title: $title"
    log_info "  Priority: $priority"
    log_info "  Type: $type"
    log_info "  Labels: $final_labels"
    log_info "  Repository: $repo"
    
    # Create issue
    if [[ "$force_create" == "true" ]]; then
        github_issue_create "$title" "$body" "$final_labels" "$repo" "false" "$dry_run"
    else
        github_issue_create "$title" "$body" "$final_labels" "$repo" "$check_dups" "$dry_run"
    fi
}

# ============================================================================
# PRODUCTION PRIORITY ENFORCEMENT
# ============================================================================

# Check if Copilot should prioritize production issues
should_prioritize_production() {
    local repo="$1"
    
    log_info "Scanning for P0/P1 issues in $repo..."
    
    local p0_count
    local p1_count
    
    p0_count=$(gh issue list --repo "$repo" --state open --label P0 --json number 2>/dev/null | wc -l)
    p1_count=$(gh issue list --repo "$repo" --state open --label P1 --json number 2>/dev/null | wc -l)
    
    if [[ $p0_count -gt 0 ]] || [[ $p1_count -gt 0 ]]; then
        log_warn "⚠️  PRODUCTION PRIORITY: Found P0=$p0_count, P1=$p1_count issues"
        log_warn "Copilot should focus on these before new features"
        return 0
    fi
    
    return 1
}

# List all production-priority open issues
list_production_priorities() {
    local repo="$1"
    
    log_info "Production Priority Issues:"
    for priority in "${PRODUCTION_PRIORITIES[@]}"; do
        local count
        count=$(gh issue list --repo "$repo" --state open --label "$priority" --json "number,title" 2>/dev/null | wc -l)
        
        if [[ $count -gt 0 ]]; then
            log_info ""
            log_info "=== $priority Issues ($count) ==="
            gh issue list --repo "$repo" --state open --label "$priority" --limit 10 --json "number,title,createdAt"
        fi
    done
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

# Ensure gh CLI is available
ensure_gh_cli

# Export functions for external use
export -f copilot_create_issue
export -f should_prioritize_production
export -f list_production_priorities
