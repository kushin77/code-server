# P2-426: Repository Hygiene & Consolidation Guide

## Overview

This document provides best practices for maintaining code-server repository hygiene, eliminating duplication, and consolidating infrastructure-as-code assets.

## Repository Structure Health Check

Run this to assess current repository state:

```bash
# Check for duplicate files
find . -type f -name "*.yml" -o -name "*.yaml" | sort | uniq -d

# Find large files
find . -type f -size +10M

# Count files by type
find . -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn

# Check git history size
du -sh .git

# Identify stale branches (>30 days old)
git branch -vv | grep "gone\]"
```

## Duplication Elimination

### Docker Compose Consolidation

**Problem**: Multiple `docker-compose*.yml` files with overlapping services

**Solution**: Single source of truth with profile-based composition

```yaml
# ❌ BEFORE: Multiple files
docker-compose.yml          (core services)
docker-compose.ai.yml       (copy of core + ollama)
docker-compose.prod.yml     (copy of core + monitoring)
docker-compose.full.yml     (all services)

# ✅ AFTER: Single file with profiles
docker-compose.yml          (all services with profiles)
docker-compose.production.yml (production overrides only)
```

### Terraform Consolidation

**Problem**: Multiple main.tf, variables.tf, outputs.tf files across phases

**Solution**: Unified directory structure with phase-based modules

```
# ❌ BEFORE
phase-15/main.tf
phase-16/main.tf
phase-18/main.tf
(duplicated provider configs, variables)

# ✅ AFTER
terraform/
  ├── main.tf              (primary config)
  ├── variables.tf         (all variables)
  ├── outputs.tf           (all outputs)
  ├── provider.tf          (single provider block)
  └── modules/
      ├── phase-2/         (only phase-specific logic)
      ├── phase-3/
      └── phase-4/
```

### Documentation Consolidation

**Problem**: Multiple status documents, completion reports

**Solution**: Single issue-driven SSOT (Single Source of Truth)

```
# ❌ BEFORE
APRIL-13-EVENING-STATUS-UPDATE.md
APRIL-14-EXECUTION-READINESS.md
APRIL-16-2026-SESSION-EXECUTION-REPORT.md
APRIL-17-21-OPERATIONS-PLAYBOOK.md
(scattered, hard to find)

# ✅ AFTER
docs/
  ├── session-reports/     (timestamped archive)
  │   └── 2026-04-16.md
  ├── CURRENT-STATUS.md    (single SSOT, updated continuously)
  └── operations/
      └── runbooks/
```

## File Organization Best Practices

### Kubernetes Manifests

**Current**: Mixed locations (k8s/, config/, root)

**Ideal**:
```
k8s/
├── namespaces/
│   └── token-services.yaml
├── deployments/
│   ├── code-server.yaml
│   ├── oauth2-proxy.yaml
│   └── token-microservice.yaml
├── services/
│   └── *.yaml
├── ingress/
│   └── *.yaml
├── rbac/
│   ├── roles.yaml
│   ├── rolebindings.yaml
│   └── serviceaccounts.yaml
└── policies/
    ├── networkpolicy.yaml
    └── poddisruptionbudget.yaml
```

### Configuration Files

**Current**: Scattered (Caddyfile, config/, root)

**Ideal**:
```
config/
├── web/
│   ├── caddy/
│   │   ├── Caddyfile.base
│   │   ├── Caddyfile.production
│   │   └── Caddyfile.staging
│   └── oauth2-proxy/
│       └── config.yaml
├── monitoring/
│   ├── prometheus.yml
│   ├── alertmanager.yml
│   └── grafana.ini
├── database/
│   ├── postgresql/
│   │   └── init.sql
│   └── redis/
│       └── redis.conf
├── iam/
│   ├── service-accounts.yaml
│   └── rbac-policy.yaml
└── app/
    └── code-server/
        └── settings.json
```

### Scripts Organization

**Current**: scripts/ has mixed purposes (build, deploy, monitor)

**Ideal**:
```
scripts/
├── build/
│   ├── build-images.sh
│   └── build-docker.sh
├── deploy/
│   ├── deploy-k8s.sh
│   ├── deploy-terraform.sh
│   └── deploy-docker.sh
├── monitor/
│   ├── health-check.sh
│   ├── metrics-query.sh
│   └── memory-dashboard.sh
├── maintenance/
│   ├── backup.sh
│   ├── cleanup.sh
│   └── migrate.sh
├── utils/
│   ├── logging.sh
│   ├── error-handling.sh
│   └── color-output.sh
└── dev/
    ├── local-setup.sh
    └── test-locally.sh
```

