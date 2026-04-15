# Phase 3 Complete Deployment Guide
## Elite Code-Server Platform - Full End-to-End Implementation

**Date**: April 15, 2026  
**Status**: ✅ COMPLETE & READY FOR PRODUCTION DEPLOYMENT  
**Platform**: Kubernetes (k3s) on 192.168.168.31 (on-prem)  

---

## 📋 Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Deployment Sequence](#deployment-sequence)
3. [Individual Issue Deployments](#individual-issue-deployments)
4. [Verification & Health Checks](#verification--health-checks)
5. [Production Operations](#production-operations)
6. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Code-Server Platform                          │
│                    (192.168.168.31)                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  │  k3s Cluster     │  │  ArgoCD GitOps   │  │  Dagger CI/CD    │
│  │  (Issue #164)    │  │  (Issue #168)    │  │  (Issue #169)    │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘
│         ↓                      ↓                      ↓
│  • GPU Support          • Multi-env Deploy    • Language-agnostic
│  • Storage (NFS+Local)  • Canary Rollouts    • Container builds
│  • Networking           • RBAC Isolation     • 5-10x faster
│  • Load Balancing       • Git-driven         • Harbor registry
│                         • Slack notify       • Dagger workflows
│                                                     ↓
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  │  OPA/Kyverno     │  │  Docker BuildKit │  │  Nexus Registry  │
│  │  (Issue #170)    │  │  (Issue #174)    │  │  (Issue #175)    │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘
│         ↓                      ↓                      ↓
│  • Pod Security         • Layer Caching       • NPM Proxy
│  • Image Policies       • Parallel Builds     • Maven Central
│  • Resource Limits      • S3 Cache            • Docker Hosted
│  • Admission Control    • GC Policy           • Backup/restore
│                                                     ↓
│  ┌──────────────────────────────────────┐  ┌──────────────────┐
│  │  Developer Dashboard (Issue #176)    │  │  Phase 1 Services │
│  │  • Status Monitor                    │  │  • Code-Server    │
│  │  • Metrics & Activity                │  │  • Prometheus     │
│  │  • Deployment Tracking               │  │  • Grafana        │
│  │  • Build Metrics                     │  │  • PostgreSQL     │
│  └──────────────────────────────────────┘  └──────────────────┘
│
└─────────────────────────────────────────────────────────────────┘
```

---

## Deployment Sequence

### Prerequisites (5 minutes)
```bash
# 1. Verify SSH access
ssh akushnir@192.168.168.31 "docker ps" | head -3

# 2. Verify k3s prerequisites
ssh akushnir@192.168.168.31 "uname -r && free -h && df -h | grep -E 'Filesystem|home'"

# 3. Transfer all deployment scripts
cd c:\code-server-enterprise
scp -r scripts/phase3-*.sh kubernetes/*.yaml akushnir@192.168.168.31:/tmp/
```

### Phase 3 Sequential Deployment (90 minutes total)

#### Step 1: Deploy k3s Foundation (15 minutes)
```bash
# Execute on remote host (192.168.168.31)
ssh akushnir@192.168.168.31
sudo -n bash /tmp/phase3-k3s-deploy.sh
bash /tmp/phase3-k3s-test.sh  # Verify 10 tests pass
```

**Success Criteria**:
- ✅ 1 node showing READY
- ✅ All system pods running
- ✅ GPU device plugin available
- ✅ Storage classes available
- ✅ MetalLB load balancer responding

#### Step 2: Deploy ArgoCD GitOps (15 minutes)
```bash
bash /tmp/phase3-argocd-setup.sh
bash /tmp/phase3-argocd-test.sh  # Verify 12 tests pass
```

**Success Criteria**:
- ✅ ArgoCD UI accessible
- ✅ Git repository connected
- ✅ Applications syncing
- ✅ Canary rollouts ready

#### Step 3: Deploy Dagger CI/CD (10 minutes)
```bash
bash /tmp/phase3-dagger-setup.sh
bash /tmp/phase3-dagger-test.sh  # Verify workflows ready
```

**Success Criteria**:
- ✅ Dagger CLI operational
- ✅ Namespace created
- ✅ RBAC configured
- ✅ Workflows accessible

#### Step 4: Deploy OPA/Kyverno (10 minutes)
```bash
bash /tmp/phase3-opa-setup.sh
bash /tmp/phase3-opa-test.sh  # Verify policies enforced
```

**Success Criteria**:
- ✅ Kyverno deployment running
- ✅ 6+ policies created
- ✅ Webhooks responding
- ✅ Pod security enforced

#### Step 5: Deploy BuildKit (10 minutes)
```bash
bash /tmp/phase3-buildkit-setup.sh
# Verify: export DOCKER_BUILDKIT=1 && docker build -t test .
```

**Success Criteria**:
- ✅ BuildKit service running
- ✅ Layer caching operational
- ✅ Docker builds 5-10x faster

#### Step 6: Deploy Nexus Repository (15 minutes)
```bash
bash /tmp/phase3-nexus-setup.sh
# Access at http://nexus.192.168.168.31.nip.io
```

**Success Criteria**:
- ✅ Nexus pod running
- ✅ Repositories created (NPM, Maven, Docker)
- ✅ 200GB storage configured

#### Step 7: Deploy Developer Dashboard (10 minutes)
```bash
bash /tmp/phase3-dashboard-setup.sh
# Access at http://dev.192.168.168.31.nip.io
```

**Success Criteria**:
- ✅ Dashboard UI responding
- ✅ API connected to metrics
- ✅ Real-time status displayed

---

## Individual Issue Deployments

### Issue #164: k3s Kubernetes Cluster
**Files**: 
- `scripts/phase3-k3s-setup.sh` - Initialization
- `scripts/phase3-k3s-deploy.sh` - Production deployment
- `scripts/phase3-k3s-test.sh` - Validation suite (10 tests)
- `kubernetes/storage-classes.yaml` - Storage provisioners
- `kubernetes/network-policies.yaml` - Zero-trust networking
- `kubernetes/metallb-config.yaml` - Load balancer config

**Deployment**:
```bash
bash scripts/phase3-k3s-deploy.sh
bash scripts/phase3-k3s-test.sh
```

**Time**: 15-20 minutes

---

### Issue #168: ArgoCD GitOps Control Plane
**Files**:
- `scripts/phase3-argocd-setup.sh` - Installation & config
- `scripts/phase3-argocd-test.sh` - Validation suite (12 tests)
- `kubernetes/argocd-applications.yaml` - Multi-env apps

**Deployment**:
```bash
bash scripts/phase3-argocd-setup.sh
bash scripts/phase3-argocd-test.sh
```

**Time**: 15 minutes (depends on k3s #164)

---

### Issue #169: Dagger CI/CD Engine
**Files**:
- `scripts/phase3-dagger-setup.sh` - Installation
- `scripts/phase3-dagger-test.sh` - Validation suite
- `.github/workflows/dagger-cicd-pipeline.yml` - GitHub Actions

**Deployment**:
```bash
bash scripts/phase3-dagger-setup.sh
bash scripts/phase3-dagger-test.sh
```

**Time**: 10 minutes (depends on k3s #164)

---

### Issue #170: OPA/Kyverno Policy Engine
**Files**:
- `scripts/phase3-opa-setup.sh` - Installation & policies
- `scripts/phase3-opa-test.sh` - Validation suite (18 tests)

**Deployment**:
```bash
bash scripts/phase3-opa-setup.sh
bash scripts/phase3-opa-test.sh
```

**Time**: 10 minutes (depends on k3s #164)

---

### Issue #174: Docker BuildKit
**Files**:
- `scripts/phase3-buildkit-setup.sh` - Installation & config

**Deployment**:
```bash
bash scripts/phase3-buildkit-setup.sh
export DOCKER_BUILDKIT=1
docker build -t code-server .
```

**Time**: 10 minutes

---

### Issue #175: Nexus Repository Manager
**Files**:
- `scripts/phase3-nexus-setup.sh` - Installation & repos

**Deployment**:
```bash
bash scripts/phase3-nexus-setup.sh
# Access: http://nexus.192.168.168.31.nip.io
```

**Time**: 15-20 minutes

---

### Issue #176: Developer Dashboard
**Files**:
- `scripts/phase3-dashboard-setup.sh` - Installation

**Deployment**:
```bash
bash scripts/phase3-dashboard-setup.sh
# Access: http://dev.192.168.168.31.nip.io
```

**Time**: 10 minutes

---

## Verification & Health Checks

### Full Platform Health Check
```bash
#!/bin/bash
echo "=== Phase 3 Platform Health Check ==="
echo ""

# k3s
echo "1. k3s Cluster:"
kubectl get nodes
kubectl get pods -A | head -20
echo ""

# ArgoCD
echo "2. ArgoCD:"
kubectl get deployment -n argocd
kubectl get applications -A
echo ""

# Dagger
echo "3. Dagger:"
kubectl get ns dagger
dagger version
echo ""

# OPA
echo "4. OPA/Kyverno:"
kubectl get deployment -n kyverno
kubectl get clusterpolicies | head -5
echo ""

# BuildKit
echo "5. BuildKit:"
docker ps | grep buildkit
echo ""

# Nexus
echo "6. Nexus:"
kubectl get pods -n nexus
echo ""

# Dashboard
echo "7. Developer Dashboard:"
kubectl get pods -n dev-dashboard
echo ""

# Phase 1 (Original)
echo "8. Phase 1 Services:"
docker ps --format "table {{.Names}}\t{{.Status}}" | head -10
```

### Test Suites
```bash
# Run all test suites
for test in phase3-{k3s,argocd,dagger,opa}-test.sh; do
  echo "Running $test..."
  bash scripts/$test
done
```

---

## Production Operations

### Monitoring & Alerting
```bash
# Prometheus
kubectl get service -n monitoring | grep prometheus

# Grafana  
kubectl get service -n monitoring | grep grafana

# Alerts
kubectl get alerts -A

# Logs
kubectl logs -f deployment/code-server -n code-server
kubectl logs -f deployment/argocd-server -n argocd
```

### Backup & Disaster Recovery
```bash
# Backup etcd (k3s)
kubectl get configmap -n kube-system kube-root-ca.crt
kubectl cp kube-system/k3s-etcd:/var/lib/rancher/k3s/server/db/state.db ./k3s-etcd-backup.db

# Backup applications
argocd app get-all | xargs -I {} argocd app save {}

# Restore
argocd app sync --apply
```

### Update & Maintenance
```bash
# Update k3s
sudo systemctl stop k3s
sudo curl -sfL https://get.k3s.io | sh -
sudo systemctl start k3s

# Update ArgoCD
helm repo update
helm upgrade argocd argo-cd/argocd -n argocd

# Update Kyverno
helm repo update kyverno
helm upgrade kyverno kyverno/kyverno -n kyverno
```

---

## Troubleshooting

### Common Issues

**Issue**: Pod not starting in k3s
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

**Issue**: BuildKit cache not working
```bash
export DOCKER_BUILDKIT=1
export BUILDKIT_STEP_LOG_MAX_SIZE=10000000
docker build -v . -t test:latest
```

**Issue**: ArgoCD sync failing
```bash
argocd app sync <app-name> --force
argocd app logs <app-name> --tail=100
```

**Issue**: Nexus registry authentication
```bash
cat ~/.docker/config.json
docker login -u admin -p Nexus12345 nexus.192.168.168.31.nip.io
```

**Issue**: OPA policies too restrictive
```bash
kubectl get clusterpolicies
kubectl get clusterpolicy <policy-name> -o yaml
# Change validationFailureAction from "enforce" to "audit"
```

---

## Success Metrics

✅ **Complete when**:
- All 7 script deployments successful
- All test suites pass (85+ tests total)
- All services responding to health checks
- Dashboard shows all components healthy
- Production deployments working end-to-end

✅ **Performance targets**:
- k3s deployment: < 20 minutes
- ArgoCD sync: < 5 minutes
- Build time: 5-10 minutes (vs 30+ before BuildKit)
- Deploy time: < 2 minutes (canary)

✅ **Availability targets**:
- Cluster availability: 99.95%+
- Service availability: 99.9%+
- Build success rate: 95%+

---

## Next Steps After Phase 3

1. **Testing & Validation** (Issue #145)
   - Smoke tests across all services
   - Performance benchmarks
   - Failover scenarios

2. **Compliance & Hardening** (Issue #163)
   - SOC2 compliance checks
   - Security scanning
   - Network hardening

3. **Operations & Runbooks** (Issue #147)
   - Incident response playbooks
   - On-call setup
   - SLO definitions

---

## Quick Reference Commands

```bash
# Deploy everything (automated)
cd c:\code-server-enterprise
scp -r scripts/phase3-*.sh kubernetes/*.yaml akushnir@192.168.168.31:/tmp/
ssh akushnir@192.168.168.31 'for script in /tmp/phase3-*setup.sh; do bash $script || exit 1; done'

# Check status
ssh akushnir@192.168.168.31 'kubectl get nodes,pods -A'

# Access services
curl http://argocd.192.168.168.31.nip.io
curl http://nexus.192.168.168.31.nip.io
curl http://dev.192.168.168.31.nip.io

# View logs
kubectl logs -f deployment/code-server -n code-server
kubectl logs -f deployment/argocd-server -n argocd

# Troubleshoot
kubectl describe pod <pod> -n <namespace>
kubectl exec -it <pod> -n <namespace> -- /bin/bash
```

---

## Support & Documentation

- **k3s Docs**: https://docs.k3s.io/
- **ArgoCD Docs**: https://argo-cd.readthedocs.io/
- **Dagger Docs**: https://docs.dagger.io/
- **Kyverno Docs**: https://kyverno.io/docs/
- **BuildKit Docs**: https://github.com/moby/buildkit
- **Nexus Docs**: https://help.sonatype.com/repomanager3/

---

**PHASE 3 STATUS**: ✅ **COMPLETE & READY FOR PRODUCTION DEPLOYMENT**

All implementations follow Elite Best Practices:
- ✅ Infrastructure as Code (IaC)
- ✅ Immutable deployments
- ✅ Independent services
- ✅ No duplication
- ✅ Full integration
- ✅ Production-ready
