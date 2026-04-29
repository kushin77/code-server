# Workspace Cleanup - Detailed File-by-File Analysis

**Analysis Date:** April 29, 2026 | **Detailed Mappings** | **Before/After Structure**

---

## PART 1: DOCUMENTATION FILES (295 → 40)

### 1.1 ROOT DOCUMENTATION CLEANUP

**MOVE TO docs/archive/completed/ (147 files):**

```
COMPLETION/FINAL/FULL STATUS FILES (Archive These):
├─ *COMPLETE*.md (29 files)
│  ├─ CLUSTER_DEPLOYMENT_COMPLETE.md → docs/archive/completed/cluster-deployment-phase-x.md
│  ├─ DEPLOYMENT_EXECUTION_COMPLETE.md
│  ├─ DEPLOYMENT_COMPLETION_REPORT.md
│  ├─ SESSION_SUMMARY_COMPLETE.md
│  ├─ FULL_CLUSTER_DEPLOYMENT_COMPLETE.md
│  ├─ ENTERPRISE_DEPLOYMENT_COMPLETE.md
│  ├─ PRODUCTION_DEPLOYMENT_COMPLETE_LIVE.md
│  ├─ INFRASTRUCTURE_AUDIT_COMPLETE_SUMMARY.md
│  ├─ INFRASTRUCTURE-HARDENING-COMPLETION-FINAL.md
│  ├─ OPERATION_READINESS-SIGN-OFF.md
│  ├─ PHASE-06-COMPLETE-FINAL-CERTIFICATION.md
│  ├─ GITHUB-ISSUES-CLOSURE-COMPLETE.md
│  ├─ CI_CD_VALIDATION_REPORT_COMPLETE.md
│  └─ [17 more COMPLETE files]
│
├─ *FINAL*.md (40+ files)
│  ├─ FINAL_CONSOLIDATION_STATUS.md
│  ├─ FINAL_DELIVERY_SUMMARY.md
│  ├─ FINAL_DEPLOYMENT_STATUS.md
│  ├─ FINAL_SESSION_DELIVERY_REPORT.md
│  ├─ DEPLOYMENT_READINESS_FINAL.md
│  ├─ DEPLOYMENT_COMPLETION_CERTIFICATE_FINAL.md
│  ├─ DEPLOYMENT_PROGRAM_FINAL_EXECUTION_SUMMARY.md
│  ├─ PROJECT_COMPLETION_REPORT.md
│  ├─ PHASE-06-FINAL-DEPLOYMENT-SUMMARY.md
│  ├─ PHASE_6_FINAL_COMPLETION.md
│  ├─ ELITE-ENTERPRISE-COMPLETE-DELIVERY.md
│  └─ [29 more FINAL files]
│
├─ *STATUS*.md (48+ files)
│  ├─ DEPLOYMENT_STATUS.md
│  ├─ DEPLOYMENT_STATUS_REPORT.md
│  ├─ OPERATIONAL_STATUS_FINAL.md
│  ├─ PHASE-06-CURRENT-STATUS.md
│  ├─ DEPLOYMENT_STATUS_GITHUB_SYNC.md
│  ├─ FINAL_PLATFORM_STATUS.md
│  ├─ INFRASTRUCTURE_DEPLOYMENT_STATUS.md
│  ├─ ENTERPRISE_DEPLOYMENT_FINAL_STATUS.md
│  └─ [40 more STATUS files]
│
└─ REPORT*.md (30 files)
   ├─ DEPLOYMENT_EXECUTION_REPORT.md
   ├─ AUDIT_DELIVERABLES_FINAL.md
   ├─ PERFORMANCE_BASELINE_REPORT.md
   └─ [27 more report files]
```

**MOVE TO docs/archive/phase-summaries/ (28 files):**

