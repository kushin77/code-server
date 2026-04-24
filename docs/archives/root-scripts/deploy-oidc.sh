#!/usr/bin/env bash
# @file        deploy-oidc.sh
# @module      deployment/oidc-phase-2.1
# @description Phase 2.1 OIDC deployment - OAuth2 proxy and issuer setup
# @owner       Infrastructure Team
# @status      ACTIVE
#
cd /home/akushnir/code-server-enterprise

# Backup existing files (idempotent: preserve modes)
cp -p Caddyfile Caddyfile.backup.$(date +%s)
cp -p docker-compose.yml docker-compose.yml.backup.$(date +%s)
echo "✅ Files backed up"

# Copy new files (idempotent: no overwrite)
sudo mv -n /tmp/Caddyfile ./Caddyfile
sudo mv -n /tmp/docker-compose.yml ./docker-compose.yml
sudo mv -n /tmp/.env.oidc ./.env.oidc
echo "✅ New files deployed"

# Merge .env.oidc into .env (idempotent: deduplicate)
grep -v '^#' .env.oidc | grep '=' | while IFS='=' read -r key value; do
    # Remove existing key before appending to ensure no duplicates
    grep -v "^${key}=" .env > .env.tmp || true
    mv .env.tmp .env
    echo "${key}=${value}" >> .env
done
echo "✅ .env.oidc merged into .env"

# Validate docker-compose
docker-compose config > /dev/null
echo "✅ docker-compose.yml validated"

# Stop current services
docker-compose down
echo "✅ Stopped old services"

# Start new services with OIDC issuer
docker-compose up -d
echo "✅ Started new services"

# Wait for services to stabilize
sleep 15

# Check service status
echo "Service Status:"
docker ps --format "table {{.Names}}\t{{.Status}}"
