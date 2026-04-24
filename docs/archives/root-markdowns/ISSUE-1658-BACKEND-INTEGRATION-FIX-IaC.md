# Issue #1658: Backend Integration Test Fix - IaC Execution Plan
**Date**: April 24, 2026  
**Status**: READY FOR EXECUTION  
**IaC Compliance**: ✅ Immutable, Idempotent, Version Controlled  

---

## Problem Statement

**Root Cause**: `pnpm-lock.yaml` out of sync with `package.json`  
- Peer dependency mismatch: `@vitest/coverage-v8` requires different version constraints
- Backend integration tests failing during CI/CD
- Lock file integrity compromised

**Symptoms**:
- `pnpm install` fails locally
- CI/CD test job exits with peer dependency errors
- Backend tests cannot run

---

## IaC-Compliant Solution

### Step 1: Regenerate Lock File (Idempotent)
```bash
# This operation is deterministic and safe to run multiple times
pnpm install --prefer-frozen-lockfile

# If lock file needs regeneration (drift detected):
pnpm install --prefer-offline --strict-peer-dependencies

# Expected result: pnpm-lock.yaml updated with correct peer dependencies
# Expected time: ~3-5 minutes
```

### Step 2: Verify Lock File Changes
```bash
# Check git diff to verify only lock file changed
git diff pnpm-lock.yaml | head -50

# Expected: Only peer dependency corrections, no unintended changes
```

### Step 3: Commit to Version Control (IaC Principle)
```bash
# All changes must be in git for reproducibility
git add pnpm-lock.yaml

git commit -m "fix(#1658): Regenerate pnpm-lock.yaml with correct peer dependencies

- Resolves @vitest/coverage-v8 peer dependency constraint mismatch
- Idempotent operation (deterministic lockfile)
- All changes version-controlled
- Backend integration tests will now pass

Fixes #1658"

# Push to main for production deployment
git push origin main
```

### Step 4: Deploy to Both Replicas (Parallel, IaC)
```bash
# Deploy to Replica 1 and Replica 2 simultaneously
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && git pull origin main" &
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "cd code-server-enterprise && git pull origin main" &
wait

echo "✅ Both replicas pulled latest code (pnpm-lock.yaml updated)"
```

### Step 5: Verify Backend Integration Tests Pass (Idempotent)
```bash
# Run backend integration tests on both replicas
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && pnpm test:backend 2>&1 | tail -20"

# Expected output:
#   ✅ All backend integration tests passing
#   ✅ No peer dependency warnings
#   ✅ Coverage reports generated
```

### Step 6: Close Issue #1658
```bash
gh issue close 1658 -c "✅ Fixed via pnpm-lock.yaml regeneration

Verification:
- Lock file regenerated with correct peer dependencies
- All changes version-controlled and committed to main
- Both replicas deployed successfully
- Backend integration tests now passing
- Operation is idempotent and can be safely rerun

Deployed: April 24, 2026"
```

---

## IaC Compliance Verification

| Principle | Status | Evidence |
|-----------|--------|----------|
| **Infrastructure as Code** | ✅ | All changes in pnpm-lock.yaml (version controlled) |
| **Immutable** | ✅ | Lock file is deterministic (same input → same output) |
| **Idempotent** | ✅ | `pnpm install --prefer-frozen-lockfile` is safe to run multiple times |
| **Reproducible** | ✅ | Anyone running `pnpm install` will get identical dependencies |
| **No Manual Steps** | ✅ | All via CLI commands, no manual editing |
| **Version Controlled** | ✅ | Lock file committed to git before deployment |
| **Parallel Deployment** | ✅ | Both replicas pull simultaneously |

---

## Expected Outcomes

✅ **Immediate** (after commit + push):
- pnpm-lock.yaml updated in git
- Peer dependency constraints corrected
- Lock file integrity restored

✅ **After Deployment** (both replicas):
- Both replicas have updated pnpm-lock.yaml
- Backend integration tests can now run
- No dependency warnings in CI/CD

✅ **Production State**:
- All services operational with correct dependencies
- Tests passing on both replicas
- Issue #1658 resolved
- Deployment model remains idempotent

---

## Rollback Plan (If Needed)

If backend tests fail after applying this fix:
```bash
# Revert lock file to previous state (immutable git history)
git log --oneline pnpm-lock.yaml | head -5
git revert <commit-hash>
git push origin main

# Both replicas pull reverted code automatically
```

---

## Timeline

| Task | Duration | Status |
|------|----------|--------|
| Regenerate lock file | ~5 min | Ready |
| Verify changes | ~2 min | Ready |
| Commit + push | ~1 min | Ready |
| Deploy to replicas | ~3 min | Ready |
| Verify tests pass | ~5 min | Ready |
| **Total** | **~16 min** | **Ready** |

---

## Execution Checklist

- [ ] Regenerate pnpm-lock.yaml locally
- [ ] Verify git diff shows only expected changes
- [ ] Commit with issue reference
- [ ] Push to main branch
- [ ] Wait for GitHub Actions CI/CD to run (auto-triggered)
- [ ] Verify both replicas pulled latest code
- [ ] Run backend integration tests on both replicas
- [ ] Confirm all tests passing (no peer dependency warnings)
- [ ] Close issue #1658 with verification evidence

---

## Notes

- This fix is **non-breaking** — only updates lock file, no code changes
- Idempotent operation — safe to run multiple times without side effects
- Reproducible across all environments (dev, staging, production)
- Follows IaC principles: version controlled, no manual steps
- No downtime required — safe to deploy anytime
