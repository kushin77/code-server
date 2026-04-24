#!/usr/bin/env bash
# @file        scripts/ops/collab-9-troubleshoot.sh
# @module      ops/collab-9-troubleshoot
# @description Troubleshooting procedures for Collab-9 issues
#
# Interactive troubleshooting guide for common Collab-9 problems:
# - Low success rates
# - High latency
# - Connection issues
# - Memory/resource issues
#
# Usage:
#   bash scripts/ops/collab-9-troubleshoot.sh [--replica IP] [--issue TYPE]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
REPLICA="${1:-192.168.168.31}"
ISSUE_TYPE="${2:-menu}"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_menu() {
  clear
  echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║  COLLAB-9 TROUBLESHOOTING GUIDE              ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
  echo ""
  echo "Target Replica: $REPLICA"
  echo ""
  echo "Choose issue to troubleshoot:"
  echo "  1. Low success rate"
  echo "  2. High latency"
  echo "  3. WebSocket connection issues"
  echo "  4. Memory/resource issues"
  echo "  5. Webhook processing failures"
  echo "  6. View recent errors"
  echo "  7. Health status check"
  echo "  8. Exit"
  echo ""
  read -p "Choice [1-8]: " choice

  case $choice in
    1) troubleshoot_low_success_rate ;;
    2) troubleshoot_high_latency ;;
    3) troubleshoot_websocket_issues ;;
    4) troubleshoot_resource_issues ;;
    5) troubleshoot_webhook_failures ;;
    6) view_recent_errors ;;
    7) check_health_status ;;
    8) log_info "Exiting..." && exit 0 ;;
    *) log_error "Invalid choice" && sleep 2 && print_menu ;;
  esac
}

troubleshoot_low_success_rate() {
  echo ""
  echo -e "${YELLOW}Troubleshooting: Low Success Rate${NC}"
  echo "─────────────────────────────────────"
  echo ""

  # Fetch metrics
  echo "Fetching metrics from $REPLICA..."
  local metrics=$(curl -s "http://${REPLICA}:3000/metrics/github-task-sync" 2>/dev/null || echo "{}")

  local webhook_success=$(echo "$metrics" | jq '.webhook.successRate // "N/A"' 2>/dev/null)
  local event_success=$(echo "$metrics" | jq '.events.successRate // "N/A"' 2>/dev/null)
  local ws_success=$(echo "$metrics" | jq '.websocket.messageSuccessRate // "N/A"' 2>/dev/null)

  echo "Current Success Rates:"
  echo "  Webhook: $webhook_success (target: >95%)"
  echo "  Events: $event_success (target: >95%)"
  echo "  WebSocket: $ws_success (target: >95%)"
  echo ""

  # Check for errors
  echo "Recent errors in audit log:"
  local errors=$(curl -s "http://${REPLICA}:3000/audit/errors?limit=5" 2>/dev/null | jq '.data.events[].context' 2>/dev/null || echo "")
  
  if [[ -z "$errors" ]]; then
    echo "  No recent errors found ✓"
  else
    echo "$errors" | head -20
  fi

  echo ""
  echo "Troubleshooting Steps:"
  echo "  1. Check webhook deliveries: curl http://${REPLICA}:3000/audit/webhooks?limit=20"
  echo "  2. Check event processing: curl http://${REPLICA}:3000/audit/events?limit=20"
  echo "  3. Check container logs: ssh akushnir@${REPLICA} 'docker compose logs -f'"
  echo "  4. Restart services: ssh akushnir@${REPLICA} 'docker compose restart'"
  echo ""
  read -p "Press Enter to continue..."
  print_menu
}

troubleshoot_high_latency() {
  echo ""
  echo -e "${YELLOW}Troubleshooting: High Latency${NC}"
  echo "─────────────────────────────────────"
  echo ""

  # Fetch latency metrics
  echo "Fetching latency metrics from $REPLICA..."
  local metrics=$(curl -s "http://${REPLICA}:3000/metrics/github-task-sync" 2>/dev/null || echo "{}")

  local webhook_p95=$(echo "$metrics" | jq '.webhook.latency.p95 // "N/A"' 2>/dev/null)
  local webhook_p99=$(echo "$metrics" | jq '.webhook.latency.p99 // "N/A"' 2>/dev/null)
  local ws_p95=$(echo "$metrics" | jq '.websocket.latency.p95 // "N/A"' 2>/dev/null)

  echo "Current Latencies (p95):"
  echo "  Webhook latency: ${webhook_p95}ms (target: <1000ms)"
  echo "  Webhook p99: ${webhook_p99}ms"
  echo "  WebSocket latency: ${ws_p95}ms (target: <500ms)"
  echo ""

  echo "Troubleshooting Steps:"
  echo "  1. Check server resources:"
  echo "     ssh akushnir@${REPLICA} 'docker stats --no-stream'"
  echo "  2. Check network latency:"
  echo "     ping -c 5 $REPLICA"
  echo "  3. Check database performance:"
  echo "     ssh akushnir@${REPLICA} 'docker compose logs postgres | tail -20'"
  echo "  4. Review metrics history:"
  echo "     curl http://${REPLICA}:3000/metrics/github-task-sync/webhook"
  echo ""
  read -p "Press Enter to continue..."
  print_menu
}

