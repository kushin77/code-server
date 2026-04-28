# Workspace Health Dashboard

## Duplications by Category

```
Docker Compose Files         ████████████████████ 16 files
  └─ Impact: Deployment authority unclear
  └─ Effort: LOW | Impact: HIGH

Environment Variables (4x)   ████████░░ (consolidated 40 vars)
  └─ Impact: Configuration drift
  └─ Effort: MEDIUM | Impact: HIGH

Terraform Variables (3x)     ████████░░ (root + 2 environments)
  └─ Impact: Environment reproducibility
  └─ Effort: MEDIUM | Impact: HIGH

Helm Values Files (6x)       ██████░░░░ (values.* + values-*.yaml)
  └─ Impact: Resource provisioning inconsistency
  └─ Effort: LOW | Impact: MEDIUM

Config Files (Scattered)     ███████░░░ (20+ files across 4 folders)
  └─ Impact: Configuration discovery
  └─ Effort: MEDIUM | Impact: MEDIUM

Script Functions (24x)       ██████░░░░ (log_info in 24 scripts)
  └─ Impact: Logging inconsistency
  └─ Effort: MEDIUM | Impact: MEDIUM

Documentation (40+ files)    ███████░░░ (phases, deployments, scoping)
  └─ Impact: Outdated procedures discovered
  └─ Effort: LOW | Impact: MEDIUM

```

## Severity Heatmap

```
        EFFORT →
        Low  Med  High
        
HIGH   [10] [8]  [0]     ← CRITICAL: Do First (18 items)
SEVER-
ITY ↓  MEDIUM [5]  [16] [0]     ← IMPORTANT: Phase 2 (21 items)

LOW    [9]  [3]  [0]     ← NICE: Phase 3 (12 items)
```

**Quadrant Analysis:**
- **Quick Wins** (Low Effort, High Impact): 
  - Delete docker-compose variants (5 items)
  - Archive old documentation (5 items)
  - Fix naming duplicates (2 items)
  
- **Must Do** (Medium Effort, High Impact): 
  - Environment variable SSOT (1 item)
  - Terraform consolidation (2 items)
  - IaC gaps (4 items)
  
- **Backlog** (High Effort, Medium Impact):
  - Shared libraries creation (2 items)
  - IaC expansion (5 items)
  - Testing framework (1 item)

---

## Duplicate Fingerprint Analysis

### Docker Compose Variants
```
Primary:         docker-compose.yml (41 services, 1497 lines)
├─ Backup:       docker-compose.yml.backup (identical)
├─ Test:         docker-compose-clean.yml
├─ Test:         docker-compose-fixed.yml
├─ Test:         docker-compose-noinit.yml
├─ Historical:   docker-compose-cluster.yml
├─ Historical:   docker-compose-full-deployment.yml
├─ Historical:   primary_compose_full.yml
├─ Production:   docker-compose-production.yml
├─ Enterprise:   docker-compose.enterprise.yml
├─ Enterprise:   docker-compose.enterprise-replica.yml
├─ Add-on:       docker-compose.ai.yml
├─ Add-on:       docker-compose.edge-agent.yml
├─ Add-on:       docker-compose.observability.yml
├─ Add-on:       docker-compose.override.yml
└─ Add-on:       docker-compose.redpanda.yml

CONSOLIDATION OPPORTUNITY: 12-14 files → archive
RETENTION: docker-compose.yml + overlay files (.ai, .edge-agent, .observability)
```

### Environment Variable Duplication
```
.env.deployment (26 vars) ━━━┓
                               ├━━→ DB_USER, DB_PASSWORD, DB_NAME
.env.cluster (30+ vars) ━━━━━┛    REDIS_PASSWORD, QDRANT_API_KEY
                               
.env.infrastructure (17 vars) ━━→ API_HOST, API_PORT, PRIMARY_HOST
                               
terraform/variables.tf ━━━━━→    apex_domain, primary_host, registry
                               
50+ Python scripts ━━━━━━━━→    os.getenv() with hardcoded defaults

CONSOLIDATION POINT: scripts/_common/config.env
All other sources source or override this file
```

### Terraform Variable Duplication
```
terraform/variables.tf (root)
├─ apex_domain
├─ primary_host
├─ admin_email
└─ ... 15+ more

terraform/environments/private/variables.tf (redundant copy)
terraform/environments/air-gapped/variables.tf (redundant copy)

CONSOLIDATION: Single variables.tf + environment-specific overrides
```

