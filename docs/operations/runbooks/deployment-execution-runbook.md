# Phase 4-7 Deployment: Complete Execution Runbook

**Status:** ✅ READY TO EXECUTE  
**Date:** May 1, 2026  
**Duration:** 4 weeks (Phase 4 migration timeline)

---

## Quick Start (TL;DR)

```bash
# Step 1: Configure GitHub secrets (10 minutes)
# Follow: GITHUB_SECRETS_SETUP_GUIDE.md
# Add all 7 required secrets to GitHub repository

# Step 2: Test issue closure script (2 minutes)
python3 scripts/ops/close-deployment-issues.py --dry-run

# Step 3: Close GitHub issues (1 minute)
GITHUB_TOKEN=<your-token> python3 scripts/ops/close-deployment-issues.py

# Step 4: Trigger deployment workflow (1 minute)
# Go to: GitHub Actions → phase-4-7-orchestration
# Click: Run workflow
# Set: environment=staging, deployment_phase=all
# Click: Run workflow

# Step 5: Monitor deployment (30-75 minutes)
# Watch workflow progress in GitHub Actions tab
# Expected timeline: validation (5min) + provision (30min) + deploy (15min) + migrate (10min) + validate (10min)
```

---

## Pre-Deployment Setup

### 1. GitHub Secrets Configuration (REQUIRED)

**Reference Document:** `GITHUB_SECRETS_SETUP_GUIDE.md`

**Secrets to Configure:**
```
✅ AZURE_CREDENTIALS        - Azure service principal JSON
✅ DOCKER_HOST_IP           - 192.168.168.31
✅ DOCKER_HOST_SSH_KEY      - SSH private key (PEM format)
✅ VSCODE_MARKETPLACE_TOKEN - VS Code Marketplace token
✅ OPEN_VSX_TOKEN           - Open VSX Registry token
✅ SNYK_TOKEN               - Snyk security token
✅ SLACK_WEBHOOK            - Slack webhook URL (optional but recommended)
```

**Status Check:**
```bash
gh secret list --repo kushin77/code-server
# Should show all 7 secrets
```

### 2. Verify Infrastructure

```bash
# Check Kubernetes manifests exist
ls -la kubernetes/*.yaml
# Should show: namespace.yaml, deployments/, services/, statefulsets/, rbac.yaml, etc.

# Check Helm chart exists
ls -la helm/code-server-enterprise/
# Should show: Chart.yaml, templates/, values.yaml

# Check provisioning scripts exist
ls -la scripts/k8s/
# Should show: provision-aks-cluster.sh, etc.

# Check data migration script exists
ls -la scripts/ops/migrate-to-k8s-data.sh
```

### 3. Verify Documentation

```bash
# All deployment guides should exist
ls -la CI_CD_AUTOMATION_GUIDE.md
ls -la PHASE_4_7_CI_CD_DEPLOYMENT_COMPLETE.md
ls -la GITHUB_SECRETS_SETUP_GUIDE.md
ls -la TRAFFIC_MIGRATION_STRATEGY.md
ls -la DEPLOYMENT_READINESS_MAY_1_2026.md
```

---

## Deployment Workflows

### Workflow 1: Phase 4-7 Orchestration (Master)

**File:** `.github/workflows/phase-4-7-orchestration.yml`

**Purpose:** Coordinate all phases (4-7) in proper sequence

**Inputs:**
- `deployment_phase`: phase4-only | phase5-only | phase6-7-only | all
- `environment`: staging | production

**Execution:**
```bash
# Via GitHub UI:
# 1. Go to GitHub Actions tab
# 2. Select "Phase 4-7 Complete Deployment Orchestration"
# 3. Click "Run workflow"
# 4. Set inputs (environment=staging, deployment_phase=all)
# 5. Click "Run workflow"
```