troubleshoot_websocket_issues() {
  echo ""
  echo -e "${YELLOW}Troubleshooting: WebSocket Connection Issues${NC}"
  echo "─────────────────────────────────────"
  echo ""

  local metrics=$(curl -s "http://${REPLICA}:3000/metrics/github-task-sync" 2>/dev/null || echo "{}")
  local active_conns=$(echo "$metrics" | jq '.websocket.activeConnections // "N/A"' 2>/dev/null)
  local total_conns=$(echo "$metrics" | jq '.websocket.connections // "N/A"' 2>/dev/null)

  echo "WebSocket Status:"
  echo "  Active connections: $active_conns"
  echo "  Total connections (cumulative): $total_conns"
  echo ""

  echo "Troubleshooting Steps:"
  echo "  1. Check WebSocket routes:"
  echo "     ssh akushnir@${REPLICA} 'curl -s http://localhost:3000/health/ready | jq .'"
  echo "  2. Check for timeout issues in logs:"
  echo "     ssh akushnir@${REPLICA} 'docker compose logs backend | grep -i timeout | tail -20'"
  echo "  3. Check IDE client logs:"
  echo "     Check VS Code extension debug output"
  echo "  4. Verify authentication:"
  echo "     Check that WebSocket tokens are valid"
  echo ""
  read -p "Press Enter to continue..."
  print_menu
}

troubleshoot_resource_issues() {
  echo ""
  echo -e "${YELLOW}Troubleshooting: Memory/Resource Issues${NC}"
  echo "─────────────────────────────────────"
  echo ""

  echo "Checking resource usage on $REPLICA..."
  local resources=$(ssh "akushnir@${REPLICA}" "docker stats --no-stream 2>/dev/null || echo 'SSH failed'" 2>/dev/null || echo "SSH failed")

  echo "$resources" | head -20
  echo ""

  echo "Troubleshooting Steps:"
  echo "  1. Check cache sizes:"
  echo "     curl http://${REPLICA}:3000/metrics/github-task-sync/deduplication"
  echo "  2. Check audit log size:"
  echo "     ssh akushnir@${REPLICA} 'ls -lh code-server-enterprise/logs/audit/'"
  echo "  3. Check for memory leaks:"
  echo "     ssh akushnir@${REPLICA} 'docker compose logs backend | grep -i memory | tail -20'"
  echo "  4. Increase container resources:"
  echo "     Edit docker-compose.yml, set deploy.resources.limits"
  echo ""
  read -p "Press Enter to continue..."
  print_menu
}

troubleshoot_webhook_failures() {
  echo ""
  echo -e "${YELLOW}Troubleshooting: Webhook Processing Failures${NC}"
  echo "─────────────────────────────────────"
  echo ""

  local metrics=$(curl -s "http://${REPLICA}:3000/metrics/github-task-sync" 2>/dev/null || echo "{}")
  local webhook_failed=$(echo "$metrics" | jq '.webhook.failed // "N/A"' 2>/dev/null)
  local webhook_success=$(echo "$metrics" | jq '.webhook.successRate // "N/A"' 2>/dev/null)

  echo "Webhook Status:"
  echo "  Failed webhooks: $webhook_failed"
  echo "  Success rate: $webhook_success"
  echo ""

  echo "Recent webhook errors:"
  local errors=$(curl -s "http://${REPLICA}:3000/audit/webhooks?limit=10" 2>/dev/null | jq '.data.events[] | select(.outcome == "failure")' 2>/dev/null || echo "")
  
  if [[ -z "$errors" ]]; then
    echo "  No recent webhook failures ✓"
  else
    echo "$errors" | jq '.'
  fi

  echo ""
  echo "Troubleshooting Steps:"
  echo "  1. Verify webhook signature secret:"
  echo "     Check GitHub webhook settings match GITHUB_WEBHOOK_SECRET"
  echo "  2. Check webhook delivery history:"
  echo "     GitHub → Settings → Webhooks → View Deliveries"
  echo "  3. Check signature verification:"
  echo "     curl http://${REPLICA}:3000/audit/events?eventType=webhook.failed_verification"
  echo "  4. Test webhook endpoint:"
  echo "     curl -X POST http://${REPLICA}:3000/webhooks/github -H 'X-Hub-Signature-256: sha256=...' -d '{...}'"
  echo ""
  read -p "Press Enter to continue..."
  print_menu
}

view_recent_errors() {
  echo ""
  echo -e "${YELLOW}Recent Errors in Audit Log${NC}"
  echo "─────────────────────────────────────"
  echo ""

  echo "Fetching recent errors..."
  curl -s "http://${REPLICA}:3000/audit/errors?limit=20" 2>/dev/null | jq '.data.events[] | {timestamp: .timestamp, errorMessage: .errorMessage, severity: .severity}' 2>/dev/null || echo "Unable to fetch errors"

  echo ""
  read -p "Press Enter to continue..."
  print_menu
}

check_health_status() {
  echo ""
  echo -e "${YELLOW}Current Health Status${NC}"
  echo "─────────────────────────────────────"
  echo ""

  echo "Fetching health status from $REPLICA..."
  curl -s "http://${REPLICA}:3000/health" 2>/dev/null | jq '.' || echo "Unable to fetch health status"

  echo ""
  read -p "Press Enter to continue..."
  print_menu
}

# Main
if [[ "$ISSUE_TYPE" == "menu" ]]; then
  print_menu
else
  case "$ISSUE_TYPE" in
    low-success) troubleshoot_low_success_rate ;;
    high-latency) troubleshoot_high_latency ;;
    websocket) troubleshoot_websocket_issues ;;
    resources) troubleshoot_resource_issues ;;
    webhooks) troubleshoot_webhook_failures ;;
    errors) view_recent_errors ;;
    health) check_health_status ;;
    *) log_error "Unknown issue type: $ISSUE_TYPE" && exit 1 ;;
  esac
fi
