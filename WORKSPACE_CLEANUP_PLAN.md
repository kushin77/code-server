# Workspace Cleanup & Organization Plan
**Analysis Date:** April 29, 2026  
**Current State Snapshot:** 295 MD files, 1,471 scripts, 220 artifact folders, 77M git repository

---

## EXECUTIVE SUMMARY

| Category | Current | Issue | Archive Target | Priority |
|----------|---------|-------|-----------------|----------|
| **Documentation** | 295 MD files (root) | 148 are completion/status files | docs/archive/completed/ | HIGH |
| **Scripts** | 1,173 in scripts/ | 7 duplicate names, poor org | scripts/archive/deprecated/ | MEDIUM |
| **Artifacts** | 220 folders | Phase-specific, outdated | artifacts/archive/ | HIGH |
| **Docker-compose** | 27 variants | Many deprecated/phase-specific | docs/archive/docker-compose/ | MEDIUM |
| **Hidden Folders** | .backups (3.1M), .bootstrap-state (468K) | Build/bootstrap state clutter | Safe to clean | LOW |
| **Git** | 77M (30,582 objects) | Includes terraform cache | gc + prune | LOW |
| **Terraform** | 75M in environments/ | Provider cache in .terraform/ | .gitignore .terraform/ | MEDIUM |

---

## 1. DOCUMENTATION CLEANUP

### 1.1 Root Directory Consolidation (295 files → ~40 files)

**Current Breakdown:**
- **28 PHASE_* files** → Archive to `docs/archive/phase-summaries/`
- **9 SESSION_* files** → Archive to `docs/archive/sessions/`
- **3 ELITE_ENTERPRISE_* files** → Archive to `docs/archive/legacy-frameworks/`
- **147 files with COMPLETE/FINAL/STATUS/REPORT** → Archive to `docs/archive/completed/`
- **68 utility/integration/reference files** → Consolidate into `docs/`

**Recommended Root Level (Keep Only):**
```
Root-Level Files (40-50 total):
├── README.md                          [Primary entry point]
├── START_HERE.md                      [Quick reference]
├── INDEX.md                           [Document index]
├── ROADMAP.md                         [Active roadmap only]
├── QUICK_REFERENCE.md                 [Operation cheat sheet]
│
├── .env files                         [Configuration - keep 5]
├── docker-compose.yml                 [Primary - keep only active variant]
├── package.json                       [Node config]
├── Dockerfile*                        [Build configs]
│
├── Operational (Keep):
│   ├── OPERATIONS_RUNBOOK.md
│   ├── OPERATIONS_HANDOFF.md
│   ├── PRODUCTION_OPERATIONS_GUIDE.md
│   ├── SERVICE_HEALTH_MONITORING_GUIDE.md
│
├── Reference (Move to docs/):
│   ├── ARCHITECTURE_OVERVIEW.md       → docs/architecture/
│   ├── DEPLOYMENT_GUIDE.md            → docs/operations/
│   ├── API_REFERENCE.md               → docs/api/
│   ├── SECURITY_GUIDELINES.md         → docs/security/
```

**Action Items:**
1. Create `docs/archive/completed/` folder structure
2. Move 147 COMPLETE/FINAL/STATUS/REPORT files
3. Create `docs/archive/phase-summaries/PHASE_EXECUTIVE_SUMMARY.md` with all phases
4. Create `docs/archive/sessions/SESSION_INDEX.md` with session references
5. Update root `.gitignore` to exclude archived docs from root searches

### 1.2 Documentation Deduplication

**Contradictions Found:**
- Multiple DEPLOYMENT_STATUS*.md files with conflicting dates
- 3 ELITE_ENTERPRISE frameworks describing same concept
- 12+ versions of CLUSTER_DEPLOYMENT docs with overlapping content

