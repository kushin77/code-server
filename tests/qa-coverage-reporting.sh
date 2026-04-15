#!/bin/bash
# tests/qa-coverage-reporting.sh - QA Coverage Analysis and Reporting
# Generates coverage metrics, trends, and reports for QA-COVERAGE-004

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
COVERAGE_DIR="${COVERAGE_DIR:-.qa-coverage}"
ENDPOINTS_CONFIG="${ENDPOINTS_CONFIG:-.qa-coverage/endpoints.json}"
RESULTS_DIR="${RESULTS_DIR:-test-results/qa-coverage}"
HISTORY_DIR="${HISTORY_DIR:-.qa-coverage/history}"
TREND_THRESHOLD_PERCENT="${TREND_THRESHOLD_PERCENT:-5}"

# Create directories
mkdir -p "$COVERAGE_DIR" "$RESULTS_DIR" "$HISTORY_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

log_info() {
  echo "[QA-COVERAGE] $1"
}

log_error() {
  echo "[QA-COVERAGE] ERROR: $1" >&2
}

# Calculate endpoint coverage percentage
calculate_endpoint_coverage() {
  local test_results="$1"
  
  if [[ ! -f "$test_results" ]]; then
    echo "0"
    return 1
  fi
  
  local total=$(jq '.endpoints | length' "$test_results" 2>/dev/null || echo 0)
  local passed=$(jq '[.endpoints[] | select(.status=="pass")] | length' "$test_results" 2>/dev/null || echo 0)
  
  if [[ $total -eq 0 ]]; then
    echo "0"
    return 1
  fi
  
  local percent=$((passed * 100 / total))
  echo "$percent"
}

# Calculate interaction coverage percentage
calculate_interaction_coverage() {
  local test_results="$1"
  
  if [[ ! -f "$test_results" ]]; then
    echo "0"
    return 1
  fi
  
  local total=$(jq '.interactions | length' "$test_results" 2>/dev/null || echo 0)
  local passed=$(jq '[.interactions[] | select(.status=="pass")] | length' "$test_results" 2>/dev/null || echo 0)
  
  if [[ $total -eq 0 ]]; then
    echo "0"
    return 1
  fi
  
  local percent=$((passed * 100 / total))
  echo "$percent"
}

# Calculate API contract coverage
calculate_contract_coverage() {
  local test_results="$1"
  
  if [[ ! -f "$test_results" ]]; then
    echo "0"
    return 1
  fi
  
  local total=$(jq '[.endpoints[] | select(has("assertions"))] | length' "$test_results" 2>/dev/null || echo 0)
  local passed=$(jq '[.endpoints[] | select(has("assertions") and .assertions.status=="pass")] | length' "$test_results" 2>/dev/null || echo 0)
  
  if [[ $total -eq 0 ]]; then
    echo "0"
    return 1
  fi
  
  local percent=$((passed * 100 / total))
  echo "$percent"
}

# Detect coverage regressions
detect_regressions() {
  local current_coverage="$1"
  local current_file="$2"
  local threshold="$3"
  
  # Find most recent historical result
  local previous_file=$(ls -t "$HISTORY_DIR"/coverage-*.json 2>/dev/null | head -1)
  
  if [[ -z "$previous_file" ]]; then
    log_info "No previous coverage baseline found (first run)"
    return 0
  fi
  
  local previous_coverage=$(jq '.summary.endpointCoverage' "$previous_file" 2>/dev/null || echo 0)
  local regression=$((previous_coverage - current_coverage))
  
  if [[ $regression -gt $threshold ]]; then
    log_error "Coverage regression detected: $previous_coverage% → $current_coverage% (${regression}% drop)"
    return 1
  fi
  
  if [[ $regression -gt 0 ]]; then
    log_info "Coverage decreased slightly: $previous_coverage% → $current_coverage% (${regression}% drop)"
  elif [[ $regression -lt 0 ]]; then
    log_info "Coverage improved: $previous_coverage% → $current_coverage% ($((0 - regression))% gain)"
  fi
  
  return 0
}

# Generate summary report
generate_summary() {
  local results_file="$1"
  local endpoint_cov="$2"
  local interaction_cov="$3"
  local contract_cov="$4"
  
  cat > "${RESULTS_DIR}/coverage-summary.json" << EOF
{
  "timestamp": "$(date -I'seconds')",
  "summary": {
    "endpointCoverage": $endpoint_cov,
    "interactionCoverage": $interaction_cov,
    "contractCoverage": $contract_cov,
    "overallCoverage": $(((endpoint_cov + interaction_cov + contract_cov) / 3))
  },
  "targets": {
    "endpoint": 95,
    "interaction": 80,
    "contract": 90
  },
  "status": {
    "endpointMet": $([ $endpoint_cov -ge 95 ] && echo "true" || echo "false"),
    "interactionMet": $([ $interaction_cov -ge 80 ] && echo "true" || echo "false"),
    "contractMet": $([ $contract_cov -ge 90 ] && echo "true" || echo "false")
  }
}
EOF
  
  log_info "Coverage summary written to: ${RESULTS_DIR}/coverage-summary.json"
}

# Generate trend report
generate_trend_report() {
  local summary_file="$1"
  
  # Collect historical data
  local trend_data='[]'
  for history_file in $(ls -t "$HISTORY_DIR"/coverage-*.json 2>/dev/null | head -30); do
    trend_data=$(jq -s ".[0] as \$new | .[1] += [\$new] | .[1]" "$summary_file" <(echo "$trend_data") 2>/dev/null || echo "$trend_data")
  done
  
  cat > "${RESULTS_DIR}/coverage-trend.json" << EOF
{
  "timestamp": "$(date -I'seconds')",
  "period": "30-day",
  "history": $(echo "$trend_data" | jq '.'),
  "trend": "$([ "$trend_data" == "[]" ] && echo "baseline" || echo "tracking")"
}
EOF
  
  log_info "Coverage trend written to: ${RESULTS_DIR}/coverage-trend.json"
}