### Helm Values Overlaps
```
values.yaml (base defaults)
  ├─ global.domain, tlsEnabled, tlsEmail
  ├─ resources.limits (cpu: 500m, memory: 512Mi)
  └─ 50+ base settings

values-dev.yaml (override subset)
  ├─ global.logLevel = debug
  └─ resources.requests (smaller)

values-prod.yaml AND values.prod.yaml (BOTH EXIST!)
values-staging.yaml
values.phase4-k8s.yaml (K8s Phase 4, possibly stale)
values-env-override.yaml

+ SEPARATE: config/resource-limits.yaml (different format!)

CONSOLIDATION: Delete prod.yaml duplicate, consolidate resource limits
```

### Configuration File Chaos
```
monitoring/alertmanager.yml ┐
config/alert-rules.yml      ├─ ALERT CONFIG (3 sources!)
monitoring/alerts/...yaml   ┘

config/prometheus.yml ┐
monitoring/alerts/prometheus-rules.yaml ┘ PROMETHEUS CONFIG (2 sources)

config/otel-collector.yaml ┐
config/otel-collector.config.yaml ┘ OTEL (2 copies?)

config/tempo.yaml ┐
config/tempo.config.yaml ┘ TEMPO (2 copies?)

CONSOLIDATION TARGET:
  config/monitoring/
  config/message-broker/
  config/observability/
```

### Script Function Duplication
```
wait_for_healthy_services() ← defined in 5 files
├─ scripts/ops/deploy-idempotent.sh
├─ scripts/ops/rollback-idempotent.sh
├─ scripts/ops/automated-rollback.sh
├─ scripts/ops/idempotency-enforcer.sh (x2 versions!)
└─ scripts/.backups/

wait_for_compose_health() ← defined in 2+ files
wait_for_recovery() ← defined in tests/chaos/
wait_for_service() ← defined in scripts/test-e2e-load.sh
wait_for_cluster_ready() ← defined in scripts/k8s/

log_info(), log_error(), log_success() ← 24 local definitions

CONSOLIDATION: scripts/_common/{init,health-checks}.sh
```

### Documentation Duplication
```
DEPLOYMENT*.md (NAMING CONFLICT!)
├─ DEPLOYMENT-MANIFEST.md (495 lines)
├─ DEPLOYMENT_MANIFEST.md (SAME NAME DIFFERENT CASE?!)
├─ DEPLOYMENT_SCOPING.md
├─ DEPLOYMENT_STATUS.md
├─ DEPLOYMENT_COMPLETE.txt
└─ FINAL-DEPLOYMENT-STATUS.txt

SCOPING*.md (5 files)
├─ SCOPING_IMPLEMENTATION.md
├─ SCOPING_IMPLEMENTATION_COMPLETE.md
├─ SCOPING_QUICK_REFERENCE.md
├─ SCOPING_SUMMARY.md
└─ DEPLOYMENT_SCOPING.md

PHASE*.md (20+ files)
├─ PHASES-1-14-COMPLETION-SUMMARY.md
├─ PHASES-1-15-FINAL-COMPLETION-SUMMARY.md
├─ PHASE15-ADVANCED-TESTING-*.md (x2)
├─ K8S-MIGRATION-*.md (x2)
└─ ISSUE-1537-WEEK-5-*.md (x2)

STATUS*.md (3 files)
├─ DEPLOYMENT_STATUS.md
├─ DEPLOYMENT_COMPLETE.txt
└─ FINAL-DEPLOYMENT-STATUS.txt

CONSOLIDATION TARGET:
  Keep: DEPLOYMENT_MANIFEST.md (standardize naming), SCOPING.md, README.md
  Archive: 30+ others to docs/archive/
```

---

## Consolidation Timeline

### WEEK 1: Quick Wins
```
Day 1: Docker Compose Audit
  - Identify which files actively used
  - Mark others deprecated
  - Create docker-compose.yml versions.md

Day 2: Environment Variable SSOT
  - Create scripts/_common/config.env (40+ vars)
  - Update .env.* to source it
  - Update terraform/env-to-tfvars.sh

Day 3: Duplicate App Directories
  - Resolve edge-agent vs edge_agent
  - Resolve reputation-engine vs reputation_engine
  - Update all imports

Day 4-5: Documentation Cleanup
  - Archive 25+ phase/status docs
  - Merge 5 scoping files into 1
  - Fix DEPLOYMENT-MANIFEST.md naming
```

