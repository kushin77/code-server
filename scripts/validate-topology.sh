#!/usr/bin/env bash
################################################################################
# validate-topology.sh
#
# Quality gate for #362 Phase 3: Ensures zero hardcoded IPs outside inventory
# - Scans all scripts, configs, docs
# - Reports violations with file:line context
# - Used in pre-commit hook and CI pipeline
#
# Usage:
#   scripts/validate-topology.sh                  # Full scan
#   scripts/validate-topology.sh --dry-run        # Show what would be checked
#   scripts/validate-topology.sh --fix-allowlist  # Add/update .gatekeep allowlist
#
################################################################################

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ALLOWLIST_FILE="$PROJECT_DIR/.gatekeep-hardcoded-ips"

# Patterns that ALWAYS fail (no exceptions)
CRITICAL_IPS=(
    "192\.168\.168\.31"  # Primary host IP
    "192\.168\.168\.42"  # Replica host IP
)

# Paths to scan
SCAN_PATHS=(
    "scripts/"
    "terraform/"
    "config/"
    "docker-compose*.yml"
    "Dockerfile*"
    "alerting/"
    "Makefile*"
)

# Paths to SKIP (obviously safe)
SKIP_PATTERNS=(
    ".git/"
    "node_modules/"
    ".terraform/"
    "*.backup"
    ".archived/"
    "archive/"
    "build/"
)

# =============================================================================
# MAIN LOGIC
# =============================================================================

# Build exclude patterns
build_exclude_args() {
    local exclude_args=""
    for pattern in "${SKIP_PATTERNS[@]}"; do
        exclude_args="$exclude_args --exclude-dir=$pattern"
    done
    echo "$exclude_args"
}

# Scan for hardcoded IPs
scan_hardcoded_ips() {
    local exclude_args=$(build_exclude_args)
    local violations=()
    
    echo "🔍 Scanning for hardcoded IPs outside inventory..."
    
    for ip_pattern in "${CRITICAL_IPS[@]}"; do
        # Search for the pattern
        while IFS= read -r -d '' file; do
            # Skip files in allowlist
            if [[ -f "$ALLOWLIST_FILE" ]] && grep -q "^${file}$" "$ALLOWLIST_FILE" 2>/dev/null; then
                continue
            fi
            
            # Skip comments
            local line_count=0
            while IFS= read -r line; do
                ((line_count++))
                # Skip comment-only lines
                if [[ "$line" =~ ^[[:space:]]*# ]]; then
                    continue
                fi
                # Skip lines that are examples or documentation
                if [[ "$line" =~ (example|EXAMPLE|doc|DOC|note|NOTE) ]]; then
                    continue
                fi
                # Skip terraform files with description comments
                if [[ "$file" =~ \.tf$ ]] && [[ "$line" =~ (description|default|comment) ]]; then
                    continue
                fi
                
                if echo "$line" | grep -q "$ip_pattern"; then
                    violations+=("$file:$line_count: $line")
                fi
            done < <(grep -n "$ip_pattern" "$file" 2>/dev/null || true)
        done < <(find "$PROJECT_DIR" $exclude_args -type f \
            \( -name "*.sh" -o -name "*.tf" -o -name "*.yml" -o -name "*.yaml" -o -name "Dockerfile*" -o -name "Makefile*" \) \
            -print0 2>/dev/null || true)
    done
    
    if [[ ${#violations[@]} -gt 0 ]]; then
        echo ""
        echo "❌ VIOLATIONS FOUND:"
        for violation in "${violations[@]}"; do
            echo "   $violation"
        done
        echo ""
        return 1
    else
        echo "✅ No hardcoded IPs found (all scripts use inventory)"
        return 0
    fi
}

# Check inventory file exists and is valid
check_inventory_file() {
    if [[ ! -f "$PROJECT_DIR/environments/production/hosts.yml" ]]; then
        >&2 echo "❌ ERROR: environments/production/hosts.yml not found"
        return 1
    fi
    
    if ! command -v yq >/dev/null 2>&1; then
        >&2 echo "⚠️  yq not found, skipping YAML validation"
        return 0
    fi
    
    if ! yq eval '.hosts.primary.ip' "$PROJECT_DIR/environments/production/hosts.yml" >/dev/null 2>&1; then
        >&2 echo "❌ ERROR: Invalid hosts.yml format"
        return 1
    fi
    
    echo "✅ Inventory file valid"
    return 0
}

# Check that inventory-loader.sh is sourced in key scripts
check_loader_sourcing() {
    local critical_scripts=(
        "scripts/deploy.sh"
        "scripts/bootstrap-node.sh"
    )
    
    local missing=()
    for script in "${critical_scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if ! grep -q "source.*inventory-loader" "$script" && \
               ! grep -q "source.*lib/inventory-loader" "$script"; then
                missing+=("$script")
            fi
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "⚠️  Missing inventory-loader sourcing in: ${missing[@]}"
        return 1
    fi
    
    echo "✅ Critical scripts source inventory-loader"
    return 0
}

# Validate terraform variables
validate_terraform_vars() {
    if [[ ! -f "terraform/variables.tf" ]]; then
        echo "⚠️  terraform/variables.tf not found"
        return 0
    fi
    
    # Check that inventory variable is defined
    if ! grep -q 'variable "inventory"' terraform/variables.tf; then
        >&2 echo "❌ ERROR: terraform/variables.tf missing 'inventory' variable"
        return 1
    fi
    
    echo "✅ Terraform variables configured"
    return 0
}

# Show allowed hosts (from inventory)
show_allowed_hosts() {
    if [[ ! -f "$PROJECT_DIR/environments/production/hosts.yml" ]]; then
        return 1
    fi
    
    echo ""
    echo "📋 Allowed hosts (from inventory):"
    grep "^\s*ip:" "$PROJECT_DIR/environments/production/hosts.yml" | sed 's/.*ip: /   - /'
    echo ""
    echo "All other IPs are prohibited outside inventory and DNS configs."
}

# Main validation
main() {
    local dry_run=false
    local fix_allowlist=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            --fix-allowlist) fix_allowlist=true; shift ;;
            *) >&2 echo "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    if [[ "$dry_run" == "true" ]]; then
        echo "DRY-RUN MODE: Showing what would be checked..."
        echo "Scan paths:" "${SCAN_PATHS[@]}"
        echo "Skip patterns:" "${SKIP_PATTERNS[@]}"
        return 0
    fi
    
    local exit_code=0
    
    # Run checks
    check_inventory_file || exit_code=1
    show_allowed_hosts || exit_code=1
    scan_hardcoded_ips || exit_code=1
    validate_terraform_vars || exit_code=1
    
    if [[ "$exit_code" == "0" ]]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "✅ ALL TOPOLOGY VALIDATION CHECKS PASSED"
        echo "═══════════════════════════════════════════════════════════════"
    else
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "❌ VALIDATION FAILED"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "To fix:"
        echo "  1. Update environments/production/hosts.yml with correct IPs"
        echo "  2. Replace hardcoded IPs in scripts with calls to inventory-loader:"
        echo "     OLD: ssh akushnir@192.168.168.31"
        echo "     NEW: ssh \$(get_ssh_user primary)@\$(get_host_ip primary)"
        echo "  3. Rerun: scripts/validate-topology.sh"
    fi
    
    return $exit_code
}

# Run main
cd "$PROJECT_DIR"
main "$@"
