# Terraform Consolidation Roadmap
## Path to Governance Compliance (April 14-28, 2026)

**Current State**: 11 phase-numbered terraform files exist  
**Target State**: All phase logic in main.tf, locals.tf, or modules/ only  
**Governance Enforcement Date**: April 28, 2026  
**Status**: 🟡 IN PROGRESS (Phase 26-A executing immediately)

---

## Timeline

### Week 1: April 14-21 (Soft Launch, Feedback Mode)
- ✅ Phase 25-B deployment (PostgreSQL optimization)
- ✅ Phase 26-A deployed to production (rate limiting)
- ⏳ April 21: Team governance training (soft launch begins)
- ⏳ CI/CD checks enabled but non-blocking (feedback only)

### Week 2: April 21-28 (Consolidation & Testing)
- ⏳ April 22-24: Consolidate Phase 22-B files (4 files)
- ⏳ April 24-25: Consolidate Phase 26-A/B/C/D files (4 files)
- ⏳ April 25-26: Comprehensive testing on staging
- ⏳ April 27: Final QA and verification
- ⏳ April 28: Hard enforcement enabled

### Week 3: April 28+ (Enforcement & Graduation)
- ⏳ April 28: Branch protection rules activated
- ⏳ April 28: Hard enforcement (CI checks block PRs)
- ⏳ April 30: Cleanup and archiving of disabled files
- ⏳ May 1: Phase 26 developer ecosystem launch

---

## Files to Consolidate

### Tier 1: Phase 22-B Advanced Networking (4 files)
These implement service mesh, CDN, caching, and BGP routing.

**Files**:
- `terraform/phase-22-b-istio.tf` (Istio service mesh configuration)
- `terraform/phase-22-b-cdn.tf` (CDN, edge caching)
- `terraform/phase-22-b-bgp.tf` (BGP routing, AS numbers)
- `terraform/22b-service-mesh.tf` (Duplicate? Verify first)

**Consolidation Target**: Create `terraform/modules/advanced-networking/` module  
**Status**: Ready for consolidation during Week 2 (April 22-24)

### Tier 2: Phase 26 Developer Ecosystem (4 files)
These implement rate limiting, analytics, organizations, webhooks.

**Files**:
- `terraform/phase-26a-rate-limiting.tf` (API rate limiting)
- `terraform/phase-26b-analytics.tf` (Event tracking, analytics)
- `terraform/phase-26c-organizations.tf` (Multi-tenant orgs)
- `terraform/phase-26d-webhooks.tf` (Webhook delivery system)

**Consolidation Target**: Merge into `terraform/locals.tf` + new `terraform/modules/developer-ecosystem/`  
**Status**: Already added to locals.tf (April 14), ready for additional consolidation (Week 2, April 24-25)

### Tier 3: Phase 22 GPU & Kubernetes (3 files)
These implement GPU infrastructure and Kubernetes orchestration.

**Files**:
- `terraform/phase-22-on-prem-gpu-infrastructure.tf` (GPU nodes, drivers, CUDA)
- `terraform/phase-22-on-prem-kubernetes.tf` (K8s cluster, kubeadm, containerd)
- `terraform/phase-22-e-compliance-automation.tf` (Compliance, audit logging)

**Consolidation Target**: Create `terraform/modules/on-prem-infrastructure/` module  
**Status**: Ready for consolidation during Week 2 (April 25-26)

---

## Consolidation Strategy

### Phase 1: No-Op Phase (Immediate - Week 1)
**Goal**: Get Phase 26-A deployed, enable governance checks (non-blocking)

**Actions**:
1. ✅ Add Phase 26 config to `terraform/locals.tf` (done)
2. ⏳ Deploy Phase 26-A to production (in progress)
3. ⏳ Create CI checks for phase-numbered files (feedback only, non-blocking)
4. ⏳ Team governance training April 21 (soft-launch begins)

**Why**: Prevents blocking production deployment. Gets feedback from team before hard enforcement.

### Phase 2: Module-Based Consolidation (Week 2, April 22-26)
**Goal**: Migrate phase-numbered files to modules/

