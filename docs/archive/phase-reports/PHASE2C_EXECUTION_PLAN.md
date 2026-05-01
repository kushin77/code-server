# Phase 2C: Infrastructure Validation & Testing

**Phase**: 2C (Validation & Testing)  
**Start Date**: May 5, 2026  
**Duration**: 2-3 days  
**Status**: PLANNING  
**Owner**: Infrastructure Team

---

## Overview

Phase 2C focuses on validating all Phase 2B consolidations in a staging environment and completing Tier 1 application migrations. This phase acts as a quality gate before Phase 3 (IaC Hardening) and production rollout.

---

## Objectives

1. ✅ Validate all docker-compose consolidations in staging
2. ✅ Verify monitoring config consolidation works end-to-end
3. ✅ Complete Tier 1 application migrations (memory-engine, control-plane)
4. ✅ Update deployment scripts for new docker-compose structure
5. ✅ Test background test runner in staging (1+ week operational data)
6. ✅ Document findings and create remediation plan if needed

---

## Work Items

### Work Item 1: Tier 1 Application Migrations (Estimated: 6 hours)

**Apps to Migrate**:
1. `apps/memory_engine/src/memory.py`
2. `apps/control_plane/src/controller.py`

**For Each App**:

**Step 1: Identify Usage** (15 minutes per app)
```bash
# Find all os.getenv() calls
grep -n "os\.getenv\|os\.environ" apps/memory_engine/src/*.py | head -20
```

**Step 2: Add Import** (5 minutes per app)
```python
# Add at top of main file
from apps._shared.python.config import get_config
```

**Step 3: Replace Calls** (30 minutes per app)
```python
# BEFORE:
api_key = os.getenv("MEMORY_API_KEY")
debug = os.getenv("DEBUG_MODE") == "true"
port = int(os.getenv("API_PORT", "8002"))

# AFTER:
config = get_config()
api_key = config.get_required("MEMORY_API_KEY")
debug = config.get_bool("DEBUG_MODE", False)
port = config.get_int("API_PORT", 8002)
```

**Step 4: Validate** (10 minutes per app)
```bash
# Check syntax
python3 -m py_compile apps/memory_engine/src/memory.py

# Check imports
python3 -c "from apps.memory_engine.src.memory import *"
```

**Step 5: Test** (15 minutes per app)
```bash
# Run unit tests if available
pytest apps/memory_engine/tests/ -v

# Or manual test
python3 apps/memory_engine/src/memory.py --help
```

**Step 6: Commit** (5 minutes per app)
```bash
git add apps/memory_engine/src/memory.py
git commit -m "feat(phase2c): memory-engine -> apps._shared.python.config migration

Migrate memory-engine to use centralized configuration:
  - 3 os.getenv() calls replaced with config.get() equivalents
  - API_KEY, DEBUG_MODE, API_PORT now type-safe
  - See APPLICATION_LIBRARY_MIGRATION_GUIDE.md for pattern
  - Syntax validated: python3 -m py_compile
  - Tests pass: pytest apps/memory_engine/tests/

Relates to: Phase 2B application migration framework"
```

**Validation Checklist**:
- [ ] All os.getenv() calls identified (grep output reviewed)
- [ ] Import added to main file
- [ ] All calls replaced with config.get() equivalents
- [ ] Syntax valid: python3 -m py_compile passes
- [ ] Imports work: python3 -c "from module import *" passes
- [ ] Unit tests pass (if available)
- [ ] Commit message includes reference to guide
- [ ] Git shows expected changes

**Resources**: See `APPLICATION_LIBRARY_MIGRATION_GUIDE.md` section "Step-by-Step Template"

---

### Work Item 2: Update Deployment Scripts (Estimated: 4 hours)

**Task**: Update all scripts and workflows to use new docker-compose file names

**Step 1: Find References** (30 minutes)
```bash
# Find all references to old docker-compose names
grep -r "docker-compose-production\|docker-compose-cluster\|docker-compose-full" \
  scripts/ .github/workflows/ terraform/ --include="*.sh" --include="*.yml" | \
  tee /tmp/compose-refs.txt

# Count by file
cut -d: -f1 /tmp/compose-refs.txt | sort -u | wc -l
```

**Step 2: Review Each Reference** (2 hours)

For each reference found:

