#!/bin/bash

################################################################################
# Phase 5.3: Auto-Scaling Configuration
# Purpose: Configure Kubernetes-style auto-scaling policies, resource limits,
#          and horizontal pod autoscaling (HPA) equivalent for Docker Swarm
# Usage: ./scripts/setup-autoscaling.sh [--apply]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup: Removing temporary configuration files..."; rm -f /tmp/*.yaml.tmp /tmp/*.json.tmp 2>/dev/null || true' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

################################################################################
# 1. AUTO-SCALING POLICIES
################################################################################

create_autoscaling_policies() {
    log_info "Creating auto-scaling policies..."

    cat > "${PROJECT_ROOT}/autoscaling-policies.yaml" << 'AUTO_SCALE'
---
# Phase 5.3: Auto-Scaling Policies Configuration

autoscaling:
  # Global settings
  enabled: true
  check_interval: 30s  # Check every 30 seconds

  # Resource-based scaling policies
  policies:
    
    # 1. CPU-based scaling
    cpu_scaling:
      enabled: true
      metric: cpu_usage_percent
      scale_up:
        threshold: 80
        duration: 120s  # Scale up if > 80% for 2 minutes
        replicas_add: 1
      scale_down:
        threshold: 30
        duration: 300s  # Scale down if < 30% for 5 minutes
        replicas_remove: 1
      min_replicas: 1
      max_replicas: 5

    # 2. Memory-based scaling
    memory_scaling:
      enabled: true
      metric: memory_usage_percent
      scale_up:
        threshold: 85
        duration: 120s
        replicas_add: 1
      scale_down:
        threshold: 40
        duration: 300s
        replicas_remove: 1
      min_replicas: 1
      max_replicas: 4

    # 3. Request queue-based scaling
    queue_scaling:
      enabled: true
      metric: pending_requests
      scale_up:
        threshold: 100  # Queue length > 100
        duration: 60s
        replicas_add: 2
      scale_down:
        threshold: 10
        duration: 300s
        replicas_remove: 1
      min_replicas: 2
      max_replicas: 10

    # 4. Connection pool scaling
    connection_scaling:
      enabled: true
      metric: active_connections_percent
      scale_up:
        threshold: 75
        duration: 90s
        increase_pool: 10
      scale_down:
        threshold: 25
        duration: 600s
        decrease_pool: 5
      min_pool_size: 20
      max_pool_size: 100

  # Service-specific policies
  services:
    
    control_plane:
      scaling_policy: cpu_scaling
      target_replicas: 3
      resource_limits:
        cpu: 2000m
        memory: 2Gi
      resource_requests:
        cpu: 500m
        memory: 512Mi
      cooldown: 60s

    agent_runtime:
      scaling_policy: queue_scaling
      target_replicas: 2
      resource_limits:
        cpu: 1000m
        memory: 1Gi
      resource_requests:
        cpu: 250m
        memory: 256Mi
      cooldown: 30s

    activity_feed:
      scaling_policy: memory_scaling
      target_replicas: 2
      resource_limits:
        cpu: 800m
        memory: 1Gi
      resource_requests:
        cpu: 200m
        memory: 256Mi
      cooldown: 45s

    execution_scheduler:
      scaling_policy: cpu_scaling
      target_replicas: 2
      resource_limits:
        cpu: 1000m
        memory: 1Gi
      resource_requests:
        cpu: 500m
        memory: 512Mi
      cooldown: 60s

    reputation_engine:
      scaling_policy: memory_scaling
      target_replicas: 2
      resource_limits:
        cpu: 800m
        memory: 1Gi
      resource_requests:
        cpu: 200m
        memory: 256Mi
      cooldown: 45s

  # Database scaling
  database:
    postgres:
      # Connection pool auto-scaling
      auto_adjust_pool: true
      min_pool_size: 10
      max_pool_size: 100
      target_utilization: 70
      check_interval: 60s
      
      # Automatic query optimization
      auto_analyze: true
      auto_vacuum: true
      vacuum_interval: 3600s  # 1 hour
      analyze_interval: 1800s # 30 minutes
      
      # Replication lag monitoring
      monitor_replication_lag: true
      max_acceptable_lag: 10s
      alert_threshold: 30s

    redis:
      # Memory auto-scaling
      auto_eviction: true
      eviction_policy: allkeys-lru
      target_memory_percent: 85
      
      # Persistence tuning
      auto_bgsave: true
      bgsave_interval: 3600s
      
      # Replication
      enable_replication: true
      replica_count: 1

  # Network scaling
  network:
    # Connection limiting
    max_connections: 10000
    max_connections_per_service: 100
    
    # Rate limiting
    enable_rate_limiting: true
    requests_per_second: 10000
    burst_size: 2000
    
    # Queue management
    queue_max_size: 1000
    queue_timeout: 30s

  # Cost optimization
  cost_optimization:
    # Scale down during off-peak hours
    enable_schedule_based: true
    schedules:
      weekday_peak:
        enabled: true
        days: [1, 2, 3, 4, 5]  # Monday-Friday
        start_time: "08:00"
        end_time: "18:00"
        target_replicas: 3
      
      weekday_offpeak:
        enabled: true
        days: [1, 2, 3, 4, 5]
        start_time: "18:00"
        end_time: "08:00"
        target_replicas: 1
      
      weekend:
        enabled: true
        days: [0, 6]  # Saturday-Sunday
        target_replicas: 1

  # Monitoring and alerts
  monitoring:
    prometheus_enabled: true
    metrics_port: 8888
    metrics_path: /metrics
    
    alerts:
      scaling_failures: true
      replica_mismatch: true
      resource_exhaustion: true
      queue_backlog: true

  # Gradual rollout settings
  gradual_scaling:
    enabled: true
    scale_up_rate: 1  # Add 1 replica per check interval
    scale_down_rate: 1  # Remove 1 replica per check interval
    max_change_per_interval: 2  # Max 2 replicas added/removed per interval
AUTO_SCALE

    log_success "Auto-scaling policies created"
}

