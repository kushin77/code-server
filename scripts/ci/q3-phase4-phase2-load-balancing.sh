#!/bin/bash
################################################################################
# Q3 Phase 4: Phase 2 Load Balancing & Traffic Management Configuration
# @governance IaC, immutable, idempotent, environment-driven
# @purpose Generate load balancing and traffic routing configuration for Phase 2
# @phase Q3 Phase 4 - Phase 2 (May 13-26, 2026)
# @date $(date '+%Y-%m-%d %H:%M:%S')
################################################################################

set -euo pipefail
IFS=$'\n\t'

# Source environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

# Load network configuration SSOT
source "${PROJECT_ROOT}/scripts/_common/_epic-1536-network-config.env" || {
    echo "Error: Network configuration SSOT not found"
    exit 1
}

# Configuration (SSOT)
OUTPUT_DIR="${PROJECT_ROOT}/artifacts/q3-phase4-phase2"
TIMESTAMP=$(date '+%Y-%m-%d')
CONFIG_FILE="${OUTPUT_DIR}/PHASE2-LOAD-BALANCING-CONFIG-${TIMESTAMP}.yaml"
PROCEDURES_FILE="${OUTPUT_DIR}/PHASE2-LB-PROCEDURES-${TIMESTAMP}.md"

mkdir -p "${OUTPUT_DIR}"

################################################################################
# Generate Load Balancing Configuration
################################################################################

cat > "${CONFIG_FILE}" <<'EOF'
# Phase 2 Load Balancing & Traffic Management Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Purpose: NGINX Ingress + Kubernetes Service routing for 8 stateless services

---

## VRRP Virtual IP Configuration (Ingress Entry Point)
virtual_ip: 
virtual_port_http: 80
virtual_port_https: 443
vrrp_priority: 100
vrrp_interface: eth0

---

## Ingress Controller Configuration

apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-ingress-config
  namespace: ingress-nginx
data:
  # Global timeout settings
  proxy-read-timeout: "120"
  proxy-connect-timeout: "10"
  proxy-send-timeout: "120"
  
  # Connection pooling
  upstream-keepalive-connections: "32"
  upstream-keepalive-requests: "100"
  
  # Load balancing
  upstream-hash-by: "$request_uri"
  
  # TLS settings
  ssl-protocols: "TLSv1.2 TLSv1.3"
  ssl-ciphers: "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384"
  ssl-session-cache: "shared:SSL:10m"
  ssl-session-timeout: "10m"

---

## Service Routing Rules

### Service 1: auth-server (High-Traffic, Blue-Green)

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: auth-server-ingress
  namespace: production
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/rate-limit: "1000"
    nginx.ingress.kubernetes.io/enable-cors: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - auth.
    secretName: auth-server-tls
  rules:
  - host: auth.
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: auth-server
            port:
              number: 3100

---

apiVersion: v1
kind: Service
metadata:
  name: auth-server
  namespace: production
  labels:
    service: auth-server
spec:
  type: ClusterIP
  sessionAffinity: None  # No session affinity (stateless)
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800
  ports:
  - port: 3100
    targetPort: 3100
    protocol: TCP
    name: http
  selector:
    app: auth-server
    version: "1"  # Will switch: "1" (blue) → "2" (green)

---

### Service 2: api-gateway (High-Traffic, Blue-Green)

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-gateway-ingress
  namespace: production
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/rate-limit: "2000"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - 
    secretName: api-gateway-tls
  rules:
  - host: 
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-gateway
            port:
              number: 3100

---

apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: production
spec:
  type: ClusterIP
  ports:
  - port: 3100
    targetPort: 3100
    protocol: TCP
  selector:
    app: api-gateway
    version: "1"  # Will switch to "2"

---

### Service 3: control-plane (Medium-Traffic, Rolling Update)

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: control-plane-ingress
  namespace: production
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - control.
    secretName: control-plane-tls
  rules:
  - host: control.
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: control-plane
            port:
              number: 8080

---

apiVersion: v1
kind: Service
metadata:
  name: control-plane
  namespace: production
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
  selector:
    app: control-plane

---

### Services 4-8: Canary Deployment Services

# prompt-gateway, memory-engine, activity-feed, event-bus, execution-scheduler
# All use ClusterIP (internal-only services for now)

apiVersion: v1
kind: Service
metadata:
  name: prompt-gateway
  namespace: production
spec:
  type: ClusterIP
  ports:
  - port: 3100
    targetPort: 3100
    protocol: TCP
  selector:
    app: prompt-gateway

---

## Health Check Configuration

### Readiness Probe (Traffic Eligibility)

readinessProbe:
  httpGet:
    path: /health/ready
    port: 3100
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
  successThreshold: 1

### Liveness Probe (Pod Restart)

livenessProbe:
  httpGet:
    path: /health/live
    port: 3100
  initialDelaySeconds: 15
  periodSeconds: 30
  timeoutSeconds: 5
  failureThreshold: 3
  successThreshold: 1

---

## Traffic Distribution Weights (Canary Example)

apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: prompt-gateway-canary
  namespace: production
spec:
  hosts:
  - prompt-gateway
  http:
  # Route with header (for testing)
  - match:
    - headers:
        x-canary-user:
          exact: "true"
    route:
    - destination:
        host: prompt-gateway
        subset: v2
      weight: 100
  # Default traffic split
  - route:
    - destination:
        host: prompt-gateway
        subset: v1
      weight: 95  # Start at 95% old, 5% new
    - destination:
        host: prompt-gateway
        subset: v2
      weight: 5

---

## Pod Disruption Budget (High-Availability)

apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: auth-server-pdb
  namespace: production
spec:
  minAvailable: 2  # At least 2 pods always available
  selector:
    matchLabels:
      app: auth-server

---

## Horizontal Pod Autoscaler (Auto-scaling)

apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 60
      selectPolicy: Max

---

## NetworkPolicy (Service Mesh - Optional Istio)

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-gateway-to-downstream
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api-gateway
  policyTypes:
  - Egress
  egress:
  # Allow to DNS
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
  # Allow to downstream services
  - to:
    - podSelector:
        matchLabels:
          service-tier: backend
    ports:
    - protocol: TCP
      port: 3100

EOF

cat > "${PROCEDURES_FILE}" <<'EOF'
# Phase 2 Load Balancing Operational Procedures

**Date**: $(date '+%Y-%m-%d %H:%M:%S')  
**Status**: READY FOR IMPLEMENTATION  

---

## Pre-Deployment Verification Checklist

### Ingress Controller (Must be operational)

```bash
# 1. Verify NGINX Ingress running
kubectl get deployment -n ingress-nginx
# Expected: ingress-nginx-controller (Ready)

# 2. Verify service external IP
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Expected: EXTERNAL-IP = 

# 3. Verify VRRP active
ip addr show | grep 
# Expected: inet /32 (on primary host)

# 4. Test ingress connectivity
curl -I https://
# Expected: HTTP 200 or 301 (redirect to app)
```

### Services Configuration

```bash
# 1. Verify all services exist
kubectl get svc -n production
# Expected: auth-server, api-gateway, control-plane, prompt-gateway, etc.

# 2. Verify service endpoints
kubectl describe svc auth-server -n production | grep Endpoints
# Expected: Endpoints: 10.x.x.x:3100,10.x.x.y:3100,10.x.x.z:3100

# 3. Verify load balancing
for i in {1..10}; do
  kubectl exec -it pod/test-client -- curl -s http://auth-server:3100/hostname
done
# Expected: Different pods each time (round-robin)
```

---

## Phase 2 Service Cutover Procedures

### Procedure 1: Blue-Green Deployment (auth-server)

**Pre-Cutover** (T-5 minutes):
```bash
# 1. Deploy green version
kubectl set image deployment/auth-server-green \
  auth-server=registry/auth-server:v2

# 2. Wait for readiness
kubectl wait --for=condition=Ready pod \
  -l deployment=auth-server-green --timeout=300s

# 3. Run smoke tests
curl -v http://auth-server-green:3100/health
```

**Cutover** (T+0 minutes):
```bash
# 1. Update service selector to green
kubectl patch service auth-server \
  -p '{"spec":{"selector":{"version":"2"}}}'

# 2. Monitor traffic shift (should complete in < 5 seconds)
kubectl logs deployment/auth-server-green -f --tail=20

# 3. Monitor metrics
kubectl top pods -l app=auth-server
```

**Post-Cutover** (T+15 minutes):
```bash
# 1. If stable: scale down blue
kubectl scale deployment auth-server-blue --replicas=0

# 2. Document cutover timestamp
echo "auth-server cutover completed: $(date)" >> /tmp/phase2-log.txt

# 3. Proceed to next service
```

**Rollback** (if issues):
```bash
# 1. Immediate switch back
kubectl patch service auth-server \
  -p '{"spec":{"selector":{"version":"1"}}}'

# 2. Verify traffic back to blue
sleep 10 && curl http://auth-server:3100/health

# 3. Investigate failure
kubectl logs deployment/auth-server-green | grep ERROR
```

---

### Procedure 2: Canary Deployment (prompt-gateway)

**Initial Deployment** (5% traffic):
```bash
# 1. Deploy canary version
kubectl set image deployment/prompt-gateway-canary \
  prompt-gateway=registry/prompt-gateway:v2

# 2. Update VirtualService to 95/5 split
kubectl patch virtualservice prompt-gateway-canary \
  -p '{"spec":{"http":[{"route":[{"destination":{"subset":"v1"},"weight":95},{"destination":{"subset":"v2"},"weight":5}]}]}}'

# 3. Monitor canary metrics
kubectl logs deployment/prompt-gateway-canary -f --tail=30
```

