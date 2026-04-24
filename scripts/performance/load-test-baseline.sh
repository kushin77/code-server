#!/usr/bin/env bash
# @file        scripts/performance/load-test-baseline.sh
# @module      performance/baseline-testing
# @description Execute baseline load test (100 concurrent users, 10 minutes)
# @owner       ops-team
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/scripts/_common/init.sh"

# Configuration
APP_URL="${APP_URL:-http://localhost:3000}"
ARTIFACT_DIR="${PROJECT_ROOT}/artifacts/performance-tests/$(date +%Y%m%d-%H%M%S)"
TEST_DURATION=600  # 10 minutes
NUM_USERS=100
RAMPUP_TIME=120   # 2 minutes

# Create artifact directory
mkdir -p "$ARTIFACT_DIR"/{logs,results}

log_info "=== BASELINE LOAD TEST ==="
log_info "Users: $NUM_USERS"
log_info "Duration: $((TEST_DURATION / 60)) minutes"
log_info "Ramp-up: $((RAMPUP_TIME / 60)) minutes"
log_info "Target: $APP_URL"
log_info ""

# Health check
log_info "Verifying application health..."
if ! curl -s "$APP_URL/health" | jq -e '.status == "ok"' > /dev/null 2>&1; then
  log_fatal "Application health check failed at $APP_URL"
fi
log_info "✅ Application is healthy"

# Run load test
log_info "Starting load test..."
TEST_START=$(date +%s)

# Generate load using background curl requests
for user_id in $(seq 1 $NUM_USERS); do
  {
    for request_num in $(seq 1 $((TEST_DURATION / 10))); do
      {
        RESPONSE_TIME=$(curl -s -w "%{time_total}" -o /dev/null "$APP_URL/api/workspaces" \
          -H "User-Agent: LoadTest-Baseline-User-$user_id")
        echo "$(date +%s),user-$user_id,$RESPONSE_TIME" >> "$ARTIFACT_DIR/logs/baseline.log"
      } &
      sleep 1
    done
  } &
  
  # Spawn users gradually during ramp-up
  if [ $((user_id % 10)) -eq 0 ]; then
    log_info "  Ramped up: $user_id users"
  fi
done

log_info "Running baseline load test for ${TEST_DURATION}s..."
sleep $TEST_DURATION

# Wait for all background processes
wait || true

TEST_END=$(date +%s)
TEST_ELAPSED=$((TEST_END - TEST_START))

# Analyze results
log_info ""
log_info "Test completed in ${TEST_ELAPSED}s"

if [ -f "$ARTIFACT_DIR/logs/baseline.log" ]; then
  TOTAL_REQUESTS=$(wc -l < "$ARTIFACT_DIR/logs/baseline.log")
  AVG_TIME=$(awk -F',' '{sum+=$3; count++} END {if(count>0) printf "%.3f", sum/count}' "$ARTIFACT_DIR/logs/baseline.log")
  
  log_info "Results:"
  log_info "  Total requests: $TOTAL_REQUESTS"
  log_info "  Average response time: ${AVG_TIME}s"
  
  # Save summary
  {
    echo "BASELINE_TEST_SUMMARY"
    echo "Date: $(date)"
    echo "Duration: ${TEST_ELAPSED}s"
    echo "Users: $NUM_USERS"
    echo "Total Requests: $TOTAL_REQUESTS"
    echo "Average Response Time: ${AVG_TIME}s"
  } | tee "$ARTIFACT_DIR/results/baseline-summary.txt"
  
  log_info "✅ Results saved to $ARTIFACT_DIR"
else
  log_error "No test data collected"
  exit 1
fi
