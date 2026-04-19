#!/usr/bin/env bash
# @file        scripts/auth/auth-audit-logger.sh
# @module      auth/logging
# @description Audit logging for all auth and policy decisions — writes structured logs to Google Cloud Logging
#
# Usage:
#   source scripts/auth/auth-audit-logger.sh
#   log_auth_event "login" "user@example.com" "success" "{additional_json_fields}"
#
# Environment:
#   AUDIT_LOG_PROJECT   — GCP project for logging (default: gcp-eiq)
#   AUDIT_LOG_NAME      — Log name in Cloud Logging (default: code-server-auth-policy)
#   AUDIT_RETENTION_DAYS— Log retention days (default: 90)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/_common/init.sh"

# ============================================================================
# Audit Event Types
# ============================================================================
readonly AUDIT_EVENT_TYPES=(
  "auth.login"
  "auth.logout"
  "auth.refresh"
  "auth.failed"
  "auth.keepalive.tick"
  "policy.evaluated"
  "policy.denied"
  "session.created"
  "session.expired"
  "session.revoked"
  "workspace.accessed"
  "workspace.modified"
)

# ============================================================================
# Environment Setup
# ============================================================================
AUDIT_LOG_PROJECT="${AUDIT_LOG_PROJECT:-gcp-eiq}"
AUDIT_LOG_NAME="${AUDIT_LOG_NAME:-code-server-auth-policy}"
AUDIT_RETENTION_DAYS="${AUDIT_RETENTION_DAYS:-90}"
AUDIT_BUFFER_FILE="${TMPDIR:-/tmp}/audit-buffer-$$.jsonl"

# ============================================================================
# Core Audit Logging Function
# ============================================================================
log_auth_event() {
  local event_type="$1"
  local user_email="${2:-unknown}"
  local result="${3:-unknown}"
  local extra_json="${4:-{}}"
  
  # Validate event type
  if ! printf '%s\n' "${AUDIT_EVENT_TYPES[@]}" | grep -q "^${event_type}$"; then
    log_error "Invalid audit event type: $event_type"
    return 1
  fi
  
  # Build audit record
  local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  local source_ip="${REMOTE_ADDR:-localhost}"
  local user_agent="${HTTP_USER_AGENT:-unknown}"
  
  # Extract user groups from context (if available)
  local user_groups="${AUTH_USER_GROUPS:-}"
  
  # Merge extra fields
  local audit_record=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "event": "$event_type",
  "userId": "${AUTH_USER_ID:-unknown}",
  "userEmail": "$user_email",
  "userGroups": "$user_groups",
  "result": "$result",
  "sourceIP": "$source_ip",
  "userAgent": "$user_agent",
  "metadata": $extra_json
}
EOF
  )
  
  # Buffer to file (will be flushed by log flush function)
  echo "$audit_record" >> "$AUDIT_BUFFER_FILE"
  
  # Also log locally for immediate visibility
  log_info "AUDIT[$event_type] user=$user_email result=$result"
}

# ============================================================================
# Flush Buffered Audit Logs to Cloud Logging
# ============================================================================
flush_audit_logs() {
  [[ ! -f "$AUDIT_BUFFER_FILE" ]] && return 0
  
  if ! command -v gcloud &>/dev/null; then
    log_warn "gcloud not available, storing audit logs locally only"
    cat "$AUDIT_BUFFER_FILE" >> "${HOME}/.code-server-audit-local.jsonl"
    rm -f "$AUDIT_BUFFER_FILE"
    return 0
  fi
  
  log_info "Flushing audit logs to Cloud Logging"
  
  # Build gcloud logging write command
  while IFS= read -r audit_line; do
    [[ -z "$audit_line" ]] && continue
    
    # Write to cloud logging
    gcloud logging write "$AUDIT_LOG_NAME" "$audit_line" \
      --project="$AUDIT_LOG_PROJECT" \
      --severity=INFO \
      --resource=global \
      2>/dev/null || log_warn "Failed to write audit log: $audit_line"
  done < "$AUDIT_BUFFER_FILE"
  
  rm -f "$AUDIT_BUFFER_FILE"
  log_info "Audit logs flushed successfully"
}

# ============================================================================
# Audit Query & Analysis Functions
# ============================================================================
query_auth_events() {
  local event_type="$1"
  local hours_back="${2:-24}"
  local limit="${3:-100}"
  
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud required for audit queries"
    return 1
  fi
  
  local start_time=$(date -u -d "$hours_back hours ago" +'%Y-%m-%dT%H:%M:%SZ')
  
  # Query Cloud Logging for events
  gcloud logging read \
    "resource.type=global AND \
     logName=projects/$AUDIT_LOG_PROJECT/logs/$AUDIT_LOG_NAME AND \
     jsonPayload.event=$event_type AND \
     timestamp>='$start_time'" \
    --project="$AUDIT_LOG_PROJECT" \
    --format=json \
    --limit="$limit" \
    2>/dev/null || log_error "Audit query failed"
}

# ============================================================================
# Audit Report Generation
# ============================================================================
generate_audit_report() {
  local report_file="${1:-/tmp/audit-report-$(date +%Y%m%d).json}"
  local hours_back="${2:-24}"
  
  log_info "Generating audit report for last $hours_back hours"
  
  cat > "$report_file" <<EOF
{
  "report_generated": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "reporting_period_hours": $hours_back,
  "audit_log_project": "$AUDIT_LOG_PROJECT",
  "audit_log_name": "$AUDIT_LOG_NAME",
  "events": [
EOF
  
  # For each event type, query and add to report
  for event_type in "${AUDIT_EVENT_TYPES[@]}"; do
    local count=$(query_auth_events "$event_type" "$hours_back" 1000 2>/dev/null | jq 'length' || echo 0)
    echo "    {\"event_type\": \"$event_type\", \"count\": $count}," >> "$report_file"
  done
  
  # Remove trailing comma and close
  sed -i '$ s/,$//' "$report_file"
  echo "  ]" >> "$report_file"
  echo "}" >> "$report_file"
  
  log_info "Audit report saved to: $report_file"
  cat "$report_file"
}

# ============================================================================
# Cleanup Trap
# ============================================================================
trap 'flush_audit_logs' EXIT

# ============================================================================
# Export Functions
# ============================================================================
export -f log_auth_event
export -f flush_audit_logs
export -f query_auth_events
export -f generate_audit_report
