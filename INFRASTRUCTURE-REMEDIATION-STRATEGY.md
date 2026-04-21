# INFRASTRUCTURE REMEDIATION STRATEGY — April 21, 2026

## EXECUTIVE SUMMARY: THREE REMEDIATION OPTIONS

The SSL_PROTOCOL_ERROR is caused by **two completely incompatible deployment systems** on the same network:

| Component | Primary (31) | Replica (42) | Status |
|-----------|--------------|--------------|--------|
| Orchestration | Docker Compose | Kubernetes | ❌ MISMATCHED |
| Web Server | Caddy 2.9.1 | NGINX + Ingress | ❌ MISMATCHED |
| Services | code-server + microservices | elevatediq.ai app | ❌ MISMATCHED |
| DNS Target | kushnir.cloud | elevatediq.ai | ❌ MISMATCHED |
| TLS Issuer | Let's Encrypt | (not configured) | ❌ MISMATCHED |

---

## OPTION 1: CONSOLIDATE TO DOCKER COMPOSE (RECOMMENDED - 4 HOURS)

**Strategy**: Use Primary (192.168.168.31) as single source of truth. Migrate/disable Replica.

### Phase 1: Migrate Primary to Production (1 hour)

1. **Verify Primary Caddy**:
   ```bash
   ssh akushnir@192.168.168.31
   docker logs caddy | grep "Serving" | head -1  # Confirm TLS active
   curl -v https://192.168.168.31 2>&1 | grep "SSL"  # Verify cert
   ```

2. **Update DNS** (Registrar or DNS Provider):
   ```
   kushnir.cloud  A  192.168.168.31       (primary host)
   *.kushnir.cloud  A  192.168.168.31     (wildcard for subdomains)
   ```

3. **Test Access**:
   ```bash
   curl -v https://kushnir.cloud  # Should work (Caddy responds)
   curl -v https://ide.kushnir.cloud  # Should proxy to code-server:8080
   ```

4. **Fix Failing Services on Primary** (30 minutes):

   **a) Fix Prometheus Configuration** ✅
   ```bash
   docker exec prometheus cat /etc/prometheus/prometheus.yml | grep rule_files
   # Error: /etc/prometheus/prometheus-rules-phase-23.yml: is a directory
   # Fix: Change to file path (e.g., prometheus-rules.yml)
   ```

   **b) Fix session-broker Image Reference** ✅
   ```bash
   # Get code-server digest
   docker images code-server-enterprise:dev --digests
   
   # Update .env:
   CODE_SERVER_IMAGE_ID=code-server-enterprise@sha256:ACTUAL_DIGEST
   
   docker-compose restart session-broker
   ```

   **c) Fix Redis Sentinel Cluster** ✅
   ```bash
   # Once session-broker is healthy:
   docker-compose restart redis-sentinel-1 redis-sentinel-arbiter
   
   # Verify cluster:
   docker exec redis-sentinel-1 redis-cli sentinel masters
   ```

### Phase 2: Decommission Replica (30 minutes)

Option A (Keep for DR):
```bash
ssh akushnir@192.168.168.42

# Stop Kubernetes/NGINX (preserve for future DR)
sudo systemctl stop nginx
sudo systemctl disable nginx

# Clean up Docker containers (optional)
docker compose down -v
```

Option B (Full Wipe):
```bash
ssh akushnir@192.168.168.42
sudo kubeadm reset -f  # If Kubernetes installed
sudo rm -rf /etc/kubernetes
sudo systemctl stop nginx
```

### Phase 3: Verify End-to-End (30 minutes)

```bash
# From Windows
curl -v https://kushnir.cloud
# Should see:
# - 200 OK from Caddy
# - Let's Encrypt certificate
# - Redirect to code-server or oauth2-proxy

curl -v https://ide.kushnir.cloud/healthz
# Should see:
# - 200 from code-server health check
# - Healthy = active session

curl -v https://prometheus.kushnir.cloud
# Should see:
# - 200 from Prometheus UI
# - Metrics available
```

