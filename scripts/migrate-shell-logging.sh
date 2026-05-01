#!/bin/bash
# ============================================================================
# Shell Script Logging Migration Tool
# Converts echo statements to use centralized logging library
# ============================================================================

set -e
trap 'echo "[ERROR] Script failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Cleanup complete"; true' EXIT

REPO_ROOT="${REPO_ROOT:-/home/akushnir/code-server}"
SCRIPTS_TO_UPDATE=(
    "scripts/ci/test-env-consolidation.sh"
    "scripts/ci/validate-config-ssot.sh"
    "scripts/ci/check-docker-compose-idempotency.sh"
    "scripts/ops/rotate-postgres-credentials.sh"
    "scripts/ops/deploy-cluster.sh"
)

# Function to add logging source if not already present
add_logging_source() {
    local file="$1"
    
    if grep -q 'source.*logging\.sh' "$file" 2>/dev/null; then
        return 0  # Already added
    fi
    
    # Find the line after shebang and other source commands
    local insert_line=$(grep -n '^source\|^\..*/' "$file" | tail -1 | cut -d: -f1)
    
    if [[ -z "$insert_line" ]]; then
        # No other sources, add after shebang
        insert_line=1
    fi
    
    # Insert the logging source command
    sed -i "${insert_line}a\\source \${REPO_ROOT:-\$(cd \$(dirname \"\${BASH_SOURCE[0]}\")/.. && pwd)}/scripts/common/logging.sh" "$file"
}

# Function to replace echo statements
replace_echo_statements() {
    local file="$1"
    
    # Replace: echo "Error: ..." with log_error
    sed -i 's/echo "\(Error\|ERROR\):\? \(.*\)"/log_error "\2"/g' "$file"
    sed -i "s/echo '\(Error\|ERROR\):\? \(.*\)'/log_error '\2'/g" "$file"
    
    # Replace: echo "✓ ..." or echo "Success: ..." with log_success
    sed -i 's/echo "✓ \(.*\)"/log_success "\1"/g' "$file"
    sed -i 's/echo "Success:\? \(.*\)"/log_success "\1"/g' "$file"
    sed -i "s/echo '✓ \(.*\)'/log_success '\1'/g" "$file"
    sed -i "s/echo 'Success:\? \(.*\)'/log_success '\1'/g" "$file"
    
    # Replace: echo "⚠ ..." or echo "Warning: ..." with log_warn
    sed -i 's/echo "⚠ \(.*\)"/log_warn "\1"/g' "$file"
    sed -i 's/echo "Warning:\? \(.*\)"/log_warn "\1"/g' "$file"
    sed -i "s/echo '⚠ \(.*\)'/log_warn '\1'/g" "$file"
    sed -i "s/echo 'Warning:\? \(.*\)'/log_warn '\1'/g" "$file"
    
    # Replace: echo "INFO: ..." or other info-level output with log_info
    sed -i 's/echo "INFO:\? \(.*\)"/log_info "\1"/g' "$file"
    sed -i "s/echo 'INFO:\? \(.*\)'/log_info '\1'/g" "$file"
    
    # Replace remaining echo with log_info (conservative approach)
    # This targets specific patterns to avoid breaking things
    sed -i 's/echo "\([✓✗⚠🔴🟠🟡🟢]\)\? \(.*\)"/log_info "\2"/g' "$file"
}

# Function to update a single script
update_script() {
    local script="$1"
    local full_path="$REPO_ROOT/$script"
    
    if [[ ! -f "$full_path" ]]; then
        echo "  ⚠ Skipping (not found): $script"
        return 1
    fi
    
    # Count echo statements before
    local echo_count=$(grep -c "echo " "$full_path" 2>/dev/null || echo "0")
    
    if [[ "$echo_count" -eq 0 ]]; then
        echo "  ⊘ Skipping (no echoes): $script"
        return 0
    fi
    
    # Make a backup
    cp "$full_path" "${full_path}.bak"
    
    # Add logging source
    add_logging_source "$full_path"
    
    # Replace echo statements
    replace_echo_statements "$full_path"
    
    # Count after
    local new_echo_count=$(grep -c "echo " "$full_path" 2>/dev/null || echo "0")
    
    if [[ "$new_echo_count" -lt "$echo_count" ]]; then
        echo "  ✓ Updated $script ($((echo_count - new_echo_count)) echo → log_*)"
        rm "${full_path}.bak"
        return 0
    else
        echo "  ⚠ Warning: Update may not have worked for $script, restoring"
        mv "${full_path}.bak" "$full_path"
        return 1
    fi
}

# Main
main() {
    echo "=== Shell Script Logging Migration ==="
    echo ""
    
    local updated=0
    local failed=0
    
    for script in "${SCRIPTS_TO_UPDATE[@]}"; do
        if update_script "$script"; then
            updated+=1
        else
            failed+=1
        fi
    done
    
    echo ""
    echo "Summary:"
    echo "  Updated: $updated scripts"
    echo "  Failed/Skipped: $failed scripts"
    
    if [[ $failed -eq 0 ]]; then
        echo "✅ All scripts updated successfully"
        return 0
    else
        echo "⚠ Some scripts failed or were skipped"
        return 1
    fi
}

main "$@"
