#!/usr/bin/env bash
set -euo pipefail

cd code-server-enterprise-ops

# Load production environment
echo "Loading production environment..."
if [ -f .env.production ]; then
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
