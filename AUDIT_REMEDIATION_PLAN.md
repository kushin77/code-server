# Code Review & Infrastructure Audit - Remediation Plan
**Generated**: April 28, 2026  
**Status**: IN PROGRESS  
**Severity**: 51 issues (18 HIGH, 21 MEDIUM, 12 LOW)

---

## PHASE 1: Quick Wins (1-2 weeks) ✅ ACTIVE

### 1. Duplicate App Directories - ANALYZING
**Canonical Versions** (keep these):
- `apps/reputation_engine/` (8 Python files, ~2300 LOC)
- `apps/edge-agent/` (7 Python files, ~1100 LOC)

**Duplicates to Delete**:
- `apps/reputation-engine/` (4 Python files, ~1040 LOC) - OUTDATED COPY
- `apps/edge_agent/` (4 Python files, ~710 LOC) - OUTDATED COPY

**Root Cause**: Historical naming inconsistency (underscores vs hyphens) during refactoring  
**Impact**: Import failures if code uses wrong paths  
**Action**: Delete duplicates, verify git history, test deployment  

---

### 2. Environment Variable SSOT - TODO
**Current State**: 4 separate definition locations:
- `.env.deployment` (26 vars)
- `.env.infrastructure` (17 vars)  
- `.env.cluster` (30+ vars)
- `terraform/environments/*/variables.tf` (registry, hosts, domain)

**Overlaps Found**: DB_*, REDIS_*, QDRANT_*, POSTGRES_*, API_* defined in multiple places

**Solution**: Create `scripts/_common/config.env` as canonical SSOT
- Consolidate all env var definitions
- Update all scripts to source from single location
- Add validation for required variables
- Document variable lifecycle (static vs generated)

---

### 3. Docker Compose Consolidation - TODO
**Current**: 16 variants
```
docker-compose.yml (PRIMARY - 41 services)
├── docker-compose.yml.backup
├── docker-compose-clean.yml
├── docker-compose-cluster.yml
├── docker-compose-fixed.yml
├── docker-compose-full-deployment.yml
├── docker-compose-noinit.yml
├── docker-compose-production.yml
├── primary_compose_full.yml
└── .{ai,edge-agent,enterprise,enterprise-replica,observability,override,redpanda}.yml (8 files)
```

**Solution**: Consolidate to 1 primary + overlays:
```
docker-compose.yml (main - 41 services with ALL profiles)
docker-compose.override.yml (local dev)
docker-compose.prod.yml (production values)
[ARCHIVE rest to docs/archive/]
```

---

### 4. Archive Outdated Documentation - TODO
**Files to Archive** (25+ files):
- `PHASES-1-14-COMPLETION-SUMMARY.md`
- `PHASES-1-15-FINAL-COMPLETION-SUMMARY.md`
- `K8S-MIGRATION-*.md` (3 files)
- `ISSUE-1537-*.md` (3 files)
- `PHASE15-*.md` (2 files)
- `DEPLOYMENT-MANIFEST.md` (rename to `DEPLOYMENT_MANIFEST.md` - case mismatch!)
- `DEPLOYMENT_COMPLETE.txt` (archive)
- `FINAL-DEPLOYMENT-STATUS.txt` (archive)

**Action**: `mkdir -p docs/archive/retired && mv PHASES*.md PHASE15*.md K8S-*.md ISSUE-*.md docs/archive/retired/`

---

## PHASE 2: Core Refactoring (2-4 weeks) - TODO

### 5. Terraform Variable Consolidation
Move all variables to single `terraform/variables.tf`:
- Environment-specific overrides via `.tfvars` files
- Remove duplication in `terraform/environments/*/variables.tf`

### 6. Move SSH Orchestration to Scripts
Current: SSH remote-exec in `terraform/environments/private/deployment.tf` (ANTI-PATTERN)  
Action: Extract to `scripts/ops/remote-deployment.sh` orchestration  

### 7. Consolidate Logging Functions
Current: 24 scripts with local `log_info/log_error/log_success` implementations  
Action: Standardize in `scripts/_common/init.sh` with ANSI colors, timestamps

### 8. Centralize Health Check Logic
Current: Duplicated in `deploy-idempotent.sh`, `rollback-idempotent.sh`, test scripts  
Action: Create `scripts/_common/health-checks.sh` with service-specific functions

---

## PHASE 3: IaC Hardening (Ongoing) - TODO

### 9. Database Migrations as Code
Current: Setup scripts scattered  
Action: Implement `migrations/` with versioning  

### 10. SSL/TLS via Terraform
Current: `configure-postgres-ssl.sh` (manual shell scripts)  
Action: Use Terraform ACME provider + K8s secret automation

### 11. Create `apps/_shared/` for Shared Utilities
- Python: `config.py`, `auth.py`, `logging.py`
- Shell: Common functions extracted

### 12. Move Network Policies to IaC
Current: `kubernetes/network-policies/` (manual YAML)  
Action: Terraform modules for auto-enforcement

---

## Testing & Governance

### Background Validation Suite
- Syntax checks on all scripts after edits
- Idempotency verification for deployments
- Environment variable validation
- Docker image consistency checks

### GitHub Issue Integration
- Automatically create issues for HIGH/MEDIUM findings
- Tag with `audit-remediation`, `phase-X`
- Link to remediation tasks

---

## Success Metrics

| Metric | Current | Target | Effort |
|--------|---------|--------|--------|
| **Docker-compose files** | 16 | 3 | LOW |
| **Env var SSOT** | 4 locations | 1 | MEDIUM |
| **App directory duplicates** | 2 pairs | 0 | QUICK |
| **Log function duplicates** | 24 | 1 | MEDIUM |
| **SSH orchestration location** | Terraform | Scripts | MEDIUM |
| **Documentation files** | 40+ status/phase docs | 5 active | LOW |
| **IaC coverage** | ~60% | ~90% | HIGH |
| **Test orchestration** | Scattered | Centralized | MEDIUM |

---

## Dependencies & Blockers

- [ ] Verify docker-compose variants don't have critical custom configs
- [ ] Backup existing .env files before consolidation
- [ ] Test SSH orchestration move doesn't break remote deployments
- [ ] Validate health checks work across all service types
- [ ] Ensure backward compatibility with existing deployments

---

**Next**: Start Phase 1 deletion of duplicate app directories
