# Service Health Monitoring Implementation Guide

**Status**: Implementation documentation for robust health checks across all 41 services

## Overview

This document provides the implementation strategy for adding comprehensive health monitoring to all services in the code-server deployment. This addresses the TODO item from the code review process.

## Architecture

### Health Check Layers

```
┌─────────────────────────────────────────────────┐
│         Health Check Orchestration              │
│  (scripts/ops/health-check-idempotent.sh)      │
└────────┬────────────────────────────────────────┘
         │
    ┌────┴──────────────────────┐
    │                           │
    ▼                           ▼
Docker Health Checks    Prometheus Metrics
(container-level)       (application-level)
    │                           │
    ├─ TCP probe                ├─ /metrics endpoint
    ├─ HTTP probe               ├─ Custom exporter
    ├─ Shell command            └─ Health endpoint JSON
    └─ Exit code check
```

### Service Categories

**Category A: Init Containers** (Exit on completion)
- `code-server-grafana-init`
- `code-server-redis-init`
- `code-server-redpanda-init`
- `code-server-prometheus-init`
- `code-server-loki-init`
- `code-server-alertmanager-init`
- `code-server-caddy-init`

**Category B: Long-Running Services** (Requires health checks)
- Database: postgres-db
- Cache: redis-cache
- Message Broker: redpanda-broker
- Observability: prometheus, grafana, loki, alertmanager
- API Gateway: caddy-gateway
- Security: oauth2-proxy, opa-service
- Specialized: qdrant-vectors, ollama-models, etc.

## Implementation Strategy

### 1. Docker-Compose Health Checks

Add `healthcheck` stanzas to all long-running services in `docker-compose.yml`:

```yaml
services:
  postgres-db:
    image: postgres:15
    container_name: code-server-postgres-db
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    # ... rest of config

  redis-cache:
    image: redis:7-alpine
    container_name: code-server-redis-cache
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    # ... rest of config

  prometheus:
    image: prom/prometheus:latest
    container_name: code-server-prometheus
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
    # ... rest of config
```

### 2. Health Check Verification Script

Create `scripts/ops/verify-service-health.sh`:

```bash
#!/bin/bash
# Comprehensive service health verification
# Usage: bash scripts/ops/verify-service-health.sh [--timeout 300] [--retry-interval 5]

set -euo pipefail

TIMEOUT=${1:-300}
RETRY_INTERVAL=${2:-5}
SERVICES_CHECKED=0
SERVICES_HEALTHY=0
SERVICES_UNHEALTHY=0

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get all running services from docker-compose
get_running_services() {
  docker compose ps --services
}

# Check individual service health
check_service_health() {
  local service=$1
  local container_name=$(docker compose ps "$service" --format "table {{.Names}}" | tail -1)
  
  if [[ -z "$container_name" ]]; then
    echo -e "${RED}✗${NC} $service: Not running"
    ((SERVICES_UNHEALTHY++))
    return 1
  fi
  
  # Check if container has healthcheck
  local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")
  
  case "$health_status" in
    "healthy")
      echo -e "${GREEN}✓${NC} $service: Healthy"
      ((SERVICES_HEALTHY++))
      return 0
      ;;
    "unhealthy")
      echo -e "${RED}✗${NC} $service: Unhealthy"
      ((SERVICES_UNHEALTHY++))
      return 1
      ;;
    "starting")
      echo -e "${YELLOW}⟳${NC} $service: Starting..."
      return 2
      ;;
    "none")
      # No healthcheck defined, assume healthy if running
      echo -e "${YELLOW}⊘${NC} $service: No healthcheck (running)"
      ((SERVICES_HEALTHY++))
      return 0
      ;;
    *)
      echo -e "${RED}?${NC} $service: Unknown status ($health_status)"
      ((SERVICES_UNHEALTHY++))
      return 1
      ;;
  esac
}

# Main health check loop
main() {
  echo "=== Service Health Check ==="
  echo "Timeout: ${TIMEOUT}s | Retry Interval: ${RETRY_INTERVAL}s"
  echo ""
  
  local start_time=$(date +%s)
  
  while true; do
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    
    if [[ $elapsed -gt $TIMEOUT ]]; then
      echo ""
      echo -e "${RED}Timeout exceeded ($TIMEOUT seconds)${NC}"
      break
    fi
    
    SERVICES_CHECKED=0
    SERVICES_HEALTHY=0
    SERVICES_UNHEALTHY=0
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking services..."
    
    while IFS= read -r service; do
      ((SERVICES_CHECKED++))
      check_service_health "$service"
    done < <(get_running_services)
    
    echo ""
    echo "Status: $SERVICES_HEALTHY healthy, $SERVICES_UNHEALTHY unhealthy, $SERVICES_CHECKED total"
    
    if [[ $SERVICES_UNHEALTHY -eq 0 && $SERVICES_CHECKED -gt 0 ]]; then
      echo -e "${GREEN}✓ All services are healthy!${NC}"
      return 0
    fi
    
    if [[ $elapsed -lt $TIMEOUT ]]; then
      echo "Waiting ${RETRY_INTERVAL} seconds before next check..."
      sleep "$RETRY_INTERVAL"
    fi
  done
  
  return 1
}

main
```

