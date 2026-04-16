# Phase 2.1: OIDC Issuer Deployment for Production (ide.kushnir.cloud)

**Timeline**: April 17-18, 2026  
**Environment**: Kubernetes cluster (primary) or Docker Compose (fallback)  
**Status**: Ready for deployment  
**Owner**: DevOps + Backend team  

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Production Environment                      │
│                      ide.kushnir.cloud                          │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐         ┌──────────────────┐
│  Microservices   │         │  GitHub Actions  │
│  (code-server,   │         │  CI/CD Pipelines │
│  PostgreSQL,     │         │                  │
│  Redis)          │         └──────────────────┘
└────────┬─────────┘                 │
         │                           │
         └─────────────┬─────────────┘
                       │
                       ▼
        ┌──────────────────────────┐
        │   Workload Federation    │
        │  ┌────────────────────┐  │
        │  │  OIDC Issuer       │  │
        │  │  Port: 8888        │  │
        │  │  (Kubernetes/Docker)   │
        │  └────────────────────┘  │
        └──────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
  .well-known/   .well-known/    /token
openid-config   jwks.json      Endpoint
(Discovery)     (Key Set)      (Token Issue)
        │              │              │
        └──────────────┼──────────────┘
                       │
                       ▼
        ┌──────────────────────────┐
        │   Caddy Reverse Proxy    │
        │  oidc.kushnir.cloud      │
        │  Ports: 80/443 (HTTPS)   │
        └──────────────────────────┘
```

---

## Phase 2.1 Deliverables

### 1. Kubernetes OIDC Issuer Deployment

**File**: `config/iam/k8s-oidc-issuer-production.yaml`

Core components:
- **Namespace**: `oidc-issuer` (isolated)
- **Service Account**: `oidc-issuer-sa` (RBAC-configured)
- **ConfigMap**: OIDC issuer configuration
- **Service**: ClusterIP on port 8888
- **Deployment**: OIDC issuer pod with:
  - Image: Custom OIDC issuer or open-source (e.g., coreos/dex)
  - Replicas: 3 (high availability)
  - Health checks: Liveness + readiness probes
  - Resource limits: 256Mi memory, 100m CPU
  - Volume mounts: ED25519 signing key secret

RBAC Configuration:
- **Role**: Read access to ServiceAccounts across cluster
- **RoleBinding**: Bind `oidc-issuer-sa` to role
- **ClusterRole**: (optional) For cross-namespace ServiceAccount discovery

### 2. Signing Key Management

**File**: `config/iam/k8s-oidc-signing-secret.yaml`

Kubernetes Secret containing:
- **Key Name**: `signing-key.pem` (ED25519 private key)
- **Mounted At**: `/etc/oidc/signing-key` in pod
- **Permissions**: 0600 (read-only to container)
- **Rotation Policy**: Every 30 days via cert-manager

**Generation**:
```bash
openssl genpkey -algorithm ed25519 -out signing-key.pem
kubectl create secret generic oidc-signing-key \
  --from-file=signing-key.pem \
  --namespace=oidc-issuer
```

### 3. Caddy Reverse Proxy Configuration

**File**: `config/caddy/oidc-issuer-routing.caddyfile`

Endpoints exposed:
- `oidc.kushnir.cloud/.well-known/openid-configuration` → OIDC discovery
- `oidc.kushnir.cloud/.well-known/jwks.json` → JWKS (key set)
- `oidc.kushnir.cloud/token` → Token issuance endpoint
- `oidc.kushnir.cloud/health` → Health check

Security headers:
- HSTS (Strict-Transport-Security)
- CSP (Content-Security-Policy)
- CORS (Access-Control-Allow-Origin) for service discovery
- Rate limiting: 100 req/s for /token endpoint

### 4. Service-to-Service Integration

**File**: `config/iam/workload-identity-binding.yaml`

ServiceAccount mappings:
- `code-server-sa` → Audience: `code-server`
- `postgresql-sa` → Audience: `postgresql`
- `redis-sa` → Audience: `redis`
- `prometheus-sa` → Audience: `prometheus`
- `ollama-sa` → Audience: `ollama`

Each ServiceAccount:
- Mounted JWT at `/var/run/secrets/kubernetes.io/serviceaccount/token`
- Can exchange for OIDC token via OIDC issuer
- Token includes workload identity claims

### 5. Audit Logging

**File**: `config/iam/oidc-issuer-audit-log.yaml`

Logs all token issuance events:
- Timestamp
- ServiceAccount (issuer)
- Audience (target service)
- Token ID (jti)
- Expiration
- Error details (if failed)

Stored in:
- PostgreSQL (immutable audit table)
- Loki (searchable logs)
- Prometheus metrics (count of token issues per service)

---

## Deployment Steps

### Step 1: Create OIDC Issuer Namespace & RBAC

```bash
# Apply Kubernetes manifests
kubectl apply -f config/iam/k8s-oidc-issuer-production.yaml
kubectl apply -f config/iam/k8s-oidc-signing-secret.yaml
kubectl apply -f config/iam/workload-identity-binding.yaml

# Verify deployment
kubectl get deployment -n oidc-issuer
kubectl get svc -n oidc-issuer
kubectl logs -n oidc-issuer deployment/oidc-issuer
```

### Step 2: Configure OIDC Issuer

```bash
# Create ConfigMap with OIDC configuration
kubectl create configmap oidc-issuer-config \
  --from-literal=issuer-url=https://oidc.kushnir.cloud \
  --from-literal=token-lifetime=3600 \
  --from-literal=audit-enabled=true \
  -n oidc-issuer
