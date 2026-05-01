#!/bin/bash
set -euo pipefail
# @description Validate Environment SSOT
# @governance GOV-003: Environment SSOT

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

FILES=(".env.base" ".env.infrastructure" ".env.deployment" ".env.cluster" ".env.production")
declare -A VARS
log_info "Validating Environment SSOT..."
for file in "${FILES[@]}"; do
    if [[ -f "$file" ]]; then
        log_info "Checking $file..."
        while IFS= read -r line; do
            if [[ "$line" =~ ^(export[[:space:]]+)?([A-Z0-9_]+)= ]]; then
                var_name="${BASH_REMATCH[2]}"
                if [[ -n "${VARS[$var_name]:-}" ]]; then
                    echo "  [DUPLICATE] $var_name found in $file (already defined in ${VARS[$var_name]})"
                fi
                VARS[$var_name]=$file
            fi
        done < "$file"
    fi
done
log_info "Validation complete: ${#VARS[@]} unique variables found"
