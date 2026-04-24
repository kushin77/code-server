# Dynamic Ingress Routing Strategy for Ephemeral Sessions

**Purpose**: Dynamic Ingress Routing Strategy for Ephemeral Sessions — reference and operational document.

> Issue: [#908](https://github.com/kushin77/code-server/issues/908)
> Parent: [#906](https://github.com/kushin77/code-server/issues/906)
> Date: 2026-04-20
> Status: Strategy Design & Implementation Plan

## Executive Summary

This document defines the routing strategy for temporary, session-bound URLs in the ephemeral session platform. We implement **subpath-based routing** (`dev.kushnir.cloud/<sessionId>`) over subdomain routing to optimize for DNS propagation latency, simplify certificate management, and enable session-scoped middleware policies.

---

## 1. Routing Strategy Decision Record

### 1.1 Design Options

| Aspect | Subpath (`dev.kushnir.cloud/<sessionId>`) | Subdomain (`<sessionId>.dev.kushnir.cloud`) |
|--------|-------------------------------------------|------------------------------------------|
| **DNS Propagation** | Immediate (single zone) | 5–30s min (new CNAME/DNS) |
| **Certificate** | Single wildcard cert | Wildcard or per-session cert (expensive) |
| **Session Isolation** | Session middleware rewrite | SNI/cert-based isolation |
| **Rewrite Complexity** | Moderate (path rewrite + headers) | Low (direct routing) |
| **Cache/CDN Hygiene** | Per-subpath cache keys | Per-subdomain cache purge |
| **Stale Route Cleanup** | Path-based rules + age check | DNS record cleanup |
| **Operator Experience** | One URL pattern | Multiple DNS lookups per session |

### 1.2 **Decision: Subpath-Based Routing**

**Rationale:**
- **Speed**: Sessions ready immediately post-provisioning; no DNS wait
- **Simplicity**: One cert, one DNS zone, one ingress controller
- **Policy Uniformity**: All ephemeral sessions share a single domain, making middleware/auth/logging consistent
- **Scalability**: 10k concurrent sessions on one DNS record vs. 10k DNS entries

**Trade-off:** Path rewriting is slightly more complex, but worth the operational simplicity.

---

## 2. URL Scheme and Format

### 2.1 Ephemeral Session URL

```
https://dev.kushnir.cloud/<sessionId>
```

Where:
- **Base Domain**: `dev.kushnir.cloud` (fixed, pre-configured)
- **Session ID**: UUID format or hash (40 chars max for URL safety)
  - Format: `eph-<8-char-hex>` (e.g., `eph-a1b2c3d4`)
  - Uniqueness: Collision-resistant, audit-traceable

### 2.2 Example Session URLs

```
https://dev.kushnir.cloud/eph-a1b2c3d4        # Session home/IDE
https://dev.kushnir.cloud/eph-a1b2c3d4/api    # Proxied backend
https://dev.kushnir.cloud/eph-a1b2c3d4/test   # Test runner UI
```

---

## 3. Ingress Route Management Architecture

### 3.1 Route Lifecycle

```
[Session Provisioning]
        ↓
  [Allocate Session ID: eph-XXXX]
        ↓
  [Create Ingress Route: /eph-XXXX → Pod]
        ↓
  [Add auth/rate-limit middleware]
        ↓
  [Set TTL timer (default: 1h)]
        ↓
[Session Live & Routable]
        ↓
[Session Complete / TTL Expired]
        ↓
  [Revoke auth token]
  [Remove Ingress Route]
  [Drain connections (30s timeout)]
        ↓
  [Delete Route Resources]
        ↓
[Session Cleaned Up]
```

### 3.2 Route Ownership

**Route Resources** (per session):
1. Kubernetes Ingress resource: `eph-<sessionId>`
2. ConfigMap: `eph-<sessionId>-config` (session metadata)
3. Secret: `eph-<sessionId>-auth` (session auth token)
4. DaemonSet pod: `code-server-<sessionId>`

**Ownership Label**: `app.kubernetes.io/session-id=eph-XXXX`

---

## 4. Implementation Approach

### 4.1 Session Orchestrator → Route Manager Integration

**Session Orchestrator API** (from #910):
```bash
POST /sessions
  {
    "session_id": "eph-a1b2c3d4",
    "status": "ready",
    "pod_name": "code-server-eph-a1b2c3d4",
    "pod_port": 8080,
    "session_ttl_seconds": 3600,
    "auth_token": "session_token_XXXXXXXX"
  }
```

**Route Manager** responds by:
1. Creating Kubernetes Ingress resource
2. Adding auth middleware (Caddy plugin or NGINX auth_request)
3. Registering route in observability system (metrics, logs)
4. Setting cleanup timer

### 4.2 Route Creation (Kubernetes)

**Ingress Resource Template** (`kubernetes/ephemeral/ingress-template.yaml`):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: eph-{{ session_id }}
  namespace: ephemeral-sessions
  labels:
    app.kubernetes.io/session-id: eph-{{ session_id }}
    app.kubernetes.io/managed-by: session-orchestrator
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - dev.kushnir.cloud
      secretName: dev-kushnir-cloud-cert
  rules:
    - host: dev.kushnir.cloud
      http:
        paths:
          - path: /eph-{{ session_id }}(/|$)(.*)
            pathType: RegExp
            backend:
              service:
                name: code-server-{{ session_id }}
                port:
                  number: 8080
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/auth-type: bearer
    nginx.ingress.kubernetes.io/auth-secret: eph-{{ session_id }}-auth
    nginx.ingress.kubernetes.io/auth-secret-key: token
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Session-ID: {{ session_id }}";
      more_set_headers "X-Session-Expires: {{ expiry_time }}";
      proxy_set_header X-Original-URI $request_uri;
```

### 4.3 Route Cleanup (TTL + Manual Revocation)

**Cleanup Policy:**
- **TTL Expiry**: Auto-delete route after `session_ttl_seconds` (default 1h)
- **Manual Revocation**: Session lifecycle can trigger immediate cleanup
- **Drain Period**: 30s graceful drain before forceful cleanup
- **Stale Route Reaping**: Daily audit; cleanup any route with no active pod

**Cleanup Script** (`scripts/ops/cleanup-ephemeral-routes.sh`):

```bash
#!/usr/bin/env bash
# Clean up orphaned ephemeral routes and expired sessions

kubectl get ingress -n ephemeral-sessions -o json | jq -r '.items[] | 
  select(.metadata.creationTimestamp | fromdateiso8601 < now - 3600) |
  .metadata.name' | while read -r ingress; do
  
  SESSION_ID=$(echo "$ingress" | sed 's/^eph-//')
  
  # Verify pod is gone
  if ! kubectl get pod "code-server-$SESSION_ID" -n ephemeral-sessions &>/dev/null; then
    log_info "Cleaning up orphaned route: $ingress"
    kubectl delete ingress "$ingress" -n ephemeral-sessions
    kubectl delete secret "eph-$SESSION_ID-auth" -n ephemeral-sessions 2>/dev/null || true
  fi
done
```

---

## 5. Security & Policy Framework

### 5.1 Authentication & Authorization

**Auth Flow:**
```
Browser → Caddy (TLS)
        → Auth Middleware (session token validation)
        → Rate Limiter (10 req/s per session)
        → Ingress Route
        → Code-Server Pod
```

**Token Validation**:
- Session token embedded in URL fragment or Bearer header
- Token scoped to single session ID
- Token expires with session TTL
- Token invalidated on session revocation

**Middleware Chain**:
1. **TLS**: Cloudflare → Caddy (HTTPS enforcement)
2. **Auth**: Bearer token validation (session.token)
3. **Rate Limit**: 10 requests/sec per session
4. **Headers**: Add X-Session-ID, X-Session-Expires, X-Forwarded-For
5. **Logging**: All requests logged to session audit trail

### 5.2 CORS & Headers

**Security Headers** (applied to all ephemeral session routes):
```
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN (or DENY for IDE)
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'
```

**CORS Policy**:
- Allow same-origin (dev.kushnir.cloud) requests only
- Preflight caching: 86400s (1 day)
- Disallow credentials on cross-origin requests

---

## 6. Observability & Monitoring

### 6.1 Metrics

**Prometheus Metrics** (scraped from route manager):

```yaml
metrics:
  - ephemeral_routes_active{session_id="eph-XXXX"}  # gauge
  - ephemeral_route_create_duration_seconds{session_id="eph-XXXX"}  # histogram
  - ephemeral_route_cleanup_duration_seconds{session_id="eph-XXXX"}  # histogram
  - ephemeral_route_request_total{session_id="eph-XXXX", status="200|4xx|5xx"}  # counter
  - ephemeral_route_request_duration_seconds{session_id="eph-XXXX"}  # histogram
  - ephemeral_stale_routes_count  # gauge (routes without active pod)
  - ephemeral_cleanup_failures_total  # counter
```

### 6.2 Alerts

```yaml
groups:
  - name: ephemeral-routing-alerts
    rules:
      - alert: EphemeralRouteCleanupFailed
        expr: ephemeral_cleanup_failures_total > 0
        for: 5m
        annotations:
          summary: "Session route cleanup failed for {{ $labels.session_id }}"
      
      - alert: EphemeralStaleRoutesDetected
        expr: ephemeral_stale_routes_count > 0
        for: 1h
        annotations:
          summary: "{{ $value }} stale ephemeral routes detected"
      
      - alert: EphemeralRouteLatencyHigh
        expr: histogram_quantile(0.95, ephemeral_route_request_duration_seconds) > 0.5
        for: 5m
```

### 6.3 Audit Trail

**Session Route Audit Log** (all operations logged):
```json
{
  "timestamp": "2026-04-20T12:34:56Z",
  "event": "route_created|route_revoked|route_cleanup",
  "session_id": "eph-a1b2c3d4",
  "actor": "session-orchestrator",
  "details": {
    "pod_name": "code-server-eph-a1b2c3d4",
    "ttl_seconds": 3600,
    "expiry_time": "2026-04-20T13:34:56Z"
  }
}
```

---

## 7. Stale Route Detection & Cleanup

### 7.1 Automated Reaping

**Daily Cleanup Job** (CronJob):
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ephemeral-route-cleanup
  namespace: ephemeral-sessions
spec:
  schedule: "0 * * * *"  # Hourly
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: route-manager
          containers:
            - name: cleanup
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  NOW=$(date +%s)
                  kubectl get ingress -n ephemeral-sessions -o json | jq -r '.items[] |
                    select(.metadata.creationTimestamp | fromdateiso8601 < now - 3600) |
                    select(.metadata.ownerReferences[0].kind != "Pod") |
                    .metadata.name' | while read -r ingress; do
                    
                    SESSION_ID=$(echo "$ingress" | sed 's/^eph-//')
                    if ! kubectl get pod "code-server-$SESSION_ID" -n ephemeral-sessions &>/dev/null; then
                      echo "Deleting stale route: $ingress"
                      kubectl delete ingress "$ingress" -n ephemeral-sessions
                    fi
                  done
          restartPolicy: OnFailure
```

### 7.2 Post-Teardown Audit

**Route Cleanup Verification** (run post-teardown):
```bash
bash scripts/ops/verify-route-cleanup.sh --session-id eph-a1b2c3d4
```

**Verification Checks:**
- ✓ Ingress resource deleted
- ✓ Auth secret deleted
- ✓ Service deleted
- ✓ Pod deleted
- ✓ No DNS records point to session
- ✓ Audit log entry recorded

---

## 8. Implementation Roadmap

| Phase | Owner | Target | Deliverables |
|-------|-------|--------|--------------|
| **Phase 1: Route Manager Core** | @kushin77 | May 1 | Route CRUD API, Ingress templates, session integration |
| **Phase 2: Auth & Middleware** | @kushin77 | May 8 | Token validation, rate limiting, security headers |
| **Phase 3: Observability** | @kushin77 | May 12 | Metrics, alerts, audit logging |
| **Phase 4: Cleanup & Testing** | @kushin77 | May 15 | Stale route cleanup, e2e tests, runbook |

---

## 9. Acceptance Criteria Mapping

| Criterion | Implementation | Verification |
|-----------|----------------|--------------|
| New session receives unique reachable URL | Ingress route creation + auth token | POST /sessions → URL accessible |
| URL deactivates immediately after teardown | Manual + TTL-based cleanup | Route audit: zero stale routes |
| No stale route remains after TTL expiry | CronJob cleanup + pod sync | Daily cleanup job validates |
| Route ownership/lifecycle auditable | Session ID labels + audit log | `kubectl logs` + structured events |
| Security headers/auth match baseline | Middleware chain + CSP headers | OWASP ZAP scan + pentest validation |

---

## 10. Related Files

- Orchestrator: [#910](https://github.com/kushin77/code-server/issues/910) Session Orchestrator API
- Tests: [#909](https://github.com/kushin77/code-server/issues/909) Headless test execution
- Runbooks: [#912](https://github.com/kushin77/code-server/issues/912) Incident procedures

---

## 11. References

- [OWASP — Temporary Session URLs](https://owasp.org/www-project-web-security-testing-guide/stable/4-Web_Application_Security_Testing/07-Input_Validation_Testing/07-Testing_for_Client-side_URL_Redirect.html)
- [Kubernetes Ingress API](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [NGINX Ingress Controller — Configuration](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/)