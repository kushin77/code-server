# Kubernetes Infrastructure - Quick Reference

**Phase 8 Complete**: Production-grade Kubernetes orchestration with comprehensive enterprise features.

## Quick Deploy

### Development
```bash
./kubernetes/scripts/deploy.sh dev
```

### Staging
```bash
./kubernetes/scripts/deploy.sh staging
```

### Production
```bash
./kubernetes/scripts/pre-deployment-check.sh production
./kubernetes/scripts/deploy.sh production
```

## Monitor Deployment

### Health Check (one-time)
```bash
./kubernetes/scripts/health-check.sh -n code-server
```

### Health Check (continuous watch)
```bash
./kubernetes/scripts/health-check.sh -n code-server --watch --interval 10
```

## Auto-Scaling Management

### View HPA Status
```bash
./kubernetes/scripts/scale-cluster.sh status
```

### Enable HPA for a Service
```bash
./kubernetes/scripts/scale-cluster.sh enable code-server
./kubernetes/scripts/scale-cluster.sh enable agent-api
./kubernetes/scripts/scale-cluster.sh enable embeddings
```

### Manual Scaling (disables HPA temporarily)
```bash
./kubernetes/scripts/scale-cluster.sh scale code-server 5
```

### Configure All HPAs
```bash
./kubernetes/scripts/scale-cluster.sh configure
```

## Kubectl Quick Commands

### Pod Management
```bash
# List pods
kubectl get pods -n code-server

# Watch pod status
kubectl get pods -n code-server --watch

# Get pod details
kubectl describe pod <pod-name> -n code-server

# View pod logs
kubectl logs -n code-server <pod-name>
kubectl logs -f -n code-server <pod-name>  # Follow

# Execute in pod
kubectl exec -it -n code-server <pod-name> -- /bin/bash
```

### Service Access
```bash
# Port forward to service
kubectl port-forward -n code-server svc/code-server 8080:8443

# Test service connectivity
kubectl exec -n code-server deployment/code-server -- \
  curl http://agent-api:3000/health
```

### Resource Usage
```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -n code-server

# Watch resource usage
kubectl top pods -n code-server --watch
```

### Deployments
```bash
# Rollout status
kubectl rollout status deployment/code-server -n code-server

# Rollout history
kubectl rollout history deployment/code-server -n code-server

# Rollback
kubectl rollout undo deployment/code-server -n code-server
```

## Files Structure

```
kubernetes/
├── base/                                    # Common resources
│   ├── kustomization.yaml                  # Base orchestration
│   ├── namespace.yaml                      # code-server namespace
│   ├── configmaps.yaml                     # Application config (NEW)
│   ├── hpa.yaml                            # Auto-scaling (NEW)
│   ├── pdb.yaml                            # Disruption budgets (NEW)
│   ├── monitoring.yaml                     # Prometheus rules (NEW)
│   ├── network-policies.yaml               # Security policies (NEW)
│   ├── code-server-*.yaml                  # Code Server deployment
│   ├── agent-api-*.yaml                    # Agent API deployment
│   ├── embeddings-*.yaml                   # Embeddings deployment
│   ├── redis-*.yaml                        # Redis StatefulSet
│   ├── prometheus-*.yaml                   # Prometheus deployment
│   └── grafana-*.yaml                      # Grafana deployment
│
├── overlays/                                # Environment-specific
│   ├── dev/
│   │   └── kustomization.yaml              # Dev patches
│   ├── staging/
│   │   └── kustomization.yaml              # Staging patches
│   └── production/
│       └── kustomization.yaml              # Production patches (HA)
│
├── scripts/                                 # Helper scripts (NEW)
│   ├── deploy.sh                           # Deployment tool
│   ├── pre-deployment-check.sh             # Validation
│   ├── health-check.sh                     # Monitoring
│   └── scale-cluster.sh                    # HPA management
│
└── README.md                               # This file
```

## Integration Points

### Phase 5.1: Monitoring & Observability
✅ Prometheus deployment with scrape configs
✅ Grafana dashboards pre-configured
✅ ServiceMonitor CRDs for Prometheus Operator
✅ PrometheusRule CRDs for alerting

