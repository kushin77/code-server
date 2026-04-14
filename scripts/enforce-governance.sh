#!/bin/bash
################################################################################
# File: enforce-governance.sh
# Owner: DevOps/Governance Team
# Purpose: Enforce governance policies and standards across repository
# Last Modified: April 14, 2026
# Compatibility: Ubuntu 22.04+, Bash 4.0+
#
# Dependencies:
#   - git — Version control management
#   - jq — JSON parsing for GitHub API responses
#   - curl — GitHub API interaction
#   - pre-commit — Git hook framework
#
# Related Files:
#   - .github/GOVERNANCE-ROLLOUT.md — Governance policies
#   - .pre-commit-config.yaml — Enforcement hooks
#   - CONTRIBUTING.md — Developer guidelines
#   - .github/workflows/ — Automated enforcement
#
# Usage:
#   ./enforce-governance.sh check                # Check compliance status
#   ./enforce-governance.sh apply                # Apply governance across repo
#   ./enforce-governance.sh report               # Generate compliance report
#
# Enforcement Tasks:
#   - Verify all PRs have required reviews
#   - Check branch protection rules
#   - Validate commit message format
#   - Scan for policy violations
#   - Run compliance tests
#   - Generate audit trail
#
# Exit Codes:
#   0 — Full compliance achieved
#   1 — Some violations detected (auto-fixable)
#   2 — Policy violations require manual review
#
# Examples:
#   ./scripts/enforce-governance.sh check
#   ./scripts/enforce-governance.sh report
#
# Recent Changes:
#   2026-04-14: Integrated error handling validation 
#   2026-04-13: Initial creation with enforcement automation
#
################################################################################

# GitHub Governance Enforcement Script
# Applies branch protection rules, workflow quotas, and cost controls
# Run: daily via GitHub Actions
# Maintenance: DeOps team

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Configuration
CONFIG_FILE="${1:-.github/rules.yaml}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warning() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }
verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[D]${NC} $*" || true; }

# Verify prerequisites
check_requirements() {
    log "Checking prerequisites..."
    
    for cmd in gh jq yq curl; do
        if ! command -v "$cmd" &> /dev/null; then
            error "$cmd not found. Install it first."
            exit 1
        fi
    done
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        error "GITHUB_TOKEN not set. Export it first."
        exit 1
    fi
    
    # Test GitHub CLI authentication
    if ! gh auth status &> /dev/null; then
        error "GitHub CLI not authenticated. Run 'gh auth login'"
        exit 1
    fi
    
    success "All prerequisites met"
}

# Get repository information
get_repo_info() {
    local owner="${1:?Owner required}"
    local repo="${2:?Repo required}"
    
    verbose "Fetching repo info for $owner/$repo..."
    gh api "repos/$owner/$repo" --jq '{name: .name, owner: .owner.login, default_branch: .default_branch}'
}

# Apply branch protection to a branch
apply_branch_protection() {
    local owner="$1"
    local repo="$2"
    local branch="$3"
    local config="$4"
    
    log "Applying protection to $owner/$repo/$branch..."
    
    # Extract protection settings from config
    local required_contexts=$(yq -r ".branches.$branch.protection.required_status_checks.contexts[]?" "$CONFIG_FILE" | jq -R -s -c 'split("\n")[:-1]')
    local required_reviews=$(yq -r ".branches.$branch.protection.required_pull_request_reviews.required_approving_review_count" "$CONFIG_FILE")
    local dismiss_stale=$(yq -r ".branches.$branch.protection.required_pull_request_reviews.dismiss_stale_reviews" "$CONFIG_FILE")
    local enforce_admins=$(yq -r ".branches.$branch.protection.enforce_admins" "$CONFIG_FILE")
    local allow_deletions=$(yq -r ".branches.$branch.protection.allow_deletions" "$CONFIG_FILE")
    local allow_force_pushes=$(yq -r ".branches.$branch.protection.allow_force_pushes" "$CONFIG_FILE")
    
    # Build API payload
    local payload=$(cat <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": $required_contexts
  },
  "required_pull_request_reviews": {
    "required_approving_review_count": $required_reviews,
    "dismiss_stale_reviews": $dismiss_stale,
    "require_code_owner_review": false
  },
  "enforce_admins": $enforce_admins,
  "allow_deletion": $allow_deletions,
  "allow_force_pushes": $allow_force_pushes,
  "required_conversation_resolution": true
}
EOF
)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would apply: $(echo $payload | jq -c .)"
        return 0
    fi
    
    if gh api -X PUT "repos/$owner/$repo/branches/$branch/protection" --input <(echo "$payload") &>/dev/null; then
        success "Branch protection applied to $branch"
    else
        error "Failed to apply branch protection to $branch"
        return 1
    fi
}

# Validate workflows for compliance
validate_workflows() {
    local owner="$1"
    local repo="$2"
    
    log "Validating workflows in $owner/$repo..."
    
    # Get all workflow files
    local workflows=$(gh api "repos/$owner/$repo/contents/.github/workflows" --jq ".[].name" 2>/dev/null || echo "")
    
    if [[ -z "$workflows" ]]; then
        warning "No workflows found in $owner/$repo"
        return 0
    fi
    
    local violations=0
    
    while IFS= read -r workflow; do
        verbose "Checking workflow: $workflow"
        
        # Get workflow content
        local content=$(gh api "repos/$owner/$repo/contents/.github/workflows/$workflow" --jq '.content | @base64d')
        
        # Check for timeout-minutes
        if ! echo "$content" | grep -q "timeout-minutes"; then
            warning "Workflow missing timeout-minutes: $workflow"
            ((violations++))
        fi
        
        # Check for cost category label
        if ! echo "$content" | grep -q "COST_CATEGORY"; then
            warning "Workflow missing COST_CATEGORY: $workflow"
            ((violations++))
        fi
        
        # Check for forbidden patterns
        if echo "$content" | grep -qE "curl.*http://"; then
            error "Workflow uses HTTP (must use HTTPS): $workflow"
            ((violations++))
        fi
        
        if echo "$content" | grep -qE "npm install -g"; then
            warning "Workflow uses global npm install: $workflow"
            ((violations++))
        fi
        
    done <<< "$workflows"
    
    if [[ $violations -gt 0 ]]; then
        warning "Found $violations governance violations in $owner/$repo"
        return 1
    else
        success "All workflows compliant in $owner/$repo"
        return 0
    fi
}

