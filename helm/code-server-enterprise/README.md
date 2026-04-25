# Code Server Enterprise Helm Chart

## Overview

Production-ready Helm chart for deploying code-server-enterprise microservices to Kubernetes clusters with advanced traffic management, autoscaling, and zero-trust security.

**Governance**: GOV-002 Enterprise Standards  
**Version**: 1.0.0  
**Status**: Phase 4 - Kubernetes Migration Ready  
**Immutability**: All configuration versioned in Git

## Features

### 🔐 Security & Zero-Trust
- Istio service mesh with mutual TLS (STRICT mode)
- Zero-trust NetworkPolicy configuration
- AuthorizationPolicy for service-to-service access control
- RBAC with principle of least privilege
- Pod security standards (baseline enforced)
- Non-root containers by default (uid:1002+)

### 🚀 Advanced Traffic Management (Istio)
- VirtualService for traffic routing and canary deployments
- DestinationRule with circuit breaker and outlier detection
- Gateway for ingress and TLS termination
- Load balancing policies (RoundRobin, ConsistentHash)
- Fault injection for chaos testing
- Retry logic and timeout enforcement

### 📈 Horizontal Pod Autoscaling
- CPU/Memory-based autoscaling (default 70%/80%)
- Custom metrics support (Prometheus integration)
- Per-service scaling configurations
- Aggressive scale-up (100% per 15s)
- Conservative scale-down (300s stabilization)
- Min 2 replicas, Max 8-20 replicas (service-dependent)

### 🔄 High Availability
- Multi-replica deployments with pod anti-affinity
- Pod Disruption Budgets (minAvailable: 1-2)
- Rolling update strategy (maxUnavailable: 0)
- Liveness and readiness probes (30s/10s intervals)
- Automatic pod restart on failure
- Leader election for stateful services

### 📊 Observability
- Istio traffic metrics (request rate, latency, errors)
- Prometheus metrics integration
- Jaeger distributed tracing
- Loki log aggregation
- Grafana dashboards (Istio, Kubernetes, Application)
- Structured JSON logging

### 🛡️ Resilience & Fault Tolerance
- Connection pooling and resource quotas
- Outlier detection and automatic ejection
- Circuit breaker patterns
- Graceful shutdown (preStop hooks)
- Resource limits and requests

## Architecture

### Service Mesh (Istio)
```
Client → Istio Gateway (TLS termination)
    ↓
    → Virtual Service (routing rules)
    ↓
    → Destination Rule (load balancing, circuit breaker)
    ↓
    → Pod (with Istio sidecar proxy)
    ↓
    → Backend Service
```

### Auto Scaling Flow
```
Metrics Collected
    ↓
Prometheus Scrapes (15s interval)
    ↓
HPA Evaluates (30s decision interval)
    ↓
Scale Decision (min/max replicas)
    ↓
Deployment Adjusted
    ↓
New Pods Scheduled
    ↓
Health Checks (readiness probe passing)
    ↓
Pod Joins Load Balancer Pool
```

## Quick Start

### Prerequisites
- Kubernetes 1.24+ (1.25+ recommended)
- Helm 3.10+
- Istio 1.18+ (installed in `istio-system` namespace)
- Prometheus Operator (for metrics-based HPA)
- cert-manager (for TLS certificates)

### Installation

