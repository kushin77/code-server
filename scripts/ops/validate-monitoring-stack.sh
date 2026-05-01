#!/usr/bin/env bash
################################################################################
# Monitoring Stack Validation Script
#
# Purpose: Automate validation of monitoring stack health and functionality
# Usage: bash scripts/ops/validate-monitoring-stack.sh [--full|--quick|--repair]
#
# Exit codes:
#   0 = All validation checks passed
#   1 = One or more checks failed (non-critical)
#   2 = Critical infrastructure issues found
#
################################################################################

set -euo pipefail

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; true' EXIT

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MONITORING_LOG="${ROOT_DIR}/.monitoring-validation.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${MONITORING_LOG}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "${MONITORING_LOG}"
    ((PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $*" | tee -a "${MONITORING_LOG}"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" | tee -a "${MONITORING_LOG}"
    ((FAILED++))
}

# Initialize log
mkdir -p "$(dirname "${MONITORING_LOG}")"
echo "=== Monitoring Stack Validation ===" > "${MONITORING_LOG}"
echo "Date: $(date)" >> "${MONITORING_LOG}"
echo "" >> "${MONITORING_LOG}"

# Parse arguments
VALIDATION_MODE="quick"  # quick or full
AUTO_REPAIR=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)
            VALIDATION_MODE="full"
            shift
            ;;
        --quick)
            VALIDATION_MODE="quick"
            shift
            ;;
        --repair)
            AUTO_REPAIR=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Starting monitoring stack validation (mode: ${VALIDATION_MODE})"

# ============================================================================
# PART 1: Service Health Check
# ============================================================================

echo ""
log_info "=== PART 1: Service Health Check ==="

check_service_status() {
    local service=$1
    local container="code-server-${service}"
    
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        local status=$(docker inspect -f '{{.State.Status}}' "${container}")
        if [ "${status}" = "running" ]; then
            log_success "${service} is running"
            return 0
        else
            log_error "${service} is ${status}"
            return 1
        fi
    else
        log_error "${service} container not found"
        return 1
    fi
}

# Check core monitoring services
for service in prometheus grafana alertmanager loki; do
    check_service_status "${service}" || true
done

# ============================================================================
# PART 2: Endpoint Connectivity Test
# ============================================================================

echo ""
log_info "=== PART 2: Endpoint Connectivity Test ==="

test_endpoint() {
    local name=$1
    local url=$2
    
    if curl -s "${url}" > /dev/null 2>&1; then
        log_success "${name} endpoint responding"
        return 0
    else
        log_error "${name} endpoint not responding"
        return 1
    fi
}

test_endpoint "Prometheus health" "http://localhost:9090/-/healthy"
test_endpoint "Grafana health" "http://localhost:3000/api/health"
test_endpoint "Alertmanager health" "http://localhost:9093/-/healthy"

# ============================================================================
# PART 3: Prometheus Metrics Collection
# ============================================================================

echo ""
log_info "=== PART 3: Prometheus Metrics Collection ==="

# Check active targets
ACTIVE_TARGETS=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq '.data.activeTargets | length' || echo 0)
if [ "${ACTIVE_TARGETS}" -gt 10 ]; then
    log_success "Prometheus has ${ACTIVE_TARGETS} active scrape targets"
else
    log_warning "Prometheus has only ${ACTIVE_TARGETS} active targets (expected >10)"
fi

# Check for down targets
DOWN_TARGETS=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq '[.data.activeTargets[] | select(.health=="down")] | length' || echo 0)
if [ "${DOWN_TARGETS}" -eq 0 ]; then
    log_success "All scrape targets are healthy"
else
    log_warning "Found ${DOWN_TARGETS} down targets"
fi

# Check metric data
METRIC_COUNT=$(curl -s 'http://localhost:9090/api/v1/query?query=up' 2>/dev/null | jq '.data.result | length' || echo 0)
if [ "${METRIC_COUNT}" -gt 15 ]; then
    log_success "Metrics being collected (${METRIC_COUNT} services reporting)"
else
    log_warning "Low metric collection (${METRIC_COUNT} services, expected >15)"
fi

# ============================================================================
# PART 4: Alert Rules Validation
# ============================================================================

echo ""
log_info "=== PART 4: Alert Rules Validation ==="

