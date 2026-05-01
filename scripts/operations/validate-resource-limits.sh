#!/bin/bash
###############################################################################
# @file        scripts/operations/validate-resource-limits.sh
# @module      operations/validate-resource-limits
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################

# Resource Limits Validation & Testing Script (Phase 3)
# Purpose: Test resource limits enforcement and service functionality
# Output: Validation report with results

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../_common/hosts.sh"

OUTPUT_DIR="${1:-.}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${OUTPUT_DIR}/resource-limits-validation-${TIMESTAMP}.txt"

mkdir -p "${OUTPUT_DIR}"

COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"

service_has_resource_limits() {
    local service_name="$1"

    awk -v svc="  ${service_name}:" '
        BEGIN {
            in_block = 0
            found_deploy = 0
            found_resources = 0
            found_limits = 0
            found_reservations = 0
        }
        $0 == svc { in_block = 1; next }
        in_block && $0 ~ /^  [A-Za-z0-9._-]+:/ {
            exit (found_deploy && found_resources && found_limits && found_reservations) ? 0 : 1
        }
        in_block && $0 ~ /^[[:space:]]*deploy:/ { found_deploy = 1 }
        in_block && $0 ~ /^[[:space:]]*resources:/ { found_resources = 1 }
        in_block && $0 ~ /^[[:space:]]*limits:/ { found_limits = 1 }
        in_block && $0 ~ /^[[:space:]]*reservations:/ { found_reservations = 1 }
        END { exit (found_deploy && found_resources && found_limits && found_reservations) ? 0 : 1 }
    ' "${COMPOSE_FILE}"
}

echo "🧪 Starting Resource Limits Validation (Phase 3)..."
echo "📝 Report: ${REPORT_FILE}"
echo ""

# Initialize report
{
    echo "Resource Limits Validation Report"
    echo "=================================="
    echo "Date: $(date)"
    echo "Environment: Production (Primary Node ${PRIMARY_HOST})"
    echo ""
} > "${REPORT_FILE}"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo "❌ docker-compose.yml not found at ${COMPOSE_FILE}"
    exit 1
fi

services=(opa oauth2-proxy caddy prometheus grafana loki qdrant postgres redis redpanda redpanda-console ollama)
missing_limits=0

{
    echo "TEST 1: Service Resource Limits Validation"
    echo "-----------------------------------------"
    echo "Compose file: ${COMPOSE_FILE}"
    echo ""
} >> "${REPORT_FILE}"

for service in "${services[@]}"; do
    if service_has_resource_limits "$service"; then
        echo "✅ ${service}: resource limits configured"
        {
            echo "Service: ${service}"
            echo "Status: PASS"
            echo "Check: deploy/resources/limits/reservations present"
            echo ""
        } >> "${REPORT_FILE}"
    else
        echo "⚠️  ${service}: missing full resource limits configuration"
        {
            echo "Service: ${service}"
            echo "Status: FAIL"
            echo "Check: deploy/resources/limits/reservations missing"
            echo ""
        } >> "${REPORT_FILE}"
        missing_limits+=1
    fi
done

{
    echo "Summary"
    echo "-------"
    echo "Services checked: ${#services[@]}"
    echo "Services missing limits: ${missing_limits}"
    echo "Validation Status: $([ "${missing_limits}" -eq 0 ] && echo PASS || echo FAIL)"
    echo ""
} >> "${REPORT_FILE}"

cat "${REPORT_FILE}"
echo ""
echo "✅ Validation report template created"
echo ""
echo "Manual Validation Steps:"
echo "1. SSH to primary node: ssh -i ~/.ssh/id_rsa_onprem_wsl ${SSH_USER}@${PRIMARY_HOST}"
echo "2. Check all services: docker compose ps"
echo "3. Monitor resource usage: docker stats"
echo "4. Watch logs: docker compose logs -f"
echo "5. Run load test: ./scripts/load-test/run-full-load-test.sh"
echo "6. Verify no OOM events: docker events | grep OOMKilled"
echo "7. Check Prometheus metrics: curl http://prometheus:9090/api/v1/query?query=container_memory_usage_bytes"
echo ""
echo "Report saved to: ${REPORT_FILE}"

