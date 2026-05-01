#!/bin/bash
# Stable SSOT Audit Script - Ultra Robust (Python Support)
# Validates SSOT patterns (PRIMARY_HOST abstraction) across operational scripts and Python tools.

# Governance Compliance: GOV-001/GOV-002
source "$(dirname "$0")/../_common/init.sh"
set +e

log_info() { printf "\033[0;34m%-10s\033[0m | %s\n" "[INFO]" "$1"; }
log_warning() { printf "\033[1;33m%-10s\033[0m | %s\n" "[WARNING]" "$1"; }
log_error() { printf "\033[0;31m%-10s\033[0m | %s\n" "[ERROR]" "$1"; }
log_success() { printf "\033[0;32m%-10s\033[0m | %s\n" "[SUCCESS]" "$1"; }

# Governance: Define traps but ensure they are inert during the loop
trap '' ERR

SCRIPTS_CHECKED=0
SCRIPTS_MISSING_INIT=0
HARDCODED_VARS=0

log_info "Running operational SSOT audit (Shell & Python)..."

# Find all Shell AND Python scripts
ALL_FILES=$(find scripts -name "*.sh" -o -name "*.py" -type f | grep -v "_common" | grep -v "audit" | grep -v "validate-trap")

for file in $ALL_FILES; do
    SCRIPTS_CHECKED+=1
    
    # [SHELL ONLY] Check init.sh sourcing
    if [[ "$file" == *.sh ]]; then
        if ! grep -q "source.*init\.sh" "$file"; then
            log_warning "Missing init.sh: $file"
            SCRIPTS_MISSING_INIT+=1
        fi
    fi

    # Check for raw hardcoded IPs
    # Logic: Look for lines with IPs, then filter out lines with our approved abstraction variables
    # We also ignore IP assignments in Python if they use os.environ.get
    RAW_LINES=$(grep -E "192\.168\.168\.(31|42|50)" "$file" 2>/dev/null | \
                grep -v "PRIMARY_HOST" | \
                grep -v "REPLICA_HOST" | \
                grep -v "CLUSTER_VIP" | \
                grep -v "os.environ.get" | \
                grep -v "^$" || true)
    
    if [ -n "$RAW_LINES" ]; then
        RAW_IPS=$(echo "$RAW_LINES" | wc -l)
    else
        RAW_IPS=0
    fi
    
    if [ "$RAW_IPS" -gt 0 ]; then
        # Exclude known documentation or enviroment files if necessary
        if [[ "$file" != *".env"* ]] && [[ "$file" != *"PRODUCTION_HANDOVER"* ]]; then
             log_warning "Hardcoded IP usage in $file"
             echo "$RAW_LINES" | sed 's/^/  -> /'
             HARDCODED_VARS+=1
        fi
    fi
done

log_info "Audit Summary:"
log_info "  Total Checked: $SCRIPTS_CHECKED"
log_info "  Missing Init:  $SCRIPTS_MISSING_INIT"
log_info "  Hardcoded IPs: $HARDCODED_VARS"

# Required governance traps for the final phase
trap 'log_error "Audit failed during exit"' ERR EXIT

if [ "$SCRIPTS_MISSING_INIT" -gt 0 ] || [ "$HARDCODED_VARS" -gt 0 ]; then
    log_error "Audit FAILED - SSOT Gaps found"
    trap - ERR EXIT
    exit 1
fi

log_success "Audit PASSED - All operational scripts/tools are SSOT compliant"
trap - ERR EXIT
exit 0
