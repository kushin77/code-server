# Phase 4-7 Automated Deployment Guide

**Status:** ✅ READY FOR DEPLOYMENT  
**Created:** May 1, 2026  
**Updated:** May 1, 2026

---

## Overview

This guide explains how to use the automated GitHub Actions workflows for deploying Phases 4-7 of the code-server-enterprise platform. The workflows enable fully automated:

1. **Phase 4:** Kubernetes cluster provisioning and service deployment
2. **Phase 5:** Security hardening and secret management
3. **Phase 6-7:** Team collaboration extension building and publishing

---

## Available Workflows

### 1. Phase 4 - Kubernetes Deployment
**File:** `.github/workflows/phase-4-k8s-deployment.yml`

**Triggers:**
- Manual dispatch (`workflow_dispatch`)
- Automatic on changes to `kubernetes/`, `helm/`, or `scripts/k8s/`

**Jobs:**
- `validate` - Validates manifests with kubeval and helm lint
- `provision-cluster` - Provisions Azure AKS cluster
- `deploy-services` - Deploys Helm chart and services
- `migrate-data` - Migrates data from Docker to Kubernetes
- `validate-deployment` - Verifies deployment health

**Input Parameters:**
- `environment`: staging or production
- `cluster_name`: AKS cluster name (default: code-server-enterprise-prod)
- `node_count`: Number of nodes (default: 3)

### 2. Phase 7 - Extension Building
**File:** `.github/workflows/phase-7-extension.yml`

**Triggers:**
- Manual dispatch (`workflow_dispatch`)
- Automatic on changes to `apps/extensions/team-hub/`

**Jobs:**
- `build` - Builds the extension bundle
- `security-scan` - Scans for vulnerabilities
- `package` - Creates VSIX package
- `publish` - Publishes to VS Code Marketplace
- `validate-modules` - Verifies Phase 7 ML modules
- `integration-test` - Runs integration tests
- `documentation` - Generates API documentation

**Input Parameters:**
- `publish_marketplace`: true or false

### 3. Phase 4-7 Orchestration
**File:** `.github/workflows/phase-4-7-orchestration.yml`

**Triggers:**
- Manual dispatch only

**Jobs:**
- `pre-deployment` - Validates infrastructure and documentation
- `phase-4-k8s` - Runs Phase 4 deployment workflow
- `phase-5-security` - Deploys security hardening
- `phase-6-7-intelligence` - Builds and publishes extension
- `traffic-migration` - Configures Istio traffic routing
- `post-deployment` - Validates and generates reports

**Input Parameters:**
- `deployment_phase`: phase4-only, phase5-only, phase6-7-only, or all
- `environment`: staging or production

---

## Prerequisites & Configuration

### GitHub Secrets Required

Add these secrets to your GitHub repository (Settings → Secrets and Variables → Actions):

#### Azure Deployment
```yaml
AZURE_CREDENTIALS
  Type: JSON
  Value: Azure service principal credentials
  Format: {"clientId":"...", "clientSecret":"...", "subscriptionId":"...", "tenantId":"..."}

DOCKER_HOST_IP
  Type: String
  Value: Docker host IP address (192.168.168.31)
  
DOCKER_HOST_SSH_KEY
  Type: Private Key
  Value: SSH private key for Docker host access
```

#### Extension Publishing
```yaml
VSCODE_MARKETPLACE_TOKEN
  Type: Personal Access Token
  Value: Token from VS Code Marketplace publisher profile
  
OPEN_VSX_TOKEN
  Type: Personal Access Token
  Value: Token from Open VSX Registry
  
SNYK_TOKEN
  Type: Security Token
  Value: Snyk API token for vulnerability scanning
  
SLACK_WEBHOOK
  Type: URL
  Value: Slack webhook URL for notifications
  
GITHUB_TOKEN
  Type: Auto-generated
  Value: Already available in GitHub Actions
```

### Repository Configuration

1. **Enable GitHub Actions**
   - Go to Settings → Actions → General
   - Select "Allow all actions and reusable workflows"

2. **Configure Branch Protection**
   - Require status checks to pass before merging
   - Require deployments to pass before merging

3. **Set Up Environments**
   - Create `staging` and `production` environments
   - Add approval reviewers for production deployments
   - Configure secrets per environment

---

## Deployment Procedures

### Manual Deployment via GitHub UI

1. **Go to Actions tab**
   - Click on "Phase 4-7 Complete Deployment Orchestration"

2. **Click "Run workflow"**
   - Select `deployment_phase`: "all"
   - Select `environment`: "staging" or "production"
   - Click "Run workflow"

3. **Monitor Progress**
   - Watch job execution in real-time
   - Check logs for errors
   - View artifacts when complete

### Deployment via REST API

