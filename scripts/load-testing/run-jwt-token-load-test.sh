#!/usr/bin/env bash

# @file        scripts/load-testing/run-jwt-token-load-test.sh
# @module      testing/load-testing
# @description JWT token acquisition load testing using k6
# @owner       Infrastructure
# @status      active

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TOKEN_ENDPOINT="${TOKEN_ENDPOINT:-https://ide.kushnir.cloud/oauth2/token}"
CLIENT_ID="${CLIENT_ID:-code-server}"
CLIENT_SECRET="${CLIENT_SECRET:-test-secret}"
K6_SUMMARY_FILE="artifacts/load-test-jwt-token-summary.json"
K6_DETAILED_FILE="artifacts/load-test-jwt-token-detailed.json"
DRY_RUN="${DRY_RUN:-1}"

# Load test scenarios
SCENARIO_LIGHT="${1:-light}"  # light: 50 tokens/sec, moderate: 200 tokens/sec, stress: 500+ tokens/sec

echo -e "${YELLOW}JWT Token Acquisition Load Test${NC}"
echo "Token Endpoint: $TOKEN_ENDPOINT"
echo "Scenario: $SCENARIO_LIGHT"
echo "Dry Run Mode: $DRY_RUN"
echo ""

# Define scenario parameters
case "$SCENARIO_LIGHT" in
  light)
    VUS=5
    DURATION="30s"
    THINK_TIME=0.1
    ;;
  moderate)
    VUS=20
    DURATION="60s"
    THINK_TIME=0.05
    ;;
  stress)
    VUS=50
    DURATION="120s"
    THINK_TIME=0.01
    ;;
  *)
    echo -e "${RED}Unknown scenario: $SCENARIO_LIGHT${NC}"
    echo "Valid options: light, moderate, stress"
    exit 1
    ;;
esac

APPROX_TPS=$(echo "scale=0; $VUS / $THINK_TIME" | bc)
echo "Load Test Parameters:"
echo "  Virtual Users (VUS): $VUS"
echo "  Think Time (sec): $THINK_TIME"
echo "  Approx TPS: $APPROX_TPS"
echo "  Duration: $DURATION"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "${YELLOW}DRY-RUN MODE (no actual requests will be sent)${NC}"
  echo ""
  echo "To run actual load test, execute:"
  echo "  DRY_RUN=0 TOKEN_ENDPOINT=$TOKEN_ENDPOINT $0 $SCENARIO_LIGHT"
  echo ""
  exit 0
fi

# Create k6 test script
K6_SCRIPT="artifacts/k6-jwt-token-test.js"
mkdir -p artifacts

cat > "$K6_SCRIPT" << 'EOFK6'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics
const tokenAcquisitionFailures = new Rate('token_acquisition_failures');
const tokenAcquisitionDuration = new Trend('token_acquisition_duration');
const tokenCacheHitRate = new Rate('token_cache_hits');
const uniqueTokens = new Counter('unique_tokens');
const concurrentUsers = new Gauge('concurrent_users');

export const options = {
  vus: __VUS__,
  duration: '__DURATION__',
  thresholds: {
    'http_req_duration': ['p(95)<200'],  // 95% of requests < 200ms (cached) or < 500ms (fresh)
    'token_acquisition_failures': ['rate<0.05'],  // < 5% failure rate
  },
};

// Shared state for token caching simulation
const tokenCache = {};
let cacheHits = 0;
let cacheMisses = 0;

export default function () {
  concurrentUsers.add(1);
  
  const startTime = Date.now();
  
  // Attempt token acquisition
  const payload = {
    grant_type: 'client_credentials',
    client_id: '__CLIENT_ID__',
    client_secret: '__CLIENT_SECRET__',
  };
  
  const res = http.post(__TOKEN_ENDPOINT__, payload, {
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
  });
  
  const duration = Date.now() - startTime;
  tokenAcquisitionDuration.add(duration);
  
  // Check for cached token (simulated by fast response time)
  if (duration < 100) {
    tokenCacheHitRate.add(1);
    cacheHits++;
  } else {
    cacheMisses++;
  }
  
  // Verify response
  check(res, {
    'token acquired': (r) => r.status === 200,
    'response has access_token': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.access_token !== undefined;
      } catch {
        return false;
      }
    },
    'token type is Bearer': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.token_type === 'Bearer';
      } catch {
        return false;
      }
    },
    'token expiration set': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.expires_in > 0;
      } catch {
        return false;
      }
    },
  });
  
  // Track failures
  if (res.status >= 400) {
    tokenAcquisitionFailures.add(1);
  } else {
    try {
      const body = JSON.parse(res.body);
      uniqueTokens.add(1);
    } catch {}
  }
  
  sleep(__THINK_TIME__);
}
EOFK6

# Replace variables in k6 script
sed -i "s|__VUS__|$VUS|g" "$K6_SCRIPT"
sed -i "s|__DURATION__|$DURATION|g" "$K6_SCRIPT"
sed -i "s|__THINK_TIME__|$THINK_TIME|g" "$K6_SCRIPT"
sed -i "s|__CLIENT_ID__|$CLIENT_ID|g" "$K6_SCRIPT"
sed -i "s|__CLIENT_SECRET__|$CLIENT_SECRET|g" "$K6_SCRIPT"
sed -i "s|__TOKEN_ENDPOINT__|'$TOKEN_ENDPOINT'|g" "$K6_SCRIPT"

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
    "token_acq_duration_avg_ms": (.token_acquisition_duration.values.avg | round),
    "token_acq_duration_p95_ms": (.token_acquisition_duration.values.p95 | round),
    "token_acq_duration_p99_ms": (.token_acquisition_duration.values.p99 | round),
    "cache_hit_rate_percent": (.token_cache_hits.value * 100 | round),
    "token_acq_failure_rate": (.token_acquisition_failures.value * 100 | round),
    "unique_tokens_issued": (.unique_tokens.value | round),
    "concurrent_users": (.concurrent_users.value | round)
  }' "$K6_SUMMARY_FILE" 2>/dev/null || echo "  (unable to parse summary)"
fi

echo ""
echo -e "${YELLOW}Recommendations:${NC}"
if jq -e '.metrics.token_cache_hits.value < 0.8' "$K6_SUMMARY_FILE" 2>/dev/null; then
  echo "  - Cache hit rate < 80%: Consider increasing token TTL"
fi
if jq -e '.metrics.token_acquisition_duration.values.p95 > 500' "$K6_SUMMARY_FILE" 2>/dev/null; then
  echo "  - P95 latency > 500ms: Check OIDC issuer performance"
fi