| Old Name | New Name | Context |
|----------|----------|---------|
| docker-compose-production.yml | docker-compose.prod.yml | Production deployments |
| docker-compose-cluster.yml | docker-compose.cluster.yml | Cluster mode deployments |
| docker-compose-full-deployment.yml | docker-compose.yml + profiles | Local full deployment |

**Step 3: Update Scripts** (1.5 hours)

Common update patterns:

```bash
# Pattern 1: Direct file reference
- OLD: docker-compose -f docker-compose-production.yml up
- NEW: docker-compose -f docker-compose.prod.yml up

# Pattern 2: Profile selection
- OLD: docker-compose -f docker-compose-cluster.yml up
- NEW: docker-compose -f docker-compose.cluster.yml up

# Pattern 3: Override composition
- OLD: docker-compose -f docker-compose.yml -f docker-compose-production.yml
- NEW: docker-compose -f docker-compose.prod.yml up
```

**Scripts to Check**:
- scripts/ops/deploy-production.sh
- scripts/ops/deploy-cluster.sh
- scripts/ci/docker-compose-integration-tests.sh
- scripts/ci/background-test-runner.py
- .github/workflows/*.yml (except continuous-validation.yml which already uses new names)
- terraform/provisioners (if any docker-compose invocations)

**Step 4: Validate Updates** (30 minutes)

For each updated script:
```bash
# 1. Check syntax
bash -n scripts/ops/deploy-production.sh

# 2. Dry-run if possible
scripts/ops/deploy-production.sh --dry-run

# 3. Verify docker-compose still works
docker-compose -f docker-compose.prod.yml config > /dev/null
```

**Step 5: Commit** (30 minutes)

```bash
git add scripts/ .github/workflows/ terraform/
git commit -m "refactor(phase2c): update scripts for new docker-compose structure

Update deployment scripts and workflows for Phase 2B consolidation:
  - docker-compose-production.yml → docker-compose.prod.yml
  - docker-compose-cluster.yml → docker-compose.cluster.yml
  - All references updated (scripts, workflows, terraform)
  
Files updated:
  - scripts/ops/deploy-production.sh
  - scripts/ops/deploy-cluster.sh
  - scripts/ci/docker-compose-integration-tests.sh
  - [list other files]
  
Validation:
  ✅ Syntax check: bash -n (all files pass)
  ✅ Dry-run: All scripts execute without errors
  ✅ Docker-compose: 'config' output valid
  
Relates to: Phase 2B docker-compose consolidation"
```

**Validation Checklist**:
- [ ] All references found (grep output reviewed)
- [ ] Each file updated with new names
- [ ] Bash syntax valid: bash -n (all pass)
- [ ] Docker-compose config valid: `docker-compose -f <file> config`
- [ ] Dry-runs successful (if applicable)
- [ ] Commit includes all files
- [ ] Git diff shows only necessary changes

---

### Work Item 3: Full Staging Deployment Validation (Estimated: 8 hours)

**Environment**: Staging cluster (separate from production)

**Setup** (1 hour):
```bash
# 1. Checkout Phase 2B branch
git checkout main  # Ensure on main with all Phase 2B commits

# 2. Export staging environment
export ENVIRONMENT=staging
source scripts/_common/config.env
source scripts/_common/init.sh

# 3. Clear staging (if applicable)
# docker-compose -f docker-compose.yml down  # Run only if safe in staging
```

**Deployment Tests** (4 hours):

**Test 1: Single Docker-Compose Deployment** (1 hour)
```bash
# Test: Full service deployment with all profiles
docker-compose -f docker-compose.yml \
  --profile ai \
  --profile enterprise \
  --profile infrastructure \
  --profile governance \
  config > /tmp/staging-full.json

# Start services
docker-compose -f docker-compose.yml up -d

# Wait for startup (2-3 minutes)
sleep 30

# Check service status
docker-compose ps
```

**Expected Output**:
```
NAME                    STATUS
code-server-db         Up (healthy)
code-server-redis      Up (healthy)
code-server-api        Up (healthy)
code-server-grafana    Up (healthy)
code-server-prometheus Up (healthy)
code-server-loki       Up (healthy)
[... 39 total services]
```

**Test 2: Health Checks** (30 minutes)
```bash
# Source health check functions
source scripts/_common/health-checks.sh

# Run all health checks
health_check_postgres
health_check_redis
health_check_api
health_check_grafana
health_check_prometheus

# Expected: All return 0 (success)
```

**Test 3: Production Profile** (1 hour)
```bash
# Stop current deployment
docker-compose down

# Start with prod profile
docker-compose -f docker-compose.prod.yml up -d

# Verify services
docker-compose ps

# Check health
source scripts/_common/health-checks.sh
health_check_api
health_check_postgres
```

**Test 4: Cluster Mode** (1 hour)
```bash
# Stop current deployment
docker-compose down

# Start cluster deployment
docker-compose -f docker-compose.cluster.yml up -d

# Verify cluster services
docker-compose ps | grep -E "node|cluster|coordinator"

# Check cluster health
docker-compose logs | grep -i "cluster.*healthy\|joined"
```

**Monitoring Validation** (2 hours):

**Prometheus Validation**:
```bash
# Check Prometheus UI
# curl -s http://localhost:9090 | grep -i "prometheus"

# Verify config loaded
docker-compose logs prometheus | grep -i "configuration"

# Check active targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
```

**Expected**: 8+ active targets

**Grafana Validation**:
```bash
# Check Grafana UI
# curl -s http://localhost:3000 | grep -i "grafana"

# Verify datasources
curl -s -H "Authorization: Bearer admin" \
  http://localhost:3000/api/datasources | jq '.[] | .name'

# Expected datasources:
# - Prometheus
# - Loki (if applicable)
```

**Loki Validation**:
```bash
# Check Loki logs
curl -s http://localhost:3100/loki/api/v1/labels | jq '.values | length'

# Expected: 5+ log labels
```

**AlertManager Validation**:
```bash
# Check AlertManager status
curl -s http://localhost:9093 | grep -i "alertmanager"

# Verify config
curl -s http://localhost:9093/api/v1/status | jq '.config' | head -20
```

**Service Validation** (1 hour):

For each critical service:
```bash
# Check logs for errors
docker-compose logs service-name | grep -i "error\|fatal\|panic"

# Check configuration
docker-compose exec service-name cat /path/to/config.yml
```

**Cleanup** (30 minutes):
```bash
# Document findings
echo "## Staging Validation Results" > /tmp/staging-results.txt
echo "Date: $(date)" >> /tmp/staging-results.txt
echo "Services: $(docker-compose ps | wc -l)" >> /tmp/staging-results.txt
echo "Health checks: $(source scripts/_common/health-checks.sh; health_check_api && echo PASS || echo FAIL)" >> /tmp/staging-results.txt

# Stop services
docker-compose down

# Save logs for analysis
docker-compose logs > /tmp/staging-deployment.log 2>&1
```

**Validation Checklist**:
- [ ] Full deployment: All 39 services start
- [ ] All services marked as "Up (healthy)"
- [ ] Health check functions: All pass
- [ ] Production profile: Services start and pass health checks
- [ ] Cluster mode: Cluster services detected
- [ ] Prometheus: 8+ targets active
- [ ] Grafana: 3+ datasources available
- [ ] Loki: 5+ log labels found
- [ ] AlertManager: Config loaded
- [ ] No errors in service logs
- [ ] Config files properly mounted

---

### Work Item 4: Background Test Runner Operational Validation (Estimated: 2 hours)

**Task**: Verify continuous validation workflow runs as expected

**Step 1: Verify Workflow Deployment** (15 minutes)
```bash
# Check workflow file exists
ls -la .github/workflows/continuous-validation.yml

# Verify syntax
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/continuous-validation.yml'))"

# Expected: No errors, file valid YAML
```

**Step 2: Check Workflow Execution** (1 hour)

In GitHub Actions UI:
1. Navigate to Actions tab
2. Look for "Continuous Infrastructure Validation" workflow
3. Check execution history:
   - Scheduled runs: Should have executed on 6-hour schedule
   - Manual runs: Should show any on-demand executions
   - Push runs: Should show execution on config file changes

**Expected**:
- ✅ Workflow shows as "successful" or "completed"
- ✅ All validation steps pass (green checkmarks)
- ✅ Execution time: < 5 minutes
- ✅ Summary tab shows validation results

**Step 3: Review Generated Issues** (30 minutes)

```bash
# Check for auto-created issues
gh issue list --label "validation-failure" --label "auto-created" | head -10

# Review recent issues
gh issue view <issue-number>  # Check details

# Expected:
# - Issues created only for actual failures
# - Issues have clear error messages
# - Issues link to workflow runs
```

**Step 4: Validate Error Handling** (15 minutes)

If no failures occurred naturally:
```bash
# Manually trigger workflow with intentional failure
# 1. Temporarily break config.env (for test)
# 2. Run workflow manually
# 3. Verify issue created
# 4. Fix config.env
# 5. Close auto-created issue
```

**Validation Checklist**:
- [ ] Workflow file exists and is valid YAML
- [ ] Workflow appears in GitHub Actions UI
- [ ] Scheduled runs executed on 6-hour schedule
- [ ] Validation steps show expected results
- [ ] Error handling works (issues created on failures)
- [ ] Issue format is clear and actionable
- [ ] No duplicate issues created

---

### Work Item 5: Create Phase 2C Validation Report (Estimated: 1 hour)

**Output**: `PHASE2C_VALIDATION_REPORT.md`

**Contents**:
```markdown
# Phase 2C Validation Report

## Summary
- Date: [completion date]
- All validations: PASS / FAIL
- Issues found: [count]
- Remediations: [count]

## Test Results
- Tier 1 migrations: [memory-engine status], [control-plane status]
- Script updates: [count] files updated, all syntax valid
- Staging deployment: All services healthy
- Monitoring: Prometheus, Grafana, Loki operational
- Background test runner: [count] executions, [count] issues created

## Findings
[List any issues or unexpected behavior]

## Recommendations
[Recommendations for Phase 3 or production rollout]

## Sign-Off
✅ All Phase 2C validations complete
✅ Ready for Phase 3 (IaC Hardening)
```

**Commit**:
```bash
git add PHASE2C_VALIDATION_REPORT.md
git commit -m "docs(phase2c): validation report and sign-off

Phase 2C validation complete:
  ✅ Tier 1 apps migrated (memory-engine, control-plane)
  ✅ Deployment scripts updated (30+ references updated)
  ✅ Staging deployment validated (all 39 services healthy)
  ✅ Monitoring stack operational (Prometheus, Grafana, Loki)
  ✅ Background test runner operational (continuous validation active)
  
Status: Ready for Phase 3 (IaC Hardening)"
```

---

## Timeline

| Activity | Duration | Start | End |
|----------|----------|-------|-----|
| Tier 1 app migrations | 6h | Day 1 morning | Day 1 afternoon |
| Deploy script updates | 4h | Day 1 afternoon | Day 2 morning |
| Staging deployment validation | 8h | Day 2 morning | Day 2 evening |
| Background test runner validation | 2h | Day 3 morning | Day 3 morning |
| Create validation report | 1h | Day 3 late morning | Day 3 midday |
| **Total Phase 2C** | **21h** | **May 5** | **May 7** |

---

## Success Criteria

✅ Tier 1 apps (memory-engine, control-plane) successfully migrated and tested  
✅ All deployment scripts updated and tested (bash -n passes)  
✅ Staging deployment: All 39 services start and health checks pass  
✅ Monitoring stack: Prometheus, Grafana, Loki, AlertManager operational  
✅ Background test runner: Continuous validation active and working  
✅ Zero critical issues found during validation  
✅ Phase 2C validation report created and approved  

---

## Rollback Plan (If Needed)

If validation fails, rollback to previous stable state:

```bash
# Identify last working commit
git log --oneline | grep "phase2b"

# Rollback Tier 1 migrations
git revert [memory-engine migration commit]
git revert [control-plane migration commit]

# Rollback script updates
git revert [script update commit]

# Investigate root cause
docker-compose logs > /tmp/failure-analysis.log
```

---

## Resources

- **Migration Guide**: `APPLICATION_LIBRARY_MIGRATION_GUIDE.md`
- **Docker-Compose Guide**: `DOCKER_COMPOSE_CONSOLIDATION.md`
- **Phase 2B Report**: `PHASE2B_FINAL_EXECUTION_REPORT.md`
- **Health Checks**: `scripts/_common/health-checks.sh`
- **Config Guide**: `scripts/_common/config.env`

---

## Owner & Approval

**Phase Owner**: Infrastructure Team  
**Prepared by**: Phase 2B Completion Team  
**Date**: April 28, 2026  

---

End of Phase 2C Execution Plan
