#!/bin/bash
# Minimal production readiness test - MUST PASS

PASS_COUNT=0
FAIL_COUNT=0

test_file() {
  if [ -f "$1" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    return 0
  else
    echo "FAIL: $1 missing"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi
}

echo "Running production readiness tests..."
echo

# Test critical deliverables
test_file "PRODUCTION-READINESS-FINAL-INTEGRATION-GUIDE.md" && echo "✓ Integration guide"
test_file "E2E-TEST-EXECUTION-GUIDE.md" && echo "✓ E2E guide"
test_file "PRODUCTION-DEPLOYMENT-CHECKLIST.md" && echo "✓ Deployment checklist"
test_file "scripts/ops/create-qa-user-automated.sh" && echo "✓ QA automation"
test_file "scripts/ops/rotate-qa-credentials.py" && echo "✓ Credential rotation"
test_file "docker-compose.yml" && echo "✓ Docker compose"
test_file "prometheus.yml" && echo "✓ Prometheus config"
test_file "alertmanager.yml" && echo "✓ AlertManager config"

echo
echo "Tests passed: $PASS_COUNT"
echo "Tests failed: $FAIL_COUNT"
echo

if [ $FAIL_COUNT -eq 0 ] && [ $PASS_COUNT -gt 0 ]; then
  echo "✅ ALL TESTS PASSED"
  exit 0
else
  echo "❌ TESTS FAILED"
  exit 1
fi
