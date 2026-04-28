# Docker Compose Architecture Guide

## Overview

The Code Server Enterprise deployment uses a **layered composition strategy** with 9 Docker Compose files orchestrated via Docker Compose profiles and overlays.

This guide explains the architecture, purpose of each file, and how to use them effectively.

---

## File Structure

```
docker-compose.yml                 # PRIMARY (Base - all 41 services, 1576 lines)
├── docker-compose.prod.yml        # PRODUCTION OVERLAY (prod-specific configs)
├── docker-compose.enterprise.yml  # ENTERPRISE OVERLAY (enterprise features)
├── docker-compose.override.yml    # LOCAL DEVELOPMENT (dev overrides, minimal)
├── docker-compose.ai.yml          # AI WORKLOADS (Ollama, vision models - profile: ai)
├── docker-compose.cluster.yml     # CLUSTER MODE (multi-node, HA - complex)
├── docker-compose.observability.yml # OBSERVABILITY (Grafana, Prometheus - profile: observability)
├── docker-compose.edge-agent.yml  # EDGE DEPLOYMENT (edge-agent service)
└── docker-compose.redpanda.yml    # EVENT STREAMING (Redpanda Kafka broker)
```

---

## Composition Strategy

### Architecture: Profiles + Overlays

**Docker Profiles** (runtime activation):
```bash
docker-compose --profile ai --profile observability up -d
```

Services marked with `profiles: ["ai"]` only activate when explicitly requested.

**Overlays** (file composition):
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Compose applies files in order, with later files overriding earlier ones.

---

## File Purposes

### 1. docker-compose.yml (1576 lines) - PRIMARY
**Purpose:** Base production deployment with all 41 core services

**Contains:**
- 6 init containers (Alpine-based setup)
- Infrastructure (OPA, Caddy, OAuth2-proxy)
- Observability (Prometheus, Grafana, Loki, Alertmanager)
- Data stores (PostgreSQL, Redis, Redpanda, Qdrant)
- AI/ML engines (Memory-engine, Multimodal-AI, Reputation-engine)
- Agent services (Code-reviewer, Doc-writer, Test-generator, Incident-responder)
- Execution platform (Scheduler, Activity-feed, Paperclip)
- Edge components (Edge-agent, Env-provisioner)

**Governance:**
- GOV-002: All services have health checks and logging
- All images pinned to sha256 digests
- All services run as non-root users
- All services have resource limits defined

**Usage:**
```bash
docker-compose up -d                    # Deploy with defaults
docker-compose --profile ai up -d       # Deploy including AI services
```

---

### 2. docker-compose.prod.yml (579 lines) - PRODUCTION OVERLAY
**Purpose:** Production-specific configuration overrides

**Overrides:**
- Resource limits adjusted for production loads
- Logging configuration (max file sizes, retention)
- Environment variables for production URLs/domains
- Database credentials (from .env.deployment)
- Health check timeouts (more lenient for production)
- Restart policies (unless-stopped)

**Usage:**
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

---

### 3. docker-compose.override.yml (20 lines) - LOCAL DEVELOPMENT
**Purpose:** Minimal local development overrides

**Changes:**
- Reduced resource limits for dev machines
- Local URL mappings (localhost)
- Simplified logging
- Faster startup configurations

**Note:** Docker Compose automatically loads this file if present

**Usage:**
```bash
docker-compose up -d     # Automatically includes override.yml
```

---

### 4. docker-compose.enterprise.yml (307 lines) - ENTERPRISE OVERLAY
**Purpose:** Enterprise-specific features and configurations

**Contains:**
- Enterprise security policies
- Advanced monitoring configurations
- Multi-tenant support settings
- License enforcement containers

**Usage:**
```bash
docker-compose -f docker-compose.yml -f docker-compose.enterprise.yml up -d
```

---

### 5. docker-compose.ai.yml (112 lines) - AI PROFILE
**Purpose:** AI and ML workload services (Ollama, vision models)

**Services:**
- Ollama (LLM inference)
- Memory-engine (embedding service)
- Multimodal-AI (vision + language)
- Reputation-engine (scoring)

**Activation:** Profile-based (requires explicit flag)

**Usage:**
```bash
docker-compose --profile ai up -d
```

---

### 6. docker-compose.observability.yml (90 lines) - OBSERVABILITY PROFILE
**Purpose:** Monitoring and observability stack

**Services:**
- Prometheus (metrics collection)
- Grafana (dashboarding)
- Loki (log aggregation)
- Alertmanager (alerting)
- Tempo (distributed tracing)
- OpenTelemetry Collector (metrics/traces/logs ingestion)

**Activation:** Profile-based

**Usage:**
```bash
docker-compose --profile observability up -d
```

---

### 7. docker-compose.cluster.yml (1256 lines) - CLUSTER MODE
**Purpose:** Multi-node clustering and high-availability configuration

**Features:**
- Node discovery and coordination
- Distributed consensus (Raft)
- Cross-node replication
- Load balancing configuration
- Failover orchestration

**Complexity:** Advanced (requires cluster setup)

**Usage:**
```bash
docker-compose -f docker-compose.yml -f docker-compose.cluster.yml up -d
```

---