# Generate HTML report
generate_html_report() {
  local summary_file="$1"
  
  local endpoint_cov=$(jq '.summary.endpointCoverage' "$summary_file")
  local interaction_cov=$(jq '.summary.interactionCoverage' "$summary_file")
  local contract_cov=$(jq '.summary.contractCoverage' "$summary_file")
  local overall_cov=$(jq '.summary.overallCoverage' "$summary_file")
  
  cat > "${RESULTS_DIR}/coverage-report.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>QA Coverage Report</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 20px; background: #f5f5f5; }
    .header { background: #2c3e50; color: white; padding: 20px; border-radius: 4px; margin-bottom: 20px; }
    .metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px; margin-bottom: 20px; }
    .metric { background: white; padding: 15px; border-radius: 4px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
    .metric-value { font-size: 32px; font-weight: bold; margin: 10px 0; }
    .metric.pass { border-left: 4px solid #27ae60; }
    .metric.warn { border-left: 4px solid #f39c12; }
    .metric.fail { border-left: 4px solid #e74c3c; }
    .progress-bar { width: 100%; height: 20px; background: #ecf0f1; border-radius: 2px; overflow: hidden; }
    .progress-fill { height: 100%; background: linear-gradient(90deg, #27ae60, #2ecc71); transition: width 0.3s; }
    .footer { color: #7f8c8d; font-size: 12px; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="header">
    <h1>QA Coverage Report</h1>
    <p>Generated: <span id="timestamp"></span></p>
  </div>
  
  <div class="metrics">
    <div class="metric pass">
      <h3>Endpoint Coverage</h3>
      <div class="metric-value"><span id="endpoint">0</span>%</div>
      <div class="progress-bar"><div class="progress-fill" style="width: <ENDPOINT_PCT>%"></div></div>
      <p>Target: 95%</p>
    </div>
    
    <div class="metric pass">
      <h3>Interaction Coverage</h3>
      <div class="metric-value"><span id="interaction">0</span>%</div>
      <div class="progress-bar"><div class="progress-fill" style="width: <INTERACTION_PCT>%"></div></div>
      <p>Target: 80%</p>
    </div>
    
    <div class="metric pass">
      <h3>Contract Coverage</h3>
      <div class="metric-value"><span id="contract">0</span>%</div>
      <div class="progress-bar"><div class="progress-fill" style="width: <CONTRACT_PCT>%"></div></div>
      <p>Target: 90%</p>
    </div>
    
    <div class="metric pass">
      <h3>Overall Coverage</h3>
      <div class="metric-value"><span id="overall">0</span>%</div>
      <div class="progress-bar"><div class="progress-fill" style="width: <OVERALL_PCT>%"></div></div>
      <p>Combined Average</p>
    </div>
  </div>
  
  <div class="footer">
    <p>QA-COVERAGE-004 | VPN-Only | Dual Engine (Playwright + Puppeteer)</p>
  </div>
</body>
</html>
EOF

  # Inject actual values
  sed -i "s/<ENDPOINT_PCT>/$endpoint_cov/g" "${RESULTS_DIR}/coverage-report.html"
  sed -i "s/<INTERACTION_PCT>/$interaction_cov/g" "${RESULTS_DIR}/coverage-report.html"
  sed -i "s/<CONTRACT_PCT>/$contract_cov/g" "${RESULTS_DIR}/coverage-report.html"
  sed -i "s/<OVERALL_PCT>/$overall_cov/g" "${RESULTS_DIR}/coverage-report.html"
  
  log_info "HTML report written to: ${RESULTS_DIR}/coverage-report.html"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

case "${1:-analyze}" in
  analyze)
    # Analyze provided results
    local results_file="${2:-.qa-coverage/latest-results.json}"
    
    if [[ ! -f "$results_file" ]]; then
      log_error "Results file not found: $results_file"
      exit 1
    fi
    
    log_info "Analyzing coverage from: $results_file"
    
    # Calculate metrics
    local endpoint_cov=$(calculate_endpoint_coverage "$results_file")
    local interaction_cov=$(calculate_interaction_coverage "$results_file")
    local contract_cov=$(calculate_contract_coverage "$results_file")
    
    log_info "Endpoint coverage: ${endpoint_cov}%"
    log_info "Interaction coverage: ${interaction_cov}%"
    log_info "Contract coverage: ${contract_cov}%"
    
    # Check for regressions
    local summary_file="${RESULTS_DIR}/coverage-summary.json"
    generate_summary "$results_file" "$endpoint_cov" "$interaction_cov" "$contract_cov"
    
    if detect_regressions "$endpoint_cov" "$summary_file" "$TREND_THRESHOLD_PERCENT"; then
      log_info "✅ Coverage thresholds met"
    else
      log_error "❌ Coverage regression detected"
      exit 1
    fi
    
    # Generate reports
    generate_trend_report "$summary_file"
    generate_html_report "$summary_file"
    
    # Save to history
    cp "$summary_file" "${HISTORY_DIR}/coverage-$(date +%s).json"
    
    log_info "Coverage analysis complete"
    ;;
    
  summary)
    cat "${RESULTS_DIR}/coverage-summary.json"
    ;;
    
  trend)
    cat "${RESULTS_DIR}/coverage-trend.json"
    ;;
    
  *)
    echo "Usage: $0 [analyze|summary|trend]"
    exit 1
    ;;
esac
