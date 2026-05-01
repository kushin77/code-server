# Edge Agent Phase 3: Integration & Deployment Guide

**Status**: ✅ PHASE 3 IMPLEMENTATION COMPLETE  
**Governance**: 100% IaC, Immutable, Idempotent  
**Target Deployment**: Q3 2026  

---

## Quick Start

### 1. Verify All Phase 3 Components Deployed

```bash
# Check all scripts present
ls -la scripts/edge-agent/
ls -la apps/edge-agent/
ls -la apps/control-plane/edge_agent_handlers.py

# Expected output:
# scripts/edge-agent/register-edge-agent.sh
# scripts/edge-agent/monitor-edge-agent-health.sh
# apps/edge-agent/models.py
# apps/control-plane/edge_agent_handlers.py
```

### 2. Start Edge Agent Daemon

```bash
# Set environment variables
export CONTROL_PLANE="http://control-plane:8080"
export EDGE_LOCATION="us-west"
export EDGE_CAPACITY="8"

# Register edge agent (idempotent)
bash scripts/edge-agent/register-edge-agent.sh --agent-id=worker-01

# Expected output:
# [2026-04-24 12:00:00 UTC] SUCCESS: Agent worker-01 registered successfully
# [2026-04-24 12:00:00 UTC] SUCCESS: Heartbeat daemon started (PID: 12345)
```

### 3. Verify Registration in Control Plane

```bash
# Query agent registry
curl http://localhost:8080/api/v1/edge-agents

# Expected response:
# {
#   "agents": [
#     {
#       "id": "worker-01",
#       "status": "ACTIVE",
#       "location": "us-west",
#       "capacity": 8,
#       "lastHeartbeat": "2026-04-24T12:00:10Z",
#       "registeredAt": "2026-04-24T12:00:00Z"
#     }
#   ],
#   "total": 1,
#   "healthy": 1,
#   "unhealthy": 0
# }
```

### 4. Monitor Agent Health

```bash
# Start health monitoring (background)
bash scripts/edge-agent/monitor-edge-agent-health.sh &

# Verify monitoring started
sleep 5
curl http://localhost:8080/api/v1/edge-agents/worker-01/status

# Expected response:
# {
#   "id": "worker-01",
#   "status": "ACTIVE",
#   "lastHeartbeat": "2026-04-24T12:00:35Z",
#   "heartbeatCount": 3
# }
```

---

## Deployment Architecture

### Single-Replica Setup (Development)

```
┌─────────────────────────────────────────┐
│        Docker Host (192.168.168.31)     │
├─────────────────────────────────────────┤
│                                         │
│  Control Plane (:8080)                  │
│  ├─ FastAPI server                      │
│  ├─ Agent registry (in-memory)          │
│  └─ Heartbeat handler                   │
│                                         │
│  Edge Agent #1 (:8081)                  │
│  ├─ Registration daemon                 │
│  ├─ Heartbeat sender (30s)              │
│  └─ Health check                        │
│                                         │
│  Edge Agent #2 (:8082)                  │
│  ├─ Registration daemon                 │
│  ├─ Heartbeat sender (30s)              │
│  └─ Health check                        │
│                                         │
│  Health Monitor                         │
│  ├─ Checks all agents (10s)             │
│  ├─ Detects timeouts (60s)              │
│  └─ Logs state changes                  │
│                                         │
└─────────────────────────────────────────┘
```

### Multi-Replica Setup (Production)

```
┌──────────────────────────────┐  ┌──────────────────────────────┐
│  Primary (192.168.168.31)    │  │ Secondary (192.168.168.42)   │
├──────────────────────────────┤  ├──────────────────────────────┤
│ Control Plane (ACTIVE)       │  │ Control Plane (STANDBY)      │
│ Edge Agent x3                │  │ Edge Agent x3                │
│ Health Monitor               │  │ Health Monitor               │
└──────────────────────────────┘  └──────────────────────────────┘
                │                             │
                └─────────┬───────────────────┘
                          │
                    PostgreSQL (16)
                    Replicated
```

---

## File Structure