**Consolidation Strategy:**
```
docs/
├── archive/
│   ├── completed/                     [148 status/final/completion files]
│   ├── phase-summaries/
│   │   ├── PHASE_EXECUTIVE_SUMMARY.md [Master index linking all phases]
│   │   ├── phase-01/
│   │   ├── phase-02/
│   │   └── ...
│   ├── sessions/
│   │   ├── SESSION_INDEX.md
│   │   ├── session-05/
│   │   └── session-06/
│   └── retired/                       [Old frameworks, v1 implementations]
├── operations/
│   ├── RUNBOOK.md                    [Consolidates all runbooks]
│   ├── HANDOFF_PROCEDURES.md
│   └── HEALTH_MONITORING.md
├── architecture/
│   ├── SYSTEM_ARCHITECTURE.md
│   ├── CLUSTER_TOPOLOGY.md
│   └── REDUNDANCY_ANALYSIS.md        [Consolidates redundancy docs]
├── governance/
│   ├── COMPLIANCE_POSTURE.md
│   ├── SSOT_INDEX.md
│   └── CONFIG_MONITORING.md
└── integration/
    ├── EXTERNAL_INTEGRATIONS.md
    ├── GITHUB_SYNC.md
    └── GPU_SETUP.md
```

### 1.3 Large Documentation Files (>500 lines)

**Keep as-is (Strategic):**
- `EPHEMERAL_VS_PERSISTENT_RESOURCES.md` (1,327 lines) - Architectural reference
- `COMPREHENSIVE_REDUNDANCY_ANALYSIS.md` (1,189 lines) - Design documentation
- `GOVERNANCE_COMPLIANCE_POSTURE_REVIEW.md` (1,177 lines) - Compliance record
- `GAP_ANALYSIS_DEPLOYMENT_STATE_2026-04-29.md` (981 lines) - Current snapshot

**Consolidation Strategy:**
- Archive phase-by-phase guides to `docs/archive/phase-summaries/`
- Keep one `ARCHITECTURE_GUIDE.md` instead of 3 architecture docs
- Consolidate hardware/infrastructure guides into `docs/operations/INFRASTRUCTURE_SETUP.md`

---

## 2. SCRIPT ORGANIZATION & CONSOLIDATION

### 2.1 Current Script Distribution (1,173 total)

**Top Folders:**
```
scripts/ops/          91 scripts  (12% of total) - Highest concentration
scripts/ci/           40 scripts  (3.4%)
scripts/cloud/        25 scripts  (2.1%)
scripts/_common/      21 scripts  (1.8%)
scripts/phase5/       14 scripts  (1.2%)
... [remaining 982 scripts in 30+ folders]
```

### 2.2 Duplicate Scripts (7 Found)

| Script Name | Locations | Recommendation |
|------------|-----------|-----------------|
| `add-trap-handlers.sh` | Multiple | Consolidate to `scripts/_common/error-handling.sh` |
| `deploy-grafana-dashboards.sh` | 2+ | Keep latest, archive to `scripts/archive/` |
| `production-readiness-check.sh` | 2+ | Consolidate with validation suite |
| `rollback.sh` | Multiple | Central version in `scripts/operations/rollback.sh` |
| `run-chaos-tests.sh` | 2+ | Unified test suite in `scripts/testing/` |
| `setup-advanced-team-coordination.sh` | 2+ | Move to `scripts/setup/` |
| `validate-resource-limits.sh` | 2+ | Move to `scripts/validation/` |

**Deduplication Process:**
1. Audit each duplicate for functional differences
2. Create master version with combined functionality
3. Create symlinks or wrapper scripts if needed
4. Archive originals to `scripts/archive/deprecated-YYYYMMDD/`
5. Update all references in other scripts

### 2.3 Proposed Script Reorganization

**Current (Too Granular):** 40+ top-level folders

