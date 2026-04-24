# Issue #1658 — Execution Checklist & Step-by-Step Guide

## Prerequisites Verified ✅
- [x] Root cause identified: pnpm-lock.yaml out of sync with package.json
- [x] Solution documented: pnpm install --prefer-frozen-lockfile (idempotent, deterministic)
- [x] Governance compliant: IaC/Immutable/Idempotent
- [x] Scripts prepared: Python fix script + bash fix script
- [x] Documentation complete: 3 guides + execution checklist
- [x] Backup plan ready: restore pnpm-lock.yaml.backup if needed

## Implementation Method: Choose One

### Option A: Python Script (Recommended - Most Reliable)
```bash
cd c:\code-server-enterprise
python3 fix-issue-1658.py --test-local
```

**Steps Automated**:
1. Backup current pnpm-lock.yaml
2. Run pnpm install --prefer-frozen-lockfile
3. Verify lock file syntax
4. Run backend tests to confirm fix
5. Stage changes for commit
6. Show commit instructions

**Expected Output**: ✓ Fix implementation complete - Ready for commit and push

### Option B: Bash Script (Alternative)
```bash
cd c:\code-server-enterprise
bash scripts/fix-1658-regenerate-pnpm-lock.sh --test-local
```

### Option C: Manual Steps (If Scripts Fail)

#### Step 1: Navigate to repo
```bash
cd c:\code-server-enterprise
```

#### Step 2: Backup current lock file
```bash
cp pnpm-lock.yaml pnpm-lock.yaml.backup
```

#### Step 3: Regenerate lock file
```bash
pnpm install --prefer-frozen-lockfile
```

**What this does**:
- Recalculates transitive dependency tree
- Fixes @vitest/coverage-v8 peer dependency mismatch
- Produces deterministic, reproducible output
- Safe to run multiple times (idempotent)

#### Step 4: Verify syntax
```bash
grep "lockfileVersion:" pnpm-lock.yaml
# Expected: lockfileVersion: '9.0'
```

#### Step 5: Run backend tests
```bash
cd apps/backend
pnpm test
# Expected: Tests pass (previously failed at framework initialization)
```

#### Step 6: Review changes
```bash
cd ../..
git diff pnpm-lock.yaml | head -50
```

#### Step 7: Stage changes
```bash
git add pnpm-lock.yaml
```

#### Step 8: Commit
```bash
git commit -m "fix(deps): regenerate pnpm-lock.yaml for #1658 test framework initialization

Fixes deterministic backend-integration test failures caused by @vitest/coverage-v8
peer dependency mismatch. Regenerating lock file recomputes transitive dependency
tree with correct version resolution.

Fixes #1658"
```

#### Step 9: Push to main
```bash
git push origin main
```

---

## Post-Execution Verification

### Verification 1: Confirm Commit
```bash
git log --oneline -1
# Should show: fix(deps): regenerate pnpm-lock.yaml for #1658 test framework initialization
```

### Verification 2: Verify Production Stability
```bash
# Confirm both replicas remain in sync
echo "=== COMMIT PARITY ==="
git -C . rev-parse --short HEAD
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && git rev-parse --short HEAD"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "cd code-server-enterprise && git rev-parse --short HEAD"
# All three should return same commit

echo "=== GIT DRIFT ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && git status --short | wc -l"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "cd code-server-enterprise && git status --short | wc -l"
# Both should return 0 (zero modifications)

echo "=== SERVICE HEALTH ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker ps --quiet | wc -l"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps --quiet | wc -l"
# Both should return 20 (20 services UP per replica)
```

### Verification 3: Health Endpoints
```bash
# Root endpoint (should return 403 - auth required)
curl -I https://ide.kushnir.cloud/
# Expected: 403 Forbidden

# Health endpoint (should return 200)
curl -I https://ide.kushnir.cloud/health
# Expected: 200 OK
```

### Verification 4: CI/CD Pipeline
- Watch GitHub Actions for workflow runs
- Expected: backend-integration tests pass
- Expected: All 63 open issues remain open (no new failures)

---

## Success Criteria Checklist

