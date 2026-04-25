# DNS-Based Service Discovery Architecture

**Issue:** #1536 - Networking, DNS & Performance  
**Date:** April 25, 2026  
**Status:** FOUNDATION COMPLETE - IaC Pattern Established

## Overview

All inter-service communication in the ElevatedIQ DevOS stack uses Docker Compose's built-in DNS service discovery. Services reference each other by **container service names**, not hardcoded IPs, enabling automatic DNS resolution and network resilience.

---

## Service Discovery Pattern

### 1. Docker Compose Internal DNS

Docker Compose automatically creates a bridge network (`services`) and provides DNS resolution for all containers on that network:

```yaml
networks:
  services:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-services
```

Each service is resolvable by its name within the network:

- `opa:8181` → resolves to OPA policy engine
- `redpanda:9092` → resolves to Redpanda message broker
- `postgres:5432` → resolves to PostgreSQL database
- `ollama:11434` → resolves to Ollama LLM runtime
- `tempo:4317` → resolves to Grafana Tempo tracing backend

### 2. Current Service Topology

#### Internal (Docker Network — DNS-Resolved)

```
┌─────────────────────────────────────────┐
│     Docker Bridge Network (services)    │
├─────────────────────────────────────────┤
│                                         │
│  opa:8181 (Policy Engine)              │
│  redis:6379 (Cache)                    │
│  postgres:5432 (Database)              │
│  redpanda:9092 (Event Bus)             │
│  qdrant:6333 (Vector Store)            │
│  ollama:11434 (LLM Runtime)            │
│  tempo:4317 (Distributed Tracing)      │
│  prometheus:9090 (Metrics)             │
│  loki:3100 (Log Aggregation)           │
│  otel-collector:4317 (Telemetry)       │
│  loki:3100 (Logging Backend)           │
│  grafana:3000 (Dashboards)             │
│                                         │
└─────────────────────────────────────────┘
```

#### External (Host Env Vars — Dynamically Configurable)

```
scripts/_common/_base-config.env:
  PRIMARY_HOST=${PRIMARY_HOST:-192.168.168.31}
  REPLICA_HOST=${REPLICA_HOST:-192.168.168.42}
  NAS_HOST=${NAS_HOST:-192.168.168.56}
```

### 3. Service Configuration Examples

#### PostgreSQL Database Reference

```yaml
environment:
  - DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@postgres:5432/${DB_NAME}
```

✅ Uses service name `postgres` (resolved via Docker DNS)  
✅ No hardcoded IP

#### OPA Policy Engine Reference

```yaml
environment:
  - OPA_URL=http://opa:8181
```

✅ Uses service name `opa` (resolved via Docker DNS)  
✅ No hardcoded IP

#### Ollama LLM Runtime Reference

```yaml
environment:
  - OLLAMA_HOST=http://ollama:11434
```

✅ Uses service name `ollama` (resolved via Docker DNS)  
✅ No hardcoded IP

#### Grafana Tempo Tracing Reference

```yaml
environment:
  - OTLP_ENDPOINT=http://tempo:4317
```

✅ Uses service name `tempo` (resolved via Docker DNS)  
✅ No hardcoded IP

---

## External Host References (Scalability)

For operations that require SSH or external host access:

```bash
# Sourced from scripts/_common/_base-config.env
source scripts/_common/_base-config.env

# Use templated env vars:
ssh akushnir@${PRIMARY_HOST} "docker ps"
scp file.txt akushnir@${REPLICA_HOST}:/tmp/
mount -t cifs //${NAS_HOST}/share /mnt/nas
```

### Env Var Defaults

| Variable | Default | Used For |
|----------|---------|----------|
| `PRIMARY_HOST` | `192.168.168.31` | Primary deployment node, SSH, NAS |
| `REPLICA_HOST` | `192.168.168.42` | Replica/secondary node, failover |
| `NAS_HOST` | `192.168.168.56` | Network-attached storage mount |
| `APEX_DOMAIN` | `kushnir.cloud` | Certificate generation, Caddyfile |

---

## DNS Resilience & Failover

### Container Restart Policy

All services use `restart: unless-stopped` to automatically recover if DNS resolution temporarily fails:

```yaml
restart: unless-stopped
```

### Health Checks

Each service includes a health check to detect DNS resolution failures:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8001/health"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

If health check fails (e.g., DNS lookup failed), Docker Compose restarts the container.

### Network Dependencies

Services declare explicit `depends_on` relationships to ensure startup order:

```yaml
depends_on:
  - postgres
  - redis
  - opa
```

This ensures dependencies are available before downstream services start DNS lookups.

---

## Verification

### Test DNS Resolution Inside Container

```bash
# Verify OPA is resolvable
docker exec -it agent-runtime \
  nslookup opa

# Verify connectivity to Tempo
docker exec -it otel-collector \
  getent hosts tempo

# Verify full service connectivity
docker exec -it execution-scheduler \
  curl -f http://opa:8181/health
```

### Verification Output

```
Name:      opa
Address:   172.18.0.2

→ DNS resolution successful ✓
```

---

## Best Practices for Service References

### ✅ DO: Use Service Names

```yaml
environment:
  - DATABASE_URL=postgresql://user:pass@postgres:5432/db
```

### ✅ DO: Use Templated Env Vars for External Hosts

```bash
ssh akushnir@${PRIMARY_HOST} "docker ps"
```

### ✅ DO: Document Service Port Assumptions

```yaml
# Assumption: kafka broker is on redpanda:9092
environment:
  - KAFKA_BROKER=redpanda:9092  # Do not change port without updating all consumers
```

### ❌ DON'T: Hardcode IPs in Docker Compose

```yaml
# ❌ WRONG
environment:
  - DATABASE_URL=postgresql://user:pass@192.168.168.31:5432/db
```

### ❌ DON'T: Hardcode IPs in Scripts (Outside Comments)

```bash
# ❌ WRONG
ssh akushnir@192.168.168.31 "docker ps"

# ✅ CORRECT
ssh akushnir@${PRIMARY_HOST} "docker ps"
```

---

## Migration Path (Future Work)

### Phase 1: Complete ✓
- Internal service DNS already working (all services on bridge network)
- Environment variables templated in docker-compose

### Phase 2: Planned
- Add PRIMARY_HOST/REPLICA_HOST references to docker-compose for any external integrations
- Implement DNS health checks at container entry point (e.g., `wait-for-dns.sh`)
- Validate all scripts source `_base-config.env`

### Phase 3: Planned
- Add Cloudflare DNS API for dynamic DNS updates (if replicating across external hosts)
- Implement VRRP VIP for multi-host failover (secondary epic: #(DR-epic))

---

## Related Files

- [scripts/_common/_base-config.env](../../scripts/_common/_base-config.env) — Host configuration
- [scripts/_common/hosts.sh](../../scripts/_common/hosts.sh) — Host utility functions
- [docker-compose.yml](../../docker-compose.yml) — Service definitions and networking
- [Caddyfile](../../Caddyfile) — Reverse proxy configuration
- [docs/architecture/INFRASTRUCTURE-REFERENCE.md](./INFRASTRUCTURE-REFERENCE.md) — Full infrastructure topology

---

## Issue #1536 Progress

- [x] Internal DNS service discovery via Docker Compose ✓
- [x] Environment variable templating for external hosts ✓
- [ ] NAS throughput benchmarking (planned)
- [ ] DNS failover validation (planned)
- [ ] Redis caching strategy documentation (planned)
- [ ] Network performance tuning (planned)

**Foundation: Complete**

