# Phase 15: Advanced Networking & Service Mesh

## Overview

Phase 15 implements Istio service mesh for enterprise-grade traffic management, security, and observability across microservices. Combined with Phase 12's distributed tracing and Phase 13's security, this completes the full observability and security stack.

**Objectives:**
- ✅ Istio service mesh deployment and configuration
- ✅ Automatic mTLS encryption between services
- ✅ Advanced traffic management (routing, load balancing, circuit breaking)
- ✅ Canary deployments and A/B testing
- ✅ Service resilience (retries, timeouts, fault injection)
- ✅ Network policies and fine-grained access control
- ✅ Istio observability integration with Prometheus/Jaeger

---

## 1. Istio Installation & Configuration

### 1.1 Istio Setup

```bash
#!/bin/bash
# kubernetes/scripts/install-istio.sh

set -e

ISTIO_VERSION="1.19.0"

echo "=== Installing Istio $ISTIO_VERSION ==="

# Download Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-$ISTIO_VERSION

# Install Istio CRDs
kubectl apply -f manifests/charts/istio-operator/crds-post-1.8.yaml

# Create istio-system namespace
kubectl create namespace istio-system || true

# Install Istio using operator
kubectl apply -f manifests/operator/default.yaml

# Wait for operator to be ready
echo "Waiting for Istio operator to be ready..."
kubectl wait --for=condition=Ready pod -l name=istio-operator -n istio-operator --timeout=300s

# Create IstioOperator resource
kubectl apply << 'EOF'
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
  name: istio-default
spec:
  profile: production
  hub: docker.io/istio

  meshConfig:
    # Enable mTLS by default
    mtls:
      mode: STRICT
    
    # Configure access logs
    accessLogFile: /dev/stdout
    accessLogFormat: |
      [%START_TIME%] "%REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)% %PROTOCOL%"
      %RESPONSE_CODE% %RESPONSE_FLAGS% %BYTES_RECEIVED% %BYTES_SENT%
      "%DURATION%" "%RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)%" "%REQ(USER-AGENT)%"
      "%REQ(X-B3-TRACE-ID?:-)" "%REQ(X-B3-SPAN-ID?:-)" "%REQ(X-B3-PARENT-SPAN-ID?:-)"
    
    # Protocol detection and timeout settings
    protocolDetectionTimeout: 10ms
    
    # Load balancing settings
    loadBalancing:
      destinationRule:
        consistentHashLBPolicy: {}
    
    # Tracing configuration
    enableTracing: true
    defaultProviders:
      metrics:
      - prometheus
      tracing:
      - jaeger
  
  components:
    # Ingress gateway
    ingressGateways:
    - name: istio-ingressgateway
      enabled: true
      k8s:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 1000m
            memory: 1024Mi
        hpa:
          enabled: true
          minReplicas: 3
          maxReplicas: 10
          targetCPUUtilizationPercentage: 80
        service:
          type: LoadBalancer
          ports:
          - port: 15021
            targetPort: 15021
            name: status-port
          - port: 80
            targetPort: 8080
            name: http2
          - port: 443
            targetPort: 8443
            name: https
    
    # Egress gateway
    egressGateways:
    - name: istio-egressgateway
      enabled: true
      k8s:
        hpa:
          enabled: true
          minReplicas: 2
          maxReplicas: 5
    
    # Control plane
    pilot:
      k8s:
        resources:
          requests:
            cpu: 500m
            memory: 2048Mi
          limits:
            cpu: 2000m
            memory: 4096Mi
        hpa:
          enabled: true
          minReplicas: 3
          maxReplicas: 10
          targetCPUUtilizationPercentage: 80

  values:
    prometheus:
      enabled: true
    grafana:
      enabled: true

EOF

echo "✅ Istio installed successfully"

# Verify installation
kubectl rollout status deployment/istiod -n istio-system --timeout=300s
for gw in istio-ingressgateway istio-egressgateway; do
  kubectl rollout status deployment/$gw -n istio-system --timeout=300s || true
done

echo ""
echo "Istio installation verified"
```

### 1.2 Auto-Sidecar Injection

```yaml
# kubernetes/base/istio-sidecar-injection.yaml

apiVersion: v1
kind: Namespace
metadata:
  name: code-server
  labels:
    istio-injection: enabled  # Auto-inject Envoy sidecars

---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: code-server
spec:
  # Enforce mTLS for all workloads in namespace
  mtls:
    mode: STRICT

---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-from-namespace
  namespace: code-server
spec:
  rules:
  # Allow traffic from same namespace
  - from:
    - source:
        namespaces: ["code-server"]
    to:
    - operation:
        methods: ["GET", "POST"]
  
  # Allow health checks without mTLS
  - from:
    - source:
        principals: ["cluster.local/ns/kube-system/sa/kubelet"]
    to:
    - operation:
        ports: ["8080"]
```

