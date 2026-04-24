# Execution Scheduler - Architecture & Operations Guide

## Overview

The Execution Scheduler is a cost/latency-aware task routing engine that decides where to execute compute workloads:
- **LOCAL**: User's machine (fastest, no cost)
- **CI**: GitHub Actions runners (free tier or paid)
- **EDGE**: Volunteer compute from engineer laptops (zero cost)

**Decision Logic**:
```
IF data_classification in [confidential, restricted]
  → LOCAL only (security boundary)
ELSE IF task_type in [ai_inference, model_training] AND gpu_available > 50%
  → LOCAL (fastest for GPU)
ELSE IF local_cpu_saturation < 70% AND cpu_cores_needed <= 8
  → LOCAL (preferred, sunk cost)
ELSE IF task_type in [test_suite, lint, build]
  → CI (free tier, designed for these)
ELSE IF user_reputation_tier == elite AND local_available > 20%
  → LOCAL priority access
ELSE IF edge_nodes available
  → EDGE (volunteer compute)
ELSE
  → CI (default fallback)
```

## API Reference

### 1. Submit Task for Scheduling

```http
POST /scheduler/submit
Content-Type: application/json

{
  "task_type": "ai_inference",
  "data_classification": "public",
  "estimated_cpu_cores": 4,
  "estimated_duration_seconds": 300,
  "estimated_tokens": 5000,
  "user_id": "user-123",
  "user_reputation_tier": "standard"
}

Response 200:
{
  "task_id": "task-a1b2c3d4e5f6",
  "destination": "local",
  "reason": "GPU available locally for inference task",
  "cost_estimate": 0.0,
  "latency_estimate_ms": 100,
  "confidence": 0.95,
  "fallback_destination": "ci"
}
```

### 2. Complete Task Execution

```http
POST /scheduler/tasks/task-a1b2c3d4e5f6/complete
?destination=local&duration_seconds=245&cpu_cores_used=4&tokens_used=4800&status=success

Response 200:
{
  "task_id": "task-a1b2c3d4e5f6",
  "status": "recorded",
  "cost_usd": 0.0096,
  "timestamp": "2026-04-25T14:30:00Z"
}
```

**Cost Calculation**:
- LOCAL: $0/task (sunk cost)
- CI free tier: $0/task
- CI paid runners: $0.035/minute
- EDGE: $0/task (volunteer)
- AI tokens: $0.002 per 1000 tokens

### 3. Get Real-time Resources

```http
GET /scheduler/resources

Response 200:
{
  "local": {
    "cpu_available_percent": 45.5,
    "gpu_available_percent": 62.0,
    "memory_available_gb": 18.5
  },
  "ci": {
    "idle_runners": 3,
    "queue_depth": 5,
    "estimated_wait_minutes": 8
  },
  "edge": {
    "available_nodes": 2,
    "total_available_cores": 16
  },
  "timestamp": "2026-04-25T14:30:00Z"
}
```

### 4. Get Monthly Costs

```http
GET /scheduler/costs/monthly

Response 200:
{
  "total_cost": 45.32,
  "budget_usd": 500.0,
  "budget_remaining": 454.68,
  "budget_utilization_percent": 9.06,
  "budget_exceeded": false,
  "enforce_cost_controls": false,
  "breakdown": {
    "local": {
      "count": 143,
      "cost": 0.0,
      "duration_hours": 18.5
    },
    "ci": {
      "count": 28,
      "cost": 0.0,
      "duration_hours": 12.3
    },
    "ci_paid": {
      "count": 3,
      "cost": 45.32,
      "duration_hours": 21.6
    },
    "edge": {
      "count": 18,
      "cost": 0.0,
      "duration_hours": 9.2
    }
  },
  "timestamp": "2026-04-25T14:30:00Z"
}
```

### 5. List All Tasks

```http
GET /scheduler/tasks?destination=local&limit=50

Response 200:
{
  "tasks": [
    {
      "task_id": "task-a1b2c3d4e5f6",
      "destination": "local",
      "duration_seconds": 245,
      "cost_usd": 0.0096,
      "tokens_used": 4800
    }
  ],
  "total": 189,
  "timestamp": "2026-04-25T14:30:00Z"
}
```