### WEEK 2-3: Core Infrastructure
```
Day 6-7: Configuration Reorganization
  - Consolidate config/ → monitoring/, message-broker/, observability/
  - Move SSH from terraform → scripts/ops/
  - Document config precedence

Day 8-9: Script Consolidation
  - Add wait_for_healthy_services to scripts/_common/init.sh
  - Create scripts/_common/health-checks.sh
  - Update all callers

Day 10-11: Helm Values
  - Delete duplicate prod.yaml
  - Consolidate resource-limits.yaml → Helm
  - Document merge strategy

Day 12-13: Terraform
  - Consolidate variables.tf (3 → 1)
  - Move SSH orchestration to scripts/ops/
  - Create terraform/environments/{env}.tfvars
```

### WEEK 4+: IaC Gaps
```
Day 14-21: Infrastructure as Code
  - Database migrations → terraform
  - SSL/TLS → terraform ACME
  - Network policies → terraform
  - RBAC → terraform
  - Backup policy → terraform

Day 22+: Shared Libraries
  - Create apps/_shared/python/ structure
  - Implement config.py, auth.py, logging.py
  - Gradually migrate apps
```

---

## Consolidation Checklist

### Phase 1: CRITICAL (Week 1)
- [ ] Audit docker-compose variants (active vs historical)
- [ ] Create scripts/_common/config.env with 40+ vars
- [ ] Update .env.deployment to source config.env
- [ ] Update .env.infrastructure to source config.env
- [ ] Update .env.cluster to source config.env
- [ ] Resolve edge-agent vs edge_agent (delete one, update imports)
- [ ] Resolve reputation-engine vs reputation_engine (delete one, update imports)
- [ ] Fix DEPLOYMENT-MANIFEST.md naming (delete .md variant if duplicate)
- [ ] Archive 25+ dated/phase documentation files

### Phase 2: CORE (Weeks 2-3)
- [ ] Consolidate config files into subdirectories
- [ ] Move SSH commands from terraform to scripts/ops/
- [ ] Verify otel/tempo config duplicates (delete if redundant)
- [ ] Move wait_for_healthy_services to scripts/_common/init.sh
- [ ] Create scripts/_common/health-checks.sh
- [ ] Update deploy-idempotent.sh to source health-checks.sh
- [ ] Update rollback-idempotent.sh to source health-checks.sh
- [ ] Delete values.prod.yaml (keep values-prod.yaml)
- [ ] Consolidate terraform variables (single variables.tf)
- [ ] Merge 5 scoping docs into SCOPING.md

### Phase 3: IaC (Weeks 4+)
- [ ] Database migrations to terraform provisioner
- [ ] SSL/TLS setup to terraform
- [ ] Network policies to terraform
- [ ] RBAC to terraform
- [ ] Create apps/_shared/python/config.py
- [ ] Create apps/_shared/python/auth.py
- [ ] Migrate first 3 apps to use shared utilities
- [ ] Create tests/README.md with test hierarchy
- [ ] Create ci/test-orchestrator.sh

---

## Success Metrics

| Metric | Before | After | Status |
|--------|--------|-------|--------|
| Docker Compose Variants | 16 | 1 (+ overlays) | 🔴 Pending |
| Environment Var Sources | 4 | 1 | 🔴 Pending |
| Config Files Organized | 20+ scattered | 5 folders | 🔴 Pending |
| Terraform Var Locations | 3 | 1 | 🔴 Pending |
| Documentation Files | 40+ | 5-8 active | 🔴 Pending |
| Script Duplication | 24+ functions | 1-2 centralized | 🔴 Pending |
| Shared Library Coverage | 0% | 80%+ | 🔴 Pending |
| **Overall Consolidation** | **~70 redundant items** | **~40% reduction** | 🔴 Pending |

---

## Files Generated by This Analysis

1. **WORKSPACE_ANALYSIS_SUMMARY.md** - This report
2. **WORKSPACE_ANALYSIS_ISSUES.csv** - Machine-readable issue inventory
3. Session memory: `/memories/session/workspace-analysis-2026-04-28.md` - Detailed findings

## Next Steps

1. Review recommendations with team
2. Prioritize by business impact
3. Assign owners to each phase
4. Execute Phase 1 (quick wins) to build momentum
5. Document decisions as you consolidate