**Proposed (Consolidated):**
```
scripts/
├── operations/         [Core operational scripts - 91 from ops/]
│   ├── deployment/    [Deployment procedures]
│   ├── monitoring/    [Health checks, monitoring]
│   ├── maintenance/   [Backups, cleanup, gc]
│   └── rollback/      [Disaster recovery]
│
├── ci/                [CI/CD pipelines - 40 scripts]
│   ├── validation/    [Pre-deployment checks]
│   ├── testing/       [Test runners]
│   └── deployment/    [CD automation]
│
├── infrastructure/    [Cloud/K8s/Docker - 25 scripts]
│   ├── cloud/        [AWS/GCP provisioning]
│   ├── kubernetes/   [K8s operations]
│   └── docker/       [Container management]
│
├── setup/            [Initial setup & config - 14 scripts]
│   ├── bootstrap/    [Cluster bootstrapping]
│   ├── provisioning/ [Env provisioning]
│   └── initialization/
│
├── utilities/        [Common utilities]
│   ├── error-handling.sh      [Unified trap/error handling]
│   ├── logging.sh             [Standard logging]
│   ├── retry.sh               [Retry mechanisms]
│   └── validation.sh          [Input validation]
│
├── security/         [Security scanning, auditing]
├── compliance/       [Governance, compliance checks]
├── archive/          [Deprecated/historical scripts]
│   └── deprecated-YYYYMMDD/  [Timestamped batches]
│
└── docs/
    ├── SCRIPT_MANIFEST.md    [Master index of all scripts]
    ├── NAMING_CONVENTIONS.md [Script naming standards]
    └── USAGE_GUIDE.md        [Common script patterns]
```

### 2.4 Script Cleanup Actions

**Immediate (Safe):**
- [ ] Create `scripts/archive/deprecated-YYYYMMDD/` folder
- [ ] Move duplicate scripts → archive with `.deprecated` suffix
- [ ] Create `scripts/utilities/common.sh` with shared functions
- [ ] Add header to all scripts: purpose, dependencies, usage

**Phase-Specific Cleanup:**
- [ ] Archive scripts/phase1-phase15 to `scripts/archive/phase-specific/`
- [ ] Keep only 1 example: `scripts/examples/phase-template.sh`
- [ ] Create `PHASE_SCRIPTS_INDEX.md` reference

**Validation:**
- [ ] Test script reorganization with dry-run
- [ ] Update all cross-references in remaining scripts
- [ ] Verify CI/CD pipelines can still locate scripts

---

## 3. ARTIFACT & BUILD ARTIFACT CLEANUP

### 3.1 Artifacts Directory (220 folders, mixed content)

**Current Structure Issues:**
```
artifacts/
├── phase1-20260428-111753/     [Timestamped, unclear purpose]
├── phase55/                     [Numbered but unclear]
├── phase703/                    [Out of order]
├── validate-storage-hygiene/   [One-off validations]
├── chaos-20260428-112359/      [Chaos test outputs]
├── deployments/                [Deployment logs]
└── [215 more similar folders]
```

**Recommended Structure:**
```
artifacts/
├── current/                    [Active/latest artifacts]
│   ├── deployment-logs/
│   ├── test-results/
│   └── validation-reports/
│
├── archive/                    [Timestamped by phase and date]
│   ├── phase-01/
│   │   ├── 20260401-initial-deployment/
│   │   └── 20260403-remediation/
│   ├── phase-02/
│   ├── ... [phases 3-24]
│   └── chaos-testing/
│       ├── 20260428-chaos-01/
│       └── 20260428-chaos-02/
│
├── validation-results/        [Moved from root]
│   ├── storage-hygiene/
│   ├── p2-hardening/
│   └── ...
│
└── README.md                  [Artifact retention policy]
```

**Retention Policy:**
- **Current:** Keep indefinitely (referenced in ops)
- **Archive:** Keep 1 month (for recovery/audit)
- **Older:** Move to docs/archive/ or compress to .tar.gz with metadata
- **Logs:** Rotate monthly, keep 3 months in artifacts/, older to storage

### 3.2 Action Items

- [ ] Create new folder structure above
- [ ] Scan existing artifacts for content (logs, reports, configs, outputs)
- [ ] Move phase-specific artifacts to `artifacts/archive/phase-NN/`
- [ ] Compress old artifacts: `tar -czf artifacts/archive/phase-01.tar.gz phase-01/`
- [ ] Create `artifacts/MANIFEST.md` with purpose of each artifact folder
- [ ] Set up gitignore for artifacts (already configured, verify)

---

## 4. DOCKER-COMPOSE CONSOLIDATION (27 → 3-5 files)

