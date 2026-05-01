#!/bin/bash
# pre-deployment-verification.sh
# Run this on May 1 morning at 06:00 UTC to verify all systems ready
# Usage: ./pre-deployment-verification.sh

set -e
trap 'echo "[ERROR] Script failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Cleaning up temporary files..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="pre-deployment-verification-$TIMESTAMP.log"
REPORT_FILE="pre-deployment-report-$TIMESTAMP.txt"

echo "🔍 FINAL PRE-DEPLOYMENT VERIFICATION - May 1, 2026" | tee "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "================================================" | tee -a "$LOG_FILE"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

check_item() {
  local name=$1
  local cmd=$2
  local expected=$3
  
  echo -n "  [$((PASS+FAIL+WARN+1))] $name... " | tee -a "$LOG_FILE"
  
  if eval "$cmd" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PASS${NC}" | tee -a "$LOG_FILE"
    PASS+=1
  else
    echo -e "${RED}❌ FAIL${NC}" | tee -a "$LOG_FILE"
    FAIL+=1
  fi
}

check_warning() {
  local name=$1
  local cmd=$2
  
  echo -n "  [$((PASS+FAIL+WARN+1))] $name... " | tee -a "$LOG_FILE"
  
  if eval "$cmd" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  WARN${NC}" | tee -a "$LOG_FILE"
    WARN+=1
  else
    echo -e "${GREEN}✅ OK${NC}" | tee -a "$LOG_FILE"
  fi
}

echo "🔧 INFRASTRUCTURE CHECKS" | tee -a "$LOG_FILE"
echo "========================" | tee -a "$LOG_FILE"

check_item "Primary Host Reachable" "ping -c 1 192.168.168.31"
check_item "Secondary Host Reachable" "ping -c 1 192.168.168.42"
check_item "SSH Access to Primary" "ssh -o ConnectTimeout=5 akushnir@192.168.168.31 'echo test'"
check_item "Docker Service Running" "docker ps > /dev/null 2>&1"
check_item "Docker Compose Available" "docker-compose --version"

echo ""
echo "🏗️  SERVICES CHECK" | tee -a "$LOG_FILE"
echo "==================" | tee -a "$LOG_FILE"

check_item "Appsmith Service Running" "docker ps | grep -q appsmith"
check_item "Hermes Integration Running" "docker ps | grep -q hermes-integration"
check_item "PostgreSQL Running" "docker ps | grep -q postgres"
check_item "Redis Running" "docker ps | grep -q redis"
check_item "Code Server Running" "docker ps | grep -q code-server"
check_item "All Services Healthy" "docker ps --format '{{.Status}}' | grep -q 'Up (healthy)'"

echo ""
echo "🔗 CONNECTIVITY CHECK" | tee -a "$LOG_FILE"
echo "=====================" | tee -a "$LOG_FILE"

check_item "DNS Resolution" "nslookup kushnir.cloud"
check_item "Port 443 Open" "timeout 3 bash -c 'echo > /dev/tcp/173.77.179.148/443'"
check_item "External HTTP Response" "curl -I -k https://kushnir.cloud/ 2>&1 | grep -q 'HTTP'"
check_item "API Health Endpoint" "curl -k https://kushnir.cloud/api/hermes/health | grep -q 'healthy'"

echo ""
echo "💾 DATA INTEGRITY CHECK" | tee -a "$LOG_FILE"
echo "=======================" | tee -a "$LOG_FILE"

check_item "Database Responsive" "docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c 'SELECT 1;' > /dev/null"
check_item "Redis Responsive" "docker exec code-server-redis redis-cli ping | grep -q 'PONG'"
check_item "Backup System Working" "test -d backup-* || mkdir -p backup-test && rm -rf backup-test"

echo ""
echo "📊 PERFORMANCE BASELINE" | tee -a "$LOG_FILE"
echo "=======================" | tee -a "$LOG_FILE"

