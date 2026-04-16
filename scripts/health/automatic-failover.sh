#!/bin/bash
# scripts/health/automatic-failover.sh
# Part of Phase 7d-003: Health Checks & Automatic Failover

set -e

PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
HAPROXY_STATS_URL="http://localhost:8404/haproxy-stats;csv"
HAPROXY_USER="admin"
HAPROXY_PASS="admin123"

# Metadata
# Version: 1.0.0 (Phase 7d)
# Description: Automated health-based failover for HAProxy nodes

echo "--- Automatic Failover: Phase 7d-003 ---"

# 1. Check if Primary node is unhealthy
primary_status=$(curl -u "$HAPROXY_USER:$HAPROXY_PASS" -sfL "$HAPROXY_STATS_URL" | grep "code_server_backend,primary" | awk -F',' '{print $18}')

echo "[INFO] Primary status: $primary_status"

if [[ "$primary_status" != "UP" ]]; then
    echo "[ALERT] Primary node is down ($primary_status)"
    
    # 2. Check if Replica is healthy
    replica_status=$(curl -u "$HAPROXY_USER:$HAPROXY_PASS" -sfL "$HAPROXY_STATS_URL" | grep "code_server_backend,replica" | awk -F',' '{print $18}')
    
    echo "[INFO] Replica status: $replica_status"
    
    if [[ "$replica_status" == "UP" ]]; then
        echo "[ACTION] Failover triggered: Primary down, Replica promoted to active."
        # HAProxy handles the traffic routing, this script is for alerting and incident tracking
        
        # Slack/Teams integration (optional)
        # curl -X POST $SLACK_WEBHOOK -d '{"text": "Failover Triggered: Primary down, Replica promoted."}'
        
        # Create GitHub Incident
        if command -v gh &> /dev/null; then
            gh issue create --repo kushin77/code-server --title "🚨 INCIDENT: Automatic Failover Triggered" \
              --body "Primary node $PRIMARY_HOST is $primary_status. Replica node $REPLICA_HOST is $replica_status and has been promoted to active. Time: $(date)"
        fi
    else
        echo "[CRITICAL] Both Primary AND Replica are down. Service outage active."
        exit 1
    fi
else
    echo "[INFO] Primary node healthy ($primary_status). Service operating normally."
fi

exit 0
