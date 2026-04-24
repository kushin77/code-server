#!/usr/bin/env bash

# @file        scripts/load-testing/run-failover-load-test.sh
# @module      testing/load-testing
# @description Load test during primary-to-replica failover
# @owner       Infrastructure
# @status      active

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENDPOINT="${ENDPOINT:-https://ide.kushnir.cloud}"
K6_SUMMARY_FILE="artifacts/load-test-failover-summary.json"
K6_DETAILED_FILE="artifacts/load-test-failover-detailed.json"
DRY_RUN="${DRY_RUN:-1}"
FAILOVER_TRIGGER_DELAY="${FAILOVER_TRIGGER_DELAY:-15}"

# Load test scenarios
SCENARIO="${1:-light}"  # light: monitor failover, moderate: light load during failover

echo -e "${BLUE}Failover Load Test${NC}"
echo "Endpoint: $ENDPOINT"
echo "Scenario: $SCENARIO"
echo "Failover Trigger Delay: ${FAILOVER_TRIGGER_DELAY}s"
echo "Dry Run Mode: $DRY_RUN"
echo ""

# Define scenario parameters
case "$SCENARIO" in
  monitor)
    VUS=5
    DURATION="60s"
    DESCRIPTION="Monitor connectivity during failover"
    ;;
  light)
    VUS=10
    DURATION="60s"
    DESCRIPTION="Light load during failover"
    ;;
  moderate)
    VUS=50
    DURATION="120s"
    DESCRIPTION="Moderate load during failover"
    ;;
  *)
    echo -e "${RED}Unknown scenario: $SCENARIO${NC}"
    echo "Valid options: monitor, light, moderate"
    exit 1
    ;;
esac

echo "Load Test Parameters:"
echo "  Scenario: $DESCRIPTION"
echo "  Virtual Users (VUS): $VUS"
echo "  Duration: $DURATION"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "${YELLOW}DRY-RUN MODE${NC}"
  echo ""
  echo "IMPORTANT: Before running actual failover test:"
  echo "1. Verify primary and replica are both healthy"
  echo "2. Have backup/restore procedures ready"
  echo "3. Monitor infrastructure dashboards during test"
  echo "4. Be ready to abort test if issues arise"
  echo ""
  echo "To run actual failover test, execute:"
  echo "  DRY_RUN=0 FAILOVER_TRIGGER_DELAY=30 $0 $SCENARIO"
  echo ""
  exit 0
fi

# Create k6 test script
K6_SCRIPT="artifacts/k6-failover-test.js"
mkdir -p artifacts

cat > "$K6_SCRIPT" << 'EOFK6'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics
const requestErrors = new Rate('failover_request_errors');
const requestLatency = new Trend('failover_request_latency');
const failoverDetectionTime = new Trend('failover_detection_time');
const errorAfterFailover = new Counter('errors_after_failover');
const successAfterFailover = new Counter('success_after_failover');
const requestsBeforeFailover = new Counter('requests_before_failover');
const requestsAfterFailover = new Counter('requests_after_failover');
const concurrentRequests = new Gauge('failover_concurrent_requests');

const FAILOVER_DETECTION_WINDOW = __FAILOVER_TRIGGER_DELAY__ * 1000 + 10000;  // +10s buffer
const testStartTime = Date.now();

export const options = {
  vus: __VUS__,
  duration: '__DURATION__',
  thresholds: {
    'failover_request_latency': ['p(95)<1000'],    // During failover, allow up to 1s
    'failover_request_errors': ['rate<0.15'],      // Allow up to 15% errors during failover window
  },
};

