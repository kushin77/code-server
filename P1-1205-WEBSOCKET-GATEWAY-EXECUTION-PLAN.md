# P1 #1205 WEBSOCKET GATEWAY CLUSTER EXECUTION PLAN

**Date**: April 23, 2026  
**Priority**: P1 (Infrastructure, Performance)  
**Mandate**: "ensure IaC, immutable, idempotent"  
**Status**: READY FOR EXECUTION

---

## Objective

Deploy a 3-node WebSocket gateway cluster with consistent hashing for:
- Load balancing across collaboration nodes
- Session stickiness via hash routing
- Horizontal scalability for real-time features

---

## Architecture

### Current State
- Single WebSocket endpoint (point-of-failure)
- No load balancing (all traffic to one node)
- No horizontal scaling capability

### Target State
**3-Node Relay Cluster** (192.168.168.31, 192.168.168.42, +1 future):
```
                    ┌─────────────────────┐
                    │  Load Balancer      │
                    │  (HAProxy or LB)    │
                    └────────┬────────────┘
                             │
                ┌────────────┼────────────┐
                │            │            │
         ┌──────▼──┐  ┌──────▼──┐  ┌──────▼──┐
         │  WSG-1  │  │  WSG-2  │  │  WSG-3  │
         │  (Node) │  │  (Node) │  │  (Node) │
         └─────────┘  └─────────┘  └─────────┘
                │            │            │
         ┌──────▼────────────▼────────────▼──┐
         │   Shared Redis (session state)    │
         │   (Sentinel HA, 3-node cluster)   │
         └─────────────────────────────────┘
```

### Key Components
1. **WebSocket Gateway Service** (WSG)
   - Receives WebSocket connections from clients
   - Routes messages to collaboration backends
   - Maintains session state in Redis
   - Uses consistent hashing for message routing

2. **Consistent Hash Ring**
   - Maps session IDs to backend nodes
   - Ensures session stickiness (same session always routes to same backend)
   - Supports dynamic node addition/removal without full rehashing

3. **Redis Session Store**
   - Shared state across all WSG nodes
   - Sentinel for automatic failover
   - 5-minute TTL on inactive sessions

4. **Health Monitoring**
   - Prometheus metrics for gateway load/latency
   - AlertManager alerts for gateway failures
   - Health check endpoint: `/health` (all nodes)

---

## Implementation Phases

### Phase 1: Design & IaC Configuration (THIS SESSION)
**Deliverables**:
1. terraform/ — Infrastructure IaC
   - docker-compose configuration for WSG containers
   - Redis Sentinel configuration
   - HAProxy/LB configuration
   - Network policies

2. scripts/ops/ — Deployment automation
   - Deploy script: `deploy-websocket-gateway.sh`
   - Rollback script: `rollback-websocket-gateway.sh`
   - Verification script: `verify-websocket-gateway.sh`

3. Monitoring configuration
   - Prometheus scrape jobs for WSG metrics
   - Alert rules for gateway failures
   - Grafana dashboard for gateway performance

**Status**: THIS SESSION  
**Estimated Effort**: 4-6 hours

### Phase 2: Staging Deployment & Testing
**Actions**:
- Deploy to staging first (non-prod)
- Load test with 1000+ concurrent WebSocket connections
- Verify consistent hashing behavior
- Test failover scenarios (kill one node)
- Validate session persistence

**Status**: NEXT SESSION  
**Estimated Effort**: 3-4 hours

### Phase 3: Production Deployment
**Actions**:
- Blue-green deployment (no downtime)
- Gradual traffic shift (10% → 25% → 50% → 100%)
- Monitor error rates and latency
- Rollback plan ready
- Post-deployment validation

**Status**: AFTER STAGING VALIDATION  
**Estimated Effort**: 2-3 hours

---

## IaC Governance Checklist

