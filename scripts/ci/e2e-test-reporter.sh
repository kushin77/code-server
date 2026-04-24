#!/usr/bin/env bash
# @file        scripts/ci/e2e-test-reporter.sh
# @module      ci/e2e-testing
# @description E2E test result analysis and reporting (Issues #986-990 support)
# @owner       qa-team
# @status      Ready for use after E2E tests complete
#
# Purpose: Analyze Playwright test results and generate summary reports
#
# Usage:
#   bash scripts/ci/e2e-test-reporter.sh [--format=markdown|json|html]
#   bash scripts/ci/e2e-test-reporter.sh --upload-artifacts
#   bash scripts/ci/e2e-test-reporter.sh --comment-issue 986
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
REPORT_FORMAT="${REPORT_FORMAT:-markdown}"
RESULTS_FILE="${RESULTS_FILE:-artifacts/playwright-results.json}"
JUNIT_FILE="${JUNIT_FILE:-artifacts/playwright-junit.xml}"
HTML_REPORT="${HTML_REPORT:-artifacts/playwright-report}"
UPLOAD_ARTIFACTS="${UPLOAD_ARTIFACTS:-false}"
COMMENT_ISSUE="${COMMENT_ISSUE:-}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_pass() {
  echo -e "${GREEN}[✓]${NC} $1"
}

log_fail() {
  echo -e "${RED}[✗]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[!]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --format)
      REPORT_FORMAT="$2"
      shift 2
      ;;
    --upload)
      UPLOAD_ARTIFACTS="true"
      shift
      ;;
    --comment-issue)
      COMMENT_ISSUE="$2"
      shift 2
      ;;
    *)
      log_fail "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Parse Playwright JSON results
parse_playwright_results() {
  if [[ ! -f "$RESULTS_FILE" ]]; then
    log_fail "Results file not found: $RESULTS_FILE"
    return 1
  fi

  # Extract metrics using jq (if available) or Python
  if command -v jq &> /dev/null; then
    TOTAL_TESTS=$(jq '.stats.expected // 0' "$RESULTS_FILE")
    PASSED_TESTS=$(jq '.stats.expected - (.stats.unexpected // 0) - (.stats.skipped // 0)' "$RESULTS_FILE")
    FAILED_TESTS=$(jq '.stats.unexpected // 0' "$RESULTS_FILE")
    SKIPPED_TESTS=$(jq '.stats.skipped // 0' "$RESULTS_FILE")
    DURATION=$(jq '.stats.duration // 0' "$RESULTS_FILE")
  else
    # Fallback: basic parsing
    TOTAL_TESTS=$(grep -o '"expected": [0-9]*' "$RESULTS_FILE" | head -1 | cut -d' ' -f2)
    FAILED_TESTS=$(grep -o '"unexpected": [0-9]*' "$RESULTS_FILE" | head -1 | cut -d' ' -f2)
    SKIPPED_TESTS=$(grep -o '"skipped": [0-9]*' "$RESULTS_FILE" | head -1 | cut -d' ' -f2)
    PASSED_TESTS=$((TOTAL_TESTS - FAILED_TESTS - SKIPPED_TESTS))
    DURATION=0
  fi

  # Calculate metrics
  PASS_RATE=$((PASSED_TESTS * 100 / (TOTAL_TESTS > 0 ? TOTAL_TESTS : 1)))
}

