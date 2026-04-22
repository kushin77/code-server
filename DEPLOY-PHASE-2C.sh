#!/usr/bin/env bash
# @file        DEPLOY-PHASE-2C.sh
# @module      deployment/phase-2c
# @description Phase 2C deployment - configuration merge and service update
# @owner       Infrastructure Team
# @status      ACTIVE
#
set -euo pipefail

cd ~/code-server-enterprise

echo "=== PHASE 2C DEPLOYMENT: Configuration Merge ==="

# Step 1: Backup current .env
BACKUP_NAME=".env.backup.phase-2c.$(date +%s)"
cp .env "$BACKUP_NAME"
echo "✓ Backed up .env to $BACKUP_NAME"

# Step 2: Merge Phase 2 JWT variables into .env
cat >> .env << 'PHASE2EOF'

# Phase 2 JWT Service-to-Service Auth Configuration
SERVICE_CLIENT_SESSION_BROKER_ID="session-broker"
SERVICE_CLIENT_SESSION_BROKER_SECRET="K1HI0I7l7ZvSd3Lpvz8APfIapTwGbfYo"
SERVICE_CLIENT_BACKEND_ID="backend"
SERVICE_CLIENT_BACKEND_SECRET="HgugXoYLIRA4FlCQhk3TTNZs7KCetGez"

# OIDC Issuer Configuration
OIDC_ISSUER_URL="http://oauth2-oidc-issuer:4182"
OIDC_CLIENT_ID="code-server"
OIDC_CLIENT_SECRET="test-secret-local"

# JWT Configuration
JWT_ISSUER_URL="http://oauth2-oidc-issuer:4182"
JWT_JWKS_CACHE_TTL_MINUTES="60"
JWT_TOKEN_CACHE_TTL_MINUTES="55"
JWT_TOKEN_REFRESH_BUFFER_MINUTES="5"
JWT_VALIDATION_TIMEOUT_MS="5000"
JWT_METRICS_ENABLED="true"

# Service Subjects & Audiences
CODE_SERVER_JWT_SUBJECT="code-server@svc.internal"
CODE_SERVER_JWT_AUDIENCE="code-server,api,github-actions,kubernetes"
SESSION_BROKER_JWT_SUBJECT="session-broker@svc.internal"
SESSION_BROKER_JWT_AUDIENCE="session-broker,api,kubernetes"

# Feature Flags
ENABLE_JWT_BEARER_TOKEN_AUTH="true"
ENABLE_JWT_VALIDATION_CACHING="true"
ENABLE_JWT_METRICS_COLLECTION="true"
ENABLE_SERVICE_TO_SERVICE_AUTH="true"
PHASE2EOF

echo "✓ Merged Phase 2 JWT configuration into .env"
echo ""

# Step 3: Update Caddyfile with LB secret
echo "=== Updating Caddyfile with Caddy LB session secret ==="
IDE_SESSION_LB_SECRET="e63ad29df1012adf9f911a08bd24013b6bb5d1182d270f494f784082318fb12c"

# Check if we need to update the LB policy
if grep -q "lb_policy cookie ide_session_lb secret734" Caddyfile; then
    sed -i "s/lb_policy cookie ide_session_lb secret734/lb_policy cookie ide_session_lb $IDE_SESSION_LB_SECRET/" Caddyfile
    echo "✓ Updated Caddyfile LB policy from hardcoded secret to production secret"
elif ! grep -q "lb_policy cookie ide_session_lb $IDE_SESSION_LB_SECRET" Caddyfile; then
    echo "⚠ Caddyfile LB policy not found or already different - skipping"
fi

echo "Current LB policy:"
grep "lb_policy cookie" Caddyfile || echo "  (no match found)"

echo ""
echo "=== Phase 2C Configuration Deployment Ready ==="
echo "Backup: $BACKUP_NAME"
echo "Next steps:"
echo "  1. Verify .env changes: tail .env"
echo "  2. Deploy: docker-compose up -d"
echo "  3. Verify health: docker ps"
echo "  4. Test JWT token: curl -X POST http://localhost:4182/oauth2/token"
