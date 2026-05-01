#!/bin/bash

################################################################################
# @file analyze-documentation-gaps.sh
# @module documentation-analysis
# @description Automated documentation gap analysis — scans required docs and 
#              generates issues for missing documentation
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

# Required documentation checklist
declare -A REQUIRED_DOCS=(
    ["docs/architecture/overview.md"]="Architecture Overview — system design, component relationships, deployment topology"
    ["docs/runbooks/comprehensive-deployment-runbook.md"]="Deployment Runbook — step-by-step deployment procedures, rollback, health checks"
    ["docs/security/security-guide.md"]="Security Guide — authentication, authorization, secrets management, compliance"
    ["docs/testing/test-plan.md"]="Test Plan — unit tests, integration tests, E2E tests, performance baselines"
    ["docs/api/api-reference.md"]="API Reference — OpenAPI/Swagger, all endpoints, error codes, rate limits"
    ["CHANGELOG.md"]="Changelog — version history, breaking changes, release notes"
)

# Output file
REPORT_FILE="${PROJECT_ROOT}/artifacts/documentation-gap-analysis-report.json"
ISSUES_FILE="${PROJECT_ROOT}/artifacts/documentation-gap-issues.md"

################################################################################
# Functions
################################################################################

log_analysis() {
    log_info "[DOC-GAP] $*"
}

analyze_gaps() {
    local missing_count=0
    local existing_count=0
    declare -a missing_docs=()
    
    log_analysis "Starting documentation gap analysis..."
    log_analysis "Repository root: ${PROJECT_ROOT}"
    
    # Check each required document
    for doc_path in "${!REQUIRED_DOCS[@]}"; do
        local full_path="${PROJECT_ROOT}/${doc_path}"
        local description="${REQUIRED_DOCS[$doc_path]}"
        
        if [[ -f "$full_path" ]]; then
            log_analysis "✅ FOUND: ${doc_path}"
            existing_count+=1
        else
            log_analysis "❌ MISSING: ${doc_path} — ${description}"
            missing_count+=1
            missing_docs+=("$doc_path|$description")
        fi
    done
    
    # Check for broken links in existing docs
    log_analysis "Checking for broken links in documentation..."
    local broken_links=0
    
    if command -v markdown-link-check &> /dev/null; then
        for md_file in $(find "${PROJECT_ROOT}/docs" -name "*.md" 2>/dev/null || true); do
            if ! markdown-link-check "$md_file" &> /dev/null; then
                broken_links+=1
                log_warn "Broken links found in: $md_file"
            fi
        done
    else
        log_info "markdown-link-check not installed — skipping link validation"
    fi
    
    # Generate JSON report
    local json_output=$(cat <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "total_required": ${#REQUIRED_DOCS[@]},
  "existing_count": $existing_count,
  "missing_count": $missing_count,
  "missing_docs": [
EOF
)
    
    local first=true
    for entry in "${missing_docs[@]}"; do
        IFS='|' read -r path desc <<< "$entry"
        if [[ "$first" == true ]]; then
            first=false
            json_output+=$(printf '\n    {"path": "%s", "description": "%s"}' "$path" "$desc")
        else
            json_output+=$(printf ',\n    {"path": "%s", "description": "%s"}' "$path" "$desc")
        fi
    done
    
    json_output+=$(cat <<EOF

  ],
  "broken_links_detected": $broken_links,
  "coverage_percentage": $((existing_count * 100 / ${#REQUIRED_DOCS[@]})),
  "status": "$([ "$missing_count" -eq 0 ] && echo "COMPLETE" || echo "INCOMPLETE")"
}
EOF
)
    
    # Write JSON report
    mkdir -p "$(dirname "$REPORT_FILE")"
    echo "$json_output" > "$REPORT_FILE"
    log_analysis "Report written to: $REPORT_FILE"
    
    # Generate markdown issues file
    local md_output="# Documentation Gap Analysis Report

**Generated**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')  
**Coverage**: $existing_count / ${#REQUIRED_DOCS[@]} ($((existing_count * 100 / ${#REQUIRED_DOCS[@]}))%)  
**Status**: $([ "$missing_count" -eq 0 ] && echo "✅ COMPLETE" || echo "❌ INCOMPLETE")

## Missing Documentation ($missing_count)

"
    
    if [[ $missing_count -gt 0 ]]; then
        for entry in "${missing_docs[@]}"; do
            IFS='|' read -r path desc <<< "$entry"
            md_output+="- **${path}** — ${desc}"$'\n'
        done
    else
        md_output+="All required documentation is present."$'\n'
    fi
    
    md_output+="

## Existing Documentation ($existing_count)

"
    
    for doc_path in "${!REQUIRED_DOCS[@]}"; do
        local full_path="${PROJECT_ROOT}/${doc_path}"
        if [[ -f "$full_path" ]]; then
            local size=$(wc -c < "$full_path")
            md_output+="- ✅ **${doc_path}** ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo $size bytes))"$'\n'
        fi
    done
    
    if [[ $broken_links -gt 0 ]]; then
        md_output+="

## Quality Issues

- ⚠️ **Broken Links**: $broken_links document(s) contain invalid links
"
    fi
    
    md_output+="

## Next Steps

1. For each missing document:
   - Create file at path
   - Add content matching description
   - Ensure 100+ lines of substantive content
   
2. For broken links:
   - Run \`markdown-link-check docs/**/*.md\`
   - Fix all invalid URLs
   
3. Validate:
   - \`bash scripts/ci/analyze-documentation-gaps.sh\` returns 100% coverage
"
    
    # Write markdown report
    echo "$md_output" > "$ISSUES_FILE"
    log_analysis "Markdown report written to: $ISSUES_FILE"
    
    # Return exit code
    if [[ $missing_count -gt 0 ]]; then
        log_warn "Documentation gap analysis: $missing_count documents missing"
        return 1
    else
        log_success "All required documentation present"
        return 0
    fi
}

################################################################################
# Main
################################################################################

main() {
    log_info "Documentation Gap Analysis — Starting"
    
    if analyze_gaps; then
        log_success "Documentation analysis complete — no gaps detected"
        exit 0
    else
        log_warn "Documentation analysis complete — gaps identified"
        log_info "Report: $REPORT_FILE"
        log_info "Issues: $ISSUES_FILE"
        exit 1
    fi
}

main "$@"
