#!/bin/bash
# Deduplicate .env file - keep last value for each key

set -euo pipefail

ENV_FILE="${1:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: $ENV_FILE not found"
    exit 1
fi

echo "Deduplicating $ENV_FILE..."
echo "Original lines: $(wc -l < "$ENV_FILE")"

# Create deduplicated version: keep last occurrence of each key
awk -F= '
    NF >= 1 {
        key = $1
        gsub(/^[[:space:]]+/, "", key)
        if (key != "" && key !~ /^#/) {
            values[key] = $0
        } else if (key == "" || key ~ /^#/) {
            # Keep blank lines and comments
            lines[NR] = $0
        }
    }
    END {
        for (key in values) {
            print values[key]
        }
    }
' "$ENV_FILE" | sort > "${ENV_FILE}.tmp"

mv "${ENV_FILE}.tmp" "$ENV_FILE"

echo "Deduplicated lines: $(wc -l < "$ENV_FILE")"
echo "✅ Deduplication complete"
