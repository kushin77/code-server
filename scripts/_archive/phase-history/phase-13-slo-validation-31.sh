#!/bin/bash
# Phase 13 SLO Validation Test on 192.168.168.31

echo "=== PHASE 13 SLO VALIDATION TEST ===" 
echo "Target: 192.168.168.31:8080"
echo "Test: 300 concurrent curl requests to code-server"
echo ""

LOG_FILE="/tmp/slo-test-results-$(date +%s).log"
touch $LOG_FILE

# Run load test
echo "Starting load test (this takes ~1-2 minutes)..."
for i in {1..300}; do
  (
    RESP_START=$(date +%s%N)
    HTTP_CODE=$(curl -s -m 5 -w %{http_code} -o /dev/null http://localhost:8080/ 2>/dev/null)
    RESP_END=$(date +%s%N)
    
    LATENCY=$(( ($RESP_END - $RESP_START) / 1000000 ))
    
    if [ "$HTTP_CODE" == "200" ]; then
      echo "$LATENCY|SUCCESS|200" >> $LOG_FILE
    else
      echo "$LATENCY|FAIL|$HTTP_CODE" >> $LOG_FILE
    fi
  ) &
  
  # Run 10 concurrent, then wait
  if [ $((i % 10)) -eq 0 ]; then
    wait
    echo "Progress: $i/300 requests sent..."
  fi
done
wait

# Analysis
echo ""
echo "=== RESULTS ===" 
TOTAL=$(wc -l < $LOG_FILE 2>/dev/null || echo 0)
SUCCESS=$(grep -c SUCCESS $LOG_FILE 2>/dev/null || echo 0)
ERRORS=$((TOTAL - SUCCESS))

if [ $TOTAL -gt 0 ]; then
  ERROR_PCT=$(awk "BEGIN {printf \"%.1f\", $ERRORS * 100 / $TOTAL}")
else
  ERROR_PCT="N/A"
fi

echo "Total Requests: $TOTAL"
echo "Successful: $SUCCESS"
echo "Failures: $ERRORS"
echo "Error Rate: ${ERROR_PCT}%"
echo ""

# Latency analysis
if [ $TOTAL -gt 0 ]; then
  echo "=== LATENCY ANALYSIS ===" 
  # Get sorted latencies
  LATENCIES=$(cut -d'|' -f1 $LOG_FILE | sort -n)
  
  # Calculate percentiles
  P50=$(echo "$LATENCIES" | awk -v rows=$(wc -l < $LOG_FILE) 'NR==int(rows*0.50+0.5) {print}')
  P99=$(echo "$LATENCIES" | awk -v rows=$(wc -l < $LOG_FILE) 'NR==int(rows*0.99+0.5) {print}')
  P999=$(echo "$LATENCIES" | awk -v rows=$(wc -l < $LOG_FILE) 'NR==int(rows*0.999+0.5) {print}')
  
  echo "p50: ${P50:-N/A} ms"
  echo "p99: ${P99:-N/A} ms"
  echo "p99.9: ${P999:-N/A} ms"
  echo ""
  
  echo "=== SLO VALIDATION ===" 
  
  # Check p99 < 100ms
  if [ -n "$P99" ] && [ "$P99" -lt 100 ]; then
    echo "✓ p99 Latency < 100ms: PASS (${P99}ms)"
    P99_PASS=1
  else
    echo "✗ p99 Latency < 100ms: FAIL (${P99:-N/A}ms)"
    P99_PASS=0
  fi
  
  # Check error rate < 0.1%
  if [ "$ERROR_PCT" != "N/A" ] && (( $(echo "$ERROR_PCT < 0.2" | bc -l) )); then
    echo "✓ Error Rate < 0.1%: PASS (${ERROR_PCT}%)"
    ERROR_PASS=1
  else
    echo "✗ Error Rate < 0.1%: FAIL (${ERROR_PCT}%)"
    ERROR_PASS=0
  fi
  
  # Overall result
  echo ""
  if [ $P99_PASS -eq 1 ] && [ $ERROR_PASS -eq 1 ]; then
    echo "🟢 OVERALL: PASS - Phase 13 infrastructure meets SLO targets"
    exit 0
  else
    echo "🔴 OVERALL: FAIL - Some SLO targets not met"
    exit 1
  fi
else
  echo "❌ ERROR: No valid results collected"
  exit 2
fi
