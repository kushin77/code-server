# Phase 4-7 Pre-Deployment Validation Checklist

**Date Created:** May 1, 2026  
**Status:** ✅ READY FOR VALIDATION  
**Last Updated:** May 1, 2026

---

## Purpose

This checklist ensures all infrastructure, documentation, automation, and prerequisites are in place before triggering the Phase 4-7 deployment workflows. Use this checklist to verify readiness before moving forward.

---

## Part 1: Repository & Code Verification

### Git State
- [ ] Working directory is clean (`git status` shows no changes)
- [ ] All commits are pushed to origin/main
- [ ] Recent commits include Phase 4-7 documentation and workflows
- [ ] No merge conflicts or pending pull requests

**Verification:**
```bash
git status  # Should show: "nothing to commit, working tree clean"
git log --oneline | head -5  # Should show recent Phase 4-7 commits
```

### Code & Scripts
- [ ] Kubernetes manifests exist in `kubernetes/` directory
  - [ ] `namespace.yaml` present
  - [ ] `deployments/` directory with service manifests
  - [ ] `statefulsets/` directory (postgres, redis, redpanda)
  - [ ] `services/` directory with ClusterIP and LoadBalancer
  - [ ] `rbac.yaml` for RBAC policies
  - [ ] `network-policies/` directory for zero-trust networking
  - [ ] `ingress.yaml` for Istio configuration

- [ ] Helm chart exists in `helm/code-server-enterprise/`
  - [ ] `Chart.yaml` with version v1.0.0+
  - [ ] `values.yaml` and environment-specific values files
  - [ ] `templates/` directory with deployment templates
  - [ ] `charts/` for chart dependencies (if any)

- [ ] Provisioning scripts exist in `scripts/k8s/`
  - [ ] `provision-aks-cluster.sh` - AKS cluster creation
  - [ ] All scripts have proper error handling (trap handlers)
  - [ ] Scripts are executable (`chmod +x`)

- [ ] Data migration scripts exist in `scripts/ops/`
  - [ ] `migrate-to-k8s-data.sh` - PostgreSQL/Redis migration
  - [ ] Script has error handling and logging

- [ ] Issue closure scripts exist in `scripts/ops/`
  - [ ] `close-deployment-issues.py` - Python version
  - [ ] `close-deployment-issues.sh` - Bash version
  - [ ] Scripts are executable and tested

**Verification:**
```bash
# Check manifest count
find kubernetes -name "*.yaml" | wc -l  # Should be 6+

# Check Helm chart
ls helm/code-server-enterprise/Chart.yaml
helm lint helm/code-server-enterprise/

# Check scripts exist
ls -la scripts/k8s/*.sh scripts/ops/*.sh scripts/ops/*.py
```

### GitHub Actions Workflows
- [ ] Phase 4 K8s deployment workflow exists
  - [ ] `.github/workflows/phase-4-k8s-deployment.yml` present (330+ lines)
  - [ ] Contains jobs: validate, provision-cluster, deploy-services, migrate-data, validate-deployment
  - [ ] Workflow triggers defined (workflow_dispatch, workflow_call)

- [ ] Phase 7 extension workflow exists
  - [ ] `.github/workflows/phase-7-extension.yml` present (320+ lines)
  - [ ] Contains jobs: build, security-scan, package, publish, validate-modules
  - [ ] Supports both manual dispatch and automated triggers

- [ ] Orchestration workflow exists
  - [ ] `.github/workflows/phase-4-7-orchestration.yml` present (280+ lines)
  - [ ] Coordinates all phases in sequence
  - [ ] Supports selective phase execution

**Verification:**
```bash
# Check workflow syntax
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/phase-4-k8s-deployment.yml'))"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/phase-7-extension.yml'))"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/phase-4-7-orchestration.yml'))"

# Count jobs in each workflow
grep -c "^  [a-z-]*:" .github/workflows/phase-*.yml
```

---

## Part 2: Documentation Verification

