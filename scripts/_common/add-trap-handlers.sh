#!/bin/bash
###############################################################################
# @file scripts/_common/add-trap-handlers.sh
# @module infrastructure
# @description Batch add error trap handlers to all scripts for consistent
#              error handling and cleanup
# @governance GOV-002: All scripts must have standardized error handling
# @usage bash scripts/_common/add-trap-handlers.sh [--dry-run] [--script FILE]
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
DRY_RUN="${1:-false}"
TARGET_SCRIPT="${2:-}"
MODIFIED_COUNT=0
SKIPPED_COUNT=0

# Trap handler template - will be inserted after init.sh sourcing
read -r -d '' TRAP_HANDLER << 'EOF' || true

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
# Set traps for error handling and cleanup
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; true' EXIT
EOF

# Color output
log_success() { echo -e "\033[32m✓\033[0m $1"; }
log_error()   { echo -e "\033[31m✗\033[0m $1"; }
log_info()    { echo -e "\033[36mℹ\033[0m $1"; }
log_warn()    { echo -e "\033[33m⚠\033[0m $1"; }

# Check if script already has trap handler
has_trap_handler() {
    local file="$1"
    grep -q "^trap " "$file" && return 0 || return 1
}

# Find insertion point (after init.sh sourcing)
find_insertion_point() {
    local file="$1"
    local line_num=$(grep -n "source.*init\.sh" "$file" | tail -1 | cut -d: -f1)
    if [[ -z "$line_num" ]]; then
        # If no init.sh, find after set -euo pipefail
        line_num=$(grep -n "set -euo pipefail" "$file" | head -1 | cut -d: -f1)
    fi
    echo "$line_num"
}

# Add trap handler to a script
add_trap_to_script() {
    local file="$1"
    
    # Skip if already has trap
    if has_trap_handler "$file"; then
        SKIPPED_COUNT+=1
        log_warn "Already has trap handler: $file"
        return 0
    fi
    
    # Find insertion point
    local line_num=$(find_insertion_point "$file")
    if [[ -z "$line_num" ]]; then
        log_error "Could not find insertion point in $file"
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Insert trap handler after the found line
    head -n "$line_num" "$file" > "$temp_file"
    echo "$TRAP_HANDLER" >> "$temp_file"
    tail -n +$((line_num + 1)) "$file" >> "$temp_file"
    
    # Replace original file (in dry-run, just show diff)
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would modify: $file"
        diff -u "$file" "$temp_file" | head -20 || true
    else
        cp "$temp_file" "$file"
        log_success "Added trap handler: $file"
        MODIFIED_COUNT+=1
    fi
    
    rm "$temp_file"
}

# Main
main() {
    log_info "Adding trap handlers to scripts..."
    
    if [[ -n "$TARGET_SCRIPT" ]]; then
        # Single script mode
        if [[ ! -f "$TARGET_SCRIPT" ]]; then
            log_error "File not found: $TARGET_SCRIPT"
            exit 1
        fi
        add_trap_to_script "$TARGET_SCRIPT"
    else
        # Batch mode - all scripts without trap handlers
        local count=0
        while IFS= read -r script; do
            add_trap_to_script "$script"
            count+=1
            if (( count % 10 == 0 )); then
                log_info "Processed $count scripts..."
            fi
        done < <(find "$REPO_ROOT/scripts" -name "*.sh" -type f ! -path ".backups/*" | xargs grep -L "^trap " | sort)
    fi
    
    echo ""
    log_success "Complete!"
    log_info "Modified: $MODIFIED_COUNT scripts"
    log_info "Skipped: $SKIPPED_COUNT scripts (already have trap handlers)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "This was a dry-run. Use without --dry-run to apply changes."
    fi
}

main "$@"
