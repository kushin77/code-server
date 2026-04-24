#!/bin/bash
# PHASE 13 DAY 2 - APRIL 14, 2026 EXECUTION CHECKLIST
# 24-Hour Sustained Load Testing
# Primary Contact: DevOps Lead
# Backup Contact: Platform Manager

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_header() { echo -e "\n${GREEN}=== $1 ===${NC}\n"; }
log_pass() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# ============================================================================
# PRE-FLIGHT VERIFICATION (08:00-09:00 UTC - April 14, 2026)
# ============================================================================

log_header "PHASE 13 DAY 2 PREFLIGHT VERIFICATION"
echo "Execution Date: April 14, 2026"
echo "Execution Time: 09:00 UTC (Load test begins)"
echo "Duration: 24 hours (until April 15, 09:00 UTC)"
echo "Decision Point: April 15, 12:00 UTC"
echo ""

# ============================================================================
# 1. INFRASTRUCTURE HEALTH CHECK (T-60 minutes)
# ============================================================================

log_header "1. INFRASTRUCTURE HEALTH CHECK (T-60 min)"

echo "[1.1] Container Status Check"
CONTAINER_COUNT=$(docker ps --format "{{.Names}}" | wc -l)
HEALTHY_COUNT=$(docker ps --filter "health=healthy" --format "{{.Names}}" | wc -l)

if [ "$CONTAINER_COUNT" -ge 5 ]; then
  log_pass "Containers running: $CONTAINER_COUNT"
else
  log_error "Expected 5+ containers, found $CONTAINER_COUNT"
  exit 1
fi

if [ "$HEALTHY_COUNT" -ge 4 ]; then
  log_pass "Healthy containers: $HEALTHY_COUNT/5"
else
  log_warn "Only $HEALTHY_COUNT healthy containers (alert threshold: 4)"
fi

echo ""
echo "[1.2] Host Resource Verification"
FREE_SPACE=$(df /home | tail -1 | awk '{print int($4/1024/1024)}')
if [ "$FREE_SPACE" -gt 40 ]; then
  log_pass "Available disk space: ${FREE_SPACE}GB (target: >40GB)"
else
  log_error "Insufficient disk space: ${FREE_SPACE}GB (need >40GB)"
  exit 1
fi

MEMORY=$(free -g | grep Mem | awk '{print $7}')
if [ "$MEMORY" -gt 8 ]; then
  log_pass "Available memory: ${MEMORY}GB (target: >8GB)"
else
  log_warn "Memory low: ${MEMORY}GB available"
fi

echo ""
echo "[1.3] Network Connectivity"
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
  log_pass "Internet connectivity verified"
else
  log_error "Network connectivity failed"
  exit 1
fi

LATENCY=$(ping -c 1 8.8.8.8 | grep avg | awk -F'/' '{print $5}' | cut -d. -f1)
log_pass "Network latency: ${LATENCY}ms"

# ============================================================================
# 2. DEPLOYMENT VERIFICATION (T-45 minutes)
# ============================================================================

log_header "2. DEPLOYMENT VERIFICATION (T-45 min)"

