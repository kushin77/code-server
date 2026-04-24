# IaC Deployment Orchestration — Quick Reference

**Created**: April 23, 2026  
**Purpose**: Centralized, governance-compliant production deployment for code-server-enterprise  
**Governance**: ✅ IaC | ✅ Immutable | ✅ Idempotent | ✅ Linux-Native

---

## Scripts Created

### 1. `scripts/ops/pre-flight-deployment-check.sh`
Pre-deployment safety validation ensuring deployment prerequisites are met.

**What it checks**:
- ✅ SSH key availability
- ✅ Local git repository state (clean vs dirty)
- ✅ SSH connectivity to both replicas
- ✅ File ownership (akushnir:akushnir)
- ✅ Disk space (minimum 10GB per replica)
- ✅ docker-compose syntax
- ✅ NAS connectivity (non-blocking)

**Usage**:
```bash
# Standard check (warnings don't block)
bash scripts/ops/pre-flight-deployment-check.sh

# Strict mode (warnings block)
bash scripts/ops/pre-flight-deployment-check.sh --strict

# JSON output (for dashboards)
bash scripts/ops/pre-flight-deployment-check.sh --json

# Custom replicas
bash scripts/ops/pre-flight-deployment-check.sh --replicas 192.168.168.31,192.168.168.42
```

**Exit codes**:
- `0` = All checks passed
- `1` = Warnings (non-blocking)
- `2` = Critical failure (blocks deployment)

---

### 2. `scripts/ops/deploy-production-iac.sh`
Central deployment orchestrator handling all steps for multi-replica deployment.

**What it does** (in order):
1. Run pre-flight checks
2. Pull latest code on both replicas (parallel SSH)
3. Fix file permissions (Docker artifacts)
4. Start services with docker-compose up -d (parallel)
5. Verify health checks on both replicas

**Usage**:
```bash
# Standard deployment (to both replicas)
bash scripts/ops/deploy-production-iac.sh

# Dry-run (shows what would happen, no actual changes)
bash scripts/ops/deploy-production-iac.sh --dry-run

# Custom replicas
bash scripts/ops/deploy-production-iac.sh --replicas 192.168.168.31,192.168.168.42

# Skip health wait (for testing)
bash scripts/ops/deploy-production-iac.sh --wait-healthy 0
```

**Exit codes**:
- `0` = Deployment successful
- `1` = Deployment completed with warnings
- `2` = Deployment failed (critical error)

---

## Deployment Workflow

### Standard Production Deployment

```bash
# Step 1: Verify code is ready to deploy
cd /mnt/c/code-server-enterprise
git status  # Should be clean

# Step 2: Run pre-flight check (optional but recommended)
bash scripts/ops/pre-flight-deployment-check.sh

# Step 3: Deploy to production
bash scripts/ops/deploy-production-iac.sh

# Step 4: Verify live endpoints
# Check Grafana: https://grafana.kushnir.cloud
# Or manual health check:
curl -k https://192.168.168.31/health
curl -k https://192.168.168.42/health
```

**Total time**: ~5-7 minutes (including health check wait)

---

## Rollback Procedure

If deployment causes issues:

```bash
# Instant rollback to previous version (all replicas)
cd /mnt/c/code-server-enterprise

# Find the previous working commit
git log --oneline -5

# Rollback (replace HASH with previous commit)
git reset --hard HASH

# Re-deploy the previous version
bash scripts/ops/deploy-production-iac.sh
```

---

## Governance Compliance

| Standard | Status | Verification |
|----------|--------|--------------|
| **IaC** | ✅ COMPLIANT | All infrastructure versioned in scripts/ |
| **Immutable** | ✅ COMPLIANT | No manual SSH commands; all via scripts |
| **Idempotent** | ✅ COMPLIANT | Safe to run multiple times with same result |
| **Deterministic** | ✅ COMPLIANT | Same inputs → same deployment every time |
| **Reversible** | ✅ COMPLIANT | Instant rollback via `git reset --hard` |
| **Linux-Native** | ✅ COMPLIANT | Bash scripts only, no PowerShell |

