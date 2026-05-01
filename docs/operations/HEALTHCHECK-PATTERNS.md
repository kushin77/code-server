# Healthcheck Patterns Reference
**Best Practices & Proven Configurations for Service Health Monitoring**

---

## Overview

This guide documents healthcheck patterns proven effective for different service types in the code-server deployment. Each pattern includes rationale, timing values, and troubleshooting guidance.

**Key Principle:** Healthchecks must be image-aware and protocol-aware. Generic patterns fail; service-specific tuning required.

---

## 1. Python FastAPI Services

### Pattern
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

### Rationale
- **Startup Grace (40s):** Python interpreter startup + fastapi app initialization (avg 30-35s)
- **Interval (30s):** Standard for stateless services; fast enough to detect failures
- **Timeout (10s):** curl default; should succeed in <1s for healthy endpoint, 10s is safety margin
- **Retries (3):** 3 failures × 30s interval = 90s before marking unhealthy

### Prerequisites in Image
```dockerfile
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
```

### Health Endpoint (Example)
```python
from fastapi import FastAPI

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}
```

### Services Using This Pattern
- code-server-testing (port 8888)
- code-server-multimodal-ai (port 8040, with FastAPI enhancement)
- code-server-edge-agent (port 8060, with FastAPI enhancement)
- code-server-control-plane (port 8086)
- code-server-activity-feed (port 8004)

### Troubleshooting
| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| `health: starting` after 2 min | Image missing curl or dependencies | Add curl to Dockerfile; verify imports work |
| `unhealthy` after startup | Health endpoint not responding | Check port mapping; verify `@app.get("/health")` exists |
| Frequent restarts | Timeout too short | Increase `start_period` to 60s; check app logs |
| Container crashes during probe | Health endpoint bugs | Wrap endpoint in try/catch; return 500 instead of crashing |

---

## 2. Java Application Services

### Pattern
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/api/health"]
  interval: 30s
  timeout: 15s
  retries: 3
  start_period: 90s  # ← Critical: Java startup is slow
```

### Rationale
- **Startup Grace (90s):** JVM startup + class loading + Spring Boot initialization (avg 60-80s)
  - JVM itself: 5-10s
  - Class loading: 20-40s
  - Spring context initialization: 30-50s
- **Timeout (15s):** Java apps can have brief GC pauses; 15s gives headroom
- **Interval (30s):** Standard; Java services are stable once running
- **Retries (3):** 3 failures × 30s = 90s additional grace period

### Prerequisites in Image
```dockerfile
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
```

### Services Using This Pattern
- code-server-gitlab (port 8101) — uses more aggressive start_period 120s
- code-server-artifact-repo (port 8083, Nexus) — uses start_period 90s

### Tuning for Slow Builds
If service is slower on your infrastructure:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
  interval: 30s
  timeout: 15s
  retries: 3
  start_period: 120s  # Extended for slower builds
```

### Troubleshooting
| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Restart loop during startup | `start_period` too short | Check pod logs; likely still initializing; increase start_period |
| OOMKilled after startup | Java heap insufficient | Increase container memory; add `-Xmx` JVM arg |
| Slow health checks | GC pauses | Normal; consider tuning GC options in JVM args |

### Example: GitLab (special case)
```yaml
code-server-gitlab:
  image: gitlab/gitlab-ce:16.7.1
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:80/-/health"]
    interval: 30s
    timeout: 15s
    retries: 3
    start_period: 120s  # Extra time for GitLab's complex init
```

---

## 3. Go Binary Services

### Pattern
```yaml
healthcheck:
  test: ["CMD", "/app/health-check"]  # or built-in health endpoint
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s  # ← Go binaries start very fast
```

### Rationale
- **Startup Grace (10s):** Go binaries compile to single binary; no interpreter overhead (startup < 500ms)
- **Timeout (5s):** Go services respond very quickly; 5s is ample
- **Interval (30s):** Standard
- **Retries (3):** Standard

### Pattern Options