### 4.1 Current Variants Analysis

**27 docker-compose files identified:**

**Category 1: Actively Used (Keep)**
- `docker-compose.yml` (Primary)
- `docker-compose.production.yml` (Production override)
- `docker-compose.override.yml` (Development override)

**Category 2: Phase-Specific (Archive)**
- `docker-compose.phase-11-add-services.yml`
- `docker-compose.phase-11-expansion.yml`
- `docker-compose.phase-11-extension.yml`
- `docker-compose.phase-13-apps-mock.yml`
- `docker-compose.phase-13-apps.yml`
- `docker-compose.phase-14-expansion-mock.yml`
- `docker-compose.phase-14-expansion.yml`

**Category 3: Infrastructure/Deployment (Consolidate)**
- `docker-compose.infrastructure-core.yml`
- `docker-compose.infrastructure-only.yml`
- `docker-compose.infrastructure-v2.yml`
- `docker-compose.infrastructure-v3.yml`
→ Keep v3, archive others

**Category 4: Testing/Legacy (Archive)**
- `docker-compose.production-clean.yml`
- `docker-compose.production-test.yml`
- `docker-compose.production-replica.yml`
- `docker-compose.enterprise-simple.yml`
- `docker-compose.production-test.yml`
- `docker-compose.prod.yml` (duplicate of production.yml)

**Category 5: Specialized (Review)**
- `docker-compose.ai.yml` (AI services)
- `docker-compose.edge-agent.yml` (Edge agent)
- `docker-compose.observability.yml` (Observability stack)
- `docker-compose.redpanda.yml` (Message queue)

### 4.2 Recommended Final Structure

```
Root:
├── docker-compose.yml                    [Primary - base services]
├── docker-compose.production.yml         [Prod overrides]
├── docker-compose.override.yml           [Dev overrides]
├── docker-compose.observability.yml      [Optional observability stack]

docs/archive/docker-compose-variants/    [Historical variants]
├── infrastructure-evolution/
│   ├── docker-compose.infrastructure-v1.yml
│   ├── docker-compose.infrastructure-v2.yml
│   └── docker-compose.infrastructure-v3.yml
├── phase-specific/
│   ├── phase-11-expansion.yml
│   ├── phase-13-apps.yml
│   └── phase-14-expansion.yml
├── testing/
│   ├── docker-compose.production-test.yml
│   ├── docker-compose.enterprise-simple.yml
│   └── docker-compose.production-clean.yml
└── specialized/
    ├── docker-compose.ai.yml
    ├── docker-compose.edge-agent.yml
    └── docker-compose.redpanda.yml
```

### 4.3 Migration Steps

1. **Backup all variants:**
   ```bash
   mkdir -p docs/archive/docker-compose-variants/
   cp docker-compose.*.yml docs/archive/docker-compose-variants/
   ```

2. **Verify production uses active files:**
   ```bash
   grep -r "docker-compose" .github/workflows/ scripts/ops/ | grep "\.yml" | sort | uniq
   ```

3. **Keep only essential, remove/archive others:**
   ```bash
   rm docker-compose.prod.yml docker-compose.production-clean.yml # Duplicates
   rm docker-compose.infrastructure-v*.yml docker-compose.phase-*.yml
   ```

4. **Document file purpose in README:**
   ```markdown
   ## Docker Compose Files
   - **docker-compose.yml** - Primary services configuration
   - **docker-compose.production.yml** - Production-specific overrides
   - **docker-compose.override.yml** - Development overrides
   ```

---

## 5. ENVIRONMENT FILE CONSOLIDATION (5 → 2-3 files)

### 5.1 Current .env Files

| File | Size | Purpose | Status |
|------|------|---------|--------|
| `.env.agent-safeguards` | 5.6K | Agent safety guardrails | Active |
| `.env.cluster` | 4.5K | Cluster configuration | Active |
| `.env.deployment` | 3.6K | Deployment settings | Active |
| `.env.infrastructure` | 2.7K | Infrastructure config | Active |
| `.env.production` | 3.4K | Production overrides | Active |
| `.env.schema.json` | 11K | Schema reference | Reference |

