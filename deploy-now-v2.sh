#!/usr/bin/env bash
set -euo pipefail

cd code-server-enterprise-ops

echo "Starting deployment..."

# Use .env.production with docker-compose
docker-compose --env-file .env.production up --detach

# Wait for containers to stabilize
sleep 15

# Check status
echo ""
echo "=== Service Status ==="
docker-compose ps

echo ""
echo "✓ Deployment started successfully!"