## Kafka Event Schema

All scheduler decisions published to Kafka topics:

### Topic: scheduler.task.submitted
```json
{
  "event_id": "uuid-...",
  "event_type": "scheduler.task.submitted",
  "schema_version": "1.0",
  "timestamp": "2026-04-25T14:30:00Z",
  "source": {"service": "execution-scheduler", "instance": "primary"},
  "actor": {"type": "human", "id": "user-123"},
  "payload": {
    "task_id": "task-a1b2c3d4e5f6",
    "task_type": "ai_inference",
    "destination": "local",
    "reason": "GPU available locally for inference task",
    "cost_estimate": 0.0,
    "user_id": "user-123"
  }
}
```

### Topic: scheduler.task.routed
```json
{
  "event_type": "scheduler.task.routed",
  "payload": {
    "task_id": "task-a1b2c3d4e5f6",
    "destination": "local",
    "routing_latency_ms": 12,
    "confidence": 0.95,
    "fallback_destination": "ci"
  }
}
```

### Topic: scheduler.task.completed
```json
{
  "event_type": "scheduler.task.completed",
  "payload": {
    "task_id": "task-a1b2c3d4e5f6",
    "destination": "local",
    "status": "success",
    "duration_seconds": 245,
    "cost_usd": 0.0096,
    "tokens_used": 4800,
    "error_message": null
  }
}
```

## Resource Monitoring

Scheduler continuously monitors three tiers:

### Local Resources (30s poll interval)
- CPU utilization (cores, percent available)
- GPU utilization & memory (CUDA/ROCm)
- System RAM (GB available)
- Disk I/O metrics

### CI Resources
- GitHub Actions queue depth
- Available runners (idle count)
- Estimated wait time based on queue
- Runner type capabilities

### Edge Nodes
- Node registry (hostname, capacity)
- Health checks (heartbeat < 2 minutes)
- Per-node CPU/GPU/memory availability
- Utilization thresholds (>80% excluded from routing)

## Cost Model

### Local: $0/hour (Sunk Cost)
User's own hardware already purchased. Preferred choice when capacity available.

### CI Runners: Free + Paid Options
- **Free tier**: Included with GitHub, 2000 minutes/month
- **Paid runners**: $0.035/minute ($2.10/hour) for compute-intensive tasks

### Edge: $0/hour (Volunteer)
Engineer volunteer compute when they have spare capacity.

### AI Token Costs: $0.002 per 1000 tokens
Applied when task uses LLM inference (estimated_tokens > 0).

## Budget Controls

**Monthly Budget**: $500 USD (configurable)

**Enforcement Tiers**:
- **< 50%**: No restrictions
- **50-80%**: Warning alerts logged
- **80-100%**: Cost controls enforced
  - Prefer LOCAL over CI paid runners
  - Route non-critical tasks to edge
  - Increase latency tolerance
- **> 100%**: Budget exceeded
  - Force all non-GPU tasks to CI free tier
  - Restrict new paid runner submissions
  - Alert owner

## Observability

### Prometheus Metrics (Scraped every 15 seconds)
```
scheduler_tasks_submitted_total{destination="local|ci|edge"}
scheduler_tasks_completed_total{destination=..., status="success|failure"}
scheduler_task_duration_seconds{destination=...}
scheduler_routing_decision_latency_ms
scheduler_cost_usd_total{destination=...}
scheduler_resource_utilization_percent{resource="cpu|gpu|memory"}
scheduler_ci_queue_depth
scheduler_edge_nodes_available
scheduler_monthly_spend_usd
scheduler_monthly_budget_utilization_percent
```

### Grafana Dashboard
Dashboard JSON available at: `grafana/dashboards/execution-scheduler.json`

Panels:
1. **Tasks by Destination** (pie chart)
2. **Cost Trend** (line graph, rolling 30-day)
3. **Resource Utilization** (gauge: local/CI/edge)
4. **Routing Confidence** (histogram)
5. **Budget Status** (gauge with thresholds)
6. **Task Duration Distribution** (histogram)

### Alert Rules (Prometheus)

1. **SchedulerBudgetExceeded** (CRITICAL)
   - Condition: `scheduler_monthly_spend_usd > scheduler_monthly_budget_usd`
   - Duration: 5m
   - Action: Page on-call engineer