**Jobs Executed:**
1. pre-deployment (5 min) - Infrastructure validation
2. phase-4-k8s (40 min) - Kubernetes deployment
3. phase-5-security (10 min) - Security hardening
4. phase-6-7-intelligence (30 min) - Extension build/publish
5. traffic-migration (5 min) - Configure Istio routing
6. post-deployment (10 min) - Final validation
7. create-milestone (2 min) - GitHub milestone (prod only)

**Expected Timeline:** ~75 minutes (staging), ~100 minutes (production with approvals)

### Workflow 2: Phase 4 Kubernetes Deployment

**File:** `.github/workflows/phase-4-k8s-deployment.yml`

**Purpose:** Provision AKS cluster and deploy all 38 microservices

**Inputs:**
- `environment`: staging | production
- `cluster_name`: AKS cluster identifier
- `node_count`: 3-9

**Jobs:**
1. validate (5 min) - Manifest validation
2. provision-cluster (30 min) - Create AKS cluster
3. deploy-services (15 min) - Install Helm chart
4. migrate-data (10 min) - PostgreSQL/Redis migration
5. validate-deployment (10 min) - Health checks

**Success Criteria:**
- All manifests pass kubeval
- Helm chart deploys successfully
- All 50+ pods reach "Running" state
- Data migration completes with zero errors
- Health checks pass for all services

### Workflow 3: Phase 7 Extension Building

**File:** `.github/workflows/phase-7-extension.yml`

**Purpose:** Build, test, and publish team-hub extension

**Jobs:**
1. build (10 min) - Compile TypeScript
2. security-scan (5 min) - Vulnerability scanning
3. package (5 min) - Create VSIX
4. publish (5 min) - Publish to marketplaces
5. validate-modules (2 min) - Verify ML modules
6. integration-test (5 min) - Run tests
7. documentation (2 min) - Generate API docs

**Success Criteria:**
- TypeScript compiles without errors
- VSIX package created (<10MB)
- Published to VS Code Marketplace
- All Phase 7 ML modules bundled

---

## Detailed Execution Steps

### Phase 1: Pre-Deployment (Today - May 1)

#### Step 1.1: Configure Secrets (10 minutes)
```bash
# Per GITHUB_SECRETS_SETUP_GUIDE.md:

# 1. Get Azure service principal
az ad sp create-for-rbac --name "code-server-deployment-bot" --role Contributor

# 2. Store secrets in GitHub
gh secret set AZURE_CREDENTIALS < azure-credentials.json
gh secret set DOCKER_HOST_IP --body "192.168.168.31"
gh secret set DOCKER_HOST_SSH_KEY < ~/.ssh/docker-host-key
gh secret set VSCODE_MARKETPLACE_TOKEN --body "<token>"
gh secret set OPEN_VSX_TOKEN --body "<token>"
gh secret set SNYK_TOKEN --body "<token>"
gh secret set SLACK_WEBHOOK --body "<webhook-url>"

# 3. Verify
gh secret list --repo kushin77/code-server
```

#### Step 1.2: Close GitHub Issues (5 minutes)
```bash
# Test in dry-run mode first
python3 scripts/ops/close-deployment-issues.py --dry-run

# Execute closure
GITHUB_TOKEN=<token> python3 scripts/ops/close-deployment-issues.py

# Expected output:
# ✅ #3102 closed with evidence
# ✅ #3103 closed with evidence
# ✅ #3107 closed with evidence
# ✅ #3105 updated with CI/CD transition note
```

#### Step 1.3: Verify Git State (2 minutes)
```bash
# Check working directory clean
git status
# Expected: "working tree clean"

# Check commits
git log --oneline | head -10
# Should show recent Phase 4-7 commits
```

### Phase 2: Staging Deployment (May 3-7)

#### Step 2.1: Trigger Workflow (1 minute)
```bash
# Via GitHub UI:
# 1. Go to: https://github.com/kushin77/code-server/actions
# 2. Click: "Phase 4-7 Complete Deployment Orchestration"
# 3. Click: "Run workflow"
# 4. Set:
#    - environment: staging
#    - deployment_phase: all
# 5. Click: "Run workflow"
```