---

## 2. VirtualServices & DestinationRules

### 2.1 Traffic Management Configuration

```yaml
# kubernetes/deployments/code-server/virtualservice.yaml

apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: code-server
  namespace: code-server
spec:
  hosts:
  - code-server
  - code-server.code-server.svc.cluster.local
  http:
  # Route to stable version
  - match:
    - headers:
        user-agent:
          regex: ".*Chrome.*"
    route:
    - destination:
        host: code-server
        port:
          number: 8080
        subset: v1
      weight: 90
    - destination:
        host: code-server
        port:
          number: 8080
        subset: v2
      weight: 10
    timeout: 10s
    retries:
      attempts: 3
      perTryTimeout: 2s
  
  # Canary route (2% traffic to new version)
  - match:
    - uri:
        prefix: /api/v2
    route:
    - destination:
        host: code-server
        port:
          number: 8080
        subset: v2
      weight: 100
    timeout: 10s
  
  # Default route
  - route:
    - destination:
        host: code-server
        port:
          number: 8080
        subset: v1
      weight: 100
    timeout: 10s
    retries:
      attempts: 3
      perTryTimeout: 2s

---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: code-server
  namespace: code-server
spec:
  host: code-server
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
    loadBalancer:
      simple: LEAST_REQUEST
  subsets:
  # Stable version
  - name: v1
    labels:
      version: v1
    trafficPolicy:
      connectionPool:
        http:
          maxRequestsPerConnection: 2
  
  # Canary version
  - name: v2
    labels:
      version: v2
    trafficPolicy:
      connectionPool:
        tcp:
          maxConnections: 50
        http:
          http1MaxPendingRequests: 50
```

---

## 3. Gateway & Ingress Configuration

### 3.1 Istio Gateway Setup

```yaml
# kubernetes/deployments/code-server/gateway.yaml

apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: code-server-gateway
  namespace: code-server
spec:
  selector:
    istio: ingressgateway
  servers:
  # HTTP
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "code-server.example.com"
    httpsRedirect: true
  
  # HTTPS with TLS
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: code-server-tls-secret
    hosts:
    - "code-server.example.com"

---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: code-server-vs
  namespace: code-server
spec:
  hosts:
  - "code-server.example.com"
  gateways:
  - code-server-gateway
  http:
  - route:
    - destination:
        host: code-server
        port:
          number: 8080
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s

---
# TLS Certificate Secret
apiVersion: v1
kind: Secret
metadata:
  name: code-server-tls-secret
  namespace: istio-system
type: kubernetes.io/tls
stringData:
  tls.crt: |
    -----BEGIN CERTIFICATE-----
    ...certificate content...
    -----END CERTIFICATE-----
  tls.key: |
    -----BEGIN PRIVATE KEY-----
    ...private key content...
    -----END PRIVATE KEY-----
```

---

## 4. Canary Deployments

### 4.1 Canary Rollout Strategy

```bash
#!/bin/bash
# kubernetes/scripts/canary-rollout.sh

set -e

SERVICE=${1:-code-server}
NEW_VERSION=${2}
TRAFFIC_WEIGHT_START=${3:-5}
TRAFFIC_WEIGHT_STEP=${4:-5}
INTERVAL=${5:-300}  # 5 minutes between steps

echo "=== Canary Deployment Procedure ==="
echo "Service: $SERVICE"
echo "New Version: $NEW_VERSION"
echo "Starting Traffic Weight: ${TRAFFIC_WEIGHT_START}%"

# Step 1: Deploy new version
echo ""
echo "Step 1: Deploying $NEW_VERSION..."
kubectl set image deployment/$SERVICE \
  $SERVICE=$SERVICE:$NEW_VERSION \
  -n code-server \
  --record

# Wait for rollout to be ready
kubectl rollout status deployment/$SERVICE -n code-server --timeout=600s

# Step 2: Gradually shift traffic
echo ""
echo "Step 2: Gradually shifting traffic..."

WEIGHT=$TRAFFIC_WEIGHT_START
while [ $WEIGHT -le 100 ]; do
  echo "  Current traffic weight: ${WEIGHT}%"
  
  # Update VirtualService
  kubectl patch vs code-server -n code-server --type merge -p \
    "{\"spec\":{\"http\":[{\"route\":[{\"destination\":{\"host\":\"code-server\",\"subset\":\"v1\"},\"weight\":$((100-WEIGHT))},{\"destination\":{\"host\":\"code-server\",\"subset\":\"v2\"},\"weight\":$WEIGHT}]}]}}"
  
  # Monitor metrics
  echo "    Monitoring error rate..."
  ERROR_RATE=$(kubectl top pods -n code-server | grep $NEW_VERSION | awk '{print $NF}')
  
  if (( $(echo "$ERROR_RATE > 5" | bc -l) )); then
    echo "    ❌ Error rate too high ($ERROR_RATE%), rolling back..."
    kubectl rollout undo deployment/$SERVICE -n code-server
    exit 1
  fi
  
  # Sleep before next step
  if [ $WEIGHT -lt 100 ]; then
    echo "    Waiting ${INTERVAL}s before next step..."
    sleep $INTERVAL
  fi
  
  WEIGHT=$((WEIGHT + TRAFFIC_WEIGHT_STEP))
done

echo ""
echo "✅ Canary deployment complete"
echo "All traffic now routed to $NEW_VERSION"
```