### 5.2 Consolidation Recommendation

**Option A: Maintain by Purpose** (Recommended)
```
.env.schema.json          [Schema - don't change]
.env                      [Development defaults - gitignore entry]
.env.production           [Production overrides only - no secrets]
.env.cluster              [Cluster-specific config]
.env.agent-safeguards     [Agent safety config]
```

**Option B: Single Master .env**
- Create `.env.example` with all possible variables
- Document which variables are environment-specific
- Use feature flags for conditional loading

### 5.3 Action Items

- [ ] Document purpose of each .env file
- [ ] Identify overlap and consolidate where possible
- [ ] Ensure .env.production contains only override values
- [ ] Move secrets to proper secret management (GSM if not already)
- [ ] Add `.env` to .gitignore if not already present
- [ ] Create `.env.schema.json` reference in docs/

---

## 6. HIDDEN FOLDER CLEANUP

### 6.1 Folder Analysis

| Folder | Size | Files | Content | Recommendation |
|--------|------|-------|---------|-----------------|
| `.backups/` | 3.1M | 307 | Deduplication fixes (old) | ARCHIVE |
| `.bootstrap-state/` | 468K | 116 | Init state JSON files | ARCHIVE |
| `.agent-work/` | 108K | 1 | open-issues.json | KEEP |
| `.deployments/` | 16K | 2 | Current deployment state | KEEP |

### 6.2 Cleanup Actions

**Archive to docs/archive/.backup-history/**
```bash
# Create archive with timestamp
mkdir -p docs/archive/.backup-history/2026-04-29/
mv .backups/* docs/archive/.backup-history/2026-04-29/
mv .bootstrap-state/* docs/archive/.backup-history/2026-04-29/
```

**Rationale:**
- `.backups/`: Contains deduplication fixes from April 27 (historical)
- `.bootstrap-state/`: Contains init-XXXXXXX.json files (bootstrap artifacts)
- **Keep:** `.deployments/` (active deployment tracking), `.agent-work/` (current issues)

---

## 7. GIT REPOSITORY CLEANUP

### 7.1 Current State

- **Repository Size:** 77M
- **Git Objects:** 30,582
- **Provider Cache:** Terraform providers (~40M in .terraform/)

### 7.2 .gitignore Improvements

**Add to .gitignore:**
```gitignore
# Terraform
.terraform/                # ✅ Already present (verify coverage)
terraform/.terraform/      # Add explicit path
terraform/tfplan          # Already ignored via *.tfplan

# Build artifacts
*.tfplan                   # ✅ Already covered
*.tfbackup                 # ✅ Already present

# Docker artifacts
docker-compose.*.backup
*.tar.gz                   # Too broad? Narrow if needed
*.zip                      # Too broad? Narrow if needed

# IDE & OS
.DS_Store                  # ✅ Present
Thumbs.db                  # ✅ Present
.history/                  # ✅ Present
.vscode-server/            # Add if exists

# Logs & artifacts
logs/                      # ✅ Present
artifacts/                 # ✅ Present (but archive/ should exist)
.deployments/              # ✅ Present

# Python
__pycache__/              # ✅ Present
*.egg-info/               # Add

# Node
dist/                     # Add
build/                     # Add
.next/                     # Add if exists

# Large files
*.iso
*.dmg
*.exe
```

### 7.3 Git Cleanup Steps

**Safe cleanup (no history loss):**
```bash
# 1. Garbage collection
git gc --aggressive

# 2. Prune reflog
git reflog expire --all --expire=now
git gc --prune=now

# 3. Check size reduction
du -sh .git

# 4. Optional: Force-prune old objects
git count-objects -v
```

**One-time cleanup (if needed):**
```bash
# Remove terraform provider cache from history (CAUTION)
git filter-branch --tree-filter 'find .terraform -type f -delete' -- --all
# Then gc --prune=now
```

### 7.4 .gitattributes Enhancement

**Current:**
```
config/grafana/provisioning/dashboards/**/*.json text eol=lf
```

**Recommended additions:**
```gitattributes
# JSON files
*.json text eol=lf
.env.schema.json text eol=lf

