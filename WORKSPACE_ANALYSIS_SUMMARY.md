# Workspace Duplication & Gap Analysis
**Generated**: April 28, 2026 | **Repository**: /home/akushnir/code-server

---

## Quick Summary
- **51 Total Issues Found**: 18 HIGH, 21 MEDIUM, 12 LOW
- **3 Critical SSOT Violations**: Env vars, Docker Compose variants, Terraform variables
- **~40% Consolidation Potential**: Files, configs, scripts
- **Estimated Effort**: 3-4 weeks across 3 phases

---

## 🔴 HIGH SEVERITY (Do First)

| # | Category | Issue | Files | Impact | Priority |
|---|----------|-------|-------|--------|----------|
| 1 | Docker Compose | 16 file variants | 15 docker-compose*.yml + primary_compose_full.yml | Deployment confusion, unclear authority | **CRITICAL** |
| 2 | Environment Vars | SSOT violation - 4 definition locations | .env.deployment, .env.infrastructure, .env.cluster, terraform/variables.tf | Configuration drift, deployment failures | **CRITICAL** |
| 3 | App Directories | Duplicate directories (different naming) | apps/edge_agent + apps/edge-agent | Import failures, code desync | **HIGH** |
| 4 | App Directories | Duplicate directories (different naming) | apps/reputation_engine + apps/reputation-engine | Import failures, code desync | **HIGH** |
| 5 | Terraform | Variables duplicated across 3 locations | terraform/variables.tf + environments/*/variables.tf | Hard to replicate environments | **HIGH** |
| 6 | Terraform | SSH remote-exec pattern (not IaC) | terraform/environments/private/deployment.tf | Anti-pattern, drift risk | **HIGH** |
| 7 | IaC Gaps | Database migrations not in code | setup scripts scattered | Manual process, non-reproducible | **HIGH** |
| 8 | IaC Gaps | SSL/TLS setup as scripts | configure-postgres-ssl.sh, setup-database-ssl.sh | Manual configuration, inconsistent | **HIGH** |
| 9 | IaC Gaps | Network policies manual | kubernetes/network-policies/code-server-netpol.yaml | Not auto-enforced, drift risk | **HIGH** |
| 10 | IaC Gaps | RBAC manual | kubernetes/rbac/code-server-rbac.yaml | Not auto-enforced, drift risk | **HIGH** |

---

## 🟡 MEDIUM SEVERITY (Next Priority)

| # | Category | Issue | Files | Impact |
|---|----------|-------|-------|--------|
| 1 | Helm Values | Overlapping resource definitions | values.yaml + config/resource-limits.yaml | Inconsistent provisioning |
| 2 | Helm Values | Duplicate prod configs | values.prod.yaml + values-prod.yaml | Unclear which is used |
| 3 | Config Files | Alert configs scattered | monitoring/alertmanager.yml, config/alert-rules.yml, monitoring/alerts/prometheus-rules.yaml | Missed alerts, unclear authority |
| 4 | Config Files | Otel/Tempo duplicates | otel-collector.yaml + otel-collector.config.yaml | Which is used? Why two? |
| 5 | Config Files | Message broker configs scattered | config/kafka-topics.yaml + config/redpanda.yaml + docker-compose.redpanda.yml | Configuration drift |
| 6 | Scripts | Health check functions duplicated | deploy-idempotent, rollback-idempotent, automated-rollback, test-e2e-load, chaos-test | Maintenance burden |
| 7 | Scripts | wait_for_* functions duplicated | 5+ implementations (different logic) | Retry logic inconsistency |
| 8 | Scripts | Log functions duplicated | 24 scripts with local log_info/log_error | Inconsistent logging format |
| 9 | CI/CD | Pre-deployment validation duplicated | pre-deployment-validation.sh + pre-deployment-validation-simple.sh | Unclear which to use |
| 10 | CI/CD | Drift detection duplicated | drift-detection.yml + gitops-drift-detection.yml | Redundant workflows |
| 11 | Documentation | Deployment docs scattered | 3 DEPLOYMENT_*.md files (DEPLOYMENT-MANIFEST.md vs DEPLOYMENT_MANIFEST.md!) | Documentation confusion |
| 12 | Documentation | Scoping docs duplicated | 5 SCOPING*.md files | Outdated procedures followed |
| 13 | Testing | Test locations scattered | tests/ + apps/*/tests/ + scripts/test-* + .github/workflows/*test* | Hard to discover/run |
| 14 | Shared Libraries | No common Python utilities | Each app loads own config (50+ os.getenv calls) | Code duplication |
| 15 | Shared Libraries | Auth patterns duplicated | apps/*/src/oauth2_server.py | Inconsistent OAuth handling |

