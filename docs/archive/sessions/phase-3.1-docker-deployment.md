# Edge Agent Phase 3.1: Docker Integration & Deployment Guide

**Status**: 🚀 READY FOR DEPLOYMENT  
**Date**: April 25, 2026  
**Phase**: 3.1 (Docker Configuration)  
**Governance**: 100% IaC, Immutable, Idempotent  

---

## Overview

Phase 3.1 packages the Edge Agent registration and heartbeat infrastructure into production-ready Docker containers:

1. **Edge Agent Container** — Agent registration and heartbeat daemon
2. **Health Monitor Container** — Centralized health monitoring
3. **Docker Compose Integration** — Multi-region deployment template
4. **GitHub Actions Workflow** — Automated testing and validation

---

## Files Delivered

### Container Images (2)

| File | Purpose | Size | Status |
|------|---------|------|--------|
| `apps/edge-agent/Dockerfile` | Edge agent runtime | 50 LOC | ✅ Ready |
| `apps/edge-agent/Dockerfile.monitor` | Health monitor runtime | 40 LOC | ✅ Ready |

### Configuration Files (2)

| File | Purpose | Lines | Status |
|------|---------|-------|--------|
| `apps/edge-agent/requirements.txt` | Python dependencies | 40 LOC | ✅ Ready |
| `docker-compose.edge-agent.yml` | Multi-service orchestration | 200+ LOC | ✅ Ready |

### CI/CD Automation

| File | Purpose | Tests | Status |
|------|---------|-------|--------|
| `.github/workflows/test-edge-agent.yml` | Test & build automation | 6+ | ✅ Ready |

---

## Quick Start

### Prerequisites

```bash
# Required: Docker and docker-compose installed
docker --version    # >= 24.0
docker-compose --version  # >= 2.20

# Required: Environment variables set
export OAUTH2_CLIENT_ID=your-client-id
export OAUTH2_CLIENT_SECRET=your-client-secret
```

### Deployment Steps

#### Step 1: Build Edge Agent Images

```bash
# Build edge agent container
docker build -t paperclip/edge-agent:latest \
  -f apps/edge-agent/Dockerfile .

# Build health monitor container
docker build -t paperclip/edge-agent-monitor:latest \
  -f apps/edge-agent/Dockerfile.monitor .

# Verify builds
docker images | grep edge-agent
# paperclip/edge-agent          latest    abc123...
# paperclip/edge-agent-monitor  latest    def456...
```

#### Step 2: Deploy Edge Agent Services

```bash
# Option A: Use docker-compose with edge agent services
docker-compose -f docker-compose.yml \
               -f docker-compose.edge-agent.yml \
               up -d

# Option B: Deploy edge agents only (without main services)
docker-compose -f docker-compose.edge-agent.yml up -d

# Verify deployment
docker-compose ps
# NAME                          STATUS
# control-plane-edge-api        Up 30s (healthy)
# edge-agent-us-west-1          Up 15s (healthy)
# edge-agent-us-east-1          Up 15s (healthy)
# edge-agent-eu-central-1       Up 15s (healthy)
# edge-agent-health-monitor     Up 10s (healthy)
```

#### Step 3: Verify Agent Registration

```bash
# List all registered agents
curl http://localhost:8080/api/v1/edge-agents

# Expected response (3 agents, all ACTIVE):
# {
#   "agents": [
#     {
#       "id": "edge-agent-us-west-1",
#       "status": "ACTIVE",
#       "location": "us-west",
#       "capacity": 8,
#       "lastHeartbeat": "2026-04-25T12:00:35Z",
#       "registeredAt": "2026-04-25T12:00:00Z"
#     },
#     ...
#   ],
#   "total": 3,
#   "healthy": 3,
#   "unhealthy": 0
# }
```

#### Step 4: Monitor Health Status

```bash
# Watch agent health metrics
watch -n 5 'curl -s http://localhost:8080/api/v1/edge-agents | jq .'

# Check individual agent status
curl http://localhost:8080/api/v1/edge-agents/edge-agent-us-west-1/status

# View health monitor logs
docker logs edge-agent-health-monitor --follow
```

---

## Container Architecture

### Edge Agent Container

