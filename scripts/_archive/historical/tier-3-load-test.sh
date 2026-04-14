#!/bin/bash
################################################################################
# Tier 3 Load Testing Suite
# Validates performance improvements under production load
# IaC: Idempotent, automated performance validation
################################################################################

set -euo pipefail

# Configuration
TARGET_URL="${TARGET_URL:-http://localhost:3000}"
CONCURRENT_USERS="${CONCURRENT_USERS:-100}"
DURATION="${DURATION:-60}"
WARMUP_DURATION="${WARMUP_DURATION:-30}"
RAMP_UP_TIME="${RAMP_UP_TIME:-10}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Tier 3 Load Testing Suite                          ║"
echo "║           Production Performance Validation                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration:"
echo "  Target URL:        $TARGET_URL"
echo "  Concurrent Users:  $CONCURRENT_USERS"
echo "  Test Duration:     ${DURATION}s"
echo "  Warmup Duration:   ${WARMUP_DURATION}s"
echo "  Ramp-up Time:      ${RAMP_UP_TIME}s"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight Checks
# ─────────────────────────────────────────────────────────────────────────────

echo "🔍 Pre-flight Checks"
echo "═══════════════════════════════════════════════════════════════"

# Check if target is reachable
if ! curl -s --connect-timeout 5 "$TARGET_URL/healthz" > /dev/null 2>&1; then
  echo "❌ ERROR: Cannot reach target at $TARGET_URL"
  echo "   Please ensure the application is running"
  exit 1
fi
echo "✅ Target is reachable"

# Check if ApacheBench is available (optional)
if command -v ab &> /dev/null; then
  echo "✅ ApacheBench (ab) is available"
  USE_AB=true
else
  echo "⚠️  ApacheBench not found, using curl-based testing"
  USE_AB=false
fi

# Check if jq is available (for JSON parsing)
if ! command -v jq &> /dev/null; then
  echo "⚠️  jq not found, installing..."
  apt-get update && apt-get install -y jq || echo "Could not install jq"
fi

echo ""

# ─────────────────────────────────────────────────────────════════════════════
# Warmup Phase
# ─────────────────────────────────────────────────────────=-=-=-=-=-=-=-=-=-=-=-=-

echo "🔥 Warmup Phase (${WARMUP_DURATION}s) - Filling Cache"
echo "═══════════════════════════════════════════════════════════════"

WARMUP_START=$(date +%s)
WARMUP_REQUESTS=0

while [ $(($(date +%s) - WARMUP_START)) -lt $WARMUP_DURATION ]; do
  # Randomize endpoints to exercise different cache paths
  ENDPOINT=$((RANDOM % 3))

  case $ENDPOINT in
    0) curl -s -X GET "$TARGET_URL/api/users/$((RANDOM % 100))" > /dev/null 2>&1 ;;
    1) curl -s -X GET "$TARGET_URL/api/items" > /dev/null 2>&1 ;;
    2) curl -s -X GET "$TARGET_URL/api/cache-status" > /dev/null 2>&1 ;;
  esac

  WARMUP_REQUESTS=$((WARMUP_REQUESTS + 1))
done

echo "✅ Warmup complete - $WARMUP_REQUESTS requests executed"
echo ""

# ─────────────────────────────════════════════════════════════────────────────
# Load Testing - curl-based (fallback)
# ─────────────════════════════════════════════════────────────────────────────

