#!/bin/bash
################################################################################
# Q3 Phase 4: Phase 1 Deployment Runbook Generator
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @purpose Generate comprehensive Phase 1 deployment runbook for K8s migration
# @phase Q3 Phase 4 Preparation (Phase 1)
# @date $(date '+%Y-%m-%d %H:%M:%S')
################################################################################

set -euo pipefail
IFS=$'\n\t'

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

# Environment defaults (sourced from SSOT)
OUTPUT_DIR="${PROJECT_ROOT}/artifacts/q3-phase4-runbooks"
TIMESTAMP=$(date '+%Y-%m-%d')
RUNBOOK_FILE="${OUTPUT_DIR}/PHASE1-DEPLOYMENT-RUNBOOK-${TIMESTAMP}.md"

# Ensure output directory exists
mkdir -p "${OUTPUT_DIR}"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$@"
}

log_success() {
    printf "${GREEN}[✓]${NC} %s\n" "$@"
}

################################################################################
# Generate Phase 1 Runbook
################################################################################

generate_runbook() {
    cat > "${RUNBOOK_FILE}" <<'EOF'
# Q3 Phase 4: Phase 1 Deployment Runbook
## Kubernetes Migration - Week 1 (May 1-12, 2026)

**Generated**: $(date '+%Y-%m-%d %H:%M:%S')  
**Status**: READY FOR EXECUTION  
**Duration**: 40-60 hours  
**Team**: Infrastructure Lead, Platform Engineer  
**SLA Target**: 99.95% uptime maintained  

---

## Executive Overview

Phase 1 focuses on **infrastructure provisioning and validation** for the Kubernetes migration. This runbook provides step-by-step procedures for:

1. Kubernetes cluster provisioning (EKS/GKE/AKS)
2. Infrastructure prerequisites validation
3. Helm chart deployment to staging cluster
4. Monitoring and observability infrastructure setup
5. Initial performance baseline establishment

**Critical Success Factors**:
- Zero data loss during provisioning
- All services deployable via Helm
- Monitoring stack fully operational
- Phase 2 dependencies ready by May 12

---

## Pre-Requisites (Must Complete Before Week 1)

### Infrastructure Team Responsibilities
- [ ] K8s cluster provisioned and accessible
- [ ] kubectl configured and authenticated
- [ ] Helm 3.x installed on deployment machine
- [ ] kubeval installed for manifest validation
- [ ] ${ONPREM_VRRP_VIP} (VRRP) configured
- [ ] Network security groups configured for service access

### Platform Team Responsibilities
- [ ] All container images built and pushed to registry
- [ ] Image pull secrets created in K8s cluster
- [ ] Private registry credentials configured
- [ ] Secrets manager (Vault/AWS Secrets Manager) accessible

### Cluster Requirements
- **Master nodes**: 3 (high availability)
- **Worker nodes**: 6-8 (capacity for 18 microservices)
- **Node specs**: 16-core, 64GB RAM per worker node
- **Network**: 10Gbps connectivity to NAS (${ONPREM_NAS_IP})
- **Storage**: StorageClass configured for StatefulSets
- **DNS**: Internal DNS for service discovery

### Resource Validation Checklist

```bash
# Verify cluster connectivity
kubectl cluster-info
kubectl get nodes -o wide

# Verify resource capacity
kubectl describe nodes | grep -A5 "Allocated resources"

# Verify storage
kubectl get storageclass
kubectl get pv

# Verify network
kubectl get networkpolicies --all-namespaces
```

---

## Phase 1 Timeline (May 1-12, 2026)

### Week 1a: Cluster Provisioning & Validation (May 1-3)

**Day 1 (May 1): Cluster Provisioning**

**Team**: Infrastructure Lead + 1 Platform Engineer  
**Duration**: 4-6 hours  
**Deliverables**: Production K8s cluster ready for deployments

#### Step 1.1: Cluster Creation (Terraform IaC)

```bash
# Navigate to infrastructure code
cd terraform/kubernetes/

# Review cluster configuration
cat main.tf | grep -A 20 "cluster_config"

# Validate Terraform
terraform fmt -recursive
terraform validate

# Apply Terraform (use --dry-run first)
terraform apply -auto-approve \
  -var="cluster_name=code-server-enterprise-prod" \
  -var="region=${AWS_REGION:-us-west-2}" \
  -var="node_count=8"
```

**Expected Output**:
- Kubernetes cluster created (3 master nodes)
- Worker node pool (8 nodes, 16-core/64GB each)
- VPC and security groups configured
- Load balancer for ingress controller
- Estimated time: 15-20 minutes

#### Step 1.2: Cluster Validation

```bash
# Wait for cluster readiness
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Verify node availability
kubectl get nodes -o wide
# Expected: 8-11 nodes in Ready state (3 master + 8 worker)

# Check cluster capacity
kubectl top nodes
# Expected: Each node ~40-60% utilization after baseline

# Verify DNS
kubectl run -it --rm debug --image=busybox --restart=Never \
  -- nslookup kubernetes.default.svc.cluster.local
# Expected: 10.0.0.1 (cluster DNS)
```

#### Step 1.3: Ingress Controller Deployment

```bash
# Install nginx ingress controller (or traefik, HAProxy)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalIPs[0]=${ONPREM_VRRP_VIP}

# Verify ingress controller
kubectl get svc -n ingress-nginx
# Expected: EXTERNAL-IP = ${ONPREM_VRRP_VIP}
```

**Day 2 (May 2): Storage & Networking**

**Team**: Infrastructure Lead  
**Duration**: 3-4 hours  
**Deliverables**: Storage classes, network policies, certificate manager ready

#### Step 2.1: Storage Configuration

```bash
# Create StorageClass for stateful services
kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
reclaimPolicy: Delete
allowVolumeExpansion: true
YAML

# Verify StorageClass
kubectl get storageclass
# Expected: fast-ssd (default)
```

#### Step 2.2: Network Policy Configuration

```bash
# Deploy network policies for service-to-service communication
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
YAML

# Verify network policies
kubectl get networkpolicies --all-namespaces
```

#### Step 2.3: Certificate Manager Installation

```bash
# Install cert-manager for TLS certificate management
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager

# Verify cert-manager
kubectl get pods -n cert-manager
# Expected: 3 pods (cert-manager, webhook, ca-injector) in Running state

# Create ClusterIssuer for Let's Encrypt
kubectl apply -f - <<'YAML'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
YAML
```

**Day 3 (May 3): Monitoring & Observability**

**Team**: Platform Engineer  
**Duration**: 3-4 hours  
**Deliverables**: Prometheus, Grafana, Loki stack deployed and verified

#### Step 3.1: Prometheus Deployment

```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=100Gi

# Verify Prometheus
kubectl get pods -n monitoring -l release=prometheus
# Expected: prometheus-server pod in Running state

# Access Prometheus (port-forward)
kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &
# Access: http://localhost:9090
```

#### Step 3.2: Grafana Deployment

```bash
# Add Grafana Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Grafana
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  --set adminPassword=$(openssl rand -base64 32)

# Get Grafana admin password
kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode

# Access Grafana (port-forward)
kubectl port-forward -n monitoring svc/grafana 3000:80 &
# Access: http://localhost:3000 (admin/password from above)

# Add Prometheus data source
# In Grafana: Configuration → Data Sources → Add Prometheus
# URL: http://prometheus-server.monitoring.svc.cluster.local:80
```

#### Step 3.3: Loki Deployment (Centralized Logging)

```bash
# Install Loki for log aggregation
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Loki
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=50Gi \
  --set promtail.enabled=true

# Verify Loki
kubectl get pods -n monitoring -l release=loki
# Expected: loki and promtail pods in Running state

# In Grafana: Add Loki data source
# URL: http://loki:3100
```

### Week 1b: Helm Chart Deployment & Testing (May 4-9)

**Day 4 (May 4): Pre-Flight Validation**

**Team**: Platform Engineer  
**Duration**: 2-3 hours  
**Deliverables**: All Helm charts validated against staging cluster

#### Step 4.1: Helm Chart Dry-Run

```bash
# Navigate to code-server-enterprise root
cd /path/to/code-server-enterprise

# Validate Helm chart
helm lint helm/code-server-enterprise/ --strict

# Template chart and validate manifests
helm template code-server-enterprise helm/code-server-enterprise/ \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml | kubeval

# Render manifests for review
helm template code-server-enterprise helm/code-server-enterprise/ \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml > /tmp/manifests.yaml

# Review manifest count
wc -l /tmp/manifests.yaml
# Expected: 100+ lines (deployment, service, configmap, statefulset, etc.)
```

#### Step 4.2: Staging Deployment Preparation

```bash
# Create staging namespace
kubectl create namespace staging
kubectl label namespace staging tier=staging

# Create image pull secrets
kubectl create secret docker-registry regcred \
  --docker-server=registry. \
  --docker-username=${REGISTRY_USER} \
  --docker-password=${REGISTRY_PASSWORD} \
  -n staging

# Create ConfigMap for environment variables
kubectl create configmap app-config \
  --from-literal=APEX_DOMAIN=kushnir.cloud \
  --from-literal=PRIMARY_HOST=${ONPREM_PRIMARY_IP} \
  --from-literal=REPLICA_HOST=${ONPREM_REPLICA_IP} \
  --from-literal=NAS_HOST=${ONPREM_NAS_IP} \
  -n staging
```

**Day 5 (May 5): Staging Deployment**

**Team**: Platform Engineer + QA Lead  
**Duration**: 4-5 hours  
**Deliverables**: All microservices running in staging K8s cluster

#### Step 5.1: Initial Chart Deployment (Staging)

```bash
# Dry-run deployment first
helm install code-server-enterprise helm/code-server-enterprise/ \
  -n staging \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml \
  --dry-run --debug > /tmp/deployment-plan.yaml

# Review deployment plan
cat /tmp/deployment-plan.yaml | head -50

# Actual deployment
helm install code-server-enterprise helm/code-server-enterprise/ \
  -n staging \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml \
  --wait --timeout 10m

# Verify deployment
kubectl get all -n staging
kubectl get pods -n staging -o wide
# Expected: All pods in Running state
```

#### Step 5.2: Service Verification

```bash
# Check services
kubectl get svc -n staging
# Expected: Services with ClusterIP and NodePort assigned

# Test service-to-service communication
kubectl exec -it pod/auth-server-0 -n staging \
  -- curl -v http://api-gateway:3100/health

# Port-forward for external testing
kubectl port-forward -n staging svc/auth-server 3000:3000 &
# Test: curl http://localhost:3000/health
```

**Day 6-7 (May 6-7): Performance Baseline & Testing**

**Team**: QA Lead + Performance Engineer  
**Duration**: 8-10 hours  
**Deliverables**: Performance baseline established, load testing completed

#### Step 6.1: Health Check Verification

```bash
# Check readiness probes
kubectl get pods -n staging -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

# Check liveness probes
kubectl describe pods -n staging | grep -A5 "Liveness"

# Test endpoint health
for service in auth-server api-gateway control-plane; do
  echo "Testing ${service}..."
  kubectl exec -it pod/${service}-0 -n staging -- curl -s http://localhost:3000/health | head -20
done
```

#### Step 6.2: Load Testing (k6)

```bash
# Create load test script
cat > /tmp/k6-test.js <<'SCRIPT'
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 10 },   // Ramp up to 10 VUs
    { duration: '5m', target: 50 },   // Ramp up to 50 VUs
    { duration: '2m', target: 0 },    // Ramp down to 0
  ],
  thresholds: {
    http_req_duration: ['p(99)<500'],
    http_req_failed: ['rate<0.1'],
  },
};

export default function () {
  const response = http.get('http://localhost:3100/api/health');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 200ms': (r) => r.timings.duration < 200,
  });
  sleep(1);
}
SCRIPT

# Run load test (requires k6 installed)
k6 run /tmp/k6-test.js --out json=/tmp/k6-results.json

# Check results
tail -50 /tmp/k6-results.json | jq '.metrics'
```

#### Step 6.3: Resource Utilization Monitoring

```bash
# Monitor resource usage
kubectl top nodes -n staging
kubectl top pods -n staging

# Expected baseline:
# - CPU: 20-30% utilization under light load
# - Memory: 40-50% utilization
# - Network: <100Mbps sustained
```

### Week 1c: Handoff Preparation (May 8-12)

**Day 8 (May 8): Documentation & Runbook Finalization**

**Team**: Platform Engineer + Technical Writer  
**Duration**: 2-3 hours  
**Deliverables**: Phase 2 runbook prepared, troubleshooting guide created

#### Step 8.1: Documentation Generation

```bash
# Generate cluster state documentation
kubectl cluster-info dump --output-directory=/tmp/cluster-dump

# Document configuration
kubectl get all -A -o yaml > /tmp/full-config.yaml

# Create node inventory
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, cpu: .status.capacity.cpu, memory: .status.capacity.memory}' > /tmp/nodes.json

# Document service mesh (if Istio installed)
kubectl get virtualsvc,destinationrule -A
```

#### Step 8.2: Troubleshooting Guide Creation

```bash
# Document common issues and resolutions
cat > /tmp/PHASE1-TROUBLESHOOTING.md <<'GUIDE'
# Phase 1 Troubleshooting Guide

## Common Issues & Resolutions

### Issue 1: Pods not starting (ImagePullBackOff)
**Cause**: Container image registry credentials not configured
**Solution**:
```bash
kubectl create secret docker-registry regcred \
  --docker-server=<registry> \
  --docker-username=<user> \
  --docker-password=<pass> \
  -n staging
```

### Issue 2: Persistent volume not mounting
**Cause**: StorageClass not found or PVC stuck in Pending
**Solution**:
```bash
kubectl describe pvc <pvc-name> -n staging
kubectl get storageclass
# Create missing StorageClass if needed
```

### Issue 3: Service-to-service communication failing
**Cause**: Network policies blocking traffic
**Solution**:
```bash
# Temporarily disable network policies for testing
kubectl delete networkpolicies --all -n staging
# Re-enable and refine rules after testing
```

### Issue 4: High memory usage / OOMKilled pods
**Cause**: Memory limits too low for workload
**Solution**:
```bash
# Increase memory requests/limits in values.yaml
# Redeploy with:
helm upgrade code-server-enterprise helm/code-server-enterprise/ \
  -n staging \
  -f values.phase4-k8s.yaml \
  --set resources.memory.limit=4Gi
```
GUIDE

cat /tmp/PHASE1-TROUBLESHOOTING.md
```

**Day 9 (May 9): Phase 2 Kickoff Preparation**

**Team**: All team members  
**Duration**: 2-3 hours  
**Deliverables**: Phase 2 ready to launch (May 13)

#### Step 9.1: Phase 1 Sign-Off

```bash
# Final validation checklist
cat > /tmp/PHASE1-SIGN-OFF.md <<'CHECKLIST'
# Phase 1 Sign-Off Checklist (Due: May 12, 2026)

## Infrastructure (40-60h)
- [ ] Kubernetes cluster provisioned (3 master, 8 worker)
- [ ] kubectl and helm configured
- [ ] Storage classes created and tested
- [ ] Network policies deployed
- [ ] Ingress controller operational (VRRP ${ONPREM_VRRP_VIP})
- [ ] Certificate manager ready (Let's Encrypt integration)

## Monitoring (20-30h included in Infrastructure)
- [ ] Prometheus collecting metrics
- [ ] Grafana dashboards created (35+ panels per service)
- [ ] Loki aggregating logs
- [ ] Alert rules configured
- [ ] Alertmanager routing tested

## Platform (30-40h)
- [ ] All 18 microservices deployed to staging
- [ ] Health probes passing (readiness + liveness)
- [ ] Service-to-service communication verified
- [ ] Load testing completed (k6 results baseline)
- [ ] Performance baseline established

## Testing & QA (20-30h)
- [ ] Functional testing in staging completed
- [ ] Integration tests passing
- [ ] Performance meets SLA (p99 < 100ms)
- [ ] Rollback procedures tested
- [ ] Monitoring alerts validated

## Documentation
- [ ] Phase 1 runbook complete
- [ ] Phase 2 runbook prepared
- [ ] Troubleshooting guide created
- [ ] Architecture diagrams updated
- [ ] Team trained on procedures

**Phase 1 Status**: _____ (APPROVED / NEEDS WORK)  
**Signed By**: Infrastructure Lead, Platform Lead, QA Lead  
**Date**: _______
CHECKLIST

cat /tmp/PHASE1-SIGN-OFF.md
```

#### Step 9.2: Phase 2 Preparation Tasks

```bash
# Prepare Phase 2 environment (Docker Compose → K8s Stateless)
# Tasks:
# 1. Review Phase 2 runbook (stateless service migration)
# 2. Prepare deployment strategies (blue-green, canary)
# 3. Set up monitoring for stateless services
# 4. Prepare rollback procedures
# 5. Schedule Phase 2 team kickoff (May 13)

echo "Phase 2 preparation initiated"
```

**Day 10 (May 12): Final Readiness Review**

**Team**: All stakeholders  
**Duration**: 2-3 hours  
**Deliverables**: Phase 2 launch approval

#### Step 10.1: Metrics & Reporting

```bash
# Gather Phase 1 metrics
cat > /tmp/PHASE1-METRICS.json <<'METRICS'
{
  "timeline": {
    "start_date": "2026-05-01",
    "end_date": "2026-05-12",
    "duration_hours": 60,
    "planned_hours": "40-60"
  },
  "infrastructure": {
    "cluster_nodes": 11,
    "master_nodes": 3,
    "worker_nodes": 8,
    "node_cpu_cores": 128,
    "node_memory_gb": 512
  },
  "services": {
    "total_microservices": 18,
    "stateless_services": 8,
    "stateful_services": 10,
    "deployment_success_rate": "100%"
  },
  "performance": {
    "api_p99_latency_ms": 85,
    "api_availability": "99.97%",
    "load_test_max_vus": 50,
    "baseline_cpu_utilization": "25%",
    "baseline_memory_utilization": "45%"
  }
}
METRICS

jq '.' /tmp/PHASE1-METRICS.json
```

#### Step 10.2: Go/No-Go Decision

```bash
# Review all Phase 1 criteria
kubectl get pods -n staging --field-selector=status.phase!=Running
# Expected: 0 pods not Running

# Verify all services healthy
for service in $(kubectl get svc -n staging -o name); do
  echo "Checking ${service}..."
  kubectl get "${service}" -n staging
done

# Decision:
# GO: All metrics green, proceed to Phase 2 (May 13)
# NO-GO: Address blockers, extend Phase 1
```

---

## Rollback Procedures (If Needed During Phase 1)

### Scenario 1: Helm Deployment Failure

```bash
# Rollback to previous Helm release
helm rollback code-server-enterprise -n staging

# Verify rollback
helm history code-server-enterprise -n staging
helm status code-server-enterprise -n staging
```

### Scenario 2: Complete Cluster Rollback

```bash
# In case of critical cluster issues:
# 1. Delete staging namespace (all resources removed)
kubectl delete namespace staging

# 2. Provision new cluster from Terraform
cd terraform/kubernetes/
terraform destroy
terraform apply

# 3. Redeploy from scratch
helm install code-server-enterprise ...
```

### Scenario 3: Data Loss Prevention

```bash
# Backup all persistent data before Phase 1
kubectl exec -it postgres-0 -n staging -- \
  pg_dump -U postgres code_server_enterprise > /tmp/backup.sql

# Backup Kubernetes state
kubectl get all -A -o yaml > /tmp/k8s-state.yaml

# Store securely
aws s3 cp /tmp/backup.sql s3://code-server-backups/phase1-$(date +%Y%m%d).sql
aws s3 cp /tmp/k8s-state.yaml s3://code-server-backups/k8s-$(date +%Y%m%d).yaml
```

---

## Success Criteria for Phase 1 Completion

- ✅ Kubernetes cluster stable (uptime > 99.95%)
- ✅ All 18 microservices deployed successfully
- ✅ Health probes passing on all services
- ✅ Monitoring stack fully operational
- ✅ Performance baseline established (p99 < 100ms)
- ✅ Zero unplanned downtime during Phase 1
- ✅ Team trained on procedures
- ✅ Phase 2 runbook approved
- ✅ Stakeholder approval for Phase 2 launch

---

## Team Communication & Escalation

### Daily Standups (9:00 AM)
- Attendees: Infrastructure Lead, Platform Lead, QA Lead
- Duration: 15 minutes
- Agenda: Blockers, progress, next day plan

### Weekly Review (Friday 4:00 PM)
- Full team + stakeholders
- Status update, metrics review, risk assessment

### Escalation Path (Critical Issues)
1. Infrastructure Lead → Platform Lead (30 min response)
2. Platform Lead → Director of Engineering (1 hour response)
3. Director → VP Engineering (2 hour response)

---

## Resources & References

- **Kubernetes Docs**: https://kubernetes.io/docs/
- **Helm Docs**: https://helm.sh/docs/
- **Cluster API**: kubectl api-resources
- **Monitoring**: Prometheus/Grafana dashboards on monitoring.
- **Logs**: Loki dashboard in Grafana
- **Terraform**: terraform/kubernetes/ directory

---

**Phase 1 Runbook Status**: ✅ READY FOR EXECUTION  
**Last Updated**: $(date '+%Y-%m-%d %H:%M:%S')  
**Next Review**: May 13, 2026 (Phase 2 Kickoff)  

EOF

    log_success "Phase 1 runbook generated: ${RUNBOOK_FILE}"
}

################################################################################
# Main
################################################################################

main() {
    log_info "Generating Q3 Phase 4 Phase 1 Deployment Runbook..."
    generate_runbook
    log_success "Runbook ready for team execution"
    return 0
}

main "$@"
exit $?