**Gradual Ramp** (every 5 minutes):
```bash
# T+5 min: 75/25
kubectl patch virtualservice prompt-gateway-canary \
  --type json -p '[{"op":"replace","path":"/spec/http/0/route/0/weight","value":75},{"op":"replace","path":"/spec/http/0/route/1/weight","value":25}]'

# T+10 min: 50/50
kubectl patch virtualservice prompt-gateway-canary \
  --type json -p '[{"op":"replace","path":"/spec/http/0/route/0/weight","value":50},{"op":"replace","path":"/spec/http/0/route/1/weight","value":50}]'

# T+15 min: 25/75
kubectl patch virtualservice prompt-gateway-canary \
  --type json -p '[{"op":"replace","path":"/spec/http/0/route/0/weight","value":25},{"op":"replace","path":"/spec/http/0/route/1/weight","value":75}]'

# T+20 min: 0/100 (full cutover)
kubectl patch virtualservice prompt-gateway-canary \
  --type json -p '[{"op":"replace","path":"/spec/http/0/route/0/weight","value":0},{"op":"replace","path":"/spec/http/0/route/1/weight","value":100}]'
```

**Finalization** (after 5 min stability):
```bash
# 1. Scale down old version
kubectl scale deployment prompt-gateway-v1 --replicas=0

# 2. Mark v2 as new stable
kubectl label deployment prompt-gateway-canary \
  stability=stable --overwrite
```

---

## Monitoring During Phase 2

### Real-Time Metrics Dashboard

```bash
# 1. Grafana dashboard for service metrics
# Access: http://grafana.monitoring.svc.cluster.local:3000
# Dashboard: "Phase 2 Stateless Services Cutover"
# Panels: Latency, Error Rate, CPU/Memory, Request Count

# 2. Prometheus queries (during cutover)
# Query error rate
rate(http_requests_total{status=~"5.."}[5m])

# Query latency
histogram_quantile(0.99, http_request_duration_seconds)

# Query pod status
count(kube_pod_status_phase{phase="Running"})
```

### Alert Thresholds (Phase 2)

```yaml
- alert: ServiceLatencyHigh
  expr: histogram_quantile(0.99, http_request_duration_seconds) > 0.15
  for: 2m
  action: Page on-call engineer

- alert: ServiceErrorRateHigh
  expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.01
  for: 1m
  action: Rollback service immediately

- alert: PodNotReady
  expr: count(kube_pod_status_phase{phase!="Running"}) > 2
  for: 1m
  action: Page on-call engineer
```

---

## Load Testing During Phase 2

### k6 Load Test (Per Service)

```javascript
// File: tests/load/phase2-service-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 10 },   // Ramp to 10 VUs
    { duration: '5m', target: 50 },   // Ramp to 50 VUs
    { duration: '2m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(99)<100'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const response = http.get('http://auth-server:3100/health');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 100ms': (r) => r.timings.duration < 100,
  });
  sleep(1);
}
```

**Execution**:
```bash
# Run load test
k6 run tests/load/phase2-service-test.js \
  --out json=/tmp/k6-results.json

# Check results
jq '.metrics | keys' /tmp/k6-results.json
```

---

## Incident Response During Phase 2

### If Service Degradation Detected (During Cutover)

**T+0 to T+1 minute**:
1. Alert triggered (latency > 150ms OR error rate > 1%)
2. On-call engineer notified
3. Decision: Investigate (yellow) or Rollback (red)

**If YELLOW (investigate)**:
```bash
# Check pod status
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name> | tail -50

# Check metrics
kubectl top pod <pod-name>

# Check service connectivity
kubectl exec -it <debug-pod> -- curl -v http://service:port/health
```

**If RED (rollback)**:
```bash
# Immediate traffic switch
kubectl patch service auth-server \
  -p '{"spec":{"selector":{"version":"1"}}}'

# Verify rollback
curl http://auth-server:3100/health

# Incident post-mortem (after 15 min)
# - What failed?
# - Why wasn't it caught in testing?
# - How to prevent next time?
```

---

## Post-Cutover Validation

**After Each Service Cutover**:

```bash
# 1. Endpoint verification (15 min)
for i in {1..60}; do
  curl -s http://auth-server:3100/health
  sleep 15
done

# 2. Error log review (30 min)
kubectl logs deployment/auth-server --since=30m | grep -i error

# 3. Performance metrics (30 min)
kubectl exec -it pod/prometheus-0 -- \
  promtool query instant \
  'histogram_quantile(0.99, http_request_duration_seconds)'

# 4. Integration tests (30 min)
./tests/integration/test-auth-server-integration.sh

# 5. Sign-off
echo "Service auth-server validated at $(date)" >> /tmp/phase2-signoff.txt
```

---

## Success Metrics After Phase 2

```
8/8 Stateless Services Running: ✓
Zero Downtime Achieved:          ✓ (< 1s interruption)
Performance Baseline:            ✓ (p99 < 100ms)
All Metrics Flowing:             ✓ (100% coverage)
Team Confidence High:            ✓ (ready for Phase 3)
```

EOF

echo "✓ Load balancing configuration and procedures generated"
echo "  Config: ${CONFIG_FILE}"
echo "  Procedures: ${PROCEDURES_FILE}"
