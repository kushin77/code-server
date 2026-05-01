#!/bin/bash

###
# @file codebase-hygiene-audit.sh
# @module scripts/ci/codebase-hygiene-audit.sh
# @description Comprehensive codebase hygiene and deduplication audit
# @compliance IaC, idempotent, audit logging
###

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Source initialization
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${PROJECT_ROOT}/scripts/_common/init.sh" || {
    echo "FATAL: Cannot source init.sh" >&2
    exit 1
}

# Report generation
AUDIT_REPORT="${PROJECT_ROOT}/artifacts/reports/codebase-hygiene-audit.json"
mkdir -p "$(dirname "$AUDIT_REPORT")"

# Counters
declare -A audit_results=(
    [total_scripts]=0
    [scripts_with_issues]=0
    [duplicate_sourcing]=0
    [inline_logging]=0
    [hardcoded_ips]=0
    [missing_headers]=0
    [high_complexity]=0
)

declare -a issues=()
blocking_issues=0

log_info "=== P3 #1533 Phase 1: Codebase Hygiene Audit ===" | tee -a "${AUDIT_REPORT}.log"
log_info "Repository: ${PROJECT_ROOT}" | tee -a "${AUDIT_REPORT}.log"
log_info "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')" | tee -a "${AUDIT_REPORT}.log"
log_info "" | tee -a "${AUDIT_REPORT}.log"

# ============================================================================
# CHECK 1: Duplicate Direct Sourcing (must use init.sh only)
# ============================================================================

log_info "CHECK 1: Direct sourcing of individual _common/* files (should use init.sh)"

while IFS= read -r script; do
    if [[ "$(basename "$script")" == "codebase-hygiene-audit.sh" ]]; then
        continue
    fi
    if grep -qE 'source.*scripts/_common/(logging|config|utils)\.sh|source.*scripts/_common/_base' "$script" 2>/dev/null; then
        audit_results[duplicate_sourcing]+=1
        blocking_issues+=1
        issues+=("DUPLICATE_SOURCING: $script - direct sourcing of _common/*.sh files (must use init.sh)")
        log_warn "  $script: direct sourcing detected"
    fi
done < <(find "${PROJECT_ROOT}/scripts" -name "*.sh" -type f)

# ============================================================================
# CHECK 2: Inline Logging (should use log_error, log_warn, etc.)
# ============================================================================

log_info "CHECK 2: Inline echo logging (should use log_error/log_warn functions)"

while IFS= read -r script; do
    if grep -qE 'echo.*"(ERROR|WARN|INFO|DEBUG):' "$script" 2>/dev/null; then
        audit_results[inline_logging]+=1
        blocking_issues+=1
        issues+=("INLINE_LOGGING: $script - using echo for logging instead of log_* functions")
        log_warn "  $script: inline logging detected"
    fi
done < <(find "${PROJECT_ROOT}/scripts" -name "*.sh" -type f)

# ============================================================================
# CHECK 3: Hardcoded IPs (should use env vars)
# ============================================================================

log_info "CHECK 3: Hardcoded IPs (should use \$PRIMARY_HOST, \$REPLICA_HOST, etc.)"

readonly AUDIT_HOSTS=("${PRIMARY_HOST}" "${REPLICA_HOST}" "${NAS_HOST}")

# Search for hardcoded IPs in scripts (exclude comments and templates)
while IFS= read -r script; do
    for host in "${AUDIT_HOSTS[@]}"; do
        if grep -F "$host" "$script" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v 'APEX_DOMAIN\|template\|example' >/dev/null; then
            audit_results[hardcoded_ips]+=1
            blocking_issues+=1
            issues+=("HARDCODED_IP: $script - contains hardcoded IP addresses")
            log_warn "  $script: hardcoded IP detected"
            break
        fi
    done
done < <(find "${PROJECT_ROOT}/scripts" -name "*.sh" -type f)

# ============================================================================
# CHECK 4: Missing GOV-002 Headers
# ============================================================================

log_info "CHECK 4: Missing GOV-002 metadata headers (@file, @module, @description)"

