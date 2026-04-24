# Istio Service Mesh Configuration

**Component**: Istio Control Plane & Sidecar Configuration  
**Date**: April 25, 2026  
**Version**: 1.0.0  
**Status**: Production-Ready  
**GitHub Issue**: #1767  

## Overview

This directory contains production-ready Istio service mesh configuration for code-server-enterprise, implementing:

- **Strict mTLS Enforcement**: Mutual TLS for all service-to-service communication
- **Advanced Traffic Management**: VirtualServices with canary/blue-green deployment support
- **Distributed Tracing**: Jaeger integration for observability and debugging
- **Ingress Gateway**: External traffic routing with TLS termination
- **Security Policies**: Zero-trust authorization with defense-in-depth

## Files

### Core Configuration Files

| File | Purpose | Description |
|------|---------|-------------|
| `namespace.yaml` | Namespace Setup | Creates istio-system and code-server-enterprise namespaces with proper labels |
| `peer-authentication.yaml` | mTLS Policy | Strict mode enforcement + authorization policies for zero-trust networking |
| `gateway.yaml` | Ingress Gateway | External traffic routing, TLS termination, CORS configuration |
| `destination-rules.yaml` | Traffic Policies | Load balancing, connection pooling, outlier detection per service |
| `telemetry.yaml` | Observability | Jaeger tracing, metrics collection, access logging configuration |
| `proxy-config.yaml` | Sidecar Config | Envoy proxy settings, ServiceEntry for external APIs, egress rules |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Ingress Gateway                        │
│                   (External Traffic Entry)                  │
│                    TLS: cert-manager                        │
└────────────────────────────┬────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   VirtualService│
                    │  (API, Frontend)│
                    └────────┬────────┘
                             │
     ┌───────────────────────┼───────────────────────┐
     │                       │                       │
┌────▼────────┐      ┌──────▼──────┐      ┌────────▼────┐
│    API Pod  │      │ Frontend Pod│      │  Governance │
│ (Stable 95%)│      │ (Stable 90%)│      │   Services  │
│  Sidecar    │      │  Sidecar    │      │  (Sidecars) │
└────┬────────┘      └──────┬──────┘      └────────┬────┘
     │                      │                      │
     └──────────────────────┼──────────────────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
          ┌───▼──────┐  ┌──▼────┐  ┌─────▼───┐
          │Prometheus│  │ Loki  │  │  Jaeger │
          │Metrics   │  │ Logs  │  │ Traces  │
          └──────────┘  └───────┘  └─────────┘
              │             │             │
              └─────────────┼─────────────┘
                            │
                    ┌───────▼────────┐
                    │  Observability │
                    │   Dashboard    │
                    │   (Grafana)    │
                    └────────────────┘

mTLS enforced: All internal service-to-service communication
              + Defense-in-depth authorization policies
```

## Prerequisites

- **Kubernetes**: 1.24+ (with RBAC enabled)
- **Istio**: 1.18.0+ (install via `istioctl` or Helm)
- **Jaeger**: Deployed in code-server-enterprise namespace
- **cert-manager**: For TLS certificate management
- **Helm**: 3.10+ (optional, for templating)

## Installation

### Step 1: Install Istio Control Plane

```bash
# Option A: Using istioctl (recommended)
istioctl install --set profile=production \
  --set meshConfig.enableAutoMtls=true \
  --set meshConfig.mtlsPolicy=STRICT \
  -y

# Option B: Using Helm
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
helm install istio-base istio/base --namespace istio-system --create-namespace
helm install istiod istio/istiod --namespace istio-system
```

### Step 2: Deploy Namespaces

```bash
# Create namespaces with Istio sidecar injection enabled
kubectl apply -f istio/namespace.yaml

# Verify sidecar injection label
kubectl get namespace -L istio-injection
```

### Step 3: Deploy Security Policies

```bash
# Deploy mTLS enforcement
kubectl apply -f istio/peer-authentication.yaml

# Verify PeerAuthentication resources
kubectl get peerauthentication -n code-server-enterprise -o wide
```

### Step 4: Deploy Gateway & VirtualServices

```bash
# Deploy ingress gateway
kubectl apply -f istio/gateway.yaml

# Verify Gateway and VirtualService resources
kubectl get gateway,virtualservice -n code-server-enterprise
```

### Step 5: Deploy Traffic Policies

```bash
# Deploy DestinationRules for load balancing
kubectl apply -f istio/destination-rules.yaml

