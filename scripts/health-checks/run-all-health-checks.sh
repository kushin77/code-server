#!/usr/bin/env bash
# @file        scripts/health-checks/run-all-health-checks.sh
# @module      operations/health-checks
# @description Orchestrate all health checks and report comprehensive system status
# @owner       Infrastructure Team
# @status      Production ready - April 23, 2026
#
# Runs all health check scripts sequentially and provides:
# - Individual check results
# - Overall system health status
# - Failed checks summary
# - Integration with monitoring systems

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source logging from common directory
source "$SCRIPT_DIR/../_common/init.sh"
    # Fallback if common logging not available
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
    log_fatal() { echo "[FATAL] $*"; }
}

# Configuration
RESULTS_DIR="${PROJECT_DIR}/artifacts/health-checks"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${RESULTS_DIR}/health-report-${TIMESTAMP}.txt"
JSON_FILE="${RESULTS_DIR}/health-report-${TIMESTAMP}.json"

# Health check tracking
declare -A CHECK_RESULTS
declare -A CHECK_TIMES
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Helper functions
run_health_check() {
    local check_name="$1"
    local check_script="$2"
    
    if [[ ! -f "$check_script" ]]; then
        log_error "Health check script not found: $check_script"
        CHECK_RESULTS["$check_name"]="SKIP"
        return 1
    fi
    
    log_info "Running health check: $check_name"
    
    local start_time
    start_time=$(date +%s%N)
    
    local result=0
    local output
    output=$(bash "$check_script" 2>&1) || result=$?
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    CHECK_RESULTS["$check_name"]="$result"
    CHECK_TIMES["$check_name"]="$duration_ms"
    
    case "$result" in
        0)
            log_info "✓ $check_name PASSED (${duration_ms}ms)"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            ;;
        1)
            log_warn "⚠ $check_name WARNING (${duration_ms}ms)"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            ;;
        *)
            log_error "✗ $check_name FAILED (${duration_ms}ms)"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            ;;
    esac
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

# Create results directory
mkdir -p "$RESULTS_DIR"

# Header
{
    echo "========================================"
    echo "HEALTH CHECK REPORT"
    echo "========================================"
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Host: $(hostname)"
    echo ""
} | tee "$REPORT_FILE"

log_info "Starting comprehensive health check suite..."
log_info "Results: $RESULTS_DIR"
log_info ""

# Run all health checks
log_info "Executing health checks..."
log_info ""

# 1. PgBouncer Health Check
run_health_check "PgBouncer Connection Pool" \
    "$SCRIPT_DIR/check-pgbouncer-health.sh"

# 2. Backup Status Check
run_health_check "Database Backup Status" \
    "$SCRIPT_DIR/check-backup-status.sh"

# 3. Replication Lag Check
run_health_check "PostgreSQL Replication Lag" \
    "$SCRIPT_DIR/check-replication-lag.sh"

log_info ""
log_info "========================================"
log_info "HEALTH CHECK SUMMARY"
log_info "========================================"

# Summary
{
    echo ""
    echo "========================================"
    echo "SUMMARY"
    echo "========================================"
    echo "Total Checks: $TOTAL_CHECKS"
    echo "Passed: $PASSED_CHECKS"
    echo "Failed/Warning: $FAILED_CHECKS"
    echo ""
    
    # Determine overall health
    if (( FAILED_CHECKS == 0 )); then
        echo -e "${GREEN}Overall Status: HEALTHY${NC}"
        OVERALL_STATUS="HEALTHY"
    elif (( FAILED_CHECKS < TOTAL_CHECKS / 2 )); then
        echo -e "${YELLOW}Overall Status: DEGRADED${NC}"
        OVERALL_STATUS="DEGRADED"
    else
        echo -e "${RED}Overall Status: UNHEALTHY${NC}"
        OVERALL_STATUS="UNHEALTHY"
    fi
    
    echo ""
    echo "Individual Check Results:"
    for check in "${!CHECK_RESULTS[@]}"; do
        local result="${CHECK_RESULTS[$check]}"
        local time="${CHECK_TIMES[$check]:-0}"
        
        case "$result" in
            0)
                echo -e "  ${GREEN}✓${NC} $check (${time}ms)"
                ;;
            1)
                echo -e "  ${YELLOW}⚠${NC} $check (${time}ms)"
                ;;
            *)
                echo -e "  ${RED}✗${NC} $check (${time}ms)"
                ;;
        esac
    done
    
    echo ""
    echo "Report generated: $REPORT_FILE"
    echo "JSON report: $JSON_FILE"
    echo "========================================"
} | tee -a "$REPORT_FILE"

# Generate JSON output for monitoring integration
{
    echo "{"
    echo "  \"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
    echo "  \"hostname\": \"$(hostname)\","
    echo "  \"overall_status\": \"$OVERALL_STATUS\","
    echo "  \"summary\": {"
    echo "    \"total_checks\": $TOTAL_CHECKS,"
    echo "    \"passed\": $PASSED_CHECKS,"
    echo "    \"failed_warning\": $FAILED_CHECKS"
    echo "  },"
    echo "  \"checks\": {"
    
    local first=true
    for check in "${!CHECK_RESULTS[@]}"; do
        local result="${CHECK_RESULTS[$check]}"
        local time="${CHECK_TIMES[$check]:-0}"
        
        if [[ "$first" == false ]]; then
            echo ","
        fi
        first=false
        
        echo -n "    \"$check\": {\"status\": $result, \"duration_ms\": $time}"
    done
    
    echo ""
    echo "  }"
    echo "}"
} > "$JSON_FILE"

log_info "✓ Health check report saved to $REPORT_FILE"
log_info "✓ JSON report saved to $JSON_FILE"

# Determine exit code
if (( FAILED_CHECKS == 0 )); then
    exit 0
elif (( FAILED_CHECKS < TOTAL_CHECKS / 2 )); then
    exit 1
else
    exit 2
fi