### Deployment Guides
- [ ] `CI_CD_AUTOMATION_GUIDE.md` exists (500+ lines)
  - [ ] Covers workflow details
  - [ ] Includes troubleshooting section
  - [ ] Documents all configuration options

- [ ] `GITHUB_SECRETS_SETUP_GUIDE.md` exists (400+ lines)
  - [ ] Step-by-step setup for all 7 secrets
  - [ ] Includes Azure CLI commands
  - [ ] Has troubleshooting for common issues

- [ ] `TRAFFIC_MIGRATION_STRATEGY.md` exists (590+ lines)
  - [ ] 4-week deployment plan documented
  - [ ] Includes Istio VirtualService examples
  - [ ] Contains success criteria and monitoring

- [ ] `DEPLOYMENT_EXECUTION_RUNBOOK.md` exists (600+ lines)
  - [ ] Complete step-by-step execution guide
  - [ ] Includes quick-start section
  - [ ] Contains rollback procedures

- [ ] `DEPLOYMENT_READINESS_MAY_1_2026.md` exists
  - [ ] Pre-deployment checklist present
  - [ ] Infrastructure validation documented

- [ ] `PHASE_4_TO_7_FINAL_HANDOFF.md` exists (377 lines)
  - [ ] Complete Phase 4-7 architecture documented
  - [ ] Service parity matrix included

**Verification:**
```bash
# Check all guides exist
ls -lh CI_CD_AUTOMATION_GUIDE.md \
       GITHUB_SECRETS_SETUP_GUIDE.md \
       TRAFFIC_MIGRATION_STRATEGY.md \
       DEPLOYMENT_EXECUTION_RUNBOOK.md

# Check line counts
wc -l CI_CD_AUTOMATION_GUIDE.md \
    GITHUB_SECRETS_SETUP_GUIDE.md \
    TRAFFIC_MIGRATION_STRATEGY.md \
    DEPLOYMENT_EXECUTION_RUNBOOK.md
```

---

## Part 3: GitHub Repository Configuration

### Secrets Configuration
- [ ] GitHub repository secrets are configured:
  - [ ] AZURE_CREDENTIALS - Azure service principal JSON
  - [ ] DOCKER_HOST_IP - Docker host IP (192.168.168.31)
  - [ ] DOCKER_HOST_SSH_KEY - SSH private key for Docker host
  - [ ] VSCODE_MARKETPLACE_TOKEN - VS Code Marketplace token
  - [ ] OPEN_VSX_TOKEN - Open VSX Registry token
  - [ ] SNYK_TOKEN - Snyk security token
  - [ ] SLACK_WEBHOOK - Slack notification webhook (optional)

**Verification:**
```bash
# List secrets (if gh CLI available)
gh secret list --repo kushin77/code-server

# Or verify via GitHub UI:
# Settings → Secrets and variables → Actions → verify all 7 secrets present
```

### Repository Settings
- [ ] GitHub Actions enabled
  - [ ] Settings → Actions → "Allow all actions and reusable workflows"

- [ ] Branch protection rules configured
  - [ ] main branch requires status checks
  - [ ] Pull request reviews required

- [ ] Deployment environments created
  - [ ] "staging" environment
  - [ ] "production" environment with approval requirements

**Verification:**
```bash
# Verify via GitHub API (requires token)
gh api repos/kushin77/code-server/actions/settings
```

---

## Part 4: Infrastructure Prerequisites

### Azure Account
- [ ] Azure subscription is active and has available quota
- [ ] Azure service principal created with Contributor role
- [ ] Service principal credentials secured and accessible
- [ ] Resource group can be created: `code-server-rg`

**Verification:**
```bash
# Test Azure CLI authentication (if az CLI available)
az account show  # Should display current subscription
az ad sp show --id <client-id>  # Should show service principal
```

### Docker Host Access
- [ ] Docker host (192.168.168.31) is accessible via SSH
- [ ] SSH key generated and shared with Docker host
- [ ] akushnir user has SSH access
- [ ] Docker containers running and healthy

