# Control Plane Service

Orchestration and control hub for Code Server Enterprise. Manages deployment lifecycle, resource allocation, cluster coordination, and system-wide state management.

## Architecture Overview

The Control Plane is the central coordination service that:

- **Deployment Orchestration**: Manages application lifecycle across single and multi-cluster deployments
- **Resource Management**: Allocates CPU, memory, and network resources to services
- **Cluster Coordination**: Synchronizes state across primary and replica clusters
- **Policy Enforcement**: Applies deployment policies, rollback strategies, and health constraints
- **Audit & Compliance**: Tracks all operational decisions with immutable audit logs
- **Circuit Breaker Management**: Coordinates failure detection and recovery across services

### Service Dependencies

```
control-plane
├── PostgreSQL (control_plane_db, audit_logs table)
├── Redis (deployment state, locks)
├── Kafka (deployment events, rollback triggers)
├── auth-server (verify deployment authorization)
└── reputation_engine (tier-based deployment permissions)
```

### Data Flow

```
User Request
    ↓
API Gateway / HTTP
    ↓
Control Plane Service
    ├─→ Verify Authorization (auth-server)
    ├─→ Check Tier Permissions (reputation_engine)
    ├─→ Validate Deployment Plan
    ├─→ Acquire Distributed Lock (Redis)
    ├─→ Store in PostgreSQL (audit log)
    └─→ Publish Event (Kafka)
         ↓
      Orchestration Engine
         ↓
      Affected Services (activity_feed, agent-runtime, etc.)
```

## Core Components

### 1. Deployment Orchestrator

Manages end-to-end deployment lifecycle:

```python
# Example: Deploy a new version of a service
POST /deployments
{
    "service": "auth-server",
    "version": "2.1.0",
    "deployment_strategy": "canary",
    "canary_percentage": 10,
    "replicas": 3,
    "health_checks": ["readiness", "liveness"],
    "rollback_on_failure": true
}

Response:
{
    "deployment_id": "dep-20260428-001",
    "status": "in_progress",
    "timeline": {
        "start_time": "2026-04-28T10:00:00Z",
        "eta_completion": "2026-04-28T10:05:00Z"
    },
    "current_stage": "pre_deployment_validation",
    "progress": 15,
    "events": [
        {"timestamp": "10:00:00", "event": "Deployment created", "level": "info"},
        {"timestamp": "10:00:05", "event": "Auth validation passed", "level": "info"}
    ]
}
```

### 2. Resource Allocator

Manages cluster resources with reservation and quota enforcement:

```python
# Example: Request resource allocation
POST /resources/allocate
{
    "service": "multimodal-ai",
    "cpu_cores": 4,
    "memory_gb": 8,
    "gpu_required": true,
    "network_bandwidth_mbps": 1000,
    "storage_gb": 50,
    "priority": "high"
}

Response:
{
    "allocation_id": "alloc-20260428-001",
    "status": "allocated",
    "assignment": {
        "node": "worker-2",
        "cpu_cores": 4,
        "memory_gb": 8,
        "gpu": "nvidia-a100-1",
        "network_vlan": 100
    },
    "ttl_seconds": 3600,
    "quota_remaining": {
        "cpu_cores": 8,
        "memory_gb": 16,
        "gpu": 1
    }
}
```

### 3. Cluster Coordinator

Manages multi-cluster state synchronization:

```python
# Example: Register cluster replica
POST /clusters/register
{
    "cluster_id": "cluster-replica-32",
    "host": "192.168.168.32",
    "role": "replica",
    "primary_host": "192.168.168.31",
    "capabilities": {
        "max_services": 50,
        "gpu_support": true,
        "regions": ["us-east-1", "us-east-2"]
    },
    "sync_interval_seconds": 30
}

Response:
{
    "cluster_id": "cluster-replica-32",
    "status": "synced",
    "sync_time_ms": 45,
    "services_synced": 28,
    "state": {
        "ready_replicas": 3,
        "pending_deployments": 2,
        "failed_services": 0
    }
}
```

### 4. Policy Engine

Enforces deployment and operational policies:

```python
# Example: Apply deployment policy
POST /policies/apply
{
    "policy_name": "canary_deployment",
    "rules": [
        {
            "name": "max_error_rate",
            "condition": "error_rate > 5%",
            "action": "automatic_rollback",
            "window_seconds": 60
        },
        {
            "name": "latency_threshold",
            "condition": "p99_latency > 500ms",
            "action": "scale_up",
            "scale_factor": 1.5
        }
    ],
    "apply_to_services": ["auth-server", "api-gateway"],
    "effective_period": "2026-04-28T10:00:00Z/2026-04-29T10:00:00Z"
}

Response:
{
    "policy_id": "pol-20260428-001",
    "status": "applied",
    "services_affected": 2,
    "rules_active": 2,
    "last_triggered": null
}
```