**For Phase 22-B Advanced Networking**:
```
terraform/modules/advanced-networking/
  ├── main.tf (networking, service mesh, CDN, BGP)
  ├── variables.tf
  ├── outputs.tf
  ├── locals.tf (configuration)

terraform/main.tf (updated to reference module)
  ├── module "advanced_networking" {
  │   source = "./modules/advanced-networking"
```

**For Phase 26 Developer Ecosystem**:
```
terraform/modules/developer-ecosystem/
  ├── main.tf (rate limiting, analytics, orgs, webhooks)
  ├── variables.tf
  ├── outputs.tf
```

**Result**: Single terraform/main.tf imports modules, no phase-numbered files in root

### Phase 3: Hard Enforcement (April 28+)
**Goal**: Block new phase-numbered files, clean up old ones

**Actions**:
1. Enable CI/CD check that blocks phase-*.tf files
2. Archive all phase-numbered files to `terraform/.archive/`
3. Disable old files: `terraform/phase-*.tf.disabled` (for reference)
4. Document in `terraform/CONSOLIDATION-COMPLETE.md`

---

## Consolidation Checklist (Per File)

### Before Moving File to Module:
- [ ] Review current usage: grep -r "phase-22-b-istio" (see what imports it)
- [ ] Identify all variables/outputs it exports
- [ ] Check for cross-phase dependencies in terraform/
- [ ] Verify in production for 24 hours (ensure no emergency rollbacks)

### During Migration:
- [ ] Create new module directory `terraform/modules/{name}/`
- [ ] Copy .tf file content to module/main.tf
- [ ] Extract variables to module/variables.tf
- [ ] Update terraform/main.tf to reference new module
- [ ] Remove old phase-*.tf file (backup in .archive/)
- [ ] Run `terraform plan` and verify no changes

### After Migration:
- [ ] Test on staging environment
- [ ] Deploy to production
- [ ] Monitor for 24 hours
- [ ] Document in CONSOLIDATION-COMPLETE.md
- [ ] Mark old file as .disabled (keep for 30 days, then delete)

---

## Governance Enforcement Details

### CI/CD Check: phase-files-forbidden
**Enabled**: April 21 (soft-launch, non-blocking)  
**Hard Enforcement**: April 28 (blocks merge)

**Logic**:
```bash
# REJECT if match:
[[ $CHANGED_FILE =~ phase-[0-9]+-.*\.tf$ ]] && EXIT=1

# ALLOW if:
[[ $CHANGED_FILE == terraform/modules/*/main.tf ]] && EXIT=0
[[ $CHANGED_FILE == docs/phases/* ]] && EXIT=0
```

### Branch Protection Rule
**Enabled**: April 17 (requires GitHub issue #274)

**Rule**: 
- Require `terraform-validate` check to pass
- Require `code-review` approval (1 senior engineer)
- Require `governance-compliance` check to pass (April 21+)
- Dismiss stale reviews

---

## Success Metrics

| Metric | Current | Target | Timeline |
|--------|---------|--------|----------|
| Phase-numbered files | 11 | 0 | April 28 |
| Files in modules/ | 2 | 8+ | April 28 |
| terraform/main.tf complexity | High | Low (imports modules) | April 28 |
| CI check pass rate | N/A | >95% | April 28 |
| Consolidation tests | 0 | 20+ | April 28 |

---

## Risk Mitigation

**Risk**: Consolidation breaks production deployment  
**Mitigation**: Conservative schedule, test on staging first, canary deploy

**Risk**: Team resistance to phase-file removal  
**Mitigation**: Governance training (April 21), soft-launch period (April 21-28), clear documentation

**Risk**: Missed consolidation deadline  
**Mitigation**: Weekly progress tracking, daily standups April 22-28

---

## Next Steps (Immediate)

1. ✅ Add Phase 26 config to locals.tf (done)
2. ⏳ **Deploy Phase 26-A to production NOW** (in progress)
3. ⏳ Create CI/CD check for phase-files (non-blocking)
4. ⏳ Deploy PostgreSQL optimization (Phase 25-B)
5. ⏳ Create GitHub issue #274 (branch protection setup)
6. ⏳ April 21: Team governance training

---

**Status**: READY FOR EXECUTION  
**Blocker**: None (proceeding immediately)  
**Owner**: Infrastructure Team  
**Last Updated**: April 14, 2026

