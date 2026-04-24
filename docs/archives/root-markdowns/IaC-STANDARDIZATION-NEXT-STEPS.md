# IaC Standardization - Next Steps for Operations Team

**Status**: Code and governance infrastructure complete on main branch. Ready for production execution.
**Date**: April 24, 2026
**Responsible Team**: Operations / DevOps

## What Was Completed (Development Phase ✅)

- `scripts/ci/standardize-image-digests.sh` — Automation to capture and pin image digests
- `scripts/ci/validate-iac-compliance.sh` — Governance validator for IaC principles
- SQL migrations verified idempotent (14 IF NOT EXISTS patterns)
- Docker-compose.yml versioning documented in git
- All changes merged to main branch (PR #1680)

## What Remains (Operations Phase ⏳)

### STEP 1: Execute Image Digest Standardization on Replica 1

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
git pull origin main
bash scripts/ci/standardize-image-digests.sh 192.168.168.31
```

**What this does**:
- Captures actual SHA256 digests from running containers
- Updates docker-compose.yml to pin all images to @sha256:HASH format
- Validates 100% coverage (all images pinned)
- Commits changes to git with conventional message

**Expected output**: 
```
✓ Captured 30 image digests
✓ Updated docker-compose.yml (77% → 100% coverage)
✓ Validated all 38 services have pinned images
✓ Committed: feat(iac): standardize image digests on replica-1
```

### STEP 2: Execute Image Digest Standardization on Replica 2

```bash
ssh akushnir@192.168.168.42
cd code-server-enterprise
git pull origin main
bash scripts/ci/standardize-image-digests.sh 192.168.168.42
```

### STEP 3: Validate IaC Compliance Across Both Replicas

On either replica:
```bash
bash scripts/ci/validate-iac-compliance.sh
```

**Expected output** (all ✓):
```
IaC COMPLIANCE REPORT
✓ Immutability: All images pinned to SHA256 digests
✓ Idempotency: 14 SQL migrations use IF NOT EXISTS
✓ Reproducibility: docker-compose.yml version-controlled
✓ Configuration: No hardcoded secrets in codebase
✓ Scripts: All use error handling (set -euo pipefail)
✓ 100% COMPLIANT
```

### STEP 4: Redeploy Both Replicas with Pinned Images

```bash
# Replica 1
ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose up -d --no-build'

# Replica 2 (parallel)
ssh akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose up -d --no-build'

# Wait for deployment
sleep 30

# Verify both are healthy
ssh akushnir@192.168.168.31 'docker-compose ps'
ssh akushnir@192.168.168.42 'docker-compose ps'
```

### STEP 5: Verify Failover Works with Pinned Images

Test failover to ensure state persistence and immutability:
```bash
# On replica 1: Verify all services healthy
ssh akushnir@192.168.168.31 'docker-compose ps | grep -c "Up"'

# Simulate replica 1 failure (optional - for testing only)
# ssh akushnir@192.168.168.31 'docker-compose stop caddy'
# Verify load balancer routes to replica 2
# Restore: ssh akushnir@192.168.168.31 'docker-compose up -d'
```

## Verification Checklist

- [ ] Both replicas deployed with pinned images
- [ ] All 38 services running (docker-compose ps shows healthy)
- [ ] IaC compliance check passes (100%)
- [ ] Failover tested and working
- [ ] Application accessible on ide.kushnir.cloud
- [ ] Session state persists across replica failover
- [ ] No error logs in Grafana/Loki

## Rollback Plan (If Needed)

If image pinning causes issues:
```bash
# Revert to previous version
git revert HEAD
docker-compose down
git pull
docker-compose up -d
```

## IaC Principles Now Enforced

1. **Immutability**: All container images pinned to exact SHA256 digests
   - Prevents "surprise" updates from image tags
   - Every deployment uses identical binaries
   - Detect tampering via digest mismatch

2. **Idempotency**: All SQL migrations and Docker restarts are safe to re-run
   - IF NOT EXISTS patterns prevent duplicate schema creation
   - Restart policies ensure service self-healing
   - No manual steps required for recovery

3. **Reproducibility**: All infrastructure version-controlled in git
   - Every configuration change tracked with commit history
   - Exact replica state recoverable from git history
   - Audit trail for compliance and debugging

## Success Criteria

✅ Task complete when:
- Both replicas have 100% image digest coverage
- IaC compliance validator returns all ✓
- Failover test passes
- Collab-9 Stage 2 canary proceeds as scheduled (April 26, 2026)

---

**Questions?** Check:
- [docker-compose.yml](docker-compose.yml) — Service definitions
- [scripts/ci/standardize-image-digests.sh](scripts/ci/standardize-image-digests.sh) — Implementation
- [scripts/ci/validate-iac-compliance.sh](scripts/ci/validate-iac-compliance.sh) — Validation
- Production Cluster Architecture (in memories/repo/)

**Timeline**: Execute ASAP after this document is reviewed. Must complete before Collab-9 Stage 2 canary on April 26, 2026.
