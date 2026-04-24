# Infrastructure Audit Report — April 21, 2026

## EXECUTIVE SUMMARY

🔴 **CRITICAL**: SSL_PROTOCOL_ERROR on kushnir.cloud caused by **Caddy not running on replica (192.168.168.42)**

The system is operating in **degraded cluster mode** with multiple component failures blocking production accessibility.

---

## DIAGNOSIS: SSL_PROTOCOL_ERROR Root Cause

🔴 **CRITICAL ARCHITECTURE MISMATCH DETECTED**

When you access `kushnir.cloud`, you get `ERR_SSL_PROTOCOL_ERROR` because:

1. **PRIMARY (192.168.168.31)**: Docker Compose + Caddy (configured for kushnir.cloud)
2. **REPLICA (192.168.168.42)**: Kubernetes/Helm + NGINX Ingress (configured for elevatediq.ai)
3. **DNS points to**: 192.168.168.42 (replica) with no kushnir.cloud configuration
4. **Result**: NGINX returns 404, browser gets invalid TLS response

**Two Incompatible Deployment Systems:**
- Primary: 7 microservices in Docker Compose
- Replica: Kubernetes with NGINX Ingress Controller + different applications (elevatediq.ai)
- **Connection**: NONE — Not a cluster, not synchronized, separate infrastructure

---

## INFRASTRUCTURE STATUS

### PRIMARY (192.168.168.31) — Partial Degradation ⚠️

| Service | Status | Issue |
|---------|--------|-------|
| caddy | ✅ UP (healthy) | TLS/HTTPS operational |
| code-server | ✅ UP (healthy) | IDE responsive |
| postgresql | ✅ UP (healthy) | Database healthy |
| redis | ✅ UP (healthy) | Cache operational |
| grafana | ✅ UP (healthy) | Monitoring dashboard up |
| ollama | ✅ UP (healthy) | LLM engine ready |
| jaeger | ✅ UP (healthy) | Tracing enabled |
| session-broker | ❌ RESTARTING | Crashing repeatedly |
| pgbouncer | ❌ RESTARTING | Crashing repeatedly |
| redis-sentinel-1 | ❌ RESTARTING | Crashing repeatedly |
| redis-sentinel-arbiter | ❌ RESTARTING | Crashing repeatedly |
| alertmanager | ❌ RESTARTING | Crashing repeatedly |
| prometheus | ❌ RESTARTING | Crashing repeatedly |

**Blocking Issues**:
- session-broker: `CODE_SERVER_IMAGE_ID must be a sha256 digest-pinned image reference`
- prometheus: `/etc/prometheus/prometheus-rules-phase-23.yml: is a directory` (expects file, gets directory)
- Sentinel/pgbouncer: DNS failures for session-broker prevent cluster initialization

### REPLICA (192.168.168.42) — Critical Failure 🔴

| Service | Status | Issue |
|---------|--------|-------|
| caddy | ❌ **Created (not running)** | **NO HTTPS LISTENER** ← ROOT CAUSE |
| oauth2-proxy | ⚠️ UP (unhealthy) | Bound to 127.0.0.1:4180 (localhost only) |
| code-server | ✅ UP (healthy) | IDE responsive |
| postgresql | ✅ UP (healthy) | Database healthy |
| redis | ✅ UP (healthy) | Cache operational |
| redis-sentinel-1 | ❌ RESTARTING | Depends on primary cluster |
| redis-sentinel-arbiter | ❌ RESTARTING | Depends on primary cluster |
| pgbouncer | ❌ RESTARTING | Depends on primary cluster |

**Critical Issue**:
- Caddy is NOT RUNNING → No port 443 listener → SSL_PROTOCOL_ERROR

---

## ROOT CAUSES (Ranked by Impact)

### 🔴 CRITICAL: Caddy Not Running on Replica

**Impact**: SSL_PROTOCOL_ERROR when accessing kushnir.cloud (if replica is DNS target)  
**Status**: Container exists but in "Created" state  
**Fix**: `docker compose up -d caddy`

### 🔴 CRITICAL: prometheus-rules Configuration Error

**Impact**: prometheus crashes every 30 seconds, metrics unavailable  
**Error**: `/etc/prometheus/prometheus-rules-phase-23.yml: is a directory`  
**Root Cause**: prometheus.yml references a directory path instead of a YAML file  
**Fix**: Update prometheus.yml to point to correct file path

### 🟠 HIGH: session-broker Missing Image Digest

**Impact**: Session management unavailable, blocks cluster initialization  
**Error**: `CODE_SERVER_IMAGE_ID must be a sha256 digest-pinned image reference`  
**Root Cause**: Environment variable contains tag (`:latest` or `:dev`) instead of sha256 digest  
**Fix**: Set `CODE_SERVER_IMAGE_ID` to pinned digest (e.g., `code-server@sha256:abc123...`)

### 🟠 HIGH: oauth2-proxy Bound to Localhost Only

**Impact**: OAuth2 authentication unavailable from external clients  
**Config**: `127.0.0.1:4180` (should be `0.0.0.0:4180` or remove host binding)  
**Fix**: Update docker-compose on replica: remove host binding or set to `0.0.0.0`

### 🟠 HIGH: Redis Sentinel Cluster Initialization Failed

