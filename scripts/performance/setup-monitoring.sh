#!/usr/bin/env bash
# @file        scripts/performance/setup-monitoring.sh
# @module      performance/monitoring-setup
# @description Setup Prometheus and Grafana for performance testing
# @owner       ops-team
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/scripts/_common/init.sh"

# Configuration
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000/monitoring}"
APP_URL="${APP_URL:-http://localhost:3000}"
ARTIFACT_DIR="${PROJECT_ROOT}/artifacts/performance-tests"

log_info "=== PERFORMANCE TEST MONITORING SETUP ==="
log_info ""

# 1. Verify Prometheus is running
log_info "1. Checking Prometheus health..."
if curl -s "$PROMETHEUS_URL/-/healthy" | grep -q "Prometheus"; then
  log_info "✅ Prometheus is healthy"
else
  log_warn "⚠️  Prometheus may not be fully ready"
fi

# 2. Verify scrape targets
log_info ""
log_info "2. Checking scrape targets..."
ACTIVE_TARGETS=$(curl -s "$PROMETHEUS_URL/api/v1/targets" | jq '.data.activeTargets | length')
log_info "   Active targets: $ACTIVE_TARGETS"
if [ "$ACTIVE_TARGETS" -gt 5 ]; then
  log_info "✅ Scrape targets configured"
else
  log_warn "⚠️  Only $ACTIVE_TARGETS targets active (expected > 5)"
fi

# 3. Verify application health
log_info ""
log_info "3. Checking application health..."
if curl -s "$APP_URL/health" | jq -e '.status == "ok"' > /dev/null 2>&1; then
  log_info "✅ Application is healthy"
else
  log_error "❌ Application health check failed"
  exit 1
fi

# 4. Create monitoring queries file
log_info ""
log_info "4. Creating monitoring queries reference..."
mkdir -p "$ARTIFACT_DIR"

cat > "$ARTIFACT_DIR/monitoring-queries.md" << 'EOF'
# Performance Test Monitoring Queries

## Latency Metrics
```
# p99 latency
histogram_quantile(0.99, rate(http_request_duration_seconds[5m]))

# p95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds[5m]))

# p50 latency
histogram_quantile(0.50, rate(http_request_duration_seconds[5m]))

# Average request duration
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])
```

## Error Rate Metrics
```
# HTTP error rate (5xx)
rate(http_requests_total{status=~"5.."}[5m])

# Total error rate (4xx + 5xx)
rate(http_requests_total{status=~"[45].."}[5m])

# Request throughput (RPS)
rate(http_requests_total[5m])
```

## Resource Metrics
```
# Memory usage
container_memory_usage_bytes / 1024 / 1024

# CPU usage percentage
rate(container_cpu_usage_seconds_total[5m]) * 100

# Memory growth over time
rate(container_memory_usage_bytes[1m]) / 1024 / 1024
```

## Database Metrics
```
# Active database connections
pg_stat_activity_count

# Query execution time (if pg_stat_statements enabled)
histogram_quantile(0.95, rate(pg_stat_statements_calls[5m]))
```

## Cache Metrics
```
# Redis memory usage
redis_memory_used_bytes / 1024 / 1024

# Redis hit rate
redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total)
```
EOF

log_info "✅ Monitoring queries reference created"

# 5. Verify key metrics exist
log_info ""
log_info "5. Verifying key metrics are being collected..."

METRICS=(
  "http_requests_total"
  "http_request_duration_seconds"
  "container_memory_usage_bytes"
  "container_cpu_usage_seconds_total"
)

for metric in "${METRICS[@]}"; do
  if curl -s "$PROMETHEUS_URL/api/v1/series" \
    --data-urlencode "match[]=$metric" | jq -e '.data | length > 0' > /dev/null 2>&1; then
    log_info "   ✅ $metric"
  else
    log_warn "   ⚠️  $metric not found"
  fi
done

# 6. Create test configuration file
log_info ""
log_info "6. Creating test configuration..."

cat > "$ARTIFACT_DIR/test-config.env" << EOF
# Performance Test Configuration
# Generated: $(date)

# Test Environment
APP_URL=${APP_URL}
PROMETHEUS_URL=${PROMETHEUS_URL}
GRAFANA_URL=${GRAFANA_URL}

# Test Parameters
BASELINE_USERS=100
BASELINE_DURATION=600

SPIKE_USERS=1000
SPIKE_DURATION=300

SUSTAINED_USERS=500
SUSTAINED_DURATION=1800

# Success Thresholds
P99_BASELINE_THRESHOLD_MS=200
P99_SPIKE_THRESHOLD_MS=500
ERROR_RATE_BASELINE_THRESHOLD=0.1
ERROR_RATE_SPIKE_THRESHOLD=1.0
MEMORY_BASELINE_THRESHOLD_MB=1000
MEMORY_SUSTAINED_THRESHOLD_MB=2000

# Artifact Directory
ARTIFACT_DIR=${ARTIFACT_DIR}
EOF

log_info "✅ Test configuration created"

# 7. Final summary
log_info ""
log_info "=========================================="
log_info "✅ MONITORING SETUP COMPLETE"
log_info "=========================================="
log_info ""
log_info "Next steps for April 24:"
log_info "1. Review monitoring queries: $ARTIFACT_DIR/monitoring-queries.md"
log_info "2. Open Grafana dashboards: $GRAFANA_URL"
log_info "3. Execute baseline test: bash scripts/performance/load-test-baseline.sh"
log_info "4. Execute spike test: bash scripts/performance/load-test-spike.sh"
log_info "5. Execute sustained load: bash scripts/performance/load-test-sustained.sh"
log_info "6. Analyze results and generate report"
log_info ""
