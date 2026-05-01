#!/bin/bash
###############################################################################
# @file        scripts/ops/collect-baseline-metrics.sh
# @module      ops/collect-baseline-metrics
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/ops/collect-baseline-metrics.sh
# @description Collects performance metrics to establish operational baselines.
# @governance GOV-002
# Baseline Metrics Collection Script
# Collects hourly performance metrics for 24 hours to establish operational baselines

set -e

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

ARTIFACT_DIR="artifacts"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONTINUE_MODE="false"
BASELINE_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --continue)
            CONTINUE_MODE="true"
            shift
            ;;
        -h|--help)
            echo "Usage: bash scripts/ops/collect-baseline-metrics.sh [--continue]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [[ "${CONTINUE_MODE}" == "true" ]]; then
    BASELINE_DIR="$(ls -td "${ARTIFACT_DIR}"/baseline-* 2>/dev/null | head -1 || true)"
    if [[ -z "${BASELINE_DIR}" || ! -d "${BASELINE_DIR}" ]]; then
        echo "No existing baseline directory found. Run once without --continue first." >&2
        exit 1
    fi
else
    BASELINE_DIR="${ARTIFACT_DIR}/baseline-${TIMESTAMP}"
fi

echo -e "${BLUE}=== BASELINE METRICS COLLECTION ===${NC}"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Artifact Directory: ${BASELINE_DIR}"
echo ""

# Create baseline directory
mkdir -p "${BASELINE_DIR}"

# Function to collect metrics from Prometheus
collect_prometheus_metrics() {
    local metric_name=$1
    local query=$2
    local output_file=$3
    
    echo -e "${YELLOW}Collecting: ${metric_name}${NC}"
    
    # Query Prometheus for metric
    response=$(curl -s "http://localhost:9090/api/v1/query?query=${query}" 2>/dev/null || echo "{}")
    
    echo "${response}" > "${output_file}"
    echo "  ✓ Saved to ${output_file}"
}

# Function to collect Grafana dashboard data
collect_grafana_metrics() {
    local dashboard_name=$1
    local output_file=$2
    
    echo -e "${YELLOW}Collecting dashboard: ${dashboard_name}${NC}"
    
    # Export dashboard metrics (requires Grafana API access)
    # This would typically be done via: curl -H "Authorization: Bearer $GRAFANA_TOKEN" ...
    # For now, we'll use Prometheus queries instead
    
    echo "  (Dashboard metrics collected via Prometheus)"
}

# Baseline Collection Point
echo -e "${BLUE}=== T+0 BASELINE (Initial Snapshot) ===${NC}"

# OPA Metrics
collect_prometheus_metrics "OPA Decisions Rate" \
    "rate(opa_decisions_total%5B5m%5D)" \
    "${BASELINE_DIR}/opa-decisions-rate.json"

collect_prometheus_metrics "OPA Latency p95" \
    "opa_decision_duration_seconds{quantile=\"0.95\"}" \
    "${BASELINE_DIR}/opa-latency-p95.json"

collect_prometheus_metrics "OPA Error Rate" \
    "rate(opa_errors_total%5B5m%5D)" \
    "${BASELINE_DIR}/opa-error-rate.json"

# Memory Engine Metrics
collect_prometheus_metrics "Memory Search Rate" \
    "rate(memory_search_queries_total%5B5m%5D)" \
    "${BASELINE_DIR}/memory-search-rate.json"

collect_prometheus_metrics "Memory Search Latency p95" \
    "memory_search_duration_seconds{quantile=\"0.95\"}" \
    "${BASELINE_DIR}/memory-latency-p95.json"

collect_prometheus_metrics "Memory Error Rate" \
    "rate(memory_errors_total%5B5m%5D)" \
    "${BASELINE_DIR}/memory-error-rate.json"

# Kafka Metrics
collect_prometheus_metrics "Kafka Throughput" \
    "rate(kafka_messages_total%5B5m%5D)" \
    "${BASELINE_DIR}/kafka-throughput.json"

collect_prometheus_metrics "Kafka Consumer Lag" \
    "kafka_consumer_lag" \
    "${BASELINE_DIR}/kafka-consumer-lag.json"

collect_prometheus_metrics "Kafka Error Rate" \
    "rate(kafka_errors_total%5B5m%5D)" \
    "${BASELINE_DIR}/kafka-error-rate.json"

# Resource Metrics
collect_prometheus_metrics "CPU Usage" \
    "rate(process_cpu_seconds_total%5B5m%5D) * 100" \
    "${BASELINE_DIR}/cpu-usage.json"

collect_prometheus_metrics "Memory Usage" \
    "process_resident_memory_bytes / 1024 / 1024" \
    "${BASELINE_DIR}/memory-usage.json"

