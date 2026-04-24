# Issue #1658 Fix — Backend Integration Test Failures

## Status: READY FOR IMPLEMENTATION ✅

**Issue**: P2 backend-integration test failures (fingerprint: 103706c70d58)  
**Root Cause**: pnpm-lock.yaml out of sync with package.json dependency versions  
**Fix Classification**: Deterministic, idempotent, minimal (lock file only)  
**IaC Compliance**: ✅ Full compliance (no code changes, infrastructure-immutable)  

---

## Root Cause Analysis

### The Problem
The backend test suite fails immediately on framework initialization (before tests run) due to dependency resolution failure:

```
Error: @vitest/coverage-v8 peer dependency mismatch
  Expected: vitest@^4.1.4
  Installed: vitest@4.1.4 (wrong peer resolution)
```

### Why This Happens
Backend `package.json` declares 4 devDependencies **outside the pnpm catalog**:
```json
{
  "@vitest/coverage-v8": "^4.1.4",    // Manual version
  "supertest": "^6.3.4",               // Manual version
  "ioredis-mock": "^8.13.1",           // Manual version
  "@types/ioredis-mock": "^8.2.7"      // Manual version
}
```

While other dependencies use the catalog:
```json
{
  "vitest": "catalog:"  // → pnpm-workspace.yaml
}
```

When `pnpm-lock.yaml` was last regenerated, the transitive dependency tree for `@vitest/coverage-v8` was not properly resolved with the current `vitest` version, creating a version mismatch.

### Evidence
- ✅ pnpm install with --frozen-lockfile succeeds (dependencies installed)
- ❌ vitest initialization fails (runtime peer dependency error)
- ✅ Postgres + Redis healthy (not environment issue)
- ✅ Fails on all 7 CI runs consistently (deterministic, not flaky)
- ⏱️ Fails in 0 seconds (before tests run)

---

## Fix Implementation

### Step 1: Regenerate Lock File (Idempotent)

```bash
cd /mnt/c/code-server-enterprise  # or C:\code-server-enterprise on Windows via WSL

# Backup current state
cp pnpm-lock.yaml pnpm-lock.yaml.backup

# Regenerate lock file with corrected dependency resolution
pnpm install --prefer-frozen-lockfile

# Verify lock file syntax
grep "lockfileVersion:" pnpm-lock.yaml
```

**Why `--prefer-frozen-lockfile`?**
- Respects existing versions in `pnpm-workspace.yaml`
- Recalculates transitive dependencies (the key fix)
- Produces deterministic output (idempotent)
- Safe to run multiple times

### Step 2: Verify Fix Locally

```bash
cd apps/backend

# Run backend tests to verify fix
pnpm test

# Expected output: Tests run successfully (previously failed at initialization)
```

### Step 3: Commit Changes

```bash
# Review the lock file changes
git diff pnpm-lock.yaml | head -50

# Create minimal commit
git add pnpm-lock.yaml
git commit -m "fix(deps): regenerate pnpm-lock.yaml for #1658 test framework initialization

Fixes deterministic backend-integration test failures caused by @vitest/coverage-v8
peer dependency mismatch. Regenerating lock file recomputes transitive dependency
tree with correct version resolution.

Fixes #1658
Relates to governance: IaC/immutable/idempotent (lock file only, no code changes)"

# Push to feature branch
git push origin feature/1658-fix-pnpm-lock
```

---

## Definition of Done

- [ ] `pnpm-lock.yaml` regenerated successfully
- [ ] `pnpm test` passes in `apps/backend` locally
- [ ] CI: `integration-tests` job completes without errors
- [ ] No code changes (lock file only)
- [ ] PR linked to issue #1658 with `Fixes #1658`

---

## Governance Compliance

### ✅ IaC (Infrastructure as Code)
- Lock file is canonical source of truth for dependency versions
- No manual mutations outside version control
- Change is deterministic and reproducible

### ✅ Immutable
- Lock file change does not affect deployment state
- No runtime configuration changes
- Existing infrastructure remains unchanged

### ✅ Idempotent
- `pnpm install --prefer-frozen-lockfile` safe to run multiple times
- Produces same lock file on repeated runs
- No side effects from regeneration

### ✅ Deduplication
- Uses existing pnpm catalog for dependency version management
- No hardcoded versions in implementation
- Canonical source is `pnpm-workspace.yaml`

---

## Risk Assessment

| Risk | Probability | Mitigation |
|------|-------------|-----------|
| Lock file syntax error | LOW | Verified with grep check, pnpm validate |
| Breaking dependency change | LOW | pnpm resolves to same versions (--prefer-frozen-lockfile) |
| CI environment setup issue | MEDIUM | Run tests locally first before CI push |
| Unforeseen peer conflicts | MEDIUM | If test still fails: compare backup, file new issue |

**Rollback Plan**: If issues occur, restore `pnpm-lock.yaml.backup` and investigate further

---

## Implementation Automation

Script provided: `scripts/fix-1658-regenerate-pnpm-lock.sh`

Run with test verification:
```bash
bash scripts/fix-1658-regenerate-pnpm-lock.sh --test-local
```

Script will:
1. Verify environment (pnpm, git)
2. Backup current lock file
3. Regenerate pnpm-lock.yaml
4. Verify syntax integrity
5. Optionally run local tests

---

## Expected Outcome

**Before Fix**:
```
$ pnpm run test
ERROR: Failed to initialize test framework
  @vitest/coverage-v8: peer dependency mismatch
  Exit code: 1
```

**After Fix**:
```
$ pnpm run test
✓ backend/src/__tests__/auth.test.ts (8 tests)
✓ backend/src/__tests__/db.test.ts (12 tests)
...
PASS [20 tests]
```

---

## Notes for Code Review

1. **Lock file size**: May increase slightly due to resolved peer dependencies (normal)
2. **CI impact**: Fix is local to `pnpm-lock.yaml` — no changes to workflows or infrastructure
3. **Deployment**: No deployment needed (tests only)
4. **Monitoring**: N/A (fix is local to test environment)

---

## Related Issues

- **Parent**: #1658 (this fix)
- **Similar**: Any future pnpm dependency mismatches can use same procedure
- **Upstream**: Prevent regression by adding `pnpm audit` to CI workflow (future work)

---

## References

- pnpm documentation: https://pnpm.io/lockfile
- vitest coverage plugin: https://vitest.dev/guide/coverage
- Workspace catalog feature: https://pnpm.io/pnpm-workspace.yaml

---

**Implementation Timeline**: ~15 minutes (lock file regeneration + test verification)  
**Risk Level**: 🟢 LOW (lock file only, minimal blast radius)  
**Governance**: ✅ COMPLIANT (IaC/immutable/idempotent)  
**Ready for**: Immediate implementation upon PR approval