# Verify DestinationRule resources
kubectl get destinationrule -n code-server-enterprise -o wide
```

### Step 6: Configure Telemetry & Tracing

```bash
# Deploy Jaeger integration
kubectl apply -f istio/telemetry.yaml

# Verify Telemetry resources
kubectl get telemetry -n code-server-enterprise
```

### Step 7: Deploy Proxy & Network Policies

```bash
# Deploy proxy configuration
kubectl apply -f istio/proxy-config.yaml

# Verify NetworkPolicy resources
kubectl get networkpolicy -n code-server-enterprise
```

## Deployment Patterns

### Canary Deployment (5% traffic to new version)

```bash
# VirtualService automatically weights:
# Stable (v1.0.0): 95%
# Canary (v1.1.0-rc1): 5%

# Scale canary up gradually by updating VirtualService weights
kubectl patch vs api-vs -n code-server-enterprise \
  --type merge -p '{
    "spec": {
      "http": [{
        "route": [
          {"destination": {"host": "api", "subset": "stable"}, "weight": 90},
          {"destination": {"host": "api", "subset": "canary"}, "weight": 10}
        ]
      }]
    }
  }'
```

### Blue-Green Deployment (instant switch)

```bash
# Update VirtualService to route to green (new version)
kubectl patch vs api-vs -n code-server-enterprise \
  --type merge -p '{
    "spec": {
      "http": [{
        "route": [{
          "destination": {"host": "api", "subset": "green"},
          "weight": 100
        }]
      }]
    }
  }'
```

### Traffic Splitting for A/B Testing

```bash
# Route 70% to stable, 30% to experimental
kubectl patch vs frontend-vs -n code-server-enterprise \
  --type merge -p '{
    "spec": {
      "http": [{
        "route": [
          {"destination": {"host": "frontend", "subset": "stable"}, "weight": 70},
          {"destination": {"host": "frontend", "subset": "experimental"}, "weight": 30}
        ]
      }]
    }
  }'
```

## Security

### mTLS Enforcement (Strict Mode)

- **PeerAuthentication**: STRICT mode requires valid client certificate
- **AuthorizationPolicy**: Default-deny with explicit allow rules
- **Defense-in-Depth**: Service principals validated by Kubernetes RBAC

```yaml
# Only services with identity "cluster.local/ns/code-server-enterprise/sa/api" 
# can access the API service
```

### Zero-Trust Networking

- **All internal traffic**: mTLS required
- **Ingress traffic**: TLS termination at gateway
- **Egress traffic**: Controlled via NetworkPolicy and ServiceEntry

### Certificate Management

- **Istio CA**: Automatically issues short-lived certificates (24h default)
- **cert-manager**: Manages gateway TLS certificates (Let's Encrypt)
- **Rotation**: Automatic, transparent to applications

## Observability

### Distributed Tracing

Jaeger integration provides end-to-end request tracing:

```bash
# Access Jaeger UI
kubectl port-forward -n code-server-enterprise svc/jaeger 16686:16686
# Navigate to http://localhost:16686
```

### Metrics Collection

Prometheus scrapes Istio metrics via `/stats/prometheus`:

```bash
# Query request rate from Prometheus
kubectl port-forward -n code-server-enterprise svc/prometheus 9090:9090
# http://localhost:9090
# Query: rate(istio_requests_total[1m])
```

### Access Logging

Envoy access logs are written to stdout:

```bash
# View logs for a pod
kubectl logs <pod-name> -n code-server-enterprise -c istio-proxy | grep HttpIn
```

## Verification

### 1. Check mTLS Status

```bash
# Verify STRICT mode is enforced
kubectl get peerauthentication -n code-server-enterprise
# Output should show mode: STRICT

# Check certificate validity
kubectl get secret -n code-server-enterprise | grep istio
```

### 2. Test Traffic Routing

```bash
# Port-forward to API service
kubectl port-forward -n code-server-enterprise svc/api 3100:3100

# Make test request
curl -v http://localhost:3100/health

# Check VirtualService routing
kubectl get vs api-vs -n code-server-enterprise -o yaml | grep -A 20 "http:"
```

### 3. Verify Tracing Integration

```bash
# Check Jaeger connectivity from pods
kubectl exec -it <api-pod> -n code-server-enterprise -c api -- \
  curl -v http://jaeger-collector:14268/api/traces

# Verify traces appear in Jaeger UI
# Look for service "api" with recent traces
```

### 4. Validate AuthorizationPolicy

```bash
# Test that unauthorized traffic is blocked
kubectl run test-client --image=curlimages/curl -it --rm \
  -n code-server-enterprise -- \
  curl -v http://api:3100/health

