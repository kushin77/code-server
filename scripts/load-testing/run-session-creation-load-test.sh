#!/usr/bin/env bash

# @file        scripts/load-testing/run-session-creation-load-test.sh
# @module      testing/load-testing
# @description Session creation and management load testing using k6
# @owner       Infrastructure
# @status      active

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SESSION_ENDPOINT="${SESSION_ENDPOINT:-https://ide.kushnir.cloud/api/sessions}"
K6_SUMMARY_FILE="artifacts/load-test-session-summary.json"
K6_DETAILED_FILE="artifacts/load-test-session-detailed.json"
DRY_RUN="${DRY_RUN:-1}"

# Load test scenarios
SCENARIO="${1:-light}"  # light: 50 sessions, moderate: 200 sessions, stress: 500+ sessions

echo -e "${YELLOW}Session Creation Load Test${NC}"
echo "Session Endpoint: $SESSION_ENDPOINT"
echo "Scenario: $SCENARIO"
echo "Dry Run Mode: $DRY_RUN"
echo ""

# Define scenario parameters
case "$SCENARIO" in
  light)
    VUS=10
    DURATION="30s"
    ITERATIONS_PER_USER=5
    ;;
  moderate)
    VUS=50
    DURATION="60s"
    ITERATIONS_PER_USER=4
    ;;
  stress)
    VUS=200
    DURATION="120s"
    ITERATIONS_PER_USER=3
    ;;
  *)
    echo -e "${RED}Unknown scenario: $SCENARIO${NC}"
    echo "Valid options: light, moderate, stress"
    exit 1
    ;;
esac

TOTAL_SESSIONS=$((VUS * ITERATIONS_PER_USER))
echo "Load Test Parameters:"
echo "  Virtual Users (VUS): $VUS"
echo "  Iterations per User: $ITERATIONS_PER_USER"
echo "  Total Sessions: $TOTAL_SESSIONS"
echo "  Duration: $DURATION"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "${YELLOW}DRY-RUN MODE (no actual requests will be sent)${NC}"
  echo ""
  echo "To run actual load test, execute:"
  echo "  DRY_RUN=0 SESSION_ENDPOINT=$SESSION_ENDPOINT $0 $SCENARIO"
  echo ""
  exit 0
fi

# Create k6 test script
K6_SCRIPT="artifacts/k6-session-creation-test.js"
mkdir -p artifacts

cat > "$K6_SCRIPT" << 'EOFK6'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics
const sessionCreationFailures = new Rate('session_creation_failures');
const sessionCreationDuration = new Trend('session_creation_duration');
const sessionCleanupDuration = new Trend('session_cleanup_duration');
const sessionsCreated = new Counter('sessions_created');
const activeSessions = new Gauge('active_sessions');
const sessionErrors = new Rate('session_errors');

export const options = {
  vus: __VUS__,
  duration: '__DURATION__',
  thresholds: {
    'session_creation_duration': ['p(95)<200'],  // 95% session creation < 200ms
    'session_creation_failures': ['rate<0.05'],  // < 5% failure rate
  },
};

const sessionStore = {};
let sessionCounter = 0;

export default function () {
  activeSessions.add(1);
  
  // Session creation request
  const createPayload = {
    user_id: `test-user-${__VU__}-${sessionCounter}`,
    username: `testuser-${__VU__}`,
    email: `test-${__VU__}@example.com`,
    ttl: 3600,
  };
  
  const startCreation = Date.now();
  const createRes = http.post(__SESSION_ENDPOINT__, JSON.stringify(createPayload), {
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer test-token',
    },
  });
  const creationDuration = Date.now() - startCreation;
  sessionCreationDuration.add(creationDuration);
  
  let sessionId = null;
  check(createRes, {
    'session created': (r) => r.status === 201,
    'response has session_id': (r) => {
      try {
        const body = JSON.parse(r.body);
        sessionId = body.session_id;
        return sessionId !== undefined;
      } catch {
        return false;
      }
    },
    'session expiry set': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.expires_at !== undefined;
      } catch {
        return false;
      }
    },
  });
  
  if (createRes.status === 201) {
    sessionsCreated.add(1);
    sessionStore[sessionId] = {
      created: Date.now(),
      expires: Date.now() + 3600000,
    };
  } else {
    sessionCreationFailures.add(1);
    sessionErrors.add(1);
  }
  
  sleep(0.5);
  
  // Session validation request (if created)
  if (sessionId) {
    const validateRes = http.get(
      __SESSION_ENDPOINT__ + '/' + sessionId,
      {
        headers: {
          'Authorization': 'Bearer test-token',
        },
      }
    );
    
    check(validateRes, {
      'session validated': (r) => r.status === 200,
      'session not expired': (r) => {
        try {
          const body = JSON.parse(r.body);
          return body.expires_at > Date.now() / 1000;
        } catch {
          return false;
        }
      },
    });
  }
  
  sleep(0.5);
  
  // Session cleanup request
  if (sessionId) {
    const startCleanup = Date.now();
    const cleanupRes = http.delete(
      __SESSION_ENDPOINT__ + '/' + sessionId,
      {
        headers: {
          'Authorization': 'Bearer test-token',
        },
      }
    );
    const cleanupDuration = Date.now() - startCleanup;
    sessionCleanupDuration.add(cleanupDuration);
    
    check(cleanupRes, {
      'session deleted': (r) => r.status === 200 || r.status === 204,
    });
    
    delete sessionStore[sessionId];
  }
  
  sessionCounter++;
  sleep(1);
}
EOFK6

# Replace variables in k6 script
sed -i "s|__VUS__|$VUS|g" "$K6_SCRIPT"
sed -i "s|__DURATION__|$DURATION|g" "$K6_SCRIPT"
sed -i "s|__SESSION_ENDPOINT__|'$SESSION_ENDPOINT'|g" "$K6_SCRIPT"

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
    "sessions_created": (.sessions_created.value | round),
    "session_creation_duration_avg_ms": (.session_creation_duration.values.avg | round),
    "session_creation_duration_p95_ms": (.session_creation_duration.values.p95 | round),
    "session_cleanup_duration_avg_ms": (.session_cleanup_duration.values.avg | round),
    "session_creation_failure_rate": (.session_creation_failures.value * 100 | round),
    "session_error_rate": (.session_errors.value * 100 | round),
    "active_sessions_peak": (.active_sessions.value | round)
  }' "$K6_SUMMARY_FILE" 2>/dev/null || echo "  (unable to parse summary)"
fi

echo ""
echo -e "${YELLOW}Recommendations:${NC}"
if jq -e '.metrics.session_creation_duration.values.p95 > 200' "$K6_SUMMARY_FILE" 2>/dev/null; then
  echo "  - P95 latency > 200ms: Check session-broker resource allocation"
fi
if jq -e '.metrics.session_creation_failures.value > 0.05' "$K6_SUMMARY_FILE" 2>/dev/null; then
  echo "  - Failure rate > 5%: Check database connection pool and memory"
fi