### 4.2 Automated Canary with Flagger

```yaml
# kubernetes/deployments/code-server/flagger-canary.yaml

apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: code-server
  namespace: code-server
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: code-server
  progressDeadlineSeconds: 300
  
  service:
    port: 8080
    targetPort: 8080
  
  analysis:
    interval: 1m
    threshold: 5
    maxWeight: 50
    stepWeight: 5
    metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99
      interval: 1m
    - name: request-duration
      thresholdRange:
        max: 500
      interval: 1m
    webhooks:
    - name: acceptance-test
      url: http://flagger-loadtester/
      metadata:
        type: smoke
        cmd: "curl -sd 'test' http://code-server-canary:8080/api/health"
        timeout: 5s
    - name: load-test
      url: http://flagger-loadtester/
      metadata:
        type: load
        cmd: "hey -z 1m -q 10 -c 2 http://code-server-canary:8080"
        timeout: 5s
```

---

## 5. Resilience Patterns

### 5.1 Circuit Breaker Configuration

```yaml
# kubernetes/deployments/code-server/resilience.yaml

apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: code-server-resilience
  namespace: code-server
spec:
  host: code-server
  trafficPolicy:
    # Connection pooling for resource efficiency
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
    
    # Circuit breaker: eject unhealthy instances
    outlierDetection:
      # HTTP 5xx errors
      consecutive5xxErrors: 5
      # Connection failures
      consecutiveGatewayErrors: 5
      # Check interval
      interval: 30s
      # Time to sleep after ejection
      baseEjectionTime: 30s
      # Max percentage of hosts to eject
      maxEjectionPercent: 50
      # Min request count before evaluation
      minRequestVolume: 10
      # Split external/requests
      splitExternalLocalOriginErrors: true
```

### 5.2 Fault Injection for Testing

```yaml
# kubernetes/deployments/code-server/fault-injection.yaml

apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: code-server-fault-test
  namespace: code-server
spec:
  hosts:
  - code-server-fault-test
  http:
  # Simulate 10% latency (500ms added)
  - fault:
      delay:
        percentage: 10
        fixedDelay: 500ms
    route:
    - destination:
        host: code-server
        port:
          number: 8080
  
  # Simulate 5% request failures (500 errors)
  - fault:
      abort:
        percentage: 5
        httpStatus: 500
    route:
    - destination:
        host: code-server
        port:
          number: 8080
```

---

## 6. Service-to-Service Communication

### 6.1 mTLS Enforcement

```yaml
# kubernetes/base/istio-mtls-enforcement.yaml

apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: code-server
spec:
  mtls:
    mode: STRICT  # Require mTLS for all traffic

---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: code-server-allow
  namespace: code-server
spec:
  # Allow traffic from agent-api service only
  rules:
  - from:
    - source:
        principals:
        - "cluster.local/ns/code-server/sa/agent-api"
    to:
    - operation:
        methods: ["GET", "POST"]
        ports: ["8080"]

---
# Certificate for service identity
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: code-server-tls
  namespace: code-server
spec:
  secretName: code-server-tls
  duration: 87600h  # 10 years
  renewBefore: 720h  # 30 days
  commonName: code-server.code-server.svc.cluster.local
  dnsNames:
  - code-server
  - code-server.code-server
  - code-server.code-server.svc
  - code-server.code-server.svc.cluster.local
  issuerRef:
    name: code-server-selfsigned
    kind: Issuer
```

---

## 7. Observability Integration

