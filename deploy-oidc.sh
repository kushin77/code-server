#!/bin/bash
#!/usr/bin/env bash
# Phase 2.1 OIDC Deployment Script
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_common/init.sh
source "$SCRIPT_DIR/scripts/_common/init.sh"

# Navigate to deployment directory
cd "$DEPLOY_DIR"

# Backup existing files
timestamp=$(date +%Y%m%d_%H%M%S)
cp Caddyfile "Caddyfile.backup.$timestamp"
cp docker-compose.yml "docker-compose.yml.backup.$timestamp"
log_info "Files backed up with timestamp: $timestamp"

# Copy new files
sudo mv /tmp/Caddyfile ./Caddyfile
sudo mv /tmp/docker-compose.yml ./docker-compose.yml
sudo mv /tmp/.env.oidc ./.env.oidc
log_info "New files deployed"

# Merge .env.oidc into .env safely
if [ -f .env.oidc ]; then
  while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ $key =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    # Remove existing key if present
    sed -i.bak "/^${key}=/d" .env 2>/dev/null || true
    # Add new key-value pair
    echo "${key}=${value}" >> .env
  done < <(grep -v '^#' .env.oidc | grep '=')
  log_info ".env.oidc merged into .env"
fi

# Validate docker-compose
docker-compose config > /dev/null
log_info "docker-compose.yml validated"

# Stop current services
docker-compose down
log_info "Stopped old services"

# Start new services with OIDC issuer
docker-compose up -d
echo "✅ Started new services"

# Wait for services to stabilize
sleep 15

# Check service status
echo "Service Status:"
docker ps --format "table {{.Names}}\t{{.Status}}"
