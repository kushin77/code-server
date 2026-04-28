# SSOT (Single Source of Truth) Governance Index
**Last Updated**: April 28, 2026  
**Audit Status**: IN PROGRESS  
**Completeness**: Phase 1 Quick Wins (4/4) + Phase 2 Core (STARTING)

---

## Executive Summary

This document is the **canonical registry** of where authoritative data lives across the infrastructure project. All teams must consult this index before creating new configs, variables, or policies.

**Key Principle**: ONE source, MULTIPLE consumers (no duplication)

---

## 🔴 CRITICAL SSOT - Eliminate Redundancy

### 1. Environment Variables
**Canonical Location**: `scripts/_common/config.env`  
**Status**: ✅ IMPLEMENTED (April 28, 2026)
- Consolidates 4 previous .env files
- All env var definitions must go here
- Scripts source this file via: `source scripts/_common/config.env`
- Includes validation function: `validate_required_vars`

**Deprecated Locations** (keep for backward compat, but AUTHORITATIVE is config.env):
- ~~.env.deployment~~ (use config.env)
- ~~.env.infrastructure~~ (use config.env)
- ~~.env.cluster~~ (use config.env)
- ~~terraform/variables.tf~~ (split into modules + .tfvars, see Terraform strategy)

---

### 2. Logging Functions
**Canonical Location**: `scripts/_common/init.sh`  
**Status**: ✅ EXISTING + VERIFIED
- Functions: `log_info`, `log_error`, `log_success`, `log_warn`, `log_warning`
- Source via: `source scripts/_common/init.sh`
- All scripts MUST use these, not local duplicates

**Scope**: All 24 scripts currently with local log functions should migrate (Phase 2)

---

### 3. Health Check Functions
**Canonical Location**: `scripts/_common/health-checks.sh` (NEW)  
**Status**: ✅ IMPLEMENTED (April 28, 2026)
- Functions: Generic + service-specific checks
- Source via: `source scripts/_common/health-checks.sh`
- Services covered: PostgreSQL, Redis, Kafka, Qdrant, OPA
- Replaces duplicates in: deploy-idempotent.sh, rollback-idempotent.sh, test-e2e-load.sh

---

### 4. Container/Service Names
**Canonical Location**: `scripts/_common/service-names.env` (EXISTING)  
**Status**: ✅ VERIFIED (from Phase 4 consolidation)
- Variables: `POSTGRES_CONTAINER_NAME`, `REDIS_CONTAINER_NAME`, `QDRANT_CONTAINER_NAME`, etc.
- Use these in docker exec commands, not hardcoded names

---

### 5. Docker Compose Configuration
**Canonical Location**: `docker-compose.yml` (PRIMARY)  
**Status**: ⚠️ IN PROGRESS (Phase 1)
- 1 primary file with all 41 services + all profiles
- Variant overlays: `.override.yml`, `.prod.yml` (consolidating)
- **Archive targets** (12 files):
  ```
  docker-compose-clean.yml
  docker-compose-cluster.yml
  docker-compose-fixed.yml
  docker-compose-full-deployment.yml
  docker-compose-noinit.yml
  docker-compose-production.yml
  primary_compose_full.yml
  .ai.yml, .edge-agent.yml, .enterprise.yml, .enterprise-replica.yml, .observability.yml, .redpanda.yml
  ```

---

### 6. Terraform Variables
**Canonical Locations** (by scope):
- **Global defaults**: `terraform/variables.tf`
- **Module inputs**: `terraform/modules/*/variables.tf` ✅ CORRECT PATTERN
- **Environment values**: `terraform/environments/<env>/{private,air-gapped}.tfvars`

**Status**: 📋 DOCUMENTED PLAN (terraform/VARIABLE_CONSOLIDATION_PLAN.md)  
**Action**: Phase 2 - consolidate environment values to .tfvars

---

## 🟡 MEDIUM SSOT - Organize Configuration

### 7. Monitoring & Alerting Configuration
**Canonical Location**: `config/monitoring/` (REORGANIZING)  
**Current State** (SCATTERED):
- ~~monitoring/alertmanager.yml~~ → config/monitoring/alertmanager.yml
- ~~config/alert-rules.yml~~ → config/monitoring/prometheus-rules.yml
- ~~monitoring/alerts/prometheus-rules.yaml~~ → config/monitoring/prometheus-rules.yml

**Action**: Consolidate to single `config/monitoring/` directory (Phase 2)

---

### 8. Message Broker Configuration  
**Canonical Location**: `config/message-broker/` (CONSOLIDATING)  
**Current State**:
- config/kafka-topics.yaml → config/message-broker/topics.yaml
- config/redpanda.yaml → config/message-broker/redpanda.yaml
- docker-compose.redpanda.yml (SERVICE definition, not config)

**Action**: Separate config from Docker service definitions (Phase 2)

---

### 9. Otel/Observability Configuration
**Canonical Locations**:
- `config/otel-collector.yaml` (AUTHORITATIVE)
- ~~config/otel-collector.config.yaml~~ (DELETE - duplicate)
- `config/tempo.yaml` (AUTHORITATIVE)
- ~~config/tempo.config.yaml~~ (DELETE - duplicate)

