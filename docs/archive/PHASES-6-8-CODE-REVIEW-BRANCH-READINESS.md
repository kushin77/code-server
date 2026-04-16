# Phases 6-8: Code Review, Branch Hygiene & Production Readiness

**Status**: 🚀 **QUEUED FOR SEQUENTIAL EXECUTION**  
**Total Duration**: 16 hours (Phase 6: 8h, Phase 7: 4h, Phase 8: 4h)  
**Timeline**: April 17-18, 2026  

---

## 📋 PHASE 6: CODE REVIEW & CONSOLIDATION (8 hours)

### Objective
Comprehensive code review of all Phase 1-5 changes, eliminate technical debt, ensure production-grade quality.

### 6.1 Review Configuration Consolidation (2 hours)
**Scope**: Caddyfile, prometheus.tpl, alertmanager.tpl, alert-rules.yml

**Checklist**:
- [ ] Caddyfile security headers complete (HSTS, CSP, X-Frame-Options)
- [ ] All 7 service routes configured (ide, grafana, prometheus, alertmanager, jaeger, ollama, api)
- [ ] Internal network gating correct (192.168.168.0/24, 10.8.0.0/24, 10.0.0.0/8)
- [ ] prometheus.tpl has all 11 scrape_configs
- [ ] Alert rules complete (160+ rules across 6 groups)
- [ ] No hardcoded secrets found
- [ ] All templates have variable substitution points

**Automated Review**:
```bash
# Syntax validation
bash scripts/validate-config-ssot.sh

# YAML lint
yamllint alertmanager.tpl prometheus.tpl alert-rules.yml

# Template variable check
grep -E '\$\{[A-Za-z_]+\}' *.tpl | wc -l
# Should have multiple substitution points
```