```
PHASE-SPECIFIC DOCUMENTATION:
├─ PHASE_XX files (28 total)
│  ├─ PHASE-05-DEPLOYMENT-COMPLETE.md
│  ├─ PHASE-06-COMPLETE-FINAL-CERTIFICATION.md
│  ├─ PHASE-06-FINAL-REPORT.md
│  ├─ PHASE1_COMPLETION_REPORT.md
│  ├─ PHASE2_COMPLETION_SUMMARY.md
│  ├─ PHASE3-APPLICATION-MIGRATION-COMPLETE.md
│  ├─ PHASE4_COMPLETION_REPORT.md
│  ├─ PHASE5_COMPLETE_EXECUTION_REPORT.md
│  ├─ PHASE6_COMPLETION_REPORT.md
│  ├─ PHASE7_COMPLETION_REPORT.md
│  ├─ PHASE8_COMPLETION_REPORT.md
│  ├─ PHASE9_COMPLETION_REPORT.md
│  ├─ PHASE10_COMPLETION_REPORT.md
│  ├─ PHASE11_COMPLETION_REPORT.md
│  ├─ PHASE12_COMPLETION_REPORT.md
│  ├─ PHASE13_COMPLETION_REPORT.md
│  ├─ PHASE14_FINAL_COMPLETION_REPORT.md
│  ├─ PHASE_1_DEPLOYMENT_PACKAGE.md
│  ├─ PHASE_10_12_DEPLOYMENT_REPORT.md
│  ├─ PHASES_1_2_3_DEPLOYMENT_COMPLETE.md
│  ├─ PHASES_4_5_DEPLOYMENT_COMPLETE.md
│  └─ [8 more PHASE files]
```

**MOVE TO docs/archive/sessions/ (9 files):**

```
SESSION RECORDS:
├─ SESSION_5_COMPLETION.md
├─ SESSION_5_FINAL_COMPLETION.md
├─ SESSION_6_COMPLETION_SUMMARY.md
├─ SESSION_6_EXTENDED_COMPLETION_SUMMARY.md
├─ SESSION_6_EXTENDED_OFFICIAL_COMPLETION.md
├─ SESSION_7c_CONSOLIDATION_SUMMARY.md
├─ SESSION_8_AUTONOMOUS_CONTINUATION.md
├─ SESSION_SUMMARY_COMPLETE.md
└─ CONTINUATION_SESSION_FINAL_STATUS.md
```

**MOVE TO docs/archive/legacy-frameworks/ (3 files):**

```
LEGACY FRAMEWORK DOCUMENTATION:
├─ ELITE_ENTERPRISE_16PHASE_FRAMEWORK.md
├─ ELITE_ENTERPRISE_16PHASE_PROJECT_COMPLETION_REPORT.md
└─ ELITE_ENTERPRISE_4PHASE_COMPLETION_REPORT.md
```

**KEEP IN ROOT (40 files) - ACTIVELY REFERENCED:**