---

## OPTION 2: CONSOLIDATE TO KUBERNETES (ADVANCED - 8 HOURS)

**Strategy**: Migrate Docker Compose services to Kubernetes, keep Replica as cluster node.

### Architecture
```
Primary (192.168.168.31) = Kubernetes Master + Worker
Replica (192.168.168.42) = Kubernetes Worker
NGINX Ingress Controller (Replica) = API Gateway for all services
```

### Implementation (High-level)
1. Initialize Kubernetes on Primary: `kubeadm init`
2. Join Replica: `kubeadm join ... --token=XXX`
3. Install NGINX Ingress Controller
4. Migrate each service from docker-compose to Helm charts:
   - code-server → Helm chart
   - caddy → Helm chart (or use NGINX Ingress)
   - postgresql → Helm + Statefulset
   - redis → Helm + StatefulSet
   - prometheus → Helm + kube-prometheus-stack
5. Configure IngressRoute for kushnir.cloud
6. Verify replication + high availability

**Pros**: True HA, scaling, auto-healing  
**Cons**: Complexity, migration time, requires Kubernetes expertise

---

## OPTION 3: HYBRID DEPLOYMENT (COMPROMISE - 6 HOURS)

**Strategy**: Keep Docker Compose primary, use Replica as cold standby with manual failover.

### Setup
```
PRIMARY (192.168.168.31) = Active
  - Docker Compose (all services)
  - Caddy (TLS)
  - DNS points here

REPLICA (192.168.168.42) = Cold Standby
  - Identical docker-compose config (pre-built, stopped)
  - NGINX ingress removed
  - Ready to start manually if primary fails
```

### Failover Procedure (if primary fails)
```bash
# On replica
ssh akushnir@192.168.168.42
cd /home/akushnir/code-server-enterprise
docker compose up -d

# Update DNS
# kushnir.cloud → 192.168.168.42

# Verify
curl -v https://kushnir.cloud
```

**Pros**: Simple, fast, low risk  
**Cons**: No automatic failover, manual intervention required

---

## IMMEDIATE ACTION PLAN (Choose ONE Path)

### 🟢 RECOMMENDED: Option 1 (Docker Compose Primary)

**Timeline**: 4 hours  
**Risk**: Low  
**Effort**: Medium  
**Expertise**: Intermediate

**Step-by-step**:

1. **Fix Primary Services** (30 min):
   ```bash
   ssh akushnir@192.168.168.31
   
   # Fix prometheus rule file reference
   docker exec prometheus cat /etc/prometheus/prometheus.yml
   # Update if pointing to directory
   docker-compose restart prometheus
   
   # Fix session-broker image
   CODE_SERVER_IMAGE_ID=$(docker images code-server-enterprise:dev --digests --quiet | cut -d' ' -f1)
   echo "CODE_SERVER_IMAGE_ID=${CODE_SERVER_IMAGE_ID}" >> .env
   docker-compose restart session-broker
   
   # Fix Redis Sentinel
   docker-compose restart redis-sentinel-1
   ```

2. **Verify Primary Services** (10 min):
   ```bash
   docker ps | grep -E "prometheus|session-broker|sentinel" | grep "Up"
   docker logs prometheus | tail -5  # Should show "server is ready to receive requests"
   docker logs session-broker | tail -5  # Should show no "policyCode" errors
   ```

3. **Update DNS** (5 min):
   - Login to DNS provider (registrar, Cloudflare, Route53, etc.)
   - Set `kushnir.cloud` → `192.168.168.31`
   - Wait for propagation (1-15 minutes)

4. **Test HTTPS Access** (5 min):
   ```bash
   # From Windows
   curl -v https://kushnir.cloud -I  # Should return HTTP 200 or redirect
   
   # Browser: https://kushnir.cloud
   # Should see: code-server login or oauth2-proxy auth flow
   ```

