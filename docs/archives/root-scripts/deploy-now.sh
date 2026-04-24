#!/usr/bin/env bash
# @file        deploy-now.sh
# @module      deployment/quick
# @description Quick deployment trigger - loads .env.production and starts services
# @owner       Infrastructure Team
# @status      ACTIVE
#
set -euo pipefail

cd code-server-enterprise-ops

# Load production environment
echo "Loading production environment..."
if [ -f .env.production ]; then
  # shellcheck disable=SC2046
  export $(cat .env.production | grep -v '^#' | xargs)
  echo "✓ Production environment loaded"
fi

# Deploy
echo "Starting deployment..."
docker-compose up --detach

# Wait for containers to stabilize
sleep 10

# Check status
echo ""
echo "=== Service Status ==="
docker-compose ps

# Verify health
echo ""
echo "=== Health Check ==="
docker-compose exec -T code-server curl -s http://localhost:8080/health || echo "Health check pending..."

echo ""
echo "✓ === Service Status ==="
docker-compose ps

# Verify health
echo ""
echo "=== Health Check ==="
docker-compose exec -T code-server curl -s http://localhost:8080/health || echo "Health check pending..."

echo ""
echo "✓ Deployment complete!"