### Phase 5.2: SLO Tracking
✅ Prometheus metrics exposed by services
✅ Recording rules in ConfigMaps
✅ Alert configuration for burn rate

### Phase 5.3: Performance Optimization
✅ HPA configured with CPU/memory thresholds
✅ Resource requests/limits aligned to baselines
✅ Pod auto-scaling 3-10 replicas (adjustable per service)

### Phase 6: Production Deployment
✅ Blue-green deployments via rolling updates
✅ Readiness/liveness probes for health
✅ Pod Disruption Budgets (PDB) for safe eviction
✅ Automatic rollback on failures

### Phase 7: CI/CD Automation
✅ Kustomize manifests validated in build.yml
✅ Docker images pushed to GHCR
✅ kubectl deployment in deploy-production.yml

### Phase 7.1: GSM Integration
✅ Secrets not stored in manifests
✅ ConfigMaps for public configuration
✅ Secrets injected via environment from GSM

## New Phase 8 Features

### Auto-Scaling (HPA)
```yaml
# Configured for all services
code-server:      3-10 replicas, CPU 70% / Memory 80%
agent-api:        3-10 replicas, CPU 70% / Memory 80%
embeddings:       3-6  replicas, CPU 65% / Memory 75%
```

**Enable with**:
```bash
./kubernetes/scripts/scale-cluster.sh configure
```

### Pod Disruption Budgets
```yaml
# Ensures high availability during node maintenance
code-server:  minAvailable: 1
agent-api:    minAvailable: 2
embeddings:   minAvailable: 1
redis:        minAvailable: 1
```

### Network Policies
```yaml
# Default deny all traffic, then explicitly allow:
- code-server → external (metrics)
- agent-api → embeddings, redis
- embeddings → redis, HF models
- redis → peer replication
```

### Configuration Management
```yaml
# 5 ConfigMaps covering:
code-server-config:  IDE settings, APIs, feature flags
agent-api-config:    FastAPI, LangGraph, Ollama, DB
embeddings-config:   Model config, processing, metrics
prometheus-config:   Scrape jobs, global settings
grafana-datasources: Data source configuration
redis-config:        Memory, persistence, replication
```

### Monitoring Integration
```yaml
# 3 ServiceMonitor CRDs (optional, requires Prometheus Operator)
- code-server-monitor
- agent-api-monitor
- embeddings-monitor

# 3 PrometheusRule CRDs for alerting
- CodeServerDown, CodeServerHighCPU, CodeServerHighMemory
- AgentAPIDown, AgentAPIHighLatency
- EmbeddingsDown, EmbeddingsHighMemory
```

## Troubleshooting

### Pod Won't Start
```bash
# Check pod status
kubectl describe pod <pod-name> -n code-server

# View logs from previous container (if crashed)
kubectl logs <pod-name> -n code-server --previous

# Common causes:
# - ImagePullBackOff: Image not in registry
# - CrashLoopBackOff: Container crashes at startup
# - Pending: No node capacity or resources
```

### Service Not Accessible
```bash
# Check service endpoints
kubectl get endpoints -n code-server
kubectl describe service code-server -n code-server

# Test DNS resolution
kubectl exec -n code-server <pod> -- nslookup code-server

# Test connectivity
kubectl exec -n code-server <pod> -- curl http://code-server:8443/health
```

### HPA Not Scaling
```bash
# Verify Metrics Server is running
kubectl get deployment metrics-server -n kube-system

# Check HPA status
kubectl describe hpa code-server-hpa -n code-server

# View metrics
kubectl top pods -n code-server
```

### Storage Issues
```bash
# Check PersistentVolumes
kubectl get pv
kubectl get pvc -n code-server

# Describe PVC
kubectl describe pvc -n code-server <pvc-name>
```

## Advanced Operations

### Update Image (Rolling Deployment)
```bash
# Update deployment image
kubectl set image deployment/code-server \
  code-server=ghcr.io/kushin77/code-server:v2.0.0 \
  -n code-server

# Watch rollout
kubectl rollout status deployment/code-server -n code-server
```

### Scale Manually (Override HPA)
```bash
# Disable HPA temporarily
kubectl patch deployment code-server -n code-server \
  -p '{"spec":{"replicas":5}}'

# Re-enable HPA (HPA will manage replicas)
kubectl delete hpa code-server-hpa -n code-server
./kubernetes/scripts/scale-cluster.sh enable code-server
```

