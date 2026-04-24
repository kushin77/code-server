#!/usr/bin/env bash
# @file        scripts/ci/validate-oauth-runbook.sh
# @module      operations/runbooks
# @description Validate OAuth login failure recovery runbook (#966)
#
# Checks:
#  1. Runbook file exists and has required frontmatter
#  2. All referenced commands/scripts exist  
#  3. URLs and health check endpoints are documented
#  4. Step-by-step recovery procedures are complete
#
# Usage:
#   bash scripts/ci/validate-oauth-runbook.sh
#   DRY_RUN=1 bash scripts/ci/validate-oauth-runbook.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
RUNBOOK_FILE="${REPO_ROOT}/docs/runbooks/oauth-login-failure-recovery.md"
REPORT_FILE="${REPO_ROOT}/artifacts/triage/oauth-runbook-validation.json"

mkdir -p "${REPORT_FILE%/*}"

# Track results
CHECKS_PASSED=0
CHECKS_FAILED=0
FAILURES=()

# ============================================================================
# Check 1: Runbook File Exists
# ============================================================================
log_info "Check 1: Validating runbook file exists..."

if [ ! -f "$RUNBOOK_FILE" ]; then
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("Runbook file not found: $RUNBOOK_FILE")
  log_error "  FAIL: Runbook file missing"
else
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  log_info "  PASS: Runbook file exists at $RUNBOOK_FILE"
fi

# ============================================================================
# Check 2: Runbook Metadata/Frontmatter
# ============================================================================
log_info "Check 2: Validating runbook metadata..."

REQUIRED_SECTIONS=(
  "Purpose"
  "Trigger Conditions"
  "Step 1"
  "Step 2"
  "Step 3"
  "Step 4"
  "Step 5"
  "Step 6"
  "Decision Tree"
  "Verification Checklist"
)

MISSING_SECTIONS=()
for section in "${REQUIRED_SECTIONS[@]}"; do
  if grep -q "## $section" "$RUNBOOK_FILE"; then
    log_debug "  ✓ Section found: $section"
  else
    MISSING_SECTIONS+=("$section")
  fi
done

