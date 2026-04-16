#!/bin/bash
# scripts/lib/check-no-ips.sh
# ============================
# Pre-commit hook: block hardcoded production IPs from entering active code.
# IPs must live ONLY in:
#   - environments/production/hosts.yml  (canonical inventory)
#   - config/coredns/zones/              (DNS zone files)
#   - SUPPORTED-PLATFORMS.md            (documentation)
#
# Usage (automatic via pre-commit):
#   pre-commit run no-hardcoded-ips
#
# Manual usage:
#   bash scripts/lib/check-no-ips.sh

set -euo pipefail

# Production IPs that must not be hardcoded in active code
BLOCKED_IPS=(
    "192.168.168.31"
    "192.168.168.42"
    "192.168.168.30"
)

# Patterns that indicate a real hardcoded IP (not a variable reference)
# We block: bare IPs in config values, SSH targets, curl URLs
# We allow: variable assignments that set the default (env.sh patterns)

# Files and directories that are ALLOWED to contain these IPs
ALLOWED_PATTERNS=(
    "environments/"
    "config/coredns/"
    "deprecated/"
    "archived/"
    "scripts/_archive/"
    "SUPPORTED-PLATFORMS.md"
    "scripts/lib/env.sh"         # The env.sh that exports these as variables
    "check-no-ips.sh"            # This script itself
)

ISSUES=0
SCANNED=0

# Get list of staged files (for pre-commit) or all files (for manual run)
if [[ -n "${PRE_COMMIT_FILES:-}" ]]; then
    FILES="$PRE_COMMIT_FILES"
else
    # Manual run: scan all relevant files
    FILES=$(git ls-files "*.sh" "*.tf" "*.yml" "*.yaml" 2>/dev/null || true)
fi

for file in $FILES; do
    # Skip allowed paths
    SKIP=false
    for allowed in "${ALLOWED_PATTERNS[@]}"; do
        if [[ "$file" == *"$allowed"* ]]; then
            SKIP=true
            break
        fi
    done
    $SKIP && continue

    # Skip if file doesn't exist (deleted)
    [[ -f "$file" ]] || continue

    SCANNED=$((SCANNED + 1))

    for ip in "${BLOCKED_IPS[@]}"; do
        # Find IP occurrences that are NOT variable assignments (allow: PRIMARY_HOST="192.168.168.31")
        FOUND=$(grep -n "$ip" "$file" \
            | grep -v "^[[:space:]]*#" \
            | grep -v 'PRIMARY_HOST.*=.*".*192\.168\.168\.' \
            | grep -v 'REPLICA_HOST.*=.*".*192\.168\.168\.' \
            | grep -v 'VIP.*=.*".*192\.168\.168\.' \
            | grep -v "ip:.*192\.168\.168\." \
            || true)

        if [[ -n "$FOUND" ]]; then
            echo "ERROR: Hardcoded production IP '$ip' found in $file:"
            echo "$FOUND" | sed 's/^/  /'
            echo ""
            echo "  Fix: source scripts/lib/env.sh and use \$PRIMARY_HOST, \$REPLICA_HOST, \$VIP"
            echo "  Or use FQDNs: primary.prod.internal, replica.prod.internal"
            ISSUES=$((ISSUES + 1))
        fi
    done
done

if [[ "$ISSUES" -gt 0 ]]; then
    echo "═══════════════════════════════════════════════════════"
    echo "  BLOCKED: $ISSUES file(s) contain hardcoded production IPs"
    echo "  IPs must only appear in environments/production/hosts.yml"
    echo "  See: SUPPORTED-PLATFORMS.md and scripts/lib/env.sh"
    echo "═══════════════════════════════════════════════════════"
    exit 1
else
    echo "✅ No hardcoded production IPs found ($SCANNED files scanned)"
    exit 0
fi
