#!/usr/bin/env bash
# @file        scripts/ci/check-issue-governance.sh
# @module      ci/governance-enforcement
# @description Enforce GitHub issue creation governance - blocks direct gh issue create calls, requires unified script
#
# ENFORCEMENT:
# - Prevents direct 'gh issue create' in scripts (must use unified script)
# - Detects pattern: gh issue create (without source script proxy)
# - Runs in CI/CD pipeline to catch violations before merge
# - Part of Rule 8: GitHub Issue Creation Governance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/logging.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Files to scan for violations
SCAN_PATTERNS=(
    "scripts/**/*.sh"
    "scripts/**/*.py"
    ".github/workflows/*.yml"
)

# Allowed patterns (legitimate uses)
ALLOWED_PATTERNS=(
    'gh issue list'
    'gh issue view'
    'gh issue comment'
    'gh issue create.*check-issue-governance'  # This script itself
    'copilot_create_issue'  # The unified function
    'source.*issue-create-unified'  # Sourcing the unified script
    'issue_url=\$(gh issue create'  # Approved wrapper patterns
)

# Violation counter
VIOLATIONS=0

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Check if line is allowed (matches exception patterns)
is_allowed_usage() {
    local line="$1"
    
    for pattern in "${ALLOWED_PATTERNS[@]}"; do
        if [[ "$line" =~ $pattern ]]; then
            return 0  # Allowed
        fi
    done
    
    return 1  # Not allowed
}

# Scan file for violations
scan_file() {
    local file="$1"
    local line_num=0
    local found_violations=0
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Check for direct 'gh issue create' calls
        if [[ "$line" =~ gh[[:space:]]+issue[[:space:]]+create ]]; then
            # Skip if it's an allowed pattern
            if is_allowed_usage "$line"; then
                continue
            fi
            
            # Found a violation
            ((VIOLATIONS++))
            ((found_violations++))
            
            log_error "VIOLATION: Direct 'gh issue create' detected in $file:$line_num"
            log_error "  Line: $line"
            log_error "  FIX: Use 'copilot_create_issue' from scripts/_common/issue-create-unified.sh"
        fi
    done < "$file"
    
    return $((found_violations > 0 ? 1 : 0))
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log_info "GitHub Issue Creation Governance Check"
log_info "========================================"

# Find all files matching patterns
files_to_scan=()

for pattern in "${SCAN_PATTERNS[@]}"; do
    # Use find for shell scripts
    if [[ "$pattern" == *"\.sh" ]]; then
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                files_to_scan+=("$file")
            fi
        done < <(find "$SCRIPT_DIR" -name "${pattern##*/}" -type f 2>/dev/null || true)
    fi
    
    # Use find for Python scripts
    if [[ "$pattern" == *"\.py" ]]; then
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                files_to_scan+=("$file")
            fi
        done < <(find "$SCRIPT_DIR" -name "${pattern##*/}" -type f 2>/dev/null || true)
    fi
    
    # Use find for workflows
    if [[ "$pattern" == *"\.yml" ]]; then
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                files_to_scan+=("$file")
            fi
        done < <(find "$SCRIPT_DIR/../.github/workflows" -name "${pattern##*/}" -type f 2>/dev/null || true)
    fi
done

# Remove duplicates
unique_files=()
for file in "${files_to_scan[@]}"; do
    if [[ ! " ${unique_files[*]} " =~ " ${file} " ]]; then
        unique_files+=("$file")
    fi
done

log_info "Scanning ${#unique_files[@]} files..."

# Scan each file
for file in "${unique_files[@]}"; do
    scan_file "$file" || true
done

# Report results
log_info ""
log_info "========================================"

if [[ $VIOLATIONS -eq 0 ]]; then
    log_info "✓ PASS: No governance violations found"
    log_info ""
    log_info "Governance check complete. All issue creation uses unified script."
    exit 0
else
    log_error "✗ FAIL: Found $VIOLATIONS governance violation(s)"
    log_error ""
    log_error "Issue Creation Governance Rule (Rule 8):"
    log_error "- Use: copilot_create_issue from scripts/_common/issue-create-unified.sh"
    log_error "- Don't: Direct 'gh issue create' calls"
    log_error ""
    log_error "Fix violations by:"
    log_error "1. source scripts/_common/issue-create-unified.sh"
    log_error "2. Replace 'gh issue create' with 'copilot_create_issue' calls"
    log_error "3. Re-run this check: bash scripts/ci/check-issue-governance.sh"
    exit 1
fi