**Impact**: High-availability failover not operational  
**Status**: Sentinel containers restarting due to primary cluster dependency  
**Fix**: Resolve session-broker + prometheus first, then restart sentinel

---

## DNS ARCHITECTURE ANALYSIS

### Current Routing

```
kushnir.cloud
    ├─→ DNS A record: 192.168.168.42 (replica)
    ├─→ Primary backup: 192.168.168.31 (primary)
```

**Problem**: Replica has NO Caddy → no HTTPS  
**Solution**: Either:
1. Start Caddy on replica (quick fix)
2. Point DNS to primary (192.168.168.31)
3. Configure load balancer (HAProxy/dns failover)

---

## CLUSTER/FAILOVER STATUS

### High Availability Setup

**Intended**: 
- Primary (192.168.168.31) = Active + Leader
- Replica (192.168.168.42) = Standby + Follower
- Redis Sentinel manages failover
- Caddy load balances between both

**Actual**:
- Replica Caddy: NOT RUNNING
- Sentinel: RESTARTING (dependency loop)
- Failover chain: **BROKEN**

---

## IMMEDIATE FIXES (In Order)

### Step 1: Start Caddy on Replica (2 minutes)
```bash
ssh akushnir@192.168.168.42
cd /home/akushnir/code-server-enterprise
docker compose up -d caddy
docker logs caddy --tail 50  # Verify TLS startup
```

### Step 2: Fix prometheus Configuration (5 minutes)
```bash
ssh akushnir@192.168.168.31

# Check current config
docker exec prometheus cat /etc/prometheus/prometheus.yml | grep "rule_files"

# Fix the directory reference (should be a .yml file, not directory)
# Edit docker-compose.yml or volume mount

# Then restart
docker compose restart prometheus
```

### Step 3: Fix session-broker Image Reference (10 minutes)
```bash
# Get current code-server image digest
docker images --digests code-server

# Set CODE_SERVER_IMAGE_ID in .env or docker-compose
CODE_SERVER_IMAGE_ID=code-server@sha256:<digest>

# Restart
docker compose restart session-broker
```

### Step 4: Verify HTTPS Access (5 minutes)
```bash
# From Windows
curl -v https://kushnir.cloud 2>&1 | grep -E "^< HTTP|SSL|TLS|Certificate"

# Or test via browser
# https://kushnir.cloud
```

---

## VERIFICATION CHECKLIST

After fixes:

- [ ] `curl -v https://kushnir.cloud` returns `HTTP 200` (not SSL error)
- [ ] Certificate is valid (Let's Encrypt)
- [ ] Caddy logs show no errors: `docker logs caddy | grep error`
- [ ] prometheus is healthy: `docker ps | grep prometheus | grep Up`
- [ ] session-broker is healthy: `docker ps | grep session-broker | grep Up`
- [ ] Redis sentinel cluster initialized: `redis-cli sentinel masters`
- [ ] Primary + replica synchronized: `docker exec postgres pg_replicationslot ls | wc -l`

---

## DEPLOYMENT ARCHITECTURE EXPECTED

```
┌─────────────────────────────────────────────────────────┐
│ DNS: kushnir.cloud                                      │
│ - Primary A: 192.168.168.31 (primary host)              │
│ - Secondary A: 192.168.168.42 (replica host)            │
└─────────────────────────────────────────────────────────┘
           │                           │
    ┌──────▼──────────┐         ┌──────▼──────────┐
    │ PRIMARY (31)    │         │ REPLICA (42)    │
    ├─────────────────┤         ├─────────────────┤
    │ Caddy (443)     │ ◄─────► │ Caddy (443)     │
    │ code-server     │ LEADER  │ code-server     │
    │ PostgreSQL      │         │ PostgreSQL      │
    │ Redis (master)  │ ◄─────► │ Redis (slave)   │
    │ Sentinel        │         │ Sentinel        │
    │ Prometheus      │         │ Prometheus      │
    │ Grafana         │         │ Grafana         │
    └─────────────────┘         └─────────────────┘
```

**Current State**: Replica Caddy not running → path to .42 returns SSL error

---

## RECOMMENDATIONS (Enterprise Standard)

1. **Implement Load Balancer Pattern**:
   - Use Caddy upstream directive (already configured)
   - Or deploy HAProxy on separate host
   - Or use Cloudflare failover DNS

2. **Enforce IaC Compliance**:
   - All environment variables in .env.schema.json
   - IMAGE_ID pinned in terraform/variables.tf
   - Rule files defined in terraform

3. **Monitoring**:
   - Alert if Caddy exits on either host
   - Alert if Certificate expiration < 30 days
   - Alert if PostgreSQL replication lag > 1s

4. **DNS Resilience**:
   - Primary: 192.168.168.31 (active)
   - Backup: 192.168.168.42 (standby)
   - TTL: 60s (fast failover)

---

## NEXT STEPS

1. **Immediate** (now): Fix Caddy on replica + prometheus config
2. **Short-term** (1 hour): Verify cluster health + failover readiness
3. **Medium-term** (today): Implement monitoring alerts for component health
4. **Long-term** (this week): Implement automated failover via DNS or HAProxy

---

**Generated**: April 21, 2026 03:35 UTC  
**Status**: Ready for remediation  
**Timeline**: 30 minutes for critical fixes