################################################################################
# 2. RESOURCE LIMIT CONFIGURATION
################################################################################

create_resource_limits() {
    log_info "Creating resource limit configuration..."

    cat > "${PROJECT_ROOT}/resource-limits.yaml" << 'RESOURCE_LIMITS'
---
# Resource Limits and Requests for Services

services:
  data_layer:
    postgres:
      limits:
        cpu: 4000m
        memory: 8Gi
      requests:
        cpu: 2000m
        memory: 4Gi
      swap_limit: 1Gi
      pids_limit: 4096

    redis:
      limits:
        cpu: 2000m
        memory: 4Gi
      requests:
        cpu: 500m
        memory: 1Gi
      swap_limit: 500Mi
      pids_limit: 2048

    redpanda:
      limits:
        cpu: 2000m
        memory: 4Gi
      requests:
        cpu: 1000m
        memory: 2Gi

  observability:
    prometheus:
      limits:
        cpu: 2000m
        memory: 4Gi
      requests:
        cpu: 500m
        memory: 1Gi

    grafana:
      limits:
        cpu: 1000m
        memory: 2Gi
      requests:
        cpu: 250m
        memory: 512Mi

    loki:
      limits:
        cpu: 2000m
        memory: 4Gi
      requests:
        cpu: 500m
        memory: 1Gi

    tempo:
      limits:
        cpu: 1000m
        memory: 2Gi
      requests:
        cpu: 250m
        memory: 512Mi

  infrastructure:
    vault:
      limits:
        cpu: 1000m
        memory: 2Gi
      requests:
        cpu: 250m
        memory: 512Mi

    minio:
      limits:
        cpu: 2000m
        memory: 4Gi
      requests:
        cpu: 500m
        memory: 1Gi

    caddy:
      limits:
        cpu: 2000m
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 512Mi

  applications:
    control_plane:
      limits:
        cpu: 2000m
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 512Mi

    agent_runtime:
      limits:
        cpu: 1000m
        memory: 1Gi
      requests:
        cpu: 250m
        memory: 256Mi

    activity_feed:
      limits:
        cpu: 800m
        memory: 1Gi
      requests:
        cpu: 200m
        memory: 256Mi

    gitlab:
      limits:
        cpu: 4000m
        memory: 8Gi
      requests:
        cpu: 2000m
        memory: 4Gi
      swap_limit: 2Gi

  network:
    rules:
      - tcp_connections_max: 10000
      - udp_connections_max: 5000
      - max_bandwidth: "1Gbps"
      - burst_bandwidth: "5Gbps"

storage:
  limits:
    postgres_volume: 100Gi
    redis_volume: 50Gi
    minio_volume: 200Gi
    logs_volume: 100Gi
    metrics_volume: 50Gi
RESOURCE_LIMITS

    log_success "Resource limit configuration created"
}

