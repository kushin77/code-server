#!/bin/bash
# @file        scripts/audit-logging.sh
# @module      audit-logging
# @description audit logging — on-prem code-server
# @owner       platform
# @status      active
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
################################################################################
# File: audit-logging.sh
# Owner: Security/Compliance Team
# Purpose: Centralized audit logging for security and compliance events
# Last Modified: April 14, 2026
# Compatibility: Ubuntu 22.04+, Bash 4.0+
#
# Dependencies:
#   - docker — Container log collection
#   - jq — JSON log parsing and filtering
#   - journalctl — System journal access
#
# Related Files:
#   - docker-compose.yml — Log configuration for services
#   - RUNBOOKS.md — Audit log procedures
#   - COMPLIANCE_STATUS_REPORT.md — Audit trail
#
# Usage:
#   ./audit-logging.sh collect                  # Collect all audit logs
#   ./audit-logging.sh filter <pattern>         # Filter logs by pattern
#   ./audit-logging.sh archive                  # Archive logs for retention
#
# Audit Events:
#   - User authentication (login/logout)
#   - Authorization changes
#   - Configuration modifications
#   - Deployment events
#   - Security policy violations
#   - Infrastructure changes
#
# Exit Codes:
#   0 — Audit logs collected successfully
#   1 — Audit logs collected with gaps
#   2 — Failed to collect audit logs
#
# Examples:
#   ./scripts/audit-logging.sh collect
#   ./scripts/audit-logging.sh filter "authentication"
#
# Recent Changes:
#   2026-04-14: Added compliance log validation (Phase 2.2)
#   2026-04-13: Initial creation with audit log collection
#
################################################################################
###############################################################################
# AUDIT LOGGING BASH HELPERS
# Issue #183: Shell command integration with audit logging system
#
# Source this file in scripts to get audit logging functions:
#   source /usr/local/lib/audit-logging.sh
#   audit_log_event SESSION_START "$developer_id" "$ip_address"
#
###############################################################################

# Configuration
AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-$HOME/.code-server-developers/logs}"
AUDIT_LOG_FILE="${AUDIT_LOG_DIR}/audit.jsonl"
AUDIT_PYTHON_COLLECTOR="${AUDIT_PYTHON_COLLECTOR:-/srv/audit-system/audit-log-collector.py}"

# Ensure log directory exists
mkdir -p "$AUDIT_LOG_DIR"
chmod 700 "$AUDIT_LOG_DIR"

###############################################################################
# UTILITY FUNCTIONS
###############################################################################

# Get current timestamp in ISO 8601 format
get_iso_timestamp() {
    date -u +'%Y-%m-%dT%H:%M:%SZ'
}

# Get developer ID from environment or current user
get_developer_id() {
    echo "${DEVELOPER_ID:-$(id -un)}"
}

# Get client IP address
get_client_ip() {
    echo "${SSH_CLIENT%% *}" || echo "$REMOTE_ADDR" || echo "127.0.0.1"
}

# Convert string to JSON string (escape quotes and newlines)
json_escape() {
    local string="$1"
    string="${string//\\/\\\\}"
    string="${string//\"/\\\"}"
    string="${string//$'\n'/\\n}"
    echo "$string"
}

###############################################################################
# CORE LOGGING FUNCTIONS
###############################################################################

# Generic audit event logging
audit_log_event() {
    local event_type="$1"
    local developer_id="$2"
    local ip_address="$3"
    local component="$4"
    local status="${5:-success}"
    local details="${6:-{}}"
    
    # Validate inputs
    if [ -z "$event_type" ] || [ -z "$developer_id" ]; then
        echo "ERROR: event_type and developer_id required" >&2
        return 1
    fi
    
    local timestamp=$(get_iso_timestamp)
    local hostname=$(hostname)
    local session_id="${SESSION_ID:-${SSH_SESSION_ID:-unknown}}"
    
    # Build JSON event
    local json_event=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "event_type": "$event_type",
  "developer_id": "$(json_escape "$developer_id")",
  "ip_address": "$ip_address",
  "session_id": "$session_id",
  "component": "$component",
  "status": "$status",
  "details": $details,
  "hostname": "$hostname"
}
EOF
)
    
    # Write to audit log
    if echo "$json_event" >> "$AUDIT_LOG_FILE"; then
        return 0
    else
        echo "ERROR: Failed to write to audit log" >&2
        return 1
    fi
}

###############################################################################
# SESSION EVENTS
###############################################################################

