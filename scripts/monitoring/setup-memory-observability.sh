#!/bin/bash
# @file scripts/monitoring/setup-memory-observability.sh
# @module infrastructure/observability
# @description P3-1562 Phase 5: Grafana dashboards for memory engine metrics
# @governance GOV-002: All memory engine operations visible and auditable
# @usage setup-memory-observability.sh

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Load infrastructure configuration
source "${REPO_ROOT}/.env.infrastructure" 2>/dev/null || true

# Create Grafana dashboard JSON
generate_grafana_dashboard() {
  log_info "Generating Grafana dashboard for organizational memory..."
  
  cat > "${REPO_ROOT}/dashboards/memory-engine-monitoring.json" <<'EOF'
{
  "dashboard": {
    "title": "Organizational Memory Engine",
    "uid": "memory-engine",
    "tags": ["memory", "agent-learnings", "semantic-search"],
    "timezone": "UTC",
    "panels": [
      {
        "title": "Semantic Search Queries (5min)",
        "targets": [
          {
            "expr": "rate(memory_search_queries_total[5m])"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Average Search Latency",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, memory_search_latency_seconds)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Agent Task Success Rate",
        "targets": [
          {
            "expr": "memory_agent_success_rate * 100"
          }
        ],
        "type": "gauge"
      },
      {
        "title": "Documents by Collection",
        "targets": [
          {
            "expr": "memory_collection_document_count"
          }
        ],
        "type": "table"
      },
      {
        "title": "Agent Learning Quality Scores",
        "targets": [
          {
            "expr": "memory_agent_quality_score"
          }
        ],
        "type": "heatmap"
      }
    ]
  }
}
EOF
  
  log_success "Grafana dashboard created"
}

# Create Prometheus metrics configuration
generate_prometheus_metrics() {
  log_info "Generating Prometheus metrics for memory engine..."
  
  cat > "${REPO_ROOT}/config/memory-engine-metrics.yaml" <<EOF
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: 'memory-engine'
    static_configs:
      - targets: ['${MEMORY_SERVICE_ENDPOINT#http://}']
    metrics_path: '/metrics'
    scrape_interval: 30s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

rule_files:
  - 'memory-engine-alert-rules.yaml'
EOF
  
  log_success "Prometheus metrics configuration created"
}

# Create alert rules
generate_alert_rules() {
  log_info "Generating alert rules for memory engine..."
  
  cat > "${REPO_ROOT}/config/memory-engine-alert-rules.yaml" <<'EOF'
groups:
  - name: memory_engine
    rules:
      - alert: MemorySearchLatencyHigh
        expr: histogram_quantile(0.95, memory_search_latency_seconds) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memory search latency exceeds 5 seconds"
      
      - alert: AgentLearningQualityLow
        expr: memory_agent_quality_score < 0.5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Agent learning quality score below 0.5"
      
      - alert: MemoryEngineDown
        expr: up{job="memory-engine"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Memory engine is down"
EOF
  
  log_success "Alert rules created"
}

# Create memory engine documentation
generate_documentation() {
  log_info "Generating memory engine documentation..."
  
  cat > "${REPO_ROOT}/docs/architecture/memory-engine-observability.md" <<'EOF'
# Organizational Memory Engine - Observability Guide

## Metrics

- **memory_search_queries_total**: Total semantic search queries
- **memory_search_latency_seconds**: Search query latency histogram
- **memory_collection_document_count**: Documents per collection
- **memory_agent_success_rate**: Agent task success rate (0-1)
- **memory_agent_quality_score**: Average quality score of agent learnings
- **memory_agent_avg_tokens**: Average tokens per agent task
- **memory_agent_avg_duration**: Average duration per agent task

## Dashboards

- **Organizational Memory Engine**: Main monitoring dashboard
  - Search query rates
  - Search latency (p95)
  - Agent task success rate
  - Document counts by collection
  - Agent learning quality scores

## Alerts

| Alert | Threshold | Severity |
|-------|-----------|----------|
| MemorySearchLatencyHigh | p95 > 5s for 5m | Warning |
| AgentLearningQualityLow | avg quality < 0.5 for 10m | Warning |
| MemoryEngineDown | up == 0 for 1m | Critical |

## Troubleshooting

**High search latency:**
- Check Qdrant service health
- Monitor network latency between memory engine and Qdrant
- Review query complexity

**Low agent quality scores:**
- Review agent task implementations
- Check for excessive token usage
- Monitor for high error rates

**Memory engine down:**
- Check FastAPI service logs
- Verify Qdrant connection
- Restart memory engine service
EOF
  
  log_success "Documentation generated"
}

main() {
  log_info "Setting up organizational memory observability..."
  
  generate_grafana_dashboard
  generate_prometheus_metrics
  generate_alert_rules
  generate_documentation
  
  log_success "Memory observability setup complete"
  log_info "Grafana dashboard: http://localhost:3000 (Memory Engine)"
  log_info "Prometheus: http://localhost:9090"
}

main "$@"