```bash
# Get workflow ID
WORKFLOW_ID=$(gh workflow list --repo kushin77/code-server --json id,name | \
  jq -r '.[] | select(.name == "Phase 4-7 Complete Deployment Orchestration") | .id')

# Trigger workflow
gh workflow run $WORKFLOW_ID \
  --repo kushin77/code-server \
  -f deployment_phase=all \
  -f environment=staging
```

### Deployment via Command Line

```bash
# Phase 4 Only
gh workflow run phase-4-k8s-deployment.yml \
  --repo kushin77/code-server \
  -f environment=staging \
  -f cluster_name=code-server-enterprise-staging \
  -f node_count=3

# Phase 7 Only
gh workflow run phase-7-extension.yml \
  --repo kushin77/code-server \
  -f publish_marketplace=true

# All Phases
gh workflow run phase-4-7-orchestration.yml \
  --repo kushin77/code-server \
  -f deployment_phase=all \
  -f environment=staging
```

---

## Deployment Timeline & Approval Gates

### Staging Deployment (Auto-Approve)
```
Trigger → Validate → Provision → Deploy → Migrate → Validate
↓         ↓          ↓           ↓        ↓        ↓
5 min     5 min      30 min      15 min   10 min   10 min
Total: ~75 minutes
```

### Production Deployment (Manual Approval)
```
Trigger → Validate → [REVIEW] → Provision → Deploy → Migrate → Validate
↓         ↓          ↓          ↓           ↓        ↓        ↓
5 min     5 min      ⏳ waiting  30 min      15 min   10 min   10 min
Total: ~75 minutes (+ review time)
```

---

## Troubleshooting

### Workflow Fails During Validation

**Issue:** Kubernetes manifest validation fails
```bash
Error: kubeval: error validating manifest
```

**Solution:**
1. Check manifest syntax in `kubernetes/`
2. Verify API versions match cluster version
3. Run locally: `kubeval kubernetes/**/*.yaml`
4. Fix errors and retry

### Azure Authentication Fails

**Issue:** Azure login fails
```bash
Error: Failed to authenticate with Azure
```

**Solution:**
1. Verify `AZURE_CREDENTIALS` secret is set correctly
2. Check service principal permissions
3. Ensure subscription is active
4. Test locally: `az login --service-principal -u <client-id> -p <secret> --tenant <tenant>`

### Helm Deployment Timeout

**Issue:** Helm deployment stuck waiting for pods
```bash
Error: timeout waiting for pod
```

**Solution:**
1. Increase timeout: Edit workflow `--timeout 10m`
2. Check pod events: `kubectl describe pod <pod-name>`
3. Check resource limits: `kubectl top nodes`
4. Scale up node count and retry

### Data Migration Fails

**Issue:** PostgreSQL migration errors
```bash
Error: pg_dump: command not found on Docker host
```

**Solution:**
1. Verify Docker host accessibility via SSH
2. Check `DOCKER_HOST_SSH_KEY` is set correctly
3. Ensure `pg_dump` is available in container
4. Run migration manually: `bash scripts/ops/migrate-to-k8s-data.sh`

### Extension Publishing Fails

**Issue:** VS Code Marketplace authentication error
```bash
Error: 401 Unauthorized
```

**Solution:**
1. Verify `VSCODE_MARKETPLACE_TOKEN` is correct
2. Check token expiration and permissions
3. Regenerate token if needed
4. Test locally: `vsce login` and `vsce publish`

---

## Monitoring & Observability

### Real-Time Monitoring

During deployment, monitor these dashboards:

**Kubernetes Cluster:**
```bash
kubectl get nodes -w
kubectl get pods -n code-server-enterprise -w
kubectl logs -n code-server-enterprise -f deployment/<service-name>
```

**Istio Service Mesh:**
```bash
# Port-forward Kiali dashboard
kubectl port-forward -n istio-system svc/kiali 20000:20000
# Open: http://localhost:20000

# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open: http://localhost:3000
```

**Application Metrics:**
```bash
# Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Open: http://localhost:9090

# Jaeger Tracing
kubectl port-forward -n monitoring svc/jaeger 16686:16686
# Open: http://localhost:16686
```

### Workflow Artifacts

Each workflow run generates artifacts:

| Artifact | Location | Contents |
|----------|----------|----------|
| extension-bundle | `.github/workflows/phase-7-extension.yml` | Built `dist/extension.js` |
| vsix-package | `.github/workflows/phase-7-extension.yml` | Packaged `team-hub.vsix` |
| deployment-report | `.github/workflows/phase-4-7-orchestration.yml` | Deployment status & metrics |
| api-documentation | `.github/workflows/phase-7-extension.yml` | Phase 7 API docs |

**Download artifacts:**
```bash
# List artifacts
gh run view <run-id> --repo kushin77/code-server

# Download artifact
gh run download <run-id> -n extension-bundle --repo kushin77/code-server
```

