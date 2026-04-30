#!/bin/bash
# Automated Monitoring Setup

set -e
trap 'echo "[ERROR] Monitoring setup failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Monitoring setup completed"; true' EXIT

MONITORING_DIR="/home/akushnir/monitoring"
mkdir -p "$MONITORING_DIR"

# Create SLA tracking script
cat > ${MONITORING_DIR}/track-slas-automated.sh << 'SLAEOF'
#!/bin/bash
# Automated SLA Tracking (runs every 5 minutes)

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SLA_FILE="/home/akushnir/monitoring/sla-tracking.csv"

# Initialize CSV
if [ ! -f "$SLA_FILE" ]; then
  echo "timestamp,uptime_pct,api_response_ms,error_rate_pct,memory_pct,cpu_pct" > "$SLA_FILE"
fi

# Collect metrics
SERVICES=$(docker-compose ps 2>/dev/null | grep -c "Up" || echo 0)
UPTIME=$((SERVICES * 100 / 5))

API_RESPONSE=$(curl -s -w "%{time_total}" -o /dev/null -k https://kushnir.cloud/api/hermes/health 2>/dev/null || echo "999")
API_MS=$(echo "$API_RESPONSE * 1000" | bc 2>/dev/null || echo "5000")

ERROR_COUNT=$(docker-compose logs --since 5m 2>/dev/null | grep -ci "error" || echo 0)

MEMORY=$(docker stats --no-stream --no-trunc 2>/dev/null | awk 'NR>1 {gsub(/%/,"",$11); sum+=$11} END {print int(sum/NR)}' || echo "0")

CPU=$(docker stats --no-stream --no-trunc 2>/dev/null | awk 'NR>1 {gsub(/%/,"",$3); sum+=$3} END {print int(sum/NR)}' || echo "0")

# Log metrics
echo "$TIMESTAMP,$UPTIME,$API_MS,$ERROR_COUNT,$MEMORY,$CPU" >> "$SLA_FILE"

# Check thresholds
[ "$UPTIME" -lt 99 ] && echo "⚠️  ALERT: Uptime ${UPTIME}% (target 99.9%)"
[ "$API_MS" -gt 500 ] && echo "⚠️  ALERT: API ${API_MS}ms (target <500ms)"
[ "$MEMORY" -gt 70 ] && echo "⚠️  ALERT: Memory ${MEMORY}% (target <70%)"
[ "$CPU" -gt 60 ] && echo "⚠️  ALERT: CPU ${CPU}% (target <60%)"

SLAEOF
  
  chmod +x ${MONITORING_DIR}/track-slas-automated.sh
  
  # Schedule SLA tracking
  (crontab -l 2>/dev/null | grep -v track-slas-automated.sh; echo "*/5 * * * * ${MONITORING_DIR}/track-slas-automated.sh") | crontab -

