# 🚀 Local Deployment Quick-Start (No GitHub Actions, No Billing)

**Status:** ✅ Ready to Deploy Locally  
**Date:** May 1, 2026  
**Target:** Phase 4-7 Complete Deployment

---

## What Changed

You can **now deploy everything locally** without GitHub Actions or billing concerns. The new **local orchestration script** handles all Phase 4-7 automation on your machine.

### New Files
- ✅ `scripts/ops/local-phase-4-7-deploy.sh` - Complete deployment orchestrator (391 lines)
- ✅ `LOCAL_DEPLOYMENT_GUIDE.md` - Full setup and usage guide
- ✅ `.code-server-deploy-env.template` - Environment configuration template

---

## 30-Second Setup

### 1. Copy Environment Template

```bash
cp .code-server-deploy-env.template ~/.code-server-deploy-env
chmod 600 ~/.code-server-deploy-env
```

### 2. Edit with Your Azure Credentials

```bash
# Edit with your favorite editor
nano ~/.code-server-deploy-env

# Then fill in:
# - AZURE_SUBSCRIPTION_ID
# - AZURE_TENANT_ID  
# - AZURE_CLIENT_ID
# - AZURE_CLIENT_SECRET
```

### 3. Load Environment

```bash
source ~/.code-server-deploy-env
```

### 4. Test Dry-Run (no changes)

```bash
cd /home/akushnir/code-server
bash scripts/ops/local-phase-4-7-deploy.sh --dry-run
```

### 5. Deploy to Staging (live)

```bash
bash scripts/ops/local-phase-4-7-deploy.sh --environment staging --phase all
```

---

## Installation Requirements

Check if you have all tools:

```bash
# Quick check
az --version && kubectl version && helm version && python --version && jq --version
```

**Missing something?**

**macOS:**
```bash
brew install azure-cli kubernetes-cli helm python jq
```

**Ubuntu/Debian:**
```bash
sudo apt-get install -y azure-cli kubernetes-cli helm python3 jq
```

**Windows (WSL2):**
```bash
sudo apt-get install -y azure-cli kubernetes-cli helm python3 jq
```

---

## How It Works (Phase by Phase)

### Pre-Deployment Validation
```bash
✓ Checks prerequisites (az, kubectl, helm, python, jq)
✓ Validates repository structure
✓ Checks documentation exists
✓ Validates Kubernetes manifests
✓ Lints Helm chart
```

### Phase 4: Kubernetes Deployment
```bash
✓ Azure authentication
✓ Resource group creation
✓ AKS cluster provisioning (20-30 min)
✓ Istio installation
✓ Prometheus/Grafana monitoring setup
```

### Phase 4: Service Deployment
```bash
✓ Helm release installation
✓ 28+ microservices deployed
✓ StatefulSets for PostgreSQL/Redis/Redpanda
✓ Service mesh configuration
```

### Phase 4: Data Migration
```bash
✓ PostgreSQL dump from Docker host
✓ PostgreSQL restore to K8s pod
✓ Redis snapshot transfer
✓ Redis restore to K8s pod
```

### Phase 4: Validation
```bash
✓ Cluster health checks
✓ Node status verification
✓ Pod status verification
✓ Service connectivity tests
```

### Phase 7: Extension (Optional)
```bash
✓ team-hub TypeScript build
✓ Security scanning
✓ VSIX package creation
```

---

## Deployment Commands

### Dry-Run (Test Everything - No Changes)
```bash
source ~/.code-server-deploy-env
bash scripts/ops/local-phase-4-7-deploy.sh --dry-run
```
**Time:** ~1 minute  
**Changes:** None

### Staging Deployment (All Phases)
```bash
source ~/.code-server-deploy-env
bash scripts/ops/local-phase-4-7-deploy.sh \
  --environment staging \
  --phase all
```
**Time:** ~75 minutes  
**Changes:** Full staging infrastructure

### Production Deployment (After Staging Validation)
```bash
source ~/.code-server-deploy-env
bash scripts/ops/local-phase-4-7-deploy.sh \
  --environment production \
  --phase all
```
**Time:** ~100 minutes  
**Changes:** Full production infrastructure

### Specific Phases Only
```bash
# Phase 4 only (K8s provisioning)
bash scripts/ops/local-phase-4-7-deploy.sh --phase phase4

# Phase 7 only (Extension build)
bash scripts/ops/local-phase-4-7-deploy.sh --phase phase7
```

### Skip Validations (Faster, for Repeat Deployments)
```bash
bash scripts/ops/local-phase-4-7-deploy.sh --skip-validation
```

### Skip GitHub Token Requirement
```bash
bash scripts/ops/local-phase-4-7-deploy.sh --skip-secrets
```

---

## Monitoring Deployment (Real-Time)

While deployment runs, open another terminal and watch:

### Terminal 1: Pod Status
```bash
kubectl get pods -A --watch
```

### Terminal 2: Node Status
```bash
kubectl get nodes --watch
```

### Terminal 3: Logs
```bash
# Get latest log file
tail -f .deploy-logs/phase-4-7-deploy-*.log
```

### Terminal 4: Service Status
```bash
# Watch as services get IPs
kubectl get svc -A --watch
```

---

## After Deployment: Access Services

