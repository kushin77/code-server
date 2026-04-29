#!/bin/bash
# Healthcheck Event Streamer
# Streams container healthcheck status changes to Loki for centralized monitoring and alerting
#
# Purpose:
#   - Poll docker healthcheck states on an interval
#   - Detect state transitions (healthy → unhealthy, etc.)
#   - Stream events to Loki with structured labels (service, host, status, reason)
#   - Enable historical queries and alerting on health degradation
#
# Usage:
#   ./scripts/healthcheck-event-streamer.sh [OPTIONS]
#
# Options:
#   --interval N           Poll interval in seconds (default: 30)
#   --loki-url URL         Loki push URL (default: http://localhost:3100/loki/api/v1/push)
#   --host HOSTNAME        Override hostname (default: $(hostname))
#   --dry-run              Show what would be sent without posting to Loki
#   --debug                Verbose output for debugging
#   --help                 Show this help message
#
# Environment Variables:
#   LOKI_URL               Override default Loki URL
#   POLL_INTERVAL          Override default poll interval (seconds)
#
# Examples:
#   # Start streaming to local Loki
#   ./scripts/healthcheck-event-streamer.sh --interval 30
#
#   # Stream to remote Loki with dry-run
#   ./scripts/healthcheck-event-streamer.sh --loki-url http://loki.example.com:3100/loki/api/v1/push --dry-run
#
#   # Run in background (systemd or cron will handle lifecycle)
#   ./scripts/healthcheck-event-streamer.sh &
#
# Log Queries (in Loki):
#   - All healthchecks: {job="healthcheck-monitor"}
#   - Service-specific: {job="healthcheck-monitor", service="vault"}
#   - Status changes: {job="healthcheck-monitor"} | json | old_status != new_status
#   - Failures: {job="healthcheck-monitor", status="unhealthy"} | json
#   - Restart events: {job="healthcheck-monitor"} | json | restart_count > 0

set -euo pipefail
trap 'cleanup' EXIT

# Configuration
POLL_INTERVAL="${POLL_INTERVAL:-30}"
LOKI_URL="${LOKI_URL:-http://localhost:3100/loki/api/v1/push}"
HOSTNAME="${HOSTNAME:-$(hostname)}"
DRY_RUN=false
DEBUG=false
STATE_FILE="/tmp/healthcheck-streamer-state.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log() {
  echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"
}

debug() {
  if [[ "$DEBUG" == "true" ]]; then
    echo -e "${YELLOW}[DEBUG]${NC} $*"
  fi
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
  echo -e "${GREEN}[OK]${NC} $*"
}

cleanup() {
  debug "Cleaning up..."
}

show_help() {
  head -48 "$0" | tail -40
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --interval)
      POLL_INTERVAL="$2"
      shift 2
      ;;
    --loki-url)
      LOKI_URL="$2"
      shift 2
      ;;
    --host)
      HOSTNAME="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Initialize state file
initialize_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "{}" > "$STATE_FILE"
    debug "Initialized state file: $STATE_FILE"
  fi
}

# Get all containers with healthchecks
get_containers_with_healthchecks() {
  docker ps --format '{{json .}}' | while read -r line; do
    name=$(echo "$line" | jq -r '.Names')
    [[ "$name" == "code-server-"* ]] && echo "$name"
  done
}

# Get healthcheck status for container
get_healthcheck_status() {
  local container="$1"
  
  # Fetch full container inspect
  local inspect=$(docker inspect "$container" 2>/dev/null || echo '{}')
  
  # Extract health info
  local status=$(echo "$inspect" | jq -r '.[] | .State.Health.Status // "none"' 2>/dev/null || echo "unknown")
  local restart_count=$(echo "$inspect" | jq -r '.[] | .RestartCount // 0' 2>/dev/null || echo "0")
  local last_check=$(echo "$inspect" | jq -r '.[] | .State.Health.Log[-1].End // "N/A"' 2>/dev/null || echo "N/A")
  local last_output=$(echo "$inspect" | jq -r '.[] | .State.Health.Log[-1].Output // ""' 2>/dev/null | head -c 200)
  
  # Format output
  cat <<EOF
{
  "name": "$container",
  "status": "$status",
  "restart_count": $restart_count,
  "last_check": "$last_check",
  "last_output": "$last_output"
}
EOF
}

