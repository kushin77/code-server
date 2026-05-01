#!/bin/bash
# Detect drift in variable values across the environment hierarchy

set -euo pipefail
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

FILES=(".env.base" ".env.infrastructure" ".env.deployment" ".env.cluster" ".env.production")
VARS=$(grep -vE "^#|^$" "${FILES[@]}" | cut -d: -f2 | cut -d= -f1 | sort | uniq -d)

echo "Detecting Variable Value Drift..."

for var in $VARS; do
    echo "Variable: $var"
    for file in "${FILES[@]}"; do
        if [[ -f "$file" ]]; then
            val=$(grep "^$var=" "$file" | cut -d= -f2-)
            if [[ -n "$val" ]]; then
                echo "  $file: $val"
            fi
        fi
    done
done
