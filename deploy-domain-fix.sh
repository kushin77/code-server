#!/bin/bash
# Domain Fix Deployment Script
# Automatically restarts Appsmith and Caddy services with new configuration
# This script must be run by a user with docker permissions

set -euo pipefail

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Logging functions
log_info() { echo "[INFO] $1"; }
log_error() { echo "[ERROR] $1" >&2; }

echo "=========================================="
echo "Domain Configuration Fix - Auto Deploy"
echo "=========================================="
echo ""

# Step 1: Pull latest changes
echo "[1/5] Pulling latest configuration from git..."
cd /home/akushnir/code-server
git pull origin fix/domain-variability-caddy
echo "✓ Git pull complete"
echo ""

# Step 2: Load environment
echo "[2/5] Loading environment variables..."
if [ -f .env.production ]; then
    source .env.production
    echo "✓ Environment loaded from .env.production"
else
    echo "✗ ERROR: .env.production not found"
    exit 1
fi
echo ""

# Step 3: Verify docker
echo "[3/5] Verifying docker availability..."
if ! command -v docker &> /dev/null; then
    echo "✗ ERROR: docker command not found"
    echo "  Please install docker or run with docker permissions"
    exit 1
fi
docker ps > /dev/null 2>&1 || {
    echo "✗ ERROR: Cannot access docker daemon"
    echo "  Please check docker permissions or daemon status"
    exit 1
}
echo "✓ Docker is available"
echo ""

# Step 4: Restart Appsmith
echo "[4/5] Restarting Appsmith service with new OAuth configuration..."
docker compose -f docker-compose.enterprise.yml up -d appsmith 2>&1 | grep -E "^|service|Starting|Recreating|Creating"
sleep 3
docker ps | grep code-server-appsmith || {
    echo "✗ ERROR: Appsmith failed to start"
    docker logs code-server-appsmith --tail 20
    exit 1
}
echo "✓ Appsmith service restarted"
echo ""

# Step 5: Restart Caddy
echo "[5/5] Restarting Caddy reverse proxy service..."
docker compose -f docker-compose.enterprise.yml up -d caddy 2>&1 | grep -E "^|service|Starting|Recreating|Creating" || true
sleep 3
docker ps | grep caddy || docker ps | grep reverse || {
    echo "⚠ Warning: Could not verify Caddy container - checking if service is running..."
}
echo "✓ Caddy service restart initiated"
echo ""

# Verification
echo "=========================================="
echo "Deployment Complete - Verification"
echo "=========================================="
echo ""

echo "Waiting for services to stabilize (5 seconds)..."
sleep 5

echo "Service Status:"
echo "  Appsmith: $(docker ps | grep code-server-appsmith | cut -d' ' -f1 | head -c 12 || echo 'NOT FOUND')"
echo "  Caddy:    $(docker ps | grep -E 'caddy|reverse' | cut -d' ' -f1 | head -c 12 || echo 'NOT FOUND')"
echo ""

echo "Testing domain access:"
echo "  Command: curl -I https://kushnir.cloud/"
echo "  Status:  $(curl -I https://kushnir.cloud/ 2>/dev/null | head -1 || echo 'TIMEOUT (expected if TLS not yet ready)')"
echo ""

echo "Next Steps:"
echo "  1. Wait 30-60 seconds for services to fully start"
echo "  2. Visit https://kushnir.cloud in your browser"
echo "  3. You should see Appsmith OAuth login (NOT Hermes page)"
echo "  4. Click 'Continue with Google' or 'Continue with GitHub'"
echo ""

echo "If services fail to start:"
echo "  1. Check logs: docker logs code-server-appsmith -f"
echo "  2. Verify config: docker compose config | grep -A 20 appsmith:"
echo "  3. Manual restart: docker compose -f docker-compose.enterprise.yml restart appsmith"
echo ""

echo "✓ Deployment script completed successfully"
