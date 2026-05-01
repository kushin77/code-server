# Phase 4.1: Cluster Provisioning & Infrastructure Setup - IMPLEMENTATION GUIDE

**Status**: Ready for Production Deployment
**Created**: April 2026
**Phase**: 4.1 - Infrastructure Setup (Week 1)

## Overview

This guide provides ready-to-use scripts for provisioning managed Kubernetes clusters across AWS, GCP, and Azure with Istio service mesh and observability stack.

## Quick Start

### Step 1: Choose Your Cloud Provider

**AWS EKS** (Recommended)
```bash
./scripts/k8s/provision-eks-cluster.sh \
  --name code-server-enterprise-prod \
  --region us-east-1 \
  --nodes 3 \
  --instance-type t3.large
```

**Google Cloud GKE**
```bash
./scripts/k8s/provision-gke-cluster.sh \
  my-project-id \
  code-server-enterprise-prod \
  us-central1 \
  3 \
  n1-standard-2
```

**Azure AKS**
```bash
./scripts/k8s/provision-aks-cluster.sh \
  code-server-rg \
  code-server-enterprise-prod \
  eastus \
  3 \
  Standard_D2s_v3
```

For local validation without Azure or Kubernetes tooling, use:
```bash
./scripts/k8s/provision-aks-cluster.sh --dry-run
```

### Step 2: Create Application Namespace

```bash
# Create namespace
kubectl create namespace code-server-enterprise
kubectl label namespace code-server-enterprise \
  istio-injection=enabled \
  governance/policy=GOV-002
```

### Step 3: Deploy Helm Chart

```bash
# Deploy all 20+ services
helm install code-server-enterprise ./helm/code-server-enterprise \
  --namespace code-server-enterprise \
  --values helm/code-server-enterprise/values.yaml \
  --wait \
  --timeout 5m
```

### Step 4: Validate Deployment

```bash
# Run comprehensive validation
./scripts/k8s/validate-deployment.sh code-server-enterprise

# Expected output: ✓ PASSED with 0 Failed checks
```

## What Each Script Does

### provision-eks-cluster.sh
- Creates 3-node EKS cluster (t3.large instances)
- Installs Istio service mesh (production profile)
- Deploys Prometheus, Grafana, Jaeger for observability
- Enables sidecar injection on default namespace
- Tags resources with GOV-002 governance labels

### provision-gke-cluster.sh
- Creates 3-node GKE cluster (n1-standard-2 machines)
- Enables Google Cloud native features (workload identity, network policies)
- Installs Istio and monitoring stack
- Integrates with Google Cloud Console

### provision-aks-cluster.sh
- Creates 3-node AKS cluster (Standard_D2s_v3 VMs)
- Enables auto-scaling (min 3, max 9 nodes)
- Installs Istio production profile and kube-prometheus-stack monitoring
- Uses managed identity for authentication
- Supports `--dry-run` for local validation without `az`, `kubectl`, or `helm`

### validate-deployment.sh
- Verifies all pods running and ready
- Checks Istio resources (VirtualServices, DestinationRules)
- Validates HPA configuration
- Confirms mTLS enforcement
- Tests service connectivity

## Monitoring Access

### Grafana Dashboards
```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# http://localhost:3000
# Login: admin / <password-from-script>

# Available dashboards:
# - Kubernetes Cluster Health
# - Istio Mesh Traffic
# - Application Metrics
# - Resource Usage
```

### Jaeger Distributed Tracing
```bash
kubectl port-forward -n monitoring svc/jaeger 16686:16686
# http://localhost:16686

# Features:
# - Service dependency mapping
# - Request tracing across services
# - Latency analysis
# - Error tracking
```

### Prometheus Metrics
```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# http://localhost:9090

# Query examples:
# up{namespace="code-server-enterprise"}
# rate(request_total[5m])
# histogram_quantile(0.99, request_duration_seconds)
```

## Helm Deployment Details

### Services Deployed (20+)
```
✓ API Gateway (3100)
✓ Frontend (3000)
✓ PostgreSQL (5432)
✓ Redis (6379)
✓ Paperclip Control Plane (8010)
✓ Reputation Engine (8002)
✓ Execution Scheduler (8080)
✓ Agent Runtime (9001-9004)
✓ Activity Feed (8020)
✓ Knowledge Graph (8025)
✓ ... and 10+ additional microservices
```

### Autoscaling Configuration
```
API Service:
  - Min replicas: 3
  - Max replicas: 20
  - CPU target: 60%
  - Memory target: 80%

Frontend:
  - Min replicas: 2
  - Max replicas: 15
  - CPU target: 75%

Other Services:
  - Min replicas: 1-2
  - Max replicas: 8-10
  - CPU target: 70% (default)
```

