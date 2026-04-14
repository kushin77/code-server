#!/bin/bash

################################################################################
# Phase 16: 24-Hour Production Baseline Monitoring
#
# Objective: Collect comprehensive metrics over 24 hours to establish production
#            baseline, validate SLO compliance, and demonstrate system stability
#
# Output: Hourly metrics log + final baseline report
#
# Usage: bash phase-16-baseline-monitoring.sh [OUTPUT_DIR] [DURATION_HOURS]
#        Default: 24 hours, output to ./phase-16-metrics/
#
################################################################################

set -e

# Configuration
OUTPUT_DIR="${1:-.}/phase-16-metrics"
DURATION_HOURS="${2:-24}"
SAMPLE_INTERVAL=60  # seconds between samples
TOTAL_SAMPLES=$((DURATION_HOURS * 60))

PROMETHEUS_URL="http://192.168.168.31:9090"
GRAFANA_URL="http://192.168.168.31:3000"
PRODUCTION_HOST="192.168.168.31"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# Setup
mkdir -p "$OUTPUT_DIR"
METRICS_LOG="$OUTPUT_DIR/metrics-$(date +%Y%m%d-%H%M%S).log"
ALERT_LOG="$OUTPUT_DIR/alerts-$(date +%Y%m%d-%H%M%S).log"
EVENTS_LOG="$OUTPUT_DIR/events-$(date +%Y%m%d-%H%M%S).log"

log "========================================"
log "Phase 16: 24-Hour Baseline Monitoring"
log "========================================"
log "Output Directory: $OUTPUT_DIR"
log "Duration: $DURATION_HOURS hours"
log "Sample Interval: $SAMPLE_INTERVAL seconds"
log "Total Samples: $TOTAL_SAMPLES"
log "Production Host: $PRODUCTION_HOST"
log ""

# Header for metrics log
cat > "$METRICS_LOG" << 'EOF'
timestamp,service,cpu_pct,memory_mb,memory_pct,container_status
EOF

cat > "$ALERT_LOG" << 'EOF'
timestamp,alert_name,severity,status,description
EOF

cat > "$EVENTS_LOG" << 'EOF'
timestamp,event_type,service,details
EOF

# Function to collect metrics from container
collect_container_metrics() {
    local service=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Get metrics from docker via SSH
    local metrics=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no akushnir@$PRODUCTION_HOST \
        "docker stats --no-stream --format 'table {{.Names}}\t{{.CPUPerc}}\t{{.MemUsage}}' 2>/dev/null | grep $service || echo 'offline'" 2>/dev/null)

    if [ "$metrics" != "offline" ]; then
        # Parse metrics
        local cpu=$(echo "$metrics" | awk '{print $2}' | sed 's/%//')
        local mem_usage=$(echo "$metrics" | awk '{print $4}' | sed 's/M.*//')

        # Get total memory for percentage
        local total_mem=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no akushnir@$PRODUCTION_HOST \
            "free -m | grep Mem | awk '{print \$2}'" 2>/dev/null)

        local mem_pct=$((mem_usage * 100 / total_mem))

        echo "$timestamp,$service,$cpu,$mem_usage,$mem_pct,running"
        return 0
    else
        echo "$timestamp,$service,0,0,0,offline"
        return 1
    fi
}

# Function to collect Prometheus metrics
collect_prometheus_metrics() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Collect key metrics from Prometheus
    local p99_latency=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=histogram_quantile(0.99,rate(request_latency_seconds_bucket[5m]))" 2>/dev/null | \
        jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")

    local error_rate=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=rate(http_requests_total{status=~'5..'}[5m])" 2>/dev/null | \
        jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")

    local throughput=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=rate(http_requests_total[1m])" 2>/dev/null | \
        jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")

    echo "$timestamp,prometheus_p99_latency=$p99_latency,error_rate=$error_rate,throughput=$throughput"
}

# Function to check for alerts
check_alerts() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Get active alerts from AlertManager
    curl -s "http://192.168.168.31:9093/api/v1/alerts?state=active" 2>/dev/null | \
        jq -r '.data[] | "\(.labels.alertname),\(.labels.severity),\(.state),\(.annotations.description)"' 2>/dev/null | \
        while IFS=',' read -r alert_name severity state description; do
            echo "$timestamp,$alert_name,$severity,$state,$description" >> "$ALERT_LOG"
        done
}

# Function to check container health
check_container_health() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no akushnir@$PRODUCTION_HOST \
        "docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null" 2>/dev/null | tail -n +2 | \
        while IFS=$'\t' read -r container status; do
            [ -z "$container" ] && continue

            if [[ ! $status =~ "Up" ]]; then
                echo "$timestamp,container_health_check,$container,$status" >> "$EVENTS_LOG"
            fi
        done
}

# Main monitoring loop
log "Starting metrics collection..."
success "Metrics logging to: $METRICS_LOG"
success "Alerts logging to: $ALERT_LOG"
success "Events logging to: $EVENTS_LOG"
echo ""

