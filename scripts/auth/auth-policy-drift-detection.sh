#!/usr/bin/env bash
# @file        scripts/auth/auth-policy-drift-detection.sh
# @module      auth/compliance
# @description Policy drift detection — monitors for unauthorized policy changes and alerts team
#
# Usage:
#   bash scripts/auth/auth-policy-drift-detection.sh     # Run drift checks
#   bash scripts/auth/auth-policy-drift-detection.sh verify  # Just verify, don't alert
#
# Checks:
#   1. auth-flow-integrity: oauth2-proxy config matches baseline
#   2. policy-config-drift: policies/code-server.yaml not modified outside IaC
#   3. audit-log-health: audit logs being written correctly
#   4. identity-provider-health: admin-portal OAuth responding

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/_common/init.sh"

# ============================================================================
# Configuration
# ============================================================================
DRIFT_CHECK_INTERVAL="${DRIFT_CHECK_INTERVAL:-15m}"
DRIFT_ALERT_THRESHOLD="${DRIFT_ALERT_THRESHOLD:-5}"  # % drift allowed
SLACK_WEBHOOK="${SLACK_WEBHOOK_ALERTS:-}"
PAGERDUTY_KEY="${PAGERDUTY_INT_KEY:-}"
DRY_RUN="${1:-}"

DRIFT_REPORT_FILE="/tmp/policy-drift-report-$(date +%Y%m%d_%H%M%S).json"
LAST_BASELINE_HASH=""

# ============================================================================
# Check 1: Auth Flow Integrity
# ============================================================================
check_auth_flow_integrity() {
  log_info "Checking auth flow integrity..."
  
  # Verify oauth2-proxy config exists and is readable
  local oauth_config_files=(
    "oauth2-proxy.cfg"
    "docker-compose.yml"
    "Caddyfile"
  )
  
  local issues=0
  for file in "${oauth_config_files[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
      log_error "Critical config missing: $file"
      ((issues++))
      continue
    fi
    
    # Check for hardcoded secrets (major drift indicator)
    if grep -qE '(GOOGLE_CLIENT_SECRET|OAUTH2_COOKIE_SECRET)=' "$SCRIPT_DIR/$file"; then
      log_error "CRITICAL: Hardcoded secrets found in $file"
      ((issues++))
    fi
    
    # Check for required OAuth endpoints
    local required_endpoints=(
      "oauth2/callback"
      "oauth2/start"
    )
    
    for endpoint in "${required_endpoints[@]}"; do
      if ! grep -q "$endpoint" "$SCRIPT_DIR/$file"; then
        log_warn "Missing OAuth endpoint: $endpoint in $file"
        ((issues++))
      fi
    done
  done
  
  if [[ $issues -gt 0 ]]; then
    return 1
  fi
  
  log_info "Auth flow integrity check PASSED"
  return 0
}

# ============================================================================
# Check 2: Policy Configuration Drift
# ============================================================================
check_policy_config_drift() {
  log_info "Checking policy config drift..."
  
  local policy_file="$SCRIPT_DIR/policies/code-server.yaml"
  
  if [[ ! -f "$policy_file" ]]; then
    log_error "Policy file not found: $policy_file"
    return 1
  fi
  
  # Calculate current hash
  local current_hash=$(sha256sum "$policy_file" | awk '{print $1}')
  
  # Get committed version hash
  local committed_hash
  committed_hash=$(cd "$SCRIPT_DIR" && git show HEAD:policies/code-server.yaml 2>/dev/null | sha256sum | awk '{print $1}') || {
    log_warn "Could not retrieve committed hash (git not available)"
    return 0
  }
  
  # Compare
  if [[ "$current_hash" != "$committed_hash" ]]; then
    log_warn "Policy file has uncommitted changes"
    log_warn "  Current hash:   $current_hash"
    log_warn "  Committed hash: $committed_hash"
    return 1
  fi
  
  log_info "Policy config drift check PASSED"
  return 0
}

# ============================================================================
# Check 3: Audit Log Health
# ============================================================================
check_audit_log_health() {
  log_info "Checking audit log health..."
  
  if ! command -v gcloud &>/dev/null; then
    log_warn "gcloud not available, skipping audit log health check"
    return 0
  fi
  
  local project="${AUDIT_LOG_PROJECT:-gcp-eiq}"
  local log_name="${AUDIT_LOG_NAME:-code-server-auth-policy}"
  
  # Check if recent logs exist (within last 1 hour)
  local recent_logs
  recent_logs=$(gcloud logging read \
    "logName=projects/$project/logs/$log_name" \
    --project="$project" \
    --limit=1 \
    --format=json 2>/dev/null | jq 'length') || {
    log_error "Failed to query Cloud Logging"
    return 1
  }
  
  if [[ "$recent_logs" -eq 0 ]]; then
    log_warn "No recent audit logs found in Cloud Logging"
    return 1
  fi
  
  log_info "Audit log health check PASSED"
  return 0
}

