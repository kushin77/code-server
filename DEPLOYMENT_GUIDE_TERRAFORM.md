# Kubernetes Infrastructure as Code: Complete Deployment Guide
## 10-Phase Terraform Implementation for On-Premises & Cloud

## Executive Summary

This guide provides step-by-step instructions for deploying a production-grade Kubernetes cluster with 10 phases of infrastructure:

- **Phases 2-8**: Core infrastructure (namespaces, storage, monitoring, security, backup, apps, ingress, verification)
- **Phase 10**: On-premises optimization (resource management, cost analysis, operational runbooks)

**Deployment Time**: 5-10 minutes  
**Automation**: 100% Infrastructure as Code (Terraform)  
**Idempotency**: All resources safe to re-apply  
**Configuration**: Single `terraform.tfvars` file

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Pre-Deployment Checklist](#pre-deployment-checklist)
4. [Deployment Steps](#deployment-steps)
5. [Post-Deployment Verification](#post-deployment-verification)
6. [Access & Usage](#access--usage)
7. [Troubleshooting](#troubleshooting)
8. [Operations](#operations)

---

## Prerequisites

### Required Tools

```bash
# Check versions
terraform version        # v1.5.0+
kubectl version --client # v1.27.0+
helm version            # v3.12.0+
```

### Kubernetes Cluster

- Kubernetes 1.27.0 or later
- 3+ nodes (HA configuration recommended)
- 8+ CPU cores, 16+ GB memory total
- Configured kubeconfig with admin access

```bash
# Verify cluster connectivity
kubectl cluster-info
kubectl get nodes
```

### Access Credentials

- kubeconfig file location (default: `~/.kube/config`)
- Current context name from kubeconfig
- For on-premises: SSH access to nodes for troubleshooting

---

## Architecture Overview

### 10-Phase Deployment Pipeline

```
PHASE 2: Namespaces & Storage
├─ Create 6 namespaces (monitoring, security, backup, code-server, ingress, cert-manager)
├─ Create StorageClass "local-storage"
└─ Create 4 PersistentVolumes (prometheus, loki, code-server, velero)

PHASE 3: Observability Stack
├─ Prometheus (2 replicas, 50Gi storage, metrics collection)
├─ Grafana (2 replicas, dashboards & alerts)
└─ Loki (2 replicas, 20Gi storage, log aggregation)

PHASE 4: Security & RBAC
├─ Network Policies (default-deny + explicit allow rules)
├─ RBAC roles (read-only, developer, admin tiers)
├─ ServiceAccounts (monitoring, code-server, backup)
└─ Pod Security Standards

PHASE 5: Backup & Disaster Recovery
├─ Velero Helm deployment
├─ Daily full backup schedule
├─ Hourly incremental backup schedule
└─ Automated restore verification

PHASE 6: Application Platform (code-server)
├─ code-server StatefulSet (2 replicas, 100Gi workspace per pod)
├─ ConfigMaps for settings & extensions
├─ Persistent workspace storage
└─ Service for internal cluster access

PHASE 7: Ingress & Load Balancing
├─ NGINX Ingress Controller (DaemonSet for HA)
├─ cert-manager (automatic TLS certificates)
├─ Ingress routes (Grafana, Prometheus, code-server)
└─ Let's Encrypt certificate issuers (staging & prod)

PHASE 8: Verification & Validation
├─ Health check scripts
├─ Compliance verification
├─ Performance benchmarking
└─ Deployment checklist

PHASE 10: On-Premises Optimization
├─ Resource Quotas (prevent over-subscription)
├─ Priority Classes (intelligent pod eviction)
├─ Horizontal Pod Autoscaling (HPA for code-server)
├─ Metrics Optimization (compression, 80% storage savings)
├─ Cost Analysis (annual operating cost breakdown)
└─ Operational Runbooks (disaster recovery procedures)
```

### Resource Summary

| Component | Type | Count | Storage | CPU/Memory |
|-----------|------|-------|---------|-----------|
| Namespaces | K8s | 6 | - | - |
| StorageClass | K8s | 1 | - | - |
| PersistentVolumes | K8s | 4 | 570Gi | - |
| Pods (core) | K8s | 10-20 | 570Gi | ~15 CPU, 24Gi memory |
| Helm Charts | Apps | 5 | - | - |
| Services | K8s | 10+ | - | - |
| Ingress Routes | K8s | 3 | - | - |
| Network Policies | K8s | 4 | - | - |
| Priority Classes | K8s | 3 | - | - |
| Resource Quotas | K8s | 2 | - | - |
| HPA | K8s | 1 | - | - |

---

## Pre-Deployment Checklist

### Cluster Health

```bash
$ kubectl get nodes
# Expected: All nodes in "Ready" state

$ kubectl get componentstatuses
# Expected: All components Healthy

$ kubectl cluster-info
# Expected: Cluster info and certificate authority data
```

### kubeconfig Configuration

```bash
$ kubectl config current-context
# Expected: your-cluster-context

$ kubectl config view | grep current-context
# Copy the context name to terraform.tfvars

$ kubectl auth can-i create deployments --all-namespaces
# Expected: yes
```

### Disk Space

```bash
# Check node disk space
$ for node in $(kubectl get nodes -o name); do
    echo "=== $node ===" 
    kubectl debug $node -- df -h / | grep -v tmpfs
  done

# Each node should have 100+ Gi available
```

### Network Connectivity

```bash
# Test inter-node communication
$ kubectl run -it --image=busybox --restart=Never busybox -- \
    ping -c 1 <other-node-ip>

# Test DNS
$ kubectl run -it --image=busybox --restart=Never busybox -- \
    nslookup kubernetes.default
```

---

## Deployment Steps

### Step 1: Clone Repository

```bash
cd /path/to/code-server-enterprise/terraform
ls -la
# Expected files:
#   versions.tf, variables.tf, main.tf, terraform.tfvars.example
#   modules/phase2-8, phase10-onprem-optimization
```

### Step 2: Create terraform.tfvars

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
cat terraform.tfvars
```

**Critical Variables to Customize**:

```hcl
# KUBERNETES CONNECTION
kubeconfig_path      = "~/.kube/config"
kubeconfig_context   = "your-cluster-name"

# CLUSTER CONFIGURATION
cluster_name         = "your-cluster-name"
cluster_version      = "1.27.0"

# NETWORK
pod_cidr             = "10.244.0.0/16"
service_cidr         = "10.96.0.0/12"

# CREDENTIALS (CHANGE IMMEDIATELY!)
grafana_admin_password = "YOUR_SECURE_PASSWORD"
code_server_password   = "YOUR_SECURE_PASSWORD"

# HOSTNAMES
domain               = "your.domain.com"
grafana_hostname     = "grafana.your.domain.com"
prometheus_hostname  = "prometheus.your.domain.com"
code_server_hostname = "code-server.your.domain.com"

# ON-PREMISES (Phase 10)
cluster_node_count   = 3                # Your node count
cost_per_server      = 5000             # Hardware cost
annual_power_cost    = 5256             # Estimated power cost
```

### Step 3: Initialize Terraform

```bash
# Initialize workspace
make init

# Or: terraform init

# Validate configuration
make validate

# Or: terraform validate
```

**Expected Output**:
```
Initializing the backend...
Downloading required providers...
Terraform has been successfully configured!
```

### Step 4: Plan Deployment

```bash
# Preview all changes
make plan

# Or: terraform plan -out=tfplan

# Review output for:
# - Resource creation (should be ~100+ resources)
# - No unexpected deletions
# - Correct namespaces, storage sizes, etc.
```

**Expected Output**:
```
Plan: 120 to add, 0 to change, 0 to destroy
```

### Step 5: Deploy Infrastructure

#### Option A: Interactive Deployment (Recommended for First Run)

```bash
make apply

# Or: terraform apply tfplan

# This will:
# 1. Show the plan
# 2. Ask for confirmation (type "yes")
# 3. Deploy all phases
# 4. Log all activities to logs/
```

**Deployment Progress** (watch in another terminal):

```bash
watch -n 2 kubectl get pods -A
watch -n 2 kubectl get pvc -A
watch -n 2 kubectl get nodes
```

#### Option B: Automated Deployment (for CI/CD)

```bash
make quick-apply

# Or: terraform apply -auto-approve

# This will deploy without asking (idempotent, safe for re-runs)
```

### Step 6: Monitor Deployment

```bash
# Watch pod creation progress
kubectl get pods -A --watch

# Check persistent volume binding
kubectl get pvc -A

# Monitor events
kubectl get events -A --sort-by='.lastTimestamp'

# When ready, you should see:
# - All pods in "Running" state
# - All PVCs in "Bound" state
# - All nodes in "Ready" state
```

**Expected Timeline**:
- T+0-1 min: Namespaces & Storage created
- T+1-3 min: Prometheus/Grafana/Loki pods starting
- T+3-5 min: Observability stack ready
- T+5-7 min: Security & RBAC configured
- T+7-8 min: Backup & app platform ready
- T+8-10 min: Ingress & TLS ready
- T+10+ min: All verification and optimization complete

---

## Post-Deployment Verification

### Quick Verification (2 minutes)

```bash
# Show deployment summary
make outputs

# Or: terraform output deployment_summary
```

**Expected Output**:
```
deployment_summary = {
  phase_2_namespaces    = "✓ Namespaces created"
  phase_2_storage       = "✓ Storage provisioned"
  phase_3_observability = "✓ Prometheus, Grafana, Loki deployed"
  ...
  phase_10_optimization = "✓ On-premises optimization enabled"
}
```

### Full Verification (5 minutes)

```bash
# Run comprehensive health check
make health-check

# Or: bash /tmp/k8s-verification/01-health-check.sh
```

**Checks Performed**:
- [ ] All namespaces exist
- [ ] All pods are running
- [ ] All PVCs are bound
- [ ] Node resources available
- [ ] Critical services responsive

### Compliance & Performance

```bash
# Check compliance policies
make compliance

# Or: bash /tmp/k8s-verification/02-compliance-check.sh

# Run performance benchmarks
make benchmark

# Or: bash /tmp/k8s-verification/03-performance-benchmark.sh
```

### Review Deployment Checklist

```bash
# View verification checklist
make checklist

# Or: kubectl get configmap verification-checklist \
      -o jsonpath='{.data.VERIFICATION_CHECKLIST\.md}'
```

---

## Access & Usage

### View Access Information

```bash
make access-info

# Or: terraform output access_information
```

**Expected Output**:
```
MONITORING & OBSERVABILITY:
  Prometheus:  https://prometheus.your.domain.com
  Grafana:     https://grafana.your.domain.com
  Loki:        internal://loki.monitoring:3100

DEVELOPMENT PLATFORM:
  code-server: https://code-server.your.domain.com
  Workspaces:  2 replicas with 100Gi storage each

BACKUP & DISASTER RECOVERY:
  Velero:      Automated daily backups enabled

SECURITY:
  Network Policies: Default-deny with explicit allow rules
  RBAC:            Role-based access control configured
```

### Access Services Locally

```bash
# Port-forward to services
make port-forward

# Then access:
# - Prometheus: http://localhost:9090
# - Grafana:    http://localhost:3000
# - code-server: http://localhost:8080

# Login:
# Grafana:      admin / <grafana_admin_password>
# code-server:  password / <code_server_password>
```

### Via Ingress (If DNS Configured)

```bash
# Update /etc/hosts (on client machine)
<cluster-ip> prometheus.your.domain.com
<cluster-ip> grafana.your.domain.com
<cluster-ip> code-server.your.domain.com

# Then access in browser:
https://grafana.your.domain.com
https://prometheus.your.domain.com
https://code-server.your.domain.com
```

---

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -A

# Describe failing pod
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace> --previous  # If crashed
kubectl logs <pod-name> -n <namespace> -f          # Live logs

# Common causes:
# - PVC not bound: kubectl get pvc -A
# - Image not found: kubectl get events -A
# - Insufficient resources: kubectl describe node
```

### Storage Not Binding

```bash
# Check PVCs
kubectl get pvc -A

# Describe PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Check available nodes and storage
kubectl get nodes -o wide
kubectl get pv

# On on-premises: Verify local-storage provisioner
kubectl get daemonset -n kube-system | grep local-storage
```

### Ingress Not Working

```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress rules
kubectl get ingress -A

# Describe ingress
kubectl describe ingress <name> -n <namespace>

# Check cert-manager
kubectl get certificate -A
kubectl get clusterissuer
kubectl describe certificaterequest -A

# Common causes:
# - cert-manager not ready: Wait 1-2 minutes
# - DNS not resolving: Check /etc/hosts or DNS server
# - TLS cert not issued: Check cert-manager logs
```

### Helm Releases Not Installing

```bash
# Check Helm repositories
helm repo list

# Check releases
helm list -A

# Describe release
helm status <release> -n <namespace>

# Check Helm values
helm values <release> -n <namespace>

# Retry deployment
make quick-apply  # Idempotent, safe to re-run
```

### Out of Disk Space

```bash
# Check node disk usage
df -h

# Identify large directories
du -sh /* | sort -rh | head -10

# Clean old logs
find /var/log -mtime +7 -delete

# Clean Docker/containerd
docker system prune -a  # Only if not running system pods

# Or follow runbook:
kubectl get configmap onprem-runbooks -n default \
  -o jsonpath='{.data.02-storage-full-recovery\.md}'
```

### Network Connectivity Issues

```bash
# Test pod-to-pod
kubectl exec -it <pod1> -n <ns1> -- \
  ping <pod2>.<ns2>.svc.cluster.local

# Test service DNS
kubectl run -it --image=busybox --restart=Never busybox -- \
  nslookup <service>.<namespace>.svc.cluster.local

# Check network policies
kubectl get networkpolicies -A

# Temporarily allow all (for testing only)
kubectl delete networkpolicy -A --all

# Or follow runbook:
kubectl get configmap onprem-runbooks -n default \
  -o jsonpath='{.data.03-network-partition-recovery\.md}'
```

---

## Operations

### Daily Operations

```bash
# Morning status check
make verify           # Check pod status and resources

# Monitor backup completion
kubectl get backups -n backup
velero backup describe <backup-name>

# Check alerts
kubectl logs -n monitoring <alertmanager-pod>
```

### Scaling Workloads

```bash
# Increase code-server replicas
terraform apply -var 'code_server_replicas=5'

# Or use HPA (automatic)
kubectl get hpa code-server-hpa -n code-server

# Monitor HPA activity
kubectl describe hpa code-server-hpa -n code-server
kubectl get events -n code-server --sort-by='.lastTimestamp'
```

### Updating Components

```bash
# Update code-server version
terraform apply -var 'code_server_version=4.30.0'

# Chart versions
# - Edit modules/phase7-ingress/variables.tf
# - Run: terraform apply
```

### Backup & Restore

```bash
# Create on-demand backup
kubectl -n backup exec <velero-pod> -- \
  velero backup create manual-backup

# List backups
kubectl -n backup exec <velero-pod> -- \
  velero backup get

# Restore from backup
kubectl -n backup exec <velero-pod> -- \
  velero restore create --from-backup <backup-name>

# Or follow complete runbook:
kubectl get configmap onprem-runbooks -n default \
  -o jsonpath='{.data.04-backup-restore-procedure\.md}'
```

### Monitoring & Alerting

```bash
# Access Grafana
make port-forward  # Then: http://localhost:3000
# Import dashboards: Grafana UI → Dashboards → Import

# Access Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Then: http://localhost:9090

# Check Prometheus targets
# Prometheus UI → Status → Targets
```

### Cost Management

```bash
# View cost analysis
kubectl get configmap cost-optimization-report -n default

# Or directly
terraform output cost_summary

# Review monthly spending
# Update terraform.tfvars with actual costs
# Re-run: terraform apply
```

### Disaster Recovery Drills

```bash
# Follow disaster recovery procedure quarterly:

# 1. Backup cluster
make health-check
kubectl get backup -n backup | tail -5

# 2. Create test restore
kubectl -n backup exec velero-<pod> -- \
  velero restore create --from-backup <latest-backup>

# 3. Verify restore
kubectl get all -A | wc -l

# 4. Report findings
# Document any issues for post-mortem
```

---

## Maintenance Tasks

### Weekly

```bash
# Check resource usage
make verify

# Monitor quota usage
kubectl describe quota -A

# Review logs for errors
make logs
```

### Monthly

```bash
# Update & re-apply Terraform
terraform plan
terraform apply

# Run compliance checks
make compliance

# Review cost report
terraform output cost_summary

# Disaster recovery drill
# Follow runbook: 04-backup-restore-procedure
```

### Quarterly

```bash
# Full system review
# 1. Check for Kubernetes updates
# 2. Update component versions
# 3. Review and update runbooks
# 4. Plan scaling needs
# 5. Conduct full DR test
```

---

## Support & Documentation

| Resource | Location |
|----------|----------|
| Main README | `terraform/README.md` |
| Phase 2 (Namespaces) | `terraform/modules/phase2-namespaces/` |
| Phase 3 (Observability) | `terraform/modules/phase3-observability/` |
| Phase 4 (Security) | `terraform/modules/phase4-security/` |
| Phase 5 (Backup) | `terraform/modules/phase5-backup/` |
| Phase 6 (code-server) | `terraform/modules/phase6-app-platform/` |
| Phase 7 (Ingress) | `terraform/modules/phase7-ingress/` |
| Phase 8 (Verification) | `terraform/modules/phase8-verification/` |
| Phase 10 (Optimization) | `terraform/modules/phase10-onprem-optimization/README.md` |
| Makefilefile | `Makefile.terraform` |
| Operational Runbooks | via ConfigMap: `kubectl get configmap onprem-runbooks` |

---

## Quick Command Reference

```bash
# Essential commands
make help              # Show all make targets
make init              # Initialize Terraform
make plan              # Preview changes
make apply             # Deploy infrastructure
make quick-apply       # Deploy auto-approve (idempotent)
make destroy           # Destroy infrastructure

# Verification
make verify            # Verify deployment status
make health-check      # Run health checks
make compliance        # Check compliance
make benchmark         # Run performance benchmarks
make checklist         # Show verification checklist

# Access & operations
make outputs           # Show all outputs
make access-info       # Show access URLs
make port-forward      # Port-forward to services
make logs              # Show operation logs
make cleanup           # Clean test resources

# Troubleshooting
kubectl get pods -A    # List all pods
kubectl describe pod <name> -n <ns>  # Debug pod
kubectl logs <pod> -n <ns>           # View logs
kubectl exec -it <pod> -n <ns> -- /bin/sh  # Pod shell
```

---

## Next Steps

1. ✅ **Deploy**: Run `make apply`
2. ✅ **Verify**: Run `make health-check`
3. ✅ **Configure DNS**: Point domain to cluster
4. ✅ **Access Services**: Use hostnames from `make access-info`
5. ✅ **Monitor**: Set up alerting in Grafana
6. ✅ **Backup**: Verify first backup completes
7. ✅ **Drill**: Run disaster recovery procedure
8. ✅ **Document**: Keep runbooks current

---

**Status**: Production-Ready  
**Last Updated**: 2024-01-27  
**Version**: 1.0.0