### Traffic Management (Istio)
```
✓ mTLS enforcement (STRICT mode)
✓ Load balancing (RoundRobin)
✓ Circuit breaker (outlier detection)
✓ Retry logic (3 attempts, 10s timeout)
✓ Connection pooling (100 pending, 200 max concurrent)
✓ Canary deployment support (weighted traffic routing)
```

### Security
```
✓ NetworkPolicy (zero-trust)
✓ Pod Security Standards (baseline)
✓ RBAC with least privilege
✓ Non-root containers (uid:1002+)
✓ Resource quotas per namespace
✓ Persistent volume encryption
```

## Verification Checklist

After provisioning, verify:

```bash
# 1. Cluster access
kubectl cluster-info
kubectl get nodes

# 2. Istio installed
kubectl get pods -n istio-system | grep istiod

# 3. Monitoring stack
kubectl get pods -n monitoring

# 4. Services deployed
kubectl get pods -n code-server-enterprise
kubectl get svc -n code-server-enterprise

# 5. HPA configured
kubectl get hpa -n code-server-enterprise

# 6. Full validation
./scripts/k8s/validate-deployment.sh code-server-enterprise
```

## Next Steps (Phase 4.2 - Week 2)

### 1. Setup External Access
```bash
# Configure ingress for external traffic
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-gateway
  namespace: code-server-enterprise
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 3100
EOF
```

### 2. Configure Load Balancer
```bash
# Get external IP
kubectl get svc -n code-server-enterprise | grep LoadBalancer

# Update DNS to point to external IP
aws route53 change-resource-record-sets --hosted-zone-id Z... \
  --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":...}]}'
```

### 3. Setup Observability Dashboards
- Create Grafana dashboards for business metrics
- Configure alert rules for error rates and latency
- Setup Slack/PagerDuty notifications

### 4. Test Traffic Management
- Generate load to trigger HPA scaling
- Verify canary deployment capabilities
- Test failure scenarios (pod crashes, network issues)

## Troubleshooting

### Cluster creation fails
```bash
# Check AWS/GCP/Azure credentials
aws sts get-caller-identity
gcloud auth list
az account show

# Check quotas and limits in your cloud account
```

### Pods pending/not starting
```bash
kubectl describe pod <pod-name> -n code-server-enterprise
kubectl logs <pod-name> -n code-server-enterprise

# Common issues:
# - Resource limits exceeded
# - Persistent volumes not available
# - Container image pull errors
```

### mTLS connection failures
```bash
# Verify PeerAuthentication
kubectl get peerauthentication -n code-server-enterprise -o yaml

# Test mTLS manually
kubectl exec -it pod/api-xyz -n code-server-enterprise -- \
  openssl s_client -connect service:port
```

### HPA not scaling
```bash
# Check metrics availability
kubectl describe hpa api -n code-server-enterprise

# Install metrics-server if missing
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Production Readiness Checklist

Before migrating production traffic:

- [ ] All services deployed and healthy
- [ ] Istio mTLS enforced (STRICT mode)
- [ ] HPA functional (tested with load)
- [ ] Monitoring dashboards active
- [ ] Alerting rules configured
- [ ] Backup and disaster recovery procedures documented
- [ ] Team trained on operational procedures
- [ ] Runbooks created and tested
- [ ] Load testing passed (sustained baseline + 2x spike)
- [ ] Failover procedures validated

## Cost Optimization

### Resource Sizing
- EKS/GKE/AKS: 3 nodes minimum for production HA
- Instance types: General-purpose (t3.large, n1-standard-2, D2s_v3)
- Storage: 50GB Prometheus, 30GB Jaeger, 10GB Loki
- Network: Ingress NLB/ALB ($0.006/hr + data processing)

### Cost Estimates (Monthly)
```
3x t3.large (EKS):        ~$180
EKS cluster fee:          ~$73
Networking/Load Balancer: ~$30-50
Persistent storage:       ~$20-30
Monitoring tools:         ~$0 (free tier)
---
Total: ~$300-330/month
```

### Ways to Reduce Costs
- Use spot instances for non-critical services (save 70%)
- Reduce replica counts during off-peak hours
- Use provisioned capacity for predictable workloads
- Implement pod resource optimization

## Document References

- **PHASE-4-KUBERNETES-MIGRATION-PLAN.md**: Comprehensive migration strategy
- **TRAFFIC-MIGRATION-STRATEGY.md**: Traffic cutover procedures
- **helm/code-server-enterprise/README.md**: Helm chart documentation
- **docs/ARCHITECTURE.md**: System architecture overview

---

**Status**: Production Ready
**Governance**: GOV-002 Enterprise Standards
**Last Updated**: April 2026