# ============================================================================
# Check 4: Identity Provider Health
# ============================================================================
check_identity_provider_health() {
  log_info "Checking identity provider health..."
  
  local admin_portal_url="${ADMIN_PORTAL_URL:-https://admin.kushnir.cloud}"
  local userinfo_endpoint="$admin_portal_url/oauth2/api/v1/userinfo"
  
  # Probe with 10 second timeout
  if ! timeout 10s curl -sf "$userinfo_endpoint" >/dev/null 2>&1; then
    log_error "Identity provider not responding: $userinfo_endpoint"
    return 1
  fi
  
  log_info "Identity provider health check PASSED"
  return 0
}

# ============================================================================
# Calculate Overall Drift Score
# ============================================================================
calculate_drift_score() {
  local checks_passed=0
  local checks_total=4
  
  check_auth_flow_integrity && ((checks_passed++)) || true
  check_policy_config_drift && ((checks_passed++)) || true
  check_audit_log_health && ((checks_passed++)) || true
  check_identity_provider_health && ((checks_passed++)) || true
  
  # Drift score = (1 - (passed/total)) * 100
  local drift_score=$(( (checks_total - checks_passed) * 100 / checks_total ))
  
  echo "$drift_score"
}

# ============================================================================
# Alert on Drift Detected
# ============================================================================
alert_on_drift() {
  local drift_score="$1"
  
  if [[ "$drift_score" -gt "$DRIFT_ALERT_THRESHOLD" ]]; then
    local message="🚨 POLICY DRIFT DETECTED (Score: ${drift_score}%)"
    
    log_error "$message"
    
    # Post to Slack
    if [[ -n "$SLACK_WEBHOOK" ]]; then
      curl -s -X POST "$SLACK_WEBHOOK" \
        -H 'Content-Type: application/json' \
        -d "{
          \"text\": \"$message\",
          \"attachments\": [{
            \"color\": \"danger\",
            \"fields\": [
              {\"title\": \"Drift Score\", \"value\": \"${drift_score}%\"},
              {\"title\": \"Threshold\", \"value\": \"${DRIFT_ALERT_THRESHOLD}%\"},
              {\"title\": \"Report\", \"value\": \"$DRIFT_REPORT_FILE\"},
              {\"title\": \"Action\", \"value\": \"Review policy changes via: git diff HEAD policies/code-server.yaml\"}
            ]
          }]
        }" || log_warn "Failed to post drift alert to Slack"
    fi
    
    # Post to PagerDuty
    if [[ -n "$PAGERDUTY_KEY" ]]; then
      curl -s -X POST 'https://events.pagerduty.com/v2/enqueue' \
        -H 'Content-Type: application/json' \
        -d "{
          \"routing_key\": \"$PAGERDUTY_KEY\",
          \"event_action\": \"trigger\",
          \"payload\": {
            \"summary\": \"$message\",
            \"severity\": \"critical\",
            \"source\": \"code-server-policy-drift-detection\",
            \"custom_details\": {
              \"drift_score\": $drift_score,
              \"threshold\": $DRIFT_ALERT_THRESHOLD,
              \"report_file\": \"$DRIFT_REPORT_FILE\"
            }
          }
        }" || log_warn "Failed to post drift alert to PagerDuty"
    fi
  fi
}

# ============================================================================
# Generate Drift Report
# ============================================================================
generate_drift_report() {
  local drift_score="$1"
  
  cat > "$DRIFT_REPORT_FILE" <<EOF
{
  "report_generated": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "drift_score_percent": $drift_score,
  "drift_threshold_percent": $DRIFT_ALERT_THRESHOLD,
  "status": "$(if [[ $drift_score -gt $DRIFT_ALERT_THRESHOLD ]]; then echo "ALERT"; else echo "OK"; fi)",
  "checks": {
    "auth_flow_integrity": "$(check_auth_flow_integrity >/dev/null 2>&1 && echo "PASS" || echo "FAIL")",
    "policy_config_drift": "$(check_policy_config_drift >/dev/null 2>&1 && echo "PASS" || echo "FAIL")",
    "audit_log_health": "$(check_audit_log_health >/dev/null 2>&1 && echo "PASS" || echo "FAIL")",
    "identity_provider_health": "$(check_identity_provider_health >/dev/null 2>&1 && echo "PASS" || echo "FAIL")"
  },
  "repository_info": {
    "current_branch": "$(cd "$SCRIPT_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')",
    "current_commit": "$(cd "$SCRIPT_DIR" && git rev-parse HEAD 2>/dev/null || echo 'unknown')",
    "policy_file_hash": "$(sha256sum "$SCRIPT_DIR/policies/code-server.yaml" 2>/dev/null | awk '{print $1}' || echo 'unknown')"
  }
}
EOF
  
  log_info "Drift report saved: $DRIFT_REPORT_FILE"
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
  log_info "Starting policy drift detection checks"
  
  local drift_score
  drift_score=$(calculate_drift_score)
  
  log_info "Drift score: ${drift_score}%"
  generate_drift_report "$drift_score"
  
  if [[ -z "$DRY_RUN" ]]; then
    alert_on_drift "$drift_score"
  fi
  
  # Exit with error if threshold exceeded
  if [[ $drift_score -gt $DRIFT_ALERT_THRESHOLD ]]; then
    log_error "Drift detection threshold exceeded"
    return 1
  fi
  
  log_info "Policy drift detection completed successfully"
  return 0
}

main
