#!/bin/bash

# Phase 14: Pre-Launch Checklist & Verification
# Purpose: Final verification that all prerequisites are met for Phase 14 launch
# Timeline: Run before executing phase-14-rapid-execution.sh
# Owner: Infrastructure Team

set -euo pipefail

# ===== CONFIGURATION =====
REMOTE_HOST="192.168.168.31"
REMOTE_USER="root"
STAGING_HOST="192.168.168.30"
CHECKLIST_FILE="/tmp/phase-14-prelaunch-checklist.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Checklist tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# ===== UTILITY FUNCTIONS =====

check_passed() {
  local item=$1
  echo -e "${GREEN}✓${NC} $item"
  ((PASSED_CHECKS++))
}

check_failed() {
  local item=$1
  echo -e "${RED}✗${NC} $item"
  ((FAILED_CHECKS++))
}

section() {
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  $1"
  echo "════════════════════════════════════════════════════════════════"
}

verify_check() {
  ((TOTAL_CHECKS++))
  if [ $? -eq 0 ]; then
    check_passed "$1"
  else
    check_failed "$1"
  fi
}

# ===== CHECKLIST =====

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        PHASE 14: PRE-LAUNCH CHECKLIST & VERIFICATION           ║"
echo "║              All items must PASS before launch                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 1. INFRASTRUCTURE CONNECTIVITY
section "1. INFRASTRUCTURE CONNECTIVITY"

# Check production host
ping -c 1 -W 2 $REMOTE_HOST > /dev/null 2>&1
verify_check "Production host ($REMOTE_HOST) reachable"

# Check staging host
ping -c 1 -W 2 $STAGING_HOST > /dev/null 2>&1
verify_check "Staging host ($STAGING_HOST) reachable"

# Check SSH connectivity
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_HOST exit 2>/dev/null
verify_check "Production SSH access verified"

# 2. DOCKER CONTAINERS
section "2. DOCKER CONTAINERS (Production)"

# Get container count
CONTAINER_COUNT=$(ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
  "docker ps --filter 'status=running' --format '{{.Names}}' | wc -l")

if [ "$CONTAINER_COUNT" -eq 3 ]; then
  check_passed "All 3 required containers running"
  ((PASSED_CHECKS++))
else
  check_failed "Expected 3 containers, found $CONTAINER_COUNT"
  ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))

# Check code-server
ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
  "docker exec code-server-31 exit" 2>/dev/null
verify_check "code-server container is healthy"

# Check caddy
ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
  "docker exec caddy-31 exit" 2>/dev/null
verify_check "caddy container is healthy"

# Check ssh-proxy
ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
  "docker exec ssh-proxy-31 exit" 2>/dev/null
verify_check "ssh-proxy container is healthy"

# 3. MEMORY & DISK
section "3. RESOURCE AVAILABILITY"

# Check memory
MEMORY_AVAILABLE=$(ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
  "free -b | grep Mem | awk '{print \$7}'" 2>/dev/null)

if [ $MEMORY_AVAILABLE -gt 10737418240 ]; then  # 10GB in bytes
  check_passed "Memory available: $(($MEMORY_AVAILABLE / 1073741824))GB (need >10GB)"
  ((PASSED_CHECKS++))
else
  check_failed "Insufficient memory: $(($MEMORY_AVAILABLE / 1073741824))GB (need >10GB)"
  ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))

# Check disk
DISK_AVAILABLE=$(ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
  "df / | tail -1 | awk '{print \$4}'" 2>/dev/null)

if [ $DISK_AVAILABLE -gt 268435456 ]; then  # 256MB in 1K blocks = ~256GB
  check_passed "Disk available: $(($DISK_AVAILABLE / 1048576))GB (need >250GB)"
  ((PASSED_CHECKS++))
else
  check_failed "Insufficient disk: $(($DISK_AVAILABLE / 1048576))GB (need >250GB)"
  ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))

# 4. NETWORKING & DNS
section "4. NETWORKING & DNS"

# Check DNS resolution
nslookup ide.kushnir.cloud > /dev/null 2>&1
verify_check "DNS resolution: ide.kushnir.cloud resolves"

# Check Cloudflare tunnel (basic connectivity)
SSH_RESPONSE=$(ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
  "curl -s -m 5 http://localhost:8080/probe 2>/dev/null | head -c 10")

if [ -n "$SSH_RESPONSE" ]; then
  check_passed "Cloudflare tunnel connectivity verified"
  ((PASSED_CHECKS++))