# Shell scripts
*.sh text eol=lf
*.bash text eol=lf

# YAML
*.yml text eol=lf
*.yaml text eol=lf

# Docker
Dockerfile* text eol=lf
*.dockerfile text eol=lf

# Terraform
*.tf text eol=lf
*.tfvars text eol=lf

# Binary files
*.tar binary
*.gz binary
*.zip binary
*.exe binary
```

---

## 8. IMPLEMENTATION ROADMAP

### Phase 1: Safe Moves (No Risk) - Week 1
**Time: 2-4 hours**

- [ ] Create folder structure:
  ```bash
  mkdir -p docs/archive/{completed,phase-summaries,sessions,retired,docker-compose-variants}
  mkdir -p scripts/archive/deprecated-$(date +%Y%m%d)
  mkdir -p artifacts/archive
  ```

- [ ] Move completion/status docs:
  ```bash
  mv *COMPLETE*.md *FINAL*.md *STATUS*.md *REPORT*.md docs/archive/completed/
  ```

- [ ] Move phase docs:
  ```bash
  mv PHASE*.md docs/archive/phase-summaries/
  ```

- [ ] Archive backups:
  ```bash
  mkdir -p docs/archive/.backup-history/2026-04-29
  mv .backups/* .bootstrap-state/* docs/archive/.backup-history/2026-04-29/
  rmdir .backups .bootstrap-state
  ```

### Phase 2: Consolidation (Requires Testing) - Week 2
**Time: 4-8 hours**

- [ ] Consolidate docker-compose files
- [ ] Move duplicate scripts to archive with `.DEPRECATED` suffix
- [ ] Create symlinks or wrappers if needed
- [ ] Test CI/CD still works

### Phase 3: Script Reorganization (High Impact) - Week 3
**Time: 8-12 hours**

- [ ] Reorganize scripts/ folder structure
- [ ] Update all cross-references
- [ ] Create SCRIPT_MANIFEST.md
- [ ] Test all scripts still execute correctly

### Phase 4: Git Cleanup (Optional) - Week 4
**Time: 2-4 hours**

- [ ] Run `git gc --aggressive`
- [ ] Update .gitignore and .gitattributes
- [ ] Monitor repository size
- [ ] Consider provider cache strategy

---

## 9. VERIFICATION CHECKLIST

Before/After Metrics:

```
BEFORE:
- Root MD files: 295
- Script count: 1,471
- Artifacts folders: 220
- Docker-compose variants: 27
- .git size: 77M
- Total repo size: ~150M

AFTER TARGET:
- Root MD files: 40
- Script count: 1,200 (organized, 7 duplicates resolved)
- Artifacts folders: 50 (rest in archive)
- Docker-compose variants: 3-5 active + archived
- .git size: 65M (after gc)
- Total repo size: ~100M
- Cleanup reduction: 33%
```

### Verification Steps:

1. **Verify navigation:**
   ```bash
   find docs -type f -name '*.md' | wc -l  # Should be manageable
   find scripts -maxdepth 2 -type d | wc -l # Should be 10-15
   find artifacts -maxdepth 2 -type d | wc -l # Should be <50
   ```

2. **Verify references:**
   ```bash
   grep -r "PHASE.*\.md\|DEPLOYMENT.*\.md" . --include='*.sh' --include='*.md' | wc -l
   # Should be minimal (only references to active docs)
   ```

3. **Verify scripts work:**
   ```bash
   for script in scripts/operations/*.sh; do bash -n "$script"; done
   # No syntax errors should appear
   ```

4. **Verify git health:**
   ```bash
   git fsck --full
   git count-objects -v
   ```

---

## 10. RISK MITIGATION

| Risk | Mitigation | Verification |
|------|-----------|--------------|
| Break references | Audit all before moving | grep -r "PHASE.*md" before move |
| CI/CD failure | Test on branch first | Run test workflow |
| Lose important data | Create backup branch | git branch cleanup-backup |
| Script failures | Verify syntax before moving | bash -n on all scripts |
| Git corruption | Conservative approach | git fsck after operations |

---

## 11. AUTOMATED CLEANUP SCRIPT

**File: `scripts/operations/cleanup-workspace.sh`**

```bash
#!/bin/bash
# Workspace cleanup automation with rollback capability

set -euo pipefail

BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_BRANCH="cleanup-backup-${BACKUP_DATE}"

main() {
    echo "Creating backup branch: $BACKUP_BRANCH"
    git branch "$BACKUP_BRANCH"
    
    echo "Phase 1: Creating folder structure..."
    mkdir -p docs/archive/{completed,phase-summaries,sessions,retired}
    mkdir -p scripts/archive/deprecated-${BACKUP_DATE}
    mkdir -p artifacts/archive
    
    echo "Phase 2: Moving documentation..."
    # Move completion docs
    find . -maxdepth 1 -name '*COMPLETE*.md' -o -name '*FINAL*.md' \
        | xargs -I {} mv {} docs/archive/completed/ 2>/dev/null || true
    
    # Move phase docs
    find . -maxdepth 1 -name 'PHASE*.md' \
        | xargs -I {} mv {} docs/archive/phase-summaries/ 2>/dev/null || true
    
    echo "Phase 3: Archiving bootstrap artifacts..."
    mkdir -p docs/archive/.backup-history/${BACKUP_DATE}
    [[ -d .backups ]] && mv .backups/* docs/archive/.backup-history/${BACKUP_DATE}/ && rmdir .backups
    [[ -d .bootstrap-state ]] && mv .bootstrap-state/* docs/archive/.backup-history/${BACKUP_DATE}/ && rmdir .bootstrap-state
    
    echo "Phase 4: Creating indices..."
    create_phase_index
    create_session_index
    create_script_manifest
    
    echo ""
    echo "✅ Cleanup complete!"
    echo "📋 Backup branch: $BACKUP_BRANCH"
    echo "📊 New structure ready for review"
    echo ""
    echo "To rollback: git reset --hard $BACKUP_BRANCH"
}

create_phase_index() {
    cat > docs/archive/phase-summaries/README.md <<'EOF'
# Phase Summaries

Index of all phase-specific documentation and artifacts.

[Phase index content generated during cleanup]
EOF
}

create_session_index() {
    cat > docs/archive/sessions/README.md <<'EOF'
# Session Records

Historical session notes and progress reports.

[Session index content generated during cleanup]
EOF
}

create_script_manifest() {
    cat > scripts/MANIFEST.md <<'EOF'
# Script Manifest

Master index of all scripts organized by function.

[Script manifest generated during cleanup]
EOF
}

main "$@"
```

---

## 12. NEXT STEPS

**Immediate (This Week):**
1. Review this plan with team
2. Create backup branch: `git checkout -b cleanup-plan-review`
3. Test script organization on branch

**Short Term (Next 2 Weeks):**
1. Execute Phase 1 (safe moves)
2. Test CI/CD, operations scripts
3. Document any broken references

**Medium Term (Weeks 3-4):**
1. Execute Phase 2-3 (consolidation, reorganization)
2. Update documentation and runbooks
3. Perform git cleanup

**Ongoing:**
1. Maintain new folder structure going forward
2. Archive quarterly during transition phase
3. Monitor for new status files accumulation

---

## 13. MAINTENANCE POLICY (Going Forward)

**To prevent re-cluttering:**

1. **Documentation:**
   - Max 10 files in root (use docs/ for all substantive docs)
   - Monthly archive of completion reports
   - Auto-link to phase summaries

2. **Scripts:**
   - No phase-specific scripts in root
   - Quarterly review of unused scripts
   - Clear deprecation process

3. **Artifacts:**
   - Weekly rotation of logs
   - Monthly archival of test results
   - Quarterly cleanup of old phases

4. **Git:**
   - Quarterly `git gc --aggressive`
   - Monthly .gitignore review
   - Update provider pins quarterly

---

**Document Created:** April 29, 2026  
**Estimated Implementation Time:** 20-30 hours  
**Risk Level:** Low-Medium (with proper verification)  
**Expected Outcome:** 33% size reduction, significantly improved navigation