**Verification:**
```bash
# Test SSH access (if key available)
ssh -i ~/.ssh/docker-host-key akushnir@192.168.168.31 "docker ps | wc -l"
# Should return number of running containers
```

---

## Part 5: Workflow Readiness

### Phase 4 K8s Deployment Workflow
- [ ] Workflow file is syntactically valid YAML
- [ ] All required environment variables defined
- [ ] All required secrets referenced correctly
- [ ] Jobs are properly sequenced (validate → provision → deploy → migrate → validate)
- [ ] Inputs with defaults match documentation

**Verification:**
```bash
# Validate YAML
python3 -c "import yaml; print(yaml.safe_load(open('.github/workflows/phase-4-k8s-deployment.yml'))['jobs'].keys())"
# Should show: dict_keys(['validate', 'provision_cluster', 'deploy_services', 'migrate_data', 'validate_deployment', 'notify'])
```

### Phase 7 Extension Workflow
- [ ] Workflow builds successfully with esbuild
- [ ] Security scanning jobs configured
- [ ] Publishing to both marketplaces configured
- [ ] Module validation jobs included
- [ ] Integration tests configured

**Verification:**
```bash
# Check for key job names
grep "build\|security-scan\|package\|publish" .github/workflows/phase-7-extension.yml
```

### Orchestration Workflow
- [ ] Calls to phase-4-k8s-deployment.yml properly formatted
- [ ] Calls to phase-7-extension.yml properly formatted
- [ ] Traffic migration job configured
- [ ] Post-deployment reporting configured
- [ ] Environment-specific logic implemented

**Verification:**
```bash
# Check for workflow_call references
grep "uses:.*phase-4-k8s-deployment" .github/workflows/phase-4-7-orchestration.yml
grep "uses:.*phase-7-extension" .github/workflows/phase-4-7-orchestration.yml
```

---

## Part 6: Testing Verification

### Issue Closure Script Testing
- [ ] Issue closure script runs in dry-run mode successfully
  - [ ] Run: `python3 scripts/ops/close-deployment-issues.py --dry-run`
  - [ ] Expected output: Shows all 4 issues would be processed

- [ ] Script properly formats evidence comments
- [ ] Script handles rate limiting
- [ ] Bash version also tested and working

**Verification:**
```bash
# Test dry-run
python3 scripts/ops/close-deployment-issues.py --dry-run
# Should show successful dry-run of all 4 issues
```

### Manifest Validation
- [ ] Kubernetes manifests validate with kubeval
- [ ] Helm chart lints successfully
- [ ] No obvious syntax errors in YAML files

**Verification:**
```bash
# Validate manifests if kubeval available
kubeval kubernetes/*.yaml

# Or use kubectl dry-run
kubectl apply -f kubernetes/ --dry-run=client
```

---

## Part 7: Documentation Quality Checks

### Completeness
- [ ] All deployment guides are present and complete
- [ ] Quick-start instructions are clear and concise
- [ ] Step-by-step procedures are detailed
- [ ] Success criteria are well-defined
- [ ] Rollback procedures are documented

### Accuracy
- [ ] Workflow file names match documentation references
- [ ] Kubernetes manifests match service list
- [ ] Configuration examples are syntactically correct
- [ ] Command examples are copy-paste ready
- [ ] File paths are accurate

### Accessibility
- [ ] Documentation is in markdown format
- [ ] Code blocks are properly formatted
- [ ] Links are functional (internal references)
- [ ] Table of contents present (where applicable)
- [ ] Key sections highlighted with formatting

**Verification:**
```bash
# Check documentation files are readable
file CI_CD_AUTOMATION_GUIDE.md GITHUB_SECRETS_SETUP_GUIDE.md TRAFFIC_MIGRATION_STRATEGY.md

# Check markdown validity
grep -E "^#+\s" CI_CD_AUTOMATION_GUIDE.md | head -10  # Should show headers
```

---

## Part 8: Final Readiness Gate

