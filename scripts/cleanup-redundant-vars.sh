#!/bin/bash
set -euo pipefail
# @description Enforce Single Source of Truth by commenting out redundant vars
# @governance GOV-003: Environment SSOT

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

clean_file() {
    local target=$1
    shift
    local priorities=("$@")
    [[ ! -f "$target" ]] && return
    
    log_info "Cleaning $target..."
    TEMP_FILE=$(mktemp)
    while IFS= read -r line; do
        if [[ "$line" =~ ^(export[[:space:]]+)?([A-Z0-9_]+)= ]]; then
            var_name="${BASH_REMATCH[2]}"
            found=false
            for prio in "${priorities[@]}"; do
                if grep -qE "^(export[[:space:]]+)?$var_name=" "$prio" 2>/dev/null; then
                    found=true
                    break
                fi
            done
            if [ "$found" = true ]; then
                echo "# [SSOT] Redundant: $line" >> "$TEMP_FILE"
            else
                echo "$line" >> "$TEMP_FILE"
            fi
        else
            echo "$line" >> "$TEMP_FILE"
        fi
    done < "$target"
    mv "$TEMP_FILE" "$target"
}

clean_file .env.base .env.production .env.cluster .env.deployment .env.infrastructure
clean_file .env.infrastructure .env.production .env.cluster .env.deployment
clean_file .env.deployment .env.production .env.cluster
clean_file .env.cluster .env.production