---

## 🟢 LOW SEVERITY (Nice to Have)

| # | Category | Issue | Files | Impact |
|---|----------|-------|-------|--------|
| 1 | Ephemeral Resources | Unclear backup strategy | Config + monitoring tools | Data loss risk (low) |
| 2 | Naming Conventions | docker-compose.{type}.yml vs docker-compose-{variant}.yml | Mixed naming | Minor confusion |
| 3 | Package Structure | No apps/_shared/ directory | Monorepo not optimized | Maintenance overhead |
| 4 | Documentation | Historical phase docs | PHASE15-*, PHASES-1-14* | Outdated docs discoverable |
| 5 | Database | Postgres init scripts embedded | Multiple setup-*.sh | Hard to audit schema |
| 6 | Health Checks | Service-specific checks duplicated | qdrant, redpanda, opa, postgres | Maintenance burden |
| 7 | Archives | Backup files in root | .backups/, docs/archive/ | Clutters workspace |
| 8 | Docker | Base image versions inconsistent | 3 different Python slim SHA256s | Rebuild inconsistency |
| 9 | Testing | No test orchestrator | No central test runner | Tests hard to aggregate |
| 10 | CI/CD | 15+ GitHub workflows | Many overlapping concerns | Workflow maintenance |
| 11 | Secrets | No centralized secret management visible | Hardcoded defaults in code | Security risk (low) |
| 12 | Documentation | Multiple status files | DEPLOYMENT_STATUS.md + DEPLOYMENT_COMPLETE.txt + FINAL-DEPLOYMENT-STATUS.txt | Outdated status discovered |

---

## Detailed File Inventory

### Docker Compose Variants (16 files)
```
docker-compose.yml (PRIMARY - 41 services)
docker-compose.yml.backup
docker-compose-clean.yml
docker-compose-cluster.yml
docker-compose-fixed.yml
docker-compose-full-deployment.yml
docker-compose-noinit.yml
docker-compose-production.yml
primary_compose_full.yml
docker-compose.ai.yml
docker-compose.edge-agent.yml
docker-compose.enterprise.yml
docker-compose.enterprise-replica.yml
docker-compose.observability.yml
docker-compose.override.yml
docker-compose.redpanda.yml
docs/archive/primary_compose_full.yml
```

### Environment Variable Definition Locations (4)
```
.env.deployment (26 vars: DB_*, REDIS_*, QDRANT_*, etc.)
.env.infrastructure (17 vars: API_*, HEALTH_*, endpoints)
.env.cluster (30+ vars: POSTGRES_*, REDIS_*, REDPANDA_*, QDRANT_*)
terraform/environments/*/variables.tf (apex_domain, hosts, registry)
```

### Helm Values Overlapping (6 files)
```
helm/code-server-enterprise/
  ├─ values.yaml (base)
  ├─ values-dev.yaml
  ├─ values-prod.yaml
  ├─ values.prod.yaml (DUPLICATE!)
  ├─ values-staging.yaml
  └─ values.phase4-k8s.yaml
```

### Configuration Files Scattered
```
Monitoring:
  monitoring/alertmanager.yml
  config/alert-rules.yml
  monitoring/alerts/prometheus-rules.yaml
  monitoring/alerts/alert-rules.yml

Message Broker:
  config/kafka-topics.yaml
  config/redpanda.yaml
  docker-compose.redpanda.yml

Observability:
  config/otel-collector.yaml
  config/otel-collector.config.yaml (DUPLICATE?)
  config/tempo.yaml
  config/tempo.config.yaml (DUPLICATE?)
```

### Duplicate App Directories
```
apps/edge_agent/ + apps/edge-agent/
apps/reputation_engine/ + apps/reputation-engine/
```

### Scripts with Duplicate Functions
```
wait_for_healthy_services(): in 5 scripts (deploy-idempotent, rollback-idempotent, automated-rollback, idempotency-enforcer, etc.)
log_info/log_error/log_success: in 24 scripts locally
wait_for_* functions: 5+ implementations with different retry logic
```

### Documentation Duplicates
```
DEPLOYMENT-MANIFEST.md vs DEPLOYMENT_MANIFEST.md (BOTH EXIST!)
DEPLOYMENT_SCOPING.md vs SCOPING*.md (5 scoping files)
PHASES-1-14* + PHASES-1-15* + PHASE15-* (multiple completion docs)
DEPLOYMENT_STATUS.md + DEPLOYMENT_COMPLETE.txt + FINAL-DEPLOYMENT-STATUS.txt (status scattered)
```