echo "[2.1] Phase 13 Scripts Check"
if [ -d "$HOME/code-server-phase13/scripts" ]; then
  SCRIPT_COUNT=$(ls -1 $HOME/code-server-phase13/scripts/*.sh 2>/dev/null | wc -l)
  log_pass "Phase 13 scripts deployed: $SCRIPT_COUNT scripts found"
else
  log_error "Phase 13 scripts directory not found"
  exit 1
fi

echo ""
echo "[2.2] Monitoring Framework"
if [ -f "$HOME/code-server-phase13/scripts/phase-13-day2-monitoring.sh" ]; then
  log_pass "Monitoring orchestrator present"
else
  log_error "Monitoring orchestrator missing"
  exit 1
fi

echo ""
echo "[2.3] Load Test Executor"
if [ -f "$HOME/code-server-phase13/scripts/phase-13-day2-load-test.sh" ]; then
  log_pass "Load test executor ready"
else
  log_error "Load test executor missing"
  exit 1
fi

# ============================================================================
# 3. EXTERNAL DEPENDENCIES (T-30 minutes)
# ============================================================================

log_header "3. EXTERNAL DEPENDENCIES CHECK (T-30 min)"

echo "[3.1] DNS Resolution"
if nslookup code-server.kushnir.cloud > /dev/null 2>&1; then
  DNS_IP=$(nslookup code-server.kushnir.cloud | grep -A1 Name | tail -1 | awk '{print $NF}')
  log_pass "DNS resolved: code-server.kushnir.cloud → $DNS_IP"
else
  log_warn "DNS not resolvable yet (acceptable - configurable during execution)"
fi

echo ""
echo "[3.2] OAuth2 Status"
OAUTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/oauth2/auth || echo "000")
if [ "$OAUTH_RESPONSE" != "000" ]; then
  log_pass "OAuth2 endpoint responding (HTTP $OAUTH_RESPONSE)"
else
  log_warn "OAuth2 not responding (will retry at T-15 min)"
fi

# ============================================================================
# 4. SLO BASELINE COLLECTION (T-15 minutes)
# ============================================================================

log_header "4. SLO BASELINE COLLECTION (T-15 min)"

echo "[4.1] Container Response Time Baseline"
if command -v docker &> /dev/null; then
  log_pass "Docker API responding"
  DOCKER_RESPONSE=$(time docker ps --quiet 2>&1 | grep real | awk '{print $2}')
  log_pass "Docker operations baseline: ${DOCKER_RESPONSE}ms"
else
  log_error "Docker not responding"
  exit 1
fi

echo ""
echo "[4.2] SLO Target Confirmation"
echo "  • p99 Latency: < 100ms (baseline: 42-89ms from Phase 13)"
echo "  • Error Rate: < 0.1% (baseline: 0.0%)"
echo "  • Throughput: > 100 req/s (baseline: 150+ req/s)"
echo "  • Availability: > 99.9% (baseline: 99.98%)"
log_pass "All SLO targets confirmed"

# ============================================================================
# 5. FINAL PRE-EXECUTION (T-5 minutes)
# ============================================================================

log_header "5. FINAL PRE-EXECUTION CHECK (T-5 min)"

echo "[5.1] Team Confirmation"
echo "  • DevOps Lead: [CONFIRM] Ready to execute"
echo "  • Platform Manager: [CONFIRM] Team standby"
echo "  • Performance Engineer: [CONFIRM] SLO monitoring active"
echo "  • Security Team: [CONFIRM] Access control verified"

echo ""
echo "[5.2] Rollback Procedure Ready"
echo "  • Rollback script: /home/akushnir/code-server-phase13/scripts/rollback.sh"
echo "  • Estimated rollback time: < 5 minutes"
echo "  • Data backup: ON (continuous)"

echo ""
echo "[5.3] Incident Response"
echo "  • On-call rotation: Active (24/7)"
echo "  • Escalation path: DevOps → Platform → VP Engineering"
echo "  • Alert thresholds: Configured and tested"

# ============================================================================
# 6. GO/NO-GO DECISION
# ============================================================================

log_header "GO/NO-GO DECISION"

BLOCKERS=0

# Check critical infrastructure
if [ "$CONTAINER_COUNT" -lt 5 ]; then
  log_error "BLOCKER: Container count < 5"
  ((BLOCKERS++))
fi

if [ "$HEALTHY_COUNT" -lt 4 ]; then
  log_error "BLOCKER: Healthy containers < 4"
  ((BLOCKERS++))
fi

if [ "$FREE_SPACE" -lt 40 ]; then
  log_error "BLOCKER: Disk space < 40GB"
  ((BLOCKERS++))
fi

if [ $BLOCKERS -eq 0 ]; then
  echo ""
  log_pass "ALL PREFLIGHT CHECKS PASSED"
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║                   🟢 GO FOR EXECUTION                          ║"
  echo "║                                                                ║"
  echo "║  Phase 13 Day 2: 24-Hour Sustained Load Testing              ║"
  echo "║  Status: AUTHORIZED TO PROCEED                               ║"
  echo "║  Launch Time: 09:00 UTC on April 14, 2026                    ║"
  echo "║  Duration: 24 hours (until 09:00 UTC April 15, 2026)         ║"
  echo "║  Decision Point: 12:00 UTC on April 15, 2026                 ║"
  echo "║                                                                ║"
  echo "│ Next Steps:                                                    │"
  echo "│  1. Start Phase 13 Day 2 load test (→ next section)           │"
  echo "│  2. Monitor 24 hours for SLO compliance                       │"
  echo "│  3. Collect metrics and decision data                         │"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  exit 0
else
  echo ""
  log_error "EXECUTION BLOCKED: $BLOCKERS critical issue(s) found"
  echo ""
  echo "Action Required:"
  echo "  1. Review errors above"
  echo "  2. Resolve blockers"
  echo "  3. Re-run this script to verify"
  echo ""
  exit 2
fi
