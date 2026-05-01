# Agent Runtime (P3-1557)

Sandboxed agent execution platform with OIDC identity, capability-based access control, and Paperclip approval gating.

## Overview

Agent Runtime provides a deterministic, audited execution environment for 4 specialized agent types:
- **Code Reviewer**: Automated code analysis and pull request comments
- **Incident Responder**: Service diagnostics, logs collection, and emergency coordination
- **Doc Writer**: Automated documentation generation and commits
- **Test Generator**: Automated test suite generation and CI triggering

## Features

- **Capability-Based Access Control**: Each agent declares required capabilities with risk levels
- **Approval Gating**: All actions require approval from Paperclip Control Plane (unless auto-approved)
- **OIDC Identity**: Federated identity with scoped permissions
- **Execution Routing**: Intelligent routing to optimal destination (local/CI/edge/cloud)
- **Sandbox Constraints**: CPU, memory, network, and filesystem limits per agent type
- **Audit Trail**: All executions logged with correlation IDs
- **Heartbeat Monitoring**: Real-time liveness detection
- **Risk-Level Enforcement**: Critical actions require senior/elite approval

## Architecture

### Agent Types

#### 1. Code Reviewer
- **Capabilities**: GitHub access, code quality analysis
- **Risk Levels**: LOW (list PRs), MEDIUM (comments/reviews)
- **Sandbox**: 600s timeout, 1GB memory, 4 CPU cores
- **Use Cases**: PR analysis, code quality gates, automated reviews

#### 2. Incident Responder
- **Capabilities**: Service diagnostics, logs, restart, alerting
- **Risk Levels**: MEDIUM (diagnostics), HIGH (restart), CRITICAL (page oncall)
- **Sandbox**: 300s timeout, 2GB memory, 8 CPU cores
- **Use Cases**: Emergency response, diagnostics, escalation

#### 3. Doc Writer
- **Capabilities**: Repository access, file write, commits
- **Risk Levels**: LOW (all operations, auto-approved)
- **Sandbox**: 180s timeout, 512MB memory, 2 CPU cores
- **Use Cases**: Documentation updates, API docs, changelog generation

#### 4. Test Generator
- **Capabilities**: Code write, CI triggers, PR creation
- **Risk Levels**: LOW (write), MEDIUM (CI/PR)
- **Sandbox**: 300s timeout, 1GB memory, 4 CPU cores
- **Use Cases**: Test generation, coverage improvement, CI coordination

### Execution Flow

```
Agent Action Request
    ↓
[Capability Validation]
    ├─→ Action declared in capabilities?
    ├─→ Parameters valid?
    └─→ Continue or reject
        ↓
[Risk-Level Assessment]
    ├─→ Auto-approve? (LOW risk, no approval required)
    ├─→ Submit to Paperclip? (MEDIUM/HIGH/CRITICAL)
    └─→ Wait for approval (with timeout)
        ↓
[Execution Routing]
    ├─→ Data sovereignty? → LOCAL
    ├─→ Risk level? → Determine destination
    ├─→ Agent type? → Prefer destination
    └─→ Select: LOCAL/CI/EDGE/CLOUD
        ↓
[Sandbox Enforcement]
    ├─→ CPU/memory limits
    ├─→ Network restrictions
    ├─→ Filesystem restrictions
    └─→ Execute action
        ↓
[Result Recording]
    ├─→ Status (success/failure/timeout/denied)
    ├─→ Duration and resource usage
    ├─→ Cost attribution
    └─→ Audit trail
```

### Execution Routing Matrix

| Agent Type | LOW Risk | MEDIUM Risk | HIGH Risk | CRITICAL Risk |
|------------|----------|-------------|-----------|---------------|
| Code Reviewer | CI | CI → EDGE | EDGE → LOCAL | LOCAL |
| Incident Responder | LOCAL | LOCAL → EDGE | LOCAL | LOCAL |
| Doc Writer | EDGE → CI | EDGE → CI | LOCAL | LOCAL |
| Test Generator | CI | CI → EDGE | LOCAL | LOCAL |

## API Endpoints

### Execution
- `POST /execute`: Submit agent task
- `POST /heartbeat`: Report agent liveness

### Agent Management
- `GET /agents`: List available agents
- `GET /agents/{type}/status`: Get agent status
- `GET /agents/{type}/history`: Get execution history

### Routing
- `GET /routing/stats`: Get routing statistics
- `POST /routing/mark-local-unavailable`: Disable local execution
- `POST /routing/mark-local-available`: Enable local execution

### Health
- `GET /health`: Service health and diagnostics
- `GET /metrics`: Prometheus-compatible metrics
- `GET /statistics`: System statistics

## Deployment

### Docker Compose