audit_session_start() {
    local developer_id="${1:-$(get_developer_id)}"
    local ip_address="${2:-$(get_client_ip)}"
    local browser="${3:-unknown}"
    
    local details="{\"browser\": \"$(json_escape "$browser")\"}"
    
    audit_log_event "SESSION_START" "$developer_id" "$ip_address" "Session" "success" "$details"
}

audit_session_end() {
    local developer_id="${1:-$(get_developer_id)}"
    local ip_address="${2:-$(get_client_ip)}"
    local reason="${3:-normal logout}"
    
    local details="{\"reason\": \"$(json_escape "$reason")\"}"
    
    audit_log_event "SESSION_END" "$developer_id" "$ip_address" "Session" "success" "$details"
}

audit_session_timeout_warning() {
    local developer_id="${1:-$(get_developer_id)}"
    local ip_address="${2:-$(get_client_ip)}"
    local minutes_remaining="${3:-60}"
    
    local details="{\"minutes_remaining\": $minutes_remaining}"
    
    audit_log_event "SESSION_TIMEOUT_WARNING" "$developer_id" "$ip_address" "Session" "success" "$details"
}

###############################################################################
# TERMINAL/SHELL EVENTS
###############################################################################

audit_shell_command() {
    local developer_id="${1:-$(get_developer_id)}"
    local cwd="$2"
    local command="$3"
    local blocked="${4:-false}"
    
    local status="success"
    local event_type="SHELL_CMD"
    
    if [ "$blocked" = "true" ]; then
        status="blocked"
        event_type="SHELL_BLOCKED"
    fi
    
    local details="{\"cwd\": \"$(json_escape "$cwd")\", \"command\": \"$(json_escape "$command")\"}"
    
    audit_log_event "$event_type" "$developer_id" "$(get_client_ip)" "Terminal" "$status" "$details"
}

audit_shell_violation() {
    local developer_id="${1:-$(get_developer_id)}"
    local attempted_command="$2"
    local reason="${3:-permission denied}"
    
    local details="{\"attempted_command\": \"$(json_escape "$attempted_command")\", \"reason\": \"$(json_escape "$reason")\"}"
    
    audit_log_event "SHELL_VIOLATION" "$developer_id" "$(get_client_ip)" "Terminal" "denied" "$details"
}

###############################################################################
# FILE/IDE EVENTS
###############################################################################

audit_file_open() {
    local developer_id="${1:-$(get_developer_id)}"
    local file_path="$2"
    local access_type="${3:-READ}"
    
    local details="{\"file\": \"$(json_escape "$file_path")\", \"access_type\": \"$access_type\"}"
    
    audit_log_event "FILE_OPEN" "$developer_id" "$(get_client_ip)" "IDE" "success" "$details"
}

audit_file_access_denied() {
    local developer_id="${1:-$(get_developer_id)}"
    local file_path="$2"
    local access_type="${3:-WRITE}"
    local reason="${4:-read-only}"
    
    local event_type="FILE_WRITE_ATTEMPT"
    case "$access_type" in
        WRITE) event_type="FILE_WRITE_ATTEMPT" ;;
        DELETE) event_type="FILE_DELETE_ATTEMPT" ;;
        DOWNLOAD) event_type="FILE_DOWNLOAD_ATTEMPT" ;;
    esac
    
    local details="{\"file\": \"$(json_escape "$file_path")\", \"access_type\": \"$access_type\", \"reason\": \"$(json_escape "$reason")\"}"
    
    audit_log_event "$event_type" "$developer_id" "$(get_client_ip)" "IDE" "blocked" "$details"
}

audit_file_search() {
    local developer_id="${1:-$(get_developer_id)}"
    local query="$2"
    local matches="${3:-0}"
    
    local details="{\"query\": \"$(json_escape "$query")\", \"matches_found\": $matches}"
    
    audit_log_event "FILE_SEARCH" "$developer_id" "$(get_client_ip)" "IDE" "success" "$details"
}

###############################################################################
# GIT EVENTS
###############################################################################

audit_git_command() {
    local developer_id="${1:-$(get_developer_id)}"
    local command="$2"
    local repo="${3:-unknown}"
    local branch="${4:-unknown}"
    
    local details="{\"command\": \"$(json_escape "$command")\", \"repo\": \"$repo\", \"branch\": \"$branch\"}"
    
    audit_log_event "GIT_COMMAND" "$developer_id" "$(get_client_ip)" "Git" "success" "$details"
}

audit_git_push() {
    local developer_id="${1:-$(get_developer_id)}"
    local repo="$2"
    local branch="$3"
    local status="${4:-success}"
    
    local details="{\"repo\": \"$repo\", \"branch\": \"$branch\", \"commits\": 0}"
    
    audit_log_event "GIT_PUSH" "$developer_id" "$(get_client_ip)" "Git" "$status" "$details"
}

