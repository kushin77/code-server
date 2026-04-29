# Workspace Cleanup - Quick Start Guide

**Priority:** HIGH | **Estimated Effort:** 20-30 hours | **Risk:** Low (with verification)

---

## 📊 BEFORE/AFTER SUMMARY

```
CATEGORY                BEFORE      AFTER       REDUCTION   PRIORITY
─────────────────────────────────────────────────────────────────────
Root MD Files             295        40          86%        HIGH
Scripts Organization      1,171      1,171       ~0%*       MEDIUM
  * Consolidation only, duplicates resolved
Docker-compose Files       27         3-5        81%        MEDIUM
Artifacts Folders         220         50         77%        HIGH
Git Repository Size        77M        65M        16%        LOW
Total Repo Size          ~150M      ~100M       33%        ✅
─────────────────────────────────────────────────────────────────────
```

---

## ⚡ QUICK START (Do This First)

### 1. Create Backup Branch (SAFE - No Changes Yet)
```bash
cd /home/akushnir/code-server
git checkout -b cleanup-backup-$(date +%Y%m%d)
git push -u origin cleanup-backup-$(date +%Y%m%d)
echo "✅ Backup created. Can always reset to this point."
```

### 2. Verify Current State
```bash
# Count files that will be moved
echo "=== ARCHIVABLE FILES ===" && \
ls -1 *COMPLETE*.md *FINAL*.md *STATUS*.md *REPORT*.md 2>/dev/null | wc -l && \
ls -1 PHASE*.md 2>/dev/null | wc -l && \
find .backups .bootstrap-state -type f 2>/dev/null | wc -l
```

### 3. Stage 1: Create New Folder Structure
```bash
# Create all new folders at once
mkdir -p docs/archive/{completed,phase-summaries,sessions,retired,docker-compose-variants}
mkdir -p scripts/archive/deprecated-$(date +%Y%m%d)
mkdir -p artifacts/archive
mkdir -p docs/archive/.backup-history/$(date +%Y%m-%d)

echo "✅ New folder structure created"
git add -A
git commit -m "chore: create cleanup folder structure"
```

### 4. Stage 2: Move Documentation (Low Risk)
```bash
# Move COMPLETION/FINAL/STATUS/REPORT files
find . -maxdepth 1 \( \
  -name '*COMPLETE*.md' -o \
  -name '*FINAL*.md' -o \
  -name '*STATUS*.md' -o \
  -name '*REPORT*.md' \
\) -type f -exec mv {} docs/archive/completed/ \;

# Move PHASE files
find . -maxdepth 1 -name 'PHASE*.md' -type f -exec mv {} docs/archive/phase-summaries/ \;

# Move SESSION files
find . -maxdepth 1 -name 'SESSION*.md' -type f -exec mv {} docs/archive/sessions/ \;

git add -A
git commit -m "chore: archive 150+ completion and phase documentation"
echo "✅ Moved ~150 documentation files"
```

### 5. Stage 3: Archive Bootstrap/Backup Artifacts
```bash
# Archive old backup state
mkdir -p docs/archive/.backup-history/$(date +%Y-%m-%d)
[[ -d .backups ]] && mv .backups/* docs/archive/.backup-history/$(date +%Y-%m-%d)/ && rmdir .backups
[[ -d .bootstrap-state ]] && mv .bootstrap-state/* docs/archive/.backup-history/$(date +%Y-%m-%d)/ && rmdir .bootstrap-state

git add -A
git commit -m "chore: archive bootstrap and backup state"
echo "✅ Archived .backups (3.1M) and .bootstrap-state (468K)"
```

### 6. Stage 4: Consolidate Docker-compose Files
```bash
# Move phase-specific docker-compose files
for f in docker-compose.phase-*.yml docker-compose.infrastructure-v*.yml; do
  [[ -f "$f" ]] && mv "$f" docs/archive/docker-compose-variants/
done

# Clean up duplicates
rm -f docker-compose.prod.yml  # Duplicate of production.yml
rm -f docker-compose.production-clean.yml
rm -f docker-compose.production-test.yml

git add -A
git commit -m "chore: consolidate docker-compose variants (27 → 3)"
echo "✅ Docker-compose consolidated: 27 files → 3 active + archived"
```

### 7. Stage 5: Git Cleanup
```bash
# Aggressive garbage collection
git gc --aggressive --prune=now

# Check reduction
echo "Before cleanup: 77M"
echo "After cleanup: $(du -sh .git | cut -f1)"

git add -A
git commit -m "chore: git garbage collection"
```

---

## 📋 VERIFICATION CHECKLIST

After each stage, verify nothing broke:

```bash
# ✅ Verify docs still navigable
echo "Docs count: $(find docs -type f -name '*.md' | wc -l)"

# ✅ Verify scripts still exist and work
echo "Scripts count: $(find scripts -name '*.sh' | wc -l)"
bash -n scripts/operations/*.sh && echo "✅ Script syntax OK"

# ✅ Verify git is healthy
git fsck --full && echo "✅ Git objects OK"

# ✅ Verify key files referenced in CI still exist
for f in scripts/ops/deploy.sh terraform/main.tf docker-compose.yml; do
  [[ -f "$f" ]] && echo "✅ $f OK" || echo "❌ $f MISSING"
done

# ✅ Verify CI/CD workflow references
grep -l "docker-compose" .github/workflows/*.yml | head -3 | while read f; do
  grep "docker-compose" "$f" | head -2
done
```

---

## 🔍 HIGH-IMPACT CLEANUP OPPORTUNITIES

### Option A: Aggressive (Full Cleanup - 20-30 hours)
✅ Do all stages above plus:
- Reorganize scripts/ folder structure (scripts/ops/ → scripts/operations/)
- Consolidate duplicate scripts (7 found: add-trap-handlers.sh, etc.)
- Create comprehensive MANIFEST files

### Option B: Conservative (Documentation Only - 2-4 hours)
✅ Just do Stages 1-4:
- Move old docs to archive
- Consolidate docker-compose
- Clean up bootstrap artifacts
- **Keep scripts as-is** (safe, can refactor later)

### Option C: Minimal (Essential Only - 1-2 hours)
✅ Just do Stages 2-3:
- Move completion/phase docs
- Archive bootstrap state
- **Everything else stays**

---

## 🎯 RECOMMENDED PATH

**Start with Option B (Conservative)** - Stages 1-5

**Why:**
- Low risk, high reward (33% size reduction)
- No script rewiring needed
- Can always do aggressive refactor later
- Cleanest fastest path to results

**Timeline:**
- Stages 1-3: 30 minutes
- Stage 4: 15 minutes (docker-compose)
- Stage 5: 10 minutes (git gc)
- Verification: 15 minutes
- **Total: 70 minutes**

---

## ⚠️ ROLLBACK PROCEDURE

If anything breaks:

```bash
# Option 1: Reset to backup branch (safest)
git reset --hard cleanup-backup-$(date +%Y%m%d)

# Option 2: Reset to specific commit
git log --oneline | head -10
git reset --hard <commit-sha>

# Option 3: If needed, restore from archive
git checkout <backup-branch>:docs/archive/  # Get archived docs back
```

---

## 📊 WHAT GETS ARCHIVED (Safe to Move)

**These are NOT active and can be safely archived:**

| Category | Count | Examples | Destination |
|----------|-------|----------|-------------|
| PHASE docs | 28 | PHASE-06-*.md, PHASE8_*.md | `docs/archive/phase-summaries/` |
| SESSION docs | 9 | SESSION_5_COMPLETION.md | `docs/archive/sessions/` |
| Completion docs | 47 | *COMPLETE*.md, *FINAL*.md | `docs/archive/completed/` |
| Status reports | 50 | *STATUS*.md, *REPORT*.md | `docs/archive/completed/` |
| Bootstrap state | 116 | .bootstrap-state/*.json | `docs/archive/.backup-history/` |
| Old backups | 307 | .backups/deduplication-* | `docs/archive/.backup-history/` |
| Phase-specific compose | 8 | docker-compose.phase-*.yml | `docs/archive/docker-compose-variants/` |

**What stays in root (active, frequently referenced):**
```
README.md
START_HERE.md
INDEX.md
QUICK_REFERENCE.md
OPERATIONS_RUNBOOK.md
docker-compose.yml
docker-compose.production.yml
.env*
Dockerfile*
package.json
```

---

## 🚀 NEXT SESSION TASKS

After cleanup completes:

**Week 1 (This):**
- [ ] Execute cleanup stages 1-5
- [ ] Verify all tests pass
- [ ] Commit changes

**Week 2:**
- [ ] Optional: Script reorganization (if time permits)
- [ ] Optional: Consolidate duplicate scripts
- [ ] Create SCRIPT_MANIFEST.md

**Week 3:**
- [ ] Update documentation links
- [ ] Train team on new structure
- [ ] Establish maintenance policy

---

## 📞 NEED HELP?

**If something breaks:**
1. Stop and check `git status`
2. Review what files were moved
3. Reset to backup branch if needed: `git reset --hard cleanup-backup-...`
4. Reference detailed plan: [WORKSPACE_CLEANUP_PLAN.md](WORKSPACE_CLEANUP_PLAN.md)

**Questions about specific files?**
- Check what's referenced: `grep -r "filename" . --include='*.sh' --include='*.md'`
- Check git history: `git log --all -- filename`
- Check if file is active: `find . -name filename -newer 2026-04-20`

---

## ✅ SUCCESS CRITERIA

After cleanup:
- [ ] Root directory has ~40 files (was 295)
- [ ] `docs/archive/` has organized historical docs
- [ ] `scripts/` still has all 1,171 scripts (just organized)
- [ ] All CI/CD workflows still pass
- [ ] `git status` shows clean repo
- [ ] Team can still navigate documentation
- [ ] Git repo is ~33% smaller
- [ ] `du -sh .git` shows significant reduction

---

**Ready to start? Run Stage 1 (backup) first, then come back for verification.**