# Check resource usage
CPU=$(docker stats --no-stream --format '{{.CPUPerc}}' --all 2>/dev/null | grep -o '[0-9.]*' | awk '{sum+=$1} END {print int(sum)}')
MEM=$(docker stats --no-stream --format '{{.MemPerc}}' --all 2>/dev/null | grep -o '[0-9.]*' | awk '{sum+=$1} END {print int(sum)}')
DISK=$(df -h /home | awk 'NR==2 {print $5}' | sed 's/%//')

echo "  CPU Usage: $CPU% (target <60%)" | tee -a "$LOG_FILE"
if [ "$CPU" -lt 60 ]; then
  echo -e "    ${GREEN}✅ PASS${NC}" | tee -a "$LOG_FILE"
  PASS+=1
else
  echo -e "    ${RED}❌ FAIL${NC}" | tee -a "$LOG_FILE"
  FAIL+=1
fi

echo "  Memory Usage: $MEM% (target <70%)" | tee -a "$LOG_FILE"
if [ "$MEM" -lt 70 ]; then
  echo -e "    ${GREEN}✅ PASS${NC}" | tee -a "$LOG_FILE"
  PASS+=1
else
  echo -e "    ${RED}❌ FAIL${NC}" | tee -a "$LOG_FILE"
  FAIL+=1
fi

echo "  Disk Usage: $DISK% (target <70%)" | tee -a "$LOG_FILE"
if [ "$DISK" -lt 70 ]; then
  echo -e "    ${GREEN}✅ PASS${NC}" | tee -a "$LOG_FILE"
  PASS+=1
else
  echo -e "    ${RED}❌ FAIL${NC}" | tee -a "$LOG_FILE"
  FAIL+=1
fi

echo ""
echo "📋 TEAM READINESS CHECK" | tee -a "$LOG_FILE"
echo "=======================" | tee -a "$LOG_FILE"

check_item "Runbooks Available" "test -f DEVOPS_TEAM_RUNBOOK.md && test -f OPERATIONS_TEAM_RUNBOOK.md"
check_item "Deployment Checklist Available" "test -f MAY_1_GOLIVE_EXECUTION_CHECKLIST.md"
check_item "Training Curriculum Available" "test -f TEAM_TRAINING_CURRICULUM.md"
check_item "Monitoring Setup Guide Available" "test -f AUTOMATED_MONITORING_SETUP_GUIDE.md"

echo ""
echo "================================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Summary
TOTAL=$((PASS+FAIL+WARN))

{
  echo "PRE-DEPLOYMENT VERIFICATION REPORT"
  echo "Date: $(date)"
  echo "=================================="
  echo ""
  echo "RESULTS:"
  echo "--------"
  echo "✅ PASS:  $PASS"
  echo "❌ FAIL:  $FAIL"
  echo "⚠️  WARN: $WARN"
  echo "Total:   $TOTAL"
  echo ""
  
  if [ "$FAIL" -eq 0 ]; then
    echo "🎯 STATUS: READY FOR DEPLOYMENT ✅"
    echo ""
    echo "All critical checks passed. System is ready for May 1 go-live."
  else
    echo "⚠️  STATUS: ISSUES DETECTED"
    echo ""
    echo "Please resolve the $FAIL failed checks before proceeding."
  fi
} | tee -a "$REPORT_FILE"

# Final summary
echo ""
echo "Final Summary:" | tee -a "$LOG_FILE"
echo "  PASS:  $PASS checks"
echo "  FAIL:  $FAIL checks"
echo "  TOTAL: $TOTAL checks"
echo ""
echo "Reports saved to:"
echo "  - $LOG_FILE (detailed log)"
echo "  - $REPORT_FILE (summary report)"
echo ""
echo "Completed: $(date)" | tee -a "$LOG_FILE"

# Exit code
if [ "$FAIL" -eq 0 ]; then
  exit 0
else
  exit 1
fi