### 5. Audit & Compliance

Tracks all operational decisions:

```python
# Example: Get audit log
GET /audit/logs?service=auth-server&action=deploy&limit=10

Response:
{
    "logs": [
        {
            "timestamp": "2026-04-28T10:00:00Z",
            "actor": "user@company.com",
            "action": "deploy",
            "service": "auth-server",
            "version": "2.1.0",
            "status": "success",
            "details": {
                "deployment_id": "dep-20260428-001",
                "replicas": 3,
                "strategy": "canary"
            },
            "duration_seconds": 300
        }
    ],
    "total_count": 1245,
    "next_cursor": "cur-20260428-001"
}
```

## API Endpoints

### Deployment Management

```bash
# Create deployment
POST /deployments
{
    "service": "service-name",
    "version": "1.0.0",
    "deployment_strategy": "rolling|canary|blue_green",
    "replicas": 3
}

# Get deployment status
GET /deployments/{deployment_id}

# Get deployments for service
GET /deployments?service=service-name&status=in_progress

# Cancel deployment
DELETE /deployments/{deployment_id}

# Trigger rollback
POST /deployments/{deployment_id}/rollback
{
    "reason": "health_check_failure",
    "target_version": "1.0.0"
}
```

### Resource Management

```bash
# Allocate resources
POST /resources/allocate
{
    "service": "service-name",
    "cpu_cores": 4,
    "memory_gb": 8
}

# List resource allocations
GET /resources?cluster=cluster-id&status=active

# Release resource allocation
DELETE /resources/{allocation_id}

# Get resource metrics
GET /resources/{allocation_id}/metrics?interval=5m
```

### Cluster Coordination

```bash
# Register cluster
POST /clusters/register
{
    "cluster_id": "cluster-id",
    "host": "192.168.168.32",
    "role": "replica"
}

# Sync cluster state
POST /clusters/{cluster_id}/sync
{
    "full_sync": false
}

# Get cluster status
GET /clusters/{cluster_id}/status

# Get all clusters
GET /clusters?role=primary|replica
```

### Policy Management

```bash
# Apply policy
POST /policies/apply
{
    "policy_name": "policy-name",
    "rules": []
}

# List policies
GET /policies?service=service-name&status=active

# Disable policy
PUT /policies/{policy_id}
{
    "status": "disabled"
}
```

### Health & Status

```bash
# Get control plane health
GET /health

Response:
{
    "status": "healthy",
    "timestamp": "2026-04-28T10:00:00Z",
    "uptime_seconds": 86400,
    "components": {
        "database": "connected",
        "redis": "connected",
        "kafka": "connected",
        "auth_server": "responsive",
        "memory_engine": "responsive"
    }
}

# Get cluster overview
GET /overview
{
    "total_services": 28,
    "healthy_services": 27,
    "pending_deployments": 2,
    "failed_services": 1,
    "resource_utilization": {
        "cpu": "65%",
        "memory": "72%",
        "gpu": "45%"
    }
}
```

## Configuration

### Environment Variables

```bash
# Database
CONTROL_PLANE_DB_URL=postgresql://user:pass@localhost:5432/control_plane_db
CONTROL_PLANE_DB_POOL_SIZE=20
CONTROL_PLANE_DB_TIMEOUT=30

# Redis (for state and locks)
CONTROL_PLANE_REDIS_URL=redis://localhost:6379/0
CONTROL_PLANE_REDIS_LOCK_TTL=300

# Kafka (for event publishing)
CONTROL_PLANE_KAFKA_BOOTSTRAP_SERVERS=localhost:9092
CONTROL_PLANE_KAFKA_TOPICS=deployment.events,rollback.triggers,policy.changes

# Service URLs
AUTH_SERVER_URL=http://auth-server:8001
REPUTATION_ENGINE_URL=http://reputation-engine:8009

# Deployment
DEPLOYMENT_TIMEOUT_SECONDS=600
DEPLOYMENT_CHECK_INTERVAL_SECONDS=5
CANARY_PERCENTAGE_DEFAULT=10

# Audit
AUDIT_RETENTION_DAYS=365
AUDIT_LOG_LEVEL=info
```

### Docker Compose Configuration