**Action**: Verify which is used, delete duplicates (Phase 1)

---

### 10. Policy as Code (OPA)
**Canonical Location**: `policies/` directory  
**Status**: ✅ EXISTING
- Rego policies are centralized
- Bound to OPA service in docker-compose.yml

---

## 🟢 ORGANIZATIONAL SSOT - Structure & Standards

### 11. Shared Libraries
**Canonical Location**: `apps/_shared/` (TO CREATE)  
**Status**: 📋 PLANNED (Phase 2)
- Python utilities: `config.py`, `auth.py`, `logging.py`
- Shell utilities: consolidated functions
- Shared models and interfaces

**Current State** (SCATTERED):
- Each app has own config loading (50+ os.getenv calls)
- Auth patterns duplicated in 5 apps
- No shared utilities directory

---

### 12. Documentation Standards
**Canonical Location**: `docs/` with clear structure
- **Active docs**: README.md, DEPLOYMENT_MANIFEST.md, DEPLOYMENT_STATUS.md, SCOPING_SUMMARY.md
- **Archived docs**: docs/archive/retired/ ✅ CREATED (April 28)
- **Architecture docs**: docs/architecture/
- **Operational docs**: docs/operations/

---

### 13. Testing Organization
**Canonical Location**: `tests/` as single entrypoint
- `tests/README.md` - documents test hierarchy
- `tests/unit/` - unit tests
- `tests/integration/` - integration tests
- `tests/e2e/` - end-to-end tests
- `tests/chaos/` - chaos engineering

**Current State**: Scattered across `apps/*/tests/`, `scripts/test-*`, `.github/workflows/*test*`

---

## Database & IaC Standards

### 14. Database Migrations
**Canonical Location**: `migrations/` (TO CREATE - Phase 3)
- Versioned SQL migrations
- Terraform provisioners execute them
- Immutable, idempotent by design

---

### 15. Kubernetes Manifests
**Canonical Location**: `kubernetes/` directory structure
- **Network policies**: kubernetes/network-policies/ → terraform/modules/security/network_policies.tf (Phase 3 - IaC)
- **RBAC**: kubernetes/rbac/ → terraform/modules/security/rbac.tf (Phase 3 - IaC)
- **Helm values**: helm/code-server-enterprise/values*.yaml

---

## Validation & Enforcement

### SSOT Validation Commands

```bash
# Check environment variables are exported
source scripts/_common/config.env
validate_required_vars

# Check logging functions available
source scripts/_common/init.sh
declare -f log_info log_error log_success

# Check health checks available
source scripts/_common/health-checks.sh
declare -f check_postgres_health wait_for_all_services

# Check service names available
source scripts/_common/service-names.env
echo $POSTGRES_CONTAINER_NAME $REDIS_CONTAINER_NAME $QDRANT_CONTAINER_NAME
```

---

## Phase Progress Tracker

| Phase | Status | SSOT Items | Effort | Target Date |
|-------|--------|-----------|--------|------------|
| **Phase 1: Quick Wins** | ✅ 4/4 DONE | config.env, health-checks.sh, archives, app dirs | 1-2 wks | ✅ Apr 28 |
| **Phase 2: Core** | 📋 PLANNED | Terraform, docker-compose, logging, monitoring | 2-4 wks | May 12 |
| **Phase 3: IaC** | 📋 PLANNED | Migrations, Terraform modules, K8s IaC | Ongoing | May 26+ |

---

## Key Rules for Developers

1. **NEW environment variable?** → Add to `scripts/_common/config.env`, not `.env.*`
2. **NEW logging statement?** → Use `log_info`/`log_error` from `init.sh`, not `echo`
3. **NEW health check?** → Add to `scripts/_common/health-checks.sh`, not local duplicate
4. **NEW shared code?** → Put in `apps/_shared/`, not copy into each app
5. **NEW config?** → Use `config/` directory structure, not scattered files
6. **NEW documentation?** → Use `docs/` structure, archive old docs

---

## SSOT Violations Found & Resolved

| Violation | Location | Resolved |
|-----------|----------|----------|
| Env vars in 4 places | .env.deployment/infrastructure/cluster + terraform | ✅ Apr 28 - config.env |
| Logging functions duplicated | 24 scripts | ⚠️ Planned Phase 2 |
| Health checks duplicated | 5 scripts | ✅ Apr 28 - health-checks.sh |
| Docker-compose variants | 16 files | ⚠️ In progress |
| Terraform vars duplicated | 4 locations | ✅ Plan documented |
| Alert configs scattered | 3 locations | ⚠️ Planned Phase 2 |
| App directories duplicate | 2 pairs | ✅ Apr 28 - deleted |
| Monitoring configs scattered | 3 locations | ⚠️ Planned Phase 2 |
| Documentation cluttered | 40+ files | ✅ Apr 28 - archived |

---

**Status**: ACTIVELY MAINTAINED - Updated with each audit phase  
**Owner**: Infrastructure Audit Bot  
**Next Review**: April 30, 2026
