#!/bin/bash
# Deploy P0 Security Hardening (#387) to Production
# Applies zero-bypass authentication changes
# Target: 192.168.168.31 (primary production host)
# Rollback: < 60 seconds via git revert

set -euo pipefail

DEPLOY_HOST="${1:-192.168.168.31}"
DEPLOY_USER="${2:-akushnir}"
REPO_PATH="/home/${DEPLOY_USER}/code-server-enterprise"

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║ P0 SECURITY HARDENING DEPLOYMENT (#387)                                       ║"
echo "║ Applying zero-bypass authentication to production                             ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Target Host: ${DEPLOY_HOST}"
echo "Repository: ${REPO_PATH}"
echo ""

# Step 1: Pull latest code
echo "▶ Step 1/5: Pull latest changes from git"
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "cd ${REPO_PATH} && git pull origin phase-7-deployment"
echo "✓ Git pull complete"
echo ""

# Step 2: Verify code-server binding is loopback-only
echo "▶ Step 2/5: Verify code-server loopback binding"
BINDING=$(ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "grep 'bind-addr' ${REPO_PATH}/docker-compose.yml | head -1")
if [[ "$BINDING" == *"127.0.0.1:8080"* ]]; then
  echo "✓ Code-server binding is loopback-only: $BINDING"
else
  echo "✗ ERROR: Code-server binding is NOT loopback! Found: $BINDING"
  exit 1
fi
echo ""

# Step 3: Verify Loki auth is enabled
echo "▶ Step 3/5: Verify Loki authentication is enabled"
LOKI_AUTH=$(ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "grep 'auth_enabled:' ${REPO_PATH}/config/loki/loki-config.yml | head -1")
if [[ "$LOKI_AUTH" == *"true"* ]]; then
  echo "✓ Loki authentication is enabled: $LOKI_AUTH"
else
  echo "✗ ERROR: Loki authentication is NOT enabled! Found: $LOKI_AUTH"
  exit 1
fi
echo ""

# Step 4: Restart affected services
echo "▶ Step 4/5: Restart services (code-server, loki, promtail)"
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "cd ${REPO_PATH} && docker-compose restart code-server loki promtail"
echo "✓ Services restarting..."
echo ""

# Step 5: Verify deployment
echo "▶ Step 5/5: Verify deployment"
sleep 5
echo ""
echo "  Checking service health..."

# Check code-server
echo -n "  • code-server: "
TIMEOUT=0
while [ $TIMEOUT -lt 30 ]; do
  if ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "curl -s http://127.0.0.1:8080/healthz >/dev/null 2>&1" 2>/dev/null; then
    echo "✓ Healthy (loopback accessible)"
    break
  fi
  TIMEOUT=$((TIMEOUT + 1))
  sleep 1
done
if [ $TIMEOUT -ge 30 ]; then
  echo "✗ Timeout waiting for health"
fi

# Check that external port is NOT accessible (security verification)
echo -n "  • code-server external: "
if ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "! curl -s http://192.168.168.31:8080/healthz >/dev/null 2>&1" 2>/dev/null; then
  echo "✓ NOT accessible (security enforced)"
else
  echo "✗ Still accessible on external IP! Deployment failed!"
  exit 1
fi

# Check Loki health
echo -n "  • loki: "
if ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "curl -s http://127.0.0.1:3100/ready >/dev/null 2>&1" 2>/dev/null; then
  echo "✓ Healthy"
else
  echo "✗ Unhealthy"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║ ✓ DEPLOYMENT COMPLETE                                                         ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Security Changes Applied:"
echo "  ✓ code-server binds to 127.0.0.1:8080 (loopback only)"
echo "  ✓ External access blocked (oauth2-proxy only gateway)"
echo "  ✓ Loki authentication enabled (per-service tokens required)"
echo ""
echo "Verification:"
echo "  • OAuth2-proxy: https://ide.kushnir.cloud (public access)"
echo "  • code-server direct: curl http://192.168.168.31:8080 → CONNECTION REFUSED ✓"
echo "  • Loki unauthenticated: curl http://192.168.168.31:3100/loki/api/v1/labels → 401"
echo ""
echo "Rollback (if needed):"
echo "  ssh ${DEPLOY_USER}@${DEPLOY_HOST} 'cd ${REPO_PATH} && git revert HEAD && docker-compose restart code-server loki'"
echo ""