```

### Step 3: Setup Caddy Reverse Proxy

```bash
# Include OIDC issuer routing in Caddy config
caddy reload --config /etc/caddy/Caddyfile

# Verify .well-known endpoints
curl https://oidc.kushnir.cloud/.well-known/openid-configuration
curl https://oidc.kushnir.cloud/.well-known/jwks.json
```

### Step 4: Test Token Issuance

```bash
# Exec into a pod and test token generation
kubectl run test-pod --image=curlimages/curl -it --rm -- \
  sh -c "curl http://oidc-issuer.oidc-issuer:8888/token \
  -H 'X-Service-Account: code-server-sa' \
  -H 'X-Namespace: default'"

# Decode JWT to verify claims
```

### Step 5: Verify Service Integration

```bash
# Test from code-server pod
kubectl exec -it <code-server-pod> -- \
  curl http://oidc-issuer.oidc-issuer.svc.cluster.local:8888/token

# Check audit logs
kubectl logs -n oidc-issuer deployment/oidc-issuer | grep "token_issued"
```

---

## Deployment Verification Checklist

- [ ] OIDC issuer pods running (3 replicas healthy)
- [ ] Service endpoint accessible: `oidc-issuer.oidc-issuer.svc.cluster.local:8888`
- [ ] Caddy reverse proxy configured and reloading correctly
- [ ] OIDC discovery endpoint responding
- [ ] JWKS endpoint returning valid public keys
- [ ] Token issuance working for test ServiceAccount
- [ ] JWT tokens contain correct claims (iss, aud, exp, iat, jti)
- [ ] Audit logs capturing all token issuance events
- [ ] Health check endpoints responding
- [ ] Rate limiting working (100 req/s for /token)

---

## Fallback: Docker Compose Deployment

If Kubernetes unavailable, deploy OIDC issuer as Docker container:

```yaml
# docker-compose addition
services:
  oidc-issuer:
    image: coreos/dex:v2.35.3
    container_name: oidc-issuer
    ports:
      - "8888:8888"
    volumes:
      - ./config/iam/oidc-issuer-config.yaml:/etc/dex/config.yaml
      - ./config/iam/signing-key.pem:/etc/dex/signing-key.pem
    environment:
      ISSUER_URL: http://localhost:8888
      LOG_LEVEL: info
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8888/health"]
      interval: 10s
      timeout: 5s
      retries: 3
```

---

## Production Hardening Checklist

- [ ] Signing key rotation automated (every 30 days)
- [ ] OIDC issuer behind rate limiting
- [ ] TLS/HTTPS enforced (no plain HTTP in production)
- [ ] Audit logging to immutable storage (PostgreSQL + Loki)
- [ ] Metrics collected (token issuance rate, latency, errors)
- [ ] Alerts configured (issuer down, token issuance failures, key rotation)
- [ ] Backup strategy for signing keys (encrypted, offline copy)
- [ ] Disaster recovery tested (issuer failover <5 minutes)
- [ ] Access logs captured (who requested tokens, when)
- [ ] Token validation library deployed to all services

---

## Metrics & Observability

### Prometheus Metrics

```
oidc_issuer_tokens_issued_total{audience="code-server",status="success"}
oidc_issuer_token_issuance_duration_seconds{quantile="0.99"}
oidc_issuer_jwks_refreshes_total{status="success"}
oidc_issuer_signing_key_rotation_seconds_since_rotation
```

### Grafana Dashboards

1. **OIDC Issuer Health**: Pod status, token issuance rate, error rate
2. **Workload Identity**: Tokens issued per service, token age distribution
3. **Audit Trail**: Token issuance timeline, failed attempts, anomalies

---

## Rollback Procedure (If Issues)

```bash
# 1. Scale down OIDC issuer
kubectl scale deployment oidc-issuer --replicas=0 -n oidc-issuer

# 2. Services fall back to cached tokens or direct authentication
# 3. Investigate logs
kubectl logs -n oidc-issuer pod/oidc-issuer-xxx

# 4. Fix issue and redeploy
kubectl delete pod -n oidc-issuer -l app=oidc-issuer

# 5. Verify services reconnect
kubectl logs deployment/code-server | grep "token validation"
```

---

## Success Criteria

✅ OIDC issuer operational and healthy  
✅ All .well-known endpoints responding  
✅ Token issuance working for all services  
✅ JWT tokens contain correct claims  
✅ Audit logging capturing all events  
✅ Metrics visible in Prometheus  
✅ Alerts configured and testing  
✅ No errors in service logs after integration  
✅ Latency <100ms for token issuance  
✅ 99.9% availability (HA with 3 replicas)  

---

## Next Steps (Phase 3+)

After Phase 2.1 deployment:
1. **Phase 3**: RBAC enforcement in all services
2. **Phase 4**: Audit logging + compliance dashboards
3. **Phase 5**: Token rotation + refresh mechanism
4. **Phase 6**: Workload identity for external services (GitHub Actions, GCP, AWS)

---

**Phase 2.1 Status**: Ready for deployment  
**Deployment Window**: Apr 17-18, 2026  
**Owner**: DevOps team  
**Estimate**: 4-6 hours (including validation & integration testing)  