```bash
# 1. Ensure Istio is installed
kubectl get namespace istio-system
kubectl get pods -n istio-system | grep istiod

# 2. Create namespace with Istio injection
kubectl create namespace code-server-enterprise
kubectl label namespace code-server-enterprise \
  istio-injection=enabled \
  governance/policy=GOV-002

# 3. Create secrets (database, OAuth, etc.)
kubectl create secret generic database-credentials \
  --from-literal=postgres-user=postgres \
  --from-literal=postgres-password=$(openssl rand -base64 24) \
  -n code-server-enterprise

# 4. Add chart repository
helm repo add code-server https://charts.example.com
helm repo update

# 5. Install chart with production values
helm install code-server-enterprise ./helm/code-server-enterprise \
  --namespace code-server-enterprise \
  --values values-production.yaml \
  --wait \
  --timeout 5m

# 6. Verify installation
kubectl get pods -n code-server-enterprise --watch
kubectl get svc -n code-server-enterprise
kubectl get vs -n code-server-enterprise  # VirtualServices (Istio)
kubectl get dr -n code-server-enterprise  # DestinationRules (Istio)
kubectl get hpa -n code-server-enterprise  # AutoScalers

# 7. Check Istio sidecars were injected
kubectl get pods -n code-server-enterprise -o jsonpath='{.items[0].spec.containers[*].name}'
# Should output: [api istio-proxy] or similar
```

## Configuration

### Istio Service Mesh

Enable/disable and configure Istio:

```yaml
istio:
  enabled: true
  namespace: "istio-system"
  mtls:
    mode: STRICT  # STRICT, PERMISSIVE, or DISABLE
  trafficPolicy:
    connectionPool:
      http:
        http1MaxPendingRequests: 100
        http2MaxRequests: 200
```

### Horizontal Pod Autoscaling

Configure autoscaling per service:

```yaml
autoscaling:
  enabled: true
  default:
    minReplicas: 2
    maxReplicas: 10
    targetCpuUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80
  # Per-service overrides
  services:
    api:
      minReplicas: 3
      maxReplicas: 20
      targetCpuUtilizationPercentage: 60
```

### Global Settings

```yaml
global:
  domain: "api.example.com"
  logLevel: "info"
  imageRegistry: "docker.io"
  resources:
    limits:
      cpu: "500m"
      memory: "512Mi"
    requests:
      cpu: "250m"
      memory: "256Mi"
```

### Service Customization

Each microservice can be configured independently:

```yaml
services:
  api:
    enabled: true
    replicas: 3
    port: 3100
    resources:
      limits:
        cpu: "1000m"
        memory: "1Gi"
      requests:
        cpu: "500m"
        memory: "512Mi"
  frontend:
    enabled: true
    replicas: 2
    port: 3000
```

### Pod Disruption Budgets

Ensure high availability during disruptions:

```yaml
podDisruptionBudgets:
  enabled: true
  default:
    minAvailable: 1
  services:
    api:
      minAvailable: 2  # More strict for critical API
```

### NetworkPolicy (Zero-Trust)

```yaml
networkPolicies:
  enabled: true
  serviceCommunication:
    api:
      ingressFrom:
      - frontend
      - orchestrator
      egressTo:
      - postgres
      - reputation-engine
```

## Monitoring & Observability

### View Metrics
```bash
# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000 (admin / prom-operator)

# View Istio dashboard
# Dashboard: "Istio Mesh" or "Istio Service"
```

### View Traces
```bash
# Access Jaeger
kubectl port-forward -n istio-system svc/jaeger 16686:16686
# Open http://localhost:16686
```

### View Logs
```bash
# View pod logs
kubectl logs -n code-server-enterprise pod/api-xyz

# Stream logs
kubectl logs -f -n code-server-enterprise pod/api-xyz

# View Istio sidecar logs
kubectl logs -n code-server-enterprise pod/api-xyz -c istio-proxy
```

### HPA Status
```bash
# Check HPA decisions
kubectl get hpa -n code-server-enterprise
kubectl describe hpa code-server-enterprise-api -n code-server-enterprise

# Watch scaling in real-time
kubectl get hpa -n code-server-enterprise --watch
```

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n code-server-enterprise
kubectl logs <pod-name> -n code-server-enterprise
```

### mTLS issues
```bash
# Check if mTLS is enforced
kubectl get peerauthentication -n code-server-enterprise

# Test mTLS connection
kubectl exec -it pod/api-xyz -n code-server-enterprise -- \
  openssl s_client -connect reputation-engine:5000
```

### HPA not scaling
```bash
# Check metrics availability
kubectl get hpa -n code-server-enterprise
# Look for "unknown" in TARGETS

