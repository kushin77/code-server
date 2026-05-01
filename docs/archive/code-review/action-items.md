# Code Review Action Items Checklist
**Generated:** May 1, 2026  
**Status:** Ready for Implementation  
**Est. Completion Time:** 3-4 weeks

---

## 🔴 WEEK 1: CRITICAL CLEANUP (1 hour total)

### Container Image Pinning
- [ ] **Task 1.1**: Pin `code-server-control-plane:latest`
  - Command: `docker pull code-server-control-plane:latest`
  - Get digest: `docker inspect --format='{{index .RepoDigests 0}}' code-server-control-plane:latest`
  - Update: `docker-compose.yml` line ~XXX
  - Time: 3 min
  - File: CODE_REVIEW_COMPREHENSIVE_2026-05-01.md (Section 1, Issue #1)

- [ ] **Task 1.2**: Pin `code-server-enterprise-testing:latest`
  - Same process as 1.1
  - Time: 3 min

- [ ] **Task 1.3**: Pin `minio/mc:latest` (docker-compose.minio.yml)
  - Same process
  - Time: 3 min

- [ ] **Task 1.4**: Pin `minio/minio:latest` (docker-compose.minio.yml)
  - Same process
  - Time: 3 min

- [ ] **Task 1.5**: Pin `vault:latest` (docker-compose.vault.yml)
  - Same process
  - Time: 3 min

- [ ] **Validation 1.5**: Verify all images have digests
  - Command: `grep "image:" docker-compose*.yml | grep -c latest`
  - Expected result: 0

### Backup File Cleanup
- [ ] **Task 1.6**: Delete backup files
  - ```bash
    git rm docker-compose.enterprise.yml.backup
    git rm docker-compose.yml.backup
    git add .gitignore
    git commit -m "Remove backup files (git is the backup)"
    ```
  - Time: 5 min
  - File: CODE_REVIEW_COMPREHENSIVE_2026-05-01.md (Section 2)

### Legacy Directory Archival
- [ ] **Task 1.7**: Archive and remove legacy directories
  - ```bash
    git tag -a v4-phase-2-archives -m "Legacy archives from phase 2"
    git push origin v4-phase-2-archives
    git rm -r .backups .env-archive docs/archive
    git commit -m "Remove legacy archives (v6.8M saved, archived in tag)"
    ```
  - Time: 30 min
  - Saves: 6.8M repository size
  - File: CODE_REVIEW_COMPREHENSIVE_2026-05-01.md (Section 2)

### Week 1 Verification
- [ ] All docker-compose files valid: `docker-compose config > /dev/null`
- [ ] No "latest" tags remain: `grep "image:" docker-compose*.yml | grep -c latest` = 0
- [ ] Repository size reduced by ~6.8M: `du -sh .` (before/after comparison)
- [ ] Git history preserved: `git log --oneline | head -5` shows cleanup commits

**Week 1 Target**: ✅ COMPLETE (Should take 1-1.5 hours max)

---

## 🟠 WEEK 2: LOGGING STANDARDIZATION (12-16 hours)

### Python Logging Implementation

#### Phase 2.1: Create/Update Logging Module (1 hour)
- [ ] **Task 2.1.1**: Review current logging module
  - Location: `apps/_shared/python/logging.py`
  - Verify it has: JSON format, timestamp, log levels
  - Time: 15 min

- [ ] **Task 2.1.2**: Update/enhance logging module for JSON output
  - Add structured JSON format
  - Add contextual fields (request_id, user_id, etc.)
  - Time: 45 min

#### Phase 2.2: Update Python Files (4 hours)
- [ ] **Task 2.2.1**: Update `apps/hermes-integration/main.py`
  - Replace: 3x `print()` statements
  - Import: `from apps._shared.python.logging import logger`
  - Time: 20 min

- [ ] **Task 2.2.2**: Update `apps/extensions/statusbar-tiles/api-clients.py`
  - Replace: 15x `print()` statements
  - Time: 45 min

- [ ] **Task 2.2.3**: Update `apps/extensions/shared-clipboard/storage.py`
  - Replace: 6x `print()` statements
  - Time: 30 min

- [ ] **Task 2.2.4**: Update remaining 11 Python files
  - apps/auth-server/src/config.py
  - apps/env-provisioner/provisioner.py
  - apps/activity_feed/consumer.py
  - apps/execution-scheduler/cost_tracker.py
  - apps/execution-scheduler/monitors.py
  - apps/memory-engine/agent_learnings.py
  - apps/memory-engine/seed.py
  - scripts/ops/close-remaining-phase-issues.py
  - scripts/ops/inject-github-evidence.py
  - scripts/ops/generate-closure-report.py
  - scripts/ops/batch-close-phase-issues.py
  - Time: 2 hours (20 min each)

#### Phase 2.2 Validation
- [ ] No remaining print() in apps/: `grep -r "print(" apps/ --include="*.py" | wc -l` = 0
- [ ] All files import logger: `grep -r "from.*logging import" apps/ | wc -l` > 14
- [ ] Test execution: `python apps/hermes-integration/main.py --help` succeeds

### Shell Script Logging Implementation

#### Phase 2.3: Create Shell Logging Library (2 hours)
- [ ] **Task 2.3.1**: Create `scripts/common/logging.sh`
  - Implement `log_info()`, `log_error()`, `log_warn()`, `log_debug()`
  - Output JSON format with timestamp
  - Time: 2 hours
  - Reference: CODE_REVIEW_COMPREHENSIVE_2026-05-01.md (Section 1, Issue #3)

#### Phase 2.4: Update Shell Scripts (6 hours)
- [ ] **Task 2.4.1**: Update top 10 CI scripts (scripts/ci/*.sh)
  - Add: `source scripts/common/logging.sh` at top
  - Replace: `echo "..."` with `log_info "..."`
  - Time: 1 hour (6 min per script)

- [ ] **Task 2.4.2**: Update top 10 ops scripts (scripts/ops/deploy-*.sh)
  - Same pattern
  - Time: 1 hour

- [ ] **Task 2.4.3**: Update validation scripts (scripts/ops/validate-*.sh)
  - Time: 1 hour

- [ ] **Task 2.4.4**: Update backup scripts (scripts/backup/*.sh)
  - Time: 45 min

- [ ] **Task 2.4.5**: Update chaos/test scripts (scripts/chaos/*.sh)
  - Time: 45 min

- [ ] **Task 2.4.6**: Update remaining scripts
  - Time: 1 hour

#### Phase 2.4 Validation
- [ ] All scripts source logging: `grep -r "source.*logging" scripts/ | wc -l` > 20
- [ ] Echo replaced with log_*: `grep -r "^log_" scripts/ --include="*.sh" | wc -l` > 100
- [ ] No bare echo in critical scripts: `grep -r "^echo" scripts/ops/ | wc -l` < 10 (debug only)

### Docker Compose Network Consolidation

#### Phase 2.5: Standardize Networks (4 hours)
- [ ] **Task 2.5.1**: Document current network usage across 6 files
  - Files:
    - docker-compose.yml
    - docker-compose.prod.yml
    - docker-compose.enterprise.yml
    - docker-compose.vault.yml
    - docker-compose.minio.yml
    - docker-compose.override.yml
  - Time: 1 hour

- [ ] **Task 2.5.2**: Standardize to 3 networks (ingress, services, database)
  - Update prod/enterprise/vault/minio to match main
  - Use extend pattern where appropriate
  - Time: 2 hours

- [ ] **Task 2.5.3**: Test deployment parity
  - Deploy with different compose files
  - Verify services communicate correctly
  - Time: 1 hour

#### Phase 2.5 Validation
- [ ] All compose files parse: `for f in docker-compose*.yml; do docker-compose -f $f config > /dev/null || echo "FAIL: $f"; done`
- [ ] Network count consistent: `for f in docker-compose*.yml; do echo "$f: $(grep -c "^  [a-z]*:$" $f)"; done` (all should be 3)
- [ ] Services resolve via DNS: `docker-compose up -d && docker exec code-server-postgres ping code-server-redis -c 1`

**Week 2 Target**: ✅ COMPLETE (12-16 hours)  
**Dependencies**: Requires Week 1 completion

---

## 🟡 WEEK 3: IaC IMPROVEMENTS (10-16 hours)

### Terraform Input Validation

#### Phase 3.1: Add Variable Validation (6 hours)
- [ ] **Task 3.1.1**: Add IPv4/FQDN validation to `primary_host`
  - File: `terraform/environments/private/main.tf` or `variables.tf`
  - Add validation block with regex
  - Time: 1 hour
  - Reference: CODE_REVIEW_COMPREHENSIVE_2026-05-01.md (Section 5, Issue #5)

- [ ] **Task 3.1.2**: Add IPv4/FQDN validation to `replica_host`
  - Same pattern
  - Time: 1 hour

- [ ] **Task 3.1.3**: Add IPv4/FQDN validation to `nas_host`
  - Same pattern
  - Time: 1 hour

- [ ] **Task 3.1.4**: Add range validation to `ssh_port` (1-65535)
  - Time: 1 hour

- [ ] **Task 3.1.5**: Add range validation to `metrics_retention_days` (1-365)
  - Time: 1 hour

- [ ] **Task 3.1.6**: Document validation strategy
  - Add README or comments
  - Time: 30 min

#### Phase 3.1 Validation
- [ ] Test invalid IP: `terraform plan -var="primary_host=invalid"` fails at plan time
- [ ] Test invalid port: `terraform plan -var="ssh_port=99999"` fails
- [ ] Valid inputs still work: `terraform plan` succeeds

### Resource Tagging Completion

#### Phase 3.2: Add Tags to Modules (4 hours)
- [ ] **Task 3.2.1**: Add tagging to `terraform/modules/core/`
  - Tag VPC resources
  - Tag subnet resources
  - Tag gateway resources
  - Time: 1.5 hours

- [ ] **Task 3.2.2**: Add tagging to `terraform/modules/api_gateway/`
  - Time: 1 hour

- [ ] **Task 3.2.3**: Add tagging to `terraform/modules/storage/`
  - Tag S3 buckets
  - Tag EFS resources
  - Time: 1.5 hours

#### Phase 3.2 Validation
- [ ] All resources have tags: `terraform plan | grep -c "tags ="` > 50
- [ ] Tags consistent: Verify Name, Environment, ManagedBy tags on all resources
- [ ] Cost allocation possible: AWS billing can track by tag

### Optional: Logging Aggregation Integration

#### Phase 3.3: Loki/Grafana Integration (10 hours - OPTIONAL)
- [ ] Configure Loki data source in Grafana
- [ ] Create dashboard for log queries
- [ ] Verify Python logs appear in Loki
- [ ] Verify shell script logs appear in Loki
- [ ] Create alerts for ERROR-level logs
- [ ] Time: 10 hours (advanced task, can defer to Week 4)

**Week 3 Target**: ✅ COMPLETE Terraform work (10 hours)  
**Optional**: Logging aggregation (10 hours, can defer)

---

## ✅ VERIFICATION CHECKLIST

### Final Compliance Verification
- [ ] **Image Pinning**: 35/35 (100%) - no "latest" tags
- [ ] **Python Logging**: 14/14 files (100%) - no print()
- [ ] **Shell Logging**: 50/50+ scripts (100%) - all using log_*()
- [ ] **Network Consistency**: All compose files have 3 networks (100%)
- [ ] **Terraform Validation**: 5 variables have validation blocks (100%)
- [ ] **Resource Tagging**: 100% of resources tagged
- [ ] **No Backup Files**: All removed/archived
- [ ] **Repository Size**: -6.8M from cleanup

### Final Score Verification
```
Component           Target      Achieved    Pass?
────────────────────────────────────────────────
SLOG Logging        90%         90%+       ✅
Naming Conv.        100%        100%       ✅
Orphaned Files      100%        100%       ✅
IaC Quality         95%         95%+       ✅
Docker Compose      95%         95%+       ✅
────────────────────────────────────────────────
OVERALL             95%         95%+       ✅
```

---

## 📝 NOTES & DEPENDENCIES

### Dependencies
- Week 1 → Week 2: Must complete Week 1 before starting Week 2
- Week 2 → Week 3: Recommended but not blocking (parallel possible)

### Testing Requirements
- All shell scripts must pass shellcheck: `shellcheck scripts/**/*.sh`
- All Python must pass linting: `pylint apps/**/*.py`
- Docker Compose must validate: `docker-compose config > /dev/null`
- Terraform must pass validation: `terraform validate`

### Rollback Plan
- Each task creates a git commit (can revert individually)
- Week 1 archival tagged (`v4-phase-2-archives` - recoverable)
- All changes reversible via git

---

## 📊 TRACKING TEMPLATE

Copy and paste this to track progress:

```
## Progress Tracking - Code Review Implementation

### Week 1: Cleanup
- [ ] Image pinning (5 images) - [DATE: ] - Status: ___
- [ ] Backup file deletion - [DATE: ] - Status: ___
- [ ] Archive removal (6.8M) - [DATE: ] - Status: ___
- [ ] Week 1 verification - [DATE: ] - Status: ___

### Week 2: Logging
- [ ] Python logging (14 files) - [DATE: ] - Status: ___
- [ ] Shell logging library - [DATE: ] - Status: ___
- [ ] Update shell scripts (50+) - [DATE: ] - Status: ___
- [ ] Docker network consolidation - [DATE: ] - Status: ___
- [ ] Week 2 verification - [DATE: ] - Status: ___

### Week 3: IaC
- [ ] Terraform validation (5 vars) - [DATE: ] - Status: ___
- [ ] Resource tagging (3 modules) - [DATE: ] - Status: ___
- [ ] Logging aggregation (opt) - [DATE: ] - Status: ___
- [ ] Week 3 verification - [DATE: ] - Status: ___

### Summary
- Start Date: _______
- Target Completion: _______
- Actual Completion: _______
- Issues/Blockers: _______________________
```

---

## 🆘 SUPPORT RESOURCES

- **Full Report**: CODE_REVIEW_COMPREHENSIVE_2026-05-01.md
- **Quick Summary**: CODE_REVIEW_SUMMARY.md
- **This Checklist**: CODE_REVIEW_ACTION_ITEMS.md
- **Memory Notes**: /memories/session/code-review-findings.md

---

**Generated**: May 1, 2026  
**Status**: Ready for Implementation  
**Last Updated**: May 1, 2026  
**Completion Estimate**: 3-4 weeks (with full-time effort: 1-2 weeks)
