#!/bin/bash
# deploy-cloudflare-tunnel.sh
# Complete Cloudflare Tunnel deployment script
# Fetches API token from GSM and creates tunnel token automatically

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_HOST="${PROD_HOST:-akushnir@192.168.168.31}"
PROD_DIR="code-server-enterprise"

echo "════════════════════════════════════════════════════════════"
echo "CLOUDFLARE TUNNEL DEPLOYMENT - Automated"
echo "════════════════════════════════════════════════════════════"
echo ""

# Step 1: Fetch Cloudflare API token from GSM
echo "Step 1: Fetching Cloudflare API token from GSM..."
CF_API_TOKEN=$(gcloud secrets versions access latest \
  --secret="prod-cloudflare-api-token" \
  --project="gcp-eiq" 2>/dev/null) || {
  echo "❌ ERROR: Cannot fetch Cloudflare API token from GSM"
  echo "   Ensure: 1) gcloud auth is active (gcloud auth login)"
  echo "           2) You have access to gcp-eiq project"
  echo "           3) Secret 'prod-cloudflare-api-token' exists"
  exit 1
}

echo "✅ Cloudflare API token retrieved from GSM"
echo ""

# Step 2: Use API token to get/create tunnel on Cloudflare
echo "Step 2: Getting tunnel ID for 'ide-home-dev' from Cloudflare..."

# Get tunnel ID using Cloudflare API
TUNNEL_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$(echo $CF_API_TOKEN | cut -d_ -f3)/tunnels" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" | \
  jq -r '.result[] | select(.name=="ide-home-dev") | .id' | head -1) || {
  echo "❌ ERROR: Cannot get tunnel ID from Cloudflare API"
  echo "   Check: 1) API token is valid"
  echo "          2) Tunnel 'ide-home-dev' exists in Cloudflare"
  exit 1
}

if [ -z "$TUNNEL_ID" ]; then
  echo "⚠️  Tunnel 'ide-home-dev' not found in Cloudflare"
  echo "   Creating tunnel..."
  # Create tunnel if it doesn't exist
  TUNNEL_ID=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$(echo $CF_API_TOKEN | cut -d_ -f3)/tunnels" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name":"ide-home-dev","config_src":"local"}' | \
    jq -r '.result.id')
  echo "✅ Tunnel created with ID: $TUNNEL_ID"
else
  echo "✅ Tunnel found with ID: $TUNNEL_ID"
fi

echo ""

# Step 3: Get tunnel credentials token
echo "Step 3: Getting tunnel credentials token..."

TUNNEL_TOKEN=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$(echo $CF_API_TOKEN | cut -d_ -f3)/tunnels/$TUNNEL_ID/token" \
  -H "Authorization: Bearer $CF_API_TOKEN" | \
  jq -r '.result') || {
  echo "❌ ERROR: Cannot get tunnel token from Cloudflare API"
  exit 1
}

if [ -z "$TUNNEL_TOKEN" ]; then
  echo "❌ ERROR: Tunnel token is empty"
  exit 1
fi

echo "✅ Tunnel token retrieved"
echo "   Token: ${TUNNEL_TOKEN:0:20}..."
echo ""

# Step 4: Deploy token to production
echo "Step 4: Deploying token to production server..."

ssh "$PROD_HOST" << SSHEOF
  cd $PROD_DIR

  # Add token to .env
  echo "CLOUDFLARE_TUNNEL_TOKEN=$TUNNEL_TOKEN" >> .env

  # Verify
  if grep -q "CLOUDFLARE_TUNNEL_TOKEN=$TUNNEL_TOKEN" .env; then
    echo "✅ Token injected into .env"
  else
    echo "❌ ERROR: Token not properly added to .env"
    exit 1
  fi

  # Start cloudflared service
  echo "Starting cloudflared service..."
  docker-compose up -d cloudflared

  # Wait for health check
  echo "Waiting for tunnel connection..."
  sleep 5

  # Check logs for success
  if docker logs cloudflared 2>&1 | grep -q "connected to edge\|INF"; then
    echo "✅ cloudflared is connected to Cloudflare edge"
  elif docker logs cloudflared 2>&1 | grep -q "error\|Error\|ERROR"; then
    echo "❌ ERROR in cloudflared logs:"
    docker logs cloudflared | grep -i error | head -5
    exit 1
  fi
SSHEOF

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ DEPLOYMENT COMPLETE"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Verify HTTPS access:"
echo "     curl https://ide.kushnir.cloud"
echo ""
echo "  2. Check Cloudflare dashboard:"
echo "     https://dash.cloudflare.com/ → Networks → Tunnels → ide-home-dev"
echo ""
echo "  3. Monitor production logs:"
echo "     ssh $PROD_HOST 'cd $PROD_DIR && docker logs -f cloudflared'"
echo ""