# Should fail with 403 Forbidden if auth policy is properly enforced
```

## Troubleshooting

### Issue: "503 Service Unavailable" or "Connection refused"

**Cause**: mTLS enforcement not working or sidecar not injected

```bash
# Check sidecar injection status
kubectl get pods -n code-server-enterprise -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# Should show "istio-proxy" container for each pod

# If missing, manually inject or label namespace
kubectl label namespace code-server-enterprise istio-injection=enabled --overwrite
kubectl rollout restart deployment -n code-server-enterprise
```

### Issue: Canary traffic not splitting as configured

**Cause**: DestinationRule subsets not matching labels

```bash
# Verify labels on pods
kubectl get pods -n code-server-enterprise --show-labels

# Check DestinationRule subsets match pod labels
kubectl get dr api-dr -n code-server-enterprise -o yaml | grep -A 5 "subsets:"

# Update pod labels if needed
kubectl label pods <pod-name> version=v1.1.0-rc1 -n code-server-enterprise
```

### Issue: High latency after enabling mTLS

**Cause**: mTLS handshake overhead or connection pooling misconfigured

```bash
# Check connection pool settings
kubectl get dr api-dr -n code-server-enterprise -o yaml | grep -A 10 "connectionPool:"

# Adjust maxConnections and http2MaxRequests if needed
# Monitor latency in Grafana during changes
```

## Performance Tuning

### Connection Pool Optimization

```yaml
# For high-throughput services (>10k req/s)
connectionPool:
  tcp:
    maxConnections: 2000
  http:
    http1MaxPendingRequests: 1000
    http2MaxRequests: 2000
    maxRequestsPerConnection: 10
```

### Load Balancing Strategies

```yaml
# Round Robin: Default, simple distribution
loadBalancer:
  simple: ROUND_ROBIN

# Least Request: More intelligent, better for variable latency
loadBalancer:
  simple: LEAST_REQUEST

# Consistent Hash: For stateful workloads
loadBalancer:
  consistentHash:
    httpHeaderName: "x-session-id"
    minimumRingSize: 256
```

### Outlier Detection Configuration

```yaml
# Balance between sensitivity and stability
outlierDetection:
  consecutive5xxErrors: 5      # Mark unhealthy after 5 consecutive errors
  interval: 30s                 # Check every 30 seconds
  baseEjectionTime: 30s         # Eject for 30 seconds initially
  maxEjectionPercent: 50        # Eject max 50% of pool
  minRequestVolume: 10          # Require 10 requests to trigger
```

## Roadmap & Future Enhancements

### Phase 1 ✅ (Current)
- [x] Core mTLS enforcement (STRICT mode)
- [x] Ingress gateway with TLS termination
- [x] VirtualServices for canary/blue-green deployments
- [x] Jaeger tracing integration
- [x] Authorization policies (zero-trust)

### Phase 2 (Q3 2026 - Planned)
- [ ] **Fault Injection Testing**: Circuit breakers, retry logic validation
- [ ] **Rate Limiting**: Global and per-service rate limits
- [ ] **Mutual TLS Certificate Rotation**: Enhanced automation
- [ ] **Multi-Cluster Mesh**: Cross-cluster service discovery
- [ ] **Ambient Mesh Mode**: Sidcar-less eBPF-based data plane

### Phase 3 (Q4 2026 - Planned)
- [ ] **VirtualService Routing**: Advanced routing rules (path, header, weight)
- [ ] **Gateway API**: Transition from networking.istio.io to Gateway API standard
- [ ] **Custom Resource Definitions**: Domain-specific configurations
- [ ] **Performance Optimization**: eBPF offloading for high-throughput paths

## Security Considerations

1. **Certificate Expiration**: Istio CA certs rotate automatically; monitor via alerts
2. **Namespace Isolation**: Each namespace gets isolated mTLS trust domain
3. **External Traffic**: TLS termination at ingress gateway only
4. **Service Principals**: Validated via Kubernetes service accounts

## Support & Maintenance

- **Issues**: Report via GitHub issue #1767
- **Documentation**: Update this README for changes
- **Upgrades**: Follow Istio upgrade guide before updating CRDs
- **Monitoring**: Set up alerts for PeerAuthentication and AuthorizationPolicy errors

---

**Status**: Production-Ready (Phase 1)  
**Last Updated**: April 25, 2026  
**Next Review**: May 25, 2026  
