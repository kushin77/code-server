# Redundancy Analysis - Quick Reference
**Date**: April 29, 2026 | **Full Analysis**: [COMPREHENSIVE_REDUNDANCY_ANALYSIS.md](COMPREHENSIVE_REDUNDANCY_ANALYSIS.md)

---

## 1. DOCKER COMPOSE CONSOLIDATION

### Files to DELETE (24 files - 70% of total)
```bash
# Remove immediately (safe to delete):
rm -f docker-compose.prod.yml
rm -f docker-compose.production.yml
rm -f docker-compose.production-*.yml
rm -f docker-compose.enterprise-simple.yml
rm -f docker-compose.full-stack.yml
rm -f docker-compose.cluster.yml
rm -f docker-compose.minimal-deploy.yml
rm -f docker-compose.infrastructure-v2.yml
rm -f docker-compose.infrastructure-v3.yml
rm -f docker-compose.infrastructure-only.yml
rm -f docker-compose.edge-agent.yml
rm -f docker-compose.ai.yml
rm -f docker-compose.phase-11-*.yml
rm -f docker-compose.phase-13-*.yml
rm -f docker-compose.phase-14-*.yml
# Archive to: docs/archive/docker-compose-variants/
```

### Files to KEEP (4 files - 10% of total)
1. **docker-compose.yml** - Main production stack
2. **docker-compose.observability.yml** - Optional observability overlay
3. **docker-compose.override.yml** - Development overrides
4. **docker-compose.infrastructure-core.yml** - Minimal core infrastructure

### Merge Instructions
1. Extract `gitlab`, `code-server-ide`, `gitlab-runner` from `docker-compose.enterprise.yml` → append to `docker-compose.yml`
2. Extract `redpanda` specialization from `docker-compose.redpanda.yml` → document for reference only
3. Verify all services from `docker-compose.phase-13-apps.yml` → already in `docker-compose.yml`

---

## 2. CRITICAL CONFIGURATION DRIFT FIXES

### Fix #1: Redis Password (IMMEDIATE)
**Files affected**: 
- [.env.production](.env.production) (line 21)
- [docker-compose.yml](docker-compose.yml) (line 1177)
- [terraform/environments/private/modules/stack/containers-data.tf](terraform/environments/private/modules/stack/containers-data.tf) (line 68)

**Action**:
```bash
# Step 1: Set password in .env.production
echo 'REDIS_PASSWORD=your_secure_password' >> .env.production

# Step 2: Update docker-compose.yml redis section
# Change line 1185 from: command: redis-server
# To: command: redis-server --requirepass $REDIS_PASSWORD

# Step 3: Verify terraform uses same password
grep -n "redis_password" terraform/environments/private/modules/stack/containers-data.tf
```

---

### Fix #2: PostgreSQL Volume Mount (HIGH PRIORITY)
**Files affected**:
- [docker-compose.yml](docker-compose.yml) (line 1135-1155)
- [terraform/environments/private/modules/stack/containers-init.tf](terraform/environments/private/modules/stack/containers-init.tf) (line 206)
- [docker-compose.production.yml](docker-compose.production.yml) (line 25+)

**Current Conflict**:
```
docker-compose.yml:           /var/lib/postgresql/data
docker-compose.production.yml: /var/lib/postgresql/data/pgdata
terraform init script:         /var/lib/postgresql/data
```

**Action**:
```bash
# Determine correct path
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  docker exec code-server-postgres ls -la /var/lib/postgresql/
  # Check what path data actually sits in
"

# Once determined, update all three files to use same path
```

---

### Fix #3: OAuth2 Proxy Missing from Compose (HIGH)
**Issue**: Defined in [terraform/environments/private/modules/stack/containers-infrastructure.tf](terraform/environments/private/modules/stack/containers-infrastructure.tf) (line 69) but NOT in any docker-compose file

**Action**:
```bash
# Extract oauth2_proxy from terraform
# Add to docker-compose.yml before caddy service
# See terraform file for correct environment variables and configuration
```

---

## 3. ENVIRONMENT FILE CONSOLIDATION

### Current State (PROBLEMATIC)
| File | Status | Content |
|---|---|---|
| [.env.infrastructure](.env.infrastructure) | EXISTS | Host IPs, API endpoints, kafka config |
| [.env.production](.env.production) | EXISTS | Credentials, database config, domain |
| [.env.cluster](.env.cluster) | MISSING | Referenced but doesn't exist |
| [.env.deployment](.env.deployment) | MISSING | Referenced in scripts but doesn't exist |
| [.env.schema.json](.env.schema.json) | EXISTS | Incomplete schema |

