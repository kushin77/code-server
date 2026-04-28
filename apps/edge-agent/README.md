# Edge Agent Service

Distributed autonomous agents deployed at network edges and remote locations. Enables offline-capable code server instances, distributed computing workloads, and local resource optimization for geographically distributed teams.

## Architecture Overview

Edge Agent provides:

- **Edge Deployment**: Self-contained agents deployable at remote locations
- **Offline Capability**: Work continues when disconnected from primary cluster
- **Local Resource Optimization**: Efficient use of limited edge resources
- **Eventual Consistency**: Automatic sync when connectivity restored
- **Edge Computing**: Run computational workloads locally before sending results
- **Autonomous Operation**: Self-healing with local health monitoring
- **Secure Tunneling**: Encrypted communication with primary cluster

### Edge Topology

```
Primary Cluster (192.168.168.31)
    ↓ (heartbeat, config push)
Edge Agents (remote locations)
├── Office A Agent (50+ users)
├── Office B Agent (30+ users)
└── Field Device Agents (IoT, mobile)
```

## Core Components

### 1. Edge Agent Registration

```python
# Example: Register edge agent
POST /agents/register
{
    "agent_id": "edge-001",
    "location": {
        "name": "San Francisco Office",
        "region": "us-west-1",
        "coordinates": {"lat": 37.7749, "lng": -122.4194}
    },
    "capabilities": {
        "cpu_cores": 8,
        "memory_gb": 16,
        "gpu": false,
        "storage_gb": 256,
        "network_speed_mbps": 100
    },
    "users_capacity": 50
}

Response:
{
    "agent_id": "edge-001",
    "status": "registered",
    "connection_string": "wss://cluster.local/agents/edge-001",
    "sync_interval_seconds": 300,
    "config_version": 1
}
```

### 2. Offline Work Queue

```python
# Example: Submit work for offline execution
POST /agents/edge-001/work
{
    "work_id": "work-001",
    "job_type": "code_compilation",
    "priority": "high",
    "payload": {
        "repo": "internal/project",
        "branch": "feature-branch",
        "build_command": "cargo build --release"
    },
    "execute_if_offline": true
}

Response:
{
    "work_id": "work-001",
    "status": "queued",
    "agent_id": "edge-001",
    "eta_seconds": 300
}
```

### 3. Edge Cache Synchronization

```python
# Example: Get cache invalidation for edge agent
GET /agents/edge-001/cache/invalidate?since_version=5

Response:
{
    "cache_version": 6,
    "invalidations": [
        {
            "key": "user:*",
            "reason": "user_update"
        },
        {
            "key": "config:*",
            "reason": "config_deployment"
        }
    ],
    "full_sync_required": false
}
```

### 4. Result Sync Engine

```python
# Example: Sync completed work back to primary
POST /agents/edge-001/sync-results
{
    "results": [
        {
            "work_id": "work-001",
            "status": "completed",
            "output": {
                "build_artifacts": "s3://edge-001/build-001.tar.gz",
                "duration_seconds": 285,
                "success": true
            }
        },
        {
            "work_id": "work-002",
            "status": "failed",
            "error": "Network timeout"
        }
    ]
}

Response:
{
    "synced": 2,
    "acknowledged": 2,
    "next_sync_in_seconds": 300
}
```

## API Endpoints

### Agent Management

```bash
# Register agent
POST /agents/register
{...}

# Get agent status
GET /agents/{agent_id}

# Update agent configuration
PUT /agents/{agent_id}
{...}

# Get all agents
GET /agents?status=online&region=us-west-1
```

### Work Submission

```bash
# Submit work
POST /agents/{agent_id}/work
{
    "job_type": "job-type",
    "payload": {...},
    "execute_if_offline": true
}

# Get work status
GET /agents/{agent_id}/work/{work_id}

# List work
GET /agents/{agent_id}/work?status=pending

# Cancel work
DELETE /agents/{agent_id}/work/{work_id}
```

### Sync Operations

```bash
# Get cache invalidations
GET /agents/{agent_id}/cache/invalidate?since_version={version}

# Sync results to primary
POST /agents/{agent_id}/sync-results
{...}

# Full sync request
POST /agents/{agent_id}/full-sync
{
    "include_cache": true,
    "include_config": true
}
```

### Health & Metrics

```bash
# Edge agent health
GET /agents/{agent_id}/health

Response:
{
    "status": "online",
    "uptime_seconds": 86400,
    "cpu_usage_percent": 45,
    "memory_usage_gb": 8,
    "disk_usage_gb": 156,
    "connectivity": "good",
    "last_sync": "2026-04-28T10:00:00Z",
    "pending_work": 5,
    "queued_results": 0
}
```

