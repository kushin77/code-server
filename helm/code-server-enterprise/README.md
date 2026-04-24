# Code Server Enterprise Helm Chart

## Overview

Production-ready Helm chart for deploying code-server-enterprise microservices to Kubernetes clusters.

**Governance**: GOV-002 Enterprise Standards  
**Version**: 1.0.0  
**Immutability**: All configuration versioned in Git

## Features

### Security
- Zero-trust NetworkPolicy configuration
- RBAC with principle of least privilege
- Pod security standards (baseline)
- TLS termination via cert-manager
- Non-root containers by default

### Resilience
- Multi-replica deployments with pod anti-affinity
- Rolling update strategy
- Liveness and readiness probes
- Resource limits and requests
- Health check integration

### Observability
- Prometheus metrics integration
- Loki log aggregation
- Grafana dashboard support
- Structured JSON logging
- Service tracing (Jaeger)

### Scalability
- Horizontal Pod Autoscaling support
- ConfigMap-driven configuration
- Separation of secrets (external management)
- Service discovery via DNS
- LoadBalancer for API gateway

## Quick Start

### Prerequisites
- Kubernetes 1.24+
- Helm 3.10+
- cert-manager (for TLS)
- nginx-ingress-controller

### Installation

```bash
# Add chart repository (if using Helm Hub)
helm repo add code-server https://charts.example.com
helm repo update

# Install with default values
helm install code-server-enterprise ./helm/code-server-enterprise \
  --namespace production \
  --create-namespace

# Install with custom values
helm install code-server-enterprise ./helm/code-server-enterprise \
  --namespace production \
  --values custom-values.yaml

# Verify installation
helm list -n production
kubectl get pods -n production
```

## Configuration

### Global Settings

```yaml
global:
  domain: "api.example.com"
  logLevel: "info"
  imageRegistry: "docker.io"
```

### Service Customization

Each microservice can be configured independently:

```yaml
services:
  api:
    enabled: true
    replicas: 3
    resources:
      limits:
        cpu: "1000m"
        memory: "1Gi"
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