```
scripts/edge-agent/
├── register-edge-agent.sh          # Agent registration (idempotent)
└── monitor-edge-agent-health.sh    # Health monitoring

apps/edge-agent/
├── models.py                       # Pydantic schemas
├── Dockerfile                      # Edge agent container (TBD)
└── requirements.txt               # Python dependencies (TBD)

apps/control-plane/
└── edge_agent_handlers.py          # FastAPI endpoints

tests/edge-agent/
├── test_registration_idempotency.py
├── test_heartbeat_processing.py
└── test_health_monitoring.py
```

---

## Configuration Reference

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CONTROL_PLANE` | `http://localhost:8080` | Control plane URL |
| `EDGE_LOCATION` | (required) | Agent location (us-west, us-east, etc.) |
| `EDGE_CAPACITY` | `8` | Max concurrent tasks |
| `HEARTBEAT_INTERVAL` | `30` | Seconds between heartbeats |
| `HEARTBEAT_TIMEOUT` | `60` | Seconds to mark offline |
| `HEALTH_CHECK_INTERVAL` | `10` | Seconds between health checks |
| `REGISTRATION_RETRY_MAX` | `3` | Max registration attempts |
| `LOG_LEVEL` | `INFO` | Logging verbosity (DEBUG, INFO, WARN, ERROR) |

### Example .env File

```bash
# Control Plane Configuration
CONTROL_PLANE=http://control-plane:8080
CONTROL_PLANE_TOKEN=secret-token-12345

# Edge Agent Configuration
EDGE_LOCATION=us-west
EDGE_CAPACITY=8
EDGE_AGENT_ID=worker-01

# Heartbeat Configuration
HEARTBEAT_INTERVAL=30
HEARTBEAT_TIMEOUT=60

# Monitoring Configuration
HEALTH_CHECK_INTERVAL=10
REGISTRATION_RETRY_MAX=3

# Logging
LOG_LEVEL=INFO
LOG_DIR=/var/log/edge-agent
```

---

## Docker Compose Integration (TBD - Phase 3.1)

### Planned Service Definition

```yaml
services:
  control-plane:
    image: paperclip/control-plane:latest
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgresql://appuser:apppass@postgres:5432/appdb
      - REDIS_URL=redis://redis-cache:6379
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  edge-agent-1:
    image: paperclip/edge-agent:latest
    depends_on:
      control-plane:
        condition: service_healthy
    environment:
      - CONTROL_PLANE=http://control-plane:8080
      - EDGE_LOCATION=us-west
      - EDGE_CAPACITY=8
      - EDGE_AGENT_ID=worker-01
    volumes:
      - ./logs/edge-agent-1:/var/log/edge-agent
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  edge-agent-2:
    image: paperclip/edge-agent:latest
    depends_on:
      control-plane:
        condition: service_healthy
    environment:
      - CONTROL_PLANE=http://control-plane:8080
      - EDGE_LOCATION=us-west
      - EDGE_CAPACITY=8
      - EDGE_AGENT_ID=worker-02
    volumes:
      - ./logs/edge-agent-2:/var/log/edge-agent
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8082/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  edge-health-monitor:
    image: paperclip/edge-health-monitor:latest
    depends_on:
      - control-plane
      - edge-agent-1
      - edge-agent-2
    environment:
      - CONTROL_PLANE=http://control-plane:8080
      - HEALTH_CHECK_INTERVAL=10
      - HEARTBEAT_TIMEOUT=60
    volumes:
      - ./logs/health-monitor:/var/log/health-monitor
```

---

## Testing Procedures

### Test 1: Registration Idempotency

