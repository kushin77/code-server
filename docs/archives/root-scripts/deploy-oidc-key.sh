#!/usr/bin/env bash
# @file        deploy-oidc-key.sh
# @module      deployment/oidc-signing-key
# @description Deploy OIDC issuer RSA signing key to remote host
# @owner       Infrastructure Team
# @status      ACTIVE
#
set -e

REMOTE="akushnir@192.168.168.31"
SSH="-i $HOME/.ssh/id_rsa_onprem"

echo "Phase 2C: OIDC Issuer Key Deployment"
echo "Target: $REMOTE"
echo ""

# Generate key
echo "1. Generating RSA key..."
openssl genrsa 2048 > /tmp/oidc.key 2>/dev/null
echo "   ✓ Generated"

# Copy to remote /tmp
echo "2. Uploading key..."
scp $SSH /tmp/oidc.key $REMOTE:/tmp/ 2>/dev/null
echo "   ✓ Uploaded"

# Execute on remote to add to .env
echo "3. Adding key to .env..."
ssh $SSH $REMOTE << 'SSHEOF'
cd code-server-enterprise
if ! grep -q "OIDC_ISSUER_SIGNING_KEY=" .env; then
    {
        echo ""
        echo "# OIDC Issuer RSA Signing Key"
        echo -n "OIDC_ISSUER_SIGNING_KEY=\""
        cat /tmp/oidc.key
        echo "\""
    } >> .env
    echo "   ✓ Key added to .env"
else
    echo "   ✓ Key already in .env"
fi
SSHEOF

echo ""
echo "4. Restarting services..."
ssh $SSH $REMOTE "cd code-server-enterprise && docker-compose restart oauth2-oidc-issuer oauth2-proxy" || true

echo ""
echo "✅ Phase 2C key deployment complete"
echo ""
echo "Check status:"
echo "  ssh $SSH $REMOTE 'cd code-server-enterprise && docker-compose ps'"
