#!/usr/bin/env bash

# @file        scripts/load-testing/run-api-endpoint-load-test.sh
# @module      testing/load-testing
# @description Authenticated API endpoint load testing using k6
# @owner       Infrastructure
# @status      active

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
API_ENDPOINT="${API_ENDPOINT:-https://ide.kushnir.cloud/api/v1}"
TEST_RESOURCE="${TEST_RESOURCE:-/workspace}"
K6_SUMMARY_FILE="artifacts/load-test-api-endpoint-summary.json"
K6_DETAILED_FILE="artifacts/load-test-api-endpoint-detailed.json"
DRY_RUN="${DRY_RUN:-1}"

# Load test scenarios
SCENARIO="${1:-light}"  # light: 50 concurrent, moderate: 200 concurrent, stress: 500+ concurrent

echo -e "${YELLOW}API Endpoint Load Test${NC}"
echo "API Endpoint: $API_ENDPOINT$TEST_RESOURCE"
echo "Scenario: $SCENARIO"
echo "Dry Run Mode: $DRY_RUN"
echo ""

# Define scenario parameters
case "$SCENARIO" in
  light)
    VUS=10
    DURATION="30s"
    REQUEST_RATE=50
    ;;
  moderate)
    VUS=50
    DURATION="60s"
    REQUEST_RATE=200
    ;;
  stress)
    VUS=200
    DURATION="120s"
    REQUEST_RATE=500
    ;;
  *)
    echo -e "${RED}Unknown scenario: $SCENARIO${NC}"
    echo "Valid options: light, moderate, stress"
    exit 1
    ;;
esac

echo "Load Test Parameters:"
echo "  Virtual Users (VUS): $VUS"
echo "  Target Request Rate: $REQUEST_RATE reqs/sec"
echo "  Duration: $DURATION"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "${YELLOW}DRY-RUN MODE (no actual requests will be sent)${NC}"
  echo ""
  echo "To run actual load test, execute:"
  echo "  DRY_RUN=0 API_ENDPOINT=$API_ENDPOINT $0 $SCENARIO"
  echo ""
  exit 0
fi

# Create k6 test script
K6_SCRIPT="artifacts/k6-api-endpoint-test.js"
mkdir -p artifacts

cat > "$K6_SCRIPT" << 'EOFK6'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics
const apiErrors = new Rate('api_request_errors');
const apiLatency = new Trend('api_request_latency');
const authErrors = new Rate('api_auth_errors');
const rbacDenials = new Rate('api_rbac_denials');
const apiThroughput = new Counter('api_requests');
const concurrentRequests = new Gauge('api_concurrent_requests');

export const options = {
  vus: __VUS__,
  duration: '__DURATION__',
  thresholds: {
    'api_request_latency': ['p(95)<500'],      // 95% of requests < 500ms
    'api_request_errors': ['rate<0.05'],       // < 5% error rate
    'api_auth_errors': ['rate<0.01'],          // < 1% auth errors
  },
};

