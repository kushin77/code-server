# Infrastructure Lifecycle Control - Configuration SSOT

**Last Updated:** 2026-04-25T00:00:00Z
**Status:** Production Ready
**P3-1531 Phase 4 Deliverable**

## Single Source of Truth (SSOT) - Configuration Registry

All infrastructure configuration must be version-controlled and environment-variable driven. No manual configuration changes allowed in production.

### Environment Variable Registry

#### Domain Configuration
```bash
APEX_DOMAIN=kushnir.cloud              # Primary domain
IDE_DOMAIN=ide.kushnir.cloud           # IDE endpoint
AUTH_DOMAIN=auth.kushnir.cloud         # Authentication endpoint
API_DOMAIN=api.kushnir.cloud           # API endpoint
REGISTRY_DOMAIN=registry.kushnir.cloud # Container registry domain
```

#### Infrastructure Hosts
```bash
PRIMARY_HOST=192.168.168.31            # Primary on-prem host
REPLICA_HOST=192.168.168.42            # Replica on-prem host
NAS_HOST=192.168.168.56                # NAS host (eiq-nas)
NAS_MOUNT_PATH=/mnt/nas                # NAS mount point
NAS_DATA_PATH=/nas/persistent/paperclip/data
```

#### Service Versions (Pinned)
```bash
TERRAFORM_VERSION=1.5.7
DOCKER_ENGINE_VERSION=24.0.7
POSTGRES_VERSION=15.4
REDIS_VERSION=7.2.1
CADDY_VERSION=2.7.6
```

#### Health Check Configuration
```bash
HEALTH_CHECK_ENDPOINT=http://localhost:3100/health
HEALTH_CHECK_TIMEOUT=300                # 5 minutes
HEALTH_CHECK_INTERVAL=60                # Check every 60 seconds
MAX_HEALTH_CHECK_RETRIES=10
```

#### Drift Detection Configuration
```bash
DRIFT_CHECK_SCHEDULE="0 2 * * *"      # Daily at 2 AM UTC
DRIFT_ALERT_THRESHOLD=1                 # Create issue if >1 divergence
DRIFT_AUTO_REMEDIATE=false              # Manual remediation required
```

### Infrastructure Files - Version Pinning

#### docker-compose.yml Requirements
- All images must specify explicit digests (no `:latest` tags)
- Pattern: `image: registry/service:v1.2.3@sha256:abc123...`
- All services must have `restart_policy: unless-stopped`
- All services must have `healthcheck` defined
- All volumes must use host mounts with backup strategy

#### terraform/variables.tf Requirements
- All provider versions pinned (no `~>` ranges)
- All module sources version-pinned
- Required version set (e.g., `>= 1.5, < 2.0`)
- All variables documented with validation

#### Caddyfile Requirements
- All domain references use `${APEX_DOMAIN}` variables
- All paths templated, no hardcoded paths
- TLS certificate paths managed by env vars
- Auto-renewal configured

### Configuration Management Hierarchy

1. **Environment Variables** (Highest Priority)
   - Sourced from `.env` file or GSM
   - Injected at container startup
   - Used for all domain, version, and endpoint references

2. **Infrastructure Code** (Git)
   - terraform/
   - docker-compose.yml
   - Caddyfile
   - All version-controlled and auditable

3. **Runtime Overrides** (Lowest Priority, Discouraged)
   - Only for emergencies
   - Must be documented and approved
   - Should be followed by code update

### Validation Rules

✅ **PASS CRITERIA:**
- All domain references use env vars (no hardcoded `kushnir.cloud`)
- All image tags pinned to specific versions or digests
- All Terraform provider versions bounded (no `~>`)
- All infrastructure files in version control
- No manual SSH configuration changes
- All changes reviewed via PR before merge

❌ **FAIL CRITERIA:**
- Any hardcoded domain strings found
- Floating image tags (`:latest`, `:main`)
- Unbounded version ranges (`>=` without upper bound)
- Untracked infrastructure changes
- Direct production pushes without PR
- Uncommitted manual configuration

### Enforcement Points

1. **Pre-Commit Hook** (`scripts/ci/check-github-api-governance.sh`)
   - Validates no hardcoded credentials
   - Checks for floating tags
   - Ensures PR references

2. **CI Pipeline** (`.github/workflows/gitops-drift-detection.yml`)
   - Daily drift detection
   - Idempotency validation
   - Domain variability checks

3. **Runtime Reconciliation** (`scripts/ci/gitops-drift-detector.sh`)
   - Detects divergence between code and running state
   - Creates GitHub issues on drift
   - Enables manual or auto remediation

### Configuration Change Process

1. **Identify needed change**
2. **Update version-controlled files** (terraform, docker-compose.yml, Caddyfile)
3. **Create PR with detailed justification**
4. **Run validation:** `scripts/ci/check-docker-compose-idempotency.sh --report`
5. **Merge to main**
6. **GitOps workflow auto-applies** (via CI)
7. **Health checks verify** (post-deployment)
8. **Monitor** for 24 hours

### Rollback Procedure

Automatic rollback triggered on:
- Health check failure post-deploy
- Drift exceeds threshold
- Manual trigger via `scripts/ops/automated-rollback.sh`

```bash
# Dry-run rollback
scripts/ops/automated-rollback.sh compose --dry-run

# Execute rollback with health check
scripts/ops/automated-rollback.sh compose --health-check
```

### Audit & Compliance

- All changes tracked in Git with commit history
- Rollback history logged to `artifacts/rollback-history.json`
- Drift reports generated daily: `artifacts/drift-report.json`
- Health check reports: `artifacts/health-check-report.json`
- All accessible via GitHub Actions artifacts

### Current Status

✅ Phase 1: Governance Scripts Implemented (domain-variability-enforcer, idempotency-checker, drift-detector, version-pins-validator)
✅ Phase 2: Automated Rollback & Health Checks (automated-rollback.sh, health-check-post-deploy.sh)
✅ Phase 3: GitOps CI Workflow (gitops-drift-detection.yml, setup-gitops-workflow.sh)
✅ Phase 4: Configuration SSOT (this document)
✅ Phase 5: Full Redeploy Test & SLA Verification (full-redeploy-test.sh, deployment validation)