# Generate Markdown report
report_markdown() {
  local report_file="artifacts/e2e-test-report.md"
  
  cat > "$report_file" << EOF
# E2E Test Execution Report

**Date**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')

## Summary

| Metric | Value |
|--------|-------|
| Total Tests | $TOTAL_TESTS |
| Passed | $PASSED_TESTS ✅ |
| Failed | $FAILED_TESTS ❌ |
| Skipped | $SKIPPED_TESTS ⏭️ |
| Pass Rate | $PASS_RATE% |
| Duration | ${DURATION}ms (~$((DURATION / 1000))s) |

## Status

$(if [[ $FAILED_TESTS -eq 0 ]]; then echo "🟢 **ALL TESTS PASSED**"; else echo "🔴 **FAILURES DETECTED** - Review details below"; fi)

## Test Suites

### OAuth Login Flow (#986)
- [x] Test spec: oauth-login.spec.ts
- Status: Ready for execution
- Coverage: Happy path, error cases, edge cases

### Appsmith Portal Testing (#987)
- [x] Test spec: appsmith-login.spec.ts
- Status: Ready for execution
- Coverage: Static assets, OAuth flow, GitHub/SSO, interactive login

### IDE Launch and Operations (#988)
- [x] Test spec: ide-launch-workspace.spec.ts
- Status: Ready for execution
- Coverage: Editor, filesystem, terminal, extensions, settings

### Session Persistence and Failover (#989)
- [x] Test spec: session-persistence-failover.spec.ts
- Status: Ready for execution
- Coverage: Session preservation, failover, recovery

### Error Handling and Edge Cases (#990)
- [x] Test spec: error-handling-edge-cases.spec.ts
- Status: Ready for execution
- Coverage: Network failures, invalid input, rate limiting, resource exhaustion

## Detailed Results

$(if [[ $FAILED_TESTS -gt 0 ]]; then
  echo "### Failed Tests"
  echo ""
  echo "See JUnit report for details: playwright-junit.xml"
  echo ""
fi)

## Artifacts

- **HTML Report**: playwright-report/index.html
  - Visual test results with screenshots and videos on failure
  - Detailed timeline for each test
  - Browser console and network logs

- **JUnit XML**: playwright-junit.xml
  - Machine-readable format for CI integration
  - Failed test details and error messages
  - Timing information

- **JSON Results**: playwright-results.json
  - Complete test execution data
  - Test metrics and statistics
  - Full error traces

## Next Steps

$(if [[ $FAILED_TESTS -eq 0 ]]; then
  echo "1. ✅ All tests passing - Ready for production deployment"
  echo "2. Review test coverage and performance metrics"
  echo "3. Archive results: artifacts/e2e-test-report.md"
  echo "4. Proceed to production deployment"
else
  echo "1. ❌ Review failures in HTML report"
  echo "2. Check error logs in playwright-junit.xml"
  echo "3. Fix failing tests and re-run"
  echo "4. Repeat until all tests pass"
fi)

## Issues Addressed

- [x] Issue #986: OAuth login comprehensive validation
- [x] Issue #987: Appsmith portal feature testing
- [x] Issue #988: IDE launch and workspace operations
- [x] Issue #989: Session persistence and failover
- [x] Issue #990: Error handling and edge cases

---

*Report generated by scripts/ci/e2e-test-reporter.sh*  
*Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')*
EOF

  log_pass "Report generated: $report_file"
  echo "$report_file"
}

# Generate JSON report
report_json() {
  local report_file="artifacts/e2e-test-metrics.json"
  
  cat > "$report_file" << EOF
{
  "metadata": {
    "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
    "generator": "scripts/ci/e2e-test-reporter.sh"
  },
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS,
    "pass_rate": $PASS_RATE,
    "duration_ms": $DURATION
  },
  "status": "$(if [[ $FAILED_TESTS -eq 0 ]]; then echo "PASS"; else echo "FAIL"; fi)",
  "test_suites": [
    {
      "issue": "#986",
      "title": "OAuth Login Flow",
      "spec": "oauth-login.spec.ts",
      "status": "ready"
    },
    {
      "issue": "#987",
      "title": "Appsmith Portal Testing",
      "spec": "appsmith-login.spec.ts",
      "status": "ready"
    },
    {
      "issue": "#988",
      "title": "IDE Launch and Operations",
      "spec": "ide-launch-workspace.spec.ts",
      "status": "ready"
    },
    {
      "issue": "#989",
      "title": "Session Persistence and Failover",
      "spec": "session-persistence-failover.spec.ts",
      "status": "ready"
    },
    {
      "issue": "#990",
      "title": "Error Handling and Edge Cases",
      "spec": "error-handling-edge-cases.spec.ts",
      "status": "ready"
    }
  ]
}
EOF

  log_pass "JSON metrics generated: $report_file"
  echo "$report_file"
}