if [ ${#MISSING_SECTIONS[@]} -eq 0 ]; then
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  log_info "  PASS: All required sections present"
else
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("Missing sections: ${MISSING_SECTIONS[*]}")
  log_error "  FAIL: ${#MISSING_SECTIONS[@]} sections missing"
fi

# ============================================================================
# Check 3: Key Commands Referenced
# ============================================================================
log_info "Check 3: Validating referenced commands..."

REQUIRED_COMMANDS=(
  "curl -I https://kushnir.cloud/healthz"
  "docker-compose ps"
  "docker-compose logs"
  "docker-compose restart"
  "docker-compose exec"
  "scripts/ops/redeploy-portal.sh"
  "scripts/ops/failover-promote.sh"
  "gh issue create"
)

MISSING_COMMANDS=()
for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if grep -q "$cmd" "$RUNBOOK_FILE"; then
    log_debug "  ✓ Command referenced: $cmd"
  else
    MISSING_COMMANDS+=("$cmd")
  fi
done

if [ ${#MISSING_COMMANDS[@]} -eq 0 ]; then
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  log_info "  PASS: All required commands documented"
else
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("Missing command references: ${MISSING_COMMANDS[*]}")
  log_error "  FAIL: ${#MISSING_COMMANDS[@]} commands not documented"
fi

# ============================================================================
# Check 4: Health Check Endpoints
# ============================================================================
log_info "Check 4: Validating health check endpoints..."

REQUIRED_ENDPOINTS=(
  "/healthz"
  "/oauth2/sign_in"
  "/auth/reset"
  "/api/v1/health"
)

MISSING_ENDPOINTS=()
for endpoint in "${REQUIRED_ENDPOINTS[@]}"; do
  if grep -q "$endpoint" "$RUNBOOK_FILE"; then
    log_debug "  ✓ Endpoint documented: $endpoint"
  else
    MISSING_ENDPOINTS+=("$endpoint")
  fi
done

if [ ${#MISSING_ENDPOINTS[@]} -eq 0 ]; then
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  log_info "  PASS: All health check endpoints documented"
else
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("Missing endpoint documentation: ${MISSING_ENDPOINTS[*]}")
  log_error "  FAIL: ${#MISSING_ENDPOINTS[@]} endpoints missing"
fi

# ============================================================================
# Check 5: Recovery Steps Complete
# ============================================================================
log_info "Check 5: Validating recovery step completeness..."

RECOVERY_STEPS=7
DOCUMENTED_STEPS=0
for i in $(seq 1 $RECOVERY_STEPS); do
  if grep -qE "^## Step $i:" "$RUNBOOK_FILE"; then
    DOCUMENTED_STEPS=$((DOCUMENTED_STEPS + 1))
    log_debug "  ✓ Step $i documented"
  fi
done

if [ "$DOCUMENTED_STEPS" -eq "$RECOVERY_STEPS" ]; then
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  log_info "  PASS: All 7 recovery steps documented"
else
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("Only $DOCUMENTED_STEPS of $RECOVERY_STEPS recovery steps documented")
  log_error "  FAIL: Missing recovery steps"
fi

# ============================================================================
# Check 6: Alert Integration
# ============================================================================
log_info "Check 6: Validating alert integration..."

REQUIRED_ALERTS=(
  "OAuth2ProxyHighErrorRate"
  "OAuth2ProxyUnauthorizedSpike"
  "AppsmithContainerUnhealthy"
  "CaddyUpstream5xxSpike"
  "SessionBrokerUnavailable"
)

MISSING_ALERT_REFS=()
for alert in "${REQUIRED_ALERTS[@]}"; do
  if grep -q "$alert" "$RUNBOOK_FILE"; then
    log_debug "  ✓ Alert referenced: $alert"
  else
    MISSING_ALERT_REFS+=("$alert")
  fi
done

if [ ${#MISSING_ALERT_REFS[@]} -eq 0 ]; then
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  log_info "  PASS: All key alerts documented in runbook"
else
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("Missing alert references: ${MISSING_ALERT_REFS[*]}")
  log_error "  FAIL: ${#MISSING_ALERT_REFS[@]} alerts not referenced"
fi

# ============================================================================
# Check 7: Issue References
# ============================================================================
log_info "Check 7: Validating issue references..."

REQUIRED_ISSUES=("#965" "#966" "#954")
MISSING_ISSUES=()
for issue in "${REQUIRED_ISSUES[@]}"; do
  if grep -q "$issue" "$RUNBOOK_FILE"; then
    log_debug "  ✓ Issue referenced: $issue"
  else
    MISSING_ISSUES+=("$issue")
  fi
done

if [ ${#MISSING_ISSUES[@]} -eq 0 ]; then
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  log_info "  PASS: All related issues referenced"
else
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILURES+=("Missing issue references: ${MISSING_ISSUES[*]}")
  log_error "  FAIL: ${#MISSING_ISSUES[@]} issues not referenced"
fi

# ============================================================================
# Generate Report
# ============================================================================
log_info "Generating validation report..."

FAILURES_JSON="[]"
if [ ${#FAILURES[@]} -gt 0 ]; then
  FAILURES_JSON=$(printf '%s\n' "${FAILURES[@]}" | python3 -c "import sys, json; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))")
fi

REPORT_JSON=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "runbook_file": "$RUNBOOK_FILE",
  "checks_passed": $CHECKS_PASSED,
  "checks_failed": $CHECKS_FAILED,
  "total_checks": $((CHECKS_PASSED + CHECKS_FAILED)),
  "checks": {
    "file_exists": {
      "passed": $([ -f "$RUNBOOK_FILE" ] && echo true || echo false),
      "details": "Runbook markdown file present"
    },
    "required_sections": {
      "passed": $([ ${#MISSING_SECTIONS[@]} -eq 0 ] && echo true || echo false),
      "details": "${#REQUIRED_SECTIONS[@]} sections required, ${#MISSING_SECTIONS[@]} missing"
    },
    "commands_referenced": {
      "passed": $([ ${#MISSING_COMMANDS[@]} -eq 0 ] && echo true || echo false),
      "details": "${#REQUIRED_COMMANDS[@]} commands documented"
    },
    "health_endpoints": {
      "passed": $([ ${#MISSING_ENDPOINTS[@]} -eq 0 ] && echo true || echo false),
      "details": "${#REQUIRED_ENDPOINTS[@]} health endpoints documented"
    },
    "recovery_steps": {
      "passed": $([ "$DOCUMENTED_STEPS" -eq "$RECOVERY_STEPS" ] && echo true || echo false),
      "details": "$DOCUMENTED_STEPS of $RECOVERY_STEPS steps documented"
    },
    "alert_integration": {
      "passed": $([ ${#MISSING_ALERT_REFS[@]} -eq 0 ] && echo true || echo false),
      "details": "${#REQUIRED_ALERTS[@]} alerts documented"
    },
    "issue_references": {
      "passed": $([ ${#MISSING_ISSUES[@]} -eq 0 ] && echo true || echo false),
      "details": "Related issues #954, #965, #966 referenced"
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
  log_info "✓ All runbook validation checks passed ($CHECKS_PASSED/$((CHECKS_PASSED + CHECKS_FAILED)))"
  exit 0
else
  log_error "✗ Runbook validation failed ($CHECKS_FAILED failures)"
  exit 1
fi