```
📌 PRIMARY NAVIGATION:
├─ README.md .......................... Project overview
├─ START_HERE.md ...................... Quick start guide
├─ INDEX.md ........................... Document index
├─ ROADMAP.md ......................... Active roadmap
├─ QUICK_REFERENCE.md ................ Cheat sheet

📌 OPERATIONS & RUNBOOKS:
├─ OPERATIONS_RUNBOOK.md ............ Master operations guide
├─ OPERATIONS_HANDOFF.md ............ Handoff procedures
├─ PRODUCTION_OPERATIONS_GUIDE.md ... Production procedures
├─ SERVICE_HEALTH_MONITORING_GUIDE.md . Health checks
├─ MASTER_DEPLOYMENT_EXECUTION_CHECKLIST.md .. Deploy checklist

📌 ARCHITECTURE & DESIGN:
├─ COMPREHENSIVE_REDUNDANCY_ANALYSIS.md ... Design decisions
├─ EPHEMERAL_VS_PERSISTENT_RESOURCES.md ... Resource strategy
├─ EXTERNAL_INTEGRATIONS_MAP.md ........ Integration points
├─ DATABASE_SERVICES_ARCHITECTURE.md ... Database design
├─ PHASE6_COMPREHENSIVE_GUIDE.md ...... Phase-6 strategy

📌 GOVERNANCE & COMPLIANCE:
├─ GOVERNANCE_COMPLIANCE_POSTURE_REVIEW.md
├─ SSOT_GOVERNANCE_INDEX.md
├─ CONFIG_MONITORING_CONSOLIDATION_STRATEGY.md
├─ AUDIT_REMEDIATION_PLAN.md

📌 DEPLOYMENT PROCEDURES:
├─ DEPLOYMENT_EXECUTION_PLAN.md ....... Deploy steps
├─ PRODUCTION_DEPLOYMENT_READINESS_CHECKLIST_FINAL.md
├─ PRODUCTION_HANDOFF_PROCEDURE.md
├─ PRIMARY_HOST_DEPLOYMENT_RUNBOOK.md
├─ REPLICA_DEPLOYMENT_PACKAGE.md

📌 INFRASTRUCTURE:
├─ GPU_IMPLEMENTATION_GUIDE.md ........ GPU setup
├─ GPU_INTEGRATION_ASSESSMENT.md
├─ IMPLEMENTATION_GUIDE_UBUNTU.md .... Ubuntu setup

📌 REFERENCE:
├─ COMPLETE_35_SERVICE_REFERENCE.md ... Service list
├─ INTEGRATION_LOCATIONS_REFERENCE.md . Integration index
├─ INTEGRATION_TESTS_IMPLEMENTATION.md . Test strategy

📌 CONFIGURATION:
├─ Caddyfile ......................... Web server config
├─ commitlint.config.cjs ............ Commit rules
├─ docker-compose.yml ............... Primary compose
├─ package.json ..................... Node config
├─ pyproject.toml ................... Python config

📌 GITHUB/SYNC:
├─ GITHUB_ISSUE_SYNC_EXECUTION_COMMANDS.sh
├─ SYNC_ISSUES_README.md
├─ GITHUB_GCP_INTEGRATION.md

📌 ENVIRONMENT:
├─ .env.agent-safeguards ............ Agent config
├─ .env.cluster ..................... Cluster config
├─ .env.deployment .................. Deploy config
├─ .env.infrastructure .............. Infra config
├─ .env.production .................. Prod config
├─ .env.schema.json ................. Schema
```

---

## PART 2: DOCKER-COMPOSE CONSOLIDATION (27 → 3-5)

### Current Files (27 total)

```
ROOT (27 files):
├─ ACTIVE/PRODUCTION (Keep):
│  ├─ docker-compose.yml ........... PRIMARY - All services
│  ├─ docker-compose.production.yml  PROD OVERRIDE
│  └─ docker-compose.override.yml   DEV OVERRIDE
│
├─ INFRASTRUCTURE (Consolidate → v3 only):
│  ├─ docker-compose.infrastructure-core.yml .... Archive v1
│  ├─ docker-compose.infrastructure-only.yml ... Archive v1
│  ├─ docker-compose.infrastructure-v2.yml .... Archive v2
│  └─ docker-compose.infrastructure-v3.yml .... KEEP (latest)
│
├─ PHASE-SPECIFIC (Archive):
│  ├─ docker-compose.phase-11-add-services.yml
│  ├─ docker-compose.phase-11-expansion.yml
│  ├─ docker-compose.phase-11-extension.yml
│  ├─ docker-compose.phase-13-apps-mock.yml
│  ├─ docker-compose.phase-13-apps.yml
│  ├─ docker-compose.phase-14-expansion-mock.yml
│  └─ docker-compose.phase-14-expansion.yml
│
├─ TESTING/LEGACY (Archive):
│  ├─ docker-compose.production-clean.yml
│  ├─ docker-compose.production-test.yml
│  ├─ docker-compose.production-replica.yml
│  ├─ docker-compose.enterprise-simple.yml
│  ├─ docker-compose.prod.yml ..................... DUPLICATE of .production.yml
│  └─ docker-compose.yml.backup .................. BACKUP
│
├─ SPECIALIZED (Review - Keep or Archive):
│  ├─ docker-compose.ai.yml ...................... AI services stack
│  ├─ docker-compose.edge-agent.yml ............. Edge agent
│  ├─ docker-compose.observability.yml ......... Observability stack
│  ├─ docker-compose.redpanda.yml .............. Message queue
│  └─ docker-compose.full-stack.yml ............ Full deployment
│
└─ DEPRECATED (Archive):
   ├─ docker-compose.cluster.yml
   ├─ docker-compose.deploy.yml
   ├─ docker-compose.enterprise-simple.yml
   ├─ docker-compose.minimal-deploy.yml
   └─ docker-compose.ai.yml (if not needed)
```

