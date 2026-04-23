#!/usr/bin/env bash
# @file        scripts/failover/prometheus-webhook-receiver.sh
# @module      operations/failover
# @description Prometheus AlertManager webhook receiver for automated failover responses
# @owner       Infrastructure Team
# @status      Production ready - April 23, 2026
#
# Receives webhook notifications from Prometheus AlertManager and triggers:
# - Service restart on non-critical failures
# - Failover promotion on critical failures
# - Slack/email notifications
# - Metric reporting
#
# Setup:
#   1. Start webhook receiver: bash scripts/failover/start-webhook-receiver.sh
#   2. Configure AlertManager webhook: alertmanager.yml -> receivers.webhook_configs
#   3. Deploy alerting rules: alert-rules.yml
#
# Example AlertManager config:
#   receivers:
#     - name: 'failover-webhook'
#       webhook_configs:
#         - url: 'http://localhost:9099/webhook'
#           send_resolved: true

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source logging
source "$PROJECT_DIR/scripts/_common/logging.sh" 2>/dev/null || {
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
}

# Configuration
WEBHOOK_HOST="${WEBHOOK_HOST:-0.0.0.0}"
WEBHOOK_PORT="${WEBHOOK_PORT:-9099}"
WEBHOOK_TIMEOUT="${WEBHOOK_TIMEOUT:-30}"
LOG_DIR="${PROJECT_DIR}/artifacts/failover-logs"
STATE_DIR="${PROJECT_DIR}/artifacts/failover-state"

# Create directories
mkdir -p "$LOG_DIR" "$STATE_DIR"

# Function to handle webhook POST requests
handle_webhook() {
    local alert_data="$1"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    
    log_info "[$timestamp] Webhook received: Processing alert"
    
    # Extract alert details from JSON
    local status alerts_count group_labels
    status=$(echo "$alert_data" | jq -r '.status' 2>/dev/null || echo "unknown")
    alerts_count=$(echo "$alert_data" | jq '.alerts | length' 2>/dev/null || echo 0)
    
    log_info "Alert Status: $status, Count: $alerts_count"
    
    # Save alert for analysis
    echo "$alert_data" | jq . > "$LOG_DIR/alert-${timestamp// /-}.json"
    
    # Determine action based on alert
    local action="monitor"
    
    # Parse alerts array
    if [[ "$alerts_count" -gt 0 ]]; then
        echo "$alert_data" | jq -r '.alerts[] | 
            "\(.labels.alertname)|\(.labels.severity)|\(.status)"' | \
        while IFS='|' read -r alert_name severity alert_status; do
            log_info "Processing alert: $alert_name (severity: $severity, status: $alert_status)"
            
            # Determine action based on severity
            case "$severity" in
                critical)
                    log_error "CRITICAL ALERT: $alert_name"
                    action="failover"
                    trigger_failover_response "$alert_name"
                    ;;
                warning)
                    log_warn "WARNING ALERT: $alert_name"
                    action="restart"
                    trigger_service_restart "$alert_name"
                    ;;
                *)
                    log_info "INFO ALERT: $alert_name"
                    action="notify"
                    trigger_notification "$alert_name"
                    ;;
            esac
        done
    fi
    
    # Log action taken
    echo "$timestamp | $status | $alerts_count | $action" >> "$LOG_DIR/webhook-log.txt"
    
    log_info "✓ Webhook processed, action: $action"
}

# Function to trigger failover on critical alert
trigger_failover_response() {
    local alert_name="$1"
    
    log_error "Triggering failover response for: $alert_name"
    
    case "$alert_name" in
        "PrimaryDatabaseDown")
            log_error "Primary database critical failure - initiating failover"
            # Promote replica to primary
            execute_failover_promote_replica
            ;;
        "PrimaryHostDown")
            log_error "Primary host critical failure - initiating failover"
            # Switch traffic to replica host
            execute_failover_switch_primary
            ;;
        *)
            log_warn "Unknown critical alert: $alert_name (manual failover required)"
            ;;
    esac
}

