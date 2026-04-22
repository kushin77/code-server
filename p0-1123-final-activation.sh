#!/usr/bin/env bash
# P0 #1123 FINAL ACTIVATION AND VERIFICATION SCRIPT
# Run this on production host to activate mTLS and verify deployment

set -euo pipefail

DEPLOY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
DEPLOY_DIR="/home/akushnir/code-server-enterprise-ops"

echo "========================================"
echo "P0 #1123 FINAL ACTIVATION SCRIPT"
echo "========================================"
echo ""

# Step 1: Verify all artifacts are in place
echo "Step 1: Verifying artifacts on primary host..."
ssh akushnir@${DEPLOY_HOST} "
  cd ${DEPLOY_DIR}
  echo 'Checking certificates...'
  CERT_COUNT=\$(find config/mtls-certs -name '*.pem' | wc -l)
  if [ \$CERT_COUNT -eq 44 ]; then
    echo '  ✓ 44 certificate files present'
  else
    echo '  ✗ Expected 44 certificates, found \$CERT_COUNT'
    exit 1
  fi
  
  if [ -f docker-compose.mtls.yml ]; then
    echo '  ✓ Docker Compose overlay present'
  else
    echo '  ✗ Docker Compose overlay missing'
    exit 1
  fi
  
  if [ -f scripts/security/rotate-mtls-certificates.sh ]; then
    echo '  ✓ Rotation script present'
  else
    echo '  ✗ Rotation script missing'
    exit 1
  fi
"

if [ $? -eq 0 ]; then
  echo "✓ All artifacts verified on primary"
else
  echo "✗ Artifact verification failed"
  exit 1
fi

echo ""

# Step 2: Verify replica
echo "Step 2: Verifying artifacts on replica host..."
ssh akushnir@${REPLICA_HOST} "
  cd ${DEPLOY_DIR}
  CERT_COUNT=\$(find config/mtls-certs -name '*.pem' 2>/dev/null | wc -l)
  if [ \$CERT_COUNT -eq 44 ]; then
    echo '  ✓ 44 certificate files present on replica'
  else
    echo '  ✗ Expected 44 certificates on replica, found \$CERT_COUNT'
  fi
"

echo ""

# Step 3: Activation instructions
echo "Step 3: Ready for activation"
echo "========================================"
echo ""
echo "To activate mTLS on primary host, execute:"
echo ""
echo "  ssh akushnir@${DEPLOY_HOST}"
echo "  cd ${DEPLOY_DIR}"
echo "  docker-compose --env-file .env.production -f docker-compose.yml -f docker-compose.mtls.yml up -d"
echo ""
echo "This will:"
echo "  1. Load existing services from docker-compose.yml"
echo "  2. Overlay mTLS configuration from docker-compose.mtls.yml"
echo "  3. Restart all 13 services with mutual TLS enabled"
echo "  4. Activate daily certificate rotation at 02:00 UTC"
echo ""
echo "To monitor activation:"
echo "  docker-compose logs -f"
echo ""
echo "To verify mTLS is active:"
echo "  docker-compose ps"
echo "  docker-compose exec redis openssl s_client -showcerts </dev/null 2>/dev/null"
echo ""
echo "========================================"
echo "P0 #1123 DEPLOYMENT READY"
echo "========================================"