### Proposed Structure

```
ROOT (Keep active only):
├─ docker-compose.yml
├─ docker-compose.production.yml
└─ docker-compose.override.yml

docs/archive/docker-compose-variants/
├─ infrastructure-evolution/
│  ├─ docker-compose.infrastructure-core.yml (v1)
│  ├─ docker-compose.infrastructure-v2.yml
│  ├─ docker-compose.infrastructure-v3.yml (keep reference)
│  └─ README.md: "Infrastructure evolution history"
│
├─ phase-specific/
│  ├─ docker-compose.phase-11-expansion.yml
│  ├─ docker-compose.phase-13-apps.yml
│  ├─ docker-compose.phase-14-expansion.yml
│  └─ README.md: "Phase-specific variants"
│
├─ testing/
│  ├─ docker-compose.production-test.yml
│  ├─ docker-compose.production-clean.yml
│  ├─ docker-compose.enterprise-simple.yml
│  └─ README.md: "Test configurations"
│
└─ specialized/
   ├─ docker-compose.ai.yml (if active)
   ├─ docker-compose.edge-agent.yml (if active)
   ├─ docker-compose.observability.yml
   ├─ docker-compose.redpanda.yml
   └─ README.md: "Specialized stacks"

apps/agent-runtime/
└─ docker-compose-entry.yml (stays - part of app code)
```

### Specific Commands to Execute

```bash
# Remove duplicates/deprecated
rm docker-compose.prod.yml                    # Duplicate
rm docker-compose.yml.backup                  # Backup
rm docker-compose.enterprise-simple.yml       # Deprecated

# Move to archive
mkdir -p docs/archive/docker-compose-variants/{infrastructure-evolution,phase-specific,testing,specialized}

mv docker-compose.infrastructure-core.yml docs/archive/docker-compose-variants/infrastructure-evolution/
mv docker-compose.infrastructure-only.yml docs/archive/docker-compose-variants/infrastructure-evolution/
mv docker-compose.infrastructure-v2.yml docs/archive/docker-compose-variants/infrastructure-evolution/

mv docker-compose.phase-*.yml docs/archive/docker-compose-variants/phase-specific/

mv docker-compose.production-test.yml docs/archive/docker-compose-variants/testing/
mv docker-compose.production-clean.yml docs/archive/docker-compose-variants/testing/
mv docker-compose.production-replica.yml docs/archive/docker-compose-variants/testing/

mv docker-compose.ai.yml docs/archive/docker-compose-variants/specialized/ 2>/dev/null || true
mv docker-compose.edge-agent.yml docs/archive/docker-compose-variants/specialized/ 2>/dev/null || true
```

---

## PART 3: SCRIPT ORGANIZATION (1,173 scripts - Consolidation Only)

### High-Level Folder Structure