#### Step 2.2: Monitor Deployment (30-75 minutes)
```bash
# Watch real-time progress
# URL: https://github.com/kushin77/code-server/actions/runs/<run-id>

# Key milestones to watch:
# ✅ pre-deployment: PASS (5 min)
# ✅ provision-cluster: PASS (30 min) - Most time-consuming
# ✅ deploy-services: PASS (15 min)
# ✅ migrate-data: PASS (10 min)
# ✅ validate-deployment: PASS (10 min)
```

#### Step 2.3: Verify Cluster Health (10 minutes)
```bash
# After deployment completes:

# Configure kubectl access
az aks get-credentials --resource-group code-server-rg \
  --name code-server-enterprise-staging

# Check nodes
kubectl get nodes
# Expected: 3 nodes in "Ready" state

# Check pods
kubectl get pods -n code-server-enterprise
# Expected: 50+ pods in "Running" state

# Check services
kubectl get svc -n code-server-enterprise
# Expected: All services "Active"

# Check ingress
kubectl get ingress -n code-server-enterprise
# Expected: Ingress with external IP assigned

# View pod logs (if any errors)
kubectl logs -n code-server-enterprise deployment/api-gateway
```

#### Step 2.4: Begin Traffic Migration Week 1 (May 3-10)

**Reference Document:** `TRAFFIC_MIGRATION_STRATEGY.md` (Week 1 section)

```bash
# Step 1: Configure Istio VirtualService (90% Docker → 10% K8s)
kubectl apply -f istio/traffic-migration/week1-canary.yaml

# Step 2: Monitor metrics (5 minutes)
kubectl top pods -n code-server-enterprise
kubectl top nodes

# Step 3: Check traffic distribution
kubectl exec -it -n istio-system <prometheus-pod> -- \
  curl 'localhost:9090/api/v1/query?query=rate(requests_total[5m])'

# Step 4: Monitor for 24+ hours
# Success criteria:
# - Error rate < 0.1%
# - Latency P99 < 150ms
# - No anomalies in logs
# - 10% traffic consistently routing to K8s

# Step 5: Day 7 - Rollback drill
# Reduce to 5% → monitor → restore to 10%
# Verifies automatic rollback capability
```

### Phase 3: Production Deployment (May 10+)

#### Step 3.1: Approval & Go Decision
```bash
# After Week 1 canary validation:
# Team leads sign off on production deployment
# Security review complete
# Performance baselines established

# Decision criteria:
# ✅ Staging deployment stable for 7 days
# ✅ Error rate < 0.1% consistently
# ✅ No data inconsistencies
# ✅ Rollback drills successful
# ✅ On-call team briefed and ready
```

#### Step 3.2: Production Workflow Trigger
```bash
# Via GitHub UI (requires approval):
# 1. Go to: GitHub Actions
# 2. Click: "Phase 4-7 Complete Deployment Orchestration"
# 3. Click: "Run workflow"
# 4. Set:
#    - environment: production
#    - deployment_phase: all
# 5. Click: "Run workflow"
# 6. Wait for approval from code owners
# 7. Workflow proceeds after approval
```

#### Step 3.3: 4-Week Traffic Migration

```
Week 1 (May 3-10):   10% K8s traffic - Canary validation
Week 2 (May 10-17):  50% K8s traffic - Expanded canary
Week 3 (May 17-24):  90% K8s traffic - Stateful migration
Week 4 (May 24-31):  100% K8s traffic - Full cutover
```

**Reference:** `TRAFFIC_MIGRATION_STRATEGY.md` - Complete week-by-week plan

---

## Monitoring During Deployment

### Key Metrics to Watch

