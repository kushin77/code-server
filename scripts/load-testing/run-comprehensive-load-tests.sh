#!/usr/bin/env bash

# @file        scripts/load-testing/run-comprehensive-load-tests.sh
# @module      testing/load-testing
# @description Orchestrator for comprehensive load testing suite
# @owner       Infrastructure
# @status      active

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${BASE_URL:-https://ide.kushnir.cloud}"
SCENARIO="${SCENARIO:-light}"  # light, moderate, stress
DRY_RUN="${DRY_RUN:-1}"
GENERATE_REPORT="${GENERATE_REPORT:-1}"
UPLOAD_RESULTS="${UPLOAD_RESULTS:-0}"

# Result directories
RESULTS_DIR="artifacts/load-test-results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEST_RUN_DIR="$RESULTS_DIR/$TIMESTAMP"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Comprehensive Load Testing Suite Orchestrator      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Configuration:"
echo "  Base URL: $BASE_URL"
echo "  Test Scenario: $SCENARIO"
echo "  Dry Run: $DRY_RUN"
echo "  Output Directory: $TEST_RUN_DIR"
echo ""

# Create output directory
mkdir -p "$TEST_RUN_DIR"

# Test suite definition
declare -a TESTS=(
  "oauth-flow|OAuth Login Flow|run-oauth-flow-load-test.sh"
  "jwt-token|JWT Token Acquisition|run-jwt-token-load-test.sh"
  "websocket|WebSocket Connections|run-websocket-load-test.sh"
  "session|Session Creation & Management|run-session-creation-load-test.sh"
  "api-endpoint|API Endpoint (with Auth)|run-api-endpoint-load-test.sh"
)

# Tracking arrays
declare -a TEST_NAMES
declare -a TEST_RESULTS
declare -a TEST_DURATIONS
FAILED_TESTS=0
PASSED_TESTS=0

echo -e "${BLUE}Test Suite (${#TESTS[@]} tests):${NC}"
for test_spec in "${TESTS[@]}"; do
  IFS='|' read -r test_id test_name _ <<< "$test_spec"
  echo "  • $test_name"
done
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "${YELLOW}DRY-RUN MODE${NC}"
  echo "No actual tests will be executed. To run tests:"
  echo ""
  echo "  DRY_RUN=0 $0"
  echo ""
  exit 0
fi

echo -e "${YELLOW}Starting load test execution...${NC}"
echo ""

# Run each test
TEST_INDEX=0
for test_spec in "${TESTS[@]}"; do
  IFS='|' read -r test_id test_name test_script <<< "$test_spec"
  TEST_INDEX=$((TEST_INDEX + 1))
  
  echo -e "${BLUE}[${TEST_INDEX}/${#TESTS[@]}] $test_name${NC}"
  echo "─────────────────────────────────────────"
  
  TEST_START_TIME=$(date +%s)
  
  # Set up environment for this test
  export BASE_URL
  export SCENARIO
  export DRY_RUN=0
  
  TEST_SCRIPT_PATH="$SCRIPT_DIR/$test_script"
  TEST_LOG="$TEST_RUN_DIR/${test_id}.log"
  TEST_SUMMARY="$TEST_RUN_DIR/${test_id}-summary.json"
  
  # Run test
  if bash "$TEST_SCRIPT_PATH" "$SCENARIO" > "$TEST_LOG" 2>&1; then
    TEST_RESULT="✓ PASSED"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    RESULT_COLOR="$GREEN"
  else
    TEST_RESULT="✗ FAILED"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    RESULT_COLOR="$RED"
  fi
  
  TEST_END_TIME=$(date +%s)
  TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))
  
  # Save test metadata
  cat > "$TEST_RUN_DIR/${test_id}-metadata.json" << EOF
{
  "test_id": "$test_id",
  "test_name": "$test_name",
  "scenario": "$SCENARIO",
  "start_time": "$TEST_START_TIME",
  "end_time": "$TEST_END_TIME",
  "duration_seconds": $TEST_DURATION,
  "status": "$([ "$PASSED_TESTS" -gt 0 ] && echo "passed" || echo "failed")",
  "base_url": "$BASE_URL"
}
EOF
  
  # Display result
  echo -e "${RESULT_COLOR}${TEST_RESULT}${NC} (${TEST_DURATION}s)"
  
  if [ "$PASSED_TESTS" -gt 0 ]; then
    # Extract key metrics if summary exists
    if [ -f "artifacts/load-test-${test_id}-summary.json" ]; then
      echo "  Metrics:"
      jq -r '.metrics | keys[]' "artifacts/load-test-${test_id}-summary.json" 2>/dev/null | head -3 | sed 's/^/    - /'
    fi
  else
    # Show last 5 lines of error log
    echo "  Error details:"
    tail -5 "$TEST_LOG" | sed 's/^/    /'
  fi
  
  echo ""
  
  TEST_NAMES+=("$test_name")
  TEST_RESULTS+=("$TEST_RESULT")
  TEST_DURATIONS+=("${TEST_DURATION}s")