```yaml
control-plane:
  image: kushin77/code-server-control-plane@sha256:abc123...
  ports:
    - "8012:8000"
  environment:
    - CONTROL_PLANE_DB_URL=postgresql://postgres:password@postgres:5432/control_plane_db
    - CONTROL_PLANE_REDIS_URL=redis://redis:6379/0
    - KAFKA_BOOTSTRAP_SERVERS=kafka:9092
    - AUTH_SERVER_URL=http://auth-server:8001
  depends_on:
    - postgres
    - redis
    - kafka
    - auth-server
  volumes:
    - /var/log/control-plane:/var/log/control-plane
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s
```

## Deployment Strategies

### 1. Rolling Deployment

Gradually replace old instances with new ones:

```
Timeline:
T+0:  Instance 1 → Version 2.1.0 (old: 2/3 healthy)
T+30: Instance 2 → Version 2.1.0 (old: 1/3 healthy)
T+60: Instance 3 → Version 2.1.0 (old: 0/3 healthy)
T+90: Deployment complete, all instances on 2.1.0
```

**Pros**: Zero downtime, gradual traffic shift  
**Cons**: Complex rollback, mixed versions during deployment

### 2. Canary Deployment

Route small percentage of traffic to new version:

```
Timeline:
T+0:  Deploy 1 instance of version 2.1.0
T+30: Route 10% traffic to new version (monitor metrics)
T+60: Increase to 50% traffic (if healthy)
T+90: Increase to 100% traffic
```

**Pros**: Detect issues early, safe ramp-up  
**Cons**: Complex traffic routing, longer deployment time

### 3. Blue-Green Deployment

Two identical production environments, switch between them:

```
Blue Environment (Current):
  - Running version 2.0.0
  - Taking 100% traffic

Green Environment (New):
  - Running version 2.1.0
  - Staged, no traffic

After validation:
  - Switch traffic from Blue → Green
  - Keep Blue as instant rollback option
```

**Pros**: Instant rollback, zero downtime  
**Cons**: Double resource usage, synchronization complexity

## Rollback Strategies

### Automatic Rollback Triggers

```python
rollback_triggers = {
    "error_rate": {
        "threshold": "5%",
        "window": "60 seconds",
        "action": "automatic_rollback"
    },
    "latency": {
        "p99_threshold": "500ms",
        "p99_window": "120 seconds",
        "action": "scale_up_then_monitor"
    },
    "health_check": {
        "failure_count": 3,
        "window": "30 seconds",
        "action": "automatic_rollback"
    },
    "database": {
        "query_failure_rate": "10%",
        "action": "automatic_rollback"
    }
}
```

### Manual Rollback

```bash
curl -X POST http://control-plane:8012/deployments/dep-001/rollback \
  -H "Content-Type: application/json" \
  -d '{
    "reason": "business_decision",
    "target_version": "2.0.0",
    "approved_by": "user@company.com"
  }'
```

## Monitoring & Observability

### Key Metrics

```
# Deployment Metrics
deployment_duration_seconds
deployment_success_rate
deployment_rollback_rate
canary_error_rate_percentage
blue_green_switch_time_ms

# Resource Metrics
resource_allocation_rate
resource_utilization_percentage
cluster_node_utilization
network_bandwidth_usage_mbps

# Policy Metrics
policy_rule_triggers_total
automatic_rollback_count
policy_violation_count

# Operational Metrics
deployment_queue_length
deployment_concurrency
cluster_sync_latency_ms
audit_log_write_latency_ms
```

### Prometheus Scrape

```yaml
- job_name: 'control-plane'
  static_configs:
    - targets: ['localhost:8012']
  metrics_path: '/metrics'
  scrape_interval: 15s
```

### Grafana Dashboards

Create dashboards to visualize:

1. **Deployment Pipeline**: Current deployments, progress, success rate
2. **Resource Utilization**: CPU, memory, GPU, network by cluster
3. **Cluster Health**: Node status, service distribution, replication lag
4. **Policy Execution**: Triggered rules, automatic actions, violations
5. **Audit Trail**: Deployment history, policy changes, authorizations

### Log Aggregation

All logs available via activity-feed service:

```bash
curl "http://activity-feed:8010/search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "service:control-plane",
    "severity": "error",
    "time_range": "1h",
    "limit": 50
  }'
```

## Integration Examples

### With Auth-Server

Control plane verifies deployment authorization with auth-server:

```python
# Verify user can deploy to service
GET /auth-server/verify
{
    "user": "user@company.com",
    "action": "deploy",
    "resource": "auth-server",
    "tier": "senior"
}

# Response
{
    "authorized": true,
    "tier": "senior",
    "rate_limit": {
        "deployments_per_hour": 10,
        "used": 3,
        "remaining": 7
    }
}
```

### With Reputation Engine