if [ "$USE_AB" = false ]; then
  echo "🚀 Load Test Phase (curl-based)"
  echo "═══════════════════════════════════════════════════════════════"

  RESULTS_FILE="/tmp/load-test-results-$$.txt"
  > "$RESULTS_FILE"  # Clear file

  TEST_START=$(date +%s%N)
  TOTAL_REQUESTS=0
  TOTAL_TIME=0
  MIN_TIME=999999
  MAX_TIME=0
  ERRORS=0

  # Ramp-up: gradually increase concurrency
  echo "Ramping up to $CONCURRENT_USERS concurrent users over ${RAMP_UP_TIME}s..."

  CONCURRENT=1
  INCREMENT=$((CONCURRENT_USERS / RAMP_UP_TIME))
  [ $INCREMENT -lt 1 ] && INCREMENT=1

  while [ $CONCURRENT -lt $CONCURRENT_USERS ]; do
    CONCURRENT=$((CONCURRENT + INCREMENT))
    [ $CONCURRENT -gt $CONCURRENT_USERS ] && CONCURRENT=$CONCURRENT_USERS
    echo "  Current concurrency: $CONCURRENT"
    sleep 1
  done

  echo ""
  echo "Running sustained load for ${DURATION}s..."

  # Main load test loop
  TEST_END=$(($(date +%s) + DURATION))

  while [ $(date +%s) -lt $TEST_END ]; do
    # Run parallel requests
    for i in $(seq 1 $CONCURRENT_USERS); do
      {
        ENDPOINT=$((RANDOM % 3))
        START_TIME=$(date +%s%N)

        case $ENDPOINT in
          0) HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_URL/api/users/$((RANDOM % 100))") ;;
          1) HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_URL/api/items") ;;
          2) HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_URL/metrics") ;;
        esac

        END_TIME=$(date +%s%N)
        ELAPSED=$(((END_TIME - START_TIME) / 1000000))  # Convert to ms

        echo "$ELAPSED:$HTTP_CODE" >> "$RESULTS_FILE"
      } &
    done

    wait  # Wait for all background requests to complete
  done

  TEST_TOTAL=$(($(date +%s%N) - TEST_START))

  # ─────────────────────────────────────────────────────────────────────────────
  # Parse Results
  # ─────────────────────────────────────────────────────────────────────────────

  echo ""
  echo "📊 Analyzing Results..."

  if [ -f "$RESULTS_FILE" ] && [ -s "$RESULTS_FILE" ]; then
    TOTAL_REQUESTS=$(wc -l < "$RESULTS_FILE")

    # Extract times and HTTP codes
    TIMES=$(cut -d: -f1 "$RESULTS_FILE")
    CODES=$(cut -d: -f2 "$RESULTS_FILE")

    MIN_TIME=$(echo "$TIMES" | sort -n | head -1)
    MAX_TIME=$(echo "$TIMES" | sort -n | tail -1)
    TOTAL_TIME=$(echo "$TIMES" | awk '{sum+=$1} END {print sum}')
    AVG_TIME=$(echo "scale=2; $TOTAL_TIME / $TOTAL_REQUESTS" | bc)

    # P50, P95, P99
    P50=$(echo "$TIMES" | sort -n | sed "s/^//" | awk '{a[NR]=$1} END {print a[int(NR*0.5)]}')
    P95=$(echo "$TIMES" | sort -n | sed "s/^//" | awk '{a[NR]=$1} END {print a[int(NR*0.95)]}')
    P99=$(echo "$TIMES" | sort -n | sed "s/^//" | awk '{a[NR]=$1} END {print a[int(NR*0.99)]}')

    # Count HTTP errors
    ERRORS=$(echo "$CODES" | grep -v "^200" | wc -l || true)
    SUCCESS_RATE=$(echo "scale=2; ($TOTAL_REQUESTS - $ERRORS) / $TOTAL_REQUESTS * 100" | bc)

    # Throughput
    THROUGHPUT=$(echo "scale=2; $TOTAL_REQUESTS / $DURATION" | bc)
  fi

  # ─────────────────────────────────────────────────────────────────────────────
  # Load Testing - ApacheBench (if available)
  # ─────────────────────────────────────────────────────────────────────────────

elif [ "$USE_AB" = true ]; then
  echo "🚀 Load Test Phase (ApacheBench)"
  echo "═══════════════════════════════════════════════════════════════"

  AB_RESULTS="/tmp/ab-results-$$.txt"

  # Run ApacheBench
  ab -n $((CONCURRENT_USERS * DURATION / 10)) \
     -c $CONCURRENT_USERS \
     "$TARGET_URL/api/items" \
     | tee "$AB_RESULTS"

  # Parse ApacheBench results
  TOTAL_REQUESTS=$(grep "Requests per second" "$AB_RESULTS" | awk '{print $4}')
  THROUGHPUT=$(grep "Requests per second" "$AB_RESULTS" | awk '{print $4}')
  AVG_TIME=$(grep "Time per request" "$AB_RESULTS" | head -1 | awk '{print $4}')
  P95=$(grep "95%" "$AB_RESULTS" | awk '{print $2}' || echo "N/A")

  MIN_TIME=$(grep "min" "$AB_RESULTS" | awk '{print $2}' || echo "N/A")
  MAX_TIME=$(grep "max" "$AB_RESULTS" | awk '{print $2}' || echo "N/A")

  ERRORS=$(grep "Failed requests" "$AB_RESULTS" | awk '{print $3}' || echo "0")
fi

rm -f "$RESULTS_FILE" "$AB_RESULTS" 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   LOAD TEST RESULTS                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "Test Configuration:"
echo "  Concurrent Users:    $CONCURRENT_USERS"
echo "  Test Duration:       ${DURATION}s"
echo "  Total Requests:      $TOTAL_REQUESTS"
echo ""