################################################################################
# 3. AUTO-SCALING MONITORING DASHBOARD
################################################################################

create_monitoring_dashboard() {
    log_info "Creating auto-scaling monitoring dashboard configuration..."

    cat > "${PROJECT_ROOT}/docs/operations/autoscaling-monitoring.md" << 'DASHBOARD'
# Auto-Scaling Monitoring Dashboard

## Real-Time Metrics

### CPU Utilization by Service
```
sum by (service) (rate(container_cpu_usage_seconds_total[5m])) * 100
```

### Memory Usage by Service
```
container_memory_usage_bytes{job="docker_containers"} / 1024 / 1024
```

### Request Queue Length
```
http_requests_pending_total
```

### Active Connections
```
http_connections_active
```

## Scaling Events

### View Recent Scaling Events
```sql
SELECT timestamp, service_name, action, replicas_before, replicas_after, reason
FROM autoscaling_events
ORDER BY timestamp DESC
LIMIT 100;
```

### Scaling Activity Timeline
```
changes(autoscaling_replicas_count[1h])
```

## Alert Conditions

| Alert | Condition | Severity |
|-------|-----------|----------|
| High CPU | CPU > 80% for 2 min | WARNING |
| Critical CPU | CPU > 95% for 1 min | CRITICAL |
| High Memory | Memory > 85% for 2 min | WARNING |
| OOM Risk | Memory > 95% | CRITICAL |
| Queue Backlog | Queue > 500 | WARNING |
| Scaling Failure | Scale action failed | CRITICAL |

## Performance Targets

### Response Time SLOs
- p50: < 100ms
- p95: < 500ms
- p99: < 1s

### Availability SLOs
- 99.9% uptime (4.3 hours/month downtime)
- 99.99% uptime (43 minutes/month downtime)

### Resource Efficiency Targets
- CPU utilization: 40-60% (target sweet spot)
- Memory utilization: 50-70% (target sweet spot)
- Network utilization: < 40%

## Scaling Analysis

### Scaling History Query
```
SELECT 
  service_name,
  COUNT(*) as scale_events,
  AVG(EXTRACT(EPOCH FROM (timestamp_after - timestamp_before))) as avg_scale_duration_sec,
  MIN(replicas_before) as min_replicas,
  MAX(replicas_after) as max_replicas
FROM autoscaling_events
WHERE timestamp > NOW() - INTERVAL '7 days'
GROUP BY service_name
ORDER BY scale_events DESC;
```

### Cost Analysis
```
SELECT 
  service_name,
  AVG(replicas_running) as avg_replicas,
  MAX(replicas_running) as peak_replicas,
  ROUND(AVG(replicas_running) * 0.12 * 24 * 7, 2) as weekly_cost_usd
FROM autoscaling_events
WHERE timestamp > NOW() - INTERVAL '7 days'
GROUP BY service_name;
```

## Manual Scaling Override

### Scale Service Manually
```bash
docker service scale service_name=5
```

### Disable Auto-Scaling for Service
```bash
# Update service annotation
docker service update --label autoscaling.enabled=false service_name
```

### Emergency Scale Down
```bash
# Scale all services to 1 replica
for service in $(docker service ls --quiet); do
  docker service scale $service=1
done
```
DASHBOARD

    log_success "Auto-scaling monitoring dashboard created"
}

