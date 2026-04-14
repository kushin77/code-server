#!/bin/bash
# Rate Limiting Load Test Runner
# Executes k6 load test and summarizes results
# Run with: ./load-tests/run-rate-limit-test.sh

set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  API Rate Limiting Load Test                        ║"
echo "║  Target: 1000 req/s for 5 minutes                          ║"
echo "╚════════════════════════════════════════════════════════════╝"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="load-test-results/rate-limit-$TIMESTAMP"

mkdir -p "$RESULTS_DIR"

echo "Starting load test..."
echo "Results directory: $RESULTS_DIR"

# Run k6 load test
k6 run \
  --out json="$RESULTS_DIR/results.json" \
  --summary-export="$RESULTS_DIR/summary.json" \
  load-tests/rate-limit.k6.js

echo ""
echo "Load test completed!"
echo "Results saved to: $RESULTS_DIR"
echo ""

# Parse results
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test Results Summary                              ║"
echo "╚════════════════════════════════════════════════════════════╝"

if command -v jq &> /dev/null; then
  echo "Response Time (p99): $(jq '.metrics.response_time.values."p(99)"' "$RESULTS_DIR/summary.json" | xargs printf "%.0f ms\n")"
  echo "Rate Limit Exceeded: $(jq '.metrics.rate_limit_exceeded.values.rate' "$RESULTS_DIR/summary.json" | xargs printf "%.4f\n")"
  echo "Success Rate: $(jq '.metrics.requests_per_sec.values.rate' "$RESULTS_DIR/summary.json" | xargs printf "%.2%\n")"
else
  echo "jq not found - install to parse results"
  echo "Raw summary: $RESULTS_DIR/summary.json"
fi

echo ""
echo "Next steps:"
echo "  1. Review results in $RESULTS_DIR"
echo "  2. Check Grafana dashboard for rate limit metrics"
echo "  3. Adjust rate limit configuration if needed"
echo "  4. Deploy to staging for validation"