### Upgrade with Blue-Green
```bash
# Create new deployment (green)
kubectl apply -k kubernetes/overlays/production --dry-run=client -o yaml > green.yaml
# Edit green.yaml to use new image

# Deploy green
kubectl apply -f green.yaml

# Test green thoroughly
# If good: switch service selector to green
# If bad: keep blue running for rollback
```

### Check Resource Limits
```bash
# Actual resource requests
kubectl get pods -n code-server -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources}{"\n"}{end}'

# Node capacity vs. allocated
kubectl describe nodes
```

## Performance Optimization

### Optimize Resource Requests
```bash
# Monitor actual usage first
kubectl top pods -n code-server --containers

# Adjust requests in overlays if needed
# Dev: conservative (500m CPU, 512Mi mem)
# Staging: medium (1 CPU, 1Gi mem)
# Production: optimized based on telemetry
```

### Cache Configuration
```bash
# Redis memory is set to 2GB (configurable)
# Adjust in configmaps.yaml: REDIS_CACHE_TTL
# Default: 3600s (1 hour)
```

### Database Connection Pooling
```bash
# Agent API: 20 connections
# Embeddings: 8 workers
# Adjust in agent-api-config ConfigMap
```

## Security Hardening

### RBAC Configuration
```bash
# Create service account for CI/CD
kubectl create serviceaccount github-actions -n code-server

# Create role with permissions
kubectl create role github-actions \
  --verb=get,list,watch,create,update,patch \
  --resource=deployments,statefulsets,pods \
  -n code-server

# Bind role
kubectl create rolebinding github-actions \
  --role=github-actions \
  --serviceaccount=code-server:github-actions \
  -n code-server

# Get token for CI/CD
kubectl describe secret <github-actions-token> -n code-server
```

### Network Security
```bash
# Default deny all traffic
# NetworkPolicies files in base/ implement:
# - Pod isolation within namespace
# - Explicit allow rules per service
# - DNS egress for external API calls
# - No pod-to-pod communication without policy
```

### Pod Security
```yaml
# SecurityContext in deployments:
runAsNonRoot: true
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities.drop: [ALL]
```

## Compliance & Auditing

### Kubernetes API Audit Logging
```bash
# Enable if supported by cluster
# Check with cluster administrator
```

### Monitoring Compliance
```bash
# SLO error budgets from Phase 5.2
# Prometheus metrics aligned to Phase 5
# Monthly reports available
```

## Documentation References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kustomize Documentation](https://kustomize.io/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Phase 5.1: Monitoring](../../docs/MONITORING.md)
- [Phase 5.3: Performance](../../docs/PERFORMANCE_OPTIMIZATION.md)
- [Phase 7: CI/CD](../../.github/CI_CD_AUTOMATION.md)
- [Phase 7.1: GSM](../../.github/GSM_INTEGRATION.md)
- [Full Deployment Guide](./KUBERNETES_DEPLOYMENT.md)

## Environment-Specific Features

### Development
```bash
# Small resource footprint
replicas: 1 per service
CPU: 500m, Memory: 512Mi (code-server)
Verbose logging
Local image pulls
```

### Staging
```bash
# Medium resource footprint
replicas: 2 per service
CPU: 1000m, Memory: 1Gi
Structured logging
Pre-pulled images
```

### Production
```bash
# High availability
replicas: 3-10 (HPA managed)
CPU: 2-4, Memory: 2-8Gi
JSON logging for aggregation
Image update strategy: Always
Pod affinity rules
Network policies enforced
```

## Support

For issues or questions:
1. Check [Troubleshooting](#troubleshooting) section
2. Review logs: `kubectl logs -n code-server <pod>`
3. Describe pod: `kubectl describe pod -n code-server <pod>`
4. Check Prometheus: `kubectl port-forward -n code-server svc/prometheus 9090:9090`
5. Check Grafana: `kubectl port-forward -n code-server svc/grafana 3000:3000`

---

**Phase 8 Status**: ✅ Complete  
**Last Updated**: April 13, 2026  
**Maintained By**: kushin77/code-server team