# Comment on GitHub issue
comment_on_github() {
  if [[ -z "$COMMENT_ISSUE" ]] || ! command -v gh &> /dev/null; then
    log_warn "Skipping GitHub comment (no issue or gh CLI not available)"
    return 0
  fi

  local comment_body
  read -r -d '' comment_body << 'EOF' || true
## E2E Test Execution Complete ✅

**Timestamp**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')

### Test Results Summary

| Metric | Count |
|--------|-------|
| **Total Tests** | TOTAL_TESTS |
| **Passed** | PASSED_TESTS ✅ |
| **Failed** | FAILED_TESTS ❌ |
| **Skipped** | SKIPPED_TESTS ⏭️ |
| **Pass Rate** | PASS_RATE% |
| **Duration** | ~DURATION_SEC seconds |

### Status: STATUS_EMOJI STATUS_TEXT

### Artifacts

- [HTML Report](artifacts/playwright-report/index.html) - Interactive test results with screenshots
- [JUnit XML](artifacts/playwright-junit.xml) - Machine-readable results
- [Test Metrics](artifacts/e2e-test-metrics.json) - JSON metrics

### Related Issues

- [#986](https://github.com/kushin77/code-server/issues/986) - OAuth Login Flow
- [#987](https://github.com/kushin77/code-server/issues/987) - Appsmith Portal Testing
- [#988](https://github.com/kushin77/code-server/issues/988) - IDE Launch Operations
- [#989](https://github.com/kushin77/code-server/issues/989) - Session Persistence
- [#990](https://github.com/kushin77/code-server/issues/990) - Error Handling

---

*Generated by scripts/ci/e2e-test-reporter.sh*
EOF

  # Substitute variables
  comment_body="${comment_body//TOTAL_TESTS/$TOTAL_TESTS}"
  comment_body="${comment_body//PASSED_TESTS/$PASSED_TESTS}"
  comment_body="${comment_body//FAILED_TESTS/$FAILED_TESTS}"
  comment_body="${comment_body//SKIPPED_TESTS/$SKIPPED_TESTS}"
  comment_body="${comment_body//PASS_RATE/$PASS_RATE}"
  comment_body="${comment_body//DURATION_SEC/$((DURATION / 1000))}"
  
  if [[ $FAILED_TESTS -eq 0 ]]; then
    comment_body="${comment_body//STATUS_EMOJI/🟢}"
    comment_body="${comment_body//STATUS_TEXT/ALL TESTS PASSED}"
  else
    comment_body="${comment_body//STATUS_EMOJI/🔴}"
    comment_body="${comment_body//STATUS_TEXT/FAILURES DETECTED}"
  fi

  log_info "Commenting on issue #$COMMENT_ISSUE..."
  gh issue comment "$COMMENT_ISSUE" --repo "$GITHUB_REPO" --body "$comment_body"
  log_pass "Comment posted to #$COMMENT_ISSUE"
}

# Main execution
main() {
  echo "========================================="
  echo "E2E Test Result Analysis"
  echo "========================================="
  echo

  # Parse results
  if ! parse_playwright_results; then
    log_fail "Could not parse test results"
    return 1
  fi

  # Display summary
  echo "Test Execution Summary:"
  echo "  Total: $TOTAL_TESTS"
  echo "  Passed: $PASSED_TESTS (${PASS_RATE}%)"
  echo "  Failed: $FAILED_TESTS"
  echo "  Skipped: $SKIPPED_TESTS"
  echo "  Duration: $((DURATION / 1000))s"
  echo

  # Generate reports based on format
  case "$REPORT_FORMAT" in
    markdown)
      report_markdown
      ;;
    json)
      report_json
      ;;
    html)
      if [[ -d "$HTML_REPORT" ]]; then
        log_pass "HTML report already generated at: $HTML_REPORT"
      else
        log_fail "HTML report not found"
        return 1
      fi
      ;;
    *)
      log_fail "Unknown format: $REPORT_FORMAT"
      return 1
      ;;
  esac

  # Comment on GitHub if requested
  if [[ -n "$COMMENT_ISSUE" ]]; then
    comment_on_github
  fi

  # Exit code
  if [[ $FAILED_TESTS -eq 0 ]]; then
    log_pass "E2E tests successful!"
    return 0
  else
    log_fail "E2E tests failed - Review artifacts above"
    return 1
  fi
}

main
