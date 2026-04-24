#!/bin/bash
# PHASE-2C-BOOTSTRAP.sh - Generate and deploy test secrets for Phase 2C
# This creates test JWT configuration without needing GCP auth

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_HOST="192.168.168.31"
REMOTE_USER="akushnir"
SSH_KEY_PATH="${HOME}/.ssh/id_rsa_onprem"

echo "====== PHASE 2C BOOTSTRAP - GENERATE & DEPLOY TEST SECRETS ======"
echo ""

# Step 1: Generate test secrets locally
echo "Step 1: Generating test secrets..."

# Session-broker secret (32 random chars)
SB_SECRET=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))")
echo "  ✓ Session-broker secret: ${SB_SECRET:0:16}..."

# Backend secret (32 random chars)
BACKEND_SECRET=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))")
echo "  ✓ Backend secret: ${BACKEND_SECRET:0:16}..."

# LB session secret (64 hex = 32 bytes)
LB_SECRET=$(openssl rand -hex 32)
echo "  ✓ LB session secret: ${LB_SECRET:0:16}..."

# Step 2: Create .env.phase-2 locally with generated secrets
echo ""
echo "Step 2: Creating .env.phase-2 with generated secrets..."

cat > "${SCRIPT_DIR}/.env.phase-2" << ENVFILE
# Phase 2C: JWT Configuration (Generated at $(date))
# These are TEST secrets generated locally

# Generated Service Account Secrets
SERVICE_CLIENT_SESSION_BROKER_SECRET="${SB_SECRET}"
SERVICE_CLIENT_BACKEND_SECRET="${BACKEND_SECRET}"
IDE_SESSION_LB_SECRET="${LB_SECRET}"

# OIDC Issuer Configuration
OIDC_ISSUER_URL="http://oauth2-oidc-issuer:6969"
OIDC_CLIENT_ID="code-server"
OIDC_CLIENT_SECRET="test-secret-local"
OAUTH2_PROXY_CLIENT_ID="code-server"
OAUTH2_PROXY_CLIENT_SECRET="test-secret-local"

# JWT Configuration
JWT_ISSUER_URL="http://oauth2-oidc-issuer:6969"
JWT_JWKS_CACHE_TTL_MINUTES="60"
JWT_TOKEN_CACHE_TTL_MINUTES="55"
JWT_TOKEN_REFRESH_BUFFER_MINUTES="5"
JWT_VALIDATION_TIMEOUT_MS="5000"
JWT_METRICS_ENABLED="true"
JWT_AUTH_LOGGING_ENABLED="true"

# Service Subjects & Audiences
CODE_SERVER_JWT_SUBJECT="code-server@svc.internal"
CODE_SERVER_JWT_AUDIENCE="code-server,api,github-actions,kubernetes"
SESSION_BROKER_JWT_SUBJECT="session-broker@svc.internal"
SESSION_BROKER_JWT_AUDIENCE="session-broker,api,kubernetes"

# Caching
REDIS_URL="redis://redis:6379"
REDIS_CACHE_KEY_PREFIX="jwt-cache"

# Environment
ENVIRONMENT="on-prem"
DEPLOYMENT_HOST="192.168.168.31"
DEPLOYMENT_DOMAIN="192.168.168.31.nip.io"

# Feature Flags
ENABLE_JWT_BEARER_TOKEN_AUTH="true"
ENABLE_JWT_VALIDATION_CACHING="true"
ENABLE_JWT_METRICS_COLLECTION="true"
ENABLE_SERVICE_TO_SERVICE_AUTH="true"
ENABLE_PROMETHEUS_METRICS="true"
ENABLE_GRAFANA_DASHBOARDS="true"
ENABLE_ALERTMANAGER_RULES="true"
ENVFILE

echo "  ✓ .env.phase-2 created ($(wc -l < "${SCRIPT_DIR}/.env.phase-2") lines)"

# Step 3: Copy .env.phase-2 to remote host
echo ""
echo "Step 3: Copying .env.phase-2 to remote host..."

scp -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no \
  "${SCRIPT_DIR}/.env.phase-2" \
  "${REMOTE_USER}@${REMOTE_HOST}:code-server-enterprise/.env.phase-2"

echo "  ✓ .env.phase-2 copied to remote"

# Step 4: Verify .env.phase-2 on remote
echo ""
echo "Step 4: Verifying .env.phase-2 on remote..."

ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "cd code-server-enterprise && test -f .env.phase-2 && echo '  ✓ .env.phase-2 exists on remote' || echo '  ✗ .env.phase-2 missing on remote'"

# Step 5: Show what would happen if we run Phase 2C
echo ""
echo "Step 5: Test Phase 2C execution (dry-run)..."

ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "cd code-server-enterprise && DRY_RUN=1 bash /tmp/PHASE-2C-STANDALONE-EXECUTION.sh 2>&1" | grep -E "PHASE|would|✓|✗" || true

echo ""
echo "====== PHASE 2C BOOTSTRAP COMPLETE ======"
echo ""
echo "Test secrets generated and deployed successfully!"
echo ""
echo "Next steps:"
echo "  1. SSH to remote: ssh akushnir@192.168.168.31"
echo "  2. Deploy Phase 2C: cd code-server-enterprise && bash /tmp/PHASE-2C-STANDALONE-EXECUTION.sh"
echo "  3. Monitor logs: docker-compose logs -f oauth2-oidc-issuer"
echo "  4. Test token acquisition: curl -X POST http://localhost:6969/oauth2/token -d '...'"
echo ""
echo "Secrets stored in: ${SCRIPT_DIR}/.env.phase-2"
echo "To reset: rm ${SCRIPT_DIR}/.env.phase-2"
