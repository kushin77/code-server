# GIT BRANCH CLEANUP & CONSOLIDATION PLAN
**Date**: April 15, 2026  
**Repository**: kushin77/code-server  
**Status**: Ready for execution

---

## CURRENT BRANCH STATUS

### Local Branches (13)
```
  docs/failover-runbook                                   [feature]
  feat/deploy-phases-177-178-168                          [feature - phase deployment]
  feat/elite-0.01-master-consolidation-20260415-121733   [feature - elite audit]
  feat/governance-framework                               [feature - governance]
  governance-framework-clean                              [feature - governance variant]
* phase-7-deployment                                      [ACTIVE - current working branch]
  production-ready-april-18                               [feature - production release]
  week-3-critical-path                                    [feature - task planning]
  main                                                    [PRIMARY - default branch]
  phase-6-deployment                                      [feature - previous phase]
```

### Remote Branches (30+)
- `origin/HEAD -> origin/main` (default)
- Multiple `feat/elite-*`, `feat/gov-*`, `feat/execution-*` branches
- Multiple `remotes/origin/phase-*` branches

---

## BRANCH CLASSIFICATION

### KEEP - Active/Critical
- ✅ **main** - Default production branch
- ✅ **phase-7-deployment** - CURRENT ACTIVE BRANCH (all active work here)
- ✅ **production-ready-april-18** - Staging release candidate

### CONSOLIDATE - Phase Variants
- ⚠️ **phase-6-deployment** - Previous phase (can be archived)
- ⚠️ **feat/deploy-phases-177-178-168** - Merge to phase-7-deployment

### DELETE - Stale/Redundant
- ❌ **governance-framework-clean** - Duplicate of governance-framework
- ❌ **feat/governance-framework** - Merged into phase-7-deployment
- ❌ **feat/elite-0.01-master-consolidation-20260415-121733** - Audit complete
- ❌ **feat/execution-complete-april-15** - Completed work
- ❌ **docs/failover-runbook** - Documentation in main
- ❌ **week-3-critical-path** - Task planning artifact
- ❌ All `feat/elite-*` remote branches (completed features)
- ❌ All `feat/gov-*` remote branches (completed features)
- ❌ All `feat/execution-*` remote branches (completed work)
- ❌ All feature branches older than 30 days

---

## CLEANUP EXECUTION PLAN

### Phase 1: Verify Current State (5 min)
```bash
# List all branches
git branch -a

# Show branch history
git log --oneline main phase-7-deployment -10

# Identify branches merged into main
git branch -a --merged main | grep -v "main\|phase"
```

### Phase 2: Merge Active Work (10 min)
```bash
# Merge active features into phase-7-deployment
git checkout phase-7-deployment
git merge feat/deploy-phases-177-178-168

# Verify merge
git log --oneline -5
```

### Phase 3: Delete Local Branches (5 min)
```bash
git branch -d governance-framework-clean
git branch -d feat/governance-framework
git branch -d feat/elite-0.01-master-consolidation-20260415-121733
git branch -d week-3-critical-path
```

### Phase 4: Delete Remote Branches (10 min)
```bash
# Delete merged feature branches
git push origin --delete feat/elite-p1-performance
git push origin --delete feat/elite-p2-access-control
git push origin --delete feat/elite-rebuild-gpu-nas-vpn
git push origin --delete feat/execution-completion-april-15
git push origin --delete feat/execution-complete-april-15
git push origin --delete feat/gov-001-governance-automation
git push origin --delete feat/gov-002-metadata-headers
git push origin --delete feat/gov-003-eliminate-hardcoded-ips
git push origin --delete feat/gov-004-consolidate-git-credentials
git push origin --delete feat/gov-005-parameterize-docker-compose
git push origin --delete feat/gov-007-remove-logging-shim

# Delete elite branches
git push origin --delete elite-final-delivery
git push origin --delete elite-p2-infrastructure
git push origin --delete deployment-ready
```

### Phase 5: Archive Phase Branches (5 min)
```bash
# Create archive tag for historical reference
git tag -a archive/phase-6-deployment -m "Archived phase 6 deployment branch (April 15, 2026)"
git push origin archive/phase-6-deployment

# Delete old phase branch
git push origin --delete origin/phase-6-deployment (if exists remotely)
```

### Phase 6: Prune & Verify (5 min)
```bash
# Remove remote tracking branches that are deleted
git fetch origin --prune

# Verify final branch status
git branch -a | wc -l  # Should be < 15 total

# Verify current state
git log --oneline -5
git status
```