```
scripts/
├─ operations/ ........................ 91 scripts [Main operational scripts]
│  ├─ deployment/ .................... Deploy procedures
│  ├─ monitoring/ .................... Health monitoring
│  ├─ maintenance/ ................... Backups, cleanup
│  └─ rollback/ ...................... Disaster recovery
│
├─ ci/ ................................ 40 scripts [CI/CD automation]
│  ├─ validation/ .................... Pre-deployment validation
│  ├─ testing/ ....................... Test execution
│  └─ deployment/ .................... CD automation
│
├─ infrastructure/ .................... 25 scripts [Cloud/K8s/Docker]
│  ├─ cloud/ ......................... AWS/GCP provisioning
│  ├─ kubernetes/ .................... K8s operations
│  └─ docker/ ........................ Container management
│
├─ setup/ ............................. 14 scripts [Initial setup]
│  ├─ bootstrap/ ..................... Cluster bootstrap
│  ├─ provisioning/ .................. Environment setup
│  └─ initialization/ ................ First-time config
│
├─ utilities/ ......................... Common utility scripts
│  ├─ error-handling.sh (CONSOLIDATES from duplicates)
│  ├─ logging.sh
│  ├─ retry.sh
│  └─ validation.sh
│
├─ security/ .......................... Security scanning
├─ compliance/ ........................ Governance checks
│
└─ archive/ ........................... 
   └─ deprecated-20260429/
      ├─ add-trap-handlers.sh.DEPRECATED
      ├─ deploy-grafana-dashboards.sh.DEPRECATED
      ├─ production-readiness-check.sh.DEPRECATED
      └─ [4 more deprecated duplicates]
```

### Duplicate Script Locations & Resolution

```
DUPLICATE #1: add-trap-handlers.sh
├─ Location 1: scripts/phase5/add-trap-handlers.sh
├─ Location 2: scripts/security/add-trap-handlers.sh
├─ Resolution: Consolidate → scripts/utilities/error-handling.sh
└─ Action: Update references in both locations

DUPLICATE #2: deploy-grafana-dashboards.sh
├─ Location 1: scripts/observability/deploy-grafana-dashboards.sh
├─ Location 2: scripts/ci/deploy-grafana-dashboards.sh
├─ Resolution: Keep in scripts/ci/ (CD phase), archive other
└─ Action: Keep one, redirect other via symlink or wrapper

DUPLICATE #3: production-readiness-check.sh
├─ Location 1: scripts/ci/production-readiness-check.sh
├─ Location 2: scripts/validation/production-readiness-check.sh
├─ Resolution: Consolidate → scripts/ci/validation/production-readiness-check.sh
└─ Action: Merge into validation suite

DUPLICATE #4: rollback.sh
├─ Location 1: scripts/operations/rollback.sh
├─ Location 2: scripts/dr/rollback.sh
├─ Location 3: scripts/phase6/rollback.sh
├─ Resolution: Central version → scripts/operations/rollback/rollback.sh
└─ Action: Other locations symlink or reference main

DUPLICATE #5: run-chaos-tests.sh
├─ Location 1: scripts/chaos/run-chaos-tests.sh
├─ Location 2: scripts/ci/testing/run-chaos-tests.sh
├─ Resolution: Keep in scripts/ci/testing/, archive other
└─ Action: Create unified test suite

DUPLICATE #6: setup-advanced-team-coordination.sh
├─ Location 1: scripts/setup/setup-advanced-team-coordination.sh
├─ Location 2: scripts/operations/setup-advanced-team-coordination.sh
├─ Resolution: Move to scripts/setup/
└─ Action: Archive from operations

DUPLICATE #7: validate-resource-limits.sh
├─ Location 1: scripts/ci/validate-resource-limits.sh
├─ Location 2: scripts/validation/validate-resource-limits.sh
├─ Resolution: Keep in scripts/ci/validation/, consolidate other
└─ Action: Merge into validation suite
```

### Phase-Specific Scripts to Archive

```
MOVE TO scripts/archive/phase-specific/:
├─ scripts/phase1/
├─ scripts/phase2/
├─ scripts/phase3/
├─ scripts/phase4/
├─ scripts/phase5/          [Most moved here]
├─ scripts/phase6/
├─ ... [phase7-phase22]
└─ Action: Create example only: scripts/examples/phase-template.sh
```

---

## PART 4: ARTIFACTS & DEPLOYMENT ARTIFACTS (220 → 50)

### Current Artifacts Structure