export default function () {
  concurrentRequests.add(1);
  
  // Prepare authorized request
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer test-jwt-token-vu-${__VU__}`,
    'X-User-ID': `test-user-${__VU__}`,
    'X-User-Role': __VU__ % 3 === 0 ? 'admin' : 'user',
  };
  
  // Test 1: GET workspace list
  const startGet = Date.now();
  const getRes = http.get(__API_ENDPOINT__ + __TEST_RESOURCE__, {
    headers: headers,
  });
  const getLatency = Date.now() - startGet;
  apiLatency.add(getLatency);
  
  check(getRes, {
    'GET successful': (r) => r.status === 200,
    'GET response has data': (r) => r.body.length > 0,
    'GET response time < 500ms': (r) => getLatency < 500,
  });
  
  if (getRes.status === 401) {
    authErrors.add(1);
  } else if (getRes.status === 403) {
    rbacDenials.add(1);
  } else if (getRes.status >= 400) {
    apiErrors.add(1);
  }
  
  // Test 2: POST create resource (10% of requests)
  if (__VU__ % 10 === 0) {
    const createPayload = {
      name: `test-resource-${__VU__}-${Date.now()}`,
      type: 'workspace',
      visibility: 'private',
    };
    
    const startPost = Date.now();
    const postRes = http.post(
      __API_ENDPOINT__ + __TEST_RESOURCE__,
      JSON.stringify(createPayload),
      { headers: headers }
    );
    const postLatency = Date.now() - startPost;
    apiLatency.add(postLatency);
    
    check(postRes, {
      'POST successful': (r) => r.status === 201,
      'POST response has id': (r) => {
        try {
          const body = JSON.parse(r.body);
          return body.id !== undefined;
        } catch {
          return false;
        }
      },
    });
    
    if (postRes.status >= 400) {
      apiErrors.add(1);
    }
  }
  
  // Test 3: Unauthorized request (should be denied)
  const unauthorizedRes = http.get(__API_ENDPOINT__ + __TEST_RESOURCE__, {
    headers: {
      'Content-Type': 'application/json',
      // No Authorization header
    },
  });
  
  check(unauthorizedRes, {
    'Unauthorized request denied': (r) => r.status === 401,
  });
  
  if (unauthorizedRes.status !== 401) {
    authErrors.add(1);
  }
  
  // Test 4: Insufficient permissions (regular user accessing admin resource)
  if (__VU__ % 5 === 0) {
    const regularUserHeaders = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer test-jwt-token-vu-${__VU__}`,
      'X-User-ID': `test-user-${__VU__}`,
      'X-User-Role': 'user',  // Regular user
    };
    
    const adminRes = http.get(
      __API_ENDPOINT__ + '/admin/stats',
      { headers: regularUserHeaders }
    );
    
    check(adminRes, {
      'Admin resource protected': (r) => r.status === 403,
    });
    
    if (adminRes.status === 200) {
      rbacDenials.add(1);  // Should have been denied
    }
  }
  
  apiThroughput.add(1);
  concurrentRequests.add(-1);
  
  sleep(__SLEEP_TIME__);
}
EOFK6

# Calculate sleep time to achieve target request rate
# Formula: sleep_time = (vus * duration_s) / target_rate - request_overhead
# Approximate request overhead: 10ms per request
SLEEP_TIME=$(echo "scale=3; (1 / ($REQUEST_RATE / $VUS))" | bc)

# Replace variables in k6 script
sed -i "s|__VUS__|$VUS|g" "$K6_SCRIPT"
sed -i "s|__DURATION__|$DURATION|g" "$K6_SCRIPT"
sed -i "s|__API_ENDPOINT__|'$API_ENDPOINT'|g" "$K6_SCRIPT"
sed -i "s|__TEST_RESOURCE__|'$TEST_RESOURCE'|g" "$K6_SCRIPT"
sed -i "s|__SLEEP_TIME__|$SLEEP_TIME|g" "$K6_SCRIPT"

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
    "total_requests": (.api_requests.value | round),
    "api_latency_avg_ms": (.api_request_latency.values.avg | round),
    "api_latency_p95_ms": (.api_request_latency.values.p95 | round),
    "api_latency_p99_ms": (.api_request_latency.values.p99 | round),
    "api_error_rate": (.api_request_errors.value * 100 | round),
    "auth_error_rate": (.api_auth_errors.value * 100 | round),
    "rbac_denial_rate": (.api_rbac_denials.value * 100 | round),
    "concurrent_peak": (.api_concurrent_requests.value | round)
  }' "$K6_SUMMARY_FILE" 2>/dev/null || echo "  (unable to parse summary)"
fi

echo ""
echo -e "${YELLOW}Recommendations:${NC}"
if jq -e '.metrics.api_request_latency.values.p95 > 500' "$K6_SUMMARY_FILE" 2>/dev/null; then
  echo "  - P95 latency > 500ms: Check API server resources and database query performance"
fi
if jq -e '.metrics.api_auth_errors.value > 0.01' "$K6_SUMMARY_FILE" 2>/dev/null; then
  echo "  - Auth error rate > 1%: Check OIDC issuer and token validation performance"
fi
if jq -e '.metrics.api_rbac_denials.value > 0.05' "$K6_SUMMARY_FILE" 2>/dev/null; then
  echo "  - RBAC denial rate unexpected: Check authorization policy implementation"
fi
