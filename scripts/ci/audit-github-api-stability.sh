#!/bin/bash

################################################################################
# @file audit-github-api-stability.sh
# @module github-governance
# @description Audit GitHub API calls for stability issues: token scopes, 
#              403 errors, rate limits, and retry logic
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

REPORT_FILE="${PROJECT_ROOT}/artifacts/github-api-audit-report.json"
FINDINGS_FILE="${PROJECT_ROOT}/artifacts/github-api-audit-findings.md"

################################################################################
# Functions
################################################################################

log_audit() {
    log_info "[GITHUB-AUDIT] $*"
}

audit_gh_calls() {
    log_audit "Auditing GitHub API usage patterns..."
    
    declare -a findings=()
    declare -a issues_found=()
    
    # 1. Find all direct gh CLI calls
    log_audit "Scanning for gh CLI calls..."
    local gh_calls=$(grep -r "^[[:space:]]*gh " \
        --include="*.sh" \
        "${PROJECT_ROOT}/scripts" \
        "${PROJECT_ROOT}/.github/workflows" 2>/dev/null | wc -l | tr -d '[:space:]')
    
    log_audit "Found $gh_calls direct gh CLI calls"
    
    # 2. Check for missing --repo flags
    log_audit "Checking for --repo flag usage..."
    local missing_repo=$(grep -r "^[[:space:]]*gh issue\|^[[:space:]]*gh pr" \
        --include="*.sh" \
        "${PROJECT_ROOT}/scripts" \
        "${PROJECT_ROOT}/.github/workflows" 2>/dev/null | \
        grep -v "\--repo" | grep -v "scripts/audit/" | grep -v "scripts/ci/check-gh-repo-flag.sh" | wc -l | tr -d '[:space:]')
    
    if [ "$missing_repo" -gt 0 ]; then
        findings+=("❌ $missing_repo gh issue/pr calls missing --repo flag (may cause ambiguity)")
        issues_found+=("github-api-missing-repo-flag|$missing_repo gh calls missing --repo flag")
    fi
    
    # 3. Check for retry logic
    log_audit "Checking for retry logic..."
    local no_retry=$(grep -r "^[[:space:]]*gh " \
        --include="*.sh" \
        "${PROJECT_ROOT}/scripts" 2>/dev/null | \
        grep -v "retry\|backoff\|429\|403" | wc -l | tr -d '[:space:]')
    
    if [ "$no_retry" -gt 0 ]; then
        findings+=("⚠️ $no_retry gh calls may lack retry logic for 429/403 errors")
    fi
    
    # 4. Check token scope usage
    log_audit "Checking GitHub token configuration..."
    local uses_classic_pat=$(grep -r "GITHUB_TOKEN\|GH_TOKEN" \
        --include="*.yml" \
        --include="*.yaml" \
        "${PROJECT_ROOT}/.github" 2>/dev/null | \
        grep -c "secrets.GITHUB_TOKEN" || true)
    
    if [ "$uses_classic_pat" -gt 0 ]; then
        findings+=("ℹ️ Using GITHUB_TOKEN (fine-grained tokens recommended for reduced scope)")
    fi
    
    # 5. Check for hardcoded rate limit guards
    log_audit "Checking for rate limit guards..."
    local rate_limit_guards=$(grep -r "rate.limit\|rate_limit\|429\|403" \
        --include="*.sh" \
        "${PROJECT_ROOT}/scripts" 2>/dev/null | wc -l | tr -d '[:space:]')
    
    if [ "$rate_limit_guards" -lt 3 ]; then
        findings+=("⚠️ Few rate limit guards detected — consider adding rate limit monitoring")
        issues_found+=("github-api-rate-limit-monitoring|Add rate limit monitoring with alerts")
    fi
    
    # 6. Test current token validity
    log_audit "Testing GitHub token validity..."
    local token_test=""
    if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
        token_test=$(github_gh auth status 2>&1 || echo "Token validation failed")
        if echo "$token_test" | grep -q "Logged in\|authenticated"; then
            findings+=("✅ GitHub token is valid and authenticated")
        else
            findings+=("❌ GitHub token validation failed")
            issues_found+=("github-api-token-invalid|Current GitHub token is invalid or expired")
        fi
    else
        findings+=("⚠️ No GitHub token found (GH_TOKEN or GITHUB_TOKEN env var)")
    fi
    
    # 7. Check for unified issue creation script
    log_audit "Checking issue creation patterns..."
    if [ -f "${PROJECT_ROOT}/scripts/_common/issue-create-unified.sh" ]; then
        findings+=("✅ Unified issue creation script found")
    else
        findings+=("❌ Unified issue creation script not found — required for governance")
        issues_found+=("github-api-create-unified-script|Create scripts/_common/issue-create-unified.sh")
    fi
    
    # 8. Scan .github/workflows for direct issue creation
    log_audit "Checking workflows for direct issue creation..."
    local direct_creates=$(grep -r "gh issue create\|gh issue new" \
        --include="*.yml" \
        --include="*.yaml" \
        "${PROJECT_ROOT}/.github/workflows" 2>/dev/null | \
        grep -v "issue-create-unified" | wc -l | tr -d '[:space:]')
    
    if [ "$direct_creates" -gt 0 ]; then
        findings+=("⚠️ $direct_creates direct 'gh issue create' calls found in workflows (consolidate to unified script)")
        issues_found+=("github-api-consolidate-issue-creation|Consolidate direct gh issue create calls to unified script")
    fi
    
    # Generate JSON report
    local json_report=$(cat <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "total_gh_calls": $gh_calls,
  "audit_findings": [
EOF
)
    
    local first=true
    for finding in "${findings[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
            json_report+=$(printf '\n    "%s"' "$finding")
        else
            json_report+=$(printf ',\n    "%s"' "$finding")
        fi
    done
    
    json_report+=$(cat <<EOF

  ],
  "issues_requiring_action": [
EOF
)
    
    first=true
    for entry in "${issues_found[@]}"; do
        IFS='|' read -r issue_key issue_desc <<< "$entry"
        if [[ "$first" == true ]]; then
            first=false
            json_report+=$(printf '\n    {"key": "%s", "description": "%s"}' "$issue_key" "$issue_desc")
        else
            json_report+=$(printf ',\n    {"key": "%s", "description": "%s"}' "$issue_key" "$issue_desc")
        fi
    done
    
    json_report+=$(cat <<EOF

  ],
  "status": "$([ "${#issues_found[@]}" -eq 0 ] && echo "PASS" || echo "NEEDS_REMEDIATION")"
}
EOF
)
    
    # Write JSON report
    mkdir -p "$(dirname "$REPORT_FILE")"
    echo "$json_report" > "$REPORT_FILE"
    log_audit "JSON report: $REPORT_FILE"
    
    # Generate markdown findings
    local md_findings="# GitHub API Stability Audit Report

**Generated**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
**Total gh CLI Calls**: $gh_calls  
**Status**: $([ "${#issues_found[@]}" -eq 0 ] && echo "✅ PASS" || echo "⚠️ NEEDS_REMEDIATION")

## Findings

"
    
    for finding in "${findings[@]}"; do
        md_findings+="$finding"$'\n'
    done
    
    if [ "${#issues_found[@]}" -gt 0 ]; then
        md_findings+="

## Issues Requiring Action

"
        for entry in "${issues_found[@]}"; do
            IFS='|' read -r key desc <<< "$entry"
            md_findings+="- **${key}**: ${desc}"$'\n'
        done
    fi
    
    md_findings+="

## Recommendations

1. **Token Scopes**: Use fine-grained personal access tokens (not classic PAT)
   - Scopes needed: \`repo\`, \`issues\`, \`pull-requests\`, \`workflows\`
   
2. **Retry Logic**: All gh CLI calls should retry on 429/403
   - Implement exponential backoff (1s, 2s, 4s)
   - Max 3 retries
   
3. **Rate Limit Monitoring**: 
   - Alert when < 100 requests remaining
   - Track in Prometheus
   - Set dashboard
   
4. **Unified Issue Creation**:
   - All \`gh issue create\` calls go through \`scripts/_common/issue-create-unified.sh\`
   - Enforced via CI guard

5. **Testing**:
   - Test token validity before CI runs
   - Simulate rate limit scenarios
"
    
    # Write markdown report
    echo "$md_findings" > "$FINDINGS_FILE"
    log_audit "Markdown findings: $FINDINGS_FILE"
    
    # Return exit code
    if [ "${#issues_found[@]}" -eq 0 ]; then
        log_success "GitHub API audit passed — no critical issues found"
        return 0
    else
        log_warn "GitHub API audit found ${#issues_found[@]} issues requiring action"
        return 1
    fi
}

################################################################################
# Main
################################################################################

main() {
    log_info "GitHub API Stability Audit — Starting"
    
    if audit_gh_calls; then
        log_success "GitHub API audit: PASS"
        exit 0
    else
        log_warn "GitHub API audit: NEEDS_REMEDIATION"
        log_info "Report: $REPORT_FILE"
        log_info "Findings: $FINDINGS_FILE"
        exit 1
    fi
}

main "$@"
