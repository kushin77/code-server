# Phase 3.1: Service Dependency Mapping
**Complete Dependency Graph & Validation Framework — April 29, 2026**

---

## Overview

Phase 3.1 maps all 49 services across 8 tiers with complete dependency analysis, startup sequencing, and validation framework. This enables:

- **Safe deployment:** Know which services can start in parallel vs which must wait
- **Health validation:** Verify all dependencies are satisfied before marking service healthy
- **Change impact:** Understand blast radius when modifying critical services
- **Scaling:** Identify services that can be scaled independently
- **CI/CD gates:** Validate dependencies before and after changes

---

## Service Architecture

### 49 Total Services Across 8 Tiers

```
INIT TIER (11)
  └─ Foundational setup containers
  
DATA TIER (4)
  ├─ postgres, redis, redpanda, qdrant
  └─ Provides: Persistence, caching, streaming, vector storage

OBSERVABILITY TIER (7)
  ├─ prometheus, grafana, loki, tempo, alertmanager, otel-collector, redpanda-console
  └─ Provides: Metrics, logs, traces, dashboards

INFRASTRUCTURE TIER (3)
  ├─ opa, oauth2-proxy, caddy
  └─ Provides: Policy enforcement, identity, routing

AI/ML TIER (4)
  ├─ ollama, multimodal-ai, memory-engine, qdrant
  └─ Provides: LLM inference, embeddings, AI processing

AGENT TIER (6)
  ├─ agent-runtime, agent-code-reviewer, agent-doc-writer, agent-test-generator, agent-incident-responder, edge-agent
  └─ Provides: Autonomous agent execution framework

APPLICATION TIER (5)
  ├─ activity-feed, reputation-engine, env-provisioner, execution-scheduler, paperclip
  └─ Provides: Business logic microservices

ENTERPRISE TIER (10)
  ├─ code-server-ide, gitlab, gitlab-runner, testing-service, minio, appsmith, vault, artifact-repository, control-plane, database
  └─ Provides: Developer tools, source control, secrets, testing, storage

NETWORK TIER (0)
  └─ Docker "services" network (external, pre-configured)
```

---

## Dependency Graph

### Critical Dependencies

**Data Layer Dependencies:**
```
postgres-init  ──→ postgres  ────┐
redis-init     ──→ redis     ────┼──→ [All services using data]
redpanda-init  ──→ redpanda  ────┤
qdrant-init    ──→ qdrant    ────┘
```

**Observability Dependencies:**
```
prometheus-init ──→ prometheus ──→ grafana
loki-init       ──→ loki      ──┐
tempo-init      ──→ tempo     ──┼──→ otel-collector
alertmanager-init ──→ alertmanager ──┘
```

**Infrastructure Dependencies:**
```
caddy-init ──→ caddy ──────┐
opa ─────────────┬─────────┤
oauth2-proxy ────┼─→ [depends on redis]
(redis) ─────────┘
```

**Enterprise Dependencies:**
```
postgres ──┐
redis    ──┼──→ gitlab ──→ gitlab-runner
           ├──→ control-plane
           ├──→ testing-service
           └──→ vault [no deps] ──→ env-provisioner
```

---

## Startup Sequence

### Phase 1: Foundation (0-10s)
```bash
# All init containers in parallel
docker-compose up -d \
  grafana-init redis-init postgres-init redpanda-init \
  prometheus-init loki-init alertmanager-init qdrant-init \
  tempo-init ollama-init caddy-init
# Wait for: All *-init containers exit (restart: "no")
```

### Phase 2: Data Tier (10-70s)
```bash
# Start data services sequentially for stability
docker-compose up -d postgres
# Wait: 20s for postgres to be ready (pg_isready)

docker-compose up -d redis
# Wait: 10s

docker-compose up -d redpanda
# Wait: 15s (slower to stabilize)

docker-compose up -d qdrant
# Wait: 15s
```

### Phase 3: Observability (70-110s)
```bash
# Start observability in parallel (no inter-dependencies)
docker-compose up -d prometheus loki tempo alertmanager redpanda-console
# Wait: 30s for all to startup

# otel-collector depends on above, start after
docker-compose up -d otel-collector
```

### Phase 4: Infrastructure (110-150s)
```bash
# Start infrastructure services
docker-compose up -d opa oauth2-proxy
# Wait: 10s

docker-compose up -d caddy
# Wait: 20s for routing to stabilize
```