**Image**: `paperclip/edge-agent:latest`

```dockerfile
FROM python:3.11-slim
EXPOSE 8081
HEALTHCHECK: curl -f http://localhost:8081/health

Processes:
├─ [PID 1] Python FastAPI server
└─ [PID N] Heartbeat daemon (started via register-edge-agent.sh)

Volumes:
├─ /var/log/edge-agent (logs, mounted to host)
├─ /etc/edge-agent/certs (TLS certificates, read-only)

Environment:
├─ CONTROL_PLANE=http://control-plane:8080
├─ EDGE_LOCATION=us-west
├─ EDGE_CAPACITY=8
├─ HEARTBEAT_INTERVAL=30
├─ HEARTBEAT_TIMEOUT=60
```

**Startup Sequence**:
1. Validate environment variables
2. Register agent with control plane
3. Start heartbeat daemon (background)
4. Start health check server
5. Ready to receive work

**Health Check**:
```bash
# Checks if heartbeat process is running
curl -f http://localhost:8081/health

# Succeeds if:
# - Heartbeat daemon process exists
# - Control plane connectivity OK
# - Last heartbeat within 60s
```

### Health Monitor Container

**Image**: `paperclip/edge-agent-monitor:latest`

```dockerfile
FROM python:3.11-slim
EXPOSE 9090
HEALTHCHECK: curl -f http://localhost:9090/metrics

Processes:
├─ [PID 1] Health monitoring loop
└─ [Child] Prometheus metrics exporter

Volumes:
├─ /var/log/health-monitor (logs, mounted to host)

Environment:
├─ CONTROL_PLANE=http://control-plane:8080
├─ HEALTH_CHECK_INTERVAL=10
├─ HEARTBEAT_TIMEOUT=60
├─ PROMETHEUS_ENABLED=true
├─ PROMETHEUS_PORT=9090
```

**Monitoring Loop**:
```
Every 10 seconds:
1. Fetch all registered agents from control plane
2. For each agent:
   - Calculate: now - last_heartbeat
   - If > 60s: Mark as UNHEALTHY
   - Log state changes
3. Export metrics to Prometheus
4. Sleep 10s, repeat
```

**Prometheus Metrics**:
```
# Agent registry metrics
edge_agent_count{location="us-west"} = 1
edge_agent_healthy_count = 3
edge_agent_unhealthy_count = 0

# Heartbeat metrics
edge_agent_heartbeat_latency_ms{agent="us-west-1"} = 45
edge_agent_last_heartbeat_seconds{agent="us-west-1"} = 5

# Registration metrics
edge_agent_registration_total{location="us-west"} = 1
edge_agent_registration_errors_total = 0
```

---

## Docker Compose Configuration

### Single-Replica Setup (Development)

```yaml
# docker-compose.edge-agent.yml
services:
  control-plane-edge-api:        # Main control plane
  edge-agent-us-west-1:          # Worker 1 (West)
  edge-agent-us-east-1:          # Worker 2 (East)
  edge-agent-eu-central-1:       # Worker 3 (Europe)
  edge-agent-health-monitor:     # Monitoring
```

**Networking**:
```
                                  ┌─ postgres-db:5432
control-plane ────────────────────┼─ redis-cache:6379
     ▲                             └─ redis-sentinel-1
     │
     ├─ edge-agent-us-west-1 (heartbeat every 30s)
     ├─ edge-agent-us-east-1 (heartbeat every 30s)
     ├─ edge-agent-eu-central-1 (heartbeat every 30s)
     └─ edge-agent-health-monitor (health check every 10s)

All on: paperclip-network (bridge)
```

### Multi-Replica Setup (Production)

```bash
# Deploy to Replica 1 (Primary)
ssh root@192.168.168.31 'cd /code-server-enterprise && \
  docker-compose -f docker-compose.yml \
                 -f docker-compose.edge-agent.yml \
                 up -d'

# Deploy to Replica 2 (Secondary)
ssh root@192.168.168.42 'cd /code-server-enterprise && \
  docker-compose -f docker-compose.yml \
                 -f docker-compose.edge-agent.yml \
                 up -d'

# Verify both replicas
curl http://192.168.168.31:8080/api/v1/edge-agents
curl http://192.168.168.42:8080/api/v1/edge-agents
```

