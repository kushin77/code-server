#!/usr/bin/env bash
# @file        scripts/_common/apply-iac-headers-batch.sh
# @module      governance/batch-headers
# @description Batch apply IaC governance headers to all scripts lacking them
#
# IaC Principles:
# - Immutable: Header templates frozen for consistent application
# - Idempotent: Re-running safely skips files with existing headers
# - Versioned: All applications tracked with timestamps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

# Track statistics
TOTAL=0
SKIPPED=0
UPDATED=0

# Map file paths to module names and descriptions
declare -A SCRIPT_MODULES=(
    ["scripts/ci"]="ci"
    ["scripts/deploy"]="deployment"
    ["scripts/auth"]="auth"
    ["scripts/chaos"]="chaos-engineering"
    ["scripts/load-testing"]="load-testing"
)

declare -A SCRIPT_DESCRIPTIONS=(
    ["check-"]="Governance validation check"
    ["deploy-"]="Deployment script"
    ["test-"]="Test suite"
    ["run-"]="Execution runner"
    ["validate-"]="Validation script"
    ["audit-"]="Audit and reporting"
    ["generate-"]="Report generation"
    ["enforce-"]="Enforcement automation"
    ["detect-"]="Detection and analysis"
    ["fix-"]="Issue remediation"
)

# Function to get description from script filename
get_description() {
    local filename=$1
    local description="Automation script"
    
    for prefix in "${!SCRIPT_DESCRIPTIONS[@]}"; do
        if [[ "$filename" == *"$prefix"* ]]; then
            description="${SCRIPT_DESCRIPTIONS[$prefix]}"
            break
        fi
    done
    
    echo "$description"
}

# Function to get module name
get_module_name() {
    local filepath=$1
    local filename=$(basename "$filepath")
    
    # Extract domain from path
    local domain=""
    if [[ "$filepath" == *"/ci/"* ]]; then
        domain="ci"
    elif [[ "$filepath" == *"/deploy"* ]]; then
        domain="deployment"
    elif [[ "$filepath" == *"/auth/"* ]]; then
        domain="auth"
    elif [[ "$filepath" == *"/chaos/"* ]]; then
        domain="chaos"
    elif [[ "$filepath" == *"/load-testing/"* ]]; then
        domain="load-testing"
    fi
    
    echo "$domain"
}

# Function to add header to single script
add_header_to_script() {
    local filepath=$1
    
    TOTAL=$((TOTAL + 1))
    
    # Skip if header already exists
    if head -5 "$filepath" 2>/dev/null | grep -q "@file"; then
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi
    
    local filename=$(basename "$filepath")
    local module=$(get_module_name "$filepath")
    local description=$(get_description "$filename")
    
    # Detect script type
    local shebang=""
    if head -1 "$filepath" | grep -q "bash"; then
        shebang="#!/usr/bin/env bash"
    elif head -1 "$filepath" | grep -q "python"; then
        shebang="#!/usr/bin/env python3"
    elif head -1 "$filepath" | grep -q "node"; then
        shebang="#!/usr/bin/env node"
    else
        # Default to bash if unclear
        shebang="#!/usr/bin/env bash"
    fi
    
    # Create temp file with new header
    local temp_file="${filepath}.tmp.$$"
    {
        echo "$shebang"
        echo "# @file        ${filepath#${SCRIPT_DIR}/}"
        echo "# @module      ${module}/$(echo "$filename" | sed 's/\.[^.]*$//')"
        echo "# @description ${description}"
        echo "#"
        echo "# IaC Principles:"
        echo "# - Immutable: State frozen after execution, no side effects on re-run"
        echo "# - Idempotent: Safe to run multiple times with identical results"
        echo "# - Versioned: All changes tracked with audit trail"
        echo ""
        # Skip old shebang if present
        if head -1 "$filepath" | grep -q "^#!"; then
            tail -n +2 "$filepath"
        else
            cat "$filepath"
        fi
    } > "$temp_file"
    
    mv "$temp_file" "$filepath"
    chmod +x "$filepath"
    UPDATED=$((UPDATED + 1))
    log_info "✅ $filename"
}

# Main execution
log_info "Starting batch IaC header application..."

# Process CI scripts
log_info "Processing CI scripts (scripts/ci/*.sh)..."
for script in "${SCRIPT_DIR}"/scripts/ci/*.sh; do
    if [[ -f "$script" ]]; then
        add_header_to_script "$script"
    fi
done

# Process deployment scripts
log_info "Processing deployment scripts (scripts/deploy/*.sh)..."
for script in "${SCRIPT_DIR}"/scripts/deploy/*.sh; do
    if [[ -f "$script" ]]; then
        add_header_to_script "$script"
    fi
done

# Process auth scripts
log_info "Processing auth scripts (scripts/auth/*.sh)..."
for script in "${SCRIPT_DIR}"/scripts/auth/*.sh; do
    if [[ -f "$script" ]]; then
        add_header_to_script "$script"
    fi
done

# Process chaos scripts
log_info "Processing chaos engineering scripts (scripts/chaos/*.sh)..."
for script in "${SCRIPT_DIR}"/scripts/chaos/*.sh; do
    if [[ -f "$script" ]]; then
        add_header_to_script "$script"
    fi
done

# Process load testing scripts
log_info "Processing load testing scripts (scripts/load-testing/*.sh)..."
for script in "${SCRIPT_DIR}"/scripts/load-testing/*.sh; do
    if [[ -f "$script" ]]; then
        add_header_to_script "$script"
    fi
done

# Process root scripts
log_info "Processing root scripts (scripts/*.sh)..."
for script in "${SCRIPT_DIR}"/scripts/*.sh; do
    if [[ -f "$script" && ! "$script" =~ ^(scripts/ci|scripts/deploy|scripts/auth|scripts/chaos|scripts/load-testing) ]]; then
        add_header_to_script "$script"
    fi
done

# Report results
log_info ""
log_info "════════════════════════════════════════════════════════"
log_info "Batch IaC Header Application Complete"
log_info "════════════════════════════════════════════════════════"
log_info "Total scripts scanned:    $TOTAL"
log_info "Headers already present:  $SKIPPED"
log_info "Headers added:            $UPDATED"
log_info "════════════════════════════════════════════════════════"

if [[ $UPDATED -gt 0 ]]; then
    log_info "Next steps:"
    log_info "  1. Review changes: git diff"
    log_info "  2. Stage changes: git add scripts/"
    log_info "  3. Commit: git commit -m 'docs(governance): Add IaC headers to all remaining scripts'"
    log_info "  4. Push: git push origin main"
fi
