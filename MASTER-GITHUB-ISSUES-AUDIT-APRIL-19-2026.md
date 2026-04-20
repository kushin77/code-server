# COMPREHENSIVE GITHUB ISSUES AUDIT — April 19, 2026
## Production Readiness: Complete Gap & Issue Inventory

**Total Issues to Create:** 34 high-priority items  
**Total Estimated Effort:** 120+ hours  
**Priority Distribution:** 6 P0 | 15 P1 | 10 P2 | 3 P3  
**Timeline to Resolution:** 4-6 weeks

---

## 🔴 P0 CRITICAL ISSUES (Fix This Week)

### Issue 1: CRITICAL — Terraform State Backend Missing
- **Type:** Infrastructure Security
- **Description:** Terraform using local state only (no locking, audit trail, or disaster recovery)
- **Files Affected:** [main.tf](main.tf), [terraform/](terraform/)
- **Impact:** Multi-admin deployments fail; state conflicts; disaster recovery impossible
- **Effort:** 4-6 hours
- **Steps:**
  1. Set up terraform backend (S3, Cloud Storage, or encrypted NFS)
  2. Migrate local state to remote backend
  3. Test multi-user locking
  4. Document backend configuration
  5. Enable state encryption
- **Related Issues:** None
- **Blocked By:** Vault setup (P2)

### Issue 2: CRITICAL — Hardcoded Secrets in .env File
- **Type:** Security / Secret Management
- **Description:** Nine secrets stored in plaintext in .env (Google OAuth, GitHub token, GoDaddy keys, passwords)
- **Files Affected:** [.env](.env), [.env.defaults](.env.defaults)
- **Impact:** Anyone with file access reads all secrets; visible in process memory, logs, backups
- **Status:** Protected by .gitignore (not in git), but plaintext risk remains
- **Effort:** 8-12 hours (full implementation)
- **Quick Fix (2 hours):**
  1. Rotate all credentials immediately
  2. Add .env to .gitignore (already done ✓)
  3. Implement file permission restrictions (chmod 600)
  4. Add pre-commit hook to detect secrets
- **Full Fix (8-12 hours):**
  1. Implement Vault for on-prem secrets (Phase 2)
  2. Implement GSM for production secrets (Phase 3)
  3. Create bootstrap script for secret injection
  4. Update docker-compose for secret management
  5. Document secret rotation procedures
- **Related Issues:** #TBD (Vault setup), #TBD (GSM integration)
- **Acceptance Criteria:**
  - [ ] All secrets rotated
  - [ ] .env not committed to git
  - [ ] Pre-commit hook blocks plaintext secrets
  - [ ] Vault configured for on-prem
  - [ ] GSM configured for production

### Issue 3: CRITICAL — NAS Configuration Mismatch
- **Type:** Infrastructure / Operations
- **Description:** Three conflicting NAS IPs (192.168.168.10 vs .11 vs .12 vs .56) causing mount failures
- **Files Affected:** [scripts/nas-mount-31.sh](scripts/nas-mount-31.sh), [.env.example](.env.example), [scripts/nas-mount-42.sh](scripts/nas-mount-42.sh)
- **Impact:** Silent mount failures → container crashes → data access failures
- **Status:** BLOCKING production deployments
- **Effort:** 2-3 hours
- **Steps:**
  1. Verify production NAS IP (call team/docs)
  2. Update all scripts to use env vars (NAS_PRIMARY, NAS_SECONDARY, NAS_ARCHIVE)
  3. Update .env.template with correct IPs
  4. Test mount on both hosts
  5. Document NAS topology in architecture guide
  6. Add monitoring/alerting for mount status
- **Related Issues:** #TBD (NAS topology docs), #TBD (monitoring)
- **Acceptance Criteria:**
  - [ ] Single source of truth for NAS IPs (env vars)
  - [ ] Mounts working on 192.168.168.31
  - [ ] Mounts working on 192.168.168.42
  - [ ] Documented in [docs/NAS-ARCHITECTURE.md](docs/NAS-ARCHITECTURE.md)

### Issue 4: CRITICAL — Image Immutability Not Enforced
- **Type:** Infrastructure / Reproducibility
- **Description:** Some images use :latest tag instead of pinned versions (ollama, mistral, etc.)
- **Files Affected:** [docker-compose.yml](docker-compose.yml), [terraform/192.168.168.31/variables.tf](terraform/192.168.168.31/variables.tf)
- **Impact:** Non-reproducible builds; unexpected version changes on container restart
- **Effort:** 3-4 hours
- **Steps:**
  1. Replace all floating tags with pinned versions
  2. Add digest validation (sha256:...)
  3. Update Makefile to enforce pinning
  4. Add CI check to block floating tags
  5. Document version pinning policy
