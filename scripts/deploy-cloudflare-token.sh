#!/bin/bash
# Complete HTTPS Deployment Script for ide.kushnir.cloud
# Run this script once you have the real Cloudflare Tunnel token from the dashboard

set -e

echo "════════════════════════════════════════════════════════════════════"
echo "CLOUDFLARE TUNNEL TOKEN DEPLOYMENT"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "This script will:"
echo "1. Create the Cloudflare tunnel token secret in GSM"
echo "2. Deploy it to production"
echo "3. Start the cloudflared service"
echo "4. Verify HTTPS connectivity"
echo ""

# Step 1: Get or create token in GSM
echo "Step 1: Creating Cloudflare Tunnel Token in GSM..."
echo ""
echo "You need to provide the token from Cloudflare Dashboard:"
echo "  https://dash.cloudflare.com/"
echo "  → kushnir.cloud → Networks → Tunnels → ide-home-dev"
echo ""
read -p "Enter Cloudflare Tunnel Token (format: aaaa-bbbb...): " CF_TOKEN

if [ -z "$CF_TOKEN" ]; then
    echo "❌ Token cannot be empty"
    exit 1
fi

# Create secret in GSM
echo "Creating GSM secret 'prod-cloudflare-tunnel-token'..."
echo "$CF_TOKEN" | gcloud secrets create prod-cloudflare-tunnel-token \
    --replication-policy="automatic" \
    --project="gcp-eiq" \
    --data-file=- 2>&1 || \
echo "$CF_TOKEN" | gcloud secrets versions add prod-cloudflare-tunnel-token \
    --project="gcp-eiq" \
    --data-file=-

echo "✅ Token created in GSM"
echo ""

# Step 2: Deploy to production
echo "Step 2: Deploying token to production server..."
ssh akushnir@192.168.168.31 << 'SSH_EOF'
cd code-server-enterprise

# Fetch token from GSM using the fetch script
bash scripts/fetch-gsm-secrets.sh > .env.fetched

# Extract just the token line
CLOUDFLARE_TOKEN=$(grep CLOUDFLARE_TUNNEL_TOKEN .env.fetched || echo "")

if [ -z "$CLOUDFLARE_TOKEN" ]; then
    echo "❌ Failed to fetch token from GSM"
    exit 1
fi

echo "$CLOUDFLARE_TOKEN" >> .env
rm -f .env.fetched
echo "✅ Token deployed to .env"
SSH_EOF

echo ""

# Step 3: Start cloudflared
echo "Step 3: Starting cloudflared service..."
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose up -d cloudflared"
sleep 5

echo "✅ cloudflared service started"
echo ""

# Step 4: Verify connection
echo "Step 4: Verifying tunnel connection..."
READY=0
for i in {1..30}; do
    if ssh akushnir@192.168.168.31 "docker logs cloudflared 2>&1" | grep -q "connected\|connection"; then
        echo "✅ Tunnel connected to Cloudflare edge"
        READY=1
        break
    fi
    echo "  Attempt $i/30 - waiting for tunnel connection..."
    sleep 2
done

if [ $READY -eq 0 ]; then
    echo "⚠️  Tunnel may still be connecting. Check with:"
    echo "  ssh akushnir@192.168.168.31 'docker logs cloudflared -f'"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "✅ DEPLOYMENT COMPLETE"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "Test HTTPS access:"
echo "  curl https://ide.kushnir.cloud"
echo ""
echo "Or open in browser:"
echo "  https://ide.kushnir.cloud"
echo ""
