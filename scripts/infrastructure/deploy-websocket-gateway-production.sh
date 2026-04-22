#!/usr/bin/env bash
# @file        scripts/infrastructure/deploy-websocket-gateway-production.sh
# @module      infrastructure/websocket
# @description Deploy WebSocket gateway cluster to production hosts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh" 2>/dev/null || {
    echo "ERROR: Cannot source init.sh"
    exit 1
}

PRIMARY_HOST="${1:-192.168.168.31}"
REPLICA_HOST="${2:-192.168.168.42}"
DEPLOY_USER="akushnir"

log_info "=========================================="
log_info "P1 #1313: WebSocket Gateway Deployment"
log_info "=========================================="

# Verification function
verify_host_connectivity() {
    local host=$1
    log_info "Verifying connectivity to ${host}..."
    
    if ! ssh -o ConnectTimeout=5 "${DEPLOY_USER}@${host}" "echo OK" > /dev/null 2>&1; then
        log_fatal "Cannot connect to ${host}"
        return 1
    fi
    
    log_info "✓ ${host} is reachable"
}

# Deploy to single host
deploy_to_host() {
    local host=$1
    log_info ""
    log_info "Deploying to ${host}..."
    
    # Copy files
    log_info "Copying deployment files..."
    scp "${SCRIPT_DIR}/docker-compose.websocket-gateway.yml" \
        "${DEPLOY_USER}@${host}:~/code-server/"
    scp "${SCRIPT_DIR}/scripts/infrastructure/setup-websocket-gateway-cluster.sh" \
        "${DEPLOY_USER}@${host}:~/code-server/scripts/infrastructure/"
    scp "${SCRIPT_DIR}/scripts/tests/k6-websocket-gateway-test.js" \
        "${DEPLOY_USER}@${host}:~/code-server/scripts/tests/"
    
    log_info "✓ Files copied to ${host}"
    
    # Start cluster via SSH
    log_info "Starting WebSocket gateway cluster on ${host}..."
    ssh "${DEPLOY_USER}@${host}" << 'REMOTE_SCRIPT'
cd ~/code-server
docker-compose -f docker-compose.websocket-gateway.yml down 2>/dev/null || true
docker-compose -f docker-compose.websocket-gateway.yml up -d
docker-compose -f docker-compose.websocket-gateway.yml ps
REMOTE_SCRIPT
    
    log_info "✓ Cluster started on ${host}"
    
    # Wait for services to stabilize
    log_info "Waiting for services to stabilize..."
    sleep 5
    
    # Verify health
    log_info "Verifying cluster health on ${host}..."
    ssh "${DEPLOY_USER}@${host}" << 'HEALTH_CHECK'
cd ~/code-server
echo "HAProxy health:"
curl -s http://localhost:8404/stats | head -20 || echo "HAProxy stats not ready yet"

echo ""
echo "Relay nodes health:"
curl -s http://localhost:3001/health && echo " (relay-1)" || echo "Relay 1 not ready"
curl -s http://localhost:3002/health && echo " (relay-2)" || echo "Relay 2 not ready"
curl -s http://localhost:3003/health && echo " (relay-3)" || echo "Relay 3 not ready"

echo ""
echo "Redis health:"
redis-cli ping 2>/dev/null || echo "Redis not ready yet"
HEALTH_CHECK
    
    log_info "✓ Health checks complete for ${host}"
}

# Load test function
run_load_test() {
    local host=$1
    log_info ""
    log_info "Running load test on ${host}..."
    
    ssh "${DEPLOY_USER}@${host}" << 'LOAD_TEST'
cd ~/code-server

# Check if k6 is available
if ! command -v k6 &> /dev/null; then
    echo "k6 not found, skipping load test"
    echo "To install: npm install -g k6 or apt-get install k6"
    exit 0
fi

echo "Starting k6 load test (100 VUs, 5 min duration)..."
k6 run scripts/tests/k6-websocket-gateway-test.js \
    --vus 100 \
    --duration 5m \
    --env GATEWAY_HOST=localhost \
    --out json=artifacts/k6-results.json 2>&1 | tail -20

echo ""
echo "Load test completed. Results: artifacts/k6-results.json"
LOAD_TEST
    
    log_info "✓ Load test complete on ${host}"
}

main() {
    # Verify connectivity
    verify_host_connectivity "${PRIMARY_HOST}" || log_fatal "Primary host unreachable"
    
    # Deploy to primary
    deploy_to_host "${PRIMARY_HOST}"
    
    # Offer to deploy to replica
    log_info ""
    log_info "Primary deployment complete."
    log_info ""
    log_info "Replica host (${REPLICA_HOST}) deployment:"
    log_info "  - Use same process to deploy to replica for failover testing"
    log_info "  - Both hosts will have independent clusters"
    log_info "  - For HA setup, use HAProxy on both with shared Redis"
    
    # Run optional load test
    log_info ""
    read -p "Run load test now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_load_test "${PRIMARY_HOST}"
    fi
    
    log_info ""
    log_info "=========================================="
    log_info "Deployment Summary"
    log_info "=========================================="
    log_info "Primary Host: ${PRIMARY_HOST}"
    log_info "  HAProxy: http://${PRIMARY_HOST}:8080 (WebSocket)"
    log_info "  Stats: http://${PRIMARY_HOST}:8404/stats"
    log_info "  Prometheus: http://${PRIMARY_HOST}:9090"
    log_info "  Grafana: http://${PRIMARY_HOST}:3000"
    log_info ""
    log_info "Next Steps:"
    log_info "  1. Monitor cluster: docker-compose -f docker-compose.websocket-gateway.yml logs -f"
    log_info "  2. Test connectivity: curl http://${PRIMARY_HOST}:8080/ws?session_id=test-1"
    log_info "  3. View metrics: http://${PRIMARY_HOST}:8404/stats"
    log_info ""
}

main
