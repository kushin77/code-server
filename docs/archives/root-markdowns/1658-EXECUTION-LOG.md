# P2 #1658 Backend Integration Test Fix — Execution & Results

**Date**: April 24, 2026  
**Task**: Regenerate pnpm-lock.yaml to fix 7 deterministic CI test failures  
**Root Cause**: @vitest/coverage-v8 peer dependency mismatch  
**Expected Outcome**: All 7 backend-integration tests pass  
**Risk**: 🟢 LOW (deterministic fix, backup available)  

---

## Execution Plan

### Phase 1: Backup (< 1 minute)
```bash
cd /mnt/c/code-server-enterprise
cp pnpm-lock.yaml pnpm-lock.yaml.backup
echo "✅ Backup created"
```

**Expected Output**:
```
✅ Backup created
```

**Verification**:
```bash
ls -lh pnpm-lock.yaml pnpm-lock.yaml.backup
# Should show two files of same size
```

---

### Phase 2: Regenerate Lock File (2-3 minutes)
```bash
cd /mnt/c/code-server-enterprise
pnpm install --prefer-frozen-lockfile
```

**Expected Output**:
```
...
✔ installed (all good, n packages)
```

**What This Does**:
1. Reads package.json (current dependencies)
2. Resolves transitive dependencies
3. Recalculates versions for @vitest/coverage-v8 peer deps
4. Updates pnpm-lock.yaml with corrected versions

---

### Phase 3: Verify Regenerated File (< 1 minute)
```bash
# Check file is valid YAML
grep "lockfileVersion:" pnpm-lock.yaml
# Should output: lockfileVersion: '9.0'

# Check file size
wc -c pnpm-lock.yaml pnpm-lock.yaml.backup
# Should show two similar sizes
```

---

### Phase 4: Run Local Tests (2-3 minutes)
```bash
cd /mnt/c/code-server-enterprise/apps/backend
pnpm test
```

**Expected Output** (if successful):
```
 ✓ src/services/auth.test.ts (5) 45ms
 ✓ src/services/database.test.ts (8) 123ms  
 ✓ src/routes/api.test.ts (12) 156ms
 ...
 
✅ All tests passed
Exit code: 0
```

**Before Fix** (current CI failure):
```
ERROR: failed to load coverage plugin
Tests exit at 0 seconds
Exit code: 1
```

---

### Phase 5: Commit & Push (1 minute)
```bash
cd /mnt/c/code-server-enterprise

# Check what changed
git diff pnpm-lock.yaml | head -20

# Stage the change
git add pnpm-lock.yaml

# Commit with issue reference
git commit -m "fix(deps): regenerate pnpm-lock.yaml for #1658

- Recalculate transitive dependencies
- Resolve @vitest/coverage-v8 peer dependency conflict
- Unblocks backend-integration CI tests
- Fixes fingerprint 103706c70d58

Issue: #1658"

# Push to main
git push origin main
```

**Expected Output**:
```
✔ 1 file changed, N insertions(+), N deletions(-)
✔ [main abcd1234] fix(deps): regenerate pnpm-lock.yaml for #1658
✔ Pushing to origin/main...
```

---

## Verification Checklist

- [ ] Backup created and verified (same size as original)
- [ ] `pnpm install --prefer-frozen-lockfile` completed successfully
- [ ] Regenerated lock file is valid YAML
- [ ] Local tests all pass (`pnpm test` exit code 0)
- [ ] Git diff shows only pnpm-lock.yaml changes
- [ ] Commit message includes issue reference (#1658)
- [ ] Pushed to main branch successfully
- [ ] CI pipeline shows tests GREEN

---

## Rollback Procedure (If Needed)

If tests fail after regeneration, instant rollback:

```bash
cd /mnt/c/code-server-enterprise

# Restore from backup
cp pnpm-lock.yaml.backup pnpm-lock.yaml

# Verify restored
pnpm test  # Should show same error as before regeneration

# Document issue in GitHub
# (if rollback was needed, something else is blocking tests)
```

---

## Expected CI Results After Deployment

### Before Fix
```
❌ backend-integration test suite FAILED
   - fingerprint: 103706c70d58
   - all 7 runs show identical error
   - tests exit at 0 seconds
```

### After Fix  
```
✅ backend-integration test suite PASSED
   - fingerprint: 103706c70d58 (resolved)
   - all tests run successfully
   - exit code: 0
```

---

## Timeline

| Phase | Duration | Cumulative |
|-------|----------|-----------|
| Backup | 1 min | 1 min |
| Regenerate | 3 min | 4 min |
| Verify | 1 min | 5 min |
| Test | 3 min | 8 min |
| Commit/Push | 1 min | **9 minutes total** |

**Actual timing will vary based on network speed and machine load.**

---

## Governance Compliance

✅ **IaC**: pnpm-lock.yaml is versioned source of truth  
✅ **Immutable**: No code changes, dependency resolution only  
✅ **Idempotent**: Running pnpm install multiple times = same result  
✅ **Deterministic**: Same package.json → same lock file always  
✅ **Reversible**: Backup available for instant rollback  

---

## Success Criteria

✅ All 7 backend integration tests pass  
✅ CI pipeline shows GREEN  
✅ No new test failures introduced  
✅ Commit includes issue reference (#1658)  
✅ No manual code changes required  

---

## Post-Fix Actions

After successful deployment:

1. **Close Issue #1658**
   - Comment with link to commit
   - Mark as resolved
   
2. **Update CI Dashboard**
   - Verify all tests showing GREEN
   - No new failures
   
3. **Document in Retrospective**
   - Add to lessons learned
   - Note the importance of lock file consistency checks

---

## Related Documentation

- Root Cause Analysis: [1658-BACKEND-INTEGRATION-FIX-COMPLETE.md](1658-BACKEND-INTEGRATION-FIX-COMPLETE.md)
- GitHub Issue: #1658
- CI Workflow: https://github.com/kushin77/code-server/actions

---

**Status**: ✅ READY FOR EXECUTION  
**Priority**: P2 → P1 (CI blocker)  
**Risk**: 🟢 LOW  
**Time**: 7-9 minutes  
**Owner**: Backend/DevOps Team  

**Recommended Action**: Execute immediately (highest impact, lowest risk)
