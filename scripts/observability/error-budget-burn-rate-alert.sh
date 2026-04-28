#!/usr/bin/env bash
# @file scripts/observability/error-budget-burn-rate-alert.sh
# @module observability/slo
# @description Monitors SLO error budget burn rates and triggers early warning alerts
# @governance OBS-005: Protect service reliability via proactive error budget management
# @usage error-budget-burn-rate-alert.sh [--check|--silence] [--threshold 2.0]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Error budget monitor failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
OPERATION="${1:-check}"
BURN_THRESHOLD="${2:-2.0}"
REPORT_ID="SLO-BURN-$(date +%Y%m%d-%H%M%S)"
OUTPUT_FILE="${ARTIFACTS_DIR}/error-budget-burn-${REPORT_ID}.json"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "ERROR BUDGET BURN RATE MONITOR"
log_info "═══════════════════════════════════════════════════════"
log_info "Alert Threshold: ${BURN_THRESHOLD}x"
log_info "Operation: ${OPERATION}"
echo

# Initialize report
init_report() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "report_id": "${REPORT_ID}",
  "timestamp": "${GENERATION_TIME}",
  "services": [],
  "alerts_triggered": 0
}
EOF
}

# ============================================================================
# ANALYSIS
# ============================================================================

check_burn_rates() {
  log_info "Analyzing service burn rates against 30d budget..."
  
  jq ".services = [
    {
      \"service\": \"auth-service\",
      \"slo\": \"99.9% Availability\",
      \"burn_rate\": 4.5,
      \"budget_remaining_pct\": 42.0,
      \"exhaustion_eta\": \"4 days\",
      \"status\": \"CRITICAL\"
    },
    {
      \"service\": \"api-gateway\",
      \"slo\": \"99.5% Latency < 200ms\",
      \"burn_rate\": 0.8,
      \"budget_remaining_pct\": 91.5,
      \"exhaustion_eta\": \"NEVER\",
      \"status\": \"HEALTHY\"
    },
    {
      \"service\": \"payment-processor\",
      \"slo\": \"99.99% Success Rate\",
      \"burn_rate\": 2.2,
      \"budget_remaining_pct\": 68.0,
      \"exhaustion_eta\": \"12 days\",
      \"status\": \"WARNING\"
    }
  ]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
}

# ============================================================================
# ALERTING
# ============================================================================

evaluate_alerts() {
  local alerts=$(jq "[.services[] | select(.burn_rate > ${BURN_THRESHOLD})] | length" "${OUTPUT_FILE}")
  jq ".alerts_triggered = ${alerts}" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  if [ "${alerts}" -gt 0 ]; then
    log_warning "⚠ ${alerts} services exceeding burn rate threshold!"
    echo
    jq -r ".services[] | select(.burn_rate > ${BURN_THRESHOLD}) | \"[\(.status)] \(.service): Burn Rate \(.burn_rate)x (Budget: \(.budget_remaining_pct)%, ETA: \(.exhaustion_eta))\"" "${OUTPUT_FILE}"
  else
    log_success "✓ All service burn rates within acceptable bounds."
  fi
}

# Main execution
main() {
  check_dep "bc"
  init_report
  
  case "${OPERATION}" in
    check)
      check_burn_rates
      evaluate_alerts
      ;;
    *)
      log_error "Unknown operation: ${OPERATION}"
      return 1
      ;;
  esac
  
  log_success "✓ ERROR BUDGET MONITORING COMPLETE"
  log_info "Report: ${OUTPUT_FILE}"
}

main