2. **SchedulerCIQueueHigh** (WARNING)
   - Condition: `scheduler_ci_queue_depth > 50`
   - Duration: 10m
   - Action: Consider routing to edge/local

3. **SchedulerLocalSaturated** (WARNING)
   - Condition: `scheduler_resource_utilization_percent{resource="cpu"} > 90`
   - Duration: 5m
   - Action: Route new tasks to CI

4. **SchedulerEdgeNodesUnavailable** (WARNING)
   - Condition: `scheduler_edge_nodes_available == 0` AND `scheduler_ci_queue_depth > 20`
   - Duration: 15m
   - Action: Investigate edge node connectivity

## Troubleshooting

### Task always routes to CI despite local capacity
**Cause**: Local resources not being reported
**Fix**: Check local resource monitor:
```bash
curl http://localhost:8000/scheduler/resources | jq .local
```
If CPU/GPU show 0%, restart local monitor:
```bash
sudo systemctl restart execution-scheduler-monitor
```

### Budget exceeded but no expensive tasks visible
**Cause**: Paid CI runners accumulating costs
**Fix**: Check breakdown:
```bash
curl http://localhost:8000/scheduler/costs/monthly | jq .breakdown.ci_paid
```
Filter task list for ci_paid destination:
```bash
curl http://localhost:8000/scheduler/tasks?destination=ci_paid
```

### Edge nodes registered but not used
**Cause**: Heartbeat failing, nodes marked unhealthy
**Fix**: Verify edge node connectivity:
```bash
for node in edge-01 edge-02; do
  ping -c 1 $node.local && echo "$node OK" || echo "$node DOWN"
done
```

## Deployment

### Docker Compose Service
```yaml
execution-scheduler:
  image: paperclip/execution-scheduler:latest@sha256:...
  ports:
    - "8000:8000"
  environment:
    KAFKA_BROKERS: "kafka:9092"
    MONTHLY_CI_BUDGET_USD: "500"
  volumes:
    - type: bind
      source: ./config/scheduler-rules.yaml
      target: /app/config/scheduler-rules.yaml
      read_only: true
  depends_on:
    - kafka
    - prometheus
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s
    timeout: 10s
    retries: 3
```

### Configuration (config/scheduler-rules.yaml)
```yaml
routing_rules:
  - name: "sensitive-data-local-only"
    condition:
      data_classification: ["confidential", "restricted"]
    force_destination: "local"
    priority: 1000
  
  - name: "gpu-inference-local"
    condition:
      task_type: ["ai_inference", "model_training"]
    force_destination: "local"
    priority: 500
  
  - name: "ci-free-tier-tests"
    condition:
      task_type: ["test_suite", "lint", "build"]
    prefer_destination: "ci"
    priority: 100

resource_thresholds:
  local_cpu_saturation_percent: 70
  local_memory_available_gb: 4
  ci_queue_depth_threshold: 50
  edge_utilization_max_percent: 80

budget:
  monthly_usd: 500
  enforce_controls_at_percent: 80
```

## Integration with Kafka Event Bus

The Execution Scheduler publishes three event types to Kafka:

1. **scheduler.task.submitted**: When user submits task
2. **scheduler.task.routed**: When routing decision made (may differ from submission)
3. **scheduler.task.completed**: When task finishes execution

These events are consumed by:
- **Activity Feed**: Aggregates into unified activity stream
- **Cost Reporting**: Feeds billing system
- **Observability**: Prometheus scrapes for metrics
- **Audit Logging**: Maintained for compliance

## Performance Targets

- Routing decision: < 50ms (p95)
- Resource monitoring: < 30s stale (configurable)
- Cost calculation: < 10ms
- Kafka event publish: < 100ms
- Monthly cost report generation: < 5s

## Security

### Authentication
- All API endpoints authenticated via GitHub OAuth
- Service-to-service: mTLS with short-lived certificates

### Authorization
- Users can only see/manage own tasks
- Budget enforcement applies per-organization
- Admin endpoints require organization owner role

### Data Classification
- Confidential/restricted data routed LOCAL only (never leaves machine)
- Cost data visible to organization admins only
- Task details PII-scrubbed in logs/metrics
