# April 23, 2026 — Next Task Execution Plan

## Context
Last session: Collab-9 deployment (commit 69fe25e1) achieved Docker build success but encountered infrastructure blockers:
1. **NAS mount failure** (192.168.168.56 not accessible)
2. **Permission issues** on Replica 1 (root-owned Docker artifacts)
3. **IaC compliance gaps** (deployment not purely configuration-driven)

User mandate: "proceed now to next task — ensure IaC, immutable, idempotent"

---

## Next Task: Establish Production-Grade Deployment IaC

### Objective
Ensure all deployments are:
- ✅ **IaC** (Infrastructure as Code): All configuration versioned, no manual steps
- ✅ **Immutable**: No manual mutations; config-driven only
- ✅ **Idempotent**: Safe to run multiple times with identical result

### Current Issues (Root Cause Analysis)

#### 1. NAS Mount Failure (Infrastructure Blocker)
**Problem**: Docker compose trying to mount `/export/appsmith` from 192.168.168.56 (NAS)
```
appsmith-data: mount failed — no such file or directory
```

**Root Cause**: NAS connectivity or export path doesn't exist

**IaC Fix Options**:
- Option A: Make NAS mount optional in docker-compose (conditional volumes)
- Option B: Pre-flight check in deployment script (fail fast if NAS unavailable)
- Option C: Use local volumes instead of NAS for non-critical services

**Recommendation**: Option B (pre-flight check, fail loudly before docker-compose)

#### 2. Permission Issues on R31 (Deployment Blocker)
**Problem**: Git operations fail due to root-owned Docker artifacts
```
sudo chown -R akushnir:akushnir /home/akushnir/code-server-enterprise/
```

**Root Cause**: Docker containers run as root, leaving behind root-owned files

**IaC Fix Options**:
- Option A: Add pre-deployment cleanup step (idempotent chown)
- Option B: Docker compose use `user:` directive (run containers as akushnir)
- Option C: Include permission fix in scripts/_common/init.sh

**Recommendation**: Option A + B (both for robustness)

#### 3. IaC Compliance Gap (Process Blocker)
**Problem**: Manual SSH + docker-compose commands without centralized orchestration

**IaC Fix Required**:
- [ ] Centralized deployment script (scripts/ops/deploy-with-iac.sh)
- [ ] Pre-flight validation (NAS, permissions, git state)
- [ ] Configuration validation (docker-compose config PASS)
- [ ] Automated verification (health checks after deploy)
- [ ] Idempotency guarantee (safe to re-run)

---

## Execution Plan (Phased)

### Phase 1: Pre-Flight Validation (15 min)
**Goal**: Create reusable pre-flight check for deployment safety

**Deliverable**: `scripts/ops/pre-flight-deployment-check.sh`
- [ ] Verify SSH connectivity to both replicas
- [ ] Verify git state (clean working tree)
- [ ] Verify NAS connectivity (mount/ping test)
- [ ] Verify file permissions (akushnir:akushnir ownership)
- [ ] Verify disk space (min 10GB free on each replica)
- [ ] Verify docker-compose syntax (config validate)

**Governance**: 
- ✅ IaC: Version-controlled script
- ✅ Immutable: No manual mutations
- ✅ Idempotent: Safe to run multiple times
- ✅ Linux-Native: Bash script
- ✅ Metadata: GOV-002 headers

---

### Phase 2: Permission Fix Script (10 min)
**Goal**: Idempotent permission remediation

**Deliverable**: `scripts/ops/fix-deployment-permissions.sh`
- [ ] On both replicas: `sudo chown -R akushnir:akushnir code-server-enterprise/`
- [ ] On both replicas: `sudo chown -R akushnir:akushnir .docker/`
- [ ] Verify ownership change
- [ ] Report any remaining permission issues

**Governance**:
- ✅ IaC: Versioned script
- ✅ Idempotent: Safe to run multiple times
- ✅ Deterministic: Same result every time

---

### Phase 3: NAS Mount Handling (10 min)
**Goal**: Make NAS availability non-blocking

**Options**:
- [ ] Option A: docker-compose conditional volumes (skip if NAS unavailable)
- [ ] Option B: Create NAS mount pre-flight check (fail fast with actionable error)
- [ ] Option C: Use local volumes as fallback

**Recommended**: Option B (fail fast is better than silent mount failure)

**Deliverable**: `scripts/ops/validate-nas-mount.sh`
- [ ] Check NAS 192.168.168.56 is reachable
- [ ] Check /export/appsmith exists
- [ ] Return actionable error if failed
- [ ] Skip non-critical mounts if NAS unavailable

---

### Phase 4: Centralized Deployment Orchestration (20 min)
**Goal**: Single IaC deployment entry point

**Deliverable**: `scripts/ops/deploy-production-iac.sh`
- [ ] Call pre-flight validation
- [ ] Fix permissions on both replicas
- [ ] Validate NAS (skip if needed)
- [ ] Pull latest code on both replicas (parallel SSH)
- [ ] Run docker-compose up -d (parallel SSH)
- [ ] Verify health checks on both replicas
- [ ] Report deployment status

**Governance**:
- ✅ IaC: Entire deployment orchestrated from versioned script
- ✅ Immutable: No manual SSH commands
- ✅ Idempotent: Safe to run multiple times
- ✅ Deterministic: Same deployment result every time
- ✅ Reversible: Instant rollback via git (previous commit)

---

## Implementation Priority

1. **IMMEDIATE** (Next 15 min): Phase 1 + Phase 4 (create deployment orchestrator)
2. **FOLLOW-UP** (Next 10 min): Phase 2 (permission fix)
3. **FOLLOW-UP** (Next 10 min): Phase 3 (NAS validation)

**Rationale**: With centralized orchestrator + pre-flight checks, most deployment issues can be caught and fixed automatically before they block the deployment.

---

## Success Criteria

After implementation:
- ✅ No more manual SSH commands (all in scripts)
- ✅ Pre-flight checks prevent infrastructure surprises
- ✅ Permissions auto-fixed before deployment
- ✅ NAS failures caught before docker-compose fails
- ✅ Deployment is fully repeatable and reversible
- ✅ All code in version control (IaC standard met)
- ✅ All scripts meet GOV-002 governance standards

---

## Files to Create/Update

| File | Purpose | Type |
|------|---------|------|
| `scripts/ops/pre-flight-deployment-check.sh` | Safety validation | NEW |
| `scripts/ops/fix-deployment-permissions.sh` | Permission remediation | NEW |
| `scripts/ops/validate-nas-mount.sh` | NAS availability check | NEW |
| `scripts/ops/deploy-production-iac.sh` | Central orchestrator | NEW |
| `docs/PRODUCTION-DEPLOYMENT-RUNBOOK.md` | Updated with new workflow | UPDATED |

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| SSH keys missing | Pre-flight check validates ~.ssh/id_rsa_onprem |
| Git state dirty | Pre-flight check requires clean working tree |
| Permission fix fails | Script reports error and exits (fail fast) |
| NAS unavailable | Script handles gracefully, skips optional mounts |
| docker-compose fails | Health checks verify all services started |
| Rollback needed | `git reset --hard` to previous commit instantly |

---

## Next Action

Execute Phase 1 + Phase 4: Create `scripts/ops/pre-flight-deployment-check.sh` and `scripts/ops/deploy-production-iac.sh`

**Time estimate**: 25 minutes
**Governance**: 100% IaC/immutable/idempotent
**Expected outcome**: Production-grade deployment orchestration ready for team execution

---

**Status**: ✅ READY TO EXECUTE  
**Next**: Create deployment IaC scripts (Phase 1 + 4)