### Consolidation Plan
**Create unified hierarchy**:
```
.env.schema.json (master schema)
├── .env (base - safe to commit)
├── .env.production (overrides for prod)
├── .env.development (overrides for dev)
├── .env.test (overrides for test)
└── .env.local (local-only, gitignored)
```

**Action**:
```bash
# Step 1: Document all variables from both files
# Step 2: Expand .env.schema.json with all variables
# Step 3: Create base .env with sensible defaults
# Step 4: Create .env.production with prod-specific values
```

---

## 4. SCRIPT CONSOLIDATION OPPORTUNITIES

### Remove Redundant Phase Validators (100+ files)
**Pattern**: `scripts/phase*/validate-phase*.sh` (all identical structure)

```bash
# Count them
find scripts/phase* -name "validate-phase*.sh" | wc -l
# Result: ~100+ files, 95%+ code duplication

# Consolidation:
# Create: scripts/validate-phase.sh --phase N
# Remove: scripts/phase*/validate-phase*.sh
```

**Benefit**: 100+ files → 1 script = 99% code reduction

---

### Remove Redundant Extension Setups (8 files)
**Location**: `scripts/extensions/setup-*.sh`

```bash
# All follow identical pattern: download → validate → configure → restart
# Consolidate to: scripts/extensions/setup.sh --type X

# Current files (consolidate):
scripts/extensions/setup-local-folder-access.sh
scripts/extensions/setup-shared-clipboard.sh
scripts/extensions/setup-advanced-team-coordination.sh
scripts/extensions/setup-statusbar-tiles.sh
scripts/extensions/setup-github-oauth.sh
scripts/extensions/setup-kc-ide-branding.sh
scripts/extensions/setup-copilot-autonomy.sh
scripts/extensions/setup-team-communication.sh

# New approach: scripts/extensions/setup.sh --type X
```

---

### Create Shared Script Library
**Location**: `scripts/lib/`

**Extract these functions**:
1. `docker-compose-utils.sh` - docker-compose check/start/stop logic (used in 5+ scripts)
2. `ssh-orchestration.sh` - SSH commands to hosts (used in 15+ scripts)
3. `health-checks.sh` - Service health verification (used in 20+ scripts)
4. `config-loader.sh` - Environment file sourcing (used in 30+ scripts)

**Example usage after consolidation**:
```bash
source scripts/lib/docker-compose-utils.sh
source scripts/lib/ssh-orchestration.sh

# Instead of duplicating logic in each script
check_docker_compose_config "docker-compose.yml"
restart_service_on_host "primary" "code-server-postgres"
wait_for_health "http://localhost:3000/health"
```

---

## 5. DOCUMENTATION CONSOLIDATION

### Redundant Documents to Archive (120+ files)
**Categories**:
- Phase completions (40+ files) - Archive to: `docs/archive/phases/`
- Session summaries (15+ files) - Archive to: `docs/archive/sessions/`
- Status reports (25+ files) - Consolidate to: `CANONICAL_PLATFORM_STATUS.md`

### Create 8 Canonical Documents
1. **CANONICAL_PLATFORM_STATUS.md** ← Consolidate 25 status files
2. **DEPLOYMENT_GUIDE.md** ← Consolidate 20 deployment/execution docs
3. **OPERATIONS_RUNBOOK.md** ← Keep [OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md)
4. **ARCHITECTURE_REFERENCE.md** ← Create new (document actual design)
5. **CONFIGURATION_REFERENCE.md** ← Document all .env variables
6. **TROUBLESHOOTING_GUIDE.md** ← Consolidate GAP_ANALYSIS findings
7. **PHASE_ARCHIVE.md** ← Consolidate historical phase docs (read-only)
8. **INTEGRATION_REFERENCE.md** ← Keep [EXTERNAL_INTEGRATIONS_MAP.md](EXTERNAL_INTEGRATIONS_MAP.md)

