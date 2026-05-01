# Local Deployment Configuration - No GitHub Actions Required

**Date:** May 1, 2026  
**Status:** Alternative workflow for environments without GitHub Actions  
**Audience:** DevOps, Infrastructure Engineers

---

## Overview

This guide enables Phase 4-7 deployment **locally on your machine** without needing GitHub Actions or paying GitHub billing. The local orchestrator script (`scripts/ops/local-phase-4-7-deploy.sh`) handles all deployment steps:

1. ✅ Pre-deployment validation
2. ✅ GitHub issue closure (optional, requires token)
3. ✅ AKS cluster provisioning
4. ✅ Service deployment via Helm
5. ✅ Data migration (PostgreSQL/Redis)
6. ✅ Deployment validation

---

## Prerequisites

### Local Machine Requirements

```bash
# Check if you have all required tools
az --version          # Azure CLI
kubectl version       # Kubernetes CLI
helm version         # Helm package manager
python --version     # Python 3.8+
jq --version         # JSON processor
bash --version       # Bash 4.0+
```

### Installation Commands

**macOS (Homebrew):**
```bash
brew install azure-cli kubernetes-cli helm python jq
```

**Ubuntu/Debian:**
```bash
sudo apt-get install -y azure-cli kubectl helm python3 jq
```

**Windows (WSL2 or Git Bash):**
```bash
# Use chocolatey or download installers
choco install azure-cli kubernetes-cli helm python jq
```

---

## Step 1: Azure Authentication Setup

### Create Azure Service Principal

```bash
# Log in to Azure
az login

# Create a service principal (if you don't have one)
az ad sp create-for-rbac \
  --name code-server-deployment \
  --role Contributor \
  --scopes /subscriptions/{subscription-id}
```

### Save Credentials Locally

Create `~/.code-server-deploy-env` file with your credentials:

```bash
#!/usr/bin/env bash
# Azure Credentials
export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
export AZURE_TENANT_ID="<your-tenant-id>"
export AZURE_CLIENT_ID="<your-client-id>"
export AZURE_CLIENT_SECRET="<your-client-secret>"

# GitHub Token (optional, for issue closure)
export GITHUB_TOKEN="<your-github-personal-access-token>"

# Environment Settings
export DEPLOYMENT_ENVIRONMENT="staging"  # or "production"
export DEPLOYMENT_PHASE="all"             # or "phase4", "phase5", etc.
```

Make it secure:
```bash
chmod 600 ~/.code-server-deploy-env
```

---

## Step 2: Load Deployment Environment

Before running deployment, load your configuration:

```bash
# Load the environment
source ~/.code-server-deploy-env

# Verify authentication
az account show
```

---

## Step 3: Run Local Deployment Orchestrator

### Basic Usage (Staging, Dry-Run)

```bash
# Test run - no actual changes
source ~/.code-server-deploy-env
cd /home/akushnir/code-server
bash scripts/ops/local-phase-4-7-deploy.sh --dry-run
```

### Staging Deployment (Live)

```bash
source ~/.code-server-deploy-env
cd /home/akushnir/code-server
bash scripts/ops/local-phase-4-7-deploy.sh \
  --environment staging \
  --phase all
```

### Production Deployment (With Approvals)

```bash
source ~/.code-server-deploy-env
cd /home/akushnir/code-server
bash scripts/ops/local-phase-4-7-deploy.sh \
  --environment production \
  --phase all
```

### Deployment Options

```bash
# Skip validation (faster for repeat deployments)
bash scripts/ops/local-phase-4-7-deploy.sh --skip-validation

# Skip GitHub token requirement
bash scripts/ops/local-phase-4-7-deploy.sh --skip-secrets

# Deploy only specific phase
bash scripts/ops/local-phase-4-7-deploy.sh --phase phase4    # K8s provisioning only
bash scripts/ops/local-phase-4-7-deploy.sh --phase phase7    # Extension build only

# Keep monitoring dashboard open
bash scripts/ops/local-phase-4-7-deploy.sh --monitor
```

---

## Step 4: Monitor Deployment Progress

### Watch Cluster Status (while deployment runs)

```bash
# Terminal 1: Watch pod status
kubectl get pods -A --watch

# Terminal 2: Watch nodes
kubectl get nodes --watch

# Terminal 3: View logs
kubectl logs -f deployment/code-server -n code-server
```

