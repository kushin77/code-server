#!/usr/bin/env bash
# @file        scripts/ci/check-observability-alerts.sh
# @module      observability/alerts
# @description Validate alert rules for OAuth auth path observability (#965)
#
# Checks:
#  1. Alert rules defined for auth path components
#  2. Grafana dashboard JSON is valid and importable
#  3. AlertManager routing configured for auth-critical alerts
#  4. Runbook links properly configured in alert annotations
#
# Usage:
#   bash scripts/ci/check-observability-alerts.sh    # Full validation
#   DRY_RUN=1 bash scripts/ci/check-observability-alerts.sh  # Check only
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
ALERT_RULES_FILE="${REPO_ROOT}/alert-rules.yml"
DASHBOARD_FILE="${REPO_ROOT}/artifacts/triage/portal-ide-auth-path-dashboard.json"
ALERTMANAGER_FILE="${REPO_ROOT}/alertmanager.yml"
REPORT_FILE="${REPO_ROOT}/artifacts/triage/observability-alerts-validation.json"

mkdir -p "${REPORT_FILE%/*}"

# Track check results
CHECKS_PASSED=0
CHECKS_FAILED=0
FAILURES=()

# ============================================================================
# Check 1: Alert Rules Defined
# ============================================================================
log_info "Check 1: Validating alert rules for auth path components..."

REQUIRED_ALERTS=(
  "OAuth2ProxyHighErrorRate"
  "OAuth2ProxyUnauthorizedSpike"
  "PortalAuthPathGatewayErrorRateHigh"
  "PortalAuthPathUnavailable"
  "SessionBrokerUnavailable"
  "AppsmithContainerUnhealthy"
  "SessionBrokerCreateErrorsHigh"
  "SessionBrokerLookupErrorsHigh"
  "RedisActiveMasterSwitch"
  "RedisConnectedClientsDropped"
  "CaddyUpstream5xxSpike"
)

MISSING_ALERTS=()
for alert in "${REQUIRED_ALERTS[@]}"; do
  if grep -q "alert: $alert" "$ALERT_RULES_FILE"; then
    log_debug "  ✓ Alert found: $alert"
  else
    log_warn "  ✗ Alert missing: $alert"
    MISSING_ALERTS+=("$alert")
  fi
done

if [ ${#MISSING_ALERTS[@]} -eq 0 ]; then
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  log_info "  PASS: All required alerts defined"
else
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("Missing alerts: ${MISSING_ALERTS[*]}")
  log_error "  FAIL: Missing ${#MISSING_ALERTS[@]} alerts"
fi

# ============================================================================
# Check 2: Runbook Links in Alerts
# ============================================================================
log_info "Check 2: Validating runbook links in alert annotations..."

# shellcheck disable=SC2034
RUNBOOK_URL="https://github.com/kushin77/code-server/issues/965"
ALERTS_WITH_RUNBOOK=$(grep -c "runbook.*965" "$ALERT_RULES_FILE" || true)
# shellcheck disable=SC2034
TOTAL_ALERTS=$(grep -c "alert:" "$ALERT_RULES_FILE" || true)

if [ "$ALERTS_WITH_RUNBOOK" -gt 0 ]; then
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  log_info "  PASS: $ALERTS_WITH_RUNBOOK alerts reference issue #965 runbook"
else
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("No alerts reference runbook #965")
  log_error "  FAIL: No runbook links found"
fi

# ============================================================================
# Check 3: Grafana Dashboard JSON Validity
# ============================================================================
log_info "Check 3: Validating Grafana dashboard JSON..."

if [ ! -f "$DASHBOARD_FILE" ]; then
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("Dashboard file not found: $DASHBOARD_FILE")
  log_error "  FAIL: Dashboard file not found"
else
  # Validate JSON syntax
  if python3 -m json.tool "$DASHBOARD_FILE" > /dev/null 2>&1; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
    log_info "  PASS: Dashboard JSON is valid"
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    FAILURES+=("Dashboard JSON is malformed")
    log_error "  FAIL: Invalid JSON in dashboard"
  fi

  # Check required panels
  REQUIRED_PANELS=("OAuth Flow Funnel" "OAuth Error Rates" "Active Sessions" "Component Health Status" "Redis Memory Usage")
  MISSING_PANELS=()
  for panel in "${REQUIRED_PANELS[@]}"; do
    if grep -q "\"title\": \"$panel" "$DASHBOARD_FILE"; then
      log_debug "  ✓ Panel found: $panel"
    else
      MISSING_PANELS+=("$panel")
    fi
  done

  if [ ${#MISSING_PANELS[@]} -eq 0 ]; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
    log_info "  PASS: All required dashboard panels present"
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    FAILURES+=("Missing dashboard panels: ${MISSING_PANELS[*]}")
    log_error "  FAIL: ${#MISSING_PANELS[@]} panels missing"
  fi
fi

# ============================================================================
# Check 4: AlertManager Routing Configuration
# ============================================================================
log_info "Check 4: Validating AlertManager routing for auth-critical alerts..."

if grep -q "component: auth-path" "$ALERTMANAGER_FILE" && grep -q "pagerduty" "$ALERTMANAGER_FILE"; then
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  log_info "  PASS: AlertManager configured for auth-path PagerDuty routing"
else
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("AlertManager missing auth-path PagerDuty routing")
  log_error "  FAIL: AlertManager routing not configured properly"
fi

# ============================================================================
# Generate Report
# ============================================================================
log_info "Generating validation report..."

# Build failures array safely
FAILURES_JSON="[]"
if [ ${#FAILURES[@]} -gt 0 ]; then
  FAILURES_JSON=$(printf '%s\n' "${FAILURES[@]}" | python3 -c "import sys, json; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))")
fi

REPORT_JSON=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "checks_passed": $CHECKS_PASSED,
  "checks_failed": $CHECKS_FAILED,
  "total_checks": $((CHECKS_PASSED + CHECKS_FAILED)),
  "checks": {
    "alert_rules_defined": {
      "passed": $([ ${#MISSING_ALERTS[@]} -eq 0 ] && echo true || echo false),
      "details": "Validated ${#REQUIRED_ALERTS[@]} required alerts"
    },
    "runbook_links": {
      "passed": $([ "$ALERTS_WITH_RUNBOOK" -gt 0 ] && echo true || echo false),
      "details": "$ALERTS_WITH_RUNBOOK alerts reference issue #965"
    },
    "dashboard_json": {
      "passed": $([ -f "$DASHBOARD_FILE" ] && echo true || echo false),
      "details": "Dashboard file: $DASHBOARD_FILE"
    },
    "alertmanager_routing": {
      "passed": $(grep -q "component: auth-path" "$ALERTMANAGER_FILE" && echo true || echo false),
      "details": "PagerDuty routing for auth-critical alerts"
    }
  },
  "failures": $FAILURES_JSON,
  "status": "$([ $CHECKS_FAILED -eq 0 ] && echo "PASS" || echo "FAIL")"
}
EOF
)

if [ "${DRY_RUN:-1}" != "1" ]; then
  echo "$REPORT_JSON" > "$REPORT_FILE"
  log_info "Report saved to $REPORT_FILE"
fi

echo "$REPORT_JSON" | python3 -m json.tool

# ============================================================================
# Exit Status
# ============================================================================
if [ $CHECKS_FAILED -eq 0 ]; then
  log_info "✓ All observability checks passed ($CHECKS_PASSED/$((CHECKS_PASSED + CHECKS_FAILED)))"
  exit 0
else
  log_error "✗ Observability validation failed ($CHECKS_FAILED failures)"
  exit 1
fi