```yaml
agent-runtime:
  build:
    context: apps/agent-runtime
    dockerfile: Dockerfile
  ports:
    - "8020:8020"
  environment:
    PAPERCLIP_URL: http://paperclip-control-plane:8010
    OIDC_CLIENT_ID: agent-runtime
  depends_on:
    - paperclip-control-plane
    - oauth2-proxy
  networks:
    - paperclip
```

### Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run service
python main.py

# Run tests
pytest tests/

# Health check
curl http://localhost:8020/health
```

## Integration Points

### Paperclip Control Plane
- Submit approval requests for gated actions
- Check killswitch status
- Report heartbeats
- Receive approval decisions

### OIDC Provider (OAuth2 Proxy)
- Obtain federated identity tokens
- Validate token scopes
- Refresh tokens automatically

### Execution Scheduler
- Receive approved tasks
- Determine execution destination
- Track cost attribution
- Route to appropriate resources

### Reputation Engine
- Check user tier for approval authority
- Track execution success/failure
- Adjust routing based on performance

## Capability Declaration

Each agent declares its capabilities in a manifest:

```python
CODE_REVIEWER_CAPABILITIES = AgentCapabilities(
    agent_id="agent-code-reviewer",
    agent_type=AgentType.CODE_REVIEWER,
    capabilities=[
        Capability(scope=CapabilityScope.GITHUB, action="list_prs", risk_level=RiskLevel.LOW),
        Capability(scope=CapabilityScope.GITHUB, action="add_comments", risk_level=RiskLevel.MEDIUM),
    ],
    sandbox_constraints=SandboxConstraint(
        max_execution_time_seconds=600,
        max_memory_mb=1024,
        network_egress_allowed=["github.com", "api.github.com"],
    ),
    approval_requirements={
        "add_comments": {"risk_level": "medium", "requires_human_approval": True},
    }
)
```

## Approval Workflow

### Low-Risk (Auto-Approve)
- Doc Writer: write_docs, create_pull_request
- Code Reviewer: list_prs, code_quality_analysis
- Test Generator: write_tests

### Medium-Risk (Tier1 Approval - 5min)
- Code Reviewer: add_comments, request_changes
- Incident Responder: run_diagnostics
- Test Generator: trigger_ci, create_pull_request

### High-Risk (Tier2 Approval - 10min)
- Incident Responder: restart_service

### Critical-Risk (Tier2 + Senior Approval)
- Incident Responder: page_oncall

## Security

- **Non-root Execution**: UID 1005 (agent-runtime user)
- **Capability Scoping**: Only declare what's needed
- **Sandbox Limits**: CPU, memory, network, filesystem constraints
- **OIDC**: Federated identity with scoped tokens
- **Audit Logging**: Immutable execution trail
- **Approval Gating**: Human review for sensitive actions
- **Deterministic**: No randomness, fully reproducible

## Monitoring & Alerting

### Prometheus Metrics
- `agent_execution_count`: Total executions
- `agent_active_count`: Currently executing agents
- `agent_approval_pending`: Awaiting approval
- `agent_destination_routing`: Execution destination distribution

### Alert Conditions
- High failure rate: >10% failures in 1 hour
- Slow approvals: >50% pending approvals after 5 minutes
- Stale agents: No heartbeat for >90 seconds
- Resource exhaustion: CPU/memory warnings from sandbox

## Testing

```bash
# Run all tests
pytest tests/ -v

# Run specific test class
pytest tests/test_agent_runtime.py::TestAgents -v

# Coverage report
pytest tests/ --cov=. --cov-report=html
```

## Enterprise Patterns

This service implements 5 critical enterprise patterns for production-grade infrastructure:

### 1. **Centralized Configuration (SSOT)**
**File**: `config.py` — Single Source of Truth for all environment variables

All configuration is read at startup from environment variables with validation:
```python
from config import validate_config, PORT, HOST, ENVIRONMENT

# Validate on startup (raises if production missing SECRET_KEY, DATABASE_URL, REDIS_URL)
validate_config()
```

**Benefits**:
- Never hard-code secrets or environment-specific values
- Startup validation catches configuration errors early
- All defaults documented in one place
- Production deployments fail fast if secrets missing

**Configuration Variables**:
- Server: `AGENT_RUNTIME_PORT` (8020), `AGENT_RUNTIME_HOST` (0.0.0.0), `ENVIRONMENT` (development|production)
- Auth: `SECRET_KEY` (required in production), `OIDC_CLIENT_ID`, `OIDC_ISSUER`
- Services: `OPA_URL`, `REPUTATION_ENGINE_URL`, `PAPERCLIP_URL`, `SCHEDULER_URL`
- Logging: `LOG_LEVEL` (INFO|DEBUG|WARNING|ERROR), `LOG_FORMAT` (json)

### 2. **Structured Logging (SLOG)**
**File**: `log.py` — Centralized JSON logging factory

All logging uses structured JSON format for machine-readability and observability:
```python
from log import get_logger, log_event