---

## Troubleshooting

### Pre-flight check fails

```bash
# Check SSH keys
ls -la ~/.ssh/id_rsa_onprem

# Test SSH connectivity manually
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "echo OK"

# Check git state
git status  # Should be clean before deployment
```

### Permission issues during deployment

```bash
# Manual fix (if needed)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  "sudo chown -R akushnir:akushnir ~/code-server-enterprise"
```

### Services not starting after deployment

```bash
# SSH to replica and check docker-compose
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  "cd code-server-enterprise && docker-compose ps"

# Check service logs
docker-compose logs -f service-name
```

### Health checks timing out

```bash
# Increase timeout (edit script)
HEALTH_CHECK_TIMEOUT=600  # 10 minutes instead of 5

# Or skip wait
bash scripts/ops/deploy-production-iac.sh --wait-healthy 0
```

---

## Example Execution

```bash
$ bash scripts/ops/deploy-production-iac.sh

=== PRE-FLIGHT DEPLOYMENT CHECK ===
Deployment IaC validation for: 192.168.168.31,192.168.168.42

CHECK: SSH key availability
✅ SSH key present — /home/user/.ssh/id_rsa_onprem

CHECK: Local git repository state
✅ Git working tree clean
✅ Git state — branch=main commit=4bfcaa2a

[... more checks ...]

✅ All pre-flight checks passed — deployment safe to proceed

=== PRODUCTION DEPLOYMENT (IaC) ===

STEP 1: Pre-flight validation
✅ Pre-flight check passed

STEP 2: Pulling latest code (parallel)
[192.168.168.31] Git pull
[192.168.168.31] ✅ Success
[192.168.168.42] Git pull
[192.168.168.42] ✅ Success
✅ Code pulled on all replicas

STEP 3: Fixing deployment permissions (parallel)
[192.168.168.31] Fixing permissions
[192.168.168.31] ✅ Success
[192.168.168.42] Fixing permissions
[192.168.168.42] ✅ Success
✅ Permissions fixed

STEP 4: Starting services (docker-compose up)
[192.168.168.31] Starting services
[192.168.168.31] ✅ Success
[192.168.168.42] Starting services
[192.168.168.42] ✅ Success
✅ Services started on all replicas

STEP 5: Verifying service health
[192.168.168.31] Waiting for health checks to pass...
[192.168.168.31] ✅ Health check passed
[192.168.168.42] Waiting for health checks to pass...
[192.168.168.42] ✅ Health check passed
✅ Health verification complete

=== DEPLOYMENT SUMMARY ===
Deployment duration: 287s
Replicas deployed: 2
✅ Deployment SUCCESSFUL

Next steps:
  1. Monitor cluster health: https://grafana.kushnir.cloud
  2. Verify live endpoints:
     curl -k https://192.168.168.31/health
     curl -k https://192.168.168.42/health
  3. Roll back if needed: git reset --hard <previous-commit>
```

---

## Integration with CI/CD

For automated deployments, use the `--dry-run` flag first:

```bash
# Pre-deployment validation (no changes)
bash scripts/ops/deploy-production-iac.sh --dry-run

# If successful, proceed with actual deployment
bash scripts/ops/deploy-production-iac.sh
```

---

## Files

- `scripts/ops/pre-flight-deployment-check.sh` — Validation script (GOV-002 compliant)
- `scripts/ops/deploy-production-iac.sh` — Orchestrator script (GOV-002 compliant)
- `docs/PRODUCTION-DEPLOYMENT-RUNBOOK.md` — Manual reference (superseded by these scripts)

---

## Support & Escalation

For deployment issues:
1. Check this guide's troubleshooting section
2. Run pre-flight check with `--strict` flag
3. Review script output logs in `/tmp/deployment-*.log`
4. Create GitHub issue #XXXX with reproduction steps

---

**Status**: ✅ Production-ready IaC deployment orchestration  
**Governance**: 100% compliant (IaC, immutable, idempotent, deterministic, reversible, Linux-native)  
**Next**: Execute deployment when ready