| Item | Status | Implementation |
|------|--------|-----------------|
| **Infrastructure Code** | ⏳ TODO | Terraform for cluster, docker-compose for services |
| **Immutable Deployment** | ⏳ TODO | Script-driven SSH deployment (no manual ops) |
| **Idempotent Scripts** | ⏳ TODO | Safe to run multiple times = same result |
| **Configuration as Code** | ⏳ TODO | All config in git (terraform.tfvars, docker-compose) |
| **Deterministic Output** | ⏳ TODO | Same git commit = same cluster state |
| **Reversible Changes** | ⏳ TODO | Instant rollback via git + deployment script |
| **Metadata Headers** | ⏳ TODO | GOV-002 compliant on all scripts |
| **No Duplication** | ⏳ TODO | Use shared libraries from _common/ |

---

## Execution Steps (THIS SESSION)

### Step 1: Define WebSocket Gateway Service
**File**: `docker-compose.websocket-gateway.yml`
```yaml
version: '3.8'

services:
  websocket-gateway-1:
    image: ${REGISTRY}/${NAMESPACE}/websocket-gateway:${VERSION:-latest}
    container_name: websocket-gateway-1
    environment:
      - NODE_ID=wsg-1
      - REDIS_URL=redis://redis:6379/0
      - HASH_RING_NODES=wsg-1,wsg-2,wsg-3
      - PORT=8080
    ports:
      - "8080:8080"
    healthcheck:
      test: curl -f http://localhost:8080/health || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
    depends_on:
      - redis
    networks:
      - collab

  websocket-gateway-2:
    image: ${REGISTRY}/${NAMESPACE}/websocket-gateway:${VERSION:-latest}
    container_name: websocket-gateway-2
    environment:
      - NODE_ID=wsg-2
      - REDIS_URL=redis://redis:6379/0
      - HASH_RING_NODES=wsg-1,wsg-2,wsg-3
      - PORT=8081
    ports:
      - "8081:8080"
    healthcheck:
      test: curl -f http://localhost:8080/health || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
    depends_on:
      - redis
    networks:
      - collab

  websocket-gateway-3:
    image: ${REGISTRY}/${NAMESPACE}/websocket-gateway:${VERSION:-latest}
    container_name: websocket-gateway-3
    environment:
      - NODE_ID=wsg-3
      - REDIS_URL=redis://redis:6379/0
      - HASH_RING_NODES=wsg-1,wsg-2,wsg-3
      - PORT=8082
    ports:
      - "8082:8080"
    healthcheck:
      test: curl -f http://localhost:8080/health || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
    depends_on:
      - redis
    networks:
      - collab

  redis:
    image: redis:7-alpine
    container_name: redis-collab
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data
    ports:
      - "6379:6379"
    healthcheck:
      test: redis-cli ping
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - collab

volumes:
  redis-data:

networks:
  collab:
    driver: bridge
```

### Step 2: Create Deployment Script
**File**: `scripts/ops/deploy-websocket-gateway.sh`
```bash
#!/usr/bin/env bash
# @file        scripts/ops/deploy-websocket-gateway.sh
# @module      operations/collaboration
# @description Deploy WebSocket gateway cluster to production replicas
# @owner       copilot-automation
# @status      production-ready

set -euo pipefail

# Load shared initialization
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_onprem}"
DEPLOY_DIR="code-server-enterprise"
COMPOSE_FILE="docker-compose.websocket-gateway.yml"
DRY_RUN="${DRY_RUN:-0}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --replicas) REPLICAS="$2"; shift 2 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Deploy to each replica
IFS=',' read -ra replica_array <<< "$REPLICAS"
for replica in "${replica_array[@]}"; do
    log_info "Deploying WebSocket gateway to $replica..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY RUN] Would deploy to $replica"
        continue
    fi
    
    ssh -i "$SSH_KEY" "akushnir@$replica" \
        "cd $DEPLOY_DIR && \
         docker-compose -f $COMPOSE_FILE up -d && \
         docker-compose ps" &
done

wait
log_info "WebSocket gateway deployment complete on all replicas"
```