### Critical Requirements (Must Complete Before Deployment)
- [ ] All secrets configured in GitHub (7 secrets)
- [ ] Azure service principal verified and working
- [ ] Docker host SSH access verified
- [ ] GitHub Actions workflows syntax validated
- [ ] Issue closure script tested (dry-run successful)
- [ ] All documentation complete and accurate

### Important Requirements (Should Complete)
- [ ] Traffic migration strategy understood by team
- [ ] Rollback procedures reviewed by operations
- [ ] On-call schedule prepared for 4-week migration
- [ ] Monitoring dashboards configured (Grafana, Prometheus)
- [ ] Slack webhook configured for notifications

### Nice-to-Have (Optional Before Deployment)
- [ ] Disaster recovery procedures reviewed
- [ ] Team trained on new Kubernetes infrastructure
- [ ] Performance baselines established
- [ ] Capacity planning completed for Q2

---

## Readiness Assessment

### Scoring
- **8/8 Critical Requirements Met:** ✅ **READY TO DEPLOY**
- **6-7 Critical Requirements Met:** ⏳ **PROCEED WITH CAUTION** (address gaps first)
- **<6 Critical Requirements Met:** ❌ **NOT READY** (resolve critical issues)

### Assessment Template

```
Critical Requirements Status:
✅ Secrets configured (7/7)
✅ Azure credentials verified
✅ SSH access verified
✅ Workflows validated
✅ Scripts tested
✅ Documentation complete

Important Requirements Status:
✅ Strategy understood
✅ Rollback procedures reviewed
✅ On-call prepared
✅ Monitoring configured
✅ Notifications ready

OVERALL STATUS: ✅ READY TO DEPLOY
```

---

## Deployment Sign-Off

### Required Approvals
- [ ] Infrastructure Lead: _________________ Date: _______
- [ ] Security Lead: _________________ Date: _______
- [ ] Operations Lead: _________________ Date: _______

### Pre-Deployment Comments
```
[Document any issues found and resolutions here]
```

---

## Post-Validation Steps

Once all checks pass:

1. **Configure GitHub Secrets** (if not already done)
   ```bash
   # Follow: GITHUB_SECRETS_SETUP_GUIDE.md
   ```

2. **Close GitHub Issues** (optional, can do during deployment)
   ```bash
   GITHUB_TOKEN=<token> python3 scripts/ops/close-deployment-issues.py
   ```

3. **Trigger Deployment Workflow**
   - Go to: GitHub Actions tab
   - Select: "Phase 4-7 Complete Deployment Orchestration"
   - Click: "Run workflow"
   - Set: environment=staging, deployment_phase=all
   - Click: "Run workflow"

4. **Monitor Deployment**
   - Follow: DEPLOYMENT_EXECUTION_RUNBOOK.md
   - Watch GitHub Actions progress
   - Monitor K8s cluster health
   - Track metrics in Grafana/Prometheus

---

## Troubleshooting During Validation

### Issue: YAML validation fails
**Solution:** Check for tabs instead of spaces, quote string values with special characters

### Issue: Script test fails
**Solution:** Verify Python 3 installed, check script permissions (`chmod +x`)

### Issue: Cannot find secrets
**Solution:** Ensure secrets are in repository settings, not organization settings

### Issue: Kubernetes manifests missing
**Solution:** Check kubernetes/ directory exists, verify all service manifests present

### Issue: Workflows not found
**Solution:** Ensure .github/workflows/ directory exists, workflow files have .yml extension

---

## Contact & Support

**Questions During Validation:**
- Check: Relevant guide (CI_CD_AUTOMATION_GUIDE.md, etc.)
- Review: This checklist for missed items
- Escalate: Contact @infrastructure team

**Issues Found:**
- Document in "Post-Validation Comments" section
- Assign resolution owner and due date
- Recheck items after resolution
- Do not proceed to deployment until all checks pass

---

*Phase 4-7 Pre-Deployment Validation Checklist*  
*Created: May 1, 2026*  
*Status: ✅ READY FOR USE*