START_TIME=$(date +%s)
SAMPLE_COUNT=0

while [ $SAMPLE_COUNT -lt $TOTAL_SAMPLES ]; do
    SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
    ELAPSED=$(($(date +%s) - START_TIME))
    REMAINING=$((DURATION_HOURS * 3600 - ELAPSED))
    REMAINING_MINS=$((REMAINING / 60))

    # Progress indicator
    if [ $((SAMPLE_COUNT % 10)) -eq 0 ]; then
        log "Sample $SAMPLE_COUNT/$TOTAL_SAMPLES - Time elapsed: $((ELAPSED / 60))min - Remaining: ${REMAINING_MINS}min"
    fi

    # Collect metrics from each service
    for service in code-server prometheus grafana redis alertmanager caddy oauth2-proxy ssh-proxy promtail loki ollama; do
        METRICS=$(collect_container_metrics "$service" 2>/dev/null || echo "")
        [ -n "$METRICS" ] && echo "$METRICS" >> "$METRICS_LOG"
    done

    # Collect Prometheus metrics every 5 samples (5 minutes)
    if [ $((SAMPLE_COUNT % 5)) -eq 0 ]; then
        PROM_METRICS=$(collect_prometheus_metrics 2>/dev/null)
        [ -n "$PROM_METRICS" ] && echo "$PROM_METRICS" >> "$METRICS_LOG"
    fi

    # Check for alerts every 10 samples (10 minutes)
    if [ $((SAMPLE_COUNT % 10)) -eq 0 ]; then
        check_alerts 2>/dev/null
    fi

    # Check container health every 20 samples (20 minutes)
    if [ $((SAMPLE_COUNT % 20)) -eq 0 ]; then
        check_container_health 2>/dev/null
    fi

    # Sleep before next sample
    sleep $SAMPLE_INTERVAL
done

success "Metrics collection complete!"
log ""
log "Summary:"
log "- Metrics log: $METRICS_LOG"
log "- Alert log: $ALERT_LOG"
log "- Event log: $EVENTS_LOG"
log ""

# Calculate statistics
log "Calculating baseline statistics..."

# Line count
METRIC_LINES=$(wc -l < "$METRICS_LOG")
echo "Line count: $METRIC_LINES" >> "$OUTPUT_DIR/summary.txt"

# Generate summary report
cat > "$OUTPUT_DIR/baseline-summary.txt" << EOF
Phase 16: 24-Hour Baseline Metrics Summary
==========================================
Collection Period: $DURATION_HOURS hours
Start Time: $(date -d @$START_TIME '+%Y-%m-%d %H:%M:%S')
End Time: $(date '+%Y-%m-%d %H:%M:%S')
Sample Interval: $SAMPLE_INTERVAL seconds
Total Samples: $SAMPLE_COUNT

Key Metrics (Average):
EOF

# Parse and calculate averages
echo "code-server CPU: $(awk -F',' '$2=="code-server" {count++; sum+=$3} END {if (count>0) printf "%.1f%% (%d samples)\n", sum/count, count}' "$METRICS_LOG")" >> "$OUTPUT_DIR/baseline-summary.txt"
echo "prometheus CPU: $(awk -F',' '$2=="prometheus" {count++; sum+=$3} END {if (count>0) printf "%.1f%% (%d samples)\n", sum/count, count}' "$METRICS_LOG")" >> "$OUTPUT_DIR/baseline-summary.txt"
echo "grafana Memory: $(awk -F',' '$2=="grafana" {count++; sum+=$4} END {if (count>0) printf "%.0fMB (%d samples)\n", sum/count, count}' "$METRICS_LOG")" >> "$OUTPUT_DIR/baseline-summary.txt"
echo "redis CPU: $(awk -F',' '$2=="redis" {count++; sum+=$3} END {if (count>0) printf "%.1f%% (%d samples)\n", sum/count, count}' "$METRICS_LOG")" >> "$OUTPUT_DIR/baseline-summary.txt"

echo "" >> "$OUTPUT_DIR/baseline-summary.txt"
echo "Alert Summary:" >> "$OUTPUT_DIR/baseline-summary.txt"
echo "Total alerts triggered: $(wc -l < "$ALERT_LOG")" >> "$OUTPUT_DIR/baseline-summary.txt"
tail -20 "$ALERT_LOG" >> "$OUTPUT_DIR/baseline-summary.txt"

success "Summary report generated: $OUTPUT_DIR/baseline-summary.txt"
log ""
log "========================================"
log "Phase 16: Baseline Monitoring Complete"
log "========================================"
echo ""
echo "Next Steps:"
echo "1. Review baseline metrics in: $OUTPUT_DIR/"
echo "2. Compare against SLO targets"
echo "3. Investigate any anomalies"
echo "4. Generate final Phase 16 report"