### 3. Prometheus Scrape Configuration

Add to `config/prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'docker'
    static_configs:
      - targets: ['localhost:9323']  # Docker daemon metrics
  
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'grafana'
    static_configs:
      - targets: ['localhost:3000']
  
  - job_name: 'redis'
    static_configs:
      - targets: ['localhost:6379']
  
  - job_name: 'postgres'
    static_configs:
      - targets: ['localhost:5432']
  
  - job_name: 'loki'
    static_configs:
      - targets: ['localhost:3100']
  
  - job_name: 'qdrant'
    static_configs:
      - targets: ['localhost:6333']
```

### 4. Health Check Dashboard

Create Grafana dashboard (`grafana/dashboards/service-health.json`):

```json
{
  "dashboard": {
    "title": "Service Health Monitoring",
    "panels": [
      {
        "title": "Container Status",
        "targets": [
          {
            "expr": "docker_container_state_running"
          }
        ]
      },
      {
        "title": "Service Response Times",
        "targets": [
          {
            "expr": "rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])"
          }
        ]
      },
      {
        "title": "Database Connection Pool",
        "targets": [
          {
            "expr": "pg_stat_activity_count"
          }
        ]
      },
      {
        "title": "Cache Hit Rate",
        "targets": [
          {
            "expr": "redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total)"
          }
        ]
      }
    ]
  }
}
```

### 5. Alerting Rules

Create `config/prometheus/alerts.yml`:

```yaml
groups:
  - name: service_health
    rules:
      - alert: ServiceDown
        expr: docker_container_state_running == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.name }} is down"
      
      - alert: ServiceUnhealthy
        expr: docker_container_health_status == 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Service {{ $labels.name }} is unhealthy"
      
      - alert: HighLatency
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High latency detected for {{ $labels.service }}"
```

## Implementation Checklist

- [ ] **Step 1**: Update docker-compose.yml with healthcheck stanzas (all 41 services)
- [ ] **Step 2**: Create `verify-service-health.sh` script
- [ ] **Step 3**: Update Prometheus scrape config for all services
- [ ] **Step 4**: Create Grafana dashboard
- [ ] **Step 5**: Deploy alerting rules to Prometheus
- [ ] **Step 6**: Test health checks on deployment
- [ ] **Step 7**: Document init container strategy in README

## Testing

### Manual Health Check
```bash
# Test individual service health
docker ps --format "table {{.Names}}\t{{.Status}}"

# Test with verification script
bash scripts/ops/verify-service-health.sh --timeout 600
```

### Automated Testing
```bash
# Add to CI/CD pipeline
bash scripts/ops/verify-service-health.sh --timeout 300 || exit 1
```

## Monitoring & Alerting

### Key Metrics to Track
- Container restart count
- Health check failure rate
- Service response time (p50, p95, p99)
- Database connection pool utilization
- Cache hit rate
- Message queue depth

### Alert Thresholds (Recommended)
- **Critical**: Service down for > 2 minutes
- **Warning**: Service unhealthy for > 5 minutes
- **Warning**: Response time p95 > 1 second
- **Warning**: Cache hit rate < 70%
- **Info**: Database connections > 80% of pool

## Documentation References

- [Docker Health Checks](https://docs.docker.com/engine/reference/builder/#healthcheck)
- [Prometheus Monitoring](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Grafana Dashboards](https://grafana.com/docs/grafana/latest/dashboards/)

## Migration from TODO to Implementation

**Before**: Manual health verification with manual inspection
**After**: Automated health checks with Prometheus metrics and Grafana dashboards

### Success Criteria
✓ All 41 services have health checks defined
✓ Grafana dashboard shows all services' status in real-time
✓ Alerts trigger within 5 minutes of service degradation
✓ Health verification script runs in < 30 seconds
✓ Documentation covers init container strategy

---
**Generated**: 2026-04-28
**Implementation Status**: Ready for deployment
**Next Steps**: Review and merge into docker-compose.yml