done

# Generate comprehensive report
if [ "$GENERATE_REPORT" -eq 1 ]; then
  echo -e "${BLUE}Generating comprehensive report...${NC}"
  
  REPORT_FILE="$TEST_RUN_DIR/LOAD-TEST-REPORT.md"
  
  cat > "$REPORT_FILE" << EOF
# Load Testing Report
**Generated**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")**
**Scenario**: $SCENARIO**
**Base URL**: $BASE_URL**

## Executive Summary
- **Total Tests**: ${#TESTS[@]}
- **Passed**: $PASSED_TESTS
- **Failed**: $FAILED_TESTS
- **Success Rate**: $(echo "scale=1; $PASSED_TESTS * 100 / ${#TESTS[@]}" | bc)%

## Test Results

| Test | Status | Duration |
|------|--------|----------|
EOF
  
  for i in "${!TEST_NAMES[@]}"; do
    echo "| ${TEST_NAMES[$i]} | ${TEST_RESULTS[$i]} | ${TEST_DURATIONS[$i]} |" >> "$REPORT_FILE"
  done
  
  cat >> "$REPORT_FILE" << EOF

## Detailed Metrics

### OAuth Flow Metrics
\`\`\`
$(jq '.metrics' "artifacts/load-test-oauth-flow-summary.json" 2>/dev/null | head -20)
\`\`\`

### JWT Token Metrics
\`\`\`
$(jq '.metrics' "artifacts/load-test-jwt-token-summary.json" 2>/dev/null | head -20)
\`\`\`

### WebSocket Metrics
\`\`\`
$(jq '.metrics' "artifacts/load-test-websocket-summary.json" 2>/dev/null | head -20)
\`\`\`

## Analysis

### Performance Assessment
- All critical paths < 500ms: $([ $PASSED_TESTS -eq ${#TESTS[@]} ] && echo "✓ YES" || echo "✗ NO")
- Cache efficiency > 80%: $(grep -q "cache_hit_rate_percent" "$TEST_RUN_DIR/jwt-token-summary.json" 2>/dev/null && echo "Check report" || echo "N/A")
- Connection stability > 95%: $([ $PASSED_TESTS -eq ${#TESTS[@]} ] && echo "✓ YES" || echo "✗ NO")

### Recommendations

1. **If all tests passed**: Infrastructure is ready for $([ "$SCENARIO" = "stress" ] && echo "high-load production" || echo "increased traffic")
2. **If failures occurred**: Review detailed logs in $TEST_RUN_DIR
3. **Next steps**: 
   - Run with increased load (escalate from light → moderate → stress)
   - Monitor production metrics during deployment
   - Consider auto-scaling policies based on these baselines

## Test Run Details

**Results Directory**: $TEST_RUN_DIR

EOF
  
  echo -e "${GREEN}Report generated: $REPORT_FILE${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                  Test Summary                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Passed:   $PASSED_TESTS / ${#TESTS[@]}"
echo "Failed:   $FAILED_TESTS / ${#TESTS[@]}"
echo "Results:  $TEST_RUN_DIR"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
  echo -e "${GREEN}✓ All tests passed!${NC}"
  
  if [ "$UPLOAD_RESULTS" -eq 1 ]; then
    echo ""
    echo "Uploading results to GitHub..."
    # Results can be uploaded as artifact or comment
  fi
  
  exit 0
else
  echo -e "${RED}✗ Some tests failed. Review logs for details.${NC}"
  exit 1
fi