**Option A: Built-in Health Binary**
```yaml
healthcheck:
  test: ["CMD", "/app/binary-name", "health"]  # Health subcommand
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

**Option B: HTTP Health Endpoint**
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

**Option C: TCP Port Check (simplest)**
```yaml
healthcheck:
  test: ["CMD", "nc", "-z", "localhost", "PORT"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

### Services Using Go (None Currently)
*No current Go services in the deployment, but this pattern applies to future services.*

### Troubleshooting
| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| health-check binary not found | Dockerfile doesn't include it | Copy health binary into image; ensure it's executable |
| `exit code 1` | Health check failed | Verify binary logic; check logs |

---

## 4. Node.js/Express Services

### Pattern
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 20s  # Node startup faster than Python/Java but slower than Go
```

### Rationale
- **Startup Grace (20s):** Node process + module loading + app initialization (avg 15-18s)
- **Timeout (10s):** Node services respond quickly; 10s is comfortable margin
- **Interval (30s):** Standard
- **Retries (3):** Standard

### Prerequisites in Image
```dockerfile
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
```

### Health Endpoint (Example)
```javascript
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});
```

### Services Using This Pattern (None Currently)
*Future services implementing Express, NestJS, etc. should use this pattern.*

---

## 5. Native CLI Tools (Vault, Redis, etc.)

### Pattern A: Vault (Binary Probe)
```yaml
healthcheck:
  test: ["CMD", "sh", "-c", "VAULT_ADDR=http://127.0.0.1:8200 vault status"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s
```

### Rationale
- Uses native `vault status` CLI command (no external tools needed)
- HTTP override via VAULT_ADDR env var (crucial for dev mode HTTP)
- Very fast response (< 1s typically)
- Startup grace (10s) because Vault binary initialization is quick

### Key Lesson
✅ **DO:** Use service's native CLI tool if available
❌ **DON'T:** Use generic curl probes for services with native health tools

### Services Using This Pattern
- code-server-vault (port 8200) — uses `vault status` probe

### Troubleshooting
| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| unhealthy but container running | VAULT_ADDR not set or wrong protocol | Override in healthcheck test; use `VAULT_ADDR=http://127.0.0.1:8200` |
| `vault status` not found | Image missing vault binary | Dockerfile must be official Vault image |

### Pattern B: Redis (Alternative)
```yaml
healthcheck:
  test: ["CMD", "redis-cli", "ping"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 5s
```

### Services Using This Pattern
- code-server-redis (no explicit healthcheck; could add this)

---

## 6. Database Services

### PostgreSQL Pattern
```yaml
healthcheck:
  test: ["CMD", "pg_isready", "-U", "postgres"]
  interval: 10s
  timeout: 5s
  retries: 3
  start_period: 30s
```

**Key:** Uses `pg_isready` native tool; very efficient.

### MySQL/MariaDB Pattern
```yaml
healthcheck:
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
  interval: 10s
  timeout: 5s
  retries: 3
  start_period: 30s
```

### Services Using These Patterns
- code-server-postgres (currently uses docker official, may not have explicit healthcheck)

---

## 7. Message Queue Services (Kafka, RabbitMQ)

### Kafka (Redpanda) Pattern
```yaml
healthcheck:
  test: ["CMD", "rpk", "cluster", "info"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

### Services Using This Pattern
- code-server-redpanda (currently running; should verify healthcheck)

### RabbitMQ Pattern (if needed)
```yaml
healthcheck:
  test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 20s
```

---

## 8. Generic HTTP Services (Any Language)

### Minimal Pattern
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/health", "-m", "5"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

**Flags:**
- `-f` — Fail if HTTP response code is not 2xx/3xx
- `-m 5` — Timeout at 5 seconds (fail fast inside container)

### Fallback Pattern (if curl unavailable)
```yaml
healthcheck:
  test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:PORT/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

**Note:** wget is lighter-weight than curl; use if image is size-constrained.

---

## 9. Services Without Health Endpoints

### Pattern: Port Check Only
```yaml
healthcheck:
  test: ["CMD", "test", "-S", "/dev/tcp/localhost/PORT"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

**Limitations:** Detects listening port but not app health. Use only if health endpoint unavailable.

### Pattern: Process Check
```yaml
healthcheck:
  test: ["CMD", "pgrep", "process-name"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

**Limitations:** Detects process but not app health. Not recommended for production.

---

## Timing Reference Quick Lookup

| Service Type | Startup Grace | Interval | Timeout | Retries |
|--------------|---|---|---|---|
| **Python FastAPI** | 40s | 30s | 10s | 3 |
| **Python (heavy)** | 60s | 30s | 10s | 3 |
| **Java/Spring** | 90s | 30s | 15s | 3 |
| **Node.js** | 20s | 30s | 10s | 3 |
| **Go binary** | 10s | 30s | 5s | 3 |
| **Vault CLI** | 10s | 30s | 10s | 3 |
| **PostgreSQL** | 30s | 10s | 5s | 3 |
| **Generic HTTP** | 30s | 30s | 10s | 3 |

---

## Common Mistakes & How to Avoid

### ❌ Mistake 1: Assuming All Images Have `curl`
```yaml
# WRONG
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
```

**Fix:** Verify `curl` is installed or use service-native tool:
```yaml
# RIGHT
healthcheck:
  test: ["CMD", "sh", "-c", "VAULT_ADDR=http://127.0.0.1:8200 vault status"]
```

### ❌ Mistake 2: Using HTTP When Service Runs HTTPS-Only
```yaml
# WRONG (Vault in HTTPS-only mode)
healthcheck:
  test: ["CMD", "curl", "-f", "https://localhost:8200/v1/sys/health"]
  # But service in dev mode runs HTTP!
```

**Fix:** Match actual service configuration:
```yaml
# RIGHT (Vault dev mode = HTTP-only)
healthcheck:
  test: ["CMD", "sh", "-c", "VAULT_ADDR=http://127.0.0.1:8200 vault status"]
```

### ❌ Mistake 3: Too-Short `start_period` for Java Services
```yaml
# WRONG
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  start_period: 30s  # Not enough for Java
```

**Fix:** Give Java 90+ seconds:
```yaml
# RIGHT
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  start_period: 90s
```

### ❌ Mistake 4: Health Endpoint That Crashes
```python
# WRONG
@app.get("/health")
def health():
    result = expensive_database_query()  # Can throw
    return {"status": "ok"}
```

**Fix:** Lightweight, defensive health endpoint:
```python
# RIGHT
@app.get("/health")
def health():
    try:
        # Quick check only (no DB queries)
        return {"status": "ok"}, 200
    except Exception as e:
        # Never crash, always return something
        return {"error": str(e)}, 503
```

### ❌ Mistake 5: Protocol Mismatch (HTTP vs HTTPS)
```yaml
# WRONG (Healthcheck tries HTTPS but app is HTTP)
healthcheck:
  test: ["CMD", "curl", "-f", "https://localhost:8080/health"]
```

**Fix:** Match actual port and protocol:
```yaml
# RIGHT
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
```

---

## Implementation Checklist

When adding a new service, verify:

- [ ] **Image Inspection:** What tools does the image include? (curl, wget, native CLI, etc.)
- [ ] **Service Type:** Python? Java? Go? Node? Database?
- [ ] **Startup Speed:** How long does it actually take to initialize?
- [ ] **Health Endpoint:** Does service expose one? What's the path and port?
- [ ] **Protocol:** HTTP or HTTPS? Custom port?
- [ ] **Dependencies:** Does health check depend on external services?
- [ ] **Timing Tuning:** Start with reference values; adjust based on actual startup time
- [ ] **Failure Testing:** Simulate service failure; verify healthcheck detects it

---

## Testing Healthchecks

### Manual Test in Running Container
```bash
# SSH to host
ssh user@host

# Execute healthcheck test directly
docker exec code-server-vault sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault status"

# Check exit code (0 = healthy, 1 = unhealthy)
echo $?

# View full health state
docker inspect code-server-vault --format '{{json .State.Health}}'
```

### Monitor Healthcheck Over Time
```bash
watch -n 5 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep code-server-vault'
```

### Trigger Manual Restart to Test Startup Grace
```bash
docker restart code-server-vault

# Watch as it transitions: restarting → health: starting → healthy
watch -n 2 'docker ps --format "{{.Names}}\t{{.Status}}" | grep vault'
```

---

## Reference: Current Deployment Healthchecks

See [docker-compose.enterprise.yml](../docker-compose.enterprise.yml) for full live examples.

Key services:
- **vault:** Uses `vault status` CLI probe (HTTP via VAULT_ADDR)
- **testing:** Uses HTTP `/health` endpoint (FastAPI)
- **artifact-repo:** Uses HTTP `/service/rest/v1/status` (Nexus, 90s start_period)
- **appsmith:** Uses HTTP `/api/v1/applications` endpoint
- **gitlab:** Uses HTTP `/-/health` endpoint (120s start_period for GitLab complexity)

---

## Future Enhancements

1. **Prometheus Healthcheck Exporter** — Stream all healthcheck events to Loki for centralized monitoring
2. **Service Dependency Gates** — Healthchecks for `depends_on` services before starting dependents
3. **Custom Healthcheck Plugins** — Extensible framework for complex multi-step probes
4. **Performance Profiling** — Automatic profiling of startup times per service; flag outliers

---

**Document Version:** 1.0  
**Last Updated:** April 29, 2026  
**Reviewed By:** Platform Team  
**Next Review:** May 13, 2026