---

## Configuration Reference

### Environment Variables

| Variable | Default | Required | Purpose |
|----------|---------|----------|---------|
| `CONTROL_PLANE` | `http://localhost:8080` | ✅ | Control plane URL |
| `EDGE_LOCATION` | (required) | ✅ | Agent location (us-west, us-east, eu-central) |
| `EDGE_CAPACITY` | `8` | ✅ | Max concurrent tasks |
| `EDGE_AGENT_ID` | (generated) | ✅ | Unique agent identifier |
| `HEARTBEAT_INTERVAL` | `30` | ❌ | Seconds between heartbeats |
| `HEARTBEAT_TIMEOUT` | `60` | ❌ | Seconds to mark agent offline |
| `HEALTH_CHECK_INTERVAL` | `10` | ❌ | Seconds between health checks |
| `LOG_LEVEL` | `INFO` | ❌ | DEBUG, INFO, WARN, ERROR |
| `AGENT_TLS_ENABLED` | `true` | ❌ | Enable TLS for agent communication |

### Example docker-compose Overrides

```yaml
# docker-compose.override.yml
services:
  edge-agent-us-west-1:
    environment:
      LOG_LEVEL: DEBUG
      HEARTBEAT_INTERVAL: 15
    ports:
      - "8081:8081"  # Expose for local debugging
```

---

## GitHub Actions Workflow

### Test Triggers

The workflow runs automatically on:
- ✅ Push to `apps/edge-agent/` or `scripts/edge-agent/`
- ✅ Pull requests affecting edge agent code
- ✅ Manual trigger via `workflow_dispatch`

### Tests Performed

| Test | Purpose | Time |
|------|---------|------|
| Python Linting (flake8) | Code style | 30s |
| Type Checking (mypy) | Type safety | 30s |
| Shell Script Validation | Syntax check | 20s |
| Docker Build | Container build | 90s |
| Docker Health Check | Health endpoint | 30s |
| Pytest (unit tests) | Python tests | 60s |
| Security Scan (Trivy) | Vulnerability scan | 45s |

**Total Workflow Time**: ~5-10 minutes

### Sample Workflow Output

```
✅ Test Edge Agent
├─ build-and-test
│  ├─ Checkout code ... OK (2s)
│  ├─ Set up Python 3.11 ... OK (10s)
│  ├─ Install dependencies ... OK (45s)
│  ├─ Lint Python files ... OK (30s)
│  ├─ Type check with mypy ... OK (30s)
│  ├─ Format check with black ... OK (20s)
│  ├─ Validate shell scripts ... OK (20s)
│  ├─ Run Python tests ... OK (60s)
│  ├─ Build Docker image ... OK (90s)
│  ├─ Test Docker image ... OK (30s)
│  └─ Upload coverage reports ... OK (5s)
└─ security-scan
   ├─ Run Trivy scanner ... OK (45s)
   └─ Upload to GitHub Security ... OK (10s)

🎉 All tests passed! (Total: 8m 35s)
```

---

## Deployment Checklist

### Prerequisites (Before Deployment)

- [ ] Docker installed (`docker --version`)
- [ ] docker-compose >= 2.20 installed
- [ ] Git repository cloned locally
- [ ] Environment variables configured (`.env` file)
- [ ] SSH access to both replicas (if multi-region)

### Build Phase

- [ ] Edge agent image builds successfully
- [ ] Health monitor image builds successfully
- [ ] Image layers are minimal (no unnecessary files)
- [ ] Health checks defined for both images

### Deployment Phase (Single Replica)

- [ ] docker-compose.edge-agent.yml syntax valid
- [ ] All services start: `docker-compose ps` shows all HEALTHY
- [ ] Control plane health check passes
- [ ] Agents register successfully
- [ ] Heartbeats received (check agent status)

### Monitoring Phase

- [ ] Health monitor detects agents
- [ ] Prometheus metrics exported
- [ ] Logs written to host volumes
- [ ] Agent status queries return correct data

### Multi-Replica Deployment

- [ ] Deploy to Replica 1 successfully
- [ ] Deploy to Replica 2 successfully
- [ ] Agents from both replicas visible in registry
- [ ] Failover test: Stop Replica 1, verify Replica 2 takes over

