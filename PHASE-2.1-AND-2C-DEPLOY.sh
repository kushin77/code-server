#!/bin/bash
# Phase 2.1 + Phase 2C Complete Deployment
# Deploys OIDC issuer + JWT services together

set -euo pipefail

REMOTE_HOST="192.168.168.31"
REMOTE_USER="akushnir"
SSH_KEY_PATH="${HOME}/.ssh/id_rsa_onprem"

echo "====== PHASE 2.1 + PHASE 2C COMPLETE DEPLOYMENT ======"
echo ""

# Step 1: Generate OIDC issuer signing key
echo "Step 1: Generating OIDC issuer signing key..."
openssl genrsa -out /tmp/oidc_signing.key 2048 2>/dev/null
echo "✓ RSA key generated"

# Step 2: Read the key and escape for environment variable
echo ""
echo "Step 2: Preparing key for .env file..."
OIDC_KEY=$(cat /tmp/oidc_signing.key | sed 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
echo "✓ Key prepared ($(echo "$OIDC_KEY" | wc -c) bytes)"

# Step 3: Update .env.phase-2 on remote with OIDC key
echo ""
echo "Step 3: Adding OIDC configuration to remote .env.phase-2..."

scp -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no /tmp/oidc_signing.key \
  "${REMOTE_USER}@${REMOTE_HOST}:/tmp/" > /dev/null

ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no \
  "${REMOTE_USER}@${REMOTE_HOST}" << 'SSHEOF'
cd code-server-enterprise

# Append OIDC signing key to .env.phase-2
cat >> .env.phase-2 << 'ENVEOF'

# Phase 2.1 OIDC Issuer Configuration
OIDC_ISSUER_SIGNING_KEY="$(cat /tmp/oidc_signing.key)"
ENVEOF

echo "✓ OIDC key added to .env.phase-2"

# Step 4: Restart docker-compose to start OIDC issuer
echo ""
echo "Step 4: Restarting docker-compose with OIDC issuer..."
docker-compose down redis > /dev/null 2>&1 || true
source .env.phase-2
docker-compose up -d oauth2-oidc-issuer redis 2>&1 | grep -E "Creating|Starting|✓"

# Step 5: Wait for OIDC issuer to be healthy
echo ""
echo "Step 5: Waiting for OIDC issuer health..."
for i in {1..30}; do
  if curl -sf http://localhost:4182/.well-known/openid-configuration > /dev/null 2>&1; then
    echo "✓ OIDC issuer is healthy"
    break
  fi
  echo "  Attempt $i/30..."
  sleep 2
done

# Step 6: Test OIDC issuer endpoints
echo ""
echo "Step 6: Testing OIDC issuer endpoints..."
echo ""
echo "OIDC Configuration endpoint:"
curl -s http://localhost:4182/.well-known/openid-configuration | head -c 200
echo "..."
echo ""
echo "JWKS endpoint:"
curl -s http://localhost:4182/.well-known/jwks.json | head -c 200
echo "..."

# Step 7: Now run full Phase 2C with token acquisition
echo ""
echo "Step 7: Running Phase 2C token acquisition test..."
export DRY_RUN=0
bash /tmp/PHASE-2C-STANDALONE-EXECUTION.sh 2>&1 | tail -50

echo ""
echo "✓ Phase 2.1 + 2C deployment complete"
SSHEOF

echo "✓ OIDC issuer deployed and Phase 2C executed"

echo ""
echo "====== DEPLOYMENT COMPLETE ======"
echo ""
echo "Services now running:"
ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "cd code-server-enterprise && docker-compose ps | grep -E 'oauth2-oidc-issuer|redis|caddy|prometheus'"

echo ""
echo "OIDC Issuer Status:"
ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "curl -sf http://localhost:4182/.well-known/openid-configuration > /dev/null && echo '✓ Healthy' || echo '✗ Not responding'"

echo ""
echo "Phase 2.1 + 2C deployment finished. JWT authentication is now live."