**Cluster Health:**
- Pod Ready status: 100% (all pods "Running")
- Node Ready status: 100% (all nodes "Ready")
- CPU usage: 40-60% of node capacity
- Memory usage: 60-75% of node capacity

**Application Metrics:**
- Request rate: 5k-10k requests/second
- Error rate: < 0.1% (target: < 0.01%)
- Latency P99: < 100ms (target: < 50ms)
- Database replication lag: < 1 second

**Data Integrity:**
- PostgreSQL replication: In sync
- Redis keys: All present in K8s
- Redpanda partitions: All replicated
- Backup status: All successful

### Alerting

**Critical (P1):**
- Error rate > 1% for 5 minutes → Immediate rollback
- Pod not ready > 5 minutes → Escalate to infrastructure
- Database replication lag > 10 seconds → Check data sync

**High (P2):**
- Latency P99 > 200ms for 10 minutes → Investigate scaling
- Memory usage > 80% of node capacity → Check pod requests
- Multiple pod restarts → Review logs for errors

**Medium (P3):**
- Any warnings in Kubernetes events
- Deployment progress slower than expected
- Network policy violations

### Dashboard Access

```bash
# Prometheus metrics
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open: http://localhost:9090

# Grafana dashboards
kubectl port-forward -n monitoring svc/grafana 3000:80
# Open: http://localhost:3000

# Jaeger tracing
kubectl port-forward -n monitoring svc/jaeger 16686:16686
# Open: http://localhost:16686

# Kubernetes dashboard (optional)
kubectl proxy
# Open: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

---

## Rollback Procedures

### Scenario 1: Deployment Fails
```bash
# Deployment workflow failed
# → Review logs in GitHub Actions
# → Fix configuration issues
# → Delete failed AKS cluster
# → Retry workflow (all resources recreated)

# CLI command to delete cluster:
az aks delete --resource-group code-server-rg --name code-server-enterprise-staging
```

### Scenario 2: High Error Rate
```bash
# Error rate > 1% detected during canary
# → Immediate traffic revert to Docker

kubectl patch virtualservice api-gateway \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"docker-api-gateway.external"},"weight":100}]}]}}'

# Verify rollback succeeded
kubectl logs -n code-server-enterprise deployment/api-gateway --tail=50
# Should show no errors

# Investigate root cause
# → Check K8s pod logs
# → Review Prometheus metrics
# → Check application configuration
# → Schedule retry after fixes applied
```

### Scenario 3: Data Inconsistency
```bash
# PostgreSQL data mismatch detected between Docker and K8s
# → Stop application traffic
# → Verify backup integrity
# → Restore from backup

# On Docker host:
docker exec postgres-primary pg_dump -U postgres > /backup/postgres-backup.sql

# Restore to K8s:
kubectl cp postgres-backup.sql code-server-enterprise/postgres-0:/tmp/
kubectl exec -it postgres-0 -- psql -U postgres < /tmp/postgres-backup.sql

# Restart services after restore
kubectl rollout restart deployment -n code-server-enterprise

