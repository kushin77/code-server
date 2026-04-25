# Epic #1536 Phase 2 Batch 1 - Execution Checklist
## Framework Scripts Hardcoding Remediation

**Scheduled**: April 28-30, 2026  
**Batch**: 1 of 3  
**Target**: 20 framework scripts  
**Expected Commits**: 40-50  
**Status**: READY FOR EXECUTION

---

## Pre-Execution Verification

- [x] Network configuration SSOT created: `scripts/_common/_epic-1536-network-config.env`
- [x] Remediation framework ready: `scripts/ci/epic-1536-phase2-kubernetes-network-config.sh`
- [x] Batch 1 scripts identified: 20 files
- [x] Audit report generated with file list
- [x] Remediation procedures documented

---

## Batch 1 Target Files (20 scripts)

### Deployment Orchestration (8 files)
- [ ] `scripts/ops/deploy-p3-services-orchestrated.sh`
- [ ] `scripts/ops/validate-iac-deployment-readiness.sh`
- [ ] `scripts/ci/q3-phase4-kubernetes-init.sh`
- [ ] `scripts/ci/q3-phase4-helm-validation.sh`
- [ ] `scripts/ci/q3-phase4-phase1-prep-report.sh`
- [ ] `scripts/ci/q3-phase4-phase2-strategies.sh`
- [ ] `scripts/ci/q3-phase4-phase2-load-balancing.sh`
- [ ] `scripts/ci/q3-phase4-phase2-readiness.sh`

### Phase 3 & 4 Migration (2 files)
- [ ] `scripts/ci/q3-phase4-phase3-migration-strategy.sh`
- [ ] `scripts/ci/q3-phase4-phase4-production-cutover.sh`

### Validation & Monitoring (4 files)
- [ ] `scripts/ci/verify-p3-services-full-integration.sh`
- [ ] `scripts/ops/monitor-p3-services-health.sh`
- [ ] `scripts/ci/validate-iac-deployment-readiness.sh` (duplicate prevention)
- [ ] `scripts/ci/check-docker-compose-idempotency.sh`

### Hardcoding Audit Scripts (6 files)
- [ ] `scripts/ci/epic-1536-phase1-eliminate-hardcoding.sh`
- [ ] `scripts/ci/epic-1536-phase2-kubernetes-network-config.sh`
- [ ] `scripts/ci/validate-terraform-version-pins.sh`
- [ ] `scripts/ci/validate-config-ssot.sh`
- [ ] `scripts/ci/q3-phase4-epic-template.sh`
- [ ] `scripts/_common/validate-network-config.sh` (if exists)

---

## Remediation Pattern

### Pattern 1: Replace hardcoded IP with environment variable
```bash
# OLD:
VRRP_IP="192.168.168.100"

# NEW:
VRRP_IP="${ONPREM_VRRP_VIP}"
```

### Pattern 2: Replace hardcoded primary host with environment variable
```bash
# OLD:
PRIMARY_HOST="192.168.168.31"

# NEW:
PRIMARY_HOST="${ONPREM_PRIMARY_IP}"
```

### Pattern 3: Replace hardcoded domain with environment variable
```bash
# OLD:
API_DOMAIN="api.kushnir.cloud"

# NEW:
API_DOMAIN="${APP_API_DOMAIN}"
```

### Pattern 4: Add source statement for SSOT
```bash
# Add at top of script (after set -euo pipefail):
source "scripts/_common/_epic-1536-network-config.env" || {
    echo "Error: Network configuration SSOT not found"
    exit 1
}
```

---

## Execution Steps (Per File)

1. **Identify hardcoding violations** in file
   ```bash
   grep -nE "192\.168\.168\.|kushnir\.cloud" <file>
   ```

2. **Create backup branch** (if not already on feature branch)
   ```bash
   git checkout -b batch-1-<script-name>
   ```

3. **Apply remediation**
   - Replace hardcoded IPs with `${ONPREM_*}` variables
   - Replace hardcoded domains with `${DNS_ZONE}` or `${APP_*}` variables
   - Ensure `source "_epic-1536-network-config.env"` is present

4. **Validate syntax**
   ```bash
   bash -n <file>
   ```

5. **Test idempotency** (where applicable)
   ```bash
   bash <file> --dry-run
   bash <file> --dry-run  # Run twice, should produce identical output
   ```

6. **Commit with descriptive message**
   ```bash
   git commit -m "fix(epic-1536-phase2): Eliminate hardcoding in <script-name>
   
   - Replace hardcoded IPs with SSOT environment variables
   - Replace hardcoded domains with SSOT environment variables
   - Ensure source statement for network configuration SSOT
   - Syntax validated: bash -n pass
   - Idempotency verified: dry-run test pass
   
   Related: Epic #1536 Phase 2 Batch 1"
   ```

7. **Push commit to feature branch**
   ```bash
   git push origin batch-1-<script-name>
   ```

---

## Quality Checks (Before Merging Batch)

- [ ] All 20 files processed
- [ ] Syntax validation: 100% pass (bash -n)
- [ ] Idempotency tests: All pass (--dry-run)
- [ ] 40-50 commits generated
- [ ] All commits follow naming convention
- [ ] All commits reference Epic #1536
- [ ] No hardcoded IPs in final scripts
- [ ] No hardcoded domains in final scripts
- [ ] All source statements correct
- [ ] Network config SSOT values match environment expectations

---

## Success Criteria

✅ **Zero hardcoded IPs** in all 20 framework scripts  
✅ **Zero hardcoded domains** in all 20 framework scripts  
✅ **100% environment variable sourcing** for network config  
✅ **All scripts syntax-validated**  
✅ **40-50 commits** for complete audit trail  
✅ **Clean git history** with descriptive messages  

---

## Known Challenges & Mitigations

### Challenge 1: Comments mentioning IPs
**Solution**: Keep comments if they explain context, but remove hardcoded IP values
```bash
# GOOD: # Primary DNS server (uses SSOT variable)
DNS_SERVER="${ONPREM_PRIMARY_IP}"

# BAD: # Primary DNS server 192.168.168.31
DNS_SERVER="192.168.168.31"
```

### Challenge 2: Terraform/YAML files with hardcoding
**Solution**: These are deferred to Batch 2 (infrastructure files)

### Challenge 3: Scripts that need dynamic IP detection
**Solution**: Use network config SSOT as fallback, prioritize SSOT over dynamic detection

---

## Rollback Plan

If any commit causes issues:
```bash
git revert <commit-hash>
git push origin <branch>
```

All commits are atomic and reversible.

---

## Timeline

- **April 28 (Day 1)**: Files 1-5 (8 hours)
- **April 29 (Day 2)**: Files 6-15 (8 hours)
- **April 30 (Day 3)**: Files 16-20 + Quality checks (8 hours)

Total: 24 hours of execution time across 3 days

---

## GitHub Issue Updates

After Batch 1 completion:
```
Comment on Epic #1536:

## Phase 2 Batch 1: Complete ✅

Status: 20 framework scripts remediated
- P3 Services: 2 scripts ✓
- Q3 Phase 4: 8 scripts ✓
- Validation: 4 scripts ✓
- Hardcoding audit: 6 scripts ✓

Commits: 45 (estimated)
Files: 20/123 completed
Progress: 16.3% of total remediation

Quality: 100% syntax validated, 100% idempotency tested

Next: Batch 2 begins May 1 (infrastructure files)
```

---

**Batch 1 Ready**: April 28, 2026  
**Status**: APPROVED FOR EXECUTION  
**Authorization**: Ready to proceed
