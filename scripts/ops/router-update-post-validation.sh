#!/bin/bash
# Router Update Post-Validation Script
# Run this AFTER updating router port-forwards to 192.168.168.30
# Verifies the router update was successful

set -e
trap 'echo "❌ Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Script completed"; true' EXIT

VIP="192.168.168.30"
PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"

PASS=0
FAIL=0
WARN=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

check_pass() {
  echo -e "${GREEN}✅${NC} $1"
  PASS+=1
}

check_fail() {
  echo -e "${RED}❌${NC} $1"
  FAIL+=1
}

check_warn() {
  echo -e "${YELLOW}⚠️ ${NC} $1"
  WARN+=1
}

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ROUTER UPDATE POST-VALIDATION                        ║${NC}"
echo -e "${BLUE}║  $(date)                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
echo -e "${BLUE}SECTION 1: VIP Reachability${NC}"
echo "─────────────────────────────────────────────────────────────"

# Test 1: VIP ping
echo -n "VIP ICMP (ping) reachable:      "
if ping -c 1 -W 2 "$VIP" >/dev/null 2>&1; then
  check_pass "Yes"
else
  check_fail "NO - Critical: VIP not responding to ping"
fi

# Test 2: VIP HTTP
echo -n "VIP HTTP /health endpoint:     "
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$VIP/health" 2>/dev/null || echo "000")
if [[ "$HTTP_STATUS" == "200" ]]; then
  check_pass "HTTP 200 OK"
else
  check_fail "HTTP $HTTP_STATUS - Check router port-forward rules"
fi

# Test 3: VIP HTTPS
echo -n "VIP HTTPS /health endpoint:    "
HTTPS_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://$VIP/health" 2>/dev/null || echo "000")
if [[ "$HTTPS_STATUS" == "200" ]]; then
  check_pass "HTTPS 200 OK"
else
  check_warn "HTTPS $HTTPS_STATUS (may be DNS/cert related)"
fi

# ============================================================================
echo ""
echo -e "${BLUE}SECTION 2: VRRP Status${NC}"
echo "─────────────────────────────────────────────────────────────"

# Test 4: Primary VRRP
echo -n "Primary VRRP status:           "
PRIMARY_VRRP=$(ssh -o BatchMode=yes akushnir@$PRIMARY \
  "docker exec code-server-keepalived cat /var/run/keepalived.status 2>/dev/null || echo UNKNOWN" 2>/dev/null || echo "UNKNOWN")
if [[ "$PRIMARY_VRRP" == "MASTER" ]]; then
  check_pass "MASTER"
else
  check_fail "Status: $PRIMARY_VRRP (expected MASTER)"
fi

# Test 5: Replica VRRP
echo -n "Replica VRRP status:           "
REPLICA_VRRP=$(ssh -o BatchMode=yes akushnir@$REPLICA \
  "docker exec code-server-keepalived cat /var/run/keepalived.status 2>/dev/null || echo UNKNOWN" 2>/dev/null || echo "UNKNOWN")
if [[ "$REPLICA_VRRP" == "BACKUP" ]]; then
  check_pass "BACKUP"
else
  check_fail "Status: $REPLICA_VRRP (expected BACKUP)"
fi

# ============================================================================
echo ""
echo -e "${BLUE}SECTION 3: Container Health${NC}"
echo "─────────────────────────────────────────────────────────────"

# Test 6: Primary containers
echo -n "Primary containers healthy:    "
PRIMARY_HEALTHY=$(ssh -o BatchMode=yes akushnir@$PRIMARY \
  "docker ps --format '{{.Status}}' | grep -c healthy" 2>/dev/null || echo "0")
if [[ "$PRIMARY_HEALTHY" -ge 25 ]]; then
  check_pass "$PRIMARY_HEALTHY healthy"
else
  check_fail "$PRIMARY_HEALTHY healthy (expected 28+)"
fi

# Test 7: Replica containers
echo -n "Replica containers healthy:    "
REPLICA_HEALTHY=$(ssh -o BatchMode=yes akushnir@$REPLICA \
  "docker ps --format '{{.Status}}' | grep -c healthy" 2>/dev/null || echo "0")
