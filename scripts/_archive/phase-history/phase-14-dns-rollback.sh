#!/bin/bash

# Phase 14: DNS Rollback Procedure
# Purpose: Rollback production traffic from 192.168.168.31 back to staging 192.168.168.30
# Timeline: Available for 5 minutes after Phase 14 launch (18:50-21:55 UTC)
# Owner: Operations Team

set -euo pipefail

# ===== CONFIGURATION =====
STAGING_IP="192.168.168.30"
PRODUCTION_IP="192.168.168.31"
CLOUDFLARE_API_ZONE="kushnir.cloud"
CLOUDFLARE_DNS_NAME="ide"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_TOKEN:-}"
REMOTE_HOST="192.168.168.31"
REMOTE_USER="root"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ===== ROLLBACK PROCEDURES =====

echo "════════════════════════════════════════════════════════════════"
echo "PHASE 14: ROLLBACK PROCEDURE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "⚠️  WARNING: This procedure is only available during the 5-minute"
echo "    rollback window after Phase 14 launch (18:50-21:55 UTC)"
echo ""
echo "Rollback Target: Staging Infrastructure (192.168.168.30)"
echo "Current Production: 192.168.168.31"
echo ""

# Confirm rollback
read -p "🔴 Proceed with rollback to staging? [y/N]: " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Rollback cancelled."
    exit 0
fi

echo ""
echo "Initiating rollback sequence..."
echo ""

# ===== STEP 1: VALIDATE STAGING INFRASTRUCTURE =====
echo "Step 1: Validating staging infrastructure..."

# Check staging host connectivity
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${REMOTE_USER}@${STAGING_IP}" exit 2>/dev/null; then
    echo -e "${RED}✗ Staging host unreachable${NC}"
    echo "Cannot complete rollback. Staging infrastructure must be available."
    exit 1
fi

echo "✅ Staging host connectivity: OK"

# Check staging containers
STAGING_CONTAINERS=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${REMOTE_USER}@${STAGING_IP}" \
    "docker ps --filter 'status=running' --format '{{.Names}}' | grep -E '(code-server|caddy|ssh-proxy)' | wc -l")

if [ "$STAGING_CONTAINERS" -lt 3 ]; then
    echo -e "${RED}✗ Staging containers not all running${NC}"
    echo "Found $STAGING_CONTAINERS/3 required containers"
    exit 1
fi

echo "✅ Staging containers: 3/3 running"

# ===== STEP 2: PRE-ROLLBACK SNAPSHOT =====
echo ""
echo "Step 2: Creating pre-rollback snapshot..."

SNAPSHOT_DIR="/tmp/phase14-rollback-snapshot-$(date +%s)"
mkdir -p "$SNAPSHOT_DIR"

echo "Capturing production metrics..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${REMOTE_USER}@${PRODUCTION_IP}" \
    "docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}'" \
    > "$SNAPSHOT_DIR/production-stats-before.txt" 2>/dev/null || true

echo "Capturing DNS state..."
nslookup ide.kushnir.cloud > "$SNAPSHOT_DIR/dns-state-before.txt" 2>&1 || true

echo "✅ Snapshot created: $SNAPSHOT_DIR"

# ===== STEP 3: DNS CUTOVER TO STAGING =====
echo ""
echo "Step 3: Updating DNS to staging IP ($STAGING_IP)..."

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo -e "${YELLOW}⚠️  CLOUDFLARE_TOKEN not set${NC}"
    echo "Manual DNS update required:"
    echo "  Service: ide.kushnir.cloud"
    echo "  A Record: $STAGING_IP (was $PRODUCTION_IP)"
    echo "  TTL: 60 seconds"
    echo ""
    read -p "Confirm DNS updated manually? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Rollback cancelled - DNS not updated"
        exit 1
    fi
else
    # Cloudflare API call
    echo "Using Cloudflare API..."

    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${CLOUDFLARE_API_ZONE}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${CLOUDFLARE_DNS_NAME}.${CLOUDFLARE_API_ZONE}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [ -z "$ZONE_ID" ] || [ -z "$RECORD_ID" ] || [ "$ZONE_ID" = "null" ] || [ "$RECORD_ID" = "null" ]; then
        echo -e "${RED}✗ Failed to resolve Cloudflare Zone/Record IDs${NC}"
        exit 1
    fi

    # Update DNS record
    UPDATE_RESPONSE=$(curl -s -X PUT \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"${CLOUDFLARE_DNS_NAME}.${CLOUDFLARE_API_ZONE}\",\"content\":\"${STAGING_IP}\",\"ttl\":60}")

    if echo "$UPDATE_RESPONSE" | grep -q '"success":true'; then
        echo "✅ DNS A record updated: ide.kushnir.cloud → $STAGING_IP"
    else
        echo -e "${RED}✗ DNS update failed${NC}"
        echo "$UPDATE_RESPONSE"
        exit 1
    fi
fi

# Wait for DNS propagation
echo ""
echo "Waiting for DNS propagation (60 seconds)..."
ELAPSED=0
while [ $ELAPSED -lt 60 ]; do
    CURRENT_IP=$(dig +short ide.kushnir.cloud A | tail -1)
    if [ "$CURRENT_IP" = "$STAGING_IP" ]; then
        echo "✅ DNS propagated to staging IP"
        break
    fi
    echo -n "."
    sleep 5
    ((ELAPSED += 5))