else
  check_failed "Cloudflare tunnel may be disconnected, please verify"
  ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))

# 5. TLS CERTIFICATES
section "5. TLS & SECURITY"

# Check for TLS certificate
CERT_VALID=$(ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
  "docker exec caddy-31 caddy list-modules | grep -i tls > /dev/null 2>&1 && echo ok" 2>/dev/null)

if [ "$CERT_VALID" = "ok" ]; then
  check_passed "TLS module loaded in caddy"
  ((PASSED_CHECKS++))
else
  check_failed "TLS module not verified in caddy"
  ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))

# 6. GIT STATUS
section "6. GIT & AUTOMATION SCRIPTS"

# Check if phase-14-*.sh scripts exist
PHASE14_SCRIPTS=$(ls -1 scripts/phase-14-*.sh 2>/dev/null | wc -l)

if [ $PHASE14_SCRIPTS -eq 15 ]; then
  check_passed "All Phase 14 scripts present (15 files)"
  ((PASSED_CHECKS++))
else
  check_failed "Expected 15 Phase 14 scripts, found $PHASE14_SCRIPTS"
  ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))

# Check git status
if git status | grep -q "nothing to commit"; then
  check_passed "Git working directory clean"
  ((PASSED_CHECKS++))
else
  check_failed "Uncommitted changes in git (please commit before launch)"
  ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))

# 7. STAGING INFRASTRUCTURE
section "7. STAGING INFRASTRUCTURE (Rollback Target)"

# Check staging host connectivity
ping -c 1 -W 2 $STAGING_HOST > /dev/null 2>&1
verify_check "Staging host connectivity verified"

# Check staging containers
STAGING_CONTAINERS=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $REMOTE_USER@$STAGING_HOST \
  "docker ps --filter 'status=running' --format '{{.Names}}' | wc -l" 2>/dev/null || echo 0)

if [ "$STAGING_CONTAINERS" -eq 3 ]; then
  check_passed "Staging containers ready for rollback (3/3)"
  ((PASSED_CHECKS++))
else
  check_failed "Staging containers not ready for rollback ($STAGING_CONTAINERS/3)"
  ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))

# 8. TEAM READINESS
section "8. TEAM READINESS"

# Check if notification script exists
if [ -f "scripts/phase-14-team-notification.sh" ]; then
  check_passed "Team notification script ready"
  ((PASSED_CHECKS++))
else
  check_failed "Team notification script not found"
  ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))

# 9. DOCUMENTATION
section "9. DOCUMENTATION & APPROVALS"

# Check for readiness summary
if [ -f "PHASE-14-LAUNCH-READINESS-SUMMARY.md" ]; then
  check_passed "Phase 14 Readiness Summary available"
  ((PASSED_CHECKS++))
else
  check_failed "Phase 14 Readiness Summary not found"
  ((FAILED_CHECKS++))
fi
((TOTAL_CHECKS++))

# 10. FINAL DECISION GATE
section "10. FINAL DECISION GATE"

echo ""
echo "Pre-Launch Checklist Summary:"
echo "  Total Checks:  $TOTAL_CHECKS"
echo "  Passed:        ${GREEN}$PASSED_CHECKS${NC}"
echo "  Failed:        ${RED}$FAILED_CHECKS${NC}"
echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║                  ✅ ALL CHECKS PASSED                          ║"
  echo "║          Phase 14 launch is APPROVED and ready to execute      ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "🚀 Ready to proceed with Phase 14 production launch"
  echo ""
  echo "Next steps:"
  echo "1. Run: bash scripts/phase-14-rapid-execution.sh"
  echo "2. Monitor in parallel: bash scripts/phase-14-post-launch-monitoring.sh"
  echo "3. Track progress: bash scripts/phase-14-launch-dashboard.sh"
  echo ""
  exit 0
else
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║              ❌ CHECKLIST FAILED - DO NOT LAUNCH               ║"
  echo "║  $FAILED_CHECKS check(s) failed. Please resolve before launch.  ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "⚠️  Phase 14 launch is BLOCKED until all checks pass"
  echo ""
  echo "Action required:"
  echo "1. Review failed checks above"
  echo "2. Resolve issues on affected infrastructure"
  echo "3. Re-run this checklist: bash scripts/phase-14-prelaunch-checklist.sh"
  echo ""
  exit 1
fi
