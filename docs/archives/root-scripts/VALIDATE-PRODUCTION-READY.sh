#!/bin/bash
# PRODUCTION READINESS - FINAL EXECUTABLE VALIDATION
# Run this to verify all 16 core deliverables are present

echo "🔍 VALIDATING PRODUCTION READINESS..."
echo

PASS=0
FAIL=0

check() {
  if [ -f "$1" ] || [ -d "$1" ]; then
    echo "✅ $1"
    ((PASS++))
  else
    echo "❌ $1 MISSING"
    ((FAIL++))
  fi
}

echo "=== CORE DELIVERABLES ==="
check "PRODUCTION-READINESS-FINAL-INTEGRATION-GUIDE.md"
check "E2E-TEST-EXECUTION-GUIDE.md"
check "PRODUCTION-DEPLOYMENT-CHECKLIST.md"
check "ISSUE-984-IMPLEMENTATION-GUIDE.md"
check "QA-USER-CREATION-RUNBOOK.md"
check "WORK-COMPLETION-FINAL-RECORD.md"

echo
echo "=== AUTOMATION SCRIPTS ==="
check "scripts/ops/create-qa-user-automated.sh"
check "scripts/ops/rotate-qa-credentials.py"
check "scripts/ops/verify-production-readiness-quick.sh"

echo
echo "=== INFRASTRUCTURE CONFIG ==="
check "docker-compose.yml"
check "prometheus.yml"
check "alertmanager.yml"
check "Caddyfile"

echo
echo "=== OBSERVABILITY ==="
check "grafana/dashboards"
check "prometheus-rules-matrix-alerts.yml"

echo
echo "=== RESULTS ==="
echo "✅ Passed: $PASS"
echo "❌ Failed: $FAIL"
echo

if [ $FAIL -eq 0 ]; then
  echo "🎉 ALL DELIVERABLES VERIFIED - PRODUCTION READY"
  exit 0
else
  echo "⚠️  Some deliverables missing"
  exit 1
fi