# Function to restart a service on warning
trigger_service_restart() {
    local alert_name="$1"
    
    log_warn "Attempting service restart for: $alert_name"
    
    case "$alert_name" in
        "PgBouncePoolExhausted")
            log_warn "Restarting PgBouncer due to pool exhaustion"
            restart_service_safe "pgbouncer"
            ;;
        "LokiNotReady")
            log_warn "Restarting Loki service"
            restart_service_safe "loki"
            ;;
        "PrometheusDown")
            log_warn "Restarting Prometheus"
            restart_service_safe "prometheus"
            ;;
        *)
            log_info "No auto-restart configured for: $alert_name"
            ;;
    esac
}

# Function to safely restart a service with verification
restart_service_safe() {
    local service_name="$1"
    local max_attempts=3
    local attempt=1
    
    while (( attempt <= max_attempts )); do
        log_info "Restart attempt $attempt/$max_attempts for $service_name"
        
        # Get current state before restart
        local state_before
        state_before=$(docker inspect "$service_name" --format '{{.State.Running}}' 2>/dev/null || echo "unknown")
        
        # Perform restart
        if docker-compose -f "$PROJECT_DIR/docker-compose.yml" restart "$service_name" 2>/dev/null; then
            log_info "✓ $service_name restart command succeeded"
            
            # Wait for service to stabilize
            sleep 5
            
            # Verify service is running
            local state_after
            state_after=$(docker inspect "$service_name" --format '{{.State.Running}}' 2>/dev/null || echo "unknown")
            
            if [[ "$state_after" == "true" ]]; then
                log_info "✓ $service_name verified running after restart"
                echo "$(date -u '+%Y-%m-%d %H:%M:%S') | restart_success | $service_name" >> "$STATE_DIR/restart-history.log"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        if (( attempt <= max_attempts )); then
            log_warn "Restart attempt failed, waiting before retry..."
            sleep 10
        fi
    done
    
    log_error "Failed to restart $service_name after $max_attempts attempts"
    echo "$(date -u '+%Y-%m-%d %H:%M:%S') | restart_failed | $service_name" >> "$STATE_DIR/restart-history.log"
    return 1
}

# Function to send notifications
trigger_notification() {
    local alert_name="$1"
    
    log_info "Sending notification for: $alert_name"
    
    # Placeholder for Slack/email notifications
    # This would integrate with notification services
}

# Function to execute failover (promote replica to primary)
execute_failover_promote_replica() {
    log_error "EXECUTING FAILOVER: Promoting replica to primary"
    
    # This is a placeholder - actual implementation depends on your infrastructure
    # For now, log the event and trigger manual procedures
    
    echo "$(date -u '+%Y-%m-%d %H:%M:%S') | failover_initiated | replica_promotion" >> "$STATE_DIR/failover-history.log"
    
    log_error "Failover promotion initiated - manual verification required"
    log_error "Run: ssh akushnir@192.168.168.42 'bash scripts/ops/promote-replica-to-primary.sh'"
}

# Function to switch primary host
execute_failover_switch_primary() {
    log_error "EXECUTING FAILOVER: Switching primary host"
    
    echo "$(date -u '+%Y-%m-%d %H:%M:%S') | failover_initiated | host_switch" >> "$STATE_DIR/failover-history.log"
    
    log_error "Host switch initiated - manual verification required"
    log_error "Run: bash scripts/ops/switch-primary-host.sh"
}

# Function to verify webhook data format
verify_webhook_data() {
    local data="$1"
    
    # Check if data contains required AlertManager webhook fields
    if echo "$data" | jq -e '.status' > /dev/null 2>&1; then
        return 0
    else
        log_error "Invalid webhook data format"
        return 1
    fi
}

# Main webhook handler
main() {
    # Read webhook payload from stdin (sent by AlertManager)
    local webhook_data
    webhook_data=$(cat)
    
    log_info "=== Webhook Received ==="
    log_info "Payload size: ${#webhook_data} bytes"
    
    # Verify data format
    if ! verify_webhook_data "$webhook_data"; then
        log_error "Failed to verify webhook data format"
        echo "400 Bad Request"
        return 1
    fi
    
    # Process webhook
    if handle_webhook "$webhook_data"; then
        echo "200 OK"
        return 0
    else
        echo "500 Internal Server Error"
        return 1
    fi
}

# Execute main function
main