```bash
#!/bin/bash
# Test that registering same agent twice produces idempotent result

echo "[TEST 1] Registration Idempotency"

# First registration
echo "First registration..."
bash scripts/edge-agent/register-edge-agent.sh --agent-id=test-agent-1

# Verify in registry
echo "Checking registry..."
AGENT_1=$(curl -s http://localhost:8080/api/v1/edge-agents/test-agent-1)
TIMESTAMP_1=$(echo $AGENT_1 | grep -o '"registeredAt":"[^"]*' | cut -d'"' -f4)

echo "First registration timestamp: $TIMESTAMP_1"

# Second registration (same agent)
echo "Second registration (same agent)..."
sleep 2
bash scripts/edge-agent/register-edge-agent.sh --agent-id=test-agent-1

# Verify timestamp unchanged
echo "Checking registry again..."
AGENT_2=$(curl -s http://localhost:8080/api/v1/edge-agents/test-agent-1)
TIMESTAMP_2=$(echo $AGENT_2 | grep -o '"registeredAt":"[^"]*' | cut -d'"' -f4)

echo "Second registration timestamp: $TIMESTAMP_2"

if [ "$TIMESTAMP_1" == "$TIMESTAMP_2" ]; then
  echo "✅ TEST PASSED: Timestamps match (idempotent)"
else
  echo "❌ TEST FAILED: Timestamps differ (not idempotent)"
  exit 1
fi
```

### Test 2: Heartbeat Processing

```bash
#!/bin/bash
# Test that heartbeats are processed correctly

echo "[TEST 2] Heartbeat Processing"

# Register agent
bash scripts/edge-agent/register-edge-agent.sh --agent-id=test-agent-2

# Wait for initial heartbeat
sleep 35

# Check heartbeat count
HEARTBEATS=$(curl -s http://localhost:8080/api/v1/edge-agents/test-agent-2/status \
  | grep -o '"heartbeatCount":[0-9]*' | cut -d':' -f2)

echo "Heartbeats received: $HEARTBEATS"

if [ "$HEARTBEATS" -gt 0 ]; then
  echo "✅ TEST PASSED: Heartbeats processed"
else
  echo "❌ TEST FAILED: No heartbeats received"
  exit 1
fi
```

### Test 3: Health Monitoring Timeout

```bash
#!/bin/bash
# Test that health monitor detects offline agents

echo "[TEST 3] Health Monitoring Timeout"

# Register agent
AGENT_ID="test-agent-3"
bash scripts/edge-agent/register-edge-agent.sh --agent-id=$AGENT_ID

# Start health monitor
bash scripts/edge-agent/monitor-edge-agent-health.sh &
MONITOR_PID=$!

# Let heartbeats run for 30 seconds
sleep 30

# Kill heartbeat daemon (simulate agent crash)
HEARTBEAT_PIDS=$(pgrep -f "heartbeat.*$AGENT_ID")
kill $HEARTBEAT_PIDS 2>/dev/null

# Wait for health monitor to detect (> 60s timeout)
echo "Waiting for health monitor to detect offline status..."
sleep 70

# Check agent status
STATUS=$(curl -s http://localhost:8080/api/v1/edge-agents/$AGENT_ID/status \
  | grep -o '"status":"[^"]*' | cut -d'"' -f4)

echo "Agent status: $STATUS"

# Clean up
kill $MONITOR_PID 2>/dev/null

if [ "$STATUS" == "UNHEALTHY" ] || [ "$STATUS" == "OFFLINE" ]; then
  echo "✅ TEST PASSED: Agent marked offline"
else
  echo "❌ TEST FAILED: Agent not marked offline (status: $STATUS)"
  exit 1
fi
```

---

## Monitoring & Observability

### Logs Location

```
artifacts/edge-agent-logs/
├── agent-worker-01.log          # Agent 1 registration + heartbeat
├── agent-worker-02.log          # Agent 2 registration + heartbeat
├── health-monitor.log           # Health monitoring
└── control-plane.log            # Control plane API
```

### Key Log Events

```
[2026-04-24 12:00:00] [REGISTER] Agent worker-01 registration request
[2026-04-24 12:00:00] [REGISTER] Agent worker-01 registered successfully
[2026-04-24 12:00:00] [HEARTBEAT] Daemon started for worker-01 (PID: 12345)
[2026-04-24 12:00:30] [HEARTBEAT] worker-01 heartbeat received (healthy, 2/8 tasks)
[2026-04-24 12:00:60] [HEARTBEAT] worker-01 heartbeat received (healthy, 3/8 tasks)
[2026-04-24 12:01:30] [HEARTBEAT] worker-01 heartbeat received (healthy, 2/8 tasks)
[2026-04-24 12:02:00] [HEALTH] Monitoring: 2 agents, 2 healthy, 0 unhealthy
```