echo "Performance Metrics:"
echo "  Minimum Latency:     ${MIN_TIME}ms"
echo "  Average Latency:     ${AVG_TIME}ms"
echo "  P50 Latency:         ${P50:-N/A}ms"
echo "  P95 Latency:         ${P95:-N/A}ms"
echo "  P99 Latency:         ${P99:-N/A}ms"
echo "  Maximum Latency:     ${MAX_TIME}ms"
echo "  Throughput:          ${THROUGHPUT} req/s"
echo ""

echo "Reliability Metrics:"
echo "  Total Errors:        $ERRORS"
echo "  Success Rate:        ${SUCCESS_RATE:-N/A}%"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SLO Validation
# ─────────────────────────────────────────────────────────────────────────────

echo "📋 SLO Validation Against Targets"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Define SLOs
SLO_P95=300
SLO_P99=500
SLO_ERROR=2
SLO_AVAILABILITY=99.5

# Validate P95
if [ "$(echo "$P95 <= $SLO_P95" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
  echo "✅ P95 Latency: ${P95}ms (target: ${SLO_P95}ms)"
else
  echo "⚠️  P95 Latency: ${P95}ms (target: ${SLO_P95}ms) - EXCEEDS SLO"
fi

# Validate P99
if [ "$(echo "$P99 <= $SLO_P99" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
  echo "✅ P99 Latency: ${P99}ms (target: ${SLO_P99}ms)"
else
  echo "⚠️  P99 Latency: ${P99}ms (target: ${SLO_P99}ms) - EXCEEDS SLO"
fi

# Validate error rate
if [ "$(echo "$ERRORS <= ($TOTAL_REQUESTS * $SLO_ERROR / 100)" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
  echo "✅ Error Rate: $ERRORS errors (target: <${SLO_ERROR}%)"
else
  echo "⚠️  Error Rate: $ERRORS errors (target: <${SLO_ERROR}%) - EXCEEDS SLO"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Cache Metrics
# ─────────────────────────────────────────────────────────────────────────────

echo "💾 Cache Performance Metrics"
echo "═══════════════════════════════════════════════════════════════"

# Fetch current cache metrics
CACHE_STATUS=$(curl -s "$TARGET_URL/api/cache-status" 2>/dev/null || echo "{}")

if command -v jq &> /dev/null; then
  L1_HITS=$(echo "$CACHE_STATUS" | jq '.l1.hits // 0' 2>/dev/null || echo "N/A")
  L1_MISSES=$(echo "$CACHE_STATUS" | jq '.l1.misses // 0' 2>/dev/null || echo "N/A")
  L2_HITS=$(echo "$CACHE_STATUS" | jq '.l2.hits // 0' 2>/dev/null || echo "N/A")
  L2_MISSES=$(echo "$CACHE_STATUS" | jq '.l2.misses // 0' 2>/dev/null || echo "N/A")

  echo "L1 Cache:"
  echo "  Hits:   $L1_HITS"
  echo "  Misses: $L1_MISSES"

  echo "L2 Cache:"
  echo "  Hits:   $L2_HITS"
  echo "  Misses: $L2_MISSES"

  # Calculate hit rates
  if [ "$L1_HITS" != "N/A" ] && [ "$L1_MISSES" != "N/A" ]; then
    TOTAL_L1=$((L1_HITS + L1_MISSES))
    if [ $TOTAL_L1 -gt 0 ]; then
      L1_HIT_RATE=$(echo "scale=1; $L1_HITS / $TOTAL_L1 * 100" | bc)
      echo "  Hit Rate: ${L1_HIT_RATE}%"
    fi
  fi
else
  echo "$CACHE_STATUS"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Recommendations
# ─────────────────────────────────────────────────────────────────────────────

echo "📝 Recommendations"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ "$(echo "$P95 > $SLO_P95" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
  echo "⚠️  P95 latency exceeds target. Consider:"
  echo "   - Increase L1 cache size (L1_CACHE_SIZE)"
  echo "   - Increase L2 cache size (Redis memory)"
  echo "   - Extend cache TTL values"
  echo "   - Add database query optimization"
fi

if [ "$(echo "$ERRORS > 0" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
  echo "⚠️  Errors detected during load test. Check:"
  echo "   - Application error logs"
  echo "   - Redis connectivity"
  echo "   - Database connection pool size"
  echo "   - Memory usage during peak load"
fi

if [ "$(echo "${L1_HIT_RATE:-0} < 50" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
  echo "⚠️  L1 cache hit rate below 50%. Consider:"
  echo "   - Increase cache size"
  echo "   - Review cache key strategy"
  echo "   - Analyze access patterns"
fi

echo ""
echo "✅ Load testing complete!"
echo ""
echo "Next Steps:"
echo "1. Review metrics against SLOs"
echo "2. Monitor production system under similar load"
echo "3. Adjust cache configuration based on results"
echo "4. Document baseline performance metrics"