- **Examples:**
  - `ollama:latest` → `ollama:0.1.33-sha256:abc123...`
  - `mistral:latest` → `mistral:v0.1.2-sha256:def456...`
- **Related Issues:** #TBD (CI policy enforcement)
- **Acceptance Criteria:**
  - [ ] All images pinned in docker-compose.yml
  - [ ] All images pinned in terraform
  - [ ] CI enforces pinning
  - [ ] Documented in [docs/VERSION-PINNING-POLICY.md](docs/VERSION-PINNING-POLICY.md)

### Issue 5: CRITICAL — Database Name Inconsistency
- **Type:** Configuration / IaC
- **Description:** Database name defined as `codeserver` in some places, `code_server` in others, `ide_production` in others
- **Files Affected:** [.env](.env), [terraform/variables.tf](terraform/variables.tf), [docker-compose.yml](docker-compose.yml), [postgres-init.sql](postgres-init.sql)
- **Impact:** Connection failures; initialization failures; data loss risk
- **Status:** BLOCKING deployment
- **Effort:** 2-3 hours
- **Steps:**
  1. Choose canonical database name (RECOMMEND: `code_server`)
  2. Update all references
  3. Create migration script for existing databases
  4. Update documentation
  5. Test connection end-to-end
- **Related Issues:** #TBD (config SSOT)
- **Acceptance Criteria:**
  - [ ] Single database name everywhere
  - [ ] Existing deployments migrated
  - [ ] Connection tests passing

### Issue 6: CRITICAL — Configuration Conflicts (16 items)
- **Type:** Configuration / IaC
- **Description:** Configuration items defined in multiple places with conflicting values
- **Files Affected:** Multiple (.env, terraform/variables.tf, docker-compose.yml, etc.)
- **Details:** See [CONFIGURATION-SSOT-ANALYSIS-APRIL-2026.md](CONFIGURATION-SSOT-ANALYSIS-APRIL-2026.md)
- **Impact:** Unpredictable behavior; deployment failures; inconsistent environments
- **Effort:** 6-8 hours
- **Key Conflicts:**
  1. DOMAIN in .env vs terraform
  2. DATABASE_PASSWORD in .env vs .env.defaults vs terraform
  3. OLLAMA_MODELS version mismatch
  4. PRIMARY_HOST IP divergence
  5. ACME_EMAIL inconsistency
- **Steps:**
  1. For each conflict, identify SSOT location
  2. Consolidate to single source
  3. Create override hierarchy documentation
  4. Update .env.template
  5. Validate in terraform and docker-compose
  6. Test with all configuration combinations
- **Related Issues:** #TBD (SSOT framework)
- **Acceptance Criteria:**
  - [ ] Single SSOT for each config item
  - [ ] Override hierarchy documented
  - [ ] No conflicting values
  - [ ] Test suite validates consistency

---

## 🟠 P1 HIGH-PRIORITY ISSUES (Fix This Sprint)

| # | Issue | Type | Effort | File | Status |
|---|-------|------|--------|------|--------|
| 7 | Missing terraform validation rules | IaC | 3-4h | [terraform/variables.tf](terraform/variables.tf) | Not Started |
| 8 | Duplicate logging systems (60+ lines) | Code Quality | 2-3h | [scripts/](scripts/) | Not Started |
| 9 | Deprecated common-functions.sh still used | Tech Debt | 1-2h | [scripts/](scripts/) | Not Started |
| 10 | Missing GOV-002 headers (~15 scripts) | Governance | 1h | [scripts/](scripts/) | Not Started |
| 11 | Shell script naming inconsistent | Standards | 4-5h | [scripts/](scripts/) | Not Started |
| 12 | 47 documentation gaps | Documentation | 8-12h | [docs/](docs/) | Analysis Complete |
| 13 | Dockerfile optimization (layer caching) | Performance | 3-4h | [Dockerfile*](Dockerfile) | Not Started |
| 14 | NAS redundancy/failover missing | Reliability | 3-4h | [scripts/nas-mount-*.sh](scripts/) | Not Started |
| 15 | Monorepo dependency duplication | Code Quality | 3-4h | [pnpm-lock.yaml](pnpm-lock.yaml) | Analysis Complete |
| 16 | Missing lockfile CI validation | CI/CD | 2-3h | [.github/workflows/](..github/workflows/) | Not Started |
| 17 | Missing error handling in terraform | IaC | 3-4h | [terraform/](terraform/) | Not Started |
| 18 | Git commit message inconsistency | Standards | 2-3h | Repo-wide | Not Started |
| 19 | Missing API specification (OpenAPI) | Documentation | 6-8h | [docs/](docs/) | Not Started |
| 20 | Incomp