if [[ "$REPLICA_HEALTHY" -ge 24 ]]; then
  check_pass "$REPLICA_HEALTHY healthy"
else
  check_fail "$REPLICA_HEALTHY healthy (expected 27+)"
fi

# ============================================================================
echo ""
echo -e "${BLUE}SECTION 4: Router Configuration${NC}"
echo "─────────────────────────────────────────────────────────────"

echo -e "${YELLOW}ℹ️ ${NC}Router configuration verification requires manual access"
echo ""
echo "Please verify in router admin panel (http://192.168.1.1):"
echo ""
echo "✓ Port Forwarding rules:"
echo "    External Port 80  → Internal IP 192.168.168.30:80"
echo "    External Port 443 → Internal IP 192.168.168.30:443"
echo ""
echo "If rules still show 192.168.168.31:"
echo "    1. Edit each rule to point to 192.168.168.30"
echo "    2. Save configuration"
echo "    3. Wait 30 seconds"
echo "    4. Re-run this validation"
echo ""

# ============================================================================
echo ""
echo -e "${BLUE}SECTION 5: Failover Readiness${NC}"
echo "─────────────────────────────────────────────────────────────"

echo "To test failover (manual steps):"
echo ""
echo "1. SSH to primary host:"
echo "   ssh akushnir@192.168.168.31"
echo ""
echo "2. Pause a few containers:"
echo "   docker pause \$(docker ps --format '{{.ID}}' | head -5)"
echo ""
echo "3. From another terminal, monitor VIP:"
echo "   while true; do curl -s http://192.168.168.30/health && echo ' ✓'; sleep 1; done"
echo ""
echo "4. Observe:"
echo "   - VIP remains responsive"
echo "   - After ~5 seconds, VRRP switches Replica to MASTER"
echo "   - Requests continue flowing without interruption"
echo ""
echo "5. Restore primary (from primary host SSH):"
echo "   docker unpause \$(docker ps --format '{{.ID}}' | head -5)"
echo ""
echo "6. Verify primary returns to MASTER:"
echo "   sleep 5 && docker exec code-server-keepalived cat /var/run/keepalived.status"
echo ""

# ============================================================================
echo ""
echo -e "${BLUE}═════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}VALIDATION SUMMARY${NC}"
echo -e "${BLUE}═════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Checks Passed: ${GREEN}$PASS${NC}"
echo -e "Checks Failed: ${RED}$FAIL${NC}"
echo -e "Checks Warned: ${YELLOW}$WARN${NC}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}✅ ROUTER UPDATE SUCCESSFUL${NC}"
  echo ""
  echo "Your system now supports transparent failover:"
  echo ""
  echo "  Internet → Router (port-forward to VIP) → Primary/Replica"
  echo ""
  echo "  On primary failure:"
  echo "    - VIP automatically switches to Replica (<5 seconds)"
  echo "    - No external DNS changes needed"
  echo "    - Clients reconnect to VIP (now served by Replica)"
  echo "    - Failback automatic when primary recovers"
  echo ""
  echo "Next steps:"
  echo "1. Update DNS records to point to VIP if desired"
  echo "   (See DNS_SSL_CONFIGURATION.md for details)"
  echo "2. Run a failover test (see instructions above)"
  echo "3. Update ROUTER_UPDATE_CHECKPOINT.md with completion time"
  echo "4. Commit changes: git add -A && git commit -m 'ops: router update complete'"
  exit 0
else
  echo -e "${RED}❌ ROUTER UPDATE INCOMPLETE${NC}"
  echo ""
  echo "Issues found:"
  echo "- VIP not responding to HTTP requests"
  echo "- Likely cause: Port-forward rules not yet updated in router"
  echo ""
  echo "Troubleshooting:"
  echo "1. Verify router port-forward rules (see Section 4 above)"
  echo "2. Ensure rules point to 192.168.168.30 (not 192.168.168.31)"
  echo "3. Router may need 30-60 seconds to apply changes"
  echo "4. If router rebooted: This is expected, VIP remains active"
  echo "5. Re-run this validation after confirming router changes"
  exit 1
fi
