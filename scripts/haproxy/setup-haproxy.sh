#!/usr/bin/env bash
# @file        scripts/haproxy/setup-haproxy.sh
# @module      operations/load-balancing
# @description Automate HAProxy deployment for code-server failover
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
HAPROXY_CFG_SOURCE="config/haproxy.cfg"
HAPROXY_DOCKER_PATH="docker/haproxy/Dockerfile"
PRIMARY_HOST="${DEPLOY_HOST}"
REPLICA_HOST="${STANDBY_HOST}"

# Validation
if [[ ! -f "$HAPROXY_CFG_SOURCE" ]]; then
    echo "ERROR: HAProxy config source not found at $HAPROXY_CFG_SOURCE"
    exit 1
fi

echo "--- HAProxy Setup: Phase 7d-002 ---"
echo "Primary: $PRIMARY_HOST"
echo "Replica: $REPLICA_HOST"

# Detection
if command -v docker &> /dev/null; then
    echo "[INFO] Docker detected, building HAProxy image..."
    # Local build for validation
    docker build -t local/haproxy-lb:latest -f "$HAPROXY_DOCKER_PATH" .
    
    echo "[INFO] Validating configuration with haproxy -c..."
    docker run --rm local/haproxy-lb:latest haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
else
    echo "[WARN] Docker not found, performing local config syntax check only if haproxy is installed..."
    if command -v haproxy &> /dev/null; then
        haproxy -c -f "$HAPROXY_CFG_SOURCE"
    fi
fi

echo "--- Setup Complete ---"
echo "Next steps: Deploy via terraform or docker-compose to production host."
echo "Production Host: ssh ${DEPLOY_USER}@$PRIMARY_HOST"