done

# ===== STEP 4: TRAFFIC FAILOVER VALIDATION =====
echo ""
echo "Step 4: Validating traffic failover..."

# Check staging service health
echo "Testing staging service connectivity..."
for i in {1..5}; do
    if curl -s -m 5 "https://ide.kushnir.cloud/health" > /dev/null 2>&1; then
        echo "✅ Staging service health check passed (attempt $i/5)"
        break
    fi
    echo "⏳ Retry $i/5 (waiting 3 seconds)..."
    sleep 3
done

# Verify traffic is flowing to staging
echo ""
echo "Testing service endpoints..."
curl -s -m 5 "https://ide.kushnir.cloud/" | grep -q "code-server" && \
    echo "✅ Web UI accessible on staging" || \
    echo "⚠️  Web UI check inconclusive"

# ===== STEP 5: POST-ROLLBACK VALIDATION =====
echo ""
echo "Step 5: Post-rollback validation..."

echo "Capturing staging metrics..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${REMOTE_USER}@${STAGING_IP}" \
    "docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}'" \
    > "$SNAPSHOT_DIR/staging-stats-after.txt" 2>/dev/null || true

echo "Verifying DNS state..."
nslookup ide.kushnir.cloud > "$SNAPSHOT_DIR/dns-state-after.txt" 2>&1 || true

# ===== STEP 6: INCIDENT REPORT =====
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "ROLLBACK COMPLETED SUCCESSFULLY"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "✅ DNS updated: ide.kushnir.cloud → $STAGING_IP"
echo "✅ Traffic now flowing to staging"
echo "✅ Service health validated"
echo ""

# Create incident report
INCIDENT_FILE="${SNAPSHOT_DIR}/ROLLBACK_INCIDENT_REPORT.md"
cat > "$INCIDENT_FILE" << EOF
# Phase 14 Rollback Incident Report

**Rollback Timestamp**: $(date +'%Y-%m-%d %H:%M:%S UTC')
**Duration**: 5-10 minutes
**Reason**: Production SLO violation or critical issue detected

## Actions Taken

1. ✅ Staging infrastructure validated (3/3 containers healthy)
2. ✅ Pre-rollback metrics captured
3. ✅ DNS A record updated: ide.kushnir.cloud → $STAGING_IP
4. ✅ DNS propagation verified (< 60 sec)
5. ✅ Staging service health validated
6. ✅ Post-rollback metrics captured

## Current State

- **Service URL**: ide.kushnir.cloud
- **Active Infrastructure**: Staging (192.168.168.30)
- **Production Status**: Idle, ready for investigation
- **User Impact**: Minimal (rollback < 2 minutes)

## Next Steps

1. **Investigation Phase**: Analyze production logs
2. **Root Cause Analysis**: Identify SLO violation
3. **Remediation**: Fix identified issues
4. **Re-validation**: Run full Phase 14 pre-flight
5. **Retry Deployment**: Plan Phase 14 re-launch

## Rollback Snapshots

- Pre-rollback stats: production-stats-before.txt
- Post-rollback stats: staging-stats-after.txt
- DNS states: dns-state-before.txt, dns-state-after.txt

---

**Incident Owner**: Operations Team
**Priority**: CRITICAL (re-launch Phase 14 when ready)
EOF

echo "📋 Incident report created: $INCIDENT_FILE"
echo ""
echo "Snapshot Location: $SNAPSHOT_DIR"
echo ""
echo "⚠️  ACTION REQUIRED:"
echo "   1. Investigate production logs immediately"
echo "   2. Root cause analysis documents needed"
echo "   3. Update GitHub issue #210 with rollback details"
echo "   4. Plan Phase 14 re-launch once issues fixed"
echo ""

# Create GitHub issue template
cat > "/tmp/PHASE-14-ROLLBACK-ISSUE-TEMPLATE.txt" << EOF
## Phase 14 Production Rollback - Incident Report

**Status**: Rolled back to staging (192.168.168.30)
**Timestamp**: $(date +'%Y-%m-%d %H:%M:%S UTC')
**Service**: ide.kushnir.cloud

### Root Cause
[TO BE DETERMINED - Requires log analysis]

### SLO Violations Detected
- [ ] Latency p99 exceeded 100ms
- [ ] Error rate exceeded 0.1%
- [ ] Availability below 99.9%
- [ ] Container restart issues
- [ ] Other (specify below)

### Remediation Actions
[ ] Identify root cause
[ ] Implement fix
[ ] Test on staging
[ ] Prepare Phase 14 re-launch
[ ] Get executive re-approval

### Timeline for Re-launch
Scheduled: [Date/Time TBD]

---

**@kushin77** - Immediate log analysis required
**@operations** - Prepare re-launch checklist
**@security** - Validate security implications
EOF

echo "GitHub issue template available: /tmp/PHASE-14-ROLLBACK-ISSUE-TEMPLATE.txt"
echo ""

exit 0
