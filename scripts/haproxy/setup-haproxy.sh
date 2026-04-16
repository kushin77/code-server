#!/bin/bash
set -e

# setup-haproxy.sh - Automate HAProxy deployment for code-server failover
# Part of Phase 7d-002: Load Balancer & Replica Configuration

# Metadata
# Path: scripts/haproxy/setup-haproxy.sh
# Version: 1.0.0 (Phase 7d)
# Description: Installs or updates HAProxy configuration for High Availability

# Configuration
HAPROXY_CFG_SOURCE="config/haproxy.cfg"
HAPROXY_DOCKER_PATH="docker/haproxy/Dockerfile"
PRIMARY_IP="192.168.168.31"
REPLICA_IP="192.168.168.42"

# Validation
if [[ ! -f "$HAPROXY_CFG_SOURCE" ]]; then
    echo "ERROR: HAProxy config source not found at $HAPROXY_CFG_SOURCE"
    exit 1
fi

echo "--- HAProxy Setup: Phase 7d-002 ---"
echo "Primary: $PRIMARY_IP"
echo "Replica: $REPLICA_IP"

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
echo "Production Host: ssh akushnir@192.168.168.31"