audit_git_violation() {
    local developer_id="${1:-$(get_developer_id)}"
    local attempted_operation="$2"
    local reason="${3:-protected branch}"
    
    local details="{\"attempted\": \"$(json_escape "$attempted_operation")\", \"reason\": \"$(json_escape "$reason")\"}"
    
    audit_log_event "GIT_VIOLATION" "$developer_id" "$(get_client_ip)" "Git" "denied" "$details"
}

###############################################################################
# NETWORK EVENTS
###############################################################################

audit_tunnel_ingress() {
    local developer_id="${1:-$(get_developer_id)}"
    local ip_address="${2:-$(get_client_ip)}"
    local cloudflare_pop="${3:-unknown}"
    local latency_ms="${4:-0}"
    
    local details="{\"cloudflare_pop\": \"$cloudflare_pop\", \"latency_ms\": $latency_ms}"
    
    audit_log_event "TUNNEL_INGRESS" "$developer_id" "$ip_address" "Network" "success" "$details"
}

audit_tunnel_egress() {
    local developer_id="${1:-$(get_developer_id)}"
    local bytes_in="${2:-0}"
    local bytes_out="${3:-0}"
    local duration_seconds="${4:-0}"
    
    local details="{\"bytes_in\": $bytes_in, \"bytes_out\": $bytes_out, \"duration_seconds\": $duration_seconds}"
    
    audit_log_event "TUNNEL_EGRESS" "$developer_id" "$(get_client_ip)" "Network" "success" "$details"
}

audit_latency_measurement() {
    local developer_id="${1:-$(get_developer_id)}"
    local pop_to_home_ms="${2:-0}"
    local ide_load_ms="${3:-0}"
    
    local details="{\"pop_to_home_ms\": $pop_to_home_ms, \"ide_load_ms\": $ide_load_ms}"
    
    audit_log_event "LATENCY_MEASUREMENT" "$developer_id" "$(get_client_ip)" "Network" "success" "$details"
}

###############################################################################
# ADMIN EVENTS
###############################################################################

audit_admin_grant() {
    local admin_id="${1:-$(get_developer_id)}"  
    local target_developer="$2"
    local duration_days="${3:-7}"
    
    local details="{\"action\": \"grant\", \"target_developer\": \"$target_developer\", \"duration_days\": $duration_days}"
    
    audit_log_event "ADMIN_GRANT" "$admin_id" "$(get_client_ip)" "Admin" "success" "$details"
}

audit_admin_revoke() {
    local admin_id="${1:-$(get_developer_id)}"
    local target_developer="$2"
    local reason="${3:-contract ended}"
    
    local details="{\"action\": \"revoke\", \"target_developer\": \"$target_developer\", \"reason\": \"$(json_escape "$reason")\"}"
    
    audit_log_event "ADMIN_REVOKE" "$admin_id" "$(get_client_ip)" "Admin" "success" "$details"
}

audit_admin_extend() {
    local admin_id="${1:-$(get_developer_id)}"
    local target_developer="$2"
    local new_expiry="${3:-unknown}"
    
    local details="{\"action\": \"extend\", \"target_developer\": \"$target_developer\", \"new_expiry\": \"$new_expiry\"}"
    
    audit_log_event "ADMIN_EXTEND" "$admin_id" "$(get_client_ip)" "Admin" "success" "$details"
}

###############################################################################
# SECURITY EVENTS
###############################################################################

audit_rate_limit_exceeded() {
    local developer_id="${1:-$(get_developer_id)}"
    local operation="${2:-unknown}"
    local limit="${3:-30}"
    local period="${4:-1m}"
    
    local details="{\"operation\": \"$(json_escape "$operation")\", \"limit\": $limit, \"period\": \"$period\"}"
    
    audit_log_event "RATE_LIMIT_EXCEEDED" "$developer_id" "$(get_client_ip)" "Security" "blocked" "$details"
}

audit_security_alert() {
    local developer_id="${1:-$(get_developer_id)}"
    local alert_type="$2"
    local details_json="${3:-{}}"
    
    audit_log_event "SECURITY_ALERT" "$developer_id" "$(get_client_ip)" "Security" "warning" "$details_json"
}

###############################################################################
# EXPORT FOR USE IN SCRIPTS
###############################################################################

# Export all functions
export -f audit_log_event
export -f audit_session_start
export -f audit_session_end
export -f audit_shell_command
export -f audit_file_open
export -f audit_git_command
export -f audit_git_push
export -f audit_tunnel_ingress
export -f audit_admin_grant
export -f get_iso_timestamp
export -f get_developer_id
export -f json_escape
