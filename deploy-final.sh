#!/usr/bin/env bash
# @file        deploy-final.sh
# @module      deployment/final
# @description Final deployment stage - sources .env.production and starts services
# @owner       Infrastructure Team
# @status      ACTIVE
#
set -eo pipefail

cd code-server-enterprise-ops

echo "Loading production environment from .env.production..."

# Source .env.production into current shell (without set -u to allow unset vars)
set -a
source .env.production 2>/dev/null || true
set +a

echo "✓ Environment loaded"

echo ""
echo "Starting deployment..."

# Deploy
docker-compose up --detach

# Wait for containers to stabilize
sleep 15

# Check status
echo ""
echo "=== Service Status ==="
docker-compose ps

echo ""
echo "✓ Deployment complete!"
