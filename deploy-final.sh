#!/usr/bin/env bash
set -euo pipefail

# Find and navigate to the ops directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OPS_DIR="$SCRIPT_DIR"

# If we're in the repo root, navigate to ops subdirectory
if [ ! -f "docker-compose.yml" ] && [ -d "code-server-enterprise-ops" ]; then
  OPS_DIR="$SCRIPT_DIR/code-server-enterprise-ops"
fi

cd "$OPS_DIR"

echo "Loading production environment from .env.production..."

# Load environment safely
if [ -f .env.production ]; then
  # Use safe environment loading instead of source
  while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ $key =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    export "$key=$value"
  done < .env.production
  echo "✓ Environment loaded"
else
  echo "⚠ .env.production not found, continuing without it"
fi

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