5. **Decommission Replica** (10 min):
   ```bash
   ssh akushnir@192.168.168.42
   sudo systemctl stop nginx
   # Keep Kubernetes/services running for now (DR backup)
   ```

---

## KUBERNETES MIGRATION CHECKLIST (If doing Option 2)

- [ ] Kubernetes cluster initialized on primary + replica joined
- [ ] NGINX Ingress Controller deployed
- [ ] Persistent volumes configured (NAS integration)
- [ ] StatefulSets for postgres, redis, elasticsearch
- [ ] Deployments for stateless services
- [ ] Service mesh (optional: Istio for advanced traffic management)
- [ ] ArgoCD or FluxCD for GitOps
- [ ] Monitoring integrated (prometheus operator)
- [ ] Backup/restore strategy
- [ ] Disaster recovery procedure

---

## SECURITY POSTURE AFTER CONSOLIDATION

| Aspect | Before | After |
|--------|--------|-------|
| TLS Endpoint | Dual (Caddy + NGINX) | Single (Caddy) ✅ |
| DNS Propagation | Inconsistent | Single source ✅ |
| Certificate Management | Multiple issuers | Let's Encrypt via Caddy ✅ |
| Service Discovery | Manual DNS | Automatic via compose ✅ |
| Failover | Manual | Manual (Option 1) / Automatic (Option 2) |
| Compliance | Split systems | Unified ✅ |

---

## MONITORING & ALERTING POST-CONSOLIDATION

```yaml
Alerts to Configure:
  - caddy.certificate.expiration < 30 days
  - caddy.port_80_unavailable (can't listen on 80)
  - caddy.port_443_unavailable (can't listen on 443)
  - caddy.tls_handshake_failures > 10/min
  - prometheus.scrape_failures > 5
  - code_server.unhealthy (container exits)
  - dns_resolution_latency > 100ms
```

---

## DECISION MATRIX

Choose based on your requirements:

| Factor | Option 1 (Docker) | Option 2 (K8s) | Option 3 (Hybrid) |
|--------|-------------------|-----------------|-------------------|
| Speed to Resolution | ⭐⭐⭐ (4h) | ⭐ (8h+) | ⭐⭐⭐ (4h) |
| High Availability | ⭐⭐ (manual) | ⭐⭐⭐⭐⭐ (auto) | ⭐ (none) |
| Complexity | ⭐⭐ (moderate) | ⭐⭐⭐⭐⭐ (complex) | ⭐ (simple) |
| Production Readiness | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| Team Expertise Required | Intermediate | Advanced | Beginner |
| Scalability | Limited | Unlimited | Limited |
| Long-term Viability | 6-12 months | 3+ years | 3-6 months |

---

## RECOMMENDATION

**Go with Option 1 (Docker Compose)** because:

1. ✅ Fastest path to fix (4 hours vs 8+ hours)
2. ✅ Lowest risk (no migrations, single orchestrator)
3. ✅ Addresses immediate business blocker (SSL error)
4. ✅ Provides time for team to evaluate Kubernetes (Option 2) later
5. ✅ Uses existing infrastructure (Primary host already running Docker)
6. ✅ Allows Option 3 hybrid setup as interim solution
7. ✅ All monitoring/observability already in docker-compose

**Migration Path**:
```
NOW          →  OPTION 1 (Docker/Primary)
3-6 months   →  OPTION 3 (Hybrid/Cold Standby)
6-12 months  →  OPTION 2 (Kubernetes/Full HA)
```

---

## NEXT STEPS

1. **Approve Option 1 remediation plan**
2. **Allocate 4 hours of execution time**
3. **Execute Step-by-step action plan** (above)
4. **Verify HTTPS access from external clients**
5. **Document final architecture** (for knowledge base)
6. **Plan Kubernetes migration** (for Q2 2026)

---

**Generated**: April 21, 2026 03:40 UTC  
**Status**: Ready for decision + execution  
**Reviewer**: Infrastructure team  
