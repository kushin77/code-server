#!/bin/bash

################################################################################
# @file check-issue-lifecycle-governance.sh
# @module github-governance
# @description Enforce issue lifecycle governance: every closed issue must have
#              a linked PR or documented close reason
# @governance GOV-002
################################################################################

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common functions
source "${SCRIPT_DIR}/../_common/init.sh"

REPORT_FILE="${PROJECT_ROOT}/artifacts/issue-lifecycle-governance-report.json"
VIOLATIONS_FILE="${PROJECT_ROOT}/artifacts/issue-lifecycle-violations.md"
REPO_SLUG="${GITHUB_REPOSITORY:-${REPO:-kushin77/code-server}}"

################################################################################
# Functions
################################################################################

log_governance() {
    log_info "[LIFECYCLE-GOVERNANCE] $*"
}

check_closed_issues() {
    log_governance "Checking closed issues for lifecycle governance compliance..."
    
    declare -a violations=()
    local checked=0
    local compliant=0
    local violations_count=0
    
    # Get all issues closed in the last 30 days
    local since_date=$(date -u -d "30 days ago" +'%Y-%m-%dT%H:%M:%SZ')
    
    # Query GitHub for closed issues
    local closed_issues=$(github_gh issue list \
        --repo "$REPO_SLUG" \
        --state closed \
        --updated ">=${since_date}" \
        --json number,title,closedAt,labels \
        --jq '.[] | "\(.number)\t\(.title)\t\(.labels | map(.name) | join(","))"' \
        --limit 100 2>/dev/null || echo "")

    local closed_count
    closed_count=$(printf '%s\n' "$closed_issues" | sed '/^$/d' | wc -l | tr -d ' ')
    log_governance "Checking ${closed_count} closed issues from last 30 days"

    # Check each closed issue
    while IFS=$'\t' read -r issue_num issue_title labels; do
        [ -z "$issue_num" ] && continue
        
        checked+=1
        
        # Check if issue has a priority label
        local has_priority=false
        if echo "$labels" | grep -qE "P[0-3]"; then
            has_priority=true
        fi
        
        if [[ "$has_priority" == false ]]; then
            violations+=("Issue #$issue_num missing priority label (P0/P1/P2/P3)")
            violations_count+=1
            continue
        fi
        
        # Check if issue has a linked PR (via "Fixes" comments or PR references)
        local linked_pr=$(github_gh issue view "$issue_num" --repo "$REPO_SLUG" --json body --jq '.body' 2>/dev/null | \
            grep -oE "(Fixes|Closes|Resolves) #[0-9]+" | head -1 || echo "")
        
        # Alternative: check for manual close reason in recent comment
        local close_reason=$(github_gh issue view "$issue_num" --repo "$REPO_SLUG" --json comments --jq '.comments[] | select(.body | test("(manual close|auto-closed|stale|duplicate|by design)"))' 2>/dev/null || echo "")
        
        if [[ -n "$linked_pr" ]] || [[ -n "$close_reason" ]]; then
            compliant+=1
            log_governance "✅ #$issue_num: Compliant ($([ -n "$linked_pr" ] && echo "linked PR" || echo "documented close"))"
        else
            violations+=("Issue #$issue_num closed without linked PR or documented reason: \"$issue_title\"")
            violations_count+=1
            log_governance "❌ #$issue_num: VIOLATION"
        fi
    done < <(printf '%s\n' "$closed_issues")
    
    # Generate JSON report
    local json_report=$(cat <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "period_days": 30,
  "total_checked": $checked,
  "compliant_count": $compliant,
  "violation_count": $violations_count,
  "compliance_percentage": $((compliant * 100 / (checked > 0 ? checked : 1))),
  "violations": [
EOF
)
    
    local first=true
    for violation in "${violations[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
            json_report+=$(printf '\n    "%s"' "$violation")
        else
            json_report+=$(printf ',\n    "%s"' "$violation")
        fi
    done
    
    json_report+=$(cat <<EOF

  ],
  "status": "$([ $violations_count -eq 0 ] && echo "COMPLIANT" || echo "VIOLATIONS_FOUND")"
}
EOF
)
    
    # Write JSON report
    mkdir -p "$(dirname "$REPORT_FILE")"
    echo "$json_report" > "$REPORT_FILE"
    log_governance "Report: $REPORT_FILE"
    
    # Generate markdown violations report
    local md_violations="# Issue Lifecycle Governance Report

**Generated**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')  
**Period**: Last 30 days  
**Compliance**: $compliant / $checked ($((compliant * 100 / (checked > 0 ? checked : 1)))%)  
**Status**: $([ $violations_count -eq 0 ] && echo "✅ COMPLIANT" || echo "❌ VIOLATIONS_FOUND")

## Summary

Every closed issue MUST have either:
1. A linked pull request (via \"Fixes #N\", \"Closes #N\", etc.), OR
2. A documented close reason (in comment or close message)

Plus: Every issue MUST have a priority label (P0/P1/P2/P3)

"
    
    if [ $violations_count -gt 0 ]; then
        md_violations+="## Violations ($violations_count)

"
        for violation in "${violations[@]}"; do
            md_violations+="- ⚠️ $violation"$'\n'
        done
    else
        md_violations+="All issues comply with governance rules."$'\n'
    fi
    
    md_violations+="

## Governance Rules

1. **Priority Labels** (Required)
   - Every issue must have exactly one: P0 (critical), P1 (high), P2 (medium), P3 (low)
   
2. **Close Documentation** (Required)
   - If closed with linked PR: PR title/description must reference issue (\"Fixes #N\")
   - If closed manually: Close comment must explain reason
   - Cannot close without reason

3. **PR Linking** (Enforced in CI)
   - No PR can merge without at least one issue reference
   - Reference formats: \"Fixes #123\", \"Closes #456\", etc.

4. **Stale Issues** (Automated)
   - 30 days no activity → marked \"stale\"
   - 14 more days no activity → auto-closed as \"not planned\"

## Remediation

For each violation:
1. Add priority label (P0/P1/P2/P3) if missing
2. If no linked PR, add close reason comment
3. Re-open if closure was in error
"
    
    # Write markdown report
    echo "$md_violations" > "$VIOLATIONS_FILE"
    log_governance "Violations: $VIOLATIONS_FILE"
    
    # Return exit code
    if [ $violations_count -eq 0 ]; then
        log_success "Issue lifecycle governance: COMPLIANT"
        return 0
    else
        log_warn "Issue lifecycle governance: $violations_count VIOLATIONS FOUND"
        return 1
    fi
}

################################################################################
# Main
################################################################################

main() {
    log_info "Issue Lifecycle Governance Check — Starting"
    
    if check_closed_issues; then
        log_success "Governance check: PASS"
        exit 0
    else
        log_warn "Governance check: VIOLATIONS FOUND (see $VIOLATIONS_FILE)"
        exit 1
    fi
}

main "$@"
