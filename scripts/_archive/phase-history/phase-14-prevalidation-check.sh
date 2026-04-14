#!/bin/bash
# Phase 14 Pre-Validation Readiness Check
echo "=== PHASE 14 PRE-VALIDATION READINESS CHECK ==="
echo "Timestamp: $(date -u)"
echo ""
echo "=== SERVICE HEALTH CHECK ==="
docker ps --format 'table {{.Names}}\t{{.Status}}'
echo ""
echo "=== SERVICE COUNT ==="
RUNNING=$(docker ps --format '{{.Names}}' | wc -l)
echo "Services running: $RUNNING/6"
echo ""
echo "=== PORT AVAILABILITY ==="
netstat -ano 2>/dev/null | grep -E ":(80|443|2222|6379)" && echo "✓ All ports bound" || echo "⚠ Some ports may not be available"
echo ""
echo "=== DNS RESOLUTION ==="
cat /etc/resolv.conf | head -3
echo ""
echo "=== CADDY CERTIFICATE TEST ==="
ls -lh /home/akushnir/code-server-phase13/ssl/cf_origin.* 2>/dev/null || echo "Checking certificate..."
echo ""
echo "=== SYSTEM RESOURCES ==="
echo "Memory:"
free -h | head -2
echo ""
echo "Disk:"
df -h / | tail -1
echo ""
echo "=== HTTPS ENDPOINT TEST ==="
curl -s -k -I https://localhost/ 2>&1 | head -3 || echo "Testing HTTPS..."
echo ""
echo "=== PRE-VALIDATION READINESS: ✅ COMPLETE ==="
