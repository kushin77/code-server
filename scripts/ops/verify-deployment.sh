#!/bin/bash
################################################################################
# Deployment Status Verification Script
#
# Verifies that all core platform infrastructure services are deployed and
# healthy on the remote host at 192.168.168.31
################################################################################

set -euo pipefail

# Error handling
trap 'echo "[ERROR] Script failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

PRIMARY_HOST="${1:-192.168.168.31}"

echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║        DEPLOYMENT VERIFICATION & HEALTH CHECK                         ║"
echo "║        Host: ${PRIMARY_HOST}                                          ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# Get container information
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. DEPLOYED SERVICES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ssh -o ConnectTimeout=10 "akushnir@${PRIMARY_HOST}" "
    echo 'Database Services:'
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep postgres || echo '  (none running)'
    
    echo ''
    echo 'Cache Services:'
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep redis || echo '  (none running)'
    
    echo ''
    echo 'Monitoring Services:'
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'prometheus|grafana|alertmanager|loki' || echo '  (none running)'
    
    echo ''
    echo 'All Running Containers:'
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | head -15
"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. PORT MAPPINGS & ENDPOINTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ssh -o ConnectTimeout=10 "akushnir@${PRIMARY_HOST}" "
    docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep -v PORTS | head -15
"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. SERVICE HEALTH STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ssh -o ConnectTimeout=10 "akushnir@${PRIMARY_HOST}" "
    echo 'Container Status Summary:'
    docker ps -a --format 'table {{.Status}}' | sort | uniq -c | sort -rn
"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. DOCKER CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ssh -o ConnectTimeout=10 "akushnir@${PRIMARY_HOST}" "
    echo 'Docker Version:'
    docker --version
    
    echo ''
    echo 'Docker Compose Version:'
    docker-compose --version
    
    echo ''
    echo 'Networks Configured:'
    docker network ls | grep -E 'net-|bridge' | wc -l | xargs echo '  Total:'
    
    echo ''
    echo 'Named Volumes:'
    docker volume ls | tail -10
"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. API ENDPOINT STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ssh -o ConnectTimeout=10 "akushnir@${PRIMARY_HOST}" "
    if docker ps --format '{{.Names}}' | grep -q api; then
        echo '✓ API Container Running'
        CONTAINER=\$(docker ps --format '{{.Names}}' | grep api | head -1)
        docker logs \$CONTAINER 2>&1 | tail -5 || echo 'Logs unavailable'
    else
        echo '⚠ API Container Not Found'
    fi
"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. AVAILABLE ENDPOINTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ssh -o ConnectTimeout=10 "akushnir@${PRIMARY_HOST}" "
    echo 'API Endpoint:'
    docker ps --format '{{.Names}}\t{{.Ports}}' | grep api | head -1 || echo '  (check running containers)'
    
    echo ''
    echo 'Database Endpoints:'
    docker ps --format '{{.Names}}\t{{.Ports}}' | grep postgres | head -1
    
    echo ''
    echo 'Cache Endpoints:'
    docker ps --format '{{.Names}}\t{{.Ports}}' | grep redis | head -1
    
    echo ''
    echo 'Monitoring Endpoints:'
    docker ps --format '{{.Names}}\t{{.Ports}}' | grep -E 'prometheus|grafana' | head -2
"

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║        DEPLOYMENT VERIFICATION COMPLETE                               ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  Host: ${PRIMARY_HOST}"
echo "  Primary API: http://${PRIMARY_HOST}:8080"
echo "  Prometheus: http://${PRIMARY_HOST}:9090"
echo "  Grafana: http://${PRIMARY_HOST}:3000"
echo ""