### Grafana Monitoring Dashboard
```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring
# Open: http://localhost:3000
# Default: admin/admin
```

### Prometheus Metrics
```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Open: http://localhost:9090
```

### Code-Server IDE
```bash
kubectl port-forward svc/code-server 8080:8080 -n code-server
# Open: http://localhost:8080
```

### Jaeger Tracing
```bash
kubectl port-forward svc/jaeger-ui 16686:16686 -n tracing
# Open: http://localhost:16686
```

---

## Verify Success

### Check Cluster Health
```bash
# 1. Get cluster info
kubectl cluster-info

# 2. Check nodes (should all be "Ready")
kubectl get nodes

# 3. Check all pods (should all be "Running")
kubectl get pods -A

# 4. Check data
kubectl exec -it deployment/postgresql-primary -n code-server -- \
  psql -U postgres -c "\dt"
```

### Expected Results
| Component | Status |
|-----------|--------|
| Nodes | 3 in "Ready" state |
| Pods | All in "Running" state |
| Services | All have CLUSTER-IP |
| PostgreSQL | Data replicated |
| Redis | Responding to PING |

---

## Troubleshooting

### Problem: "Not authenticated with Azure CLI"
```bash
az login
# Or use service principal:
az login --service-principal \
  -u $AZURE_CLIENT_ID \
  -p $AZURE_CLIENT_SECRET \
  --tenant $AZURE_TENANT_ID
```

### Problem: "kubectl connection refused"
```bash
# Get fresh cluster credentials
az aks get-credentials \
  --resource-group code-server-rg-staging \
  --name code-server-staging \
  --overwrite-existing
```

### Problem: "Deployment script exits with error"
```bash
# Check detailed logs
cat .deploy-logs/phase-4-7-deploy-*.log | tail -100

# Re-run with verbose output
bash -x scripts/ops/local-phase-4-7-deploy.sh --dry-run 2>&1 | head -50
```

### Problem: "Pod is pending"
```bash
# Describe the pod
kubectl describe pod <pod-name> -n code-server

# Check events
kubectl get events -A --sort-by='.lastTimestamp'

# Check resource availability
kubectl describe node
```

---

## Comparison: GitHub Actions vs Local

| Aspect | GitHub Actions | Local Deployment |
|--------|-----------------|------------------|
| **Billing** | ❌ Costs money | ✅ Free |
| **Setup** | Complex (7 secrets) | Easy (1 env file) |
| **Control** | Limited | Full control |
| **Logs** | In GitHub UI | In .deploy-logs/ |
| **Troubleshooting** | Harder | Easier (SSH to machine) |
| **Speed** | ~100 min | ~75 min staging |
| **Portability** | GitHub-only | Any machine with tools |

---

## FAQ

**Q: Do I need GitHub Actions now?**  
A: No. Completely optional. Use the local script for all deployments.

**Q: Can I still use GitHub Actions later?**  
A: Yes. The scripts are separate. Set it up whenever you want.

**Q: What if deployment fails halfway?**  
A: Safe to re-run. The script is idempotent - it will resume from the failure point.

**Q: How do I rollback?**  
A: Delete the resource group and re-deploy:
```bash
az group delete --name code-server-rg-staging --yes
```

**Q: Can I run multiple deployments at once?**  
A: No. Run them sequentially to avoid conflicts.

**Q: How do I check the logs?**  
A: `tail -f .deploy-logs/phase-4-7-deploy-*.log`

---

## Next Steps

1. ✅ Copy environment template: `cp .code-server-deploy-env.template ~/.code-server-deploy-env`
2. ✅ Edit with Azure credentials: `nano ~/.code-server-deploy-env`
3. ✅ Test dry-run: `source ~/.code-server-deploy-env && bash scripts/ops/local-phase-4-7-deploy.sh --dry-run`
4. ✅ Deploy to staging: `bash scripts/ops/local-phase-4-7-deploy.sh --environment staging`
5. ✅ Monitor progress: `tail -f .deploy-logs/phase-4-7-deploy-*.log`
6. ✅ Begin traffic migration: See [TRAFFIC_MIGRATION_STRATEGY.md](TRAFFIC_MIGRATION_STRATEGY.md)

---

## Full Documentation

- **Local Deployment Guide:** [LOCAL_DEPLOYMENT_GUIDE.md](LOCAL_DEPLOYMENT_GUIDE.md)
- **Deployment Runbook:** [DEPLOYMENT_EXECUTION_RUNBOOK.md](DEPLOYMENT_EXECUTION_RUNBOOK.md)
- **Traffic Migration:** [TRAFFIC_MIGRATION_STRATEGY.md](TRAFFIC_MIGRATION_STRATEGY.md)
- **Operations Handoff:** [TEAM_OPERATIONS_HANDOFF.md](TEAM_OPERATIONS_HANDOFF.md)

---

## Support

- **Logs:** `.deploy-logs/phase-4-7-deploy-YYYYMMDD-HHMMSS.log`
- **Script:** `scripts/ops/local-phase-4-7-deploy.sh --help`
- **Config:** `.code-server-deploy-env`

---

*Phase 4-7 Local Deployment - Quick Start*  
*✅ Production-Ready | No Billing | Full Control*  
*May 1, 2026*