Control plane checks reputation tier before allowing risky deployments:

```python
# Check if user can perform risky canary deployment
GET /reputation-engine/reputation/{user_id}

# If score < 5000, restrict to 1% canary
# If score >= 5000, allow 10% canary
# If score >= 7500, allow 50% initial canary
```

### With Activity Feed

All deployment events published to activity feed:

```python
# Deployment created event
{
    "event_type": "deployment_created",
    "service": "auth-server",
    "version": "2.1.0",
    "actor": "user@company.com",
    "timestamp": "2026-04-28T10:00:00Z",
    "details": {
        "deployment_id": "dep-001",
        "strategy": "canary"
    }
}

# Deployment completed event
{
    "event_type": "deployment_completed",
    "deployment_id": "dep-001",
    "status": "success",
    "duration_seconds": 300
}
```

## Production Deployment Checklist

- [ ] PostgreSQL 14+ with automated backups configured
- [ ] Redis 7+ running with persistence and replication
- [ ] Kafka 7+ cluster operational with replication factor 3
- [ ] TLS/SSL certificates installed and valid
- [ ] Auth-server health check passing
- [ ] Reputation-engine connectivity verified
- [ ] Resource quotas defined for each service
- [ ] Deployment policies reviewed and approved
- [ ] Audit retention policy set (recommend 365 days)
- [ ] Monitoring and alerting configured
- [ ] Grafana dashboards deployed
- [ ] Team trained on deployment procedures
- [ ] Runbooks documented for common scenarios
- [ ] Disaster recovery procedures tested

## Troubleshooting

### Deployment Stuck in "in_progress"

```bash
# Check current deployment status
curl http://control-plane:8012/deployments/{deployment_id}

# Check service health
curl http://control-plane:8012/health

# Check resource availability
curl http://control-plane:8012/resources?cluster=primary

# If service is healthy but deployment stuck:
# 1. Check database for locks
SELECT * FROM control_plane_db.locks WHERE deployment_id = '{deployment_id}';

# 2. Check Redis for state
redis-cli GET "deployment:{deployment_id}:state"

# 3. If needed, force cleanup:
DELETE /deployments/{deployment_id}?force=true
```

### Rollback Not Triggering

```bash
# Verify policy is active
curl http://control-plane:8012/policies?deployment_id={id}&status=active

# Check metric values
curl http://control-plane:8012/deployments/{id}/metrics

# Manually trigger if needed
curl -X POST http://control-plane:8012/deployments/{id}/rollback \
  -d '{"reason": "manual_trigger"}'
```

### Cluster Sync Issues

```bash
# Force full cluster sync
curl -X POST http://control-plane:8012/clusters/{cluster_id}/sync \
  -d '{"full_sync": true}'

# Check sync status
curl http://control-plane:8012/clusters/{cluster_id}/status

# View replication lag
curl http://control-plane:8012/clusters/{cluster_id}/metrics?metric=sync_latency
```

## Performance Tuning

### Connection Pool Optimization

```bash
# For high concurrency (100+ deployments)
CONTROL_PLANE_DB_POOL_SIZE=50
CONTROL_PLANE_DB_POOL_TIMEOUT=30
CONTROL_PLANE_REDIS_POOL_SIZE=30
```

### Deployment Check Frequency

```bash
# Default: check every 5 seconds
# For large clusters (50+ services): check every 10 seconds
DEPLOYMENT_CHECK_INTERVAL_SECONDS=10

# Reduces database load, increases detection latency
```

### Cluster Sync Optimization

```bash
# Default: sync every 30 seconds
# For large clusters: sync every 60 seconds
CLUSTER_SYNC_INTERVAL_SECONDS=60

# Reduces network traffic, increases drift detection time
```

## Related Services

- **auth-server**: Verifies deployment authorization
- **reputation_engine**: Enforces tier-based deployment permissions
- **activity_feed**: Streams all deployment events in real-time
- **memory-engine**: Stores deployment patterns for learning
- **agent-runtime**: Executes deployment tasks
- **execution-scheduler**: Schedules deployment jobs

## Support & Documentation

For additional support, see:

- [Deployment Procedures Guide](../../DEPLOYMENT_EXECUTION_PLAN.md)
- [Production Checklist](../../DEPLOYMENT_READINESS_FINAL.md)
- [Architecture Overview](../../COMPLETE_DEPLOYMENT_PROGRAM_SUMMARY.md)
- [GitHub Issues](https://github.com/kushin77/code-server/issues) - Tag: phase-3

---

**Status**: Production Ready  
**Last Updated**: April 28, 2026  
**Maintainer**: Code Server Enterprise Team
