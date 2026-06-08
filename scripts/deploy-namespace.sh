#!/bin/bash
# @file scripts/deploy-namespace.sh
# @description Deploy code-server-enterprise stack to isolated namespace
# @usage ./scripts/deploy-namespace.sh [NAMESPACE]

set -euo pipefail

NAMESPACE="${1:-code-server-enterprise}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo " Code Server Enterprise - Namespace Deployment"
echo "════════════════════════════════════════════════════════════════"
echo "Namespace: ${NAMESPACE}"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Change to repo root
cd "${REPO_ROOT}"

# Validate Docker Compose configuration
echo "[1/5] Validating Docker Compose configuration..."
export NAMESPACE
if docker compose config > /dev/null; then
  echo "✓ Configuration valid"
else
  echo "✗ Configuration validation failed"
  exit 1
fi

# Stop any existing stack in this namespace
echo ""
echo "[2/5] Stopping existing stack (if any)..."
docker compose down --remove-orphans || true
echo "✓ Cleanup complete"

# Pull latest images
echo ""
echo "[3/5] Pulling latest images..."
docker compose pull || echo "⚠ Some images may need to be built locally"

# Deploy stack
echo ""
echo "[4/5] Deploying stack..."
if docker compose up -d --remove-orphans; then
  echo "✓ Stack deployed successfully"
else
  echo "✗ Deployment failed"
  exit 1
fi

# Wait for services to stabilize
echo ""
echo "[5/5] Waiting for services to become healthy..."
sleep 10

# Show status
echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Deployment Complete"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Container Status:"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker compose ps -q) 2>/dev/null || echo "(stats unavailable)"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Health Check"
echo "════════════════════════════════════════════════════════════════"

# Health check
if command -v curl > /dev/null; then
  for i in {1..6}; do
    if curl -sf http://localhost:3100/api/health > /dev/null 2>&1; then
      echo "✓ Health check passed"
      curl -s http://localhost:3100/api/health | jq '.' 2>/dev/null || curl -s http://localhost:3100/api/health
      echo ""
      echo "🎉 Deployment successful! Services are healthy."
      exit 0
    fi
    echo "Waiting for services... ($i/6)"
    sleep 5
  done
  echo "⚠ Health endpoint not responding (services may still be starting)"
else
  echo "⚠ curl not available, skipping health check"
fi

echo ""
echo "Logs (last 20 lines):"
docker compose logs --tail=20

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Deployment complete. Use 'docker compose logs -f' to follow logs."
echo "════════════════════════════════════════════════════════════════"