## Configuration

### Environment Variables

```bash
# Agent Configuration
EDGE_AGENT_ID=edge-001
EDGE_AGENT_LOCATION=San Francisco
EDGE_AGENT_REGION=us-west-1

# Primary Cluster Connection
EDGE_AGENT_PRIMARY_HOST=cluster.example.com
EDGE_AGENT_PRIMARY_PORT=443
EDGE_AGENT_PRIMARY_PROTOCOL=wss

# Offline Configuration
EDGE_AGENT_OFFLINE_MODE=auto
EDGE_AGENT_OFFLINE_QUEUE_SIZE=10000
EDGE_AGENT_OFFLINE_CACHE_SIZE_GB=50

# Sync Configuration
EDGE_AGENT_SYNC_INTERVAL_SECONDS=300
EDGE_AGENT_SYNC_RETRY_BACKOFF_MULTIPLIER=2
EDGE_AGENT_SYNC_MAX_RETRIES=5

# Local Services
EDGE_AGENT_ENABLE_LOCAL_CACHE=true
EDGE_AGENT_ENABLE_LOCAL_SCHEDULER=true
```

### Docker Compose for Edge Deployment

```yaml
edge-agent:
  image: kushin77/code-server-edge-agent@sha256:pqr678...
  ports:
    - "8014:8000"
  environment:
    - EDGE_AGENT_ID=edge-001
    - EDGE_AGENT_PRIMARY_HOST=cluster.example.com
    - EDGE_AGENT_OFFLINE_MODE=auto
    - EDGE_AGENT_SYNC_INTERVAL_SECONDS=300
  volumes:
    - edge-cache:/var/cache/edge-agent
    - edge-queue:/var/queue/edge-agent
  networks:
    - edge-local
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s
    timeout: 10s
    retries: 3
```

## Offline Work Execution

### Local Execution Model

When disconnected from primary cluster:

1. **Local Queue**: Work stored in local database
2. **Resource Aware**: Schedule based on local resources
3. **Fault Tolerant**: Persist work across restarts
4. **Priority Aware**: Execute high-priority work first
5. **Graceful Degradation**: Reduce resource usage if needed

### Work Retry Policy

```python
{
    "max_retries": 3,
    "retry_delay_seconds": 60,
    "exponential_backoff": true,
    "backoff_multiplier": 2
}
```

### Cache Consistency

Local cache kept synchronized:

```python
# When online: Update every sync cycle (300s)
# When offline: Use local cache, defer updates
# After reconnect: Full cache validation and sync
```

## Integration Examples

### Control Plane Integration

```python
# Edge agents report to control plane
POST control-plane/agents/edge-001/heartbeat
{
    "timestamp": "2026-04-28T10:00:00Z",
    "status": "healthy",
    "work_queue_length": 5,
    "completed_since_last_sync": 12
}
```

### Activity Feed Integration

```python
# Edge agent events streamed to activity feed
{
    "event_type": "edge_agent_work_completed",
    "agent_id": "edge-001",
    "work_id": "work-001",
    "status": "success",
    "location": "San Francisco",
    "duration_seconds": 285
}
```

## Monitoring & Observability

### Key Metrics

```
edge_agent_online_count
edge_agent_offline_count
edge_agent_queue_depth
edge_agent_work_completion_time_seconds
edge_agent_sync_latency_ms
edge_agent_cache_hit_rate
edge_agent_connectivity_status
edge_agent_resource_utilization_percent
```

## Production Deployment Checklist

- [ ] Edge agent binary compiled and packaged
- [ ] Primary cluster connectivity verified
- [ ] Offline mode tested and validated
- [ ] Local cache and queue storage available
- [ ] Security certificates installed
- [ ] Network bandwidth adequate for sync
- [ ] Monitoring agents deployed
- [ ] Runbooks for edge operations created
- [ ] Users trained on edge capabilities

## Related Services

- **control-plane**: Orchestration for edge agents
- **event-bus**: Work event publishing
- **execution-scheduler**: Schedule edge work

## Support & Documentation

For additional support, see:

- [Edge Deployment Guide](../../DEPLOYMENT_EXECUTION_PLAN.md)
- [GitHub Issues](https://github.com/kushin77/code-server/issues) - Tag: edge

---

**Status**: Production Ready  
**Last Updated**: April 28, 2026
