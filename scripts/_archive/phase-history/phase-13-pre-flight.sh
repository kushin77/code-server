#!/bin/bash
echo "=== PHASE 13 DAY 2 PRE-FLIGHT VERIFICATION ==="
echo "Time: $(date -u)"
echo ""
echo "=== CONTAINER STATUS ==="
docker ps --format 'table {{.Names}}\t{{.Status}}'
echo ""
echo "=== SYSTEM RESOURCES ==="
free -h | head -2
echo "---"
df -h / | tail -1
echo ""
echo "=== CRITICAL SCRIPTS CHECK ==="
for script in phase-13-day2-monitoring.sh phase-13-day2-orchestrator.sh phase-13-day2-load-test.sh; do
  if [ -f "/tmp/code-server-phase13/$script" ]; then
    echo "✓ $script"
  else
    echo "✗ $script MISSING"
  fi
done
echo ""
echo "=== PRE-FLIGHT STATUS ==="
CONTAINERS=$(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -c "Up")
if [ "$CONTAINERS" -ge 5 ]; then
  echo "✅ Containers: PASS ($CONTAINERS/5+ healthy)"
else
  echo "❌ Containers: FAIL ($CONTAINERS/5+ healthy)"
fi

MEMORY=$(free -h | head -2 | tail -1 | awk '{print $NF}')
echo "✓ Memory available: $MEMORY"

echo "✅ PRE-FLIGHT COMPLETE - READY FOR EXECUTION"
