#!/usr/bin/env bash
# @file        scripts/load-testing/run-collaboration-platform-load-test.sh
# @module      load-testing/collaboration
# @description Run collaboration platform load tests with SLO validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
BASE_URL="${BASE_URL:-https://ide.kushnir.cloud}"
WS_URL="${WS_URL:-wss://ide.kushnir.cloud/ws}"
SCENARIO="${SCENARIO:-moderate}"
DURATION="${DURATION:-10m}"
VUS="${VUS:-20}"
DRY_RUN="${DRY_RUN:-1}"
REPORT_DIR="${REPORT_DIR:-artifacts/load-tests}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_header() {
  log_info "=========================================="
  log_info "$1"
  log_info "=========================================="
}

log_metric() {
  log_info "  $1"
}

validate_dependencies() {
  log_info "Validating dependencies..."

  local missing_deps=()

  if ! command -v k6 &> /dev/null; then
    missing_deps+=("k6")
  fi

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_fatal "Missing required dependencies: ${missing_deps[*]}"
  fi

  log_info "All dependencies validated ✓"
}

validate_test_file() {
  log_info "Validating test file..."

  local test_file="$SCRIPT_DIR/load-testing/collaboration-platform-load-test.js"

  if [[ ! -f "$test_file" ]]; then
    log_fatal "Test file not found: $test_file"
  fi

  # Basic syntax check
  if ! head -20 "$test_file" | grep -q "Load testing framework for collaboration platform"; then
    log_fatal "Test file appears invalid or corrupted"
  fi

  log_info "Test file validated ✓"
}

prepare_report_dir() {
  log_info "Preparing report directory..."

  mkdir -p "$REPORT_DIR"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  REPORT_FILE="$REPORT_DIR/collaboration_load_test_${timestamp}.json"
  REPORT_SUMMARY="$REPORT_DIR/collaboration_load_test_${timestamp}_summary.txt"

  log_info "Reports will be saved to:"
  log_metric "$REPORT_FILE"
  log_metric "$REPORT_SUMMARY"
}

show_configuration() {
  log_header "Load Test Configuration"
  log_metric "Base URL:      $BASE_URL"
  log_metric "WebSocket URL: $WS_URL"
  log_metric "Scenario:      $SCENARIO"
  log_metric "Duration:      $DURATION"
  log_metric "VUs:           $VUS"
  log_metric "Dry Run:       $([ "$DRY_RUN" = "1" ] && echo "YES" || echo "NO")"
  echo ""
}

run_dry_run() {
  log_header "DRY RUN MODE"
  log_info "Validating test configuration without sending actual load..."
  log_info ""

  k6 run \
    --dry-run \
    --vus 1 \
    --duration 1s \
    -e "BASE_URL=$BASE_URL" \
    -e "WS_URL=$WS_URL" \
    -e "SCENARIO=$SCENARIO" \
    -e "VUS=$VUS" \
    -e "DRY_RUN=1" \
    "$SCRIPT_DIR/load-testing/collaboration-platform-load-test.js"

  log_info "Dry run validation complete ✓"
}

run_load_test() {
  log_header "Executing Load Test"
  log_info "Scenario: $SCENARIO"
  log_info "Duration: $DURATION"
  log_info "Virtual Users: $VUS"
  echo ""

  k6 run \
    --scenario "$SCENARIO" \
    --vus "$VUS" \
    --duration "$DURATION" \
    -e "BASE_URL=$BASE_URL" \
    -e "WS_URL=$WS_URL" \
    -e "SCENARIO=$SCENARIO" \
    -e "VUS=$VUS" \
    -e "DRY_RUN=0" \
    --out json="$REPORT_FILE" \
    "$SCRIPT_DIR/load-testing/collaboration-platform-load-test.js"

  log_info "Load test execution complete ✓"
}