# Verify metrics-server is installed
kubectl get deployment metrics-server -n kube-system

# Check custom metrics (if using)
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq .
```

### Istio traffic issues
```bash
# Check VirtualService
kubectl get vs -n code-server-enterprise -o yaml

# Check DestinationRule
kubectl get dr -n code-server-enterprise -o yaml

# Check AuthorizationPolicy
kubectl get authorizationpolicy -n code-server-enterprise

# Test connectivity
kubectl exec -it pod/api-xyz -- curl -v http://reputation-engine:5000/health
```

## Upgrade

```bash
# Update Helm chart
helm upgrade code-server-enterprise ./helm/code-server-enterprise \
  --namespace code-server-enterprise \
  --values values-production.yaml \
  --wait

# Rollback if needed
helm rollback code-server-enterprise 1 \
  --namespace code-server-enterprise
```

## Uninstall

```bash
# Delete Helm release (but keep data)
helm uninstall code-server-enterprise \
  --namespace code-server-enterprise

# Delete namespace (WARNING: deletes all resources)
kubectl delete namespace code-server-enterprise
```

### Secrets Management

Secrets should be managed externally via:
- AWS Secrets Manager
- HashiCorp Vault
- Kubernetes Secrets (with encryption at rest)

Example:
```bash
kubectl create secret generic code-server-enterprise-secrets \
  --from-literal=DATABASE_URL=$DATABASE_URL \
  --from-literal=REDIS_PASSWORD=$REDIS_PASSWORD \
  -n production
```

## Templates

### Standard Templates
- `deployment.yaml` - Microservice deployments with health checks
- `service.yaml` - Kubernetes Services (ClusterIP/LoadBalancer)
- `configmap.yaml` - Application configuration
- `rbac.yaml` - ServiceAccount, ClusterRole, ClusterRoleBinding
- `networkpolicy.yaml` - Zero-trust pod communication
- `ingress.yaml` - External API routing with TLS

### Helper Templates
- `_helpers.tpl` - Reusable template functions

## Deployment Patterns

### Development
```bash
helm install code-server-enterprise ./helm/code-server-enterprise \
  --set global.domain=api.dev.local \
  --set services.api.replicas=1
```

### Staging
```bash
helm install code-server-enterprise ./helm/code-server-enterprise \
  --values helm/values-staging.yaml
```

### Production
```bash
helm install code-server-enterprise ./helm/code-server-enterprise \
  --values helm/values-production.yaml \
  --set-string global.tlsEmail="admin@example.com"
```

## Verification

```bash
# Check pod status
kubectl get pods -n production

# View service endpoints
kubectl get svc -n production

# Check ingress
kubectl get ingress -n production

# Verify deployment
kubectl rollout status deployment/code-server-enterprise-api -n production

# Test health endpoints
curl https://api.example.com/health
```

## Upgrades

```bash
# Check release history
helm history code-server-enterprise -n production

# Upgrade to new chart version
helm upgrade code-server-enterprise ./helm/code-server-enterprise \
  -n production \
  --values custom-values.yaml

# Rollback if needed
helm rollback code-server-enterprise 1 -n production
```

## Uninstall

```bash
helm uninstall code-server-enterprise -n production
```

## Contributing

Chart updates must:
1. Follow GOV-002 governance standards
2. Include governance headers in all templates
3. Pass Helm validation: `helm lint`
4. Be version-controlled in Git
5. Include CHANGELOG entry
6. Pass security scanning

## Roadmap

- [ ] Horizontal Pod Autoscaler templates
- [ ] PersistentVolume templates for stateful services
- [ ] ServiceMonitor templates for Prometheus
- [ ] Istio VirtualService templates
- [ ] Multi-region deployment patterns
- [ ] Disaster recovery (backup/restore) procedures

## Support

For issues or questions:
- GitHub Issues: https://github.com/kushin77/code-server/issues
- Email: platform@example.com