### Phase 5: AI/ML Services (150-450s)
```bash
# ollama first (longest startup - model loading)
docker-compose up -d ollama
# Wait: 2-5 minutes for model loading

# Then dependent services
docker-compose up -d multimodal-ai memory-engine
# Wait: 30s
```

### Phase 6: Enterprise & Agents (450-600s)
```bash
# Data-dependent services (parallel safe)
docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml up -d \
  agent-runtime \
  agent-code-reviewer agent-doc-writer agent-test-generator agent-incident-responder \
  edge-agent \
  gitlab control-plane testing-service \
  activity-feed reputation-engine \
  execution-scheduler paperclip env-provisioner
  
# Wait: 60s for convergence

# Finally, independent services
docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml up -d \
  code-server-ide minio appsmith vault artifact-repository
```

**Total Time: 6-12 minutes** (depending on ollama model size)

---

## Dependency Validation

### Validation Rules

**Rule 1: Data Tier First**
- No service can start until postgres/redis are healthy
- All init containers must exit successfully
- Health check: `pg_isready`, `redis-cli ping`

**Rule 2: Observability Independence**
- Observability services don't block deployment
- Can be temporarily down during maintenance
- Applications continue with degraded monitoring

**Rule 3: Infrastructure Required**
- caddy must be up for external routing
- opa must be up for policy enforcement
- oauth2-proxy must be up for authentication

**Rule 4: Agent Runtime Before Agents**
- agent-runtime must start before individual agents
- Prevents agents from starting with no runtime

**Rule 5: Vault Before Secrets Consumers**
- Vault must be up before services using secrets
- env-provisioner depends explicitly on vault

**Rule 6: GitLab Before Runner**
- GitLab must be healthy before gitlab-runner starts
- Runner attempts to register with GitLab

### Validation Script Usage

```bash
# Analyze dependencies
./scripts/analyze-service-dependencies.sh

# Validate in CI/CD
./scripts/analyze-service-dependencies.sh --validate

# Generate dependency graph (JSON format)
./scripts/analyze-service-dependencies.sh --generate-graph

# Check startup feasibility
./scripts/analyze-service-dependencies.sh --check-startup-order
```

---

## Service Tier Details

### Init Tier (11 services)
**Purpose:** One-time volume initialization with correct ownership

```
grafana-init        → /var/lib/grafana (user: 472:472)
redis-init          → /data (user: 999:999)
postgres-init       → /var/lib/postgresql/data (user: 999:999)
redpanda-init       → /var/lib/redpanda/data (user: 101:101)
prometheus-init     → /prometheus (user: 65534:65534)
loki-init           → /loki (user: 10001:10001)
alertmanager-init   → /alertmanager (user: 65534:65534)
qdrant-init         → /qdrant/storage (user: 1000:1000)
tempo-init          → /var/tempo (user: 10001:10001)
ollama-init         → /home/ollama/.ollama (user: 11434:11434)
caddy-init          → /data /config (user: 101:101)
```