### Outdated Documents Needing Update
| Document | Current Claim | Actual Status | Fix |
|---|---|---|---|
| [PHASE-06-WP-6.2-VERIFICATION.txt](PHASE-06-WP-6.2-VERIFICATION.txt) | "All services healthy" | [GAP_ANALYSIS_CLUSTER_2026-04-29.md](GAP_ANALYSIS_CLUSTER_2026-04-29.md) shows failures | ARCHIVE |
| [CLUSTER_DEPLOYMENT_COMPLETE.md](CLUSTER_DEPLOYMENT_COMPLETE.md) | "25 Services Running" | GAP_ANALYSIS shows 18 healthy | UPDATE |
| [FINAL_DEPLOYMENT_STATUS.md](FINAL_DEPLOYMENT_STATUS.md) | "NO blockers" | GAP_ANALYSIS lists 8 failing services | UPDATE |

---

## 6. APP CODE CONSOLIDATION

### Duplicate Auth Implementations (4 files, 80% similar)
**Location**: Various apps

**Consolidate to**: `apps/_shared/auth.py`

**Currently duplicated in**:
- apps/auth-server/auth.py (main impl)
- apps/control-plane/auth_middleware.py
- apps/prompt-gateway/auth_check.py
- apps/edge-agent/auth_validator.py

**Action**: Extract common logic to shared, import in apps

---

### Duplicate Health Check Implementations (15 files, 95% similar)
**Location**: Each app directory

**Consolidate to**: `apps/_shared/health_check.py`

**Benefit**: Single endpoint pattern, consistent response format

---

### Duplicate Storage Clients (8 files, 85% similar)
**Location**: Various apps needing S3/MinIO access

**Consolidate to**: `apps/_shared/storage.py`

**Currently duplicated in**:
- apps/multimodal-ai/ (S3 client)
- apps/paperclip/ (MinIO client)
- apps/env-provisioner/ (storage ops)
- And 5 others...

---

## 7. QUICK WINS (Implement This Week)

### Quick Win #1: Remove 24 Docker Compose Files (2 hours)
```bash
# See section 1.0 for list of files to delete
# Test that docker-compose config still works after removal
docker-compose config --quiet && echo "✓ Still valid"
```

### Quick Win #2: Create Shared Script Library (4 hours)
```bash
mkdir -p scripts/lib
# Create scripts/lib/docker-compose-utils.sh
# Create scripts/lib/ssh-orchestration.sh
# Create scripts/lib/health-checks.sh
# Create scripts/lib/config-loader.sh
# Update 10 existing scripts to use library
```

### Quick Win #3: Fix Redis Password (30 minutes)
```bash
# Add password to .env.production
# Update docker-compose.yml
# Update terraform container
# Redeploy and verify replication
```

### Quick Win #4: Document Configuration (1 hour)
```bash
# Expand .env.schema.json with all variables
# Create CONFIGURATION_REFERENCE.md
# Map all variables across files
```

---

## 8. RISK MITIGATION

### Before Making Changes
```bash
# Create backup
git tag backup/pre-consolidation-$(date +%s)
tar czf backup-docker-compose-files.tar.gz docker-compose*.yml
tar czf backup-scripts.tar.gz scripts/
tar czf backup-docs.tar.gz *.md

# Create feature branch
git checkout -b consolidation/reduce-redundancy
```

### Verify After Each Change
```bash
# Docker compose validation
docker-compose config --quiet

# Script syntax check
bash -n scripts/*/validate*.sh

# Documentation links
markdown-link-check *.md

# No service broken
docker-compose up -d && docker-compose ps
```

### Rollback if Needed
```bash
# Delete branch
git reset --hard origin/main

# Restore files
tar xzf backup-docker-compose-files.tar.gz
```

---

## 9. VALIDATION CHECKLIST

- [ ] All 34 docker-compose files inventoried
- [ ] Terraform and compose service definitions compared
- [ ] All environment variables documented
- [ ] 100+ phase validation scripts identified for consolidation
- [ ] 130+ documentation files categorized
- [ ] App code duplication measured
- [ ] Configuration drift documented
- [ ] Quick wins prioritized
- [ ] Risk mitigation plan created
- [ ] Consolidation roadmap approved

---

**Next Steps**:
1. Review [COMPREHENSIVE_REDUNDANCY_ANALYSIS.md](COMPREHENSIVE_REDUNDANCY_ANALYSIS.md) for full details
2. Execute Quick Wins in order (7 hours total)
3. Schedule Phase 1-3 remediation (27 hours total)
4. Commit changes with detailed commit messages

**Status**: ✅ Analysis Complete | 🔄 Ready for Implementation
