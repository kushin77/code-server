#!/bin/bash
# @file        scripts/load-testing/run-collaboration-platform-load-test.sh
# @module      load-testing/collaboration
# @description Runner for k6 collaboration platform load tests with SLO validation
#
# Usage:
#   ./run-collaboration-platform-load-test.sh --dry-run
#   ./run-collaboration-platform-load-test.sh --execute --scenario moderate
#   ./run-collaboration-platform-load-test.sh --help

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DRY_RUN=1
SCENARIO="moderate"
VUS=20
DURATION="10m"
BASE_URL="${BASE_URL:-https://ide.kushnir.cloud}"
WS_URL="${WS_URL:-wss://ide.kushnir.cloud/ws}"
TEST_FILE="${SCRIPT_DIR}/collaboration-platform-load-test.js"
REPORT_DIR="${SCRIPT_DIR}/../../artifacts/load-tests"

# Parse arguments
show_help() {
  cat << 'EOF'
Collaboration Platform Load Test Runner

Usage:
  run-collaboration-platform-load-test.sh [OPTIONS]

Options:
  --dry-run              Validate configuration without running tests (default)
  --execute              Run actual load test
  --scenario SCENARIO    Load profile: light, moderate, stress (default: moderate)
  --vus COUNT           Virtual users (default: depends on scenario)
  --duration TIME       Test duration (e.g., 10m, 300s) (default: 10m)
  --url URL             Base URL for IDE (default: https://ide.kushnir.cloud)
  --ws-url URL          WebSocket URL (default: wss://ide.kushnir.cloud/ws)
  --help                Show this help message

Examples:
  # Dry run (safe preview)
  ./run-collaboration-platform-load-test.sh --dry-run

  # Execute moderate load test
  ./run-collaboration-platform-load-test.sh --execute --scenario moderate

  # Stress test with custom VUs
  ./run-collaboration-platform-load-test.sh --execute --scenario stress --vus 50

  # Custom configuration
  ./run-collaboration-platform-load-test.sh --execute \
    --scenario moderate \
    --vus 30 \
    --duration 15m \
    --url https://staging.kushnir.cloud

Load Profiles:
  light:     10-20 VUs,  5-10 min   - Development/testing
  moderate:  20-40 VUs,  10 min     - Staging validation  
  stress:    50-100 VUs, 15+ min    - Production readiness

SLO Thresholds:
  - Collaboration Latency P99: < 200ms
  - Collaboration Latency P95: < 100ms
  - Message Delivery Success:  > 99.9%
  - Presence Sync P95:         < 100ms
  - Edit Conflict Rate:        < 10%
  - WebSocket Health:          > 99.8%
  - Connection Establishment:  < 500ms

Environment Variables:
  DRY_RUN        Set to 1 for dry-run, 0 for execute
  SCENARIO       Load profile (light, moderate, stress)
  VUS            Virtual users count
  DURATION       Test duration
  BASE_URL       IDE base URL
  WS_URL         WebSocket endpoint URL
EOF
  exit 0
}

# Validate dependencies
validate_dependencies() {
  echo -e "${BLUE}[INFO]${NC} Validating dependencies..."

  local missing=0

  if ! command -v k6 &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} k6 not found. Install from https://k6.io/docs/getting-started/installation/"
    missing=1
  fi

  if ! command -v jq &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} jq not found. Install from https://stedolan.github.io/jq/download/"
    missing=1
  fi

  if [[ $missing -eq 1 ]]; then
    exit 1
  fi

  echo -e "${GREEN}[OK]${NC} All dependencies available"
}

# Validate test file
validate_test_file() {
  if [[ ! -f "$TEST_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} Test file not found: $TEST_FILE"
    exit 1
  fi
  echo -e "${GREEN}[OK]${NC} Test file found: $TEST_FILE"
}

# Display configuration
display_config() {
  echo -e "${BLUE}[INFO]${NC} Configuration:"
  echo "  Mode:           $([ $DRY_RUN -eq 1 ] && echo 'DRY RUN' || echo 'EXECUTE')"
  echo "  Scenario:       $SCENARIO"
  echo "  Virtual Users:  $VUS"
  echo "  Duration:       $DURATION"
  echo "  Base URL:       $BASE_URL"
  echo "  WebSocket URL:  $WS_URL"
  echo "  Test File:      $TEST_FILE"
}

# Run load test
run_load_test() {
  echo -e "${BLUE}[INFO]${NC} Starting collaboration platform load test..."

  mkdir -p "$REPORT_DIR"
  local report_file="${REPORT_DIR}/collaboration-load-test-$(date +%s).json"

  export DRY_RUN
  export SCENARIO
  export VUS
  export DURATION
  export BASE_URL
  export WS_URL

  if [[ $DRY_RUN -eq 1 ]]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Validating test configuration (no actual load)"
    k6 run "$TEST_FILE" \
      --vus 1 \
      --duration 1s \
      --out json="$report_file"
  else
    echo -e "${BLUE}[EXECUTE]${NC} Running load test..."
    k6 run "$TEST_FILE" \
      --vus "$VUS" \
      --duration "$DURATION" \
      --out json="$report_file"
  fi

  if [[ $? -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Load test failed"
    return 1
  fi

  # Generate summary
  echo -e "\n${GREEN}[SUCCESS]${NC} Load test completed"
  echo -e "${BLUE}[INFO]${NC} Report saved to: $report_file"

  # Parse and display results
  if [[ $DRY_RUN -eq 0 ]]; then
    display_results "$report_file"
  fi
}

# Display test results
display_results() {
  local report_file="$1"

  echo -e "\n${BLUE}[RESULTS]${NC} Test Summary:"

  # Extract metrics from JSON report
  if command -v jq &> /dev/null; then
    # This is a simplified parser - full implementation would use jq to extract
    # collaboration-specific metrics from the k6 JSON output
    echo "  Detailed metrics available in: $report_file"
  fi
}

# Main execution
main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --execute)
        DRY_RUN=0
        shift
        ;;
      --scenario)
        SCENARIO="$2"
        shift 2
        ;;
      --vus)
        VUS="$2"
        shift 2
        ;;
      --duration)
        DURATION="$2"
        shift 2
        ;;
      --url)
        BASE_URL="$2"
        shift 2
        ;;
      --ws-url)
        WS_URL="$2"
        shift 2
        ;;
      --help)
        show_help
        ;;
      *)
        echo -e "${RED}[ERROR]${NC} Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
  done

  # Validate scenario
  case "$SCENARIO" in
    light|moderate|stress)
      ;;
    *)
      echo -e "${RED}[ERROR]${NC} Invalid scenario: $SCENARIO"
      echo "Must be one of: light, moderate, stress"
      exit 1
      ;;
  esac

  # Run validation
  validate_dependencies
  validate_test_file
  display_config

  # Run test
  run_load_test
}

# Execute main function
main "$@"