### Testing & Validation

- [ ] GitHub Actions workflow passes
- [ ] All unit tests pass
- [ ] Docker build succeeds
- [ ] Container starts and health check passes
- [ ] Agent registration idempotent (tested)
- [ ] Heartbeat processing verified
- [ ] Health monitoring detects timeouts

---

## Troubleshooting

### Issue: Docker build fails with "requirements.txt not found"

**Cause**: Dockerfile run context incorrect

**Solution**:
```bash
# Build from repository root
cd /code-server-enterprise
docker build -t paperclip/edge-agent:latest -f apps/edge-agent/Dockerfile .
```

### Issue: Containers start but agents show UNHEALTHY

**Cause**: Control plane not accessible from agent container

**Solution**:
```bash
# Check network connectivity
docker-compose exec edge-agent-us-west-1 \
  curl -v http://control-plane-edge-api:8080/health

# Check environment variable
docker-compose exec edge-agent-us-west-1 \
  printenv | grep CONTROL_PLANE
```

### Issue: Heartbeat timeout occurring immediately

**Cause**: Heartbeat interval too short or timeout too aggressive

**Solution**:
```bash
# Increase timeout in docker-compose.override.yml
services:
  edge-agent-health-monitor:
    environment:
      HEARTBEAT_TIMEOUT: 120  # Increase from 60
      HEALTH_CHECK_INTERVAL: 20  # Increase from 10
```

### Issue: Health monitor shows 0 metrics

**Cause**: Prometheus endpoint not accessible

**Solution**:
```bash
# Check health monitor logs
docker logs edge-agent-health-monitor

# Verify endpoint
curl http://localhost:9090/metrics

# Check if Prometheus scrape config added to main prometheus.yml
```

---

## Performance Tuning

### Heartbeat Optimization

```bash
# Balance between responsiveness and load
HEARTBEAT_INTERVAL=30      # Every 30s (default)
HEARTBEAT_INTERVAL=15      # Every 15s (more frequent)
HEARTBEAT_INTERVAL=60      # Every 60s (less frequent)

# Timeout should be > 2x interval to avoid false positives
HEARTBEAT_TIMEOUT=60       # Default: 2x interval
HEARTBEAT_TIMEOUT=90       # For slow networks
```

### Resource Limits

```yaml
# Add to docker-compose.override.yml
services:
  edge-agent-us-west-1:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

### Scaling to Multiple Agents

```bash
# Generate 10 edge agent services programmatically
for i in {1..10}; do
  cat >> docker-compose.override.yml << EOF
  edge-agent-worker-$i:
    image: paperclip/edge-agent:latest
    environment:
      EDGE_AGENT_ID: edge-agent-worker-$i
      EDGE_LOCATION: us-west
    depends_on:
      - control-plane-edge-api
EOF
done

# Deploy all
docker-compose up -d
```

---

## Next Steps

### Phase 3.2: Integration Testing

```bash
# Test suite checklist
[ ] Registration idempotency test
[ ] Heartbeat processing test
[ ] Health monitoring timeout test
[ ] Multi-agent coordination test
[ ] Failover scenario test
```

### Phase 4: Global Load Balancing

```
Phase 3.1 (CURRENT): Docker containers
├─ Edge Agent Docker images ✅
├─ docker-compose integration ✅
├─ GitHub Actions workflow ✅
└─ Multi-region deployment template ✅

Phase 4 (NEXT): Global Distribution
├─ User→Region affinity mapping
├─ Geolocation-based routing
├─ Asset cache distribution
└─ Differential sync protocol
```

---

## Governance Compliance

✅ **IaC**: All Docker configs version-controlled  
✅ **Immutable**: No secrets in images, all env-based  
✅ **Idempotent**: Containers safe to redeploy  
✅ **GOV-002**: All files have governance headers  

---

## Related Documentation

- `PHASE-3-REGISTRATION-HEARTBEAT.md` — Protocol specification
- `PHASE-3-INTEGRATION-GUIDE.md` — General integration guide
- `docker-compose.yml` — Main deployment template
- `docker-compose.edge-agent.yml` — Edge agent services

