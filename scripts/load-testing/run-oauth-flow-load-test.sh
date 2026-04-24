#!/usr/bin/env bash

# @file        scripts/load-testing/run-oauth-flow-load-test.sh
# @module      testing/load-testing
# @description OAuth login flow load testing using k6
# @owner       Infrastructure
# @status      active

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${BASE_URL:-https://ide.kushnir.cloud}"
K6_SUMMARY_FILE="artifacts/load-test-oauth-flow-summary.json"
K6_DETAILED_FILE="artifacts/load-test-oauth-flow-detailed.json"
DRY_RUN="${DRY_RUN:-1}"

# Load test scenarios
SCENARIO_LIGHT="${1:-light}"  # light: 10 users, moderate: 50 users, stress: 200+ users

echo -e "${YELLOW}OAuth Flow Load Test${NC}"
echo "Base URL: $BASE_URL"
echo "Scenario: $SCENARIO_LIGHT"
echo "Dry Run Mode: $DRY_RUN"
echo ""

# Define scenario parameters
case "$SCENARIO_LIGHT" in
  light)
    VUS=10
    DURATION="30s"
    RPS=5
    ;;
  moderate)
    VUS=50
    DURATION="60s"
    RPS=25
    ;;
  stress)
    VUS=200
    DURATION="120s"
    RPS=100
    ;;
  *)
    echo -e "${RED}Unknown scenario: $SCENARIO_LIGHT${NC}"
    echo "Valid options: light, moderate, stress"
    exit 1
    ;;
esac

echo "Load Test Parameters:"
echo "  Virtual Users (VUS): $VUS"
echo "  Duration: $DURATION"
echo "  Target RPS: $RPS"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "${YELLOW}DRY-RUN MODE (no actual requests will be sent)${NC}"
  echo ""
  echo "To run actual load test, execute:"
  echo "  DRY_RUN=0 BASE_URL=$BASE_URL $0 $SCENARIO_LIGHT"
  echo ""
  exit 0
fi

# Create k6 test script
K6_SCRIPT="artifacts/k6-oauth-flow-test.js"
mkdir -p artifacts

cat > "$K6_SCRIPT" << 'EOFK6'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics
const loginFailureRate = new Rate('login_failures');
const loginDuration = new Trend('login_duration');
const redirectTime = new Trend('redirect_time');
const cookieSetCount = new Counter('cookies_set');
const concurrentUsers = new Gauge('concurrent_users');

export const options = {
  vus: __VUS__,
  duration: '__DURATION__',
  thresholds: {
    'http_req_duration': ['p(95)<500'],  // 95% of requests < 500ms
    'login_failures': ['rate<0.1'],       // < 10% failure rate
  },
};

export default function () {
  concurrentUsers.add(1);
  
  // Step 1: Navigate to login page
  let res = http.get(__BASE_URL__);
  check(res, {
    'login page loaded': (r) => r.status === 200,
  });
  
  // Step 2: Measure redirect to Google OAuth
  const startRedirect = Date.now();
  res = http.get(__BASE_URL__ + '/oauth2/start', {
    redirects: 0,
  });
  const redirectDuration = Date.now() - startRedirect;
  redirectTime.add(redirectDuration);
  
  check(res, {
    'redirect to OAuth initiated': (r) => r.status === 302 || r.status === 307,
  });
  
  // Step 3: Simulate successful OAuth callback
  const startLogin = Date.now();
  res = http.get(__BASE_URL__ + '/oauth2/callback?code=test-auth-code&state=test-state', {
    redirects: 0,
  });
  const loginDurationMs = Date.now() - startLogin;
  loginDuration.add(loginDurationMs);
  
  check(res, {
    'OAuth callback handled': (r) => r.status === 302 || r.status === 200,
  });
  
  if (res.cookies && res.cookies['code-server-jwt']) {
    cookieSetCount.add(1);
  }
  
  // Track failures
  if (res.status >= 400) {
    loginFailureRate.add(1);
  }
  
  sleep(1);
}
EOFK6

# Replace variables in k6 script
sed -i "s|__VUS__|$VUS|g" "$K6_SCRIPT"
sed -i "s|__DURATION__|$DURATION|g" "$K6_SCRIPT"
sed -i "s|__BASE_URL__|'$BASE_URL'|g" "$K6_SCRIPT"

echo -e "${GREEN}k6 test script created: $K6_SCRIPT${NC}"
echo ""

# Run k6 load test
echo -e "${YELLOW}Running k6 load test...${NC}"
k6 run \
  --out json="$K6_DETAILED_FILE" \
  --summary-export="$K6_SUMMARY_FILE" \
  "$K6_SCRIPT"

echo ""
echo -e "${GREEN}Load test complete!${NC}"
echo "Results:"
echo "  Summary: $K6_SUMMARY_FILE"
echo "  Detailed: $K6_DETAILED_FILE"
echo ""

# Parse and display summary
if [ -f "$K6_SUMMARY_FILE" ]; then
  echo "Test Summary:"
  jq '.metrics | {
    "requests_total": .http_reqs.value,
    "login_duration_avg": (.login_duration.values.avg | round),
    "login_duration_p95": (.login_duration.values.p95 | round),
    "login_duration_p99": (.login_duration.values.p99 | round),
    "redirect_time_avg": (.redirect_time.values.avg | round),
    "login_failure_rate": (.login_failures.value | . * 100 | round),
    "concurrent_users": (.concurrent_users.value | round)
  }' "$K6_SUMMARY_FILE" 2>/dev/null || echo "  (unable to parse summary)"
fi
