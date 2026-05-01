#!/bin/bash
# @file scripts/monitoring/setup-activity-feed-observability.sh
# @module infrastructure/observability
# @description P3-1560 Phase 5: Monitoring for Kafka event bus and Activity Feed
# @governance GOV-002: All metrics exported and alerted
# @usage setup-activity-feed-observability.sh

set -euo pipefail

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source shared helpers and normalize environment file line endings
source "${REPO_ROOT}/scripts/_common/init.sh"

# Source infrastructure configuration
source_env_file "${REPO_ROOT}/.env.infrastructure"

# Generate Prometheus alert rules
generate_alert_rules() {
  log_info "Generating alert rules for Activity Feed and Kafka..."
  
  cat > "${REPO_ROOT}/config/activity-feed-alert-rules.yaml" <<'EOF'
groups:
  - name: kafka_event_bus
    rules:
      - alert: KafkaHighConsumerLag
        expr: kafka_consumer_lag > 10000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Kafka consumer lag exceeding 10000 messages"
          description: "Consumer lag: {{ $value }} messages"
      
      - alert: KafkaBrokerDown
        expr: up{job="kafka-broker"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Kafka broker is down"
      
      - alert: EventParsingErrors
        expr: rate(event_parsing_errors_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Event parsing error rate >0.1 per second"
  
  - name: activity_feed
    rules:
      - alert: ActivityFeedHighLatency
        expr: histogram_quantile(0.95, activity_feed_api_latency_seconds) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Activity Feed API p95 latency > 1 second"
      
      - alert: ActivityFeedDown
        expr: up{job="activity-feed"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Activity Feed service is down"
      
      - alert: WebSocketConnectionErrors
        expr: rate(activity_feed_websocket_errors_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "WebSocket error rate > 0.05 per second"
EOF
  
  log_success "Alert rules created"
}

# Generate Grafana dashboard JSON
generate_grafana_dashboard() {
  log_info "Generating Grafana dashboard for Activity Feed..."
  
  cat > "${REPO_ROOT}/dashboards/kafka-event-bus-monitoring.json" <<'EOF'
{
  "dashboard": {
    "title": "Kafka Event Bus & Activity Feed",
    "uid": "kafka-event-bus",
    "tags": ["kafka", "event-bus", "activity-feed"],
    "timezone": "UTC",
    "panels": [
      {
        "title": "Event Throughput (5min)",
        "targets": [
          {"expr": "sum(rate(kafka_messages_received_total[5m])) by (topic)"}
        ],
        "type": "graph"
      },
      {
        "title": "Consumer Lag",
        "targets": [
          {"expr": "kafka_consumer_lag"}
        ],
        "type": "graph"
      },
      {
        "title": "Activity Feed API Latency (p95)",
        "targets": [
          {"expr": "histogram_quantile(0.95, activity_feed_api_latency_seconds)"}
        ],
        "type": "graph"
      },
      {
        "title": "Event Parsing Error Rate",
        "targets": [
          {"expr": "rate(event_parsing_errors_total[5m])"}
        ],
        "type": "graph"
      },
      {
        "title": "WebSocket Connections",
        "targets": [
          {"expr": "activity_feed_websocket_connections"}
        ],
        "type": "gauge"
      },
      {
        "title": "Events by Type (24h)",
        "targets": [
          {"expr": "sum(increase(kafka_messages_received_total[24h])) by (topic)"}
        ],
        "type": "table"
      }
    ]
  }
}
EOF
  
  log_success "Grafana dashboard created"
}

# Generate Prometheus scrape config
generate_prometheus_config() {
  log_info "Generating Prometheus scrape configuration..."
  
  cat > "${REPO_ROOT}/config/activity-feed-prometheus.yaml" <<'EOF'
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: 'kafka-broker'
    static_configs:
      - targets: ['${KAFKA_JMX_EXPORTER}']  # Kafka JMX exporter
    metrics_path: '/metrics'
  
  - job_name: 'activity-feed'
    static_configs:
      - targets: ['${MEMORY_SERVICE_ENDPOINT}']
    metrics_path: '/metrics'
    scrape_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['${KAFKA_BROKER}']

rule_files:
  - 'activity-feed-alert-rules.yaml'
EOF
  
  log_success "Prometheus configuration created"
}

# Generate observability documentation
generate_documentation() {
  log_info "Generating observability documentation..."
  
  cat > "${REPO_ROOT}/docs/architecture/activity-feed-observability.md" <<'EOF'
# Activity Feed & Kafka Event Bus Observability

## Metrics

### Kafka Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|------------------|
| kafka_messages_received_total | Total messages per topic | - |
| kafka_consumer_lag | Lag behind latest offset | > 10,000 messages |
| kafka_broker_up | Broker availability | == 0 (critical) |
| kafka_partition_replica_lag | Partition replication lag | > 1000 |

### Activity Feed Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|------------------|
| activity_feed_api_requests_total | API request count | - |
| activity_feed_api_latency_seconds | API response time | p95 > 1s |
| activity_feed_websocket_connections | Active WebSocket clients | - |
| activity_feed_events_ingested_total | Events processed | - |
| event_parsing_errors_total | Failed event parsing | > 0.1/sec |

## Dashboards

### Kafka Event Bus Health
- Event throughput by topic (5-minute rate)
- Consumer group lag trends
- Broker availability
- Replication status

### Activity Feed Performance
- API request latency (p50, p95, p99)
- WebSocket connection count
- Event ingestion rate
- Error rate breakdown

## Alerts

### Critical (Page On-Call)
- Kafka broker down
- Activity Feed service down
- Consumer lag > 50,000 (unable to catch up)

### Warning (Create Ticket)
- Consumer lag > 10,000
- API latency p95 > 1 second
- Event parsing error rate > 0.1/sec
- WebSocket error rate > 0.05/sec

## Troubleshooting Queries

### Find high-lag topics
```promql
kafka_consumer_lag{job="kafka"} > 1000
order by (value) desc
```

### Activity Feed error rate
```promql
rate(event_parsing_errors_total[5m])
```

### WebSocket connection health
```promql
rate(activity_feed_websocket_errors_total[5m]) / rate(activity_feed_websocket_connections[5m])
```

### Message latency end-to-end
```promql
histogram_quantile(0.95, activity_feed_api_latency_seconds)
```
EOF
  
  log_success "Observability documentation created"
}

main() {
  log_info "Setting up Activity Feed observability..."
  
  generate_alert_rules
  generate_grafana_dashboard
  generate_prometheus_config
  generate_documentation
  
  log_success "Activity Feed observability setup complete"
  log_info "Grafana: ${GRAFANA_ENDPOINT} (Kafka Event Bus & Activity Feed dashboard)"
  log_info "Prometheus: ${PROMETHEUS_ENDPOINT}"
  log_info "AlertManager: ${KAFKA_BROKER}"
}

main "$@"