- [ ] `pnpm-lock.yaml` regenerated without errors
- [ ] `pnpm test` passes in `apps/backend`
- [ ] Git diff shows only `pnpm-lock.yaml` changes
- [ ] Commit message follows conventional commits format
- [ ] Commit includes `Fixes #1658` reference
- [ ] Commit pushed to origin/main
- [ ] Both replicas still synchronized (same commit)
- [ ] All 20 services remain UP on both replicas
- [ ] Health endpoint returns 200 OK
- [ ] CI workflow completes successfully

---

## Rollback Plan (If Needed)

### If tests fail after regeneration:

```bash
# Restore from backup
mv pnpm-lock.yaml.backup pnpm-lock.yaml

# Reset git
git reset --hard

# Verify restoration
pnpm install --frozen-lockfile

# Investigate issue
# File new GitHub issue with detailed error output
```

### If replicas become desynchronized:

```bash
# On both replicas, pull from main
ssh akushnir@192.168.168.31 "cd code-server-enterprise && git pull --ff-only origin main"
ssh akushnir@192.168.168.42 "cd code-server-enterprise && git pull --ff-only origin main"

# Restart services if needed
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker compose up -d"
ssh akushnir@192.168.168.42 "cd code-server-enterprise && docker compose up -d"
```

---

## Governance Compliance Matrix

| Principle | Status | Verification |
|-----------|--------|--------------|
| **IaC** | ✅ | pnpm-lock.yaml is git-controlled canonical source |
| **Immutable** | ✅ | No code changes, lock file only, no infrastructure modifications |
| **Idempotent** | ✅ | `pnpm install --prefer-frozen-lockfile` safe to run multiple times with same result |
| **Deduplication** | ✅ | Uses existing pnpm catalog for versions, no hardcoding |

---

## Timeline & Effort Estimate

| Phase | Estimated Time | Status |
|-------|-----------------|--------|
| Lock file regeneration | 2-5 minutes | Ready |
| Test verification | 1-3 minutes | Ready |
| Git operations | < 1 minute | Ready |
| Production verification | 2-3 minutes | Ready |
| **Total** | **~10-15 minutes** | **Ready** |

---

## Key Documents

1. **[ISSUE-1658-EXECUTION-GUIDE-APRIL-23.md](../ISSUE-1658-EXECUTION-GUIDE-APRIL-23.md)** — Complete step-by-step guide
2. **[1658-BACKEND-INTEGRATION-FIX.md](../1658-BACKEND-INTEGRATION-FIX.md)** — Root cause analysis
3. **[fix-issue-1658.py](../fix-issue-1658.py)** — Python implementation script
4. **[scripts/fix-1658-regenerate-pnpm-lock.sh](../scripts/fix-1658-regenerate-pnpm-lock.sh)** — Bash implementation script

---

## Questions & Troubleshooting

### Q: What if `pnpm` is not installed?
**A**: Install pnpm globally: `npm install -g pnpm@latest` (requires Node.js)

### Q: What if tests still fail after regeneration?
**A**: Restore backup (`mv pnpm-lock.yaml.backup pnpm-lock.yaml`) and file new issue with detailed error output

### Q: Can I run this on multiple replicas?
**A**: No - execute once on main/dev environment, then push to origin/main. Replicas pull automatically.

### Q: How long does `pnpm install --prefer-frozen-lockfile` take?
**A**: 2-5 minutes depending on system performance and network

### Q: Is it safe to run multiple times?
**A**: Yes - the command is idempotent and produces same lock file on repeated runs

---

## Status: ✅ READY FOR EXECUTION

All preparations complete. This fix is:
- **Deterministic** (reproducible results)
- **Idempotent** (safe to rerun)
- **Minimal** (lock file only, no code changes)
- **Compliant** (IaC/Immutable/Idempotent governance)
- **Documented** (3 guides + checklist + scripts)

**Execute using**: Option A (Python script) or Option B (Bash script)

---

**Prepared**: April 23, 2026  
**Issue**: #1658 (P2 Backend Integration Test Failures)  
**Governance**: ✅ Fully Compliant