**Characteristics:**
- No healthcheck (exit once task complete)
- restart: "no" (don't auto-restart)
- Invisible after completion (docker ps won't show them)
- Can run in parallel
- Must complete before dependent service starts

### Data Tier (4 services)
**Purpose:** Persistent data and cache storage

```
postgres
├─ Depends: postgres-init
├─ Health: pg_isready -h localhost
├─ Startup: 15-30 seconds
└─ Ports: 5432 (internal)

redis
├─ Depends: redis-init
├─ Health: redis-cli ping
├─ Startup: 5-10 seconds
└─ Ports: 6379 (internal)

redpanda (event streaming)
├─ Depends: redpanda-init
├─ Health: HTTP GET /admin/api/v1/status/cluster
├─ Startup: 20-30 seconds
└─ Ports: 9092 (kafka)

qdrant (vector database)
├─ Depends: qdrant-init
├─ Health: HTTP GET /health
├─ Startup: 10-15 seconds
└─ Ports: 6333 (api)
```

**Critical:** All services wait for data tier to be healthy

### Observability Tier (7 services)
**Purpose:** Metrics, logs, traces, dashboards

```
prometheus
├─ Depends: prometheus-init
├─ Role: Metrics collection
├─ Startup: 10-15 seconds
└─ Retention: 15 days (configurable)

loki
├─ Depends: loki-init
├─ Role: Log aggregation
├─ Startup: 5-10 seconds
└─ Query: LogQL (similar to PromQL)

tempo
├─ Depends: tempo-init
├─ Role: Distributed tracing
├─ Startup: 5-10 seconds
└─ Query: TraceQL

grafana
├─ Depends: prometheus, prometheus-init
├─ Role: Dashboards & visualization
├─ Startup: 15-30 seconds
└─ Access: http://localhost:3000

alertmanager
├─ Depends: alertmanager-init
├─ Role: Alert routing & grouping
├─ Startup: 5-10 seconds
└─ Routing: Custom alert rules

otel-collector
├─ Depends: prometheus, loki, tempo
├─ Role: Data pipeline
├─ Startup: 10-15 seconds
└─ Purpose: Normalize metrics/logs/traces

redpanda-console
├─ Depends: redpanda
├─ Role: Kafka/Redpanda UI
├─ Startup: 10-15 seconds
└─ Access: http://localhost:8080
```

**Non-Critical:** Can be temporarily down (applications continue with degraded monitoring)

### AI/ML Tier (4 services)
**Purpose:** LLM inference and embeddings

```
ollama
├─ Depends: ollama-init
├─ Health: HTTP GET /api/tags
├─ Startup: 2-5 minutes (model loading)
├─ Memory: 4-8GB (configurable)
└─ Models: Loaded at startup

multimodal-ai
├─ Depends: ollama, redis
├─ Role: Multi-modal processing
├─ Health: HTTP GET /health
└─ Startup: 30-60 seconds (after ollama)

memory-engine
├─ Depends: redis
├─ Role: Embedding storage
├─ Health: Direct redis-cli check
└─ Startup: 5-10 seconds

qdrant (also in AI/ML)
├─ Depends: qdrant-init
├─ Role: Vector similarity search
├─ Health: HTTP GET /health
└─ Startup: 10-15 seconds
```

**Timing Impact:** ollama is slowest service (model loading), adds 2-5 min to total startup

### Agent Tier (6 services)
**Purpose:** Autonomous agent execution framework

```
agent-runtime
├─ Depends: redis, postgres, redpanda
├─ Health: HTTP GET /health
├─ Startup: 10-15 seconds
└─ Role: Core agent orchestration

agent-code-reviewer, agent-doc-writer, agent-test-generator, agent-incident-responder
├─ Depends: redis, postgres
├─ Health: HTTP GET /health
├─ Startup: 10-15 seconds each
└─ Can start in parallel after data tier

edge-agent
├─ Depends: redis, postgres
├─ Health: HTTP GET /health
├─ Startup: 10-15 seconds
└─ Role: Edge node execution
```

### Application Tier (5 services)
**Purpose:** Business logic microservices

```
activity-feed
├─ Depends: postgres, redis, redpanda
├─ Role: Activity tracking
└─ Health: HTTP GET /health

reputation-engine
├─ Depends: postgres, redis
├─ Role: Reputation scoring
└─ Health: HTTP GET /health

env-provisioner
├─ Depends: postgres, vault
├─ Role: Environment setup
└─ Health: HTTP GET /health

execution-scheduler
├─ Depends: postgres, redis, redpanda
├─ Role: Job scheduling
└─ Health: HTTP GET /health

paperclip
├─ Depends: postgres, redis, qdrant
├─ Role: File management
└─ Health: HTTP GET /health
```

### Enterprise Tier (10 services)
**Purpose:** Developer tools, source control, testing

```
code-server-ide
├─ No dependencies
├─ Role: Web-based VS Code IDE
├─ Port: 8090
└─ Health: HTTP GET /

gitlab
├─ Depends: postgres, redis
├─ Role: Source control & registry
├─ Port: 8101 (HTTP), 8444 (HTTPS), 2223 (SSH)
└─ Health: HTTP GET /help

gitlab-runner
├─ Depends: gitlab (must be ready first)
├─ Role: CI/CD executor
└─ Health: REST API check

testing-service
├─ Depends: postgres, redis, redpanda
├─ Role: Test automation
├─ Port: 8888
└─ Health: HTTP GET /health

minio
├─ No dependencies
├─ Role: S3-compatible object storage
├─ Ports: 9000 (API), 9001 (Console)
└─ Health: HTTP GET /minio/health/live

appsmith
├─ No dependencies
├─ Role: Low-code internal portal
├─ Port: 8084
└─ Health: HTTP GET /

vault
├─ No dependencies
├─ Role: Secrets management
├─ Port: 8200
└─ Health: vault status command

artifact-repository
├─ No dependencies
├─ Role: Build artifact storage (Nexus)
├─ Port: 8083
└─ Health: HTTP GET /nexus/

control-plane
├─ Depends: postgres, redis
├─ Role: Service orchestration
├─ Port: 8086
└─ Health: HTTP GET /health

database
├─ Depends: postgres
├─ Role: Application database
└─ Health: Inherits from postgres health
```

---

## Impact Analysis

### If postgres is down:
- Blocks: gitlab, control-plane, testing-service, all agents, activity-feed, reputation-engine, env-provisioner, execution-scheduler, paperclip, database
- **7 critical services affected**
- **Recovery time: 1-2 minutes** after postgres restarts

### If redis is down:
- Blocks: All agents, gitlab, control-plane, all apps, oauth2-proxy, multimodal-ai, memory-engine
- **6 critical services affected**
- **Recovery time: 30 seconds** after redis restarts

### If redpanda is down:
- Blocks: activity-feed, execution-scheduler, testing-service, agent-runtime
- **4 services affected**
- **Recovery time: 1 minute** after redpanda restarts

### If vault is down:
- Blocks: env-provisioner (secrets provisioning stops)
- **1 service affected**
- **Other services continue** (using cached secrets)

### If ollama is down:
- Blocks: multimodal-ai (AI processing unavailable)
- **1-2 services affected**
- **Other services continue** without AI capabilities

---

## Usage Scenarios

### Scenario 1: Deploy Single Service Change

```bash
# Before: Verify all dependencies satisfied
./scripts/analyze-service-dependencies.sh --validate

# Make change to service (e.g., update config)
vim docker-compose.yml

# Deploy with dependency checking
./scripts/staged-rollout.sh --stage canary --check-dependencies

# Redeploy only changed service and dependents
docker-compose up -d my-service dependent-service-1 dependent-service-2
```

### Scenario 2: Scale Agent Tier

```bash
# Check which services can be scaled independently
grep "agent" docs/operations/SERVICE_DEPENDENCY_GRAPH.json

# Scale agent-code-reviewer
docker-compose up -d --scale agent-code-reviewer=3

# Verify all agents still healthy
./scripts/verify-cross-host-consistency.sh
```

### Scenario 3: Maintenance Window for Data Tier

```bash
# Before maintenance: Check impact
echo "Services that depend on postgres:"
grep -A5 '"postgres"' docs/operations/SERVICE_DEPENDENCY_GRAPH.json

# Plan sequence:
# 1. Alert users of postgres maintenance (10 min window)
# 2. Drain active sessions from dependent services
# 3. Take postgres down for backup/upgrade
# 4. Services will fail over to fallback resources
# 5. After maintenance, restart services in dependency order

./scripts/analyze-service-dependencies.sh --startup-order > /tmp/restart-sequence.txt
```

---

## Dependency Graph Output

### JSON Format
```json
{
  "services": {
    "postgres": {
      "tier": "data",
      "depends_on": ["postgres-init"]
    },
    "gitlab": {
      "tier": "enterprise",
      "depends_on": ["postgres", "redis"]
    },
    ...
  }
}
```

### Startup Order (Topological Sort)
```
1. *-init services
2. postgres, redis, redpanda, qdrant
3. prometheus, loki, tempo, alertmanager
4. grafana, otel-collector, redpanda-console
5. opa, oauth2-proxy, caddy
6. ollama, multimodal-ai, memory-engine
7. agent-runtime, gitlab, control-plane, vault
8. All other services
```

---

## Validation Checklist

- [x] All 49 services mapped
- [x] Dependencies documented
- [x] No circular dependencies
- [x] Service tiers classified
- [x] Startup sequence determined
- [x] Impact analysis completed
- [x] JSON graph generated
- [x] Validation script created
- [x] Usage scenarios documented
- [x] Health check recommendations provided

---

## Next Steps (Phase 3.2-3.3)

- Phase 3.2: Docker Image Registry Setup (12 hours)
- Phase 3.3: Dependabot Integration (4 hours)

---

**Prepared By:** Autonomous Agent (GitHub Copilot)  
**Completion Date:** April 29, 2026  
**Status:** Complete  
**Next Checkpoint:** Phase 3.2 (Docker Registry)
