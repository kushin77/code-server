#!/bin/bash
# Alert routing module for code-server operational monitoring
# Sends alerts to Slack, email, or local syslog based on configuration
# Supports alert levels: INFO, WARNING, CRITICAL, ERROR

set -euo pipefail

trap 'log_error "Alert router failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common functions (try multiple paths)
if [[ -f "${SCRIPT_DIR}/_common/init.sh" ]]; then
  source "${SCRIPT_DIR}/_common/init.sh"
elif [[ -f "${SCRIPT_DIR}/../_common/init.sh" ]]; then
  source "${SCRIPT_DIR}/../_common/init.sh"
else
  # Fallback if init.sh not available - provide basic logging
  log_error() { echo "ERROR: $*" >&2; }
fi

# Default alert configuration (can be overridden by env vars or config file)
ALERT_CONFIG="${ALERT_CONFIG:-.alerts/config.env}"
ALERT_HISTORY="${ALERT_HISTORY:-.alerts/history.log}"

# Alert levels (in order of severity)
declare -A ALERT_LEVEL=(
    [INFO]=1
    [WARNING]=2
    [ERROR]=3
    [CRITICAL]=4
)

# Initialize alert directory and logging
init_alerts() {
    mkdir -p "$(dirname "$ALERT_HISTORY")"
    touch "$ALERT_HISTORY"
    
    # Load configuration if it exists
    if [[ -f "$ALERT_CONFIG" ]]; then
        source "$ALERT_CONFIG"
    fi
}

# Send alert to all configured channels
# Usage: send_alert <level> <source> <title> <message> [details_json]
send_alert() {
    local level="$1"
    local source="$2"
    local title="$3"
    local message="$4"
    local details_json="${5:-{}}"
    
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    # Log to history
    log_alert_history "$timestamp" "$level" "$source" "$title" "$message"
    
    # Send to configured channels
    [[ "${ALERT_SLACK_ENABLED:=false}" == "true" ]] && send_slack_alert "$level" "$source" "$title" "$message" "$details_json"
    [[ "${ALERT_EMAIL_ENABLED:=false}" == "true" ]] && send_email_alert "$level" "$source" "$title" "$message" "$details_json"
    [[ "${ALERT_SYSLOG_ENABLED:=true}" == "true" ]] && send_syslog_alert "$level" "$source" "$title" "$message"
}

# Log alert to local history file
log_alert_history() {
    local timestamp="$1"
    local level="$2"
    local source="$3"
    local title="$4"
    local message="$5"
    
    printf '[%s] [%s] [%s] %s - %s\n' "$timestamp" "$level" "$source" "$title" "$message" >> "$ALERT_HISTORY"
}

# Send alert to Slack webhook
send_slack_alert() {
    local level="$1"
    local source="$2"
    local title="$3"
    local message="$4"
    local details_json="${5:-{}}"
    
    [[ -z "${SLACK_WEBHOOK_URL:-}" ]] && return 0
    
    # Determine color based on level
    local color
    case "$level" in
        INFO) color="36a64f" ;;      # green
        WARNING) color="ff9900" ;;    # orange
        ERROR) color="dd0000" ;;      # red
        CRITICAL) color="aa0000" ;;   # dark red
        *) color="000000" ;;          # black
    esac
    
    # Escape special characters in title and message
    title="${title//\"/\\\"}"
    message="${message//\"/\\\"}"
    
    # Build JSON payload using printf instead of heredoc to avoid variable expansion issues
    local slack_json
    slack_json=$(printf '{
    "attachments": [
        {
            "fallback": "%s",
            "color": "%s",
            "title": "%s",
            "text": "%s",
            "fields": [
                {
                    "title": "Level",
                    "value": "%s",
                    "short": true
                },
                {
                    "title": "Source",
                    "value": "%s",
                    "short": true
                },
                {
                    "title": "Time",
                    "value": "%s",
                    "short": false
                }
            ],
            "footer": "code-server ops monitoring"
        }
    ]
}' "$title" "$color" "$title" "$message" "$level" "$source" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')")
    
    # Send to Slack
    curl -s -X POST -H 'Content-type: application/json' \
        --data "$slack_json" \
        "$SLACK_WEBHOOK_URL" > /dev/null 2>&1 || true
}

