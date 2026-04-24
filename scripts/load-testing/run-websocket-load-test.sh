#!/usr/bin/env bash

# @file        scripts/load-testing/run-websocket-load-test.sh
# @module      testing/load-testing
# @description WebSocket connection load testing using k6
# @owner       Infrastructure
# @status      active

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
WS_ENDPOINT="${WS_ENDPOINT:-wss://ide.kushnir.cloud/ws}"
K6_SUMMARY_FILE="artifacts/load-test-websocket-summary.json"
K6_DETAILED_FILE="artifacts/load-test-websocket-detailed.json"
DRY_RUN="${DRY_RUN:-1}"

# Load test scenarios
SCENARIO_LIGHT="${1:-light}"  # light: 10 concurrent, moderate: 50 concurrent, stress: 200+ concurrent

echo -e "${YELLOW}WebSocket Connection Load Test${NC}"
echo "WebSocket Endpoint: $WS_ENDPOINT"
echo "Scenario: $SCENARIO_LIGHT"
echo "Dry Run Mode: $DRY_RUN"
echo ""

# Define scenario parameters
case "$SCENARIO_LIGHT" in
  light)
    VUS=10
    CONNECTIONS_PER_USER=1
    MESSAGE_RATE=1
    DURATION="30s"
    ;;
  moderate)
    VUS=50
    CONNECTIONS_PER_USER=2
    MESSAGE_RATE=5
    DURATION="60s"
    ;;
  stress)
    VUS=200
    CONNECTIONS_PER_USER=3
    MESSAGE_RATE=10
    DURATION="120s"
    ;;
  *)
    echo -e "${RED}Unknown scenario: $SCENARIO_LIGHT${NC}"
    echo "Valid options: light, moderate, stress"
    exit 1
    ;;
esac

TOTAL_CONNECTIONS=$((VUS * CONNECTIONS_PER_USER))
echo "Load Test Parameters:"
echo "  Virtual Users (VUS): $VUS"
echo "  Connections per User: $CONNECTIONS_PER_USER"
echo "  Total Connections: $TOTAL_CONNECTIONS"
echo "  Message Rate (msgs/sec per connection): $MESSAGE_RATE"
echo "  Duration: $DURATION"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "${YELLOW}DRY-RUN MODE (no actual connections will be made)${NC}"
  echo ""
  echo "To run actual load test, execute:"
  echo "  DRY_RUN=0 WS_ENDPOINT=$WS_ENDPOINT $0 $SCENARIO_LIGHT"
  echo ""
  exit 0
fi

# Create k6 test script
K6_SCRIPT="artifacts/k6-websocket-test.js"
mkdir -p artifacts

cat > "$K6_SCRIPT" << 'EOFK6'
import ws from 'k6/ws';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics
const connectionFailures = new Rate('websocket_connection_failures');
const connectionDuration = new Trend('websocket_connection_duration');
const messageLatency = new Trend('websocket_message_latency');
const messagesReceived = new Counter('websocket_messages_received');
const activeConnections = new Gauge('websocket_active_connections');
const messageErrors = new Rate('websocket_message_errors');

export const options = {
  vus: __VUS__,
  duration: '__DURATION__',
  thresholds: {
    'websocket_connection_duration': ['p(95)<500'],  // 95% of connections < 500ms
    'websocket_message_latency': ['p(95)<100'],      // 95% of messages < 100ms
    'websocket_connection_failures': ['rate<0.05'],  // < 5% connection failures
  },
};

export default function () {
  const startConnect = Date.now();
  
  ws.connect(__WS_ENDPOINT__, function (socket) {
    activeConnections.add(1);
    
    const connectionTime = Date.now() - startConnect;
    connectionDuration.add(connectionTime);
    
    // Handle incoming messages
    socket.on('message', function (msg) {
      check(msg, {
        'message received': (m) => m !== null,
        'message not empty': (m) => m.length > 0,
      });
      
      messagesReceived.add(1);
    });
    
    socket.on('open', function () {
      check(true, {
        'websocket connected': () => true,
      });
      
      // Send messages at specified rate
      for (let i = 0; i < __MESSAGE_RATE__; i++) {
        const startMessage = Date.now();
        const msg = {
          type: 'ping',
          timestamp: new Date().toISOString(),
          sequence: i,
        };
        
        try {
          socket.send(JSON.stringify(msg));
          messageLatency.add(Date.now() - startMessage);
        } catch (e) {
          messageErrors.add(1);
        }
        
        sleep(1 / __MESSAGE_RATE__);  // Spread messages across 1 second
      }
    });
    
    socket.on('error', function (e) {
      connectionFailures.add(1);
      console.error('WebSocket error: ' + e);
    });
    
    // Hold connection open for connection duration
    socket.setTimeout(function () {
      socket.close();
    }, __CONNECTION_DURATION__);
    
  }, function (err) {
    connectionFailures.add(1);
    console.error('WebSocket connection error: ' + err);
  });
  
  sleep(1);
}
EOFK6

# Calculate connection duration (in milliseconds)
# For "light": 30s test, connections stay open for 20s
# For "moderate": 60s test, connections stay open for 45s
# For "stress": 120s test, connections stay open for 90s
case "$SCENARIO_LIGHT" in
  light)
    CONNECTION_DURATION_MS=20000
    ;;
  moderate)
    CONNECTION_DURATION_MS=45000
    ;;
  stress)
    CONNECTION_DURATION_MS=90000
    ;;
esac

# Replace variables in k6 script
sed -i "s|__VUS__|$VUS|g" "$K6_SCRIPT"
sed -i "s|__DURATION__|$DURATION|g" "$K6_SCRIPT"
sed -i "s|__MESSAGE_RATE__|$MESSAGE_RATE|g" "$K6_SCRIPT"
sed -i "s|__CONNECTION_DURATION__|$CONNECTION_DURATION_MS|g" "$K6_SCRIPT"
sed -i "s|__WS_ENDPOINT__|'$WS_ENDPOINT'|g" "$K6_SCRIPT"

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
    "connection_duration_avg_ms": (.websocket_connection_duration.values.avg | round),
    "connection_duration_p95_ms": (.websocket_connection_duration.values.p95 | round),
    "connection_failure_rate": (.websocket_connection_failures.value * 100 | round),
    "messages_sent": (.websocket_messages_sent.value | round),
    "messages_received": (.websocket_messages_received.value | round),
    "message_latency_avg_ms": (.websocket_message_latency.values.avg | round),
    "message_latency_p95_ms": (.websocket_message_latency.values.p95 | round),
    "message_error_rate": (.websocket_message_errors.value * 100 | round),
    "active_connections_peak": (.websocket_active_connections.value | round)
  }' "$K6_SUMMARY_FILE" 2>/dev/null || echo "  (unable to parse summary)"
fi

echo ""
echo -e "${YELLOW}Recommendations:${NC}"
if jq -e '.metrics.websocket_connection_failures.value > 0.05' "$K6_SUMMARY_FILE" 2>/dev/null; then
  echo "  - Connection failure rate > 5%: Check WebSocket server capacity"
fi
if jq -e '.metrics.websocket_message_latency.values.p95 > 100' "$K6_SUMMARY_FILE" 2>/dev/null; then
  echo "  - P95 message latency > 100ms: Check network and server resources"
fi
