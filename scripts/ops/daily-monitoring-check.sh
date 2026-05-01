#!/bin/bash
# daily_monitoring_check.sh
# Operations Team Daily Monitoring Checklist
# Run at 08:00 UTC every day
# Part of: Platform Operations Procedures

set -e

# Error handling
log_error() {
  echo "❌ ERROR: $1" >&2
}

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleaning up..."; rm -f /tmp/monitoring-daily.tmp 2>/dev/null || true' EXIT

log_info() {
  echo "ℹ️  $1"
}

echo "=== Daily Monitoring Check $(date) ===" | tee -a /tmp/monitoring-daily.log

PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"

# Check 1: Container Count
for HOST in $PRIMARY $REPLICA; do
  COUNT=$(ssh -o ConnectTimeout=10 -o BatchMode=yes akushnir@$HOST "docker ps -q | wc -l" 2>/dev/null || echo "error")
  echo "[$HOST] Containers: $COUNT (target: 43/44)" | tee -a /tmp/monitoring-daily.log
done

# Check 2: Database Replication
REP_LAG=$(ssh -o ConnectTimeout=10 -o BatchMode=yes akushnir@$PRIMARY "
  docker exec code-server-postgres psql -U postgres -c 'SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::INT;' 2>/dev/null | tail -1
" 2>/dev/null || echo "error")
echo "[PostgreSQL] Replication lag: ${REP_LAG}s (target: <5s)" | tee -a /tmp/monitoring-daily.log

# Check 3: Disk Usage
for HOST in $PRIMARY $REPLICA; do
  DISK=$(ssh -o ConnectTimeout=10 -o BatchMode=yes akushnir@$HOST "df -h / | tail -1 | awk '{print \$5}'" 2>/dev/null || echo "unknown")
  echo "[$HOST] Disk usage: $DISK (target: <70%)" | tee -a /tmp/monitoring-daily.log
done

# Check 4: Error Count (last 1h)
ERRORS=$(curl -s 'http://192.168.168.31:3100/loki/api/v1/query' \
  --data-urlencode 'query={job="docker"} | level="error"' \
  2>/dev/null | jq '.data.result | length' 2>/dev/null || echo "0")
echo "[Logs] Errors in last hour: $ERRORS (target: <10)" | tee -a /tmp/monitoring-daily.log

# Check 5: Alert Status
ACTIVE_ALERTS=$(curl -s http://192.168.168.31:9090/api/v1/alerts 2>/dev/null | jq '.data.alerts | length' 2>/dev/null || echo "0")
echo "[Alerts] Active alerts: $ACTIVE_ALERTS (target: 0)" | tee -a /tmp/monitoring-daily.log

echo "✅ Daily check complete" | tee -a /tmp/monitoring-daily.log