# Resume traffic migration after verification
```

---

## Post-Deployment Activities

### Immediate (Hours)
- [ ] Verify all services healthy in K8s
- [ ] Confirm no data inconsistencies
- [ ] Run integration test suite
- [ ] Notify stakeholders of successful milestone

### Short-term (Days)
- [ ] Monitor metrics for 7 days
- [ ] Collect performance baselines
- [ ] Document deployment learnings
- [ ] Plan Phase 5-7 feature activation

### Medium-term (Weeks)
- [ ] Optimize resource allocation
- [ ] Implement additional monitoring
- [ ] Archive Docker configuration
- [ ] Plan HA improvements

---

## Support & Escalation

### During Deployment

**On-Call Contact:** @infrastructure team

**Slack Channels:**
- #deployments - Status updates
- #incidents - Critical issues
- #kubernetes - Technical questions

**Escalation Path:**
1. **Technical Issues** → Infrastructure team
2. **Data Issues** → Database team
3. **Network Issues** → Networking team
4. **Security Issues** → Security team

### Emergency Contacts

| Role | Name | Slack | Phone |
|------|------|-------|-------|
| Lead | TBD | @infrastructure | TBD |
| Secondary | TBD | @infrastructure | TBD |
| Database | TBD | @database | TBD |

---

## Success Criteria Checklist

### Pre-Deployment
- [ ] GitHub secrets configured (all 7)
- [ ] Infrastructure validated (manifests, scripts, docs)
- [ ] Workflows verified in dry-run
- [ ] Team briefed on deployment plan
- [ ] On-call schedule confirmed

### Staging Deployment
- [ ] Cluster provisions successfully
- [ ] All 50+ pods reach "Running" state
- [ ] Health checks pass
- [ ] Data migration completes
- [ ] No errors in deployment logs

### Week 1 Canary
- [ ] 10% traffic to K8s stable
- [ ] Error rate < 0.1%
- [ ] Latency P99 < 150ms
- [ ] Rollback drill successful
- [ ] Team consensus for Phase 2

### Week 2 Expanded
- [ ] 50% traffic to K8s stable
- [ ] Error rate < 0.1%
- [ ] Latency P99 < 100ms
- [ ] Data consistency verified
- [ ] Ready for stateful migration

### Week 3 Stateful
- [ ] 90% traffic to K8s
- [ ] PostgreSQL replication lag < 1 second
- [ ] All data accessible from K8s
- [ ] Write consistency verified
- [ ] Ready for full cutover

### Week 4 Cutover
- [ ] 100% traffic to K8s
- [ ] All services healthy
- [ ] Error rate < 0.01%
- [ ] Docker infrastructure decommissioned
- [ ] Production stabilized

---

## Reference Documents

**Complete Guides:**
- `CI_CD_AUTOMATION_GUIDE.md` - Workflow details and troubleshooting
- `GITHUB_SECRETS_SETUP_GUIDE.md` - Secrets configuration step-by-step
- `TRAFFIC_MIGRATION_STRATEGY.md` - 4-week migration plan with Istio configs
- `PHASE_4_TO_7_FINAL_HANDOFF.md` - Architecture and feature overview
- `DEPLOYMENT_READINESS_MAY_1_2026.md` - Pre-deployment checklist

**Issue Management:**
- `scripts/ops/close-deployment-issues.py` - Python script for issue closure
- `scripts/ops/close-deployment-issues.sh` - Bash script for issue closure

**Workflows:**
- `.github/workflows/phase-4-k8s-deployment.yml` - Phase 4 automation
- `.github/workflows/phase-7-extension.yml` - Phase 7 automation
- `.github/workflows/phase-4-7-orchestration.yml` - Master orchestration

---

## Timeline Summary

| Phase | Dates | Duration | Status |
|-------|-------|----------|--------|
| Pre-Deployment | Today (May 1) | 20 min | Ready |
| Staging Deploy | May 3 | 2 hours | Ready |
| Week 1 Canary | May 3-10 | 7 days | Scheduled |
| Week 2 Expanded | May 10-17 | 7 days | Scheduled |
| Week 3 Stateful | May 17-24 | 7 days | Scheduled |
| Week 4 Cutover | May 24-31 | 7 days | Scheduled |
| **Total** | **May 1-31** | **4 weeks** | **Planned** |

---

## Next Immediate Actions

1. ✅ Configure GitHub secrets (10 min)
2. ✅ Close GitHub issues (2 min)
3. ✅ Verify git state (2 min)
4. ✅ Trigger Phase 4-7 orchestration workflow (1 min)
5. ✅ Monitor deployment (30-75 min)

**Total Time to Deployment:** ~2 hours

---

*Phase 4-7 Deployment: Complete Execution Runbook*  
*Created: May 1, 2026*  
*Status: ✅ READY FOR IMMEDIATE EXECUTION*