### 8. docker-compose.edge-agent.yml (218 lines) - EDGE DEPLOYMENT
**Purpose:** Edge computing node deployment (single agent-runtime)

**Deployment Model:**
- Lightweight edge agent
- Redis for local caching
- Kafka for event streaming (to cluster)
- Minimal footprint

**Usage:**
```bash
docker-compose -f docker-compose.yml -f docker-compose.edge-agent.yml up -d
```

---

### 9. docker-compose.redpanda.yml (46 lines) - EVENT STREAMING
**Purpose:** Redpanda Kafka broker configuration

**Services:**
- Redpanda (Kafka replacement)
- Redpanda Console (UI/management)

**Usage:**
```bash
docker-compose -f docker-compose.yml -f docker-compose.redpanda.yml up -d
```

---

## Deployment Scenarios

### Scenario 1: Local Development
```bash
cd /home/akushnir/code-server
docker-compose up -d
# Uses: docker-compose.yml + docker-compose.override.yml (auto-loaded)
# Services: All 41 services with dev-optimized settings
```

### Scenario 2: Production Deployment
```bash
export API_HOST=192.168.168.31
docker-compose -f docker-compose.yml -f docker-compose.prod.yml \
  --profile ai --profile observability up -d
# Services: All 41 + AI + Observability stacks
```

### Scenario 3: Cluster with HA
```bash
docker-compose -f docker-compose.yml -f docker-compose.cluster.yml \
  --profile observability up -d
# Services: All services + cluster mode + observability
```

### Scenario 4: Edge Deployment
```bash
docker-compose -f docker-compose.yml -f docker-compose.edge-agent.yml up -d
# Services: Lightweight edge agent only
```

### Scenario 5: AI/ML Only
```bash
docker-compose --profile ai up -d
# Services: AI engines only (Memory-engine, Multimodal-AI, Ollama)
```

---

## Service Count by Configuration

| Configuration | Services | Profiles |
|---|---|---|
| Base (docker-compose.yml) | 41 | none |
| + prod overlay | 41 | none |
| + ai profile | 41 + AI engines | ai |
| + observability | 41 + monitoring stack | observability |
| + cluster mode | All + cluster coordination | none |
| Edge deployment | Edge-agent only | none |

---

## Key Design Principles

### 1. **Single Responsibility**
Each file focuses on a specific deployment context or feature set:
- Base: all services
- Prod: production tuning
- AI: AI/ML workloads
- Cluster: HA/scaling

### 2. **Immutability**
Files are generated by Terraform and should not be edited manually. Changes should be made in:
- `terraform/environments/*/deployment.tf` (for deployment)
- `terraform/variables.tf` (for variable definitions)

### 3. **Composability**
Multiple files can be combined:
```bash
docker-compose -f docker-compose.yml \
  -f docker-compose.prod.yml \
  -f docker-compose.enterprise.yml \
  --profile ai --profile observability up -d
```

### 4. **Health Verification**
All services include health checks for automated monitoring:
```bash
docker-compose ps  # Shows health status
```

---

## Profile Reference

Docker Compose profiles allow conditional service activation:

| Profile | File | Services | When to Use |
|---|---|---|---|
| `ai` | docker-compose.ai.yml | Ollama, vision models, embedding | ML workloads needed |
| `observability` | docker-compose.observability.yml | Prometheus, Grafana, Loki, Tempo | Monitoring stack |
| `infrastructure` | docker-compose.yml | Env-provisioner, Edge-agent | Infrastructure automation |
| `agents` | docker-compose.yml | Agent services | Agent workloads |
| `governance` | docker-compose.yml | Reputation-engine, Paperclip | Governance features |
| `all` | docker-compose.yml | All services with profiles | Complete deployment |

---

## Troubleshooting

### Services not starting?
```bash
# Check health status
docker-compose ps

# View logs for specific service
docker-compose logs <service-name>

# Verify compose file syntax
docker-compose config
```

### Profile not activating?
```bash
# Verify profile is supported
docker-compose config --profiles ai

# Explicitly activate in up command
docker-compose --profile ai up -d
```

### Resource constraints?
Check `docker-compose.yml` for service `deploy.resources`:
- All services have CPU/memory limits
- Adjust in `docker-compose.prod.yml` for production

---

## Maintenance

### Adding a New Service
1. Add to appropriate compose file (primary, profile, or overlay)
2. Update this guide with file references
3. Verify profiles and dependencies
4. Run health check validation

### Modifying Existing Service
1. Never edit compose files directly (Terraform-generated)
2. Make changes in Terraform configurations
3. Run Terraform apply to regenerate
4. Validate with `docker-compose config`

### Deprecating Old Files
1. Archive to `docs/archive/retired/`
2. Update this guide with deprecation notice
3. Ensure no deployment scripts reference old file
4. Document migration path for users

---

## References

- **Governance:** GOV-002 - Standardized service definitions and configurations
- **Health Checks:** See docker-compose.yml for all health check configurations
- **Terraform Source:** `terraform/environments/*/deployment.tf`
- **Service Inventory:** `COMPLETE_35_SERVICE_REFERENCE.md`
- **Architecture:** `DEPLOYMENT_ARCHITECTURE.md`
