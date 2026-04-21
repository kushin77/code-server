#!/usr/bin/env bash
# @file        scripts/issue-984-complete-dod.sh
# @module      ops/deployment
# @description Complete OAuth2-Proxy deployment and DoD steps for issue #984
#
# Run this script on 192.168.168.31 to complete Definition of Done steps 2-3

set -euo pipefail

cd /home/akushnir/code-server-enterprise

echo "Step 1: Load QA credentials from GSM"
export QA_PASSWORD=$(gcloud secrets versions access latest --secret=QA_USER_PASSWORD 2>/dev/null || echo "PASSWORD_NEEDED")

if [ "$QA_PASSWORD" = "PASSWORD_NEEDED" ]; then
    echo "ERROR: Cannot access GSM. Please provide QA password manually:"
    read -sp "Enter QA user password: " QA_PASSWORD
    echo ""
fi

echo "Step 2: Verify qa@kushnir.cloud is in whitelist"
if ! grep -q "qa@kushnir.cloud" allowed-emails.txt; then
    echo "ERROR: qa@kushnir.cloud not in allowed-emails.txt"
    echo "qa@kushnir.cloud" >> allowed-emails.txt
    echo "✓ Added qa@kushnir.cloud to allowed-emails.txt"
fi

echo "Step 3: Retrieve oauth2-proxy cookie secret from .env or GSM"
if [ -f .env ]; then
    source .env 2>/dev/null || true
fi

COOKIE_SECRET="${OAUTH2_PROXY_COOKIE_SECRET:-}"
if [ -z "$COOKIE_SECRET" ]; then
    echo "Attempting to retrieve from GSM..."
    COOKIE_SECRET=$(gcloud secrets versions access latest --secret=OAUTH2_PROXY_COOKIE_SECRET 2>/dev/null || echo "")
fi

if [ -z "$COOKIE_SECRET" ]; then
    echo "WARNING: No cookie secret found. Using default 16-byte hex..."
    COOKIE_SECRET=$(openssl rand -hex 16)
fi

echo "✓ Cookie secret ready (length: ${#COOKIE_SECRET})"

echo "Step 4: Restart oauth2-proxy container"
docker-compose up -d oauth2-proxy || docker restart oauth2-proxy

echo "Step 5: Wait for oauth2-proxy to be ready"
sleep 5

echo "Step 6: Verify oauth2-proxy is running"
if docker ps --filter name=oauth2-proxy | grep -q "oauth2-proxy"; then
    echo "✓ oauth2-proxy is running"
    docker logs oauth2-proxy --tail 10
else
    echo "ERROR: oauth2-proxy did not start"
    docker logs oauth2-proxy --tail 20
    exit 1
fi

echo ""
echo "=========================================="
echo "Definition of Done Steps 2-3 COMPLETE"
echo "=========================================="
echo "✓ QA credentials loaded"
echo "✓ oauth2-proxy restarted with new whitelist"
echo ""
echo "Step 4 (Manual): Test OAuth flow in browser"
echo "- URL: https://kushnir.cloud"
echo "- Login with: qa@kushnir.cloud"
echo "- Complete Google OAuth"
echo "- Verify redirect to /dashboard"
echo ""
echo "Once tested, comment on GitHub issue #984 with completion status"