# Build Loki push request
build_loki_push() {
  local timestamp="$1"
  local labels="$2"
  local message="$3"
  
  # Timestamp in nanoseconds
  local ns_timestamp=$((timestamp * 1000000000))
  
  cat <<EOF
{
  "streams": [
    {
      "stream": $labels,
      "values": [
        ["$ns_timestamp", "$message"]
      ]
    }
  ]
}
EOF
}

# Send event to Loki
send_to_loki() {
  local labels="$1"
  local message="$2"
  local timestamp=$(date +%s)
  
  local payload=$(build_loki_push "$timestamp" "$labels" "$message")
  
  if [[ "$DRY_RUN" == "true" ]]; then
    debug "DRY-RUN: Would send to Loki:"
    echo "$payload" | jq '.' | sed 's/^/  /'
    return 0
  fi
  
  debug "Sending to Loki: $LOKI_URL"
  
  local http_code=$(curl -s -w '%{http_code}' -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$LOKI_URL" \
    -o /dev/null 2>/dev/null || echo "000")
  
  if [[ "$http_code" == "204" ]]; then
    debug "✓ Loki accepted (HTTP 204)"
    return 0
  else
    error "Loki push failed (HTTP $http_code)"
    return 1
  fi
}

# Check and report health state
check_health_state() {
  local container="$1"
  local current_state=$(get_healthcheck_status "$container")
  
  debug "Current state for $container: $current_state"
  
  # Load previous state
  local previous_state=$(jq -r ".\"$container\" // \"{}\'" "$STATE_FILE" 2>/dev/null || echo '{}')
  
  # Extract status values
  local current_status=$(echo "$current_state" | jq -r '.status')
  local previous_status=$(echo "$previous_state" | jq -r '.status // "unknown"')
  local current_restarts=$(echo "$current_state" | jq -r '.restart_count')
  local previous_restarts=$(echo "$previous_state" | jq -r '.restart_count // 0')
  
  # Build labels for Loki
  local labels="{\"job\":\"healthcheck-monitor\",\"service\":\"$container\",\"host\":\"$HOSTNAME\",\"status\":\"$current_status\"}"
  
  # Build message
  local message
  
  # Detect state transitions
  if [[ "$previous_status" != "unknown" ]] && [[ "$current_status" != "$previous_status" ]]; then
    message="STATUS_TRANSITION: $previous_status → $current_status"
    success "[$container] $message"
    send_to_loki "$labels" "$message"
  
  # Detect restarts
  elif [[ $current_restarts -gt $previous_restarts ]]; then
    message="RESTART_DETECTED: restart_count $previous_restarts → $current_restarts"
    log "[$container] $message"
    send_to_loki "$labels" "$message"
  
  # Detect continued unhealthy
  elif [[ "$current_status" == "unhealthy" ]]; then
    message="UNHEALTHY: $(echo "$current_state" | jq -r '.last_output' | head -c 100)"
    error "[$container] $message"
    send_to_loki "$labels" "$message"
  
  # Regular healthy state
  elif [[ "$current_status" == "healthy" ]]; then
    if [[ "$previous_status" != "healthy" ]]; then
      message="RECOVERED: Now healthy"
      success "[$container] $message"
      send_to_loki "$labels" "$message"
    else
      debug "[$container] Healthy (no change)"
    fi
  fi
  
  # Save current state
  local updated_state=$(jq ".\"$container\" = $current_state" "$STATE_FILE")
  echo "$updated_state" > "$STATE_FILE"
}

# Main loop
main_loop() {
  log "Healthcheck Event Streamer started"
  log "Configuration:"
  log "  Loki URL: $LOKI_URL"
  log "  Poll interval: ${POLL_INTERVAL}s"
  log "  Hostname: $HOSTNAME"
  log "  Dry-run: $DRY_RUN"
  echo ""
  
  initialize_state
  
  # First poll to establish baseline
  log "Establishing baseline..."
  for container in $(get_containers_with_healthchecks); do
    check_health_state "$container"
  done
  
  log "Streaming started. Press Ctrl+C to stop."
  echo ""
  
  # Main polling loop
  while true; do
    sleep "$POLL_INTERVAL"
    
    debug "Poll cycle at $(date +'%H:%M:%S')"
    
    for container in $(get_containers_with_healthchecks); do
      check_health_state "$container" || true
    done
  done
}

# Execution
if [[ "${1:-}" == "--test" ]]; then
  # Test mode: single poll then exit
  log "TEST MODE: Single poll cycle"
  initialize_state
  for container in $(get_containers_with_healthchecks | head -3); do
    check_health_state "$container"
  done
  log "Test complete"
else
  main_loop
fi
