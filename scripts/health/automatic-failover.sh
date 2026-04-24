#!/usr/bin/env bash
# @file        scripts/health/automatic-failover.sh
# @module      health/failover
# @description Automated health-based failover monitoring for HAProxy nodes.
# @owner       platform
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

PRIMARY_HOST="${PRIMARY_HOST:-primary.prod.internal}"
REPLICA_HOST="${REPLICA_HOST:-replica.prod.internal}"
HAPROXY_STATS_URL="${HAPROXY_STATS_URL:-http://localhost:8404/haproxy-stats;csv}"
HAPROXY_USER="${HAPROXY_USER:-admin}"
HAPROXY_PASS="${HAPROXY_PASS:-${HAPROXY_PASSWORD:-}}"

if [[ -z "${HAPROXY_PASS}" ]]; then
    log_fatal "Missing required HAProxy credentials. Set HAPROXY_PASS or HAPROXY_PASSWORD."
fi

log_info "Automatic Failover: Phase 7d-003"

# 1. Check if Primary node is unhealthy
primary_status=$(curl -u "$HAPROXY_USER:$HAPROXY_PASS" -sfL "$HAPROXY_STATS_URL" | grep "code_server_backend,primary" | awk -F',' '{print $18}')

log_info "Primary status: ${primary_status}"

if [[ "$primary_status" != "UP" ]]; then
    log_warn "Primary node is down (${primary_status})"
    
    # 2. Check if Replica is healthy
    replica_status=$(curl -u "$HAPROXY_USER:$HAPROXY_PASS" -sfL "$HAPROXY_STATS_URL" | grep "code_server_backend,replica" | awk -F',' '{print $18}')
    
    log_info "Replica status: ${replica_status}"
    
    if [[ "$replica_status" == "UP" ]]; then
        log_warn "Failover triggered: Primary down, Replica promoted to active."
        # HAProxy handles the traffic routing, this script is for alerting and incident tracking
        
        # Slack/Teams integration (optional)
        # curl -X POST $SLACK_WEBHOOK -d '{"text": "Failover Triggered: Primary down, Replica promoted."}'
        
        # Create GitHub Incident
        if command -v gh &> /dev/null; then
            gh issue create --repo kushin77/code-server --title "🚨 INCIDENT: Automatic Failover Triggered" \
              --body "Primary node ${PRIMARY_HOST} is ${primary_status}. Replica node ${REPLICA_HOST} is ${replica_status} and has been promoted to active. Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        fi
    else
        log_fatal "Both Primary and Replica are down. Service outage active."
        exit 1
    fi
else
    log_info "Primary node healthy (${primary_status}). Service operating normally."
fi

exit 0
