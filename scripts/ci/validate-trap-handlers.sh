#!/usr/bin/env bash
# Minimal Trap Validator - Robust Version
set -uo pipefail

# Minimal logging
log_info() { printf "\033[0;34m%-10s\033[0m | %s\n" "[INFO]" "$1"; }
log_success() { printf "\033[0;32m%-10s\033[0m | %s\n" "[SUCCESS]" "$1"; }
log_error() { printf "\033[0;31m%-10s\033[0m | %s\n" "[ERROR]" "$1"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_CHECKED=0
SCRIPTS_FAIL=0

log_info "Starting trap handler validation audit..."

while read -r script; do
    # Skip non-bash or very short scripts
    if ! head -1 "$script" | grep -q "bash"; then continue; fi
    if [[ $(wc -l < "$script") -lt 15 ]]; then continue; fi
    if [[ "$script" == *"init.sh"* ]]; then continue; fi

    SCRIPTS_CHECKED+=1
    
    # We look for ANY form of trap assignment
    if ! grep -q "trap.*ERR" "$script" || ! grep -q "trap.*EXIT" "$script"; then
        log_error "Missing required traps in: $script"
        SCRIPTS_FAIL+=1
    fi
done < <(find "$REPO_ROOT/scripts/ops" "$REPO_ROOT/scripts/ci" -name "*.sh" -type f)

log_info "Audit Summary: $SCRIPTS_CHECKED checked, $SCRIPTS_FAIL failed"

if [ $SCRIPTS_FAIL -gt 0 ]; then
    log_error "NON-COMPLIANT: $SCRIPTS_FAIL scripts are missing trap handlers"
    exit 1
fi

log_success "COMPLIANT: All operational scripts have required trap handlers"
exit 0