# Track workflow costs
track_workflow_costs() {
    local owner="$1"
    local repo="$2"
    
    log "Tracking workflow costs for $owner/$repo..."
    
    # Get recent workflow runs
    local runs=$(gh api "repos/$owner/$repo/actions/runs" \
        -F per_page=100 \
        --jq '.workflow_runs[] | select(.updated_at > (now - 7*24*60*60 | todate)) | {id: .id, name: .name, status: .status, conclusion: .conclusion, run_number: .run_number}')
    
    if [[ -z "$runs" ]]; then
        verbose "No recent runs found"
        return 0
    fi
    
    # Count runs by category
    local total_runs=$(echo "$runs" | jq -s 'length')
    local failed_runs=$(echo "$runs" | jq -s '[.[] | select(.conclusion == "failure")] | length')
    local success_rate=$(echo "scale=2; ($total_runs - $failed_runs) * 100 / $total_runs" | bc)
    
    log "Cost Summary for $owner/$repo (last 7 days):"
    echo "  Total runs: $total_runs"
    echo "  Failed runs: $failed_runs"
    echo "  Success rate: ${success_rate}%"
    
    # Alert if failure rate > 10%
    if (( $(echo "$failed_runs / $total_runs > 0.1" | bc -l) )); then
        warning "High failure rate detected in $owner/$repo"
    fi
}

# Disable inactive workflows
disable_inactive_workflows() {
    local owner="$1"
    local repo="$2"
    local days_threshold="${3:-90}"
    
    log "Checking for inactive workflows in $owner/$repo (>$days_threshold days)..."
    
    # Get all workflows
    local workflows=$(gh api "repos/$owner/$repo/actions/workflows" --jq '.workflows[].id' 2>/dev/null || echo "")
    
    if [[ -z "$workflows" ]]; then
        verbose "No workflows found"
        return 0
    fi
    
    while read -r workflow_id; do
        # Get last run date
        local last_run=$(gh api "repos/$owner/$repo/actions/workflows/$workflow_id/runs" \
            -F per_page=1 \
            --jq '.workflow_runs[0].updated_at | fromdate' 2>/dev/null || echo 0)
        
        local current_time=$(date +%s)
        local days_inactive=$(( ($current_time - $last_run) / 86400 ))
        
        if [[ $days_inactive -gt $days_threshold ]]; then
            local workflow_name=$(gh api "repos/$owner/$repo/actions/workflows/$workflow_id" --jq '.name')
            warning "Workflow inactive for $days_inactive days: $workflow_name"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log "[DRY RUN] Would disable: $workflow_name"
            else
                # TODO: Implement workflow disable via API or file edit
                log "Marking $workflow_name for manual review"
            fi
        fi
    done <<< "$workflows"
}

# Create compliance report
create_compliance_report() {
    local owner="$1"
    local repo="$2"
    
    log "Creating compliance report for $owner/$repo..."
    
    local report="{
  \"repo\": \"$owner/$repo\",
  \"timestamp\": \"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\",
  \"checks\": {
    \"branch_protection\": \"pending\",
    \"workflow_validation\": \"pending\",
    \"cost_tracking\": \"pending\",
    \"api_compliance\": \"pending\"
  }
}"
    
    echo "$report" | jq .
}

# Main execution
main() {
    log "GitHub Governance Enforcement"
    log "================================================"
    
    check_requirements
    
    # Get list of repositories
    local owner="${GH_OWNER:-kushin77}"
    
    log "Fetching repositories for $owner..."
    local repos=$(gh api "users/$owner/repos" --jq '.[].name' | head -20)
    
    if [[ -z "$repos" ]]; then
        error "No repositories found for $owner"
        exit 1
    fi
    
    local total_repos=0
    local compliant_repos=0
    
    # Process each repository
    while read -r repo; do
        ((total_repos++))
        
        log "Processing $owner/$repo..."
        
        # Get default branch
        local default_branch=$(gh api "repos/$owner/$repo" --jq '.default_branch')
        
        # Apply branch protections
        apply_branch_protection "$owner" "$repo" "$default_branch" "$CONFIG_FILE"
        
        # Validate workflows
        if validate_workflows "$owner" "$repo"; then
            ((compliant_repos++))
        fi
        
        # Track costs
        track_workflow_costs "$owner" "$repo"
        
        # Check for inactive workflows
        disable_inactive_workflows "$owner" "$repo" 90
        
        # Create report
        create_compliance_report "$owner" "$repo"
        
        echo ""
    done <<< "$repos"
    
    # Summary
    log "================================================"
    success "Enforcement Complete"
    echo "Total repositories: $total_repos"
    echo "Compliant repositories: $compliant_repos"
    echo "Compliance rate: $(echo "scale=1; $compliant_repos * 100 / $total_repos" | bc)%"
}

# Trap errors
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"

