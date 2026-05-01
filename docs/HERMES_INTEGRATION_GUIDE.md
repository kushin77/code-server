# Hermes Integration Guide

**Document**: `docs/HERMES_INTEGRATION_GUIDE.md`  
**Version**: 1.0  
**Status**: Production-Ready  
**Last Updated**: May 1, 2026  

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)  
2. [Component Reference](#component-reference)  
3. [Deployment Guide](#deployment-guide)  
4. [Operations Guide](#operations-guide)  
5. [Observability](#observability)  
6. [Troubleshooting](#troubleshooting)  
7. [Migration Guide](#migration-guide)  

---

## Architecture Overview

Hermes Integration is the **agent orchestration layer** for code-server. It coordinates execution across the four specialized agent containers, provides centralized health tracking, and exposes a unified dispatch API for triggering agent work.

```
┌────────────────────────────────────────────────────────────────────┐
│                          Hermes Integration                        │
│                        (hermes-integration:8000)                   │
│                                                                    │
│  ┌─────────────────┐   ┌──────────────────────────────────────┐   │
│  │  AgentRegistry  │   │        AgentOrchestrator             │   │
│  │  - register()   │   │  - dispatch(type, path, payload)     │   │
│  │  - heartbeat()  │   │  - broadcast(path, payload)          │   │
│  │  - probe_health │   │  - health_sweep()                    │   │
│  │  - mark_stale() │   │  - get_audit_log()                   │   │
│  └─────────────────┘   └──────────────────────────────────────┘   │
└─────────────────┬──────────────────────────────────────────────────┘
                  │ HTTP dispatch / healthcheck
        ┌─────────┴─────────┐
        ▼                   ▼
 ┌─────────────┐    ┌──────────────────┐
 │agent-runtime│    │  4 Agent Containers│
 │  port 8020  │    │  (port 9000 each) │
 │             │    │ code-reviewer     │
 │  Paperclip  │    │ incident-responder│
 │  OPA policy │    │ doc-writer        │
 │  Scheduler  │    │ test-generator    │
 └─────────────┘    └──────────────────┘
```

**Key design decisions:**
- Hermes is **additive** — agents work normally if Hermes is unreachable
- Agent registration is **self-directed** — each container registers on startup
- Routing is **type-based** with round-robin load balancing per type
- Liveness uses **HTTP probes** against `/health` endpoints (not sidecar)

---

## Component Reference

### `apps/hermes-integration/agent_registry.py`

Central in-memory store for all registered agents.

| Class/Method | Description |
|---|---|
| `AgentRegistry` | Main registry class |
| `.register(type, host, port)` | Register a new agent; returns `AgentRecord` |
| `.deregister(agent_id)` | Remove agent from registry |
| `.record_heartbeat(agent_id)` | Update `last_seen_at`, mark HEALTHY |
| `.probe_health(agent_id)` | Async HTTP GET to `/health` |
| `.probe_readiness(agent_id)` | Async HTTP GET to `/health/ready` |
| `.mark_stale_agents()` | Mark HEALTHY agents with >60 s no-heartbeat as UNREACHABLE |
| `.list_healthy()` | Return only HEALTHY agents |
| `.count_by_status()` | Dict of `{status: count}` |
| `AgentStatus` enum | `REGISTERING → HEALTHY → DEGRADED → UNREACHABLE → DRAINING → OFFLINE` |

**Stale threshold**: 60 seconds without a heartbeat → status set to `UNREACHABLE`.

**HA note**: The registry is currently in-process memory. For multi-replica HA, replace `_agents` dict with a Redis-backed store (same interface).

---

### `apps/hermes-integration/agent_orchestrator.py`

Routes execution requests to the best available agent.

| Class/Method | Description |
|---|---|
| `AgentOrchestrator` | Main orchestrator class |
| `.dispatch(type, path, payload)` | Route to best agent of type; retry up to 2× on network errors |
| `.broadcast(path, payload, types)` | Fan-out to all types in parallel |
| `.health_sweep()` | Probe all registered agents; update statuses |
| `.get_audit_log(limit)` | Return last N dispatch events |
| `DispatchResult` | Outcome model: `success`, `status_code`, `response_body`, `error`, `duration_ms` |

**Agent selection algorithm:**
1. Filter registry by `agent_type`
2. Prefer `HEALTHY` agents over `DEGRADED` agents
3. Round-robin within the selected pool

**Retry policy**: 2 retries on any `httpx.HTTPError` or exception (3 total attempts).

**Request timeout**: 30 seconds per dispatch.

---

### REST API Endpoints

Base URL: `http://hermes-integration:8000`

#### Agent Registry

| Method | Path | Description |
|---|---|---|
| `GET` | `/agents` | List all agents with status |
| `POST` | `/agents/register` | Register a new agent |
| `DELETE` | `/agents/{id}` | Deregister an agent |
| `POST` | `/agents/{id}/heartbeat` | Record agent heartbeat |
| `GET` | `/agents/{id}/health` | Live health probe for one agent |

#### Orchestration

| Method | Path | Description |
|---|---|---|
| `POST` | `/agents/dispatch` | Dispatch to best agent of type |
| `POST` | `/agents/broadcast` | Fan-out to multiple agent types |
| `POST` | `/agents/sweep` | Trigger health sweep of all agents |
| `GET` | `/agents/audit` | View recent dispatch audit log |

#### Existing Phase Management

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Liveness probe |
| `GET` | `/metrics` | Prometheus metrics |
| `GET` | `/phases/{n}` | Get phase details |
| `POST` | `/phases/{n}/test` | Run phase tests |
| `POST` | `/phases/{n}/commit` | Commit phase results |
| `GET` | `/status` | Full system status |

---

### Registration Payload

When an agent container starts, it POSTs to `/agents/register`:

```json
{
  "agent_id": "code-reviewer-app-host-1",
  "agent_type": "code-reviewer",
  "host": "code-server-agent-code-reviewer",
  "port": 9000,
  "metadata": {
    "version": "1.0.0",
    "capabilities": ["code-review"]
  }
}
```

Response:
```json
{
  "registered": true,
  "agent": {
    "agent_id": "code-reviewer-app-host-1",
    "agent_type": "code-reviewer",
    "status": "registering",
    "registered_at": "2026-05-01T08:00:00.000Z"
  }
}
```

---

### Dispatch Payload

```json
POST /agents/dispatch
{
  "agent_type": "code-reviewer",
  "path": "/execute",
  "payload": {
    "execution_id": "exec-abc123",
    "agent_type": "code-review",
    "input": "Review this PR diff..."
  }
}
```

Response (on success):
```json
{
  "dispatch_id": "dispatch-a1b2c3d4e5f6",
  "agent_id": "code-reviewer-host-1",
  "agent_type": "code-reviewer",
  "success": true,
  "status_code": 200,
  "response_body": { "result": "..." },
  "duration_ms": 142.7,
  "dispatched_at": "2026-05-01T08:01:00.000Z"
}
```

---

## Deployment Guide

### Docker Compose (Development)

The `hermes-integration` service is included in `docker-compose.yml` under profiles `ai`, `governance`, and `all`.

```bash
# Start with all AI services
docker compose --profile ai up -d

# Start everything
docker compose --profile all up -d

# Check hermes health
curl http://localhost:8000/health
```

**Environment variables** (`.env` or override):
```
HERMES_PORT=8000
AGENT_RUNTIME_URL=http://agent-runtime:8020
AGENT_CODE_REVIEWER_HOST=agent-code-reviewer
AGENT_CODE_REVIEWER_PORT=9000
AGENT_INCIDENT_RESPONDER_HOST=agent-incident-responder
AGENT_INCIDENT_RESPONDER_PORT=9000
AGENT_DOC_WRITER_HOST=agent-doc-writer
AGENT_DOC_WRITER_PORT=9000
AGENT_TEST_GENERATOR_HOST=agent-test-generator
AGENT_TEST_GENERATOR_PORT=9000
KAFKA_BROKER=redpanda:9092
```

### Terraform (Production)

Hermes is managed by `terraform/environments/private/modules/stack/containers-hermes.tf`.

```bash
cd terraform/environments/private
terraform plan -target=docker_container.hermes_integration
terraform apply -target=docker_container.hermes_integration
```

The Terraform resource:
- Creates container `code-server-hermes-integration`
- Port 8000 (internal + external)
- Depends on `agent_runtime` + all 4 agent containers
- Attached to `docker_network.services`
- Healthcheck: `curl -f http://localhost:8000/health`

### Kubernetes (Optional)

Apply with:
```bash
kubectl apply -f kubernetes/deployments/hermes-integration.yaml
kubectl apply -f kubernetes/services/internal-services.yaml
```

The Deployment:
- 2 replicas (RollingUpdate, maxUnavailable: 1)
- Non-root user (uid 1002)
- Resource limits: 500m CPU, 256Mi memory
- Liveness: `/health` every 30s
- Readiness: `/health` every 15s

---

## Operations Guide

### Checking Agent Status

```bash
# Via REST API
curl http://localhost:8000/agents | jq .

# Expected healthy output:
{
  "total": 4,
  "healthy": 4,
  "counts": {
    "healthy": 4,
    "registering": 0,
    "unreachable": 0
  }
}
```

### Manually Triggering a Health Sweep

```bash
curl -X POST http://localhost:8000/agents/sweep | jq .
```

### Dispatching Work Manually

```bash
curl -X POST http://localhost:8000/agents/dispatch \
  -H 'Content-Type: application/json' \
  -d '{
    "agent_type": "code-reviewer",
    "path": "/execute",
    "payload": {"execution_id": "manual-test-001", "input": "..."}
  }' | jq .
```

### Viewing Dispatch Audit Log

```bash
curl "http://localhost:8000/agents/audit?limit=20" | jq .entries[]
```

### Restarting Hermes

```bash
# Docker
docker restart code-server-hermes-integration

# Terraform (force replacement)
terraform taint docker_container.hermes_integration
terraform apply -target=docker_container.hermes_integration

# K8s
kubectl rollout restart deployment/hermes-integration -n code-server
```

After restart, agents re-register automatically within one heartbeat interval (30 s).

---

## Observability

### Health Endpoints

| Endpoint | Purpose | Expected Response |
|---|---|---|
| `GET /health` | Liveness probe | `{"status": "ok"}` |
| `GET /agents/{id}/health` | Agent-specific live probe | `{"status": "healthy", "ready": true}` |

### Prometheus Metrics

Hermes exposes metrics at `/metrics`. Scraped by `code-server-prometheus` automatically (annotation-based discovery via port 8000).

Key metrics to watch:
- `hermes_dispatch_total{agent_type, success}` — dispatch count by type + outcome
- `hermes_dispatch_duration_ms` — histogram of dispatch round-trip time
- `hermes_agents_healthy` — gauge of currently healthy agents
- `hermes_heartbeat_received_total{agent_type}` — heartbeat rate

### Grafana Dashboard

Import the Hermes dashboard from `grafana/dashboards/hermes-integration.json` (if present).

Key panels:
- Agent fleet status (healthy/degraded/unreachable)
- Dispatch success rate (last 5 min)
- Average dispatch latency per agent type
- Heartbeat frequency heatmap

### Structured Logging

All events are JSON-structured:
```json
{
  "ts": "2026-05-01T08:01:00.123Z",
  "svc": "hermes-integration",
  "level": "INFO",
  "msg": "agent_dispatch_complete",
  "dispatch_id": "dispatch-a1b2c3",
  "agent_id": "code-reviewer-host-1",
  "status_code": 200,
  "duration_ms": 143.2
}
```

Logs shipped to Loki via Docker `json-file` driver → Promtail → Loki.

Query in Grafana:
```logql
{container="code-server-hermes-integration"} | json | msg="agent_dispatch_complete"
```

### OpenTelemetry Tracing

Hermes registration and dispatch calls are traced via `hermes_tracing.py` in `apps/agent-runtime`. Spans appear in Grafana Tempo under service `hermes-integration`.

---

## Troubleshooting

### Agent appears UNREACHABLE after deployment

**Cause**: Agent container started before Hermes was ready, or heartbeat loop hasn't fired yet.

**Fix**:
```bash
# Wait one heartbeat interval (30 s), then check
curl http://localhost:8000/agents | jq '.counts'

# Or manually trigger a sweep
curl -X POST http://localhost:8000/agents/sweep
```

### Dispatch returns 502 "No healthy agents available"

**Cause**: All agents of the requested type are UNREACHABLE or DEGRADED.

**Diagnosis**:
```bash
curl http://localhost:8000/agents | jq '.agents[] | select(.agent_type == "code-reviewer")'
curl http://localhost:8000/agents/{agent_id}/health
```

**Fix**:
1. Check that the agent container is running: `docker inspect code-server-agent-code-reviewer`
2. Check agent logs: `docker logs code-server-agent-code-reviewer --tail 50`
3. Verify HERMES_URL is set in agent container env and points to Hermes correctly

### hermes_registration.py registers as wrong type

**Symptom**: All agents show as `agent-runtime` type in registry.

**Cause**: `AGENT_TYPE` env var not set in container.

**Fix**: Verify env in `docker-compose.yml` or Terraform:
```yaml
- AGENT_TYPE=code-reviewer   # must be set per-container
```

### Hermes container fails to start (Dockerfile build error)

**Cause**: Python version mismatch or missing build deps.

**Fix**: Ensure image is built from `apps/hermes-integration/Dockerfile` (python:3.11-slim multi-stage). Do not use `python:3.14` (not released).

---

## Migration Guide

### Activating Hermes in an Existing Deployment

1. **Deploy hermes-integration container** (Terraform or docker-compose)
2. **Set `HERMES_URL`** on all agent containers pointing to `http://code-server-hermes-integration:8000`
3. **Restart agent containers** — they will self-register with Hermes on startup
4. **Verify** with `curl http://localhost:8000/agents | jq '.healthy'` (should equal 5: runtime + 4 agents)

### Disabling Hermes (Rollback)

Hermes is non-blocking by design. To disable:
1. Unset `HERMES_URL` on all agent containers (or set to empty string)
2. Restart agents — they will start normally without registering
3. Stop the hermes-integration container

Agents continue executing directly without any Hermes coordination.

---

*Generated as part of Hermes Integration Phase 6 — Documentation & Handoff*  
*See also: `HERMES_INTEGRATION_PLAN.md` for full epic tracking*