### 6.2 Review Terraform Code (2 hours)
**Scope**: terraform/*.tf files (secrets.tf, docker-compose.tf, main.tf)

**Checklist**:
- [ ] All variables have type + description
- [ ] Outputs marked as sensitive where needed
- [ ] No hardcoded values (all parameterized)
- [ ] Module structure clear and reusable
- [ ] Terraform validation passes
- [ ] State file configuration correct (backend configured)

**Automated Review**:
```bash
cd terraform
terraform fmt -check  # Verify formatting
terraform validate    # Syntax check
terraform plan -json > /tmp/plan.json
jq '.diagnostics[]' /tmp/plan.json  # Check for warnings
```

### 6.3 Review Deployment Scripts (1 hour)
**Scope**: scripts/*.sh (all bash scripts)

**Checklist**:
- [ ] All scripts have #!/bin/bash header
- [ ] Error handling (set -e, trap on error)
- [ ] No hardcoded passwords
- [ ] Proper logging (echo with timestamps)
- [ ] Idempotent (can run multiple times safely)
- [ ] Exit codes correct (0=success, 1+=error)

**Automated Review**:
```bash
# Shellcheck all scripts
shellcheck scripts/*.sh

# Check for security issues
grep -r "eval\|exec\|\$(" scripts/*.sh | head -5
# Evaluate if these are necessary

# Check for hardcoded secrets
grep -E "password|secret|api_key" scripts/*.sh | grep -v '\$'
```

### 6.4 Review Documentation (1 hour)
**Scope**: README.md, CONTRIBUTING.md, DEPLOYMENT-GUIDE.md, RUNBOOKS.md

**Checklist**:
- [ ] Deployment procedure clear
- [ ] Rollback procedure documented
- [ ] Monitoring setup instructions complete
- [ ] Troubleshooting guide covers common issues
- [ ] All team members can follow guides
- [ ] No outdated instructions

**Quality Review**:
```bash
# Check markdown syntax
mdl README.md CONTRIBUTING.md

# Check for broken links
grep -r "\[.*\](.*)" *.md | grep -v "http"
```

### 6.5 Code Consolidation: Remove Duplication (2 hours)
**Scope**: Identify and remove redundant code

**Actions**:
- [ ] Check for duplicate alert rules (different names, same logic)
- [ ] Check for duplicate dashboard definitions
- [ ] Check for duplicate validation scripts
- [ ] Consolidate shared functions into libraries
- [ ] Update imports/references after consolidation

---

## 📋 PHASE 7: BRANCH HYGIENE & VALIDATION (4 hours)

### Objective
Clean branch structure, ensure main is production-ready, set branch protections.

### 7.1 Branch Audit (30 min)
**List all branches and determine fate**:

```bash
git branch -a | head -20

# Expected: 
# main (production)
# feat/elite-p1-performance (merge to main)
# feat/elite-p2-access-control (merge to main)
# feat/elite-p3-ci-fixes (already merged)
# elite-p1-production (can delete, main is now authoritative)
# elite-p2-infrastructure (can delete)
```

**Actions**:
- [ ] Delete merged feature branches
- [ ] Delete stale experiment branches (>2 weeks old)
- [ ] Rename branches to follow convention: `feat/...`, `fix/...`, `refactor/...`

### 7.2 Main Branch Protection Setup (1 hour)
**Goal**: Enforce code quality gates on main

**GitHub Settings > Branches > main**:
- [ ] Require pull request reviews before merging (≥1 approval)
- [ ] Require status checks to pass (CI/CD validation)
- [ ] Require branches to be up to date with base branch
- [ ] Restrict who can push to main (admins only)
- [ ] Require signed commits
- [ ] Require linear history (no merge commits)
- [ ] Auto-delete head branches

**Implementation**:
```bash
# Using GitHub CLI (gh)
gh repo edit --enable-auto-merge-squash --enable-auto-merge-rebase --enable-branch-protections

# Or set via terraform
resource "github_branch_protection" "main" {
  repository_id = github_repository.code-server.id
  branch        = "main"
  
  require_code_owner_reviews      = true
  required_approving_review_count  = 1
  require_status_checks           = true
  require_branches_up_to_date     = true
  enforce_admins                  = true
  require_signed_commits          = true
}
```

### 7.3 Create Release Branches (1 hour)
**Goal**: Establish release workflow

**Actions**:
- [ ] Create `release/v1.0` branch from main
- [ ] Create `hotfix/` branch template for emergency fixes
- [ ] Document branching strategy in CONTRIBUTING.md

### 7.4 Merge Phase Branches into Main (1.5 hours)
**Goal**: Consolidate all Phase work into main

```bash
# Merge all Phase branches
git checkout main
git pull origin main

git merge feat/elite-p1-performance --no-ff -m "merge(p1): Performance optimization"
git merge feat/elite-p2-access-control --no-ff -m "merge(p2): Access control & secrets"
git merge feat/elite-p3-ci-fixes --no-ff -m "merge(p3): CI/CD fixes"

# Verify all tests pass
bash scripts/validate-config-ssot.sh
bash scripts/secrets-validation.sh

# Push consolidated main
git push origin main

# Delete merged branches
git branch -d feat/elite-p1-performance feat/elite-p2-access-control feat/elite-p3-ci-fixes
git push origin --delete feat/elite-p1-performance feat/elite-p2-access-control feat/elite-p3-ci-fixes
```

---

## 📋 PHASE 8: PRODUCTION DEPLOYMENT READINESS (4 hours)

### Objective
Final validation before production deployment, SLA confirmation, runbook preparation.

### 8.1 Pre-Flight Checks (1 hour)
**Comprehensive system validation**:

```bash
# Verify all configurations
echo "=== Configuration Validation ==="
bash scripts/validate-config-ssot.sh

# Verify no secrets present
echo "=== Secrets Scan ==="
bash scripts/secrets-validation.sh

# Verify infrastructure
echo "=== Infrastructure Check ==="
ssh akushnir@192.168.168.31 "
  echo 'GPU Status:'; nvidia-smi | head -5
  echo 'NAS Mount:'; mount | grep /data
  echo 'Docker Containers:'; docker-compose ps --all | head -10
  echo 'Vault Status:'; vault status 2>/dev/null || echo 'Vault not yet deployed'
"

# Verify monitoring stack
echo "=== Monitoring Stack ==="
curl -s http://192.168.168.31:9090/api/v1/status/config | jq '.data.yaml' | head -20
```

### 8.2 Load Test Preparation (1 hour)
**Goal**: Verify system handles production load

```bash
# Create load test scenarios
cat > scripts/load-test.sh << 'EOF'
#!/bin/bash
# Load test: 1x → 2x → 5x → 10x traffic

TARGETS=("ide.kushnir.cloud" "prometheus:9090" "grafana:3000")
DURATIONS=(300 600 1200)  # 5min, 10min, 20min

for target in "${TARGETS[@]}"; do
  echo "[+] Testing $target at 1x load..."
  ab -n 1000 -c 10 "http://$target/"
  
  echo "[+] Testing $target at 5x load..."
  ab -n 5000 -c 50 "http://$target/"
done
EOF

bash scripts/load-test.sh
```

**Success Criteria**:
- [ ] P99 latency < 500ms at 1x load
- [ ] P99 latency < 1s at 5x load
- [ ] Error rate < 0.1% at all loads
- [ ] No service crashes during test
- [ ] Memory/CPU remain within limits

### 8.3 Disaster Recovery Test (1 hour)
**Goal**: Verify rollback and failover procedures**

```bash
# Test rollback procedure
echo "[*] Testing rollback..."
git tag production-$(date +%Y%m%d-%H%M%S)
git log --oneline -1
# Document current commit

# Simulate failure
# kubectl set image deployment/code-server code-server=bad-image:latest
# kubectl rollout undo deployment/code-server

# Verify previous version healthy
# kubectl rollout status deployment/code-server --timeout=5m

echo "✅ Rollback procedure verified"

# Test GPU failover
echo "[*] Testing GPU failover..."
ssh akushnir@192.168.168.31 "
  docker-compose pause ollama
  sleep 10
  curl http://localhost:11434/health
  docker-compose unpause ollama
"

# Test NAS failover
echo "[*] Testing NAS failover..."
ssh akushnir@192.168.168.31 "
  # Simulate primary NAS failure
  sudo umount /data/nfs-primary 2>/dev/null || true
  
  # Verify automatic failover to backup
  mount | grep /data
  sleep 60
  
  # Restore primary
  sudo mount /data/nfs-primary
"

echo "✅ Failover procedures verified"
```

### 8.4 SLO Definition & Monitoring (1 hour)
**Goal**: Establish production SLOs and alerts

```yaml
# SLOs - Save in monitoring/slos.yaml
apiVersion: v1
kind: SLO
metadata:
  name: code-server-slo

spec:
  objectives:
    availability:
      target: 0.9999  # 99.99% uptime
      errorBudget: 52.6 minutes/year
    
    latency:
      p95: 100ms
      p99: 200ms
      p9999: 500ms
    
    errorRate:
      target: 0.1%  # Less than 1 in 1000 requests

  alerts:
    - name: SLO breach
      threshold: 99.95%
      window: 1h
      severity: critical
```

**Monitoring Dashboard**:
```prometheus
# prometheus/slo-rules.yml
- alert: CodeServerSLOBreach
  expr: |
    (1 - (increase(requests_total{status=~"[25].."}[1h]) / increase(requests_total[1h])))
    < 0.9995
  for: 5m
  annotations:
    summary: "Code-Server SLO breached"
    description: "Error rate exceeded threshold"
```

### 8.5 Runbook Creation (Final - overlaps with above)
**Goal**: Team can respond to incidents

**Create monitoring/runbooks/ directory**:

```markdown
# runbooks/code-server-unhealthy.md

## Code-Server Pod Not Healthy

### Symptoms
- HTTP 503 from code-server
- kubectl get pods shows CrashLoopBackOff
- Logs show "port already in use"

### Diagnosis
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
docker ps | grep code-server
netstat -an | grep 3180
```

### Resolution
Option 1: Restart pod
```bash
kubectl delete pod <pod-name>
kubectl rollout status deployment/code-server
```

Option 2: Rollback to previous version
```bash
kubectl rollout undo deployment/code-server
kubectl rollout status deployment/code-server
```

Option 3: Check volume mounts
```bash
kubectl exec <pod-name> -- df -h
ls -la /home/coder/projects
```
```

---

## 🎯 CONSOLIDATED EXECUTION PLAN

### Timeline: April 15-18, 2026

| Date | Time | Phase | Duration | Owner |
|------|------|-------|----------|-------|
| Apr 15 | 14:00-18:00 | 2-3 Monitor | 4h | Auto |
| Apr 16 | 00:00-18:00 | 4: Secrets | 6h | Kushin77 |
| Apr 16 | 18:00-22:00 | 5: Windows | 4h | Kushin77 |
| Apr 17 | 08:00-16:00 | 6: Code Review | 8h | Kushin77 |
| Apr 17 | 16:00-20:00 | 7: Branches | 4h | Kushin77 |
| Apr 17 | 20:00-24:00 | 8: Readiness | 4h | Kushin77 |
| Apr 18 | 08:00-12:00 | Deploy | 4h | Kushin77 + Team |

**Total Execution**: 30 hours (Phase 0-8 combined)

---

## ✅ PRODUCTION READINESS CHECKLIST

### Security
- [ ] Zero secrets in git
- [ ] All secrets in Vault
- [ ] SSH keys rotated
- [ ] TLS certificates valid
- [ ] Audit logging enabled
- [ ] Access control configured

### Infrastructure
- [ ] GPU operational (590.48 driver)
- [ ] NAS failover working
- [ ] Prometheus scraping all targets
- [ ] AlertManager routing rules tested
- [ ] Grafana dashboards functional

### Code Quality
- [ ] All tests passing
- [ ] Shellcheck validation green
- [ ] No linting errors
- [ ] Configuration SSOT verified
- [ ] Terraform plan clean

### Deployment
- [ ] CI/CD pipelines green
- [ ] Docker images built
- [ ] Kubernetes manifests ready (if k8s)
- [ ] Terraform apply tested
- [ ] Rollback procedure documented

### Monitoring & Observability
- [ ] Prometheus metrics defined
- [ ] Alert rules comprehensive (160+)
- [ ] Grafana dashboards created
- [ ] Health endpoints configured
- [ ] SLOs defined (99.99% availability)
- [ ] Runbooks created

### Documentation
- [ ] README updated
- [ ] CONTRIBUTING.md current
- [ ] Deployment guide complete
- [ ] Architecture diagrams up-to-date
- [ ] All team members trained

---

## 🚀 DEPLOYMENT FINAL GO/NO-GO

**Gates Before Production Deployment**:

```bash
#!/bin/bash

READY=true

echo "=== Production Readiness Gate ==="

# Security
if ! bash scripts/secrets-validation.sh; then
  echo "❌ Security gate failed: secrets found"
  READY=false
fi

# Infrastructure
if ! ssh akushnir@192.168.168.31 "docker-compose ps" | grep -q "healthy\|running"; then
  echo "❌ Infrastructure gate failed: services not healthy"
  READY=false
fi

# Code Quality
if ! bash scripts/validate-config-ssot.sh; then
  echo "❌ Quality gate failed: config validation"
  READY=false
fi

# Monitoring
if ! curl -s http://192.168.168.31:9090/api/v1/status/config | jq -e '.data' > /dev/null; then
  echo "❌ Monitoring gate failed: Prometheus not responding"
  READY=false
fi

if [ "$READY" = true ]; then
  echo "✅ ALL GATES PASSED - READY FOR PRODUCTION"
  exit 0
else
  echo "❌ DEPLOYMENT BLOCKED - RESOLVE FAILURES"
  exit 1
fi
```

---

**Status**: 🚀 All Phase 4-8 guides complete and committed  
**Next Action**: Execute Phase 4 (Secrets Management) - 6 hours  
**Final Deadline**: April 18, 2026 (production deployment)  

