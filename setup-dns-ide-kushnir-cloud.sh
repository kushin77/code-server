#!/bin/bash
# DNS Configuration Script for ide.kushnir.cloud
# This script adds the required A-record to point ide.kushnir.cloud to 192.168.168.31

set -e

# Configuration
DOMAIN="ide.kushnir.cloud"
IP_ADDRESS="192.168.168.31"
ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
CF_TOKEN="${CLOUDFLARE_API_TOKEN:-}"

echo "=== DNS Configuration for ide.kushnir.cloud ==="
echo ""
echo "IMPORTANT: This script requires Cloudflare API access"
echo ""
echo "Prerequisites:"
echo "1. Cloudflare account with kushnir.cloud domain"
echo "2. Cloudflare API token with DNS edit permissions"
echo "3. Zone ID for kushnir.cloud"
echo ""

if [ -z "$CF_TOKEN" ]; then
    echo "❌ ERROR: CLOUDFLARE_API_TOKEN not set"
    echo ""
    echo "To set it:"
    echo "  export CLOUDFLARE_API_TOKEN='your-api-token'"
    echo ""
    exit 1
fi

if [ -z "$ZONE_ID" ]; then
    echo "❌ ERROR: CLOUDFLARE_ZONE_ID not set"
    echo ""
    echo "To find your Zone ID:"
    echo "  1. Log in to Cloudflare dashboard"
    echo "  2. Select kushnir.cloud domain"
    echo "  3. Copy Zone ID from right sidebar"
    echo ""
    echo "Then export it:"
    echo "  export CLOUDFLARE_ZONE_ID='zone-id-here'"
    echo ""
    exit 1
fi

echo "Configuring DNS A-record:"
echo "  Domain: $DOMAIN"
echo "  IP: $IP_ADDRESS"
echo "  Zone ID: $ZONE_ID"
echo ""

# Create DNS record
RECORD_DATA=$(cat <<EOF
{
  "type": "A",
  "name": "ide",
  "content": "$IP_ADDRESS",
  "ttl": 1,
  "proxied": false
}
EOF
)

echo "Calling Cloudflare API..."

RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$RECORD_DATA")

# Check response
if echo "$RESPONSE" | grep -q '"success":true'; then
    RECORD_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    echo ""
    echo "✅ DNS record created successfully!"
    echo ""
    echo "Record details:"
    echo "  ID: $RECORD_ID"
    echo "  Name: ide.kushnir.cloud"
    echo "  Type: A"
    echo "  Content: $IP_ADDRESS"
    echo "  TTL: 1 (automatic)"
    echo ""
    echo "DNS propagation may take 5-10 minutes globally"
    echo ""
    echo "To verify DNS is working:"
    echo "  dig ide.kushnir.cloud"
    echo "  nslookup ide.kushnir.cloud"
    echo "  curl -I https://ide.kushnir.cloud"
    echo ""
else
    echo ""
    echo "❌ ERROR: Failed to create DNS record"
    echo ""
    echo "API Response:"
    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
    echo ""
    exit 1
fi