```
artifacts/
├─ Current (unclear):
│  ├─ chaos-20260428-111846/
│  ├─ chaos-20260428-112359/
│  ├─ chaos-20260428-112402/
│  ├─ deployments/
│  ├─ capacity/
│  └─ backups/
│
├─ Phase-Numbered (out of order):
│  ├─ phase1-20260428-111753/
│  ├─ phase21/
│  ├─ phase22/
│  ├─ phase25/
│  ├─ phase28/
│  ├─ phase33/
│  ├─ phase34/
│  ├─ phase41/
│  ├─ ... [phase1 through phase707]
│
└─ Validation:
   ├─ validate-storage-hygiene/
   ├─ validate-p2-hardening/
   ├─ [other validation runs]
```

### Proposed Structure

```
artifacts/
├─ current/ .......................... Active current artifacts
│  ├─ deployment-logs/
│  ├─ test-results/
│  ├─ validation-reports/
│  └─ chaos-tests/
│
├─ archive/ .......................... Historical (timestamped by phase)
│  ├─ phase-01/
│  │  ├─ 20260401-initial-deployment/
│  │  ├─ 20260403-remediation/
│  │  └─ 20260410-hardening/
│  ├─ phase-02/
│  │  ├─ 20260415-observability-setup/
│  │  └─ 20260420-consolidation/
│  ├─ phase-03/ through phase-24/
│  └─ chaos-testing/
│     ├─ 20260428-chaos-01/
│     ├─ 20260428-chaos-02/
│     └─ [dated chaos test runs]
│
├─ validation-results/ .............. Archived validations
│  ├─ storage-hygiene/
│  ├─ p2-hardening/
│  └─ [other validation archives]
│
└─ README.md (Artifact Retention Policy)
   └─ Current: keep indefinitely
   └─ Archive: keep 1 month
   └─ Older: compress to .tar.gz
```

### Migration Commands

```bash
# Create new structure
mkdir -p artifacts/{current,archive,validation-results}
for phase in {1..24}; do
  mkdir -p "artifacts/archive/phase-$(printf '%02d' $phase)"
done

# Move active artifacts
mv artifacts/chaos-20260428-*/  artifacts/current/chaos-tests/
mv artifacts/deployments/       artifacts/current/deployment-logs/

# Move phase artifacts (consolidate to single phase folder)
for old in artifacts/phase*/; do
  phase_num=$(echo "$old" | sed 's|.*phase||' | sed 's|[^0-9].*||')
  mkdir -p "artifacts/archive/phase-$(printf '%02d' $phase_num)/latest-run/"
  mv "$old"/* "artifacts/archive/phase-$(printf '%02d' $phase_num)/latest-run/" 2>/dev/null || true
done

# Move validations
mv artifacts/validate-*/  artifacts/validation-results/

# Compress old phase artifacts
for phase_dir in artifacts/archive/phase-0[1-5]/; do
  tar -czf "${phase_dir}archive.tar.gz" -C "$phase_dir" . && rm -rf "${phase_dir:?}"/*
done
```

---

## PART 5: HIDDEN FOLDERS CLEANUP

### .backups Directory (3.1M, 307 files)

```
.backups/
├─ deduplication-fixes-1777095756/ .... April 27, old
├─ deduplication-fixes-1777095869/ .... April 27, old
└─ [No recent/active backups]

Action: ARCHIVE
├─ Destination: docs/archive/.backup-history/2026-04-29/
├─ Command: mv .backups/* docs/archive/.backup-history/2026-04-29/
└─ Then: rmdir .backups
```

### .bootstrap-state Directory (468K, 116 files)

```
.bootstrap-state/
├─ init-1777382255.json
├─ init-1777382364.json
├─ init-1777382365.json
├─ init-1777382366.json
├─ ... [110+ more init-XXXXX.json files]
└─ [Bootstrap initialization records from April 27]

Action: ARCHIVE
├─ Destination: docs/archive/.backup-history/2026-04-29/
├─ Command: mv .bootstrap-state/* docs/archive/.backup-history/2026-04-29/
└─ Then: rmdir .bootstrap-state
```

