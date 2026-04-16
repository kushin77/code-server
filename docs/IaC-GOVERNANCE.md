# IaC Governance Framework - Code-Server Enterprise
# On-Premises Infrastructure as Code Enforcement

**Status**: Production-Ready (Phase 7 Hardening)  
**Effective Date**: April 15, 2026  
**Authority**: Architecture Council + DevOps  
**Classification**: Production Standard  

---

## MISSION STATEMENT

Ensure all code-server enterprise infrastructure is:
- **Immutable**: Versioned, auditable, reproducible
- **Idempotent**: Apply twice = apply once (no unexpected changes)
- **Duplicate-Free**: Single source of truth for all configurations
- **Drift-Detectable**: Detect configuration divergence within 5 minutes
- **Rollback-Ready**: Restore to previous state in < 60 seconds

---

## 1. CORE PRINCIPLES

### Principle 1: Single Source of Truth
**Rule**: Each configuration element defined in exactly one place.

**Violations**:
- ❌ Same variable in .env AND docker-compose.yml
- ❌ Service definition in docker-compose.yml AND Terraform
- ❌ User allowlist in multiple files

**Enforcement**: 
- CI job `duplicate-detection` fails PR if violation detected
- MANIFEST.toml explicitly declares owner/source for each component

**Example - CORRECT**:
```toml
[config.allowed_users]
file = "allowed-emails.txt"
source_of_truth = true
managed_by = "terraform"
generation_script = "scripts/provision-new-user.sh"
```

### Principle 2: Immutable Artifacts
**Rule**: Production-deployed artifacts have fixed versions with checksums.

**Violations**:
- ❌ Using `image: ollama:latest` (no pinned version)
- ❌ `version = "1.x"` (floating version)
- ❌ Terraform without state backups

**Enforcement**:
```yaml
[services.ollama]
version = "0.1.8"         # ✅ Fixed version
image_sha = "sha256:..."  # ✅ Pinned by digest
```

**Rollback Procedure**:
```bash
git checkout v1.2.3       # Tag exact release
docker-compose down
docker-compose up -d      # Use previous version
```

### Principle 3: Idempotency
**Rule**: `terraform apply` (or `docker-compose up -d`) twice = same result as once.

**Violations**:
- ❌ Script creates files if not exist (second run = no-op) ✅ Actually OK
- ❌ Resource has `count = random()` (different each run)
- ❌ Manual configuration step outside IaC

**Enforcement**:
```bash
# In CI: scripts/governance/idempotency-validator.sh
terraform plan -out=tfplan1
terraform plan -out=tfplan2
# Assert: tfplan2 shows zero changes
```

**Validation**:
```bash
# Local test before PR
terraform apply
terraform apply  # Should output: No changes
```

### Principle 4: Zero Duplicates
**Rule**: No configuration defined in multiple files/layers.

**Configuration Duplication Matrix**:

| Config | File 1 | File 2 | File 3 | Owner |
|--------|--------|--------|--------|-------|
| Allowed Users | ❌ allowed-emails.txt | ❌ user-settings/ | ✅ terraform/users.tf | Terraform |
| Service Versions | ✅ docker-compose.yml | ❌ MANIFEST.toml (reference only) | ❌ .env | docker-compose.yml |
| Network Config | ✅ Terraform | ❌ docker-compose.yml | ❌ Caddyfile | Terraform |
| Environment Vars | ✅ .env | ❌ docker-compose.yml (ref only) | ❌ config/*.env | .env |

**Enforcement**:
- CI job `duplicate-detection` scans all files
- Errors if same element appears 2+ times across layers

### Principle 5: Drift Detectability
**Rule**: Configuration divergence detected within 5 minutes, alertable within 5 minutes.

**Drift Detection Workflow**:
```bash
# Every 5 minutes (via cron or monitoring)
scripts/governance/drift-detector.sh
# Compares: MANIFEST.toml baseline vs actual running state
# If drift > 5 minutes: alert ops, create issue
```

**Drift Types**:
1. **Parameter Drift**: Service image changed outside Terraform
   - Detection: `docker inspect` vs terraform state
2. **Network Drift**: Docker network modified outside Terraform
   - Detection: `docker network inspect` vs terraform state
3. **Config Drift**: Configuration file modified outside version control
   - Detection: `diff MANIFEST.toml.baseline <(running state)`

---

## 2. GOVERNANCE ENFORCEMENT

### 2.1 CI/CD Gates (Required for Merge)

All PRs touching infrastructure must pass:

```yaml
# .github/workflows/iac-governance.yml

1. ✅ duplicate-detection (fail if duplicates found)
2. ✅ terraform-validation (format + validate)
3. ✅ idempotency-validator (second apply = zero changes)
4. ✅ docker-compose-validation (no service duplicates)
5. ✅ manifest-validation (MANIFEST.toml syntax)
6. ✅ environment-consistency (no env var duplicates)
7. ✅ security-secrets-scan (no hardcoded secrets)
```

**Status**: 🔴 Required for merge = PR blocked until passing

### 2.2 Local Pre-Commit Checks

Before pushing, developer must run:

```bash
# Validate locally
bash scripts/governance/duplicate-detector.sh
bash scripts/governance/idempotency-validator.sh

# Format code
terraform fmt -recursive
docker-compose config

# Commit only if both pass
git add .
git commit -m "..."
```

### 2.3 Production Drift Monitoring

Running continuously (cron job):

```bash
# Every 5 minutes on production host
ssh akushnir@192.168.168.31 "bash scripts/governance/drift-detector.sh"

# Alert if drift > 5 minutes old
# Auto-create P1 issue if major drift detected
```

---

## 3. IMMUTABILITY STANDARDS

### 3.1 Version Pinning

**All production services must use fixed versions**:

```yaml
# ✅ CORRECT
services:
  postgres:
    image: postgres:15.2  # Fixed version
    
  caddy:
    image: caddy:2.8.4    # Fixed version

# ❌ WRONG
services:
  postgres:
    image: postgres:latest  # Latest - DON'T USE
    
  caddy:
    image: caddy:2.x       # Floating version - DON'T USE
```

### 3.2 State & Backup Requirements

**Terraform State**:
```bash
# State must be versioned and backed up
terraform state pull > terraform.state.backup  # Before apply
git add terraform.tfstate  # OR: remote backend with versioning
```

**Docker Images**:
```bash
# Tag and push images with version
docker tag code-server:latest code-server:4.115.0
docker push code-server:4.115.0  # Registry backup
```

**Configuration Files**:
```bash
git add docker-compose.yml Caddyfile .env
git commit -m "Version: baseline"
git tag v1.0.0
```

### 3.3 MANIFEST.toml as Audit Trail

**Every deployment updates MANIFEST.toml**:

```toml
[[deployment_history]]
date = "2026-04-15T20:00:00Z"
phase = "7-production"
commit = "2384dcfa"
status = "success"
manifest_version = "2.0.0"
validated_by = "github-actions"
duration_seconds = 180
```

---

## 4. IDEMPOTENCY REQUIREMENTS

### 4.1 Terraform Idempotency

**Requirement**: `terraform apply` twice = same state

**Test Procedure**:
```bash
# 1. First apply
terraform init
terraform apply  # Creates resources

# 2. Second apply (idempotency check)
terraform apply  # Should output: No changes

# CI validates: terraform plan | grep "no changes" || exit 1
```

**Common Violations**:
- ❌ Resource with `random()` or timestamp
- ❌ Local-exec without idempotent script
- ❌ Depends on external state not in terraform

### 4.2 Docker Compose Idempotency

**Requirement**: `docker-compose up -d` twice = containers not recreated

**Validation**:
```bash
docker-compose up -d 2>&1 | grep "is already running"  # = idempotent
docker-compose up -d 2>&1 | grep "Recreating"          # = NOT idempotent (fail)
```

### 4.3 Script Idempotency

**Requirement**: Running deployment scripts twice = same state

**Example - IDEMPOTENT**:
```bash
#!/bin/bash
# Check if already done
if [[ -f "/path/to/marker" ]]; then
  echo "Already initialized"
  exit 0
fi

# Do work
touch /path/to/marker
```

---

## 5. DUPLICATE DETECTION RULES

### 5.1 Environment Variables

**Violation**: Same variable in .env and config/_base-config.env

**Detection**:
```bash
comm -12 <(grep '^[A-Z_]' .env) <(grep '^[A-Z_]' config/_base-config.env)
# If output non-empty = FAIL
```

**Resolution**:
1. Choose one source (usually .env)
2. Remove from other file
3. Git commit

### 5.2 Service Definitions

**Violation**: Service defined in both docker-compose.yml and Terraform

**Example**:
```yaml
# ❌ docker-compose.yml
services:
  postgres:
    image: postgres:15

# ❌ terraform/main.tf
resource "docker_container" "postgres" {
  # Duplicate definition
}
```

**Resolution**: Use ONLY ONE:
- **Option A**: Manage in docker-compose.yml (simpler for on-prem)
- **Option B**: Manage in Terraform (preferred for IaC)

### 5.3 Configuration Sources

**Violation**: User allowlist in multiple files

**Correct Pattern**:
```
allowed-emails.txt (SOURCE OF TRUTH - Terraform-managed)
  ↓ (reference, not duplicate)
config/user-settings/
oauth2-proxy/.env (generated)
scripts/
```

**Detection Script**: `scripts/governance/duplicate-detector.sh`

---

## 6. ROLLBACK PROCEDURES

### 6.1 < 60 Second Rollback Target

**RTO (Recovery Time Objective)**:
- Docker Compose: < 15 seconds
- Terraform: < 45 seconds
- Data (PostgreSQL): < 30 seconds

**Rollback Procedure - Docker Compose**:

```bash
# 1. Identify last good tag
git tag -l | sort -V | tail -5  # Shows: v1.0.0 v1.0.1 v1.1.0 ...

# 2. Rollback
git checkout v1.0.1
docker-compose down
docker-compose up -d

# 3. Verify
docker-compose ps --filter 'status=running' | wc -l  # Should be 9+
# Total time: < 15 seconds
```

**Rollback Procedure - Terraform**:

```bash
# 1. Restore state backup
terraform state pull > current.state  # Save current
git checkout terraform.state.backup   # Restore previous

# 2. Re-apply
terraform apply  # Uses restored state

# 3. Verify
docker ps | wc -l  # Verify containers
# Total time: < 45 seconds
```

### 6.2 Tested Rollback

**Requirement**: Rollback procedure tested before Phase release

**Test Checklist**:
- [ ] Deploy version N
- [ ] Verify running
- [ ] Simulate rollback to version N-1
- [ ] Verify services come back
- [ ] Measure RTO
- [ ] Document results

**Stored In**: MANIFEST.toml rollback section

---

## 7. OPERATIONAL PROCEDURES

### 7.1 Adding New Configuration

**Step 1: Single Source of Truth**
- Choose authoritative location (terraform OR docker-compose OR config)
- Add to MANIFEST.toml with source reference

**Step 2: Check for Duplicates**
```bash
bash scripts/governance/duplicate-detector.sh
# Must pass (exit 0)
```

**Step 3: Idempotency Test**
```bash
bash scripts/governance/idempotency-validator.sh
# Must pass (exit 0)
```

**Step 4: Commit**
```bash
git add MANIFEST.toml terraform/ docker-compose.yml ...
git commit -m "IaC: Add <feature> - immutable, idempotent, duplicate-free"
git push
```

**Step 5: Merge**
- All CI gates must pass
- Approve PR
- Merge to main/phase-7-deployment

### 7.2 Resolving Drift

**If Drift Detected** (via monitoring):

```bash
# 1. Alert ops (already done by drift-detector)
# 2. Investigate
git log --oneline -5  # Recent changes
terraform plan       # Show differences

# 3. Remediate
# Option A: Fix in code and redeploy
# Option B: Restore previous version (rollback)

# 4. Verify
terraform plan       # Zero changes
docker-compose ps    # All healthy
```

### 7.3 Production Deployment Checklist

Before deploying to production:

- [ ] All IaC governance CI jobs passing
- [ ] Idempotency validated (second apply = zero changes)
- [ ] No duplicate configurations detected
- [ ] MANIFEST.toml updated with new versions
- [ ] Rollback procedure tested and documented
- [ ] All services healthchecks passing
- [ ] Drift detection running (cron job)
- [ ] Monitoring/alerting configured
- [ ] Change log updated
- [ ] Team notified

---

## 8. COMPLIANCE VERIFICATION

### 8.1 Audit Checklist

Run monthly to verify compliance:

```bash
# 1. Duplicates check
bash scripts/governance/duplicate-detector.sh

# 2. Versions pinned
grep -r "latest\|float" docker-compose.yml terraform/ && echo "FAIL" || echo "PASS"

# 3. MANIFEST.toml current
./scripts/governance/manifest-checker.sh

# 4. Rollback tested
git log | grep "Tested rollback" | head -1

# 5. Drift detection running
pgrep -f "drift-detector" || echo "Not running"
```

### 8.2 Compliance Report

Generated monthly, stored in `docs/governance-reports/`:

```markdown
## IaC Governance Compliance - April 2026

✅ Duplicate Detection: PASS (0 duplicates)
✅ Versions Pinned: PASS (all services pinned)
✅ Idempotency: PASS (terraform validated)
✅ Drift Detection: PASS (running, 0 drift detected)
✅ Rollback: PASS (tested April 15, RTO 12 seconds)

Audit Date: April 15, 2026
Verified By: devops@kushnir.cloud
Status: COMPLIANT
```

---

## 9. REFERENCES & RUNBOOKS

- [MANIFEST.toml](../MANIFEST.toml) - Resource inventory and versioning
- [CI Workflow](../.github/workflows/iac-governance.yml) - Automated enforcement
- [Duplicate Detector](../scripts/governance/duplicate-detector.sh) - Configuration audit
- [Idempotency Validator](../scripts/governance/idempotency-validator.sh) - Apply validation
- [Drift Detector](../scripts/governance/drift-detector.sh) - Real-time monitoring
- [Rollback Guide](./ROLLBACK-PROCEDURES.md) - Emergency restoration

---

## 10. ESCALATION & CONTACTS

**Governance Violations**:
- Minor (formatting): Auto-fix in CI, developer notified
- Major (duplicates): PR blocked, developer must fix
- Critical (rollback failed): P0 incident, escalate to @devops

**Governance Authority**:
- Immutability: @architecture-council
- Idempotency: @devops
- Duplicates: @devops
- Drift: @monitoring-team

---

**Policy Status**: ACTIVE & ENFORCED  
**Last Review**: April 15, 2026  
**Next Review**: May 15, 2026  
**Version**: 1.0.0 (Production)
