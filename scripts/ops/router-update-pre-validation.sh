#!/bin/bash
# Router Update Pre-Validation Script
# Run this BEFORE updating router port-forwards
# Verifies all prerequisites are met

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
  ((PASS++))
}

check_fail() {
  echo -e "${RED}❌${NC} $1"
  ((FAIL++))
}

check_warn() {
  echo -e "${YELLOW}⚠️ ${NC} $1"
  ((WARN++))
}

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ROUTER UPDATE PRE-VALIDATION                         ║${NC}"
echo -e "${BLUE}║  $(date)                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
echo -e "${BLUE}SECTION 1: Platform Health${NC}"
echo "─────────────────────────────────────────────────────────────"

# Test 1: Primary reachable
echo -n "Primary host (192.168.168.31): "
if ping -c 1 -W 2 "$PRIMARY" >/dev/null 2>&1; then
  check_pass "Reachable"
else
  check_fail "NOT reachable - Critical"
fi

# Test 2: Replica reachable
echo -n "Replica host (192.168.168.42): "
if ping -c 1 -W 2 "$REPLICA" >/dev/null 2>&1; then
  check_pass "Reachable"
else
  check_fail "NOT reachable - Critical"
fi

# Test 3: VIP reachable
echo -n "Virtual IP (192.168.168.30):   "
if ping -c 1 -W 2 "$VIP" >/dev/null 2>&1; then
  check_pass "Reachable"
else
  check_fail "NOT reachable - Critical"
fi

# Test 4: SSH access to primary
echo -n "SSH to primary:                "
if ssh -o BatchMode=yes -o ConnectTimeout=3 "akushnir@$PRIMARY" "echo ok" >/dev/null 2>&1; then
  check_pass "Working"
else
  check_fail "FAILED - Cannot SSH to primary"
fi

# Test 5: SSH access to replica
echo -n "SSH to replica:                "
if ssh -o BatchMode=yes -o ConnectTimeout=3 "akushnir@$REPLICA" "echo ok" >/dev/null 2>&1; then
  check_pass "Working"
else
  check_fail "FAILED - Cannot SSH to replica"
fi

# ============================================================================
echo ""
echo -e "${BLUE}SECTION 2: Container Health${NC}"
echo "─────────────────────────────────────────────────────────────"

# Test 6: Primary containers
echo -n "Primary containers running:    "
PRIMARY_COUNT=$(ssh -o BatchMode=yes akushnir@$PRIMARY "docker ps --format '{{.Names}}' | wc -l" 2>/dev/null || echo "0")
if [[ "$PRIMARY_COUNT" -ge 25 ]]; then
  check_pass "$PRIMARY_COUNT containers"
else
  check_warn "$PRIMARY_COUNT containers (expected 28+)"
fi

# Test 7: Primary healthy
echo -n "Primary containers healthy:    "
PRIMARY_HEALTHY=$(ssh -o BatchMode=yes akushnir@$PRIMARY "docker ps --format '{{.Status}}' | grep -c healthy" 2>/dev/null || echo "0")
if [[ "$PRIMARY_HEALTHY" -ge 25 ]]; then
  check_pass "$PRIMARY_HEALTHY healthy"
else
  check_warn "$PRIMARY_HEALTHY healthy (expected 28+)"
fi

# Test 8: Replica containers
echo -n "Replica containers running:    "
REPLICA_COUNT=$(ssh -o BatchMode=yes akushnir@$REPLICA "docker ps --format '{{.Names}}' | wc -l" 2>/dev/null || echo "0")
if [[ "$REPLICA_COUNT" -ge 24 ]]; then
  check_pass "$REPLICA_COUNT containers"
else
  check_warn "$REPLICA_COUNT containers (expected 27+)"
fi

# Test 9: Replica healthy
echo -n "Replica containers healthy:    "
REPLICA_HEALTHY=$(ssh -o BatchMode=yes akushnir@$REPLICA "docker ps --format '{{.Status}}' | grep -c healthy" 2>/dev/null || echo "0")
if [[ "$REPLICA_HEALTHY" -ge 24 ]]; then
  check_pass "$REPLICA_HEALTHY healthy"
else
  check_warn "$REPLICA_HEALTHY healthy (expected 27+)"
fi

# ============================================================================
echo ""
echo -e "${BLUE}SECTION 3: VRRP HA Status${NC}"
echo "─────────────────────────────────────────────────────────────"

