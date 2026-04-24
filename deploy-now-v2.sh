#!/usr/bin/env bash
# @file        deploy-now-v2.sh
# @module      deployment/quick-v2
# @description Quick deployment v2 - uses .env.production with docker-compose
# @owner       Infrastructure Team
# @status      ACTIVE
#
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
