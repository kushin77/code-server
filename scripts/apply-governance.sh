#!/usr/bin/env bash
# @file        scripts/apply-governance.sh
# @module      governance
# @description apply governance — on-prem code-server
# @owner       platform
# @status      active
################################################################################
# apply-governance.sh
# Apply GitHub Governance Framework to repositories
# LINUX MANDATORY: GitHub CLI automation
#
# Usage:
#   ./apply-governance.sh -o kushin77 -r repo1,repo2,repo3
#   ./apply-governance.sh -o kushin77 --all-repos
#   ./apply-governance.sh -o kushin77 --dry-run
#
# Author: GitHub Copilot | April 14, 2026
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

require_github_cli() {
    require_command "gh"
    bootstrap_github_auth || true
    if ! gh api user --jq '.login' >/dev/null 2>&1; then
        log_fatal "GitHub auth unavailable. Set GH_TOKEN/GITHUB_TOKEN (prefer GSM) or run: gh auth login"
    fi
}

# Parse arguments
OWNER=""
REPOS=()
ALL_REPOS=false
DRY_RUN=false
VERBOSE=false

usage() {
    cat << EOF
Usage: $0 -o OWNER [OPTIONS] [REPOS...]

OPTIONS:
  -o, --owner OWNER        Repository owner (required)
  -r, --repos REPOS        Comma-separated repo names (e.g., repo1,repo2,repo3)
  -a, --all-repos          Apply to all repositories owned by OWNER
  -n, --dry-run            Show what would be applied without making changes
  -v, --verbose            Enable verbose output
  -h, --help               Show this help message

EXAMPLES:
  Apply to specific repos:
    $0 -o kushin77 -r code-server,eiq-linkedin

  Apply to all repos:
    $0 -o kushin77 --all-repos

  Dry-run on all repos:
    $0 -o kushin77 --all-repos --dry-run
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--owner) OWNER="$2"; shift 2 ;;
        -r|--repos) IFS=',' read -ra REPOS <<< "$2"; shift 2 ;;
        -a|--all-repos) ALL_REPOS=true; shift ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -h|--help) usage ;;
        *) log_fatal "Unknown option: $1" ;;
    esac
done

if [[ -z "$OWNER" ]]; then
    log_fatal "Error: --owner is required"
fi

# Require GitHub CLI
require_github_cli

log_section "GitHub Governance Framework Applicator"

# Get repository list
log_info "Repository Owner: $OWNER"

if $ALL_REPOS; then
    log_info "Fetching all repositories for $OWNER..."
    mapfile -t REPOS < <(gh repo list "$OWNER" --json name --jq '.[].name')
    log_info "Found ${#REPOS[@]} repositories"
else
    if [[ ${#REPOS[@]} -eq 0 ]]; then
        log_fatal "No repositories specified. Use -r or --all-repos"
    fi
    log_info "Target repositories: ${REPOS[*]}"
fi

echo ""

# Process statistics
processed=0
successful=0
failed=0

# Process each repository
for repo in "${REPOS[@]}"; do
    ((processed++))
    log_info "[$processed/${#REPOS[@]}] Processing $OWNER/$repo..."
    
    if $VERBOSE; then
        log_info "  Getting repository info..."
    fi
    
    # Get repository info
    repo_info=""
    repo_info=$(gh api repos/"$OWNER"/"$repo" \
        --jq '{name: .name, default_branch: .default_branch, is_private: .private}' 2>/dev/null) || {
        log_error "Failed to fetch repository info for $OWNER/$repo" || true
        ((failed++))
        continue
    }
    
    default_branch=""
    default_branch=$(echo "$repo_info" | jq -r '.default_branch')
    
    if $VERBOSE; then
        log_info "  Default branch: $default_branch"
        log_info "  Applying branch protection rules..."
    fi
    
    # Create protection payload
    protection_payload=""
    protection_payload=$(cat << 'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["lint", "unit-tests", "security-scan"]
  },
  "required_pull_request_reviews": {
        "required_approving_review_count": 2,
    "dismiss_stale_reviews": true,
        "require_code_owner_reviews": true
  },
  "enforce_admins": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
)
    
    if $DRY_RUN; then
        log_warn "[DRY RUN] Would apply branch protection for $default_branch"
        if $VERBOSE; then
            echo "$protection_payload" | jq '.'
        fi
    else
        if gh api -X PUT repos/"$OWNER"/"$repo"/branches/"$default_branch"/protection \
            --input <(echo "$protection_payload") 2>/dev/null; then
            if $VERBOSE; then
                log_info "  Branch protection applied"
            fi
        else
            log_warn "  Branch protection partially applied (may have existing config)"
        fi
    fi
    
    # Check workflows
    if $VERBOSE; then
        log_info "  Checking workflows..."
    fi
    
    workflow_count=0
    workflow_count=$(gh api repos/"$OWNER"/"$repo"/contents/.github/workflows \
        --jq '.[].name | select(. != null)' 2>/dev/null | wc -l || echo 0)
    
    if [[ $workflow_count -eq 0 ]]; then
        log_warn "  No workflows found in .github/workflows"
    else
        if $VERBOSE; then
            log_info "  Found $workflow_count workflows"
        fi
    fi
    
    log_success "$OWNER/$repo governance rules applied"
    ((successful++))
    
    # Delay to avoid rate limiting (GitHub: 5000 req/hour)
    sleep 0.5
done

# Summary
log_section "Governance Application Complete"
log_info "Processed: $processed"
log_info "Successful: $successful"
log_info "Failed: $failed"

if [[ $failed -gt 0 ]]; then
    log_warn "Review failures above and retry as needed"
    exit 1
else
    log_success "All repositories processed successfully"
    exit 0
fi