while IFS= read -r script; do
    if ! head -10 "$script" | grep -q '@file' || ! head -10 "$script" | grep -q '@module' || ! head -10 "$script" | grep -q '@description'; then
        audit_results[missing_headers]+=1
        blocking_issues+=1
        issues+=("MISSING_HEADER: $script - GOV-002 metadata incomplete")
        log_warn "  $script: GOV-002 header incomplete"
    fi
done < <(find "${PROJECT_ROOT}/scripts" -name "*.sh" -type f)

# ============================================================================
# CHECK 5: Line Count (complexity indicator)
# ============================================================================

log_info "CHECK 5: Function complexity (functions > 100 lines)"

while IFS= read -r script; do
    # Find functions longer than 100 lines
    awk '/^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\s*\)/ {
        func_name=$1; start=NR; next
    }
    /^}$/ && start && (NR - start) > 100 {
        print "  " script ": " func_name " (" (NR - start) " lines)"
        start=0
        next
    }' "$script" | while read -r line; do
        if [[ -n "$line" ]]; then
            audit_results[high_complexity]=$((audit_results[high_complexity] + 1))
            issues+=("HIGH_COMPLEXITY: $line")
            log_warn "$line"
        fi
    done
done < <(find "${PROJECT_ROOT}/scripts" -name "*.sh" -type f)

# ============================================================================
# CHECK 6: Total Script Count
# ============================================================================

log_info "CHECK 6: Script inventory"

audit_results[total_scripts]=$(find "${PROJECT_ROOT}/scripts" -name "*.sh" -type f | wc -l)
log_info "  Total scripts: ${audit_results[total_scripts]}"

for category in _common ci lib ops audit monitoring extensions ide; do
    count=$(find "${PROJECT_ROOT}/scripts/$category" -name "*.sh" -type f 2>/dev/null | wc -l)
    if [[ $count -gt 0 ]]; then
        log_info "    scripts/$category/: $count scripts"
    fi
done

# ============================================================================
# CHECK 7: Docker Compose Orphan Services
# ============================================================================

log_info "CHECK 7: Docker Compose service inventory"

if [[ -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
    service_count=$(grep -E '^\s+[a-z-]+:$' "${PROJECT_ROOT}/docker-compose.yml" | wc -l)
    log_info "  Services in docker-compose.yml: $service_count"
fi

# ============================================================================
# SUMMARY
# ============================================================================

log_info ""
log_info "=== AUDIT SUMMARY ==="
log_info "Total issues found: ${#issues[@]}"
log_info "Blocking issues found: ${blocking_issues}"
log_info "  - Duplicate sourcing: ${audit_results[duplicate_sourcing]}"
log_info "  - Inline logging: ${audit_results[inline_logging]}"
log_info "  - Hardcoded IPs: ${audit_results[hardcoded_ips]}"
log_info "  - Missing headers: ${audit_results[missing_headers]}"
log_info "  - High complexity functions: ${audit_results[high_complexity]}"

# Generate JSON report
cat > "$AUDIT_REPORT" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "repository": "${PROJECT_ROOT}",
  "audit_results": {
    "total_scripts": ${audit_results[total_scripts]},
    "duplicate_sourcing": ${audit_results[duplicate_sourcing]},
    "inline_logging": ${audit_results[inline_logging]},
    "hardcoded_ips": ${audit_results[hardcoded_ips]},
    "missing_headers": ${audit_results[missing_headers]},
    "high_complexity_functions": ${audit_results[high_complexity]}
  },
  "total_issues": ${#issues[@]},
  "issues": [
EOF

for issue in "${issues[@]}"; do
    printf '    "%s",\n' "$issue" >> "$AUDIT_REPORT"
done

# Remove trailing comma from last entry
sed -i '$ s/,$//' "$AUDIT_REPORT"

cat >> "$AUDIT_REPORT" <<EOF
  ]
}
EOF

log_info ""
log_info "Report written to: $AUDIT_REPORT"

# Exit with error if blocking issues found
if [[ ${blocking_issues} -gt 0 ]]; then
    log_error "Audit found ${blocking_issues} blocking issues requiring attention"
    exit 1
else
    if [[ ${#issues[@]} -gt 0 ]]; then
        log_warn "Audit passed with advisory complexity findings"
    else
        log_info "✓ Audit PASSED - No issues found"
    fi
    exit 0
fi
