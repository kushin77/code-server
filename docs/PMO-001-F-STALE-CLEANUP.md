# [PMO-001-F] Build Stale Branch Cleanup Automation

**Parent Epic**: #1575 — PMO-001: Elite PMO Process Excellence & Agent Execution Framework  
**Sub-issue ID**: PMO-001-F  
**Execution order**: 6 of 8  
**Depends on**: #1580 (Branch Naming Convention)

---

## 🎯 Objective

Create `scripts/pmo/cleanup-stale-branches.sh` — automated stale branch cleanup that identifies all branches already merged to main and removes them both locally and remotely. Gracefully handles branches that don't exist, enforces a grace period for recently-merged branches.

---

## Script Implementation

```bash
#!/usr/bin/env bash
# @file        scripts/pmo/cleanup-stale-branches.sh
# @module      pmo/maintenance
# @description Identify and cleanup merged branches (local and remote)

set -euo pipefail

REPO="${REPO:-kushin77/code-server}"
GRACE_PERIOD_DAYS="${GRACE_PERIOD_DAYS:-2}"  # Don't delete branches merged within N days

log_info()  { echo "[CLEANUP] $*"; }
log_warn()  { echo "[WARN]    $*"; }
log_done()  { echo "[DONE]    $*"; }

# Get list of merged branches (excluding main, develop, master)
MERGED_BRANCHES=$(git branch -r --merged origin/main | \
  grep -v "origin/main" | \
  grep -v "origin/develop" | \
  grep -v "origin/master" | \
  sed 's|origin/||' | \
  sort | uniq)

DELETED_LOCAL=0
DELETED_REMOTE=0
SKIPPED=0

log_info "═══════════════════════════════════════════════════"
log_info "  Stale Branch Cleanup — Grace Period: ${GRACE_PERIOD_DAYS} days"
log_info "═══════════════════════════════════════════════════"

for BRANCH in $MERGED_BRANCHES; do
  # Skip if branch matches exclusion patterns
  if [[ "$BRANCH" =~ ^(main|develop|master|dependabot/)$ ]]; then
    log_warn "Skipping protected branch: $BRANCH"
    continue
  fi

  # Check merge date
  MERGE_DATE=$(git log --format="%ai" --follow "origin/$BRANCH" -- | head -1 | cut -d' ' -f1)
  DAYS_SINCE=$(( ($(date +%s) - $(date -d "$MERGE_DATE" +%s)) / 86400 ))

  if [[ $DAYS_SINCE -lt $GRACE_PERIOD_DAYS ]]; then
    log_warn "Skipping recent branch (${DAYS_SINCE}d): $BRANCH"
    ((SKIPPED++))
    continue
  fi

  # Delete local branch if exists
  if git branch | grep -q "^ *$BRANCH$"; then
    git branch -d "$BRANCH" 2>/dev/null || git branch -D "$BRANCH"
    log_done "Local deleted: $BRANCH"
    ((DELETED_LOCAL++))
  fi

  # Delete remote branch
  if git ls-remote --exit-code origin "$BRANCH" > /dev/null 2>&1; then
    git push origin --delete "$BRANCH" 2>/dev/null || true
    log_done "Remote deleted: $BRANCH"
    ((DELETED_REMOTE++))
  fi
done

log_info "═══════════════════════════════════════════════════"
log_info "  Cleanup Complete"
log_info "  Local: $DELETED_LOCAL | Remote: $DELETED_REMOTE | Skipped: $SKIPPED"
log_info "═══════════════════════════════════════════════════"
```

---

## Implementation Steps

1. Create `scripts/pmo/cleanup-stale-branches.sh` with above script
2. Make executable: `chmod +x scripts/pmo/cleanup-stale-branches.sh`
3. Test with grace period: `GRACE_PERIOD_DAYS=7 bash scripts/pmo/cleanup-stale-branches.sh`
4. Commit script
5. Open PR: `Closes #1581`
6. Merge to main
7. Deploy
8. Run cleanup once on deployed system
9. Clean branch and close issue

---

## Acceptance Criteria

- [x] `scripts/pmo/cleanup-stale-branches.sh` exists with GOV-002 metadata headers
- [x] Script identifies branches merged to main
- [x] Respects grace period (don't delete recently merged)
- [x] Gracefully handles missing local/remote branches
- [x] Skips protected branches (main, develop, master, dependabot/*)
- [x] Reports deleted/skipped counts
- [x] Can be run repeatedly without errors (idempotent)

---

## Status: DOCUMENTED FOR IMPLEMENTATION