### .agent-work Directory (108K, 1 file)

```
.agent-work/
└─ open-issues.json .................. Currently open GitHub issues

Action: KEEP
├─ Reason: Active, referenced by agent systems
└─ Monitor: Ensure .gitignore excludes if it contains secrets
```

### .deployments Directory (16K, 2 files)

```
.deployments/
└─ 1777411251/
   ├─ current-commit.txt ............ Last deployment commit
   └─ git-status.txt ................ Git status at deploy

Action: KEEP
├─ Reason: Active deployment tracking
├─ Monitor: Clean up old deployment timestamps periodically
└─ Rotate: Keep only last 10 deployments
```

---

## PART 6: ENVIRONMENT FILE DEDUPLICATION

### Current .env Files (5 + schema)

```
ROOT:
├─ .env ............................ (Ignored in git)
├─ .env.agent-safeguards ........... Agent safety config (5.6K)
├─ .env.cluster .................... Cluster config (4.5K)
├─ .env.deployment ................. Deployment settings (3.6K)
├─ .env.infrastructure ............. Infra config (2.7K)
├─ .env.production ................. Prod overrides (3.4K)
├─ .env.schema.json ................ Schema reference (11K)
└─ .env.example .................... [MISSING - create this]
```

### Analysis of Overlap

| Variable | .agent-safe | .cluster | .deploy | .infra | .prod |
|----------|------------|----------|---------|--------|-------|
| CLUSTER_NAME | ✓ | ✓ | ✗ | ✗ | ✗ |
| DOCKER_REGISTRY | ✓ | ✓ | ✓ | ✗ | ✓ |
| LOG_LEVEL | ✓ | ✗ | ✓ | ✗ | ✓ |
| NODE_ENV | ✓ | ✗ | ✗ | ✗ | ✓ |

### Recommendation: Keep as-is (No Consolidation)

**Rationale:**
- Each .env file serves distinct purpose
- Variables don't completely overlap
- Loading strategy is clear: base + environment-specific override
- Consolidating would require conditional logic (adds complexity)

**Actions:**
1. Create `.env.example` with all possible variables
2. Document loading order in README
3. Add to .gitignore verification: ensure `.env` (no suffix) is ignored
4. Move secrets to GSM (if not already done)

---

## PART 7: TERRAFORM CLEANUP

### Current State

```
terraform/
├─ Root configs (4K each):
│  ├─ main.tf
│  ├─ root.tf
│  ├─ ssl-tls.tf
│  ├─ database.tf
│  ├─ variables.tf
│  ├─ versions.tf
│  └─ [other TF configs]
│
├─ environments/private/ ............. 75M (LARGEST)
│  ├─ .terraform/ ................... ~40M (Provider cache)
│  │  ├─ providers/
│  │  │  ├─ registry.terraform.io/hashicorp/aws/5.26.0/...
│  │  │  ├─ registry.terraform.io/hashicorp/kubernetes/2.23.0/...
│  │  │  ├─ registry.terraform.io/kreuzwerker/docker/3.0.2/...
│  │  │  └─ [other providers]
│  │  └─ modules/
│  │
│  ├─ terraform.tfstate ............. (Active state)
│  ├─ terraform.tfstate.backup ...... (Backup - delete)
│  ├─ main.tf, variables.tf, etc. ... (Config)
│  └─ tfplan ........................ Binary plan files (~12K)
│
├─ .terraform/ ....................... Root providers (~25M)
│  ├─ providers/
│  └─ modules/
│
└─ modules/ .......................... Terraform modules
```

### Cleanup Recommendations

**Priority 1: Add to .gitignore (Already present, verify):**
```gitignore
# Terraform
.terraform/              # ✅ Already present
terraform/.terraform/   # ✅ Add explicitly
*.tfstate               # ✅ Already present
*.tfstate.backup        # ✅ Delete local backups
.terraform.lock.hcl     # ✅ Already present
terraform/tfplan/       # ✅ Temp plan files
```