## Cleanliness Checks

### Pre-Commit Validation

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
set -e

echo "🔍 Running repository hygiene checks..."

# Check for large files (>5MB)
if git diff --cached --name-only | xargs -I {} sh -c 'wc -c < {} > /tmp/size && [ $(cat /tmp/size) -gt 5242880 ] && echo "{}"' | grep -q .; then
    echo "❌ Large files detected (>5MB)"
    exit 1
fi

# Check for duplicate YAML keys
for file in $(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(yml|yaml)$'); do
    if grep -E '^[a-z_]+:.*\n.*\1:' "$file"; then
        echo "❌ Duplicate YAML keys in $file"
        exit 1
    fi
done

# Check for unencrypted secrets
if git diff --cached -S 'password\|secret\|token\|key' --name-only | grep -v '\.env\.example'; then
    echo "⚠️  Potential secrets in staged files"
    exit 1
fi

echo "✅ Repository hygiene checks passed"
```

### Regular Hygiene Audits

**Weekly**:
```bash
# Check for stale branches
git branch -vv | grep gone

# Find uncommitted changes
git status --porcelain

# Verify no large objects
find . -size +10M -type f
```

**Monthly**:
```bash
# Git history analysis
git log --stat | head -50

# Identify unused configs
grep -r "deprecated\|obsolete\|TODO: remove" .

# Docker image cleanup
docker image prune --filter "dangling=true"

# Unused variables in Terraform
terraform fmt -recursive -check .
```

## Consolidation Checklist

### Phase 1: Audit
- [ ] Document current state (file counts, duplications)
- [ ] Identify critical path files (must keep)
- [ ] Map interdependencies
- [ ] Create consolidation plan with timeline

### Phase 2: Deduplication
- [ ] Consolidate docker-compose files
- [ ] Merge Terraform configurations
- [ ] Combine documentation
- [ ] Unify monitoring configs

### Phase 3: Reorganization
- [ ] Implement ideal file structure
- [ ] Update references and imports
- [ ] Test all deployment paths
- [ ] Verify CI/CD still works

### Phase 4: Cleanup
- [ ] Archive old files (to `archive/` for 30 days)
- [ ] Remove deprecations
- [ ] Update .gitignore
- [ ] Final verification tests

### Phase 5: Documentation
- [ ] Update README
- [ ] Create file structure guide
- [ ] Document new organization
- [ ] Add to CONTRIBUTING.md

## File Lifecycle Management

### New Files

```bash
# When adding a new configuration:
1. Check if similar file exists
   git ls-files | grep -i "docker-compose"

2. If exists, add to existing file (profile/env-var)
3. If new category, create in appropriate directory
4. Update reference documentation

# Example: Adding new Prometheus scrape config
# ❌ WRONG: Create prometheus-ollama.yml
# ✅ CORRECT: Add scrape_configs entry to prometheus.yml
```

### Stale Files

```bash
# Files not touched in 90+ days
find . -type f -mtime +90 -name "*.md" -o -name "*.yml"

# Decision matrix:
# - Archive: Historical documents, old phase completions
# - Keep: Active configurations, current documentation
# - Delete: Duplicates, obsolete versions
```

### Archived Files

```
archive/
├── 2026-03/
│   ├── old-docker-compose.yml
│   └── phase-15-deployment.md
└── 2026-02/
    └── deprecated-configs/
```

## Metrics for Repository Health

Track these metrics to maintain hygiene:

```
- File count: <500 (target)
- Duplicate configs: 0
- Largest file: <50KB (except binaries)
- .git size: <200MB
- Documentation coverage: >90%
- Test coverage: >80%
- Stale branches: <5
- Average file age: <6 months
```

## Related Issues

- **#426**: Repository hygiene consolidation
- **#362**: Production environment abstraction
- **#432**: Docker Compose profiles

## References

- [Git Best Practices](https://git-scm.com/docs)
- [Repository Organization Guide](FILE-ORGANIZATION-GUIDE.md)
- [Code Quality Standards](CODE-QUALITY-STANDARDS.md)
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