---

## Post-Deployment Steps

### 1. Verify Cluster Health
```bash
# Check nodes
kubectl get nodes

# Check pods
kubectl get pods -n code-server-enterprise

# Check services
kubectl get services -n code-server-enterprise
```

### 2. Run Integration Tests
```bash
# Run full deployment test
bash scripts/ops/full-deployment-test.sh --dry-run

# Run integration tests
bash scripts/integration-tests.sh
```

### 3. Configure DNS
```bash
# Get Ingress LoadBalancer IP
kubectl get ingress -n code-server-enterprise

# Update DNS records to point to LoadBalancer IP
# api.code-server.example.com → <LOADBALANCER_IP>
# app.code-server.example.com → <LOADBALANCER_IP>
```

### 4. Begin Traffic Migration
```bash
# Week 1: 90% Docker → 10% K8s
kubectl patch virtualservice api-gateway -n code-server-enterprise \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"docker-api-gateway.external"},"weight":90},{"destination":{"host":"api-gateway"},"weight":10}]}]}}'
```

### 5. Monitor Metrics
```bash
# Check pod resource usage
kubectl top pods -n code-server-enterprise

# Check node resource usage
kubectl top nodes

# View logs
kubectl logs -n code-server-enterprise -f pod/<pod-name>
```

---

## Rollback Procedures

### Immediate Rollback
```bash
# Scale down K8s deployments
kubectl scale deployment -n code-server-enterprise --all --replicas=0

# Restore 100% traffic to Docker
kubectl patch virtualservice api-gateway -n code-server-enterprise \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"docker-api-gateway.external"},"weight":100}]}]}}'
```

### Full Cluster Teardown
```bash
# Delete namespace (all pods, services, etc.)
kubectl delete namespace code-server-enterprise

# Delete AKS cluster
az aks delete --resource-group code-server-rg --name code-server-enterprise-prod
```

---

## Support & Issues

### Get Help
- **Workflow Logs:** GitHub Actions tab → Workflow run → View logs
- **Deployment Errors:** Check artifacts for detailed logs
- **Kubernetes Issues:** `kubectl describe pod <pod-name>`, `kubectl logs <pod-name>`
- **Extension Issues:** Check build artifacts and test results

### File Issues
```bash
# Create GitHub issue for deployment problems
gh issue create \
  --repo kushin77/code-server \
  --title "Phase 4-7 Deployment Issue" \
  --body "Describe the issue and include relevant logs"
```

### Emergency Contacts
- **Ops Team:** @platform-ops
- **Security Team:** @security
- **Infrastructure Team:** @infrastructure

---

## Maintenance & Updates

### Updating Workflows

When workflows need updates:

1. **Test Changes Locally**
   ```bash
   # Act: Run workflows locally
   act -j phase-4-k8s
   ```

2. **Create PR for Review**
   ```bash
   git checkout -b update/workflows
   # Make changes to .github/workflows/
   git push -u origin update/workflows
   # Create PR for review
   ```

3. **Approve & Merge**
   - Require 2 approvals for workflow changes
   - Run in staging first
   - Verify before production

### Updating Secrets

```bash
# Update secret in GitHub
gh secret set AZURE_CREDENTIALS --repo kushin77/code-server < /path/to/credentials.json

# Verify secret
gh secret list --repo kushin77/code-server
```

---

## Success Criteria

Deployment is successful when:

- ✅ All Kubernetes manifests validate
- ✅ AKS cluster provisions successfully
- ✅ All services deploy and reach "Ready" state
- ✅ Data migration completes with zero errors
- ✅ Integration tests pass
- ✅ Extension builds and publishes successfully
- ✅ Phase 7 ML modules activate correctly
- ✅ Monitoring dashboards show healthy metrics
- ✅ Ingress routes traffic correctly
- ✅ DNS resolves to K8s LoadBalancer

---

## Next Steps

1. **Prepare Deployment Environment**
   - Set up Azure subscription and service principal
   - Configure GitHub secrets
   - Set up monitoring and alerting

2. **Execute Phase 4 Deployment**
   - Trigger workflow from GitHub Actions
   - Monitor deployment progress
   - Verify cluster health

3. **Execute Phase 5-7 Deployments**
   - Deploy security hardening (Phase 5)
   - Build and publish extension (Phase 6-7)
   - Configure intelligent features

4. **Plan Traffic Migration**
   - Schedule 4-week migration window
   - Plan rollback procedures
   - Communicate with stakeholders

---

*For additional information, see:*
- `PHASE_4_TO_7_FINAL_HANDOFF.md` - Complete handoff documentation
- `DEPLOYMENT_READINESS_MAY_1_2026.md` - Deployment checklist
- `K8S_MIGRATION_PROGRESS.md` - Technical roadmap