lete incident response procedures | Documentation | 6h | [docs/](docs/) | Not Started |
| 21 | Missing troubleshooting guide | Documentation | 4h | [docs/](docs/) | Not Started |

---

## 🟡 P2 MEDIUM-PRIORITY ISSUES (Next Sprint)

| # | Issue | Type | Effort | Estimated | Status |
|---|-------|------|--------|-----------|--------|
| 22 | Stale/archived code cleanup | Tech Debt | 4-6h | 2 weeks | Not Started |
| 23 | Hardcoded IPs/domains in scripts | Config | 4-6h | 2 weeks | Identified |
| 24 | NAS topology documentation | Documentation | 3h | 2 weeks | Not Started |
| 25 | Monorepo guide (MONOREPO.md) | Documentation | 3h | 2 weeks | Not Started |
| 26 | Error code reference documentation | Documentation | 4h | 2 weeks | Not Started |
| 27 | Data retention policy doc | Documentation | 3h | 2 weeks | Not Started |
| 28 | TODO tracker consolidation | Documentation | 6h | 2 weeks | Not Started |
| 29 | Makefile target consistency | Standards | 3h | 3 weeks | Not Started |
| 30 | Kubernetes migration (ADR-004) | IaC | 12h | Next quarter | Not Started |

---

## 🟢 P3 LOW-PRIORITY ISSUES (Backlog)

| # | Issue | Type | Effort | Status |
|---|-------|------|--------|--------|
| 31 | Extend terraform test coverage | Testing | 8-10h | Backlog |
| 32 | Optimize docker layer caching | Performance | 4-5h | Backlog |
| 33 | Create development environment guide | Documentation | 4h | Backlog |
| 34 | Establish metrics/SLO dashboards | Monitoring | 6-8h | Backlog |

---

## 🌳 BRANCH CLEANUP (SEPARATE TRACKING)

### Current Status
- **Total Branches:** 127 (local + remote)
- **Stale Branches:** ~45 (>30 days without commit)
- **Ready for Merge:** 8 (currently passing CI)
- **Blocked by CI:** 3 (failing checks)

### Cleanup Plan
- **Phase 1 (Today):** Delete 12 merged local branches ✓
- **Phase 2 (This Week):** Delete ~15 stale remote branches
  - To delete: phase-6-*, phase-7-*, week-3-*, tier2-3-*, production-ready-*, etc.
- **Phase 3 (Ongoing):** Monthly branch audit
  - Document stale branch policy in [CONTRIBUTING.md](CONTRIBUTING.md) ✓
  - Enforce naming conventions
  - Auto-delete merged branches (GitHub Actions)

---

## 📊 EFFORT ESTIMATION MATRIX

| Priority | Count | Total Hours | Team Velocity (80h/week) | Timeline |
|----------|-------|-------------|--------------------------|----------|
| **P0** | 6 | 25-40h | ~2-3 days | This week |
| **P1** | 15 | 40-60h | ~4-5 days | Next 2 weeks |
| **P2** | 10 | 30-50h | ~4-5 days | Following 2 weeks |
| **P3** | 3 | 20-30h | ~2-3 days | Backlog |
| **Branch Cleanup** | 45 branches | 3-4h | ~1-2 hours | Ongoing |
| **TOTAL** | **34** | **120-180h** | **2-3 weeks** | **Q2 2026** |

---

## 🎯 IMPLEMENTATION ROADMAP

### Week 1 (Immediate - April 22-26)
- [ ] Create all P0 GitHub issues
- [ ] Assign owners to P0 items
- [ ] Complete terraform backend setup
- [ ] Verify/fix NAS configuration
- [ ] Rotate all hardcoded secrets
- [ ] Pin all image versions
- [ ] Resolve database name conflicts
- [ ] Resolve configuration conflicts