generate_summary() {
  log_header "Load Test Results Summary"

  if [[ ! -f "$REPORT_FILE" ]]; then
    log_warn "No report file generated. Check test output above."
    return 1
  fi

  local summary_start=$(cat > "$REPORT_SUMMARY" << 'EOF'
Collaboration Platform Load Test Report
========================================

Test Configuration:
EOF
)

  echo "Test Configuration:" >> "$REPORT_SUMMARY"
  echo "  Base URL:      $BASE_URL" >> "$REPORT_SUMMARY"
  echo "  WebSocket URL: $WS_URL" >> "$REPORT_SUMMARY"
  echo "  Scenario:      $SCENARIO" >> "$REPORT_SUMMARY"
  echo "  Duration:      $DURATION" >> "$REPORT_SUMMARY"
  echo "  VUs:           $VUS" >> "$REPORT_SUMMARY"
  echo "  Timestamp:     $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$REPORT_SUMMARY"
  echo "" >> "$REPORT_SUMMARY"

  echo "SLO Thresholds:" >> "$REPORT_SUMMARY"
  echo "  Collaboration Latency P99: < 200ms" >> "$REPORT_SUMMARY"
  echo "  Collaboration Latency P95: < 100ms" >> "$REPORT_SUMMARY"
  echo "  Collaboration Latency P50: < 50ms" >> "$REPORT_SUMMARY"
  echo "  Message Delivery Success:   > 99.9%" >> "$REPORT_SUMMARY"
  echo "  Presence Sync P95:          < 100ms" >> "$REPORT_SUMMARY"
  echo "  Edit Conflict Rate:         < 10%" >> "$REPORT_SUMMARY"
  echo "  Connection Establishment:   < 500ms" >> "$REPORT_SUMMARY"
  echo "  WebSocket Health Success:   > 99.8%" >> "$REPORT_SUMMARY"
  echo "" >> "$REPORT_SUMMARY"

  # Try to extract metrics if jq is available
  if command -v jq &> /dev/null; then
    echo "Test Results:" >> "$REPORT_SUMMARY"
    # Note: k6 JSON output structure varies, this is a placeholder
    echo "  (See detailed report: $REPORT_FILE)" >> "$REPORT_SUMMARY"
  fi

  log_info "Summary saved to: $REPORT_SUMMARY"
  cat "$REPORT_SUMMARY"
}

show_help() {
  cat << 'EOF'
Usage: run-collaboration-platform-load-test.sh [OPTIONS]

Options:
  -s, --scenario SCENARIO     Load profile: light, moderate, stress (default: moderate)
  -d, --duration DURATION     Test duration, e.g., 5m, 10m (default: 10m)
  -v, --vus VUS              Number of virtual users (default: 20)
  -u, --url BASE_URL         Base URL for tests (default: https://ide.kushnir.cloud)
  -w, --ws-url WS_URL        WebSocket URL (default: wss://ide.kushnir.cloud/ws)
  --dry-run                  Validate configuration only (default)
  --execute                  Execute actual load test
  --report-dir DIR           Report output directory (default: artifacts/load-tests)
  -h, --help                 Show this help message

Examples:
  # Dry run with moderate load
  ./run-collaboration-platform-load-test.sh --dry-run

  # Execute stress test
  ./run-collaboration-platform-load-test.sh --execute --scenario stress --vus 50

  # Custom configuration
  ./run-collaboration-platform-load-test.sh --execute \
    --scenario moderate \
    --duration 15m \
    --vus 30 \
    --url https://staging.kushnir.cloud

Environment Variables:
  BASE_URL        Base URL for API endpoints
  WS_URL          WebSocket URL
  SCENARIO        Load profile (light/moderate/stress)
  DURATION        Test duration
  VUS             Number of virtual users
  DRY_RUN         1=dry run, 0=execute (default: 1)
  REPORT_DIR      Output directory for reports

EOF
}

main() {
  log_header "Collaboration Platform Load Test Runner"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -s|--scenario)
        SCENARIO="$2"
        shift 2
        ;;
      -d|--duration)
        DURATION="$2"
        shift 2
        ;;
      -v|--vus)
        VUS="$2"
        shift 2
        ;;
      -u|--url)
        BASE_URL="$2"
        shift 2
        ;;
      -w|--ws-url)
        WS_URL="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --execute)
        DRY_RUN=0
        shift
        ;;
      --report-dir)
        REPORT_DIR="$2"
        shift 2
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        log_fatal "Unknown option: $1"
        ;;
    esac
  done

  # Execution flow
  validate_dependencies
  validate_test_file
  prepare_report_dir
  show_configuration

  if [[ "$DRY_RUN" = "1" ]]; then
    run_dry_run
    log_info "To execute actual load test, run with --execute flag"
  else
    run_load_test
    generate_summary
  fi

  log_header "Load Test Complete"
}

main "$@"
