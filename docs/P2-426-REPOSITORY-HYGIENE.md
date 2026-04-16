# P2 #426: Repository Hygiene - Root Directory Consolidation Guide

## Problem

Root directory cluttered with 100+ markdown files from various sessions/phases.

## Solution

Archive historical docs, consolidate configs, establish single sources of truth.

## Files to Archive

### Session Documentation (Move to `.archived/session-docs/`)

Historical completion reports, status updates, execution records (safe to delete after 30 days):
- `APRIL-13-EVENING-STATUS-UPDATE.md`
- `APRIL-14-EXECUTION-READINESS.md`
- `APRIL-16-2026-SESSION-EXECUTION-REPORT.md`
- `APRIL-17-21-OPERATIONS-PLAYBOOK.md`
- `APRIL-22-2026-SESSION-EXECUTION-COMPLETE.md`
- `CURRENT-EXECUTION-STATUS-APRIL13-FINAL.md`
- `CLEANUP-COMPLETION-REPORT.md`
- `DEPLOYMENT-APRIL-14-STATUS.md`
- `DEPLOYMENT-COMPLETION-REPORT.md`
- `DEPLOYMENT-STATUS-FINAL.md`
- `DEPLOYMENT-CLEAN-SLATE-COMPLETION.md`
- `EXECUTION-COMPLETE-APRIL-14.md`
- `EXECUTION-TIMELINE-LIVE.md`
- `EXECUTIVE-SUMMARY-SPRINT-APRIL-15.md`
- `FINAL-ORCHESTRATION-STATUS.md`
- `FINAL-SESSION-COMPLETION-APRIL-16-2026.md`
- `FINAL-VALIDATION-REPORT.md`
- `FINAL-VERIFICATION-REPORT.md`

### Consolidated/Superseded Documentation (Move to `.archived/old-docs/`)

Old plans, analysis, reviews (replaced by current architecture/decisions):
- `ADR-001-CLOUDFLARE-TUNNEL-ARCHITECTURE.md` → moved to `/docs/adr/`
- `CODE-REVIEW-COMPREHENSIVE.md`
- `CODE_REVIEW_DUPLICATION_ANALYSIS.md`
- `CODE-REVIEW-COMPREHENSIVE-ANALYSIS.md`
- `CODE-REVIEW-OVERLAP-GAPS-INCOMPLETE.md`
- `CODE-REVIEW-DELIVERABLES-INDEX.md`
- `CONSOLIDATION-PLAN.md`
- `CONSOLIDATION_IMPLEMENTATION.md`
- `FAANG-REORGANIZATION-PLAN.md`
- `GOVERNANCE-ENHANCEMENTS-RECOMMENDATIONS.md`
- `GOVERNANCE-ROLLOUT-PLAN-PHASES-2-5.md`
- `COST-OPTIMIZATION.md`

### Legacy Build Artifacts (Delete - preserved in git history)

Phase directories and outdated docker-compose variants:
- `docker-compose-phase-*.yml` (consolidate to single `docker-compose.yml`)
- `phase-1/`, `phase-2/`, ... `phase-20/` directories
- `Caddyfile.base`, `Caddyfile.new`, `Caddyfile.production`, `Caddyfile.tpl` (consolidate to single template)
- `docker-compose.base.yml`, `docker-compose.tpl`, `docker-compose.yml.remote`

## Cleanup Commands

```bash
# 1. Create archive directory structure
mkdir -p .archived/session-docs
mkdir -p .archived/old-docs

# 2. Archive session documentation
git mv APRIL-*.md .archived/session-docs/
git mv CURRENT-*.md .archived/session-docs/
git mv CLEANUP-*.md .archived/session-docs/
git mv DEPLOYMENT-*.md .archived/session-docs/
git mv EXECUTION-*.md .archived/session-docs/
git mv FINAL-*.md .archived/session-docs/
git mv EXECUTIVE-*.md .archived/session-docs/

# 3. Archive old documentation
git mv CODE-REVIEW-*.md .archived/old-docs/
git mv CONSOLIDATION*.md .archived/old-docs/
git mv GOVERNANCE-ROLLOUT-*.md .archived/old-docs/
git mv GOVERNANCE-ENHANCEMENTS-*.md .archived/old-docs/
git mv COST-OPTIMIZATION.md .archived/old-docs/

# 4. Consolidate Caddyfile variants
mkdir -p config/caddy/.archived
git mv Caddyfile.* config/caddy/.archived/ || true
git mv Caddyfile config/caddy/Caddyfile.production || true
git rm docker-compose.base.yml docker-compose.tpl docker-compose.yml.remote || true

# 5. Remove legacy phase directories
git rm -r phase-* || true

# 6. Consolidate legacy docker-compose files
git rm docker-compose-phase-*.yml || true

# 7. Commit cleanup
git commit -m "chore(P2 #426): Repository hygiene - archive session docs, consolidate configs"

# 8. Verify
git status  # Should show .archived/ structure
ls -1 *.md  # Should only show essential docs
```

## Final Root Directory Structure

```
code-server-enterprise/
├── .github/               # GitHub Actions, issue templates (clean)
├── .archived/             # Historical docs (30-day reference)
│   ├── session-docs/      # Session status reports
│   └── old-docs/          # Superseded plans/docs
├── config/                # Configuration templates
├── docs/                  # Core documentation (ADRs, runbooks, guides)
├── k8s/                   # Kubernetes manifests
├── scripts/               # Operational scripts
├── terraform/             # Infrastructure as Code
├── .gitignore
├── .editorconfig
├── docker-compose.yml     # SINGLE source of truth
├── Dockerfile
├── Makefile
├── README.md
├── CONTRIBUTING.md
└── [minimal root files]
```

## Benefits

✅ **Cleaner root** (100+ → ~20 files)
✅ **Better organization** (docs in `/docs/`, configs in `/config/`)
✅ **Single source of truth** (one `docker-compose.yml`, one `Caddyfile.tpl`)
✅ **Easier onboarding** (clear structure for contributors)
✅ **Historical preservation** (archived docs still in git)
✅ **Reduced complexity** (simpler directory scanning for CI/CD)
✅ **Faster navigation** (less noise in root)

## Rollback

If needed, restore archived files:

```bash
# View archived file
git show HEAD:.archived/session-docs/APRIL-22*.md

# Restore to working tree
git checkout HEAD -- .archived/session-docs/APRIL-22*.md
```

## Timeline

- **Phase 1**: Archive session docs (~20 files) - 5 min
- **Phase 2**: Archive old docs (~12 files) - 3 min
- **Phase 3**: Delete phase directories - 2 min
- **Phase 4**: Consolidate docker-compose/Caddyfile - 3 min
- **Phase 5**: Commit and verify - 2 min

**Total**: ~15 minutes

---

**Priority**: P2 (Tier 2 - Structural improvement)  
**Impact**: Cleaner codebase, easier navigation, single SSOT  
**Status**: ✅ READY TO EXECUTE