### Prometheus Metrics (TBD)

```
# Agent registration count
edge_agent_registrations_total{location="us-west"}

# Agent heartbeat latency (ms)
edge_agent_heartbeat_latency_ms{agent_id="worker-01"}

# Agent health status
edge_agent_status{agent_id="worker-01"} = 1 (ACTIVE) / 0 (OFFLINE)

# Agent task utilization
edge_agent_task_utilization{agent_id="worker-01"} = 3 (3/8 tasks)
```

---

## Troubleshooting

### Issue: Agent registration fails with "Connection refused"

**Cause**: Control plane not running or incorrect URL

**Solution**:
```bash
# Verify control plane is running
curl http://localhost:8080/health

# If failed, start control plane
docker-compose up -d control-plane

# Retry registration
bash scripts/edge-agent/register-edge-agent.sh --agent-id=worker-01
```

### Issue: Heartbeat not being received

**Cause**: Heartbeat daemon not running or port blocked

**Solution**:
```bash
# Check heartbeat process running
pgrep -f "heartbeat.*worker-01"

# If empty, heartbeat daemon crashed. Check logs
tail -100 artifacts/edge-agent-logs/agent-worker-01.log

# Restart registration (creates new heartbeat daemon)
bash scripts/edge-agent/register-edge-agent.sh --agent-id=worker-01
```

### Issue: Agent marked UNHEALTHY immediately after registration

**Cause**: Heartbeat timeout too short or network delay

**Solution**:
```bash
# Increase heartbeat timeout
export HEARTBEAT_TIMEOUT=120

# Restart health monitoring
bash scripts/edge-agent/monitor-edge-agent-health.sh &
```

---

## Deployment Runbook

### Phase 3.1: Docker Container Build

```bash
# Create Dockerfile for edge-agent
cat > apps/edge-agent/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY models.py .
COPY register-edge-agent.sh ./scripts/
COPY monitor-edge-agent-health.sh ./scripts/
RUN chmod +x scripts/*.sh
HEALTHCHECK --interval=30s --timeout=5s CMD curl -f http://localhost:8081/health || exit 1
ENTRYPOINT ["bash", "scripts/register-edge-agent.sh"]
EOF

# Build image
docker build -t paperclip/edge-agent:latest apps/edge-agent/
```

### Phase 3.2: Docker Compose Integration

```bash
# Add to docker-compose.yml (see above)
docker-compose up -d control-plane edge-agent-1 edge-agent-2 edge-health-monitor
```

### Phase 3.3: Verify Deployment

```bash
# Check all services running
docker-compose ps

# Verify registry
curl http://localhost:8080/api/v1/edge-agents

# Check logs
docker-compose logs edge-agent-1
docker-compose logs health-monitor
```

---

## Success Criteria (Phase 3)

✅ **Completed**:
- Registration script (idempotent, error handling)
- Health monitoring script (timeout detection)
- Python data models (Pydantic validation)
- Control plane API handlers (5+ endpoints)

✅ **Verified**:
- All scripts tested locally
- Models type-checked (mypy)
- API endpoints validated

⏳ **Pending**:
- Docker container build
- docker-compose integration
- End-to-end testing
- Multi-replica deployment

---

## Next Steps (Phase 4)

Phase 4 will implement:
1. **Localized Caching** — Assets cached on edge agents
2. **Differential Sync** — Optimize asset distribution
3. **Cache Invalidation** — Update protocol for cached assets
4. **Locality-Aware Routing** — Direct traffic to nearest agent

**Estimated**: 2-3 weeks

---

## Related Issues & PRs

- Issue #1768 — Edge Agent & Global Distribution (Q3 CRITICAL)
- PR #1770 — Phase 3 implementation
- PR #1771 — Docker integration (TBD)
- PR #1772 — Integration tests (TBD)

---

## Governance Compliance

✅ **IaC**: All code version-controlled  
✅ **Immutable**: No secrets embedded, all config via env vars  
✅ **Idempotent**: All operations safe to re-run  
✅ **GOV-002**: All files include governance headers  

