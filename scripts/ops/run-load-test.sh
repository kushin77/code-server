#!/bin/bash
# Automated load testing with Apache Bench
# Tests platform under load and generates performance reports

set -e
trap 'echo "❌ Load test failed"; exit 1' ERR

TEST_DIR="/var/logs/load-tests"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TARGET_URL="${1:-http://192.168.168.31:8080/health}"
CONCURRENT=${2:-50}
REQUESTS=${3:-10000}

mkdir -p "$TEST_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Load Testing - $TIMESTAMP                                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if ab is installed
if ! command -v ab &> /dev/null; then
  echo "Installing Apache Bench..."
  apt-get update >/dev/null
  apt-get install -y apache2-utils >/dev/null
fi

REPORT_FILE="$TEST_DIR/load-test_${TIMESTAMP}.txt"

echo "Load Test Configuration:"
echo "  URL: $TARGET_URL"
echo "  Concurrent requests: $CONCURRENT"
echo "  Total requests: $REQUESTS"
echo ""
echo "Testing in progress..."
echo ""

# Run load test
ab -n "$REQUESTS" -c "$CONCURRENT" -q -g "$TEST_DIR/load-test_${TIMESTAMP}.tsv" \
  -r "$TARGET_URL" 2>&1 | tee "$REPORT_FILE"

# Analyze results
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Load Test Results                                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Extract key metrics
{
  echo "Load Test Summary"
  echo "================="
  echo ""
  
  grep "Requests per second" "$REPORT_FILE" || echo "Requests/sec: (not available)"
  grep "Time per request" "$REPORT_FILE" | head -1 || echo "Time per request: (not available)"
  grep "Failed requests" "$REPORT_FILE" || echo "Failed requests: 0"
  
  echo ""
  echo "Performance Interpretation:"
  
  # Get throughput
  THROUGHPUT=$(grep "Requests per second" "$REPORT_FILE" | awk '{print $NF}' || echo "0")
  
  if (( $(echo "$THROUGHPUT > 1000" | bc -l 2>/dev/null) )); then
    echo "  ✅ Excellent throughput: $THROUGHPUT req/sec"
  elif (( $(echo "$THROUGHPUT > 100" | bc -l 2>/dev/null) )); then
    echo "  ⚠️  Moderate throughput: $THROUGHPUT req/sec"
  else
    echo "  ❌ Low throughput: $THROUGHPUT req/sec"
  fi
  
  # Get response time
  RESPONSE_TIME=$(grep "Time per request" "$REPORT_FILE" | head -1 | awk '{print $NF}' | sed 's/ms//' || echo "0")
  
  if (( $(echo "$RESPONSE_TIME < 100" | bc -l 2>/dev/null) )); then
    echo "  ✅ Excellent response time: ${RESPONSE_TIME}ms"
  elif (( $(echo "$RESPONSE_TIME < 500" | bc -l 2>/dev/null) )); then
    echo "  ⚠️  Acceptable response time: ${RESPONSE_TIME}ms"
  else
    echo "  ❌ Slow response time: ${RESPONSE_TIME}ms"
  fi
  
} | tee -a "$TEST_DIR/load-test_${TIMESTAMP}_summary.txt"

echo ""
echo "Detailed Report: $REPORT_FILE"
echo "Graph Data: $TEST_DIR/load-test_${TIMESTAMP}.tsv"
echo ""

# Performance recommendations
{
  echo ""
  echo "Performance Recommendations:"
  
  FAILED=$(grep "Failed requests" "$REPORT_FILE" | awk '{print $NF}' || echo "0")
  if [[ "$FAILED" != "0" ]]; then
    echo "  ⚠️  Found $FAILED failed requests - review server logs"
  fi
  
  if (( $(echo "$RESPONSE_TIME > 200" | bc -l 2>/dev/null) )); then
    echo "  • Implement caching to reduce response times"
    echo "  • Profile slow database queries"
    echo "  • Consider horizontal scaling"
  fi
  
  if (( $(echo "$THROUGHPUT < 100" | bc -l 2>/dev/null) )); then
    echo "  • Connection pooling may be too small"
    echo "  • Check for database connection bottlenecks"
    echo "  • Review kernel tuning parameters"
  fi
  
} | tee -a "$TEST_DIR/load-test_${TIMESTAMP}_summary.txt"

echo ""
echo "✅ Load test complete"