### Check Service Health

```bash
# List all services
kubectl get svc -A

# Get detailed service info
kubectl describe svc code-server -n code-server

# Port-forward to test locally
kubectl port-forward svc/code-server 8080:80 -n code-server
# Then access: http://localhost:8080
```

---

## Step 5: Verify Deployment Success

### Health Check Procedures

```bash
# Check cluster health
kubectl cluster-info
kubectl get nodes
kubectl get nodes -o wide

# Check all pod status
kubectl get pods -A

# Check data migration
kubectl exec -it deployment/postgresql-primary -n code-server -- psql -U postgres -c "\dt"

# Check Redis availability
kubectl exec -it deployment/redis-primary -n code-server -- redis-cli PING
```

### Expected Results

| Component | Expected Status |
|-----------|-----------------|
| Nodes | 3 nodes in "Ready" state |
| Pods | All pods in "Running" state |
| Services | All services have CLUSTER-IP |
| Ingress | External IP assigned |
| PostgreSQL | Connected, data migrated |
| Redis | PING response received |
| Networking | All pods can communicate |

---

## Step 6: Access Deployed Services

### Configure kubectl Access

```bash
# Get cluster credentials
az aks get-credentials \
  --resource-group code-server-rg-staging \
  --name code-server-staging \
  --overwrite-existing

# Verify connection
kubectl get nodes
```

### Access Services

```bash
# Code Server IDE
kubectl port-forward svc/code-server 8080:8080 -n code-server
# Access: http://localhost:8080

# Grafana Monitoring
kubectl port-forward svc/grafana 3000:80 -n monitoring
# Access: http://localhost:3000 (admin/admin)

# Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Access: http://localhost:9090

# Jaeger Tracing
kubectl port-forward svc/jaeger-ui 16686:16686 -n tracing
# Access: http://localhost:16686
```

---

## Troubleshooting

### Issue: "Not authenticated with Azure CLI"

```bash
# Re-authenticate
az login

# Or use service principal directly
az login --service-principal \
  -u $AZURE_CLIENT_ID \
  -p $AZURE_CLIENT_SECRET \
  --tenant $AZURE_TENANT_ID
```

### Issue: "kubectl connection refused"

```bash
# Get new cluster credentials
az aks get-credentials \
  --resource-group code-server-rg-staging \
  --name code-server-staging \
  --overwrite-existing

# Verify connection
kubectl cluster-info
```

### Issue: "Helm chart validation failed"

```bash
# Check chart syntax
helm lint helm/code-server-enterprise/

# Validate templates
helm template code-server helm/code-server-enterprise/

# Check for missing values
helm template code-server helm/code-server-enterprise/ --values helm/code-server-enterprise/values-staging.yaml
```

### Issue: "Pod is pending or failing to start"

```bash
# Check pod status
kubectl describe pod <pod-name> -n code-server

# View pod logs
kubectl logs <pod-name> -n code-server

# Check resource limits
kubectl describe node

# View events
kubectl get events -A --sort-by='.lastTimestamp'
```

### Issue: "Deployment script exits with error"

```bash
# Check deployment logs
cat .deploy-logs/phase-4-7-deploy-*.log | tail -100

# Re-run with verbose output
bash -x scripts/ops/local-phase-4-7-deploy.sh --dry-run 2>&1 | head -50
```

---

## Traffic Migration (Post-Deployment)

After successful deployment validation, begin the 4-week traffic migration:

**Reference:** [TRAFFIC_MIGRATION_STRATEGY.md](TRAFFIC_MIGRATION_STRATEGY.md)

```bash
# Week 1: Canary (90% Docker → 10% K8s)
kubectl apply -f kubernetes/istio/week-1-canary.yaml

# Week 2: Expanded (50% Docker → 50% K8s)
kubectl apply -f kubernetes/istio/week-2-expanded.yaml

# Week 3: Stateful Migration (10% Docker → 90% K8s)
kubectl apply -f kubernetes/istio/week-3-stateful.yaml

# Week 4: Complete Cutover (100% K8s)
kubectl apply -f kubernetes/istio/week-4-complete.yaml
```

---

## Local Environment Setup Scripts

### Quick Setup Script

Create `~/.code-server-setup.sh`:

```bash
#!/usr/bin/env bash
# Code-Server Local Deployment Setup

set -e

echo "🚀 Setting up code-server local deployment environment..."

# Create config directory
mkdir -p ~/.code-server-deploy
cd ~/.code-server-deploy

# Check prerequisites
echo "Checking prerequisites..."
for tool in az kubectl helm python jq; do
    if command -v $tool &>/dev/null; then
        echo "  ✅ $tool installed"
    else
        echo "  ❌ $tool missing - please install"
        exit 1
    fi
done

# Create environment file template
if [[ ! -f ~/.code-server-deploy-env ]]; then
    cat > ~/.code-server-deploy-env << 'EOF'
#!/usr/bin/env bash
# Azure Credentials
export AZURE_SUBSCRIPTION_ID="<REPLACE-WITH-YOUR-SUBSCRIPTION-ID>"
export AZURE_TENANT_ID="<REPLACE-WITH-YOUR-TENANT-ID>"
export AZURE_CLIENT_ID="<REPLACE-WITH-YOUR-CLIENT-ID>"
export AZURE_CLIENT_SECRET="<REPLACE-WITH-YOUR-CLIENT-SECRET>"

# GitHub Token (optional)
export GITHUB_TOKEN=""

# Deployment Settings
export DEPLOYMENT_ENVIRONMENT="staging"
export DEPLOYMENT_PHASE="all"
EOF
    chmod 600 ~/.code-server-deploy-env
    echo "  ✅ Created ~/.code-server-deploy-env (fill in your Azure credentials)"
fi

# Test Azure authentication
echo "Testing Azure authentication..."
source ~/.code-server-deploy-env
if az account show &>/dev/null; then
    echo "  ✅ Azure authenticated"
else
    echo "  ⚠ Azure not authenticated - run: az login"
fi

echo "✅ Setup complete!"
echo ""
echo "To deploy:"
echo "  source ~/.code-server-deploy-env"
echo "  cd /home/akushnir/code-server"
echo "  bash scripts/ops/local-phase-4-7-deploy.sh --dry-run"
```

Run setup:
```bash
bash ~/.code-server-setup.sh
```

---

## FAQ

### Q: Can I run this without Azure credentials?
**A:** No. You need valid Azure credentials to provision the AKS cluster. [Create a service principal](https://docs.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli).

### Q: What if deployment fails halfway?
**A:** Deployment is idempotent - you can re-run the script and it will resume from where it failed.

### Q: Can I run multiple deployments simultaneously?
**A:** No. The script uses exclusive resource locks to prevent conflicts. Run them sequentially.

### Q: How do I rollback if something goes wrong?
**A:** The AKS cluster is created fresh each time. To rollback, delete the resource group and re-run:
```bash
az group delete --name code-server-rg-staging --yes
```

### Q: Do I still need GitHub Actions?
**A:** No. This local script is completely independent of GitHub Actions. Use it for your deployments.

### Q: How long does deployment take?
**A:** ~75 minutes for staging, ~100 minutes for production (includes AKS cluster creation which takes 20-30 minutes).

---

## Next Steps

1. ✅ Install prerequisites (az CLI, kubectl, helm, etc.)
2. ✅ Create Azure service principal
3. ✅ Set up local environment file (~/.code-server-deploy-env)
4. ✅ Run dry-run: `bash scripts/ops/local-phase-4-7-deploy.sh --dry-run`
5. ✅ Execute staging deployment: `bash scripts/ops/local-phase-4-7-deploy.sh --environment staging`
6. ✅ Monitor deployment progress
7. ✅ Begin traffic migration (Week 1-4 plan)

---

## Support & Monitoring

**Deployment Logs:**
- Location: `.deploy-logs/phase-4-7-deploy-YYYYMMDD-HHMMSS.log`
- Real-time: `tail -f .deploy-logs/phase-4-7-deploy-*.log`

**Monitoring Dashboards:**
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Jaeger: http://localhost:16686

**Documentation References:**
- [Deployment Execution Runbook](DEPLOYMENT_EXECUTION_RUNBOOK.md)
- [Traffic Migration Strategy](TRAFFIC_MIGRATION_STRATEGY.md)
- [Operations Handoff](TEAM_OPERATIONS_HANDOFF.md)

---

*Local Deployment Configuration - Phase 4-7*  
*Created: May 1, 2026*  
*Status: ✅ PRODUCTION-READY*