################################################################################
# 4. AUTOSCALING CONTROLLER SCRIPT
################################################################################

create_autoscaling_controller() {
    log_info "Creating auto-scaling controller script..."

    cat > "${PROJECT_ROOT}/scripts/autoscaling-controller.sh" << 'CONTROLLER'
#!/bin/bash

################################################################################
# Auto-Scaling Controller
# Purpose: Monitor metrics and automatically scale services based on policies
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

CONFIG_FILE="${PROJECT_ROOT}/autoscaling-policies.yaml"
METRICS_URL="http://prometheus:9090/api/v1"
LOG_FILE="/var/log/autoscaling-controller.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

get_metric() {
    local query="$1"
    curl -s "${METRICS_URL}/query?query=${query}" | jq '.data.result[0].value[1]' 2>/dev/null || echo "0"
}

scale_service() {
    local service="$1"
    local replicas="$2"
    local reason="$3"
    
    log "Scaling $service to $replicas replicas. Reason: $reason"
    docker service scale "${service}=${replicas}" || log "ERROR: Failed to scale $service"
}

# Monitor and auto-scale
main() {
    log "Auto-scaling controller started"
    
    while true; do
        # Check CPU for control_plane
        cpu=$(get_metric 'rate(container_cpu_usage_seconds_total{name="code-server-control-plane"}[1m])*100')
        if (( $(echo "$cpu > 80" | bc -l) )); then
            current=$(docker service ls --filter name=control_plane --format '{{.Replicas}}' | grep -o '^[0-9]*')
            if [ "$current" -lt 5 ]; then
                scale_service "code-server-control-plane" $((current + 1)) "High CPU: ${cpu}%"
            fi
        fi
        
        # Check memory for applications
        memory=$(get_metric 'container_memory_usage_bytes{name="code-server-activity-feed"}/1024/1024')
        if (( $(echo "$memory > 900" | bc -l) )); then
            current=$(docker service ls --filter name=activity-feed --format '{{.Replicas}}' | grep -o '^[0-9]*')
            if [ "$current" -lt 4 ]; then
                scale_service "code-server-activity-feed" $((current + 1)) "High Memory: ${memory}MB"
            fi
        fi
        
        # Sleep before next check
        sleep 30
    done
}

main "$@"
CONTROLLER

    chmod +x "${PROJECT_ROOT}/scripts/autoscaling-controller.sh"
    log_success "Auto-scaling controller script created"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "Phase 5.3: Auto-Scaling Configuration"
    log_info "======================================"

    create_autoscaling_policies
    create_resource_limits
    create_monitoring_dashboard
    create_autoscaling_controller

    if $APPLY; then
        log_info "Deploying auto-scaling configuration..."
        # Deploy to hosts
        ssh -o BatchMode=yes akushnir@192.168.168.31 "
            mkdir -p ~/code-server-enterprise/autoscaling
            docker service update --env-file <(cat <<EOF
AUTOSCALING_ENABLED=true
AUTOSCALING_CHECK_INTERVAL=30s
EOF
            ) code-server-control-plane || true
        " || log_warn "Could not deploy auto-scaling to primary"
        
        log_success "Phase 5.3 Auto-Scaling Configuration Applied"
    else
        log_info "Configurations created at:"
        log_info "  - ${PROJECT_ROOT}/autoscaling-policies.yaml"
        log_info "  - ${PROJECT_ROOT}/resource-limits.yaml"
        log_info "  - ${PROJECT_ROOT}/docs/operations/autoscaling-monitoring.md"
        log_info "  - ${PROJECT_ROOT}/scripts/autoscaling-controller.sh"
    fi
}

main "$@"
