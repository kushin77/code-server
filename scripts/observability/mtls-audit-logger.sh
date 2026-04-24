#!/usr/bin/env bash
# @file        scripts/observability/mtls-audit-logger.sh
# @module      observability/audit
# @description Monitor and log mTLS connections for zero-trust audit trail - P0 #1273
#
# This script runs as a sidecar/background daemon to:
# 1. Monitor mTLS certificate usage across all containers
# 2. Log service-to-service connections
# 3. Detect certificate expiry warnings
# 4. Send events to Loki for retention and dashboards
#
# Environment:
#   AUDIT_LOG_DIR: Directory for audit logs (default: /var/log/audit)
#   LOKI_URL: Loki push gateway URL (default: http://loki:3100)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/_common/init.sh"

AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-/var/log/audit}"
AUDIT_LOG="$AUDIT_LOG_DIR/mtls-connections.log"
CERT_WARNING_LOG="$AUDIT_LOG_DIR/cert-warnings.log"
LOKI_URL="${LOKI_URL:-http://loki:3100}"
LOKI_TENANT="${LOKI_TENANT:-fabric}"
POLL_INTERVAL=30  # Poll every 30 seconds

# ============================================================================
# Helper Functions
# ============================================================================

ensure_audit_dirs() {
  mkdir -p "$AUDIT_LOG_DIR"
  touch "$AUDIT_LOG"
  touch "$CERT_WARNING_LOG"
}

log_connection() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local source_service=$1
  local source_cert=$2
  local dest_service=$3
  local dest_cert=$4
  local protocol=$5
  local action=$6
  
  local log_entry="$timestamp | $source_service | $source_cert | $dest_service | $dest_cert | $protocol | $action"
  echo "$log_entry" >> "$AUDIT_LOG"
}

log_cert_warning() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local service=$1
  local days_until_expiry=$2
  local status=$3
  
  local log_entry="$timestamp | $service | $days_until_expiry | $status"
  echo "$log_entry" >> "$CERT_WARNING_LOG"
  
  # Alert if expiry within 7 days
  if [ "$days_until_expiry" -lt 7 ] && [ "$days_until_expiry" -gt 0 ]; then
    log_warn "⚠️  Certificate for $service expires in $days_until_expiry days"
  fi
}

get_container_cert_cn() {
  local container=$1
  local cert_path=$2
  
  docker exec "$container" openssl x509 -in "$cert_path" -noout -subject 2>/dev/null | \
    sed -n 's/.*CN = \([^,/]*\).*/\1/p' || echo "UNKNOWN"
}

monitor_service_connections() {
  local service=$1
  local cert_path=$2
  
  if ! docker ps --format "table {{.Names}}" | grep -q "^$service$"; then
    return  # Container not running
  fi
  
  # Get service certificate CN
  local service_cn=$(get_container_cert_cn "$service" "$cert_path" 2>/dev/null || echo "unknown-$service")
  
  # Monitor open connections (simplified - TCP only)
  docker exec "$service" ss -tnp 2>/dev/null | tail -n +2 | while IFS= read -r line; do
    # Extract local and remote addresses
    # Format: ESTAB 0 0 127.0.0.1:6379 127.0.0.1:54321 users:(("redis",pid=1,fd=8))
    
    if echo "$line" | grep -q ESTAB; then
      # Log connection established
      log_connection "$service" "$service_cn" "remote-service" "unknown" "TCP_ESTABLISHED" "CONNECTED"
    fi
  done
}

check_certificate_expiry() {
  local service=$1
  local cert_path=$2
  
  if ! docker ps --format "table {{.Names}}" | grep -q "^$service$"; then
    return
  fi
  
  local expiry_date=$(docker exec "$service" openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
  if [ -z "$expiry_date" ]; then
    return
  fi
  
  local expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null || date -d "$expiry_date" +%s)
  local current_epoch=$(date +%s)
  local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
  
  if [ "$days_until_expiry" -le 30 ]; then
    log_cert_warning "$service" "$days_until_expiry" "EXPIRY_WARNING"
  fi
}

send_to_loki() {
  local log_file=$1
  local label_key=$2
  local label_value=$3
  
  if ! command -v curl &>/dev/null; then
    return  # curl not available
  fi
  
  # Read recent logs and send to Loki
  tail -n 100 "$log_file" | while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi
    
    # Format for Loki: JSON with timestamp and labels
    local timestamp=$(echo "$line" | cut -d' ' -f1 | xargs -I {} date -d "{}" +%s%N 2>/dev/null || echo $(($(date +%s) * 1000000000)))
    
    curl -s -X POST "$LOKI_URL/loki/api/v1/push" \
      -H "X-Loki-Tenant: $LOKI_TENANT" \
      -H "Content-Type: application/json" \
      -d "{
        \"streams\": [{
          \"stream\": {
            \"$label_key\": \"$label_value\",
            \"job\": \"mtls-audit\"
          },
          \"values\": [[\"$timestamp\", \"$line\"]]
        }]
      }" \
      &>/dev/null
  done
}

# ============================================================================
# Main Monitoring Loop
# ============================================================================

main() {
  ensure_audit_dirs
  
  log_info "Starting mTLS audit logger..."
  log_info "Audit log directory: $AUDIT_LOG_DIR"
  log_info "Poll interval: $POLL_INTERVAL seconds"
  
  # Services to monitor
  local services=(
    "redis:/run/secrets/redis-cert/cert.pem"
    "postgres:/run/secrets/postgres-cert/cert.pem"
    "caddy:/run/secrets/caddy-cert/cert.pem"
    "prometheus:/run/secrets/prometheus-cert/cert.pem"
    "code-server:/run/secrets/code-server-cert/cert.pem"
  )
  
  # Main monitoring loop
  while true; do
    for service_spec in "${services[@]}"; do
      IFS=':' read -r service cert_path <<< "$service_spec"
      
      # Monitor connections
      monitor_service_connections "$service" "$cert_path" 2>/dev/null || true
      
      # Check certificate expiry
      check_certificate_expiry "$service" "$cert_path" 2>/dev/null || true
    done
    
    # Send logs to Loki every 5 minutes
    if [ $(($(date +%s) % 300)) -lt $POLL_INTERVAL ]; then
      send_to_loki "$AUDIT_LOG" "log_type" "mtls_connections" &
      send_to_loki "$CERT_WARNING_LOG" "log_type" "cert_warnings" &
    fi
    
    sleep "$POLL_INTERVAL"
  done
}

# Handle signals gracefully
trap "log_info 'Audit logger stopping...'; exit 0" SIGTERM SIGINT

main "$@"