---

## Recommended 3-Phase Remediation

### Phase 1: CRITICAL (1-2 weeks)
1. Audit which docker-compose files are actually used; mark/archive unused 12-14 files
2. Create `scripts/_common/config.env` - consolidate 40+ env vars from 4 locations
3. Resolve edge-agent/edge_agent and reputation-engine/reputation_engine duplicates
4. Update all imports and terraform variable sourcing

### Phase 2: CORE (2-4 weeks)
5. Consolidate Helm values (delete prod.yaml duplicate, document merge strategy)
6. Reorganize config/ into subfolders: monitoring/, message-broker/, observability/
7. Add wait_for_healthy_services to scripts/_common/init.sh
8. Archive/merge 5 scoping docs into 1 SCOPING.md
9. Move SSH remote-exec from terraform to scripts/ops/ (orchestration layer)

### Phase 3: IaC & SSOT (ongoing)
10. Add terraform for K8s resources (network policies, RBAC, secrets)
11. Move database migrations to terraform/helm init containers
12. Create apps/_shared/python/ with config, auth, logging utilities
13. Centralize test framework with tests/README.md and ci/test-orchestrator.sh

---

## Files to Delete/Archive (Confirm First)

**Docker Compose** (keep docker-compose.yml only):
- docker-compose-clean.yml
- docker-compose-cluster.yml
- docker-compose-fixed.yml
- docker-compose-full-deployment.yml
- docker-compose-noinit.yml
- docker-compose-production.yml
- primary_compose_full.yml
- docker-compose.yml.backup

**Helm Values** (keep values-prod.yaml, values-dev.yaml, values-staging.yaml):
- values.prod.yaml (duplicate of values-prod.yaml)
- values.phase4-k8s.yaml (archival, K8s Phase 4)

**Documentation** (archive to docs/archive/):
- PHASES-1-14-COMPLETION-SUMMARY.md
- PHASES-1-15-FINAL-COMPLETION-SUMMARY.md
- PHASE15-ADVANCED-TESTING-*.md
- K8S-MIGRATION-*.md
- ISSUE-1537-*.md
- CLUSTER-SHUTDOWN-REPORT-2026-04-27.md
- 20+ other dated status files

**Duplicates** (clean up):
- One of: edge_agent/ or edge-agent/
- One of: reputation_engine/ or reputation-engine/

---

## SSOT Foundation Files to Create

```
scripts/_common/config.env
  - Consolidates 40+ vars from .env.*, terraform, docker-compose

scripts/_common/health-checks.sh
  - wait_for_healthy_services()
  - service-specific health check helpers

apps/_shared/python/config.py
  - Centralized environment variable loading

apps/_shared/python/auth.py
  - OAuth2 patterns (OIDC, GitHub, Google)

docs/architecture/resource-classification.md
  - Ephemeral vs persistent resource definitions
  - Backup strategy per resource
  - Retention policies

docs/SCOPING.md (merged from 5 files)
  - Single source for scope boundaries
```

---

## Validation Checklist

After implementation, verify:
- [ ] Single docker-compose.yml (12-14 deprecated variants archived)
- [ ] All .env.* files source scripts/_common/config.env
- [ ] Zero duplicate app directories (edge-agent, reputation-engine standardized)
- [ ] Config files organized into 5 subdirectories
- [ ] All scripts source scripts/_common/health-checks.sh
- [ ] Helm values consolidated (single prod/dev/staging pattern)
- [ ] 70%+ of documentation archived/consolidated
- [ ] Terraform variables defined in single location
- [ ] Database migrations in IaC (terraform or Helm init)
- [ ] apps/_shared/python/ contains shared utilities

---

## Impact Summary

| Consolidation | Before | After | Effort | Benefit |
|---|---|---|---|---|
| Docker Compose | 16 variants | 1 primary + archive | LOW | HIGH (clarity) |
| Environment Vars | 4 sources | 1 SSOT | MEDIUM | HIGH (deployability) |
| Config Files | 20+ scattered | 5 organized folders | MEDIUM | MEDIUM (maintainability) |
| Scripts | 24 duplicates | 1 shared library | MEDIUM | MEDIUM (maintenance) |
| Documentation | 40+ status/phase docs | 1-5 current docs | LOW | HIGH (clarity) |
| **TOTAL** | **~70 redundant files/configs** | **~50% reduction** | **3-4 weeks** | **SIGNIFICANT** |