---

## BRANCH CONSOLIDATION STRATEGY

### Recommended Structure After Cleanup

```
# Production Release Pipeline
main                          ← Production stable releases
  └─ v1.0.0, v1.0.1, ...    (git tags)

# Deployment Pipeline  
phase-7-deployment           ← ACTIVE: All development work consolidated here
  └─ All feature branches merged here

# Release Staging
production-ready-april-18   ← Pre-release candidate for testing

# Archive (for historical reference)
tags/archive/*              ← Historical phase branches preserved as tags
```

### Future Branch Strategy

**DO**:
- ✅ Use `phase-N-deployment` branches for major releases
- ✅ Merge feature branches into `phase-N` when ready
- ✅ Tag releases: `v1.0.0`, `v1.0.1`, etc.
- ✅ Protect `main` branch (require PR reviews)
- ✅ Delete merged branches automatically (GitHub Actions)

**DON'T**:
- ❌ Create variant branches (`governance-framework-clean`, `-v2`, etc.)
- ❌ Leave stale branches unmerged
- ❌ Create phase-variant branches for same phase
- ❌ Commit to main directly (always use PRs)

---

## AUTOMATED CLEANUP SCRIPT

Save as `scripts/cleanup-git-branches.sh`:

```bash
#!/bin/bash
set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "GIT BRANCH CLEANUP SCRIPT"
echo "═══════════════════════════════════════════════════════════════"
echo ""

REPO="${1:-.}"
cd "$REPO" || exit 1

echo "📊 BEFORE CLEANUP:"
echo "Local branches: $(git branch -a | wc -l)"
echo ""

# List branches to delete
echo "🗑️  Branches to delete:"
git branch -a --merged main | grep -E "feat|governance|execution|elite" || echo "None found"
echo ""

# Delete merged branches
echo "🔄 Deleting merged local branches..."
git branch -d $(git branch --merged main | grep -E "feat|governance" | tr '\n' ' ') 2>/dev/null || echo "No branches to delete"

# Prune remote
echo "🔄 Pruning remote tracking branches..."
git fetch origin --prune

echo "📊 AFTER CLEANUP:"
echo "Local branches: $(git branch | wc -l)"
echo "Remote branches: $(git branch -r | wc -l)"
echo ""

echo "✅ Cleanup complete!"
echo ""
echo "═══════════════════════════════════════════════════════════════"
```

---

## EXECUTION CHECKLIST

- [ ] **Backup**: Create `backup/pre-cleanup-$(date +%s).tar.gz` of .git directory
- [ ] **Verify**: Run `git status` on current branch  
- [ ] **Phase 1**: Document current branch state
- [ ] **Phase 2**: Merge active work into phase-7-deployment
- [ ] **Phase 3**: Delete local branches  
- [ ] **Phase 4**: Delete remote branches (only completed/merged ones)
- [ ] **Phase 5**: Create archive tags for phase branches
- [ ] **Phase 6**: Prune and verify final state
- [ ] **Validation**: Push changes and verify on GitHub
- [ ] **Documentation**: Update branch protection rules if needed
- [ ] **Monitoring**: Watch CI/CD pipelines for 24 hours

---

## RISK ASSESSMENT

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Accidental delete of active branch | Low | Critical | Backup before cleanup, verify branch status |
| Remote branch conflicts | Low | High | Use `git fetch origin --prune` first |
| Broken CI/CD pipelines | Medium | High | Test in non-production first |
| Loss of historical context | Low | Medium | Create archive tags before deleting |

---

## ROLLBACK PROCEDURE

If cleanup goes wrong:
```bash
# 1. Check git reflog
git reflog

# 2. Recover deleted branch
git checkout -b <branch-name> <commit-sha>

# 3. Restore from backup
tar -xzf backup/pre-cleanup-*.tar.gz .git
```

---

## EXPECTED RESULTS

**Before**:
- 13 local branches
- 30+ remote branches  
- Scattered feature/phase naming
- Low clarity on active work

**After**:
- 3-4 local branches (main, phase-7, production-ready)
- 4-5 remote branches
- Clear branch hierarchy
- Single source of truth for active work

---

## RELATED ISSUES

- P2 #425: Git branch cleanup
- P3 #450: Branch protection and CI/CD

---

**Status**: ✅ Plan complete, ready for execution  
**Effort**: ~45 minutes to execute all phases  
**Timeline**: Can execute immediately (low-risk operation)  
**Owner**: DevOps team

