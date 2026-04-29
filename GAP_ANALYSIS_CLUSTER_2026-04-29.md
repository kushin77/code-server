# Cluster Gap Analysis Report
**Date:** April 29, 2026  
**Scope:** Container inventory and health analysis for both cluster nodes  
**Primary Node:** 192.168.168.31  
**Replica Node:** 192.168.168.42

---

## Executive Summary

**Cluster Health:** ⚠️ **DEGRADED**
- Core infrastructure operational on both nodes (12 healthy services each)
- HA redundancy **BROKEN** - critical services missing on replica
- AI/ML services **BROKEN** - restarting on primary, absent on replica
- Observability **PARTIAL** - logging not redundant

**Service Count:** Primary 18 (12 healthy, 5 restarting) | Replica 13 (12 healthy, 1 restarting)

---

## Container Inventory

### Primary Node (192.168.168.31) - 18 Containers

**Healthy (12):**
- code-server-loki (Up 10 min) - Centralized logging
- code-server-memory-engine (Up 35 min, healthy)
- code-server-lb (Up 40 min) - Load balancer
- code-server-redis-sentinel-primary (Up 45 min)
- code-server-grafana (Up 2h, healthy)
- code-server-redpanda-console (Up 2h, healthy)
- code-server-qdrant (Up 2h, healthy)
- code-server-prometheus (Up 2h, healthy)
- code-server-ollama (Up 2h, healthy)
- code-server-redpanda (Up 2h, healthy)
- code-server-redis (Up 2h, healthy)
- code-server-opa (Up 2h, healthy)
- code-server-postgres (Up 13 min, healthy)

**Restarting (5):**
- code-server-execution-scheduler (exit 1)
- code-server-reputation-engine (exit 3 - persistent)
- code-server-activity-feed (exit 1)
- code-server-caddy (exit 1)
- code-server-oauth2-proxy (exit 1)

### Replica Node (192.168.168.42) - 13 Containers

**Healthy (12):**
- code-server-memory-engine (Up 24 min, healthy)
- code-server-postgres (Up 25 min)
- code-server-prometheus (Up 25 min)
- code-server-caddy (Up 25 min)
- code-server-redis-sentinel-replica (Up 45 min)
- code-server-redpanda-console (Up 2h, healthy)
- code-server-grafana (Up 2h, healthy)
- code-server-redis (Up 2h, healthy)
- code-server-ollama (Up 2h, healthy)
- code-server-qdrant (Up 2h, healthy)
- code-server-redpanda (Up 2h, healthy)
- code-server-opa (Up 2h, healthy)

**Restarting (1):**
- code-server-tempo (exit 1)

---

## Critical Gaps (HA Compromise)

### 1. Load Balancer Missing on Replica ❌ CRITICAL
- **Service:** code-server-lb
- **Status:** Present on PRIMARY only
- **Impact:** Replica cannot serve traffic independently; single point of failure for ingress
- **HA Risk:** HIGH - Failover will lose load balancing capability

### 2. Centralized Logging Missing on Replica ❌ CRITICAL
- **Service:** code-server-loki
- **Status:** Present on PRIMARY only
- **Impact:** Log aggregation not redundant; logs lost if primary fails
- **HA Risk:** MEDIUM - Observability compromised but not critical for operations

### 3. Auth Proxy Missing on Replica ❌ HIGH
- **Service:** code-server-oauth2-proxy
- **Status:** Present on PRIMARY only
- **Impact:** Authentication layer not redundant
- **HA Risk:** MEDIUM - Replica cannot authenticate requests independently

---

## Health Issues - Primary Node

### Service: code-server-activity-feed
**Status:** ❌ Restarting (exit code 1)  
**Root Cause:** `ModuleNotFoundError: No module named 'fastapi'`  
**Details:** Docker image built without Python FastAPI dependency
```
Traceback (most recent call last):
  File "/app/main.py", line 8, in <module>
    from fastapi import FastAPI, Query, WebSocket, HTTPException
ModuleNotFoundError: No module named 'fastapi'
```
**Fix:** Rebuild Docker image with `pip install fastapi` or add to requirements.txt

---

