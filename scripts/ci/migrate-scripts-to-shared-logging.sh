#!/bin/bash

##############################################################################
# Script Migration Tool: Consolidate Local Logging with Shared Module
##############################################################################
# This tool automatically migrates bash scripts from local logging functions
# to the centralized shared logging module (apps/_shared/test.sh)
##############################################################################

set -euo pipefail

trap 'log_error "Migration failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup complete"; rm -f /tmp/migrate*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SHARED_TEST_SCRIPT="$REPO_ROOT/apps/_shared/test.sh"

# Statistics
SCRIPTS_PROCESSED=0
SCRIPTS_MIGRATED=0
SCRIPTS_FAILED=0
SCRIPTS_SKIPPED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

##############################################################################
# Helper Functions
##############################################################################

log_info() {
    printf "[${BLUE}INFO${NC}] %s\n" "$1"
}

log_success() {
    printf "[${GREEN}✓${NC}] %s\n" "$1"
}

log_warning() {
    printf "[${YELLOW}⚠${NC}] %s\n" "$1"
}

log_error() {
    printf "[${RED}✗${NC}] %s\n" "$1"
}

##############################################################################
# Check if script has local logging functions
##############################################################################

has_local_logging() {
    local script="$1"
    grep -q "log_info\|log_success\|log_error\|log_warning\|log_debug" "$script" || return 1
}

##############################################################################
# Check if script already uses shared logging
##############################################################################

uses_shared_logging() {
    local script="$1"
    grep -q "apps/_shared/test.sh\|source.*test.sh\|\\. .*test.sh" "$script" || return 1
}

##############################################################################
# Extract logging function definitions from script
##############################################################################

extract_logging_functions() {
    local script="$1"
    grep -A 5 "^log_info()\|^log_success()\|^log_error()\|^log_warning()\|^log_debug()" "$script" || true
}

##############################################################################
# Generate migration for a script
##############################################################################

migrate_script() {
    local script="$1"
    local backup="${script}.backup"
    local script_name=$(basename "$script")
    
    # Check preconditions
    if uses_shared_logging "$script"; then
        log_warning "Script already uses shared logging: $script"
        SCRIPTS_SKIPPED+=1
        return 0
    fi
    
    if ! has_local_logging "$script"; then
        log_warning "Script has no local logging functions: $script"
        SCRIPTS_SKIPPED+=1
        return 0
    fi
    
    # Create backup
    cp "$script" "$backup"
    log_info "Created backup: $backup"
    
    # Remove local logging function definitions
    local tmpfile=$(mktemp)
    
    # Extract first 20 lines to find where to insert source statement
    head -20 "$script" > "$tmpfile" || true
    
    # Check if script is sourcing init.sh
    if grep -q "source.*init.sh\|\\. .*init.sh" "$script"; then
        # Add shared logging source after init.sh
        sed -i.tmp '
            /source.*init\.sh\|\\. .*init\.sh/ {
                a\
# Source shared logging functions\
source "$REPO_ROOT/apps/_shared/test.sh"
            }
            /^log_info()/,/^}$/{
                /^log_info()/d
                /^}/d
                /^[[:space:]]*printf/d
            }
            /^log_success()/,/^}$/{
                /^log_success()/d
                /^}/d
                /^[[:space:]]*printf/d
            }
            /^log_error()/,/^}$/{
                /^log_error()/d
                /^}/d
                /^[[:space:]]*printf/d
            }
            /^log_warning()/,/^}$/{
                /^log_warning()/d
                /^}/d
                /^[[:space:]]*printf/d
            }
            /^log_debug()/,/^}$/{
                /^log_debug()/d
                /^}/d
                /^[[:space:]]*printf/d
            }
        ' "$script"
        rm -f "$script.tmp"
    else
        # Add shared logging source at the top (after shebang)
        {
            head -1 "$script"  # shebang
            echo ""
            echo "# Source shared logging functions"
            echo "SCRIPT_DIR=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)\""
            echo "REPO_ROOT=\"\$(cd \"\$SCRIPT_DIR/../..\" && pwd)\""
            echo "source \"\$REPO_ROOT/apps/_shared/test.sh\""
            echo ""
            tail -n +2 "$script" | sed '
                /^log_info()/,/^}$/d
                /^log_success()/,/^}$/d
                /^log_error()/,/^}$/d
                /^log_warning()/,/^}$/d
                /^log_debug()/,/^}$/d
            '
        } > "$tmpfile"
        
        mv "$tmpfile" "$script"
    fi
    
    # Validate bash syntax
    if bash -n "$script" 2>/dev/null; then
        log_success "Migrated: $script"
        SCRIPTS_MIGRATED+=1
        rm -f "$backup"  # Remove backup if successful
    else
        log_error "Migration failed (syntax error): $script"
        log_info "Restoring from backup..."
        mv "$backup" "$script"
        SCRIPTS_FAILED+=1
    fi
    
    SCRIPTS_PROCESSED+=1
}

##############################################################################
# Main Migration Loop
##############################################################################

main() {
    log_info "Script Consolidation Migration Tool"
    log_info "Target: Consolidate local logging with shared module"
    echo ""
    
    # Find all bash scripts
    local scripts_to_migrate=()
    
    log_info "Scanning for scripts with local logging functions..."
    
    while IFS= read -r script; do
        scripts_to_migrate+=("$script")
    done < <(find "$REPO_ROOT/scripts" -name "*.sh" -type f | sort)
    
    log_success "Found ${#scripts_to_migrate[@]} bash scripts"
    echo ""
    
    # Migrate each script
    for script in "${scripts_to_migrate[@]}"; do
        if has_local_logging "$script"; then
            migrate_script "$script"
        fi
    done
    
    # Print summary
    echo ""
    log_info "=== Migration Summary ==="
    printf "Total Scripts Scanned:    %3d\n" "$SCRIPTS_PROCESSED"
    printf "Successfully Migrated:    ${GREEN}%3d${NC}\n" "$SCRIPTS_MIGRATED"
    printf "Failed:                   ${RED}%3d${NC}\n" "$SCRIPTS_FAILED"
    printf "Skipped (already done):   ${YELLOW}%3d${NC}\n" "$SCRIPTS_SKIPPED"
    echo ""
    
    if [[ $SCRIPTS_FAILED -eq 0 ]]; then
        log_success "All migrations completed successfully!"
        return 0
    else
        log_error "Some migrations failed. Check backups and logs above."
        return 1
    fi
}

# Run main
main "$@"