# Check alert rules loaded
ALERT_RULES=$(curl -s http://localhost:9090/api/v1/rules 2>/dev/null | jq '.data.groups[].rules | length' | awk '{sum+=$1} END {print sum}' || echo 0)
if [ "${ALERT_RULES}" -gt 20 ]; then
    log_success "Alert rules loaded (${ALERT_RULES} total rules)"
else
    log_warning "Low alert rule count (${ALERT_RULES}, expected >20)"
fi

# Check for alert evaluation errors
ALERT_ERRORS=$(curl -s http://localhost:9090/api/v1/rules 2>/dev/null | jq '[.data.groups[].rules[] | select(.state=="error")] | length' || echo 0)
if [ "${ALERT_ERRORS}" -eq 0 ]; then
    log_success "No alert rule evaluation errors"
else
    log_error "Found ${ALERT_ERRORS} alert rule evaluation errors"
fi

# ============================================================================
# PART 5: Alertmanager Configuration
# ============================================================================

echo ""
log_info "=== PART 5: Alertmanager Configuration ==="

# Check if routes configured
ROUTE_COUNT=$(curl -s http://localhost:9093/api/v1/status 2>/dev/null | jq '.config.routes | length' || echo 0)
if [ "${ROUTE_COUNT}" -gt 0 ]; then
    log_success "Alertmanager routes configured"
else
    log_warning "No alert routes found"
fi

# Check receivers configured
RECEIVER_COUNT=$(curl -s http://localhost:9093/api/v1/status 2>/dev/null | jq '.config.receivers | length' || echo 0)
if [ "${RECEIVER_COUNT}" -gt 0 ]; then
    log_success "Alertmanager receivers configured (${RECEIVER_COUNT} receivers)"
else
    log_error "No alert receivers configured"
fi

# ============================================================================
# PART 6: Grafana Datasources
# ============================================================================

echo ""
log_info "=== PART 6: Grafana Datasources ==="

# Note: Requires GRAFANA_API_TOKEN to be set
if [ -n "${GRAFANA_API_TOKEN:-}" ]; then
    DS_COUNT=$(curl -s -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
        http://localhost:3000/api/datasources 2>/dev/null | jq 'length' || echo 0)
    if [ "${DS_COUNT}" -gt 0 ]; then
        log_success "Grafana datasources configured (${DS_COUNT} datasources)"
    else
        log_warning "No datasources found in Grafana"
    fi
else
    log_warning "GRAFANA_API_TOKEN not set - skipping datasource check"
fi

# ============================================================================
# PART 7: Disk & Memory Metrics
# ============================================================================

echo ""
log_info "=== PART 7: Disk & Memory Metrics ==="

# Check Prometheus disk usage
PROM_DISK=$(docker exec code-server-prometheus du -sh /prometheus 2>/dev/null | awk '{print $1}' || echo "unknown")
log_info "Prometheus disk usage: ${PROM_DISK}"

# Check Loki disk usage
LOKI_DISK=$(docker exec code-server-loki du -sh /loki 2>/dev/null | awk '{print $1}' || echo "unknown")
log_info "Loki disk usage: ${LOKI_DISK}"

# Check Prometheus memory
PROM_MEM=$(docker stats --no-stream code-server-prometheus 2>/dev/null | tail -1 | awk '{print $6}' || echo "unknown")
log_success "Prometheus memory: ${PROM_MEM}"

# ============================================================================
# PART 8: Query Performance (Full mode only)
# ============================================================================

if [ "${VALIDATION_MODE}" = "full" ]; then
    echo ""
    log_info "=== PART 8: Query Performance Test ==="
    
    # Test simple query
    START_TIME=$(date +%s%N)
    curl -s 'http://localhost:9090/api/v1/query?query=up' > /dev/null
    END_TIME=$(date +%s%N)
    QUERY_TIME=$(( (END_TIME - START_TIME) / 1000000 ))  # Convert to milliseconds
    
    if [ "${QUERY_TIME}" -lt 1000 ]; then
        log_success "Query performance good (${QUERY_TIME}ms)"
    else
        log_warning "Query performance slow (${QUERY_TIME}ms, expected <1000ms)"
    fi
fi

# ============================================================================
# PART 9: Test Alert Delivery (Full mode only)
# ============================================================================

if [ "${VALIDATION_MODE}" = "full" ]; then
    echo ""
    log_info "=== PART 9: Alert Delivery Test ==="
    
    log_info "Sending test alert to Alertmanager..."
    curl -X POST http://localhost:9093/api/v1/alerts \
        -H "Content-Type: application/json" \
        -d '[{
            "labels": {
                "alertname": "MonitoringValidationTest",
                "severity": "warning",
                "service": "monitoring"
            },
            "annotations": {
                "summary": "Monitoring validation test alert",
                "description": "This is an automated test alert"
            }
        }]' 2>/dev/null
    
    sleep 2
    
    # Check if alert is visible
    ALERT_FOUND=$(curl -s 'http://localhost:9093/api/v1/alerts?filter=all' 2>/dev/null | \
        jq '[.data[] | select(.labels.alertname=="MonitoringValidationTest")] | length' || echo 0)
    
    if [ "${ALERT_FOUND}" -gt 0 ]; then
        log_success "Test alert successfully routed through Alertmanager"
    else
        log_warning "Test alert not found in Alertmanager"
    fi
fi

# ============================================================================
# Summary Report
# ============================================================================

echo ""
echo "==============================================="
log_info "=== VALIDATION SUMMARY ==="
echo "==============================================="
echo -e "${GREEN}Passed:${NC} ${PASSED}"
echo -e "${YELLOW}Warnings:${NC} ${WARNINGS}"
echo -e "${RED}Failed:${NC} ${FAILED}"
echo ""

if [ ${FAILED} -eq 0 ]; then
    log_success "Monitoring stack validation PASSED"
    EXIT_CODE=0
else
    log_error "Monitoring stack validation FAILED (${FAILED} critical issues)"
    EXIT_CODE=2
fi

# Save summary to log
{
    echo ""
    echo "=== VALIDATION SUMMARY ==="
    echo "Passed: ${PASSED}"
    echo "Warnings: ${WARNINGS}"
    echo "Failed: ${FAILED}"
    echo "Exit code: ${EXIT_CODE}"
} >> "${MONITORING_LOG}"

log_info "Full validation log saved to: ${MONITORING_LOG}"

exit ${EXIT_CODE}