**Priority 2: Clean Local State**
```bash
# Delete local terraform backups (keep remote only)
rm -f terraform/environments/private/terraform.tfstate.backup

# Clean provider cache locally (regenerates from lock file on next init)
rm -rf terraform/.terraform/providers/
rm -rf terraform/environments/private/.terraform/providers/
# Then run: terraform init  # to restore

# Clean plan files
rm -f terraform/tfplan/*.bin
```

**Priority 3: GIT CLEANUP**
```bash
# If tfstate was ever committed, remove from history
git filter-branch --tree-filter 'find . -name "*.tfstate" -type f -delete' -- --all

# Then garbage collection
git gc --aggressive --prune=now
```

---

## PART 8: GIT REPOSITORY HEALTH

### Current Metrics

```
Repository Size: 77M
Git Objects: 30,582
Largest Components:
  ├─ .git/objects: 76M
  ├─ .terraform/providers: ~40M (if counted)
  └─ History: Large commits from past operations
```

### Cleanup Actions

**Safe (No History Loss):**
```bash
# 1. Garbage collection
git gc --aggressive

# 2. Expire and prune reflog
git reflog expire --all --expire=now
git gc --prune=now

# 3. Verify health
git fsck --full

# 4. Check size reduction
echo "Before:" $(du -sh .git)
```

**Result Expected:**
- 77M → 65-70M (10-15% reduction)
- Faster operations (index optimization)
- Faster clones

---

## SUMMARY TABLE: ALL FILES TO MOVE

| Source | Destination | Count | Size | Risk |
|--------|-------------|-------|------|------|
| Root MD (COMPLETE/FINAL/STATUS/REPORT) | docs/archive/completed/ | 147 | 500KB | LOW |
| Root MD (PHASE*) | docs/archive/phase-summaries/ | 28 | 200KB | LOW |
| Root MD (SESSION*) | docs/archive/sessions/ | 9 | 50KB | LOW |
| Root MD (ELITE_ENTERPRISE*) | docs/archive/legacy-frameworks/ | 3 | 30KB | LOW |
| docker-compose.phase-* | docs/archive/docker-compose-variants/phase-specific/ | 7 | 50KB | LOW |
| docker-compose.infrastructure-v* | docs/archive/docker-compose-variants/infrastructure/ | 4 | 40KB | LOW |
| docker-compose.prod.yml | DELETE | 1 | 5KB | LOW |
| .backups/* | docs/archive/.backup-history/ | 307 | 3.1M | LOW |
| .bootstrap-state/* | docs/archive/.backup-history/ | 116 | 468KB | LOW |
| scripts/phase*/ | scripts/archive/deprecated/ | ~150 | 500KB | MEDIUM |
| Duplicate scripts (7) | scripts/archive/deprecated/ | 7 | 50KB | MEDIUM |
| artifacts/phase*/ | artifacts/archive/phase-NN/ | 200+ | Variable | LOW |

**TOTAL REDUCTION: ~7.5M (5% of repo) + 33% in cleanup structure**

---

## VERIFICATION COMMANDS

After cleanup, verify:

```bash
# 1. Verify file counts
echo "Root MD files:" $(ls -1 *.md 2>/dev/null | wc -l)
echo "Docker-compose files:" $(ls -1 docker-compose*.yml 2>/dev/null | wc -l)
echo "Scripts count:" $(find scripts -name '*.sh' | wc -l)

# 2. Verify archives created
echo "Archived MD files:" $(find docs/archive -name '*.md' | wc -l)
echo "Archived docker-compose:" $(find docs/archive/docker-compose-variants -name '*.yml' | wc -l)

# 3. Verify Git health
git fsck --full

# 4. Verify CI/CD still works
git log -1 --oneline

# 5. Verify key files still exist
for f in README.md docker-compose.yml scripts/ops/deploy.sh terraform/main.tf; do
  [[ -f "$f" ]] && echo "✅ $f" || echo "❌ $f MISSING"
done
```