### Week 2-3 (April 29 - May 10)
- [ ] Create P1 GitHub issues
- [ ] Migrate duplicate logging systems
- [ ] Remove deprecated common-functions.sh
- [ ] Fix terraform validation rules
- [ ] Fix missing GOV-002 headers
- [ ] Add CI validation for lockfile
- [ ] Document 47 missing docs
- [ ] Add NAS redundancy/failover

### Week 4+ (May 13+)
- [ ] Create P2 GitHub issues
- [ ] Complete documentation gap closure
- [ ] Cleanup stale branches
- [ ] Establish metrics/SLO dashboards
- [ ] Begin Kubernetes migration planning

---

## ✅ SUCCESS CRITERIA (Production Ready)

### Code Quality
- [ ] 0 P0 issues remaining
- [ ] <10 P1 issues remaining (accepted tech debt)
- [ ] All tests passing
- [ ] No hardcoded secrets
- [ ] All config via environment variables
- [ ] <5% code duplication ratio
- [ ] 100% image version pinning

### Documentation
- [ ] README.md complete
- [ ] Deployment guide complete
- [ ] Troubleshooting guide complete
- [ ] Architecture documentation present
- [ ] API specification (OpenAPI) present
- [ ] Incident response procedures documented
- [ ] NAS topology documented
- [ ] Monorepo guide documented

### Operations
- [ ] Terraform state backend configured
- [ ] Multi-admin deployments working
- [ ] Disaster recovery tested
- [ ] Failover tested
- [ ] NAS redundancy active
- [ ] Monitoring/alerting active
- [ ] Secret rotation schedule established

### Security
- [ ] 0 plaintext secrets
- [ ] Vault configured
- [ ] GSM configured
- [ ] Secret scanning enabled in CI/CD
- [ ] Pre-commit hooks deployed
- [ ] Access controls verified
- [ ] Compliance checklist passing

---

## 📝 NOTES & REFERENCES

**Analysis Documents Created (April 19, 2026):**
1. [DOCUMENTATION-AUDIT-APRIL-19-2026.md](DOCUMENTATION-AUDIT-APRIL-19-2026.md)
2. [CONFIGURATION-SSOT-ANALYSIS-APRIL-2026.md](CONFIGURATION-SSOT-ANALYSIS-APRIL-2026.md)
3. [CODEBASE-ANALYSIS-APRIL-2026.md](CODEBASE-ANALYSIS-APRIL-2026.md)
4. [COMPREHENSIVE-AUDIT-APRIL-19-2026.md](COMPREHENSIVE-AUDIT-APRIL-19-2026.md)
5. [SECURITY-INCIDENT-HARDCODED-SECRETS-APRIL-19-2026.md](SECURITY-INCIDENT-HARDCODED-SECRETS-APRIL-19-2026.md)
6. [SECRETS-MANAGEMENT-REMEDIATION-PLAN-APRIL-19-2026.md](SECRETS-MANAGEMENT-REMEDIATION-PLAN-APRIL-19-2026.md)

**Previous Session Documentation:**
- [CODE-REVIEW-COMPLETION-SUMMARY-APRIL-19-2026.md](CODE-REVIEW-COMPLETION-SUMMARY-APRIL-19-2026.md)
- [GOVERNANCE-COMPLIANCE-REVIEW-APRIL-19-2026.md](GOVERNANCE-COMPLIANCE-REVIEW-APRIL-19-2026.md)
- [WORKSPACE-GOVERNANCE-ANALYSIS-APRIL-2026.md](WORKSPACE-GOVERNANCE-ANALYSIS-APRIL-2026.md)

---

## 🚀 NEXT IMMEDIATE ACTIONS

1. **Create GitHub Issues (Today):**
   ```bash
   # This document should be shared with team
   # Create one GitHub issue per P0 item
   # Create one epic per priority level (P0, P1, P2)
   ```

2. **Assign Owners (Today):**
   - P0 items: Assign to core team members
   - P1 items: Assign with sprint planning
   - Link to milestones

3. **Start Implementation (Tomorrow):**
   - Begin with P0 critical path items
   - Parallel work on independent P1 items
   - Weekly status updates

4. **Testing & Verification (Ongoing):**
   - E2E tests for each fix
   - Deployment to replica before production
   - Sign-off checklist for each issue

---

**Report Generated:** 2026-04-19T15:45:00Z  
**Status:** Ready for GitHub Issue Creation  
**Ownership:** Required for P0 items  
**Next Review:** After all P0 GitHub issues created