collect_prometheus_metrics "Disk Usage" \
    "node_filesystem_avail_bytes / node_filesystem_size_bytes * 100" \
    "${BASELINE_DIR}/disk-usage.json"

# Application Metrics
collect_prometheus_metrics "API Latency p95" \
    "http_request_duration_seconds{quantile=\"0.95\"}" \
    "${BASELINE_DIR}/api-latency-p95.json"

collect_prometheus_metrics "Application Error Rate" \
    "rate(http_requests_total{status=~\"5..\"}%5B5m%5D)" \
    "${BASELINE_DIR}/app-error-rate.json"

echo ""
echo -e "${GREEN}✓ Initial baseline snapshot collected${NC}"

# Function to create hourly baseline snapshot
create_hourly_baseline() {
    local hour=$1
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    echo -e "${BLUE}=== T+${hour}h Baseline Snapshot ===${NC}"
    echo "Timestamp: ${timestamp}"
    
    cat > "${BASELINE_DIR}/baseline-hour-${hour}.json" << EOF
{
  "timestamp": "${timestamp}",
  "hour": ${hour},
  "metrics": {
    "opa": {
      "decisions_per_sec": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/opa-decisions-rate.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')",
      "latency_p95_ms": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/opa-latency-p95.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')",
      "error_rate": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/opa-error-rate.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')"
    },
    "memory_engine": {
      "search_queries_per_sec": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/memory-search-rate.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')",
      "latency_p95_ms": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/memory-latency-p95.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')",
      "error_rate": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/memory-error-rate.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')"
    },
    "kafka": {
      "throughput_msg_sec": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/kafka-throughput.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')",
      "consumer_lag_ms": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/kafka-consumer-lag.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')",
      "error_rate": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/kafka-error-rate.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')"
    },
    "resources": {
      "cpu_percent": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/cpu-usage.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')",
      "memory_mb": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/memory-usage.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')",
      "disk_available_percent": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/disk-usage.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')"
    },
    "application": {
      "api_latency_p95_ms": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/api-latency-p95.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')",
      "error_rate": "$(grep -o '\"value\":\[[0-9.]*' ${BASELINE_DIR}/app-error-rate.json | head -1 | cut -d: -f2 | tr -d '[' || echo 'N/A')"
    }
  }
}
EOF
    
    echo "  ✓ Snapshot saved: ${BASELINE_DIR}/baseline-hour-${hour}.json"
}

# Create snapshots
if [[ "${CONTINUE_MODE}" == "true" ]]; then
    current_hour=$(find "${BASELINE_DIR}" -maxdepth 1 -name 'baseline-hour-*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
    create_hourly_baseline "${current_hour}"
else
    create_hourly_baseline 0
    create_hourly_baseline 1
fi

echo ""
echo -e "${GREEN}✓ Baseline collection initialized${NC}"
echo ""
echo "To continue monitoring for 24 hours, run:"
echo "  while true; do sleep 3600; bash scripts/ops/collect-baseline-metrics.sh --continue; done"
echo ""
echo "Baseline files saved to: ${BASELINE_DIR}/"
echo "Review metrics using: cat ${BASELINE_DIR}/baseline-hour-*.json | jq ."
echo ""

# Create baseline summary report
if [[ "${CONTINUE_MODE}" != "true" ]]; then
cat > "${BASELINE_DIR}/README.md" << 'EOF'
# Baseline Metrics Collection

This directory contains performance baseline metrics collected immediately after production deployment.

## Files

- `baseline-hour-*.json`: Hourly snapshots of all metrics
- `*-rate.json`: Raw Prometheus responses for rate metrics
- `*-latency-*.json`: Latency percentile data
- `*-error-rate.json`: Error rate metrics

## Key Metrics Baseline

### OPA Policy Engine
- Decisions/sec (rate)
- Latency p95 (ms)
- Error rate (%)

### Memory Engine
- Search queries/sec
- Latency p95 (ms)
- Error rate (%)

### Kafka Event Bus
- Message throughput (msg/sec)
- Consumer lag (ms)
- Error rate (%)

### Resources
- CPU utilization (%)
- Memory usage (MB)
- Disk availability (%)

### Application
- API latency p95 (ms)
- Error rate (%)

## Usage

1. Review metrics hourly during first 24 hours
2. After 24 hours, generate baseline report
3. Use baseline data to calibrate alert thresholds
4. Archive baselines for future trend analysis

## Next Steps

After baseline collection complete (24 hours):
1. Review BASELINE-COLLECTION-REPORT.md
2. Calibrate alert thresholds based on baselines
3. Deploy updated thresholds to Prometheus
4. Update operational procedures if needed
EOF
fi

echo "Baseline collection ready. Monitor hourly for next 24 hours."
