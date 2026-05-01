#!/bin/bash
# post-deployment-verification.sh
# Run this after deployment (09:00-10:00 UTC) to verify production is working
# Usage: ./post-deployment-verification.sh

set -e
trap 'echo "[ERROR] Verification failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Post-deployment verification complete"; true' EXIT
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="post-deployment-verification-$TIMESTAMP.log"

echo "🚀 POST-DEPLOYMENT VERIFICATION - May 1, 2026" | tee "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "=================================================" | tee -a "$LOG_FILE"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

test_endpoint() {
  local name=$1
  local url=$2
  local expect=$3
  
  echo -n "  Testing: $name... " | tee -a "$LOG_FILE"
  
  response=$(curl -s -k "$url" 2>/dev/null)
  
  if echo "$response" | grep -q "$expect"; then
    echo -e "${GREEN}✅ PASS${NC}" | tee -a "$LOG_FILE"
    ((PASS++))
  else
    echo -e "${RED}❌ FAIL${NC}" | tee -a "$LOG_FILE"
    echo "    Response: $response" | tee -a "$LOG_FILE"
    ((FAIL++))
  fi
}

echo "🌐 EXTERNAL CONNECTIVITY" | tee -a "$LOG_FILE"
echo "========================" | tee -a "$LOG_FILE"

test_endpoint "Home Page" "https://kushnir.cloud/" "html"
test_endpoint "API Health" "https://kushnir.cloud/api/hermes/health" "healthy"
test_endpoint "Appsmith Dashboard" "https://kushnir.cloud/" "appsmith"

echo ""
echo "🔗 INTERNAL SERVICES" | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"

echo -n "  Docker Services: " | tee -a "$LOG_FILE"
services=$(docker ps --format 'table {{.Names}}' | wc -l)
if [ "$services" -ge 5 ]; then
  echo -e "${GREEN}✅ $services services running${NC}" | tee -a "$LOG_FILE"
  ((PASS++))
else
  echo -e "${RED}❌ Only $services services running (expect 5+)${NC}" | tee -a "$LOG_FILE"
  ((FAIL++))
fi

echo -n "  Database: " | tee -a "$LOG_FILE"
if docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT 1;" > /dev/null 2>&1; then
  echo -e "${GREEN}✅ Responsive${NC}" | tee -a "$LOG_FILE"
  ((PASS++))
else
  echo -e "${RED}❌ Not responsive${NC}" | tee -a "$LOG_FILE"
  ((FAIL++))
fi

echo -n "  Redis: " | tee -a "$LOG_FILE"
if docker exec code-server-redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
  echo -e "${GREEN}✅ Responsive${NC}" | tee -a "$LOG_FILE"
  ((PASS++))
else
  echo -e "${RED}❌ Not responsive${NC}" | tee -a "$LOG_FILE"
  ((FAIL++))
fi

echo ""
echo "📊 RESOURCE STATUS" | tee -a "$LOG_FILE"
echo "==================" | tee -a "$LOG_FILE"

cpu=$(docker stats --no-stream --format '{{.CPUPerc}}' --all 2>/dev/null | grep -o '[0-9.]*' | awk '{sum+=$1} END {print int(sum)}')
mem=$(docker stats --no-stream --format '{{.MemPerc}}' --all 2>/dev/null | grep -o '[0-9.]*' | awk '{sum+=$1} END {print int(sum)}')
disk=$(df -h /home | awk 'NR==2 {print $5}' | sed 's/%//')

echo "  CPU: $cpu% (target <60%)" | tee -a "$LOG_FILE"
if [ "$cpu" -lt 60 ]; then
  echo -e "    ${GREEN}✅ OK${NC}" | tee -a "$LOG_FILE"
  ((PASS++))
else
  echo -e "    ${YELLOW}⚠️  High${NC}" | tee -a "$LOG_FILE"
fi

echo "  Memory: $mem% (target <70%)" | tee -a "$LOG_FILE"
if [ "$mem" -lt 70 ]; then
  echo -e "    ${GREEN}✅ OK${NC}" | tee -a "$LOG_FILE"
  ((PASS++))
else
  echo -e "    ${YELLOW}⚠️  High${NC}" | tee -a "$LOG_FILE"
fi

echo "  Disk: $disk% (target <70%)" | tee -a "$LOG_FILE"
if [ "$disk" -lt 70 ]; then
  echo -e "    ${GREEN}✅ OK${NC}" | tee -a "$LOG_FILE"
  ((PASS++))
else
  echo -e "    ${YELLOW}⚠️  High${NC}" | tee -a "$LOG_FILE"
fi

echo ""
echo "=================================================" | tee -a "$LOG_FILE"
TOTAL=$((PASS+FAIL))

{
  echo ""
  echo "POST-DEPLOYMENT VERIFICATION SUMMARY"
  echo "===================================="
  echo "✅ PASS: $PASS"
  echo "❌ FAIL: $FAIL"
  echo "Total:   $TOTAL"
  echo ""
  
  if [ "$FAIL" -eq 0 ]; then
    echo "🎉 STATUS: DEPLOYMENT SUCCESSFUL ✅"
    echo ""
    echo "Production is operational and all systems are healthy."
  else
    echo "⚠️  STATUS: ISSUES DETECTED"
    echo ""
    echo "Please investigate the $FAIL failed checks."
  fi
  
  echo ""
  echo "Next Steps:"
  echo "1. Monitor SLA targets for 24 hours"
  echo "2. Proceed with operational handoff (May 2)"
  echo "3. Follow OPERATIONAL_TRANSITION_PLAN_MAY_2_3.md"
} | tee -a "$LOG_FILE"

echo ""
echo "Log saved: $LOG_FILE"
echo "Completed: $(date)"

if [ "$FAIL" -eq 0 ]; then
  exit 0
else
  exit 1
fi
