#!/bin/bash
# @file issue-create-unified.sh
# @module governance/issues
# @description Unified GitHub issue creation with governance-enforced labels and automation

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
DRY_RUN="${DRY_RUN:-false}"

# ============================================================================
# Validation
# ============================================================================
validate_token() {
    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo "❌ GITHUB_TOKEN not set" >&2
        return 1
    fi
}

validate_inputs() {
    local title="$1"
    local body="$2"
    local labels="$3"
    
    if [[ -z "$title" ]]; then
        echo "❌ Issue title required" >&2
        return 1
    fi
    
    if [[ ${#title} -lt 5 ]]; then
        echo "❌ Issue title must be at least 5 characters" >&2
        return 1
    fi
    
    # Validate labels contain at least one priority
    local has_priority=false
    for label in $(echo "$labels" | tr ',' '\n'); do
        [[ "$label" =~ ^P[0-3]$ ]] && has_priority=true
    done
    
    if [[ "$has_priority" != "true" ]]; then
        echo "❌ Labels must include priority (P0, P1, P2, or P3)" >&2
        return 1
    fi
}

# ============================================================================
# Deduplication
# ============================================================================
check_issue_exists() {
    local title="$1"
    
    # Search for similar open issues
    local result=$(gh issue list \
        --repo "$GITHUB_REPO" \
        --search "title:\"$title\" state:open" \
        --json title \
        --jq 'length' 2>/dev/null || echo "0")
    
    if [[ "$result" -gt 0 ]]; then
        echo "⚠️  Issue with similar title already exists" >&2
        return 1
    fi
}

# ============================================================================
# Issue Creation
# ============================================================================
create_issue() {
    local title="$1"
    local body="$2"
    local labels="$3"
    local assignees="${4:-}"
    
    echo "📝 Creating issue: $title"
    echo "   Labels: $labels"
    [[ -n "$assignees" ]] && echo "   Assignees: $assignees"
    
    local gh_cmd=(
        "gh" "issue" "create"
        "--repo" "$GITHUB_REPO"
        "--title" "$title"
        "--body" "$body"
        "--label" "$labels"
    )
    
    [[ -n "$assignees" ]] && gh_cmd+=("--assignee" "$assignees")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🧪 [DRY RUN] Would execute: ${gh_cmd[*]}"
        return 0
    fi
    
    local issue_url=$("${gh_cmd[@]}" 2>/dev/null || echo "failed")
    
    if [[ "$issue_url" == "failed" ]]; then
        echo "❌ Failed to create issue" >&2
        return 1
    fi
    
    echo "✅ Issue created: $issue_url"
}

# ============================================================================
# CLI Interface
# ============================================================================
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --title TEXT           Issue title (required)
    --body TEXT            Issue description
    --labels LABELS        Comma-separated labels (e.g., "P1,bug,enhancement")
                          Must include P0-P3 priority
    --assignees USERS      Comma-separated GitHub usernames
    --dry-run              Show what would be created without creating
    --help                 Show this help message

EXAMPLES:
    # Create P1 bug with automatic assignment
    $(basename "$0") \\
        --title "Fix authentication token rotation" \\
        --body "Token rotation failing after 90 days" \\
        --labels "P1,bug,security" \\
        --assignees "akushnir"
    
    # Create P2 feature request (dry-run)
    $(basename "$0") \\
        --title "Add Docker health checks" \\
        --body "Implement health checks for all services" \\
        --labels "P2,enhancement" \\
        --dry-run

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN        GitHub API token (required, use for authentication)
    GITHUB_REPO         Repository in owner/name format (default: kushin77/code-server)
    DRY_RUN             Set to 'true' for dry-run mode

EOF
}

# ============================================================================
# Main
# ============================================================================
main() {
    local title=""
    local body=""
    local labels=""
    local assignees=""
    
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
            --labels)
                labels="$2"
                shift 2
                ;;
            --assignees)
                assignees="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help)
                usage
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                return 1
                ;;
        esac
    done
    
    # Validation
    validate_token || return 1
    validate_inputs "$title" "$body" "$labels" || return 1
    check_issue_exists "$title" || return 1
    
    # Create
    create_issue "$title" "$body" "$labels" "$assignees" || return 1
}

main "$@"
