#!/bin/bash
# @file        scripts/vpn-endpoint-testing.sh
# @module      networking
# @description Test VPN endpoint connectivity and service health.
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════
# VPN Endpoint Testing & Validation Script
# Tests connectivity to all critical on-prem infrastructure endpoints
# Usage: ./vpn-endpoint-testing.sh
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Target endpoints
declare -a ENDPOINTS=(
    "${DEPLOY_HOST}:${PORT_CODE_SERVER}:code-server-http"
    "${DEPLOY_HOST}:${PORT_CADDY_HTTP}:caddy-http"
    "${DEPLOY_HOST}:${PORT_CADDY_HTTPS}:caddy-https"
    "${DEPLOY_HOST}:${PORT_OLLAMA}:ollama"
    "${DEPLOY_HOST}:${PORT_PROMETHEUS}:prometheus"
    "${DEPLOY_HOST}:${PORT_GRAFANA}:grafana"
    "${DEPLOY_HOST}:16686:jaeger"
    "${DEPLOY_HOST}:${PORT_ALERTMANAGER}:alertmanager"
    "${DEPLOY_HOST}:4180:oauth2-proxy"
    "${DEPLOY_HOST}:5432:postgres"
    "${DEPLOY_HOST}:6379:redis"
    "192.168.168.56:111:nfs-portmapper"
    "192.168.168.56:2049:nfs-nfs"
    "192.168.168.55:111:nfs-portmapper-55"
    "192.168.168.55:2049:nfs-nfs-55"
)

# DNS resolution test
echo -e "${YELLOW}═══ DNS Resolution Testing ═══${NC}"
for host in "${DEPLOY_HOST}" "192.168.168.56" "192.168.168.55" "8.8.8.8"; do
    if ping -c 1 -W 2 "$host" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $host reachable"
    else
        echo -e "${RED}✗${NC} $host unreachable"
    fi
done

# Port connectivity testing
echo -e "\n${YELLOW}═══ Port Connectivity Testing ═══${NC}"
FAILED=0
PASSED=0

for endpoint in "${ENDPOINTS[@]}"; do
    IFS=':' read -r host port service <<< "$endpoint"
    
    if timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $service ($host:$port)"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $service ($host:$port) - connection failed"
        ((FAILED++))
    fi
done

# HTTP health check for web services
echo -e "\n${YELLOW}═══ HTTP Health Checks ═══${NC}"

declare -a HTTP_ENDPOINTS=(
    "http://${DEPLOY_HOST}:${PORT_CODE_SERVER}/healthz:code-server"
    "http://${DEPLOY_HOST}:${PORT_CADDY_HTTP}/health:caddy"
    "http://${DEPLOY_HOST}:${PORT_OLLAMA}/api/tags:ollama"
    "http://${DEPLOY_HOST}:${PORT_PROMETHEUS}/-/healthy:prometheus"
    "http://${DEPLOY_HOST}:${PORT_GRAFANA}/api/health:grafana"
    "http://${DEPLOY_HOST}:16686/:jaeger"
    "http://${DEPLOY_HOST}:${PORT_ALERTMANAGER}/-/healthy:alertmanager"
)

for http_endpoint in "${HTTP_ENDPOINTS[@]}"; do
    IFS=':' read -r url service <<< "$http_endpoint"
    
    if timeout 5 curl -sf "$url" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $service HTTP health check"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $service HTTP health check failed"
        ((FAILED++))
    fi
done

# NAS mount verification
echo -e "\n${YELLOW}═══ NAS Mount Verification ═══${NC}"

if mountpoint -q /mnt/nas-56; then
    echo -e "${GREEN}✓${NC} /mnt/nas-56 is mounted"
    if df /mnt/nas-56 &> /dev/null; then
        USAGE=$(df /mnt/nas-56 | tail -1 | awk '{print $5}')
        echo -e "  └─ Usage: $USAGE"
        ((PASSED++))
    fi
else
    echo -e "${RED}✗${NC} /mnt/nas-56 is NOT mounted"
    ((FAILED++))
fi

if mountpoint -q /mnt/nas-export; then
    echo -e "${GREEN}✓${NC} /mnt/nas-export is mounted"
    ((PASSED++))
else
    echo -e "${RED}✗${NC} /mnt/nas-export is NOT mounted"
    ((FAILED++))
fi

# Docker connectivity test
echo -e "\n${YELLOW}═══ Docker Service Verification ═══${NC}"

declare -a SERVICES=(
    "code-server:${PORT_CODE_SERVER}"
    "caddy:${PORT_CADDY_HTTP}"
    "ollama:${PORT_OLLAMA}"
    "prometheus:${PORT_PROMETHEUS}"
    "grafana:${PORT_GRAFANA}"
    "jaeger:16686"
    "alertmanager:${PORT_ALERTMANAGER}"
)

for service in "${SERVICES[@]}"; do
    IFS=':' read -r container port <<< "$service"
    
    # This would require SSH access to run docker commands
    echo -e "${YELLOW}ℹ${NC} $container on $port (verify with: docker logs $container)"
done

# Summary
echo -e "\n${YELLOW}═══ Test Summary ═══${NC}"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ All tests passed! VPN/Infrastructure connectivity verified.${NC}"
    exit 0
else
    echo -e "\n${RED}✗ $FAILED test(s) failed. Check infrastructure connectivity.${NC}"
    exit 1
fi
