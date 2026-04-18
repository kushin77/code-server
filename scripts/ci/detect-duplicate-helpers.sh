#!/usr/bin/env bash
# @file        scripts/ci/detect-duplicate-helpers.sh
# @module      ci/governance
# @description Detect re-implementation of canonical helper functions from scripts/_common and scripts/lib
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

# Source logging if available
if [[ -f "scripts/_common/init.sh" ]]; then
    source "scripts/_common/init.sh" 2>/dev/null || true
fi

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_fatal() { echo "[FATAL] $*" >&2; exit 1; }

VIOLATIONS=0
WARNINGS=0

# ─── Check 1: Re-implemented canonical functions ─────────────────────────────
log_info "Checking for re-implemented canonical helper functions..."

# Extract canonical function names from _common and lib
CANONICAL_FUNCS=$(grep -rhE '^[a-z_]+\(\)' \
    scripts/_common/ \
    scripts/lib/ \
    2>/dev/null \
    | grep -oE '^[a-z_]+' \
    | grep -v '^_' \
    | sort -u)

while IFS= read -r func; do
    # Skip very short/generic names that might legitimately appear in user scripts
    [[ ${#func} -lt 4 ]] && continue

    # Find files that define this function outside of _common/ and lib/
    matches=$(grep -rlE "^${func}\(\)" \
        scripts/ \
        --include="*.sh" \
        2>/dev/null \
        | grep -v "scripts/_common/" \
        | grep -v "scripts/lib/" \
        | grep -v "scripts/_archive/" \
        | grep -v "scripts/logging.sh" \
        | grep -v "scripts/ci/detect-duplicate-helpers.sh" \
        || true)

    if [[ -n "$matches" ]]; then
        while IFS= read -r file; do
            log_warn "Duplicate function '${func}()' defined in $file — use canonical from scripts/_common/ or scripts/lib/"
            WARNINGS=$((WARNINGS + 1))
        done <<< "$matches"
    fi
done <<< "$CANONICAL_FUNCS"

# ─── Check 2: Inline error patterns that should use log_* ────────────────────
log_info "Checking for inline echo-based error/fatal patterns..."

# Find echo "ERROR:" or similar patterns in scripts (excluding _common itself)
while IFS= read -r line; do
    file="${line%%:*}"
    content=$(echo "$line" | cut -d: -f3-)
    # Skip comments and the logging file itself
    if [[ "$content" =~ ^[[:space:]]*# ]]; then continue; fi
    if [[ "$file" =~ scripts/_common/ ]]; then continue; fi
    log_warn "Inline echo-error pattern in $file: $content — use log_error or log_fatal instead"
    WARNINGS=$((WARNINGS + 1))
done < <(grep -rn \
    -e 'echo "ERROR:' \
    -e "echo 'ERROR:" \
    -e 'echo "FATAL:' \
    -e "echo 'FATAL:" \
    -e 'echo -e "ERROR' \
    scripts/ \
    --include="*.sh" \
    2>/dev/null \
    | grep -v "scripts/_common/" \
    | grep -v "scripts/ci/" \
    || true)

# ─── Check 3: Duplicate compose service definitions ──────────────────────────
log_info "Checking for duplicate service names across compose files..."

# Build list of service names per compose file
SEEN_SERVICES=()
COMPOSE_FILES=(docker-compose.yml docker-compose.production.yml docker-compose.base.yml docker-compose.dev.yml)

for cf in "${COMPOSE_FILES[@]}"; do
    [[ ! -f "$cf" ]] && continue
    while IFS= read -r svc; do
        # Check if we've seen this service in another compose file
        for seen in "${SEEN_SERVICES[@]:-}"; do
            if [[ "$seen" == "$svc" ]]; then
                log_warn "Service '$svc' appears in multiple compose files — potential overlap"
                WARNINGS=$((WARNINGS + 1))
                break
            fi
        done
        SEEN_SERVICES+=("$svc")
    done < <(python3 -c "
import sys, re
with open('$cf') as f:
    content = f.read()
matches = re.findall(r'^  ([a-z][a-z0-9_-]+):$', content, re.MULTILINE)
for m in matches: print(m)
" 2>/dev/null || true)
done

# ─── Report ───────────────────────────────────────────────────────────────────
echo ""
if [[ $VIOLATIONS -gt 0 ]]; then
    log_fatal "Deduplication violations found: $VIOLATIONS violations, $WARNINGS warnings. See docs/DEDUPLICATION-POLICY.md"
elif [[ $WARNINGS -gt 0 ]]; then
    log_warn "Deduplication warnings: $WARNINGS. Consider refactoring. See docs/DEDUPLICATION-POLICY.md"
    echo "[INFO] ⚠️  Deduplication check passed with $WARNINGS warnings"
    exit 0
else
    echo "[INFO] ✅ Deduplication check passed — no duplicates detected"
fi