### 7.1 Metric Collection

```yaml
# kubernetes/base/istio-metrics.yaml

apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: custom-metrics
  namespace: code-server
spec:
  metrics:
  - providers:
    - name: prometheus
    disabled: false
    dimensions:
    - request_path
    - request_method
    - request_host
    - response_code
    - source_namespace
    - destination_namespace
    - destination_service
    - destination_service_name
    - destination_service_namespace
    - destination_service_port
    - destination_port
    - error_code
```

### 7.2 Prometheus Recording Rules for Istio

```yaml
# monitoring/istio-recording-rules.yaml

apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: istio-recording-rules
  namespace: monitoring
spec:
  groups:
  - name: istio.recording_rules
    interval: 30s
    rules:
    # Request rate
    - record: istio:request:rate5m
      expr: rate(istio_request_total[5m])
    
    # Error rate
    - record: istio:request_errors:rate5m
      expr: rate(istio_request_total{response_code=~"5.."}[5m])
    
    # Latency
    - record: istio:request_duration:p95
      expr: histogram_quantile(0.95, rate(istio_request_duration_milliseconds_bucket[5m]))
    
    # Service dependency health
    - record: istio:service_health
      expr: |
        (istio_request_total{response_code=~"2.."} or vector(0))
        /
        (istio_request_total or vector(0))
```

---

## 8. Network Policies

### 8.1 Fine-Grained Network Access

```yaml
# kubernetes/deployments/code-server/network-policies.yaml

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: code-server-ingress
  namespace: code-server
spec:
  podSelector:
    matchLabels:
      app: code-server
  policyTypes:
  - Ingress
  - Egress
  
  ingress:
  # Allow from agent-api
  - from:
    - namespaceSelector:
        matchLabels:
          name: code-server
    - podSelector:
        matchLabels:
          app: agent-api
    ports:
    - protocol: TCP
      port: 8080
  
  # Allow from Istio ingress gateway
  - from:
    - namespaceSelector:
        matchLabels:
          istio-injection: enabled
    - podSelector:
        matchLabels:
          istio: ingressgateway
    ports:
    - protocol: TCP
      port: 8080
  
  # Allow health checks
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 8080
      destinationPorts:
      - 8081  # Health check port
  
  egress:
  # DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  
  # Database
  - to:
    - podSelector:
        matchLabels:
          app: postgresql
    ports:
    - protocol: TCP
      port: 5432
  
  # Cache
  - to:
    - podSelector:
        matchLabels:
          app: redis
    ports:
    - protocol: TCP
      port: 6379
  
  # External HTTPS
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
```

---

## 9. Service Mesh Dashboard

```json
{
  "dashboard": {
    "title": "Istio Service Mesh Dashboard",
    "tags": ["istio", "networking"],
    "panels": [
      {
        "title": "Request Rate",
        "type": "timeseries",
        "targets": [
          {
            "expr": "sum(rate(istio_request_total[5m])) by (destination_service)"
          }
        ]
      },
      {
        "title": "Error Rate %",
        "type": "timeseries",
        "targets": [
          {
            "expr": "(sum(rate(istio_request_total{response_code=~'5..'}[5m])) / sum(rate(istio_request_total[5m]))) * 100 by (destination_service)"
          }
        ]
      },
      {
        "title": "P95 Latency",
        "type": "timeseries",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(istio_request_duration_milliseconds_bucket[5m])) by (destination_service)"
          }
        ]
      },
      {
        "title": "Service Dependencies",
        "type": "nodeGraph",
        "targets": [
          {
            "expr": "istio_request_total"
          }
        ]
      },
      {
        "title": "Circuit Breaker Status",
        "type": "table",
        "targets": [
          {
            "expr": "envoy_cluster_circuit_breakers_default_cx_open"
          }
        ]
      }
    ]
  }
}
```

---

## 10. Success Criteria

- ✅ Istio deployed and healthy
- ✅ All services have sidecar proxies injected automatically
- ✅ mTLS enforced between all services
- ✅ VirtualServices configured with retries/timeouts
- ✅ DestinationRules with circuit breakers active
- ✅ Canary deployments tested successfully
- ✅ Service dependency graph visible
- ✅ Network policies restricted to least-privilege access

---

## Next Steps

1. Install Istio in cluster
2. Enable sidecar injection
3. Deploy VirtualServices and DestinationRules
4. Configure Gateways for ingress
5. Test canary deployment with Flagger
6. Setup resilience testing
7. Create service mesh dashboard
8. Begin **Phase 16: Cost Optimization & Capacity Planning**