# Send alert via email
send_email_alert() {
    local level="$1"
    local source="$2"
    local title="$3"
    local message="$4"
    local details_json="${5:-{}}"
    
    [[ -z "${EMAIL_TO:-}" ]] && return 0
    
    # Check if mail command is available
    if ! command -v mail &> /dev/null; then
        return 1
    fi
    
    # Build email body
    local email_body
    email_body=$(printf "Code-Server Operational Alert\n\nAlert Level: %s\nSource: %s\nTitle: %s\nTime: %s\n\nMessage:\n%s\n\nDetails:\n%s\n\n---\nThis is an automated alert from code-server operational monitoring.\n" \
        "$level" "$source" "$title" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" "$message" "$details_json")
    
    # Send email
    echo "$email_body" | mail -s "[$level] $title" "$EMAIL_TO" 2>/dev/null || true
}

# Send alert to syslog (always available)
send_syslog_alert() {
    local level="$1"
    local source="$2"
    local title="$3"
    local message="$4"
    
    # Convert to syslog priority
    local priority
    case "$level" in
        INFO) priority="info" ;;
        WARNING) priority="warning" ;;
        ERROR) priority="err" ;;
        CRITICAL) priority="crit" ;;
        *) priority="notice" ;;
    esac
    
    logger -t "code-server-ops" -p "local0.$priority" "[$source] $title - $message"
}

# Query alert history
# Usage: query_alerts [since_minutes] [level_filter]
query_alerts() {
    local since_minutes="${1:=60}"
    local level_filter="${2:=}"
    
    if [[ ! -f "$ALERT_HISTORY" ]]; then
        log_error "Alert history file not found: $ALERT_HISTORY"
        return 1
    fi
    
    # Calculate cutoff timestamp
    local cutoff=$(date -u -d "$since_minutes minutes ago" '+%Y-%m-%dT%H:%M:%SZ')
    
    # Filter alerts
    if [[ -n "$level_filter" ]]; then
        grep "\[$level_filter\]" "$ALERT_HISTORY" | grep -E "\[$cutoff" || true
    else
        awk -v cutoff="$cutoff" '$0 ~ cutoff' "$ALERT_HISTORY" || true
    fi
}

# Get alert statistics
# Usage: alert_stats [since_minutes]
alert_stats() {
    local since_minutes="${1:=1440}"  # Default: last 24 hours
    
    if [[ ! -f "$ALERT_HISTORY" ]]; then
        printf '{"info": 0, "warning": 0, "error": 0, "critical": 0}\n'
        return 0
    fi
    
    local cutoff=$(date -u -d "$since_minutes minutes ago" '+%Y-%m-%dT%H:%M:%SZ')
    
    local info=$(awk -v cutoff="$cutoff" '$0 ~ cutoff && /\[INFO\]/' "$ALERT_HISTORY" | wc -l)
    local warning=$(awk -v cutoff="$cutoff" '$0 ~ cutoff && /\[WARNING\]/' "$ALERT_HISTORY" | wc -l)
    local error=$(awk -v cutoff="$cutoff" '$0 ~ cutoff && /\[ERROR\]/' "$ALERT_HISTORY" | wc -l)
    local critical=$(awk -v cutoff="$cutoff" '$0 ~ cutoff && /\[CRITICAL\]/' "$ALERT_HISTORY" | wc -l)
    
    printf '{"info": %d, "warning": %d, "error": %d, "critical": %d}\n' \
        "$info" "$warning" "$error" "$critical"
}

# Suppress duplicate alerts (same source/title within time window)
# Usage: should_alert <source> <title> [window_seconds]
should_alert() {
    local source="$1"
    local title="$2"
    local window_seconds="${3:=300}"  # Default: 5 minutes
    
    if [[ ! -f "$ALERT_HISTORY" ]]; then
        return 0  # Should alert (no history)
    fi
    
    # Check if this alert was recently sent
    local cutoff=$(date -u -d "$window_seconds seconds ago" '+%Y-%m-%dT%H:%M:%SZ')
    local recent_count=$(grep -c "\[$cutoff.*\[$source\] $title" "$ALERT_HISTORY" 2>/dev/null || echo 0)
    
    [[ $recent_count -eq 0 ]]
}

# Main execution for direct invocation
main() {
    init_alerts
    
    if [[ $# -lt 3 ]]; then
        log_error "Usage: alert-router.sh <level> <source> <title> [message] [details_json]"
        log_error "Example: alert-router.sh WARNING drift-watchdog 'Drift detected' 'Found 5 drifted resources' '{...}'"
        return 1
    fi
    
    send_alert "$@"
}

# Only run main if directly invoked (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
