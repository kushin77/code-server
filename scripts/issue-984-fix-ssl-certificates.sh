#!/bin/bash
# @file        scripts/issue-984-fix-ssl-certificates.sh
# @module      issue-984/ssl-fix
# @description Fix SSL/TLS certificate issues preventing OAuth from working

set -euo pipefail

echo "=============================================="
echo "SSL Certificate Fix for Issue #984"
echo "=============================================="
echo ""

# Check current certificate status
echo "Checking current certificate status..."
docker exec caddy ls -la /data/caddy/certificates 2>/dev/null || echo "⚠ No certificates found in Caddy"

# Step 1: Stop Caddy
echo ""
echo "Step 1: Stopping Caddy..."
docker stop caddy || true
sleep 2

# Step 2: Clean up certificate cache (force renewal)
echo "Step 2: Cleaning certificate cache..."
docker run --rm -v caddy_data:/data alpine rm -rf /data/caddy/certificates /data/caddy/acme 2>/dev/null || echo "⚠ Could not clean cache"

# Step 3: Restart Caddy (will request new certificates)
echo "Step 3: Restarting Caddy with certificate renewal..."
docker-compose up -d caddy
sleep 10

# Step 4: Monitor Caddy startup
echo "Step 4: Monitoring Caddy logs..."
for i in {1..30}; do
    if docker ps --filter name=caddy | grep -q "caddy"; then
        echo "✓ Caddy started (attempt $i)"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: Caddy failed to start after 30 attempts"
        exit 1
    fi
    sleep 1
done

# Step 5: Wait for certificate generation (Let's Encrypt)
echo "Step 5: Waiting for certificates to be generated..."
for i in {1..60}; do
    if docker exec caddy ls /data/caddy/certificates > /dev/null 2>&1; then
        echo "✓ Certificates found"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "⚠ Certificates not found after 60 seconds (may need manual intervention)"
    fi
    echo "  Waiting... ($i/60)"
    sleep 1
done

# Step 6: Test HTTPS endpoint
echo ""
echo "Step 6: Testing HTTPS endpoint..."
IDE_DOMAIN="${IDE_DOMAIN:-ide.kushnir.cloud}"
if curl -s -k --max-time 10 "https://$IDE_DOMAIN/health" > /dev/null 2>&1; then
    echo "✓ HTTPS endpoint is working"
else
    echo "⚠ HTTPS endpoint is not yet responding (may need more time)"
fi

# Step 7: Verify certificate
echo ""
echo "Step 7: Verifying certificate details..."
echo | openssl s_client -servername "$IDE_DOMAIN" -connect localhost:443 2>/dev/null | grep -A 2 "subject=" || echo "⚠ Could not verify certificate"

echo ""
echo "=============================================="
echo "SSL Fix Complete"
echo "=============================================="
echo ""
echo "Next steps:"
echo "1. Wait 2-5 minutes for Let's Encrypt validation"
echo "2. Test: curl -v https://$IDE_DOMAIN"
echo "3. If still failing, check: docker logs caddy"
echo ""