export default function () {
  concurrentRequests.add(1);
  
  const currentTime = Date.now();
  const timeFromStart = currentTime - testStartTime;
  const isFailoverWindow = timeFromStart > FAILOVER_DETECTION_WINDOW - 5000 && timeFromStart < FAILOVER_DETECTION_WINDOW + 10000;
  
  // Prepare request
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer test-jwt-token-vu-${__VU__}`,
  };
  
  // Make health check request
  const startReq = Date.now();
  const res = http.get(__ENDPOINT__ + '/health', {
    headers: headers,
  });
  const latency = Date.now() - startReq;
  requestLatency.add(latency);
  
  // Categorize request
  if (timeFromStart < FAILOVER_DETECTION_WINDOW) {
    requestsBeforeFailover.add(1);
  } else {
    requestsAfterFailover.add(1);
  }
  
  // Check response
  check(res, {
    'request succeeded': (r) => r.status === 200,
    'health check passed': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.status === 'healthy';
      } catch {
        return false;
      }
    },
  });
  
  if (res.status >= 400) {
    requestErrors.add(1);
    if (isFailoverWindow) {
      errorAfterFailover.add(1);
    }
  } else {
    if (isFailoverWindow) {
      successAfterFailover.add(1);
    }
  }
  
  // If we detect transition, measure failover detection time
  if (isFailoverWindow && res.status === 200) {
    const detectionTime = timeFromStart - FAILOVER_DETECTION_WINDOW;
    if (detectionTime > 0 && detectionTime < 10000) {
      failoverDetectionTime.add(detectionTime);
    }
  }
  
  concurrentRequests.add(-1);
  sleep(__REQUEST_INTERVAL__);
}
EOFK6

# Calculate request interval based on desired load
REQUEST_INTERVAL=$(echo "scale=2; 1 / ($VUS * 2)" | bc)

# Replace variables in k6 script
sed -i "s|__VUS__|$VUS|g" "$K6_SCRIPT"
sed -i "s|__DURATION__|$DURATION|g" "$K6_SCRIPT"
sed -i "s|__ENDPOINT__|'$ENDPOINT'|g" "$K6_SCRIPT"
sed -i "s|__FAILOVER_TRIGGER_DELAY__|$FAILOVER_TRIGGER_DELAY|g" "$K6_SCRIPT"
sed -i "s|__REQUEST_INTERVAL__|$REQUEST_INTERVAL|g" "$K6_SCRIPT"

echo -e "${GREEN}k6 test script created: $K6_SCRIPT${NC}"
echo ""

# Display failover instructions
echo -e "${YELLOW}Failover Test Instructions:${NC}"
echo ""
echo "1. k6 test will start immediately and run for $DURATION"
echo "2. Test will continue for approximately ${FAILOVER_TRIGGER_DELAY}s before triggering failover"
echo "3. SSH to primary host and execute failover trigger:"
echo ""
echo "   # On primary host (192.168.168.31):"
echo "   docker stop caddy-primary  # Simulate primary failure"
echo ""
echo "4. Test will continue and measure:"
echo "   - Request latency before failover"
echo "   - Error rate during failover"
echo "   - Failover detection time"
echo "   - Request latency after failover"
echo "   - Request success rate post-failover"
echo ""
echo "5. After test completes, manually restore primary:"
echo "   docker start caddy-primary"
echo ""

# Confirm before proceeding
echo -e "${BLUE}Ready to start failover load test?${NC}"
echo "IMPORTANT: You must manually trigger failover when prompted!"
echo ""

read -p "Press Enter to start test (or Ctrl+C to cancel)..." || exit 1

# Run k6 load test
echo -e "${YELLOW}Starting k6 load test...${NC}"
echo "Failover trigger window: ${FAILOVER_TRIGGER_DELAY}s to $((FAILOVER_TRIGGER_DELAY + 15))s"
echo ""

k6 run \
  --out json="$K6_DETAILED_FILE" \
  --summary-export="$K6_SUMMARY_FILE" \
  "$K6_SCRIPT" &

TEST_PID=$!

# After delay, prompt for failover trigger
sleep "$FAILOVER_TRIGGER_DELAY"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            TRIGGER FAILOVER NOW                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Execute on primary host (192.168.168.31):"
echo "  docker stop caddy-primary"
echo ""
echo "Press Enter after triggering failover..."
read

wait $TEST_PID

echo ""
echo -e "${GREEN}Load test complete!${NC}"
echo "Results:"
echo "  Summary: $K6_SUMMARY_FILE"
echo "  Detailed: $K6_DETAILED_FILE"
echo ""

# Parse and display summary
if [ -f "$K6_SUMMARY_FILE" ]; then
  echo "Failover Test Summary:"
  jq '.metrics | {
    "requests_before_failover": (.requests_before_failover.value | round),
    "requests_after_failover": (.requests_after_failover.value | round),
    "latency_avg_ms": (.failover_request_latency.values.avg | round),
    "latency_p95_ms": (.failover_request_latency.values.p95 | round),
    "latency_max_ms": (.failover_request_latency.values.max | round),
    "error_rate_before": "N/A",
    "error_rate_after": (.errors_after_failover.value | . / (.errors_after_failover.value + .success_after_failover.value) * 100 | round),
    "failover_detection_time_ms": (.failover_detection_time.values.min | round),
    "total_errors": (.failover_request_errors.value | round)
  }' "$K6_SUMMARY_FILE" 2>/dev/null || echo "  (unable to parse summary)"
fi

echo ""
echo -e "${YELLOW}Failover Test Analysis:${NC}"
echo ""
echo "Key Metrics to Review:"
echo "1. Failover Detection Time: < 5 seconds is ideal"
echo "2. Error Rate During Failover: < 20% is acceptable"
echo "3. P95 Latency Post-Failover: < 1 second"
echo "4. Success Rate Recovery: Should reach > 99% within 30s"
echo ""

echo -e "${BLUE}Next Steps:${NC}"
echo "1. Restore primary host: docker start caddy-primary"
echo "2. Verify both primary and replica are healthy"
echo "3. Review detailed metrics in: $K6_DETAILED_FILE"
echo "4. Document failover RTO (Recovery Time Objective)"
echo "5. Compare with infrastructure targets"