### Service: code-server-execution-scheduler
**Status:** ❌ Restarting (exit code 1)  
**Root Cause:** `could not translate host name "postgres" to address: Temporary failure in name resolution`  
**Details:** Service trying to connect to hostname "postgres" instead of "code-server-postgres"
```
sqlalchemy.exc.OperationalError: (psycopg2.OperationalError) 
could not translate host name "postgres" to address: 
Temporary failure in name resolution
```
**Fix:** Update database connection string to use `code-server-postgres` or resolve DNS for `postgres` service name

---

### Service: code-server-reputation-engine
**Status:** ❌ Restarting (exit code 3)  
**Root Cause:** Unknown - repeated failures, exit code 3 indicates dependency or configuration issue  
**Details:** Container consistently exits with code 3
**Fix:** Check application logs and Docker image configuration

---

### Service: code-server-caddy
**Status:** ❌ Restarting (exit code 1)  
**Root Cause:** Configuration file permission issue (known from previous session)  
**Details:** `/code-server-enterprise-ops/config/caddy/` owned by root, not accessible by container
**Fix:** 
- Option 1: `sudo chown -R akushnir:akushnir /code-server-enterprise-ops/config/caddy/`
- Option 2: Mount config via environment variables instead of file volume

---

### Service: code-server-oauth2-proxy
**Status:** ❌ Restarting (exit code 1)  
**Root Cause:** Configuration file permission issue (known from previous session)  
**Details:** `/code-server-enterprise-ops/config/oauth2-proxy/` owned by root
**Fix:** Same as caddy - either fix permissions or use environment variable config mount

---

## Health Issues - Replica Node

### Service: code-server-tempo
**Status:** ❌ Restarting (exit code 1)  
**Root Cause:** Backend configuration incomplete  
**Details:** Tempo tracing service backend not properly configured
**Fix:** Configure Tempo backend storage (filesystem, S3, or similar)

---

## Missing Services Analysis

### AI/ML Services Missing on Replica (Expected)
- `code-server-execution-scheduler`
- `code-server-reputation-engine`
- `code-server-activity-feed`

**Root Cause:** Docker images only built locally on primary; no shared registry  
**Impact:** AI/ML services cannot scale to replica  
**Expected Fix:** Set up Docker Registry (self-hosted or Docker Hub), push images, pull on replica

**Note:** These services are also restarting on PRIMARY due to missing dependencies, so replicating them to replica would reproduce the same failures. Must fix primary issues first.

---

## Summary by Category

| Category | Primary | Replica | Gap | Severity |
|----------|---------|---------|-----|----------|
| Core Data Services | ✅ All up | ✅ All up | None | - |
| Observability | ✅ Prometheus, Grafana, Loki | ✅ Prometheus, Grafana | ❌ No Loki | HIGH |
| Infrastructure | ⚠️ Caddy/OAuth2 restarting | ✅ Caddy up | ❌ No LB, No Auth | CRITICAL |
| AI/ML Services | ❌ All restarting | ❌ None deployed | ❌ Broken | MEDIUM |
| Tracing | ✅ None deployed | ⚠️ Tempo restarting | ⚠️ Config issue | LOW |

---

## Recommendations

### IMMEDIATE (Restore HA - 1-2 hours)
1. Deploy `code-server-lb` to replica node
2. Deploy `code-server-loki` to replica node
3. Deploy `code-server-oauth2-proxy` to replica node

### SHORT-TERM (Fix Service Health - 1-2 hours)
1. Fix execution-scheduler: Update database connection to use `code-server-postgres`
2. Fix activity-feed: Rebuild Docker image with FastAPI dependency
3. Fix reputation-engine: Debug container startup and fix root cause
4. Fix caddy/oauth2-proxy: Resolve config file permissions or use environment variables

### MEDIUM-TERM (Complete Deployment - 2-4 hours)
1. Set up Docker Registry (Harbor, Docker Registry, or Docker Hub)
2. Push AI/ML images to registry
3. Deploy AI/ML services to both nodes
4. Fix Tempo backend configuration (use filesystem or S3 backend)

### LONG-TERM (Operational Excellence)
1. Implement health checks and auto-remediation
2. Set up centralized config management
3. Create deployment automation to ensure cluster parity
4. Implement cross-node image distribution automation

---

## Conclusion

The cluster has operational core infrastructure but **HA redundancy is broken** due to critical services missing on the replica node. Primary node health is also compromised with 5 restarting services. These must be addressed to restore production readiness for disaster recovery scenarios.

**Current Status:** Development/Testing ready | **Production Ready:** ❌ NO
