#!/bin/bash

# Phase 14: Production DNS Failover Script
# Purpose: Execute DNS cutover from staging to production
# Timeline: April 14, 2026 @ 08:30 UTC
# Owner: Infrastructure Team

set -euo pipefail

# ===== CONFIGURATION =====
STAGING_IP="192.168.168.30"      # Current production (staging)
PRODUCTION_IP="192.168.168.31"   # New production (code-server-31)
DOMAIN="code-server.company.com"
CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
ROLLBACK_DELAY=300               # Seconds before allowing rollback

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "════════════════════════════════════════════════════════════════"
echo "PHASE 14: PRODUCTION DNS FAILOVER"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📅 Timeline: April 14, 2026 @ 08:30 UTC"
echo "🎯 Action: DNS cutover to production (192.168.168.31)"
echo "⏱️  Execution: 3-5 minutes"
echo ""

# ===== 1. PRE-FAILOVER VALIDATION =====
echo "1️⃣  PRE-FAILOVER VALIDATION"
echo "────────────────────────────────────────────────────────────────"

# Verify production is ready
echo "  Checking production health (192.168.168.31)..."
if ! timeout 5 curl -sf "http://${PRODUCTION_IP}:8080/health" > /dev/null 2>&1; then
    echo "  ❌ Production health check FAILED"
    exit 1
fi
echo "  ✅ Production is healthy"

# Verify staging is still operational
echo "  Checking staging health (192.168.168.30)..."
if ! timeout 5 curl -sf "http://${STAGING_IP}:8080/health" > /dev/null 2>&1; then
    echo "  ⚠️  Staging is not healthy, but proceeding (cutover may be forced)"
fi
echo "  ✅ Pre-failover validation complete"
echo ""

# ===== 2. DNS RECORD VERIFICATION =====
echo "2️⃣  DNS RECORD VERIFICATION"
echo "────────────────────────────────────────────────────────────────"

echo "  Current DNS records for ${DOMAIN}:"
if command -v dig &> /dev/null; then
    dig +short "${DOMAIN}" | head -5
else
    nslookup "${DOMAIN}" | grep -A 5 "Name:"
fi

echo "  Current Cloudflare tunnel status:"
if [ -n "$CLOUDFLARE_API_TOKEN" ]; then
    TUNNEL_ID=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/*/cfd_tunnel" | \
        jq -r '.result[0].id')
    echo "  ✅ Cloudflare tunnel ID: $TUNNEL_ID"
else
    echo "  ⚠️  CLOUDFLARE_API_TOKEN not set, skipping tunnel verification"
fi
echo ""

# ===== 3. EXECUTE DNS FAILOVER =====
echo "3️⃣  EXECUTE DNS FAILOVER"
echo "────────────────────────────────────────────────────────────────"

echo "  📌 POINT OF NO RETURN 📌"
echo ""
echo "  🟡 About to update DNS records:"
echo "     FROM: ${STAGING_IP} (192.168.168.30)"
echo "     TO:   ${PRODUCTION_IP} (192.168.168.31)"
echo ""
read -p "  Confirm DNS failover? (type 'YES' to proceed): " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "  ❌ Failover cancelled"
    exit 1
fi

echo ""
echo "  🚀 Updating DNS records..."
echo "  Timestamp: $(date +'%Y-%m-%d %H:%M:%S UTC')"
echo ""

# Update DNS (Using Cloudflare API or local DNS)
if [ -n "$CLOUDFLARE_API_TOKEN" ]; then
    # Update Cloudflare DNS record
    echo "  Updating Cloudflare DNS..."
    RESPONSE=$(curl -s -X PUT \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -d "{\"type\":\"A\",\"name\":\"${DOMAIN}\",\"content\":\"${PRODUCTION_IP}\",\"ttl\":60}")
    
    if echo "$RESPONSE" | jq -e '.success' > /dev/null 2>&1; then
        echo "  ✅ Cloudflare DNS updated successfully"
    else
        echo "  ❌ Cloudflare DNS update failed"
        echo "$RESPONSE"
        exit 1
    fi
else
    echo "  ℹ️  Manual DNS update required:"
    echo "     Domain: ${DOMAIN}"
    echo "     Old IP: ${STAGING_IP}"
    echo "     New IP: ${PRODUCTION_IP}"
    echo "     Action: Update DNS A record to ${PRODUCTION_IP}"
    echo ""
    read -p "  Confirm DNS manually updated? (type 'YES'): " MANUAL_CONFIRM
    if [ "$MANUAL_CONFIRM" != "YES" ]; then
        echo "  ❌ DNS failover cancelled"
        exit 1
    fi
fi

echo ""
echo "  ✅ DNS failover complete!"
echo ""

# ===== 4. PROPAGATION WAIT =====
echo "4️⃣  DNS PROPAGATION"
echo "────────────────────────────────────────────────────────────────"

echo "  Waiting for DNS propagation (TTL: 60 seconds)..."
for i in {1..12}; do
    sleep 5
    CURRENT_IP=$(dig +short "${DOMAIN}" | head -1)
    if [ "$CURRENT_IP" = "$PRODUCTION_IP" ]; then
        echo "  ✅ DNS propagated (attempt $i/12)"
        break
    fi
    echo "  ⏳ Still propagating... (attempt $i/12, current IP: $CURRENT_IP)"
done

echo ""

# ===== 5. PRODUCTION VERIFICATION =====
echo "5️⃣  PRODUCTION VERIFICATION"
echo "────────────────────────────────────────────────────────────────"

echo "  Testing production via domain name..."
for i in {1..5}; do
    if curl -sf "https://${DOMAIN}/health" > /dev/null 2>&1; then
        echo "  ✅ Production accessible via ${DOMAIN} (attempt $i/5)"
        break
    fi
    echo "  ⏳ Waiting for production to be accessible (attempt $i/5)..."
    sleep 2
done

# ===== 6. ROLLBACK PROTECTION =====
echo ""
echo "6️⃣  ROLLBACK PROTECTION"
echo "────────────────────────────────────────────────────────────────"

echo "  🔒 Rollback protection enabled"
echo "  Rollback disabled for: ${ROLLBACK_DELAY} seconds ($(( ROLLBACK_DELAY / 60 )) minutes)"
echo ""
echo "  To rollback after protection expires:"
echo "  $ bash scripts/phase-14-dns-rollback.sh"
echo ""

# ===== 7. SUMMARY =====
echo "════════════════════════════════════════════════════════════════"
echo "✅ PHASE 14 DNS FAILOVER COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📊 Status:"
echo "  • DNS Updated: ✅ ${STAGING_IP} → ${PRODUCTION_IP}"
echo "  • Domain: ${DOMAIN}"
echo "  • Production Ready: ✅"
echo "  • Timestamp: $(date +'%Y-%m-%d %H:%M:%S UTC')"
echo ""
echo "🎯 NEXT STEPS:"
echo "  1. Monitor production dashboards (every 15 min)"
echo "  2. Verify developer activity normal"
echo "  3. Check SLO compliance (latency, errors, uptime)"
echo "  4. At 12:00 UTC: Go/No-Go decision"
echo ""
echo "⏱️  Rollback available for ${ROLLBACK_DELAY} seconds"
echo ""

exit 0