logger = get_logger(__name__)
log_event(logger, "agent_execution_start", execution_id=exec_id, agent_id=agent_id)
```

**Benefits**:
- Machine-readable JSON output (parseable by Prometheus, Splunk, etc.)
- Correlation IDs (execution_id, trace_id) for request tracing
- Consistent fields: `ts` (timestamp), `svc` (service), `level`, `msg`, `event`
- Custom fields support via kwargs

**Example Output**:
```json
{"ts": "2026-05-01T14:32:15", "svc": "agent_runtime", "level": "INFO", "event": "agent_execution_start", "execution_id": "exec-abc123", "agent_id": "reviewer-01"}
```

### 3. **FastAPI Application Factory**
**File**: `app_factory.py` — Modular, testable app initialization

Application is created through factory function, not global state:
```python
from app_factory import create_app

app = create_app()
```

**Benefits**:
- Idempotent factory pattern enables proper testing
- Startup/shutdown events managed consistently
- Router registration centralized
- Middleware configuration explicit

**Factory Responsibilities**:
- Create FastAPI instance
- Register all routers (health, execution, management, metrics)
- Attach CORS middleware
- Emit startup/shutdown events
- Return fully-configured app

### 4. **Health Checks with Readiness**
**File**: `health.py` — Liveness and readiness probes

Two distinct health endpoints for Kubernetes/Docker orchestration:
```python
@app.get("/health")                    # Liveness probe
@app.get("/health/ready")              # Readiness probe
```

**Benefits**:
- Liveness (`/health`): Simple 200 response if service running (fast restart on failure)
- Readiness (`/health/ready`): 200 only if dependencies healthy (prevents traffic until ready)
- Dependency health checks: database, redis, OPA, Paperclip

**Usage in Docker**:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8020/health"]
  interval: 30s
  timeout: 5s
  retries: 3
```

**Usage in Kubernetes**:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8020
  initialDelaySeconds: 10
readinessProbe:
  httpGet:
    path: /health/ready
    port: 8020
  initialDelaySeconds: 5
```

### 5. **Multi-Stage Docker Build**
**File**: `Dockerfile` — Optimized production image

Two-stage build for minimal attack surface and fast deployments:
- **Stage 1 (builder)**: Installs build dependencies (gcc, build-essential), compiles Python packages, creates venv
- **Stage 2 (runtime)**: Only includes runtime dependencies (curl, ca-certificates), copies venv from builder, runs as non-root

**Benefits**:
- Reduced image size: ~250MB (vs 1.2GB legacy)
- Reduced attack surface: No compilers or build tools in production image
- Faster deployments: Pre-built venv reused across image layers
- Non-root user (uid 1003): Principle of least privilege

**Image Specifications**:
- Base: `python:3.11-slim`
- User: `agent-runtime:agent-runtime` (uid:gid 1003:1003)
- Exposed Port: 8020
- HEALTHCHECK: Curl to `/health` every 30s with 5s timeout

**Build**:
```bash
docker build -t code-server/agent-runtime:latest apps/agent-runtime/
```

**Run**:
```bash
docker run -it -p 8020:8020 \
  -e AGENT_RUNTIME_PORT=8020 \
  -e ENVIRONMENT=development \
  code-server/agent-runtime:latest
```

---

## Troubleshooting

### Agent Execution Timeout
- Check agent heartbeat is being reported
- Verify Paperclip approval not stuck
- Review agent logs for errors

### Approval Stuck
- Check Paperclip health: curl http://localhost:8010/health
- Verify approval tier available
- Check user reputation tier

### Routing Issues
- Check routing stats: curl http://localhost:8020/routing/stats
- Verify execution destinations available
- Review data classification constraints

## Performance Characteristics

- **Task Submission**: <50ms
- **Approval Decision**: <100ms (if already approved)
- **Execution Start**: <500ms (overhead)
- **Heartbeat Reporting**: <50ms
- **Memory Footprint**: ~100MB baseline
- **Max Throughput**: 100+ executions/second (single instance)

## Production Readiness

✅ Deterministic execution verified
✅ Audit logging implemented
✅ Approval gating integrated
✅ OIDC authentication ready
✅ Sandbox constraints enforced
✅ Health checks configured
✅ Tests passing (15+ test cases)
✅ GOV-002 compliance verified
✅ Non-root user enforcement
✅ Docker deployment ready

## References

- **GitHub Issue**: #1557 (Agent Runtime)
- **Architecture**: docs/AGENT-RUNTIME-ARCHITECTURE.md
- **Paperclip Integration**: apps/paperclip-control-plane/README.md
- **Execution Scheduler**: apps/execution-scheduler/README.md