# Test 10: Primary VRRP status
echo -n "Primary VRRP status:           "
PRIMARY_VRRP=$(ssh -o BatchMode=yes akushnir@$PRIMARY \
  "docker exec code-server-keepalived cat /var/run/keepalived.status 2>/dev/null || echo UNKNOWN" 2>/dev/null || echo "UNKNOWN")
if [[ "$PRIMARY_VRRP" == "MASTER" ]]; then
  check_pass "MASTER (OK)"
else
  check_warn "Status: $PRIMARY_VRRP (check keepalived)"
fi

# Test 11: Replica VRRP status
echo -n "Replica VRRP status:           "
REPLICA_VRRP=$(ssh -o BatchMode=yes akushnir@$REPLICA \
  "docker exec code-server-keepalived cat /var/run/keepalived.status 2>/dev/null || echo UNKNOWN" 2>/dev/null || echo "UNKNOWN")
if [[ "$REPLICA_VRRP" == "BACKUP" ]]; then
  check_pass "BACKUP (OK)"
else
  check_warn "Status: $REPLICA_VRRP (check keepalived)"
fi

# ============================================================================
echo ""
echo -e "${BLUE}SECTION 4: HTTP Health${NC}"
echo "─────────────────────────────────────────────────────────────"

# Test 12: VIP HTTP response
echo -n "VIP HTTP /health endpoint:     "
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$VIP/health" 2>/dev/null || echo "000")
if [[ "$HTTP_STATUS" == "200" ]]; then
  check_pass "HTTP 200 OK"
else
  check_fail "HTTP $HTTP_STATUS (expected 200)"
fi

# Test 13: Primary HTTP response
echo -n "Primary HTTP /health endpoint: "
PRIMARY_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://$PRIMARY/health" 2>/dev/null || echo "000")
if [[ "$PRIMARY_HTTP" == "200" ]]; then
  check_pass "HTTP 200 OK"
else
  check_fail "HTTP $PRIMARY_HTTP"
fi

# Test 14: Replica HTTP response
echo -n "Replica HTTP /health endpoint: "
REPLICA_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://$REPLICA/health" 2>/dev/null || echo "000")
if [[ "$REPLICA_HTTP" == "200" ]]; then
  check_pass "HTTP 200 OK"
else
  check_fail "HTTP $REPLICA_HTTP"
fi

# ============================================================================
echo ""
echo -e "${BLUE}SECTION 5: Database Connectivity${NC}"
echo "─────────────────────────────────────────────────────────────"

# Test 15: PostgreSQL on primary
echo -n "PostgreSQL on primary:         "
if ssh -o BatchMode=yes akushnir@$PRIMARY \
  "docker exec code-server-postgres psql -U postgres -d code_server -c 'SELECT 1' >/dev/null 2>&1"; then
  check_pass "Accessible"
else
  check_warn "Connection check failed"
fi

# Test 16: PostgreSQL on replica
echo -n "PostgreSQL on replica:         "
if ssh -o BatchMode=yes akushnir@$REPLICA \
  "docker exec code-server-postgres psql -U postgres -d code_server -c 'SELECT 1' >/dev/null 2>&1"; then
  check_pass "Accessible"
else
  check_warn "Connection check failed"
fi

# ============================================================================
echo ""
echo -e "${BLUE}SECTION 6: Network Access${NC}"
echo "─────────────────────────────────────────────────────────────"

# Test 17: Router reachability (common IPs)
echo -n "Router accessibility:          "
ROUTER_FOUND=0
for ROUTER_IP in 192.168.1.1 192.168.0.1 10.0.0.1 172.16.0.1; do
  if ping -c 1 -W 1 "$ROUTER_IP" >/dev/null 2>&1; then
    check_pass "Found at $ROUTER_IP"
    ROUTER_FOUND=1
    break
  fi
done
if [[ $ROUTER_FOUND -eq 0 ]]; then
  check_warn "Router not found at common IPs (may need manual access)"
fi

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
  echo -e "${GREEN}✅ SYSTEM READY FOR ROUTER UPDATE${NC}"
  echo ""
  echo "Next steps:"
  echo "1. Access your router admin panel (http://192.168.1.1 or similar)"
  echo "2. Navigate to Port Forwarding settings"
  echo "3. Update rules:"
  echo "   - Port 80/443 external → 192.168.168.30 internal (was 192.168.168.31)"
  echo "4. Save configuration"
  echo "5. Run: router-update-post-validation.sh"
  exit 0
else
  echo -e "${RED}❌ SYSTEM NOT READY${NC}"
  echo ""
  echo "Fix the failed checks before proceeding with router update."
  echo "See output above for details."
  exit 1
fi
