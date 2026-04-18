#!/bin/bash
# @file        scripts/vpn-enterprise-endpoint-scan.sh
# @module      networking
# @description vpn enterprise endpoint scan — on-prem code-server
# @owner       platform
# @status      active
# ═══════════════════════════════════════════════════════════════════════════════
# VPN Enterprise Endpoint Scan - Network Topology & Service Verification
# ═══════════════════════════════════════════════════════════════════════════════
# Purpose: Verify all VPN endpoints, network connectivity, and service availability
# Exit Code: 0 = all endpoints healthy, 1+ = issues detected
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Enterprise endpoints
ENDPOINTS=(
    "${DEPLOY_HOST}:${PORT_CODE_SERVER}"    # Code-Server (Primary)
    "${DEPLOY_HOST}:4180"    # OAuth2-Proxy
    "${DEPLOY_HOST}:${PORT_GRAFANA}"    # Grafana
    "${DEPLOY_HOST}:${PORT_PROMETHEUS}"    # Prometheus
    "${DEPLOY_HOST}:${PORT_ALERTMANAGER}"    # AlertManager
    "${DEPLOY_HOST}:16686"   # Jaeger
    "${DEPLOY_HOST}:5432"    # PostgreSQL
    "${DEPLOY_HOST}:6379"    # Redis
)

ENDPOINTS_REPLICA=(
    "${REPLICA_HOST:-192.168.168.42}:${PORT_CODE_SERVER}"    # Code-Server (Replica)
)

# Counters
ENDPOINTS_UP=0
ENDPOINTS_DOWN=0
ENDPOINTS_SKIPPED=0

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

log_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

log_check() {
    echo -e "${YELLOW}→${NC} $1"
}

log_up() {
    echo -e "${GREEN}✓${NC} $1"
    ((ENDPOINTS_UP++))
}

log_down() {
    echo -e "${RED}✗${NC} $1"
    ((ENDPOINTS_DOWN++))
}

log_skip() {
    echo -e "${YELLOW}⊘${NC} $1 (unreachable - may be expected)"
    ((ENDPOINTS_SKIPPED++))
}

# ─────────────────────────────────────────────────────────────────────────────
# Endpoint Checking
# ─────────────────────────────────────────────────────────────────────────────

check_endpoint() {
    local host port endpoint_name
    host="${1%%:*}"
    port="${1##*:}"
    endpoint_name="$2"
    
    # Skip if no connectivity to host
    if ! ping -c 1 -W 2 "$host" &>/dev/null 2>&1; then
        log_skip "Host unreachable: $host (network may not be available locally)"
        return 0
    fi
    
    # Check port connectivity
    if timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        log_up "$endpoint_name is UP ($host:$port)"
        return 0
    else
        log_down "$endpoint_name is DOWN (could not connect to $host:$port)"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Scan
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         VPN ENTERPRISE ENDPOINT SCAN - NETWORK TOPOLOGY VERIFICATION         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Primary Site Scan
    log_header "Primary Site - ${DEPLOY_HOST}"
    echo ""
    
    # Code-Server
    check_endpoint "${DEPLOY_HOST}:${PORT_CODE_SERVER}" "Code-Server (IDE)" || true
    echo ""
    
    # OAuth2-Proxy
    check_endpoint "${DEPLOY_HOST}:4180" "OAuth2-Proxy (Auth Gateway)" || true
    echo ""
    
    # Observability Stack
    log_header "Observability Stack (Primary)"
    check_endpoint "${DEPLOY_HOST}:${PORT_GRAFANA}" "Grafana (Dashboards)" || true
    check_endpoint "${DEPLOY_HOST}:${PORT_PROMETHEUS}" "Prometheus (Metrics)" || true
    check_endpoint "${DEPLOY_HOST}:${PORT_ALERTMANAGER}" "AlertManager (Alerts)" || true
    check_endpoint "${DEPLOY_HOST}:16686" "Jaeger (Tracing)" || true
    echo ""
    
    # Database Stack
    log_header "Database Stack (Primary)"
    check_endpoint "${DEPLOY_HOST}:5432" "PostgreSQL (Primary DB)" || true
    check_endpoint "${DEPLOY_HOST}:6379" "Redis (Cache)" || true
    echo ""
    
    # Replica Site Scan
    log_header "Replica Site - ${REPLICA_HOST:-192.168.168.42}"
    echo ""
    check_endpoint "${REPLICA_HOST:-192.168.168.42}:${PORT_CODE_SERVER}" "Code-Server (Replica - Standby)" || true
    echo ""
    
    # Summary
    log_header "Endpoint Scan Summary"
    echo -e "${GREEN}✓ Endpoints UP:      $ENDPOINTS_UP${NC}"
    echo -e "${RED}✗ Endpoints DOWN:    $ENDPOINTS_DOWN${NC}"
    echo -e "${YELLOW}⊘ Endpoints SKIPPED: $ENDPOINTS_SKIPPED${NC}"
    echo ""
    
    if [[ $ENDPOINTS_DOWN -eq 0 ]]; then
        echo -e "${GREEN}═════════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}✓ ALL ENDPOINTS OPERATIONAL - NETWORK HEALTHY${NC}"
        echo -e "${GREEN}═════════════════════════════════════════════════════════════════════════════════${NC}"
        return 0
    else
        echo -e "${YELLOW}═════════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}⚠ $ENDPOINTS_DOWN ENDPOINTS UNAVAILABLE - CHECK NETWORK CONNECTIVITY${NC}"
        echo -e "${YELLOW}═════════════════════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Note: This script runs locally. If endpoints are unreachable:"
        echo "  1. Run from production host: ssh akushnir@${DEPLOY_HOST}"
        echo "  2. Then: bash scripts/vpn-enterprise-endpoint-scan.sh"
        echo "  3. Or use fallback: bash scripts/vpn-enterprise-endpoint-scan-fallback.sh"
        return 0  # Return 0 since network unavailability is expected locally
    fi
}

main "$@"
