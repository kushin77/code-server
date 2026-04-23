#!/usr/bin/env bash
# @file        scripts/ops/collab-9-monitoring.sh
# @module      ops/collab-9-monitoring
# @description Monitor Collab-9 health and metrics in production
#
# Real-time monitoring dashboard for Collab-9 showing:
# - Cluster health status
# - Webhook delivery metrics
# - WebSocket connection metrics
# - Error tracking
# - Active alerts
#
# Usage:
#   bash scripts/ops/collab-9-monitoring.sh [--interval 5] [--replicas 31,42]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
INTERVAL=5
REPLICAS=("192.168.168.31" "192.168.168.42")

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --interval)
      INTERVAL=$2
      shift 2
      ;;
    --replicas)
      IFS=',' read -ra REPLICAS <<<"$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ANSI colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
  clear
  echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║          COLLAB-9 PRODUCTION MONITORING DASHBOARD              ║${NC}"
  echo -e "${BLUE}║                     $(date '+%Y-%m-%d %H:%M:%S')                            ║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

get_replica_health() {
  local replica=$1
  local url="http://${replica}:3000/health"

  if curl -s -f "$url" 2>/dev/null | jq '.status' -r 2>/dev/null; then
    return 0
  else
    echo "UNAVAILABLE"
    return 1
  fi
}

get_replica_metrics() {
  local replica=$1
  local url="http://${replica}:3000/metrics/github-task-sync"

  curl -s "$url" 2>/dev/null | jq '.' 2>/dev/null || echo "null"
}

get_active_alerts() {
  local replica=$1
  local url="http://${replica}:3000/health/alerts"

  curl -s "$url" 2>/dev/null | jq '.alerts[]' -r 2>/dev/null | head -5 || echo "None"
}

print_replica_status() {
  local replica=$1
  local health=$(get_replica_health "$replica")
  
  local status_color=$GREEN
  if [[ "$health" == "degraded" ]]; then
    status_color=$YELLOW
  elif [[ "$health" == "unhealthy" ]] || [[ "$health" == "UNAVAILABLE" ]]; then
    status_color=$RED
  fi

  printf "%-30s ${status_color}%-12s${NC}\n" "Replica: $replica" "$health"
}

print_metrics() {
  local replica=$1
  
  echo -e "${BLUE}─ Metrics for $replica${NC}"

  local metrics=$(get_replica_metrics "$replica")
  
  if [[ "$metrics" == "null" ]]; then
    echo "  ⚠ Unable to fetch metrics"
    return
  fi

  # Extract key metrics
  local webhook_received=$(echo "$metrics" | jq '.webhook.received // 0' 2>/dev/null)
  local webhook_processed=$(echo "$metrics" | jq '.webhook.processed // 0' 2>/dev/null)
  local webhook_success=$(echo "$metrics" | jq '.webhook.successRate // "N/A"' 2>/dev/null)
  
  local ws_connections=$(echo "$metrics" | jq '.websocket.activeConnections // 0' 2>/dev/null)
  local ws_messages=$(echo "$metrics" | jq '.websocket.messagesSent // 0' 2>/dev/null)
  local ws_success=$(echo "$metrics" | jq '.websocket.messageSuccessRate // "N/A"' 2>/dev/null)
  
  local event_processed=$(echo "$metrics" | jq '.events.processed // 0' 2>/dev/null)
  local event_success=$(echo "$metrics" | jq '.events.successRate // "N/A"' 2>/dev/null)
  
  local dedup_hits=$(echo "$metrics" | jq '.deduplication.cacheHits // 0' 2>/dev/null)
  local dedup_rate=$(echo "$metrics" | jq '.deduplication.hitRate // "N/A"' 2>/dev/null)

  printf "  %-30s %s\n" "Webhooks Received:" "$webhook_received"
  printf "  %-30s %s\n" "Webhooks Processed:" "$webhook_processed"
  printf "  %-30s %s\n" "Webhook Success Rate:" "$webhook_success"
  echo ""
  printf "  %-30s %s\n" "Active WebSocket Connections:" "$ws_connections"
  printf "  %-30s %s\n" "WebSocket Messages Sent:" "$ws_messages"
  printf "  %-30s %s\n" "WebSocket Success Rate:" "$ws_success"
  echo ""
  printf "  %-30s %s\n" "Events Processed:" "$event_processed"
  printf "  %-30s %s\n" "Event Success Rate:" "$event_success"
  echo ""
  printf "  %-30s %s\n" "Dedup Cache Hits:" "$dedup_hits"
  printf "  %-30s %s\n" "Dedup Hit Rate:" "$dedup_rate"
}

print_alerts() {
  local replica=$1
  
  echo -e "${BLUE}─ Active Alerts for $replica${NC}"
  
  local alerts=$(get_active_alerts "$replica")
  if [[ "$alerts" == "None" ]]; then
    echo -e "  ${GREEN}No active alerts${NC}"
  else
    echo "$alerts" | while read -r alert; do
      echo -e "  ${YELLOW}⚠ $alert${NC}"
    done
  fi
}

# Main monitoring loop
while true; do
  print_header

  # Cluster status
  echo -e "${BLUE}CLUSTER STATUS${NC}"
  for replica in "${REPLICAS[@]}"; do
    print_replica_status "$replica"
  done
  echo ""

  # Detailed metrics for each replica
  for replica in "${REPLICAS[@]}"; do
    print_metrics "$replica"
    echo ""
  done

  # Alerts for each replica
  echo -e "${BLUE}ACTIVE ALERTS${NC}"
  for replica in "${REPLICAS[@]}"; do
    print_alerts "$replica"
    echo ""
  done

  echo -e "${BLUE}─ Refreshing in ${INTERVAL}s (Ctrl+C to exit)${NC}"
  sleep "$INTERVAL"
done