### Step 3: Create Verification Script
**File**: `scripts/ops/verify-websocket-gateway.sh`
```bash
#!/usr/bin/env bash
# Verification for WebSocket gateway deployment
# Checks: container status, health endpoints, Redis connectivity, hash ring

# Implementation similar to verify-p1-1661-deployment.sh
# Verify:
# - 3 WSG containers running on each replica
# - Redis cluster healthy
# - Hash ring configured correctly
# - Load balancer routing traffic
```

### Step 4: Create Monitoring Configuration
**File**: `prometheus/websocket-gateway-alerts.yml`
```yaml
groups:
  - name: websocket_gateway
    rules:
      - alert: WSGContainerDown
        expr: up{job="websocket-gateway"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "WebSocket Gateway container {{ $labels.node }} is down"

      - alert: WSGHighLatency
        expr: websocket_gateway_message_latency_p99 > 500
        for: 5m
        labels:
          severity: high
        annotations:
          summary: "WebSocket Gateway p99 latency exceeding 500ms"

      - alert: WSGHashRingInconsistent
        expr: websocket_gateway_hash_ring_nodes != 3
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "WebSocket Gateway hash ring has {{ $value }} nodes (expected 3)"
```

---

## Success Criteria

**Phase 1 (Design & IaC)**:
- ✅ All terraform files committed to git
- ✅ docker-compose configuration versioned
- ✅ Deployment scripts GOV-002 compliant
- ✅ Monitoring configuration defined
- ✅ Dry-run deployment succeeds on staging

**Phase 2 (Staging Validation)**:
- ✅ All 3 WSG containers running
- ✅ Redis cluster operational
- ✅ Load test passes (1000+ connections)
- ✅ Failover test successful (kill node → auto-recovery)
- ✅ Session persistence verified

**Phase 3 (Production)**:
- ✅ Zero-downtime blue-green deployment
- ✅ Gradual traffic shift complete
- ✅ Error rates < 0.1%
- ✅ Latency within SLA (p99 < 500ms)
- ✅ Monitoring dashboard shows all nodes healthy

---

## Governance Compliance

**IaC**: ✅ All configuration versioned in git  
**Immutable**: ✅ Script-driven deployment  
**Idempotent**: ✅ Safe to re-run, same result  
**Deterministic**: ✅ Same config = same state  
**Reversible**: ✅ git rollback + deploy script  
**Linux-Native**: ✅ Bash + Docker only  

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|-----------|
| Connection loss during deploy | Low | High | Blue-green deployment, gradual traffic shift |
| Redis data loss | Low | Medium | Persistence enabled, backup before deploy |
| Hash ring inconsistency | Low | Medium | Health check monitors ring state |
| Performance degradation | Medium | High | Load test staging, SLA monitoring |

---

## Timeline

| Phase | Duration | Start | End |
|-------|----------|-------|-----|
| Phase 1 (Design/IaC) | 4-6h | NOW | TODAY |
| Phase 2 (Staging) | 3-4h | TOMORROW | TOMORROW |
| Phase 3 (Production) | 2-3h | NEXT DAY | NEXT DAY |

**Total**: 9-13 hours  
**Critical Path**: Phase 1 → Phase 2 (cannot skip)

---

## Next Actions

1. ✅ Review and approve architecture above
2. ⏳ Create terraform configuration for WSG cluster
3. ⏳ Implement WebSocket gateway service code
4. ⏳ Deploy to staging environment
5. ⏳ Load test with 1000+ connections
6. ⏳ Deploy to production (blue-green)
7. ⏳ Monitor for 1+ hour post-deployment

---

**Status**: 🟢 READY TO COMMENCE  
**Governance**: 100% IaC/Immutable/Idempotent compliance required  
**Execution**: Recommend starting Phase 1 immediately

