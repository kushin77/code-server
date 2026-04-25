# IaC Remediation Backlog — April 25, 2026

**Status:** Documented and Ready for Remediation  
**Date:** April 25, 2026  
**Audit Date:** April 25, 2026  
**Total Issues:** 78 violations across 43 legacy scripts  
**Priority:** P2 (Important but does not block current deployment)

---

## 📊 Executive Summary

The Infrastructure as Code (IaC) compliance audit identified 78 violations across 43 legacy scripts. All new code (deployment automation, infrastructure libraries) is **100% IaC-compliant**. This backlog documents pre-existing violations in scripts created before IaC standards were enforced.

### Violation Breakdown

| Category | Count | Severity | Pattern |
|----------|-------|----------|---------|
| Hardcoded assignments | 38 | HIGH | Missing `${VAR:-default}` pattern |
| Missing error handling | 5 | HIGH | No `set -euo pipefail` |
| Missing @governance headers | 12 | MEDIUM | No script documentation |
| Dynamic timestamps | 23 | MEDIUM | Using `$(date)` in configs |
| **TOTAL** | **78** | - | **43 scripts** |

---

## 🔴 Category 1: Hardcoded Assignments (38 Issues)

**Definition:** Scripts use hardcoded variable assignments instead of environment variables with fallbacks.

**Pattern (WRONG):**
```bash
HOST="192.168.168.31"          # ❌ Hardcoded IP
PORT="3100"                     # ❌ Hardcoded port
PASSWORD="secret123"            # ❌ Hardcoded password
```

**Pattern (CORRECT):**
```bash
readonly HOST="${DEPLOY_HOST:-192.168.168.31}"      # ✅ Env var with default
readonly PORT="${API_PORT:-3100}"                    # ✅ Configurable
readonly PASSWORD="${DB_PASSWORD:-}"                 # ✅ From env (no default for secrets)
```

### Affected Scripts (38 total)

**scripts/ci/ (13 violations):**
1. analyze-documentation-gaps.sh
2. audit-network-hardcoding.sh
3. check-docker-compose-idempotency.sh
4. check-github-api-governance.sh
5. codebase-hygiene-audit.sh
6. domain-variability-enforcer.sh
7. fix-codebase-deduplication.sh
8. gitops-drift-detector.sh
9. q2-2026-completion-audit.sh
10. security-vulnerability-remediation.sh
11. setup-gitops-workflow.sh
12. validate-config-ssot.sh
13. validate-terraform-version-pins.sh

**scripts/lib/ (1 violation):**
1. nas.sh

**scripts/ops/ (24 violations):**
1. audit-logging-orchestrator.sh
2. autonomous-operations-orchestrator.sh
3. calibrate-alert-thresholds.sh
4. cleanup-uncommitted.sh
5. collect-baseline-metrics.sh
6. configure-postgres-ssl.sh
7. deployment-pipeline.sh
8. harden-ssl-tls.sh
9. implement-network-policies.sh
10. implement-rbac.sh
11. infrastructure-health-check.sh
12. monitor-replication.sh
13. production-readiness-check.sh
14. setup-database-ssl.sh
15. setup-encryption-at-rest.sh
16. setup-log-rotation.sh
17. setup-opa-service.sh
18. setup-production-alerts.sh
19. setup-qdrant-vector-db.sh
20. setup-rbac.sh
21. setup-redpanda-eventbus.sh
22. sla-metrics-reporter.sh
23. validate-tls-hardening.sh
24. verify-drop-deployment.sh

**Remediation:** Convert all hardcoded assignments to `${VAR:-default}` pattern. Approximately 2-5 hours per script depending on complexity.

---

## 🔴 Category 2: Missing Error Handling (5 Issues)

**Definition:** Scripts lack `set -euo pipefail` for fault-safe execution.

**Pattern (WRONG):**
```bash
#!/bin/bash
# Script starts without error handling
VARIABLE="value"
command_that_fails
another_command  # ❌ Still runs despite failure above
```

**Pattern (CORRECT):**
```bash
#!/bin/bash
set -euo pipefail  # ✅ Stops on error, undefined vars, pipe failures

VARIABLE="value"
command_that_fails  # ✅ Script stops here, doesn't continue
```

### Affected Scripts (5 total)

1. scripts/ci/pre-deployment-validation-simple.sh
2. scripts/ops/calibrate-alert-thresholds.sh
3. scripts/ops/collect-baseline-metrics.sh
4. scripts/ops/ssh-emergency-recovery.sh
5. scripts/ops/validate-resource-limits.sh

**Remediation:** Add `set -euo pipefail` as second line in each script (after shebang and any comments). Less than 1 minute per script.

---

## 🟡 Category 3: Missing @governance Headers (12 Issues)

**Definition:** Scripts lack documentation headers explaining purpose, author, and date.

**Pattern (WRONG):**
```bash
#!/bin/bash
# Description...
set -euo pipefail
```

**Pattern (CORRECT):**
```bash
#!/bin/bash
# @governance: Purpose of script — brief explanation
# Purpose: What this script does
# Author: Who created it
# Date: When created
# 
# Related issues: #1234, #1567

set -euo pipefail
```

### Affected Scripts (12 total)

**scripts/lib/ (1 violation):**
1. nas.sh

**scripts/ci/ (7 violations):**
1. check-docker-compose-idempotency.sh
2. check-github-api-governance.sh
3. codebase-hygiene-audit.sh
4. domain-variability-enforcer.sh
5. fix-codebase-deduplication.sh
6. gitops-drift-detector.sh
7. q2-2026-completion-audit.sh

**scripts/ops/ (4 violations):**
1. cleanup-uncommitted.sh
2. production-readiness-check.sh
3. verify-drop-deployment.sh
4. [1 additional script with minimal header]

**Remediation:** Add @governance header block with purpose, author, and date. Less than 5 minutes per script.

---

## 🟡 Category 4: Dynamic Timestamps (23 Issues)

**Definition:** Configuration templates include dynamic timestamps, breaking idempotency.

**Pattern (WRONG):**
```bash
# Generated: $(date)  # ❌ Different every run
# Last updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)  # ❌ Not idempotent
config_version="generated-$(date +%s)"  # ❌ Breaks reproducibility
```

**Pattern (CORRECT):**
```bash
# Generated: 2026-04-25 (static or from git)
# Last updated: Via git commit history (not in file)
# No timestamps in generated configs
```

### Affected Scripts (23 violations)

Pre-existing issue in:
- scripts/lib/connection-pool.sh (FIXED in commit 98282291)
- 22 other scripts with timestamp generation in configurations

**Common Pattern:**
- Configuration generators embedding `$(date)` in output
- Log rotation scripts with date-based naming
- Backup scripts with timestamp in filenames

**Remediation Strategies:**
1. **Remove timestamps from config templates** (highest priority)
2. **Use git commit time** if timestamp needed for audit
3. **Use environment variable** for timestamp injection
4. **Accept filename variation** (not stored in git)

**Remediation:** 30 minutes to 2 hours per script depending on where timestamps are used.

---

## 🎯 Remediation Priority Matrix

### Phase 1: Critical (Do First)
**Priority:** Unblock production deployment  
**Effort:** ~8 hours total

- [ ] Category 2: Add `set -euo pipefail` to 5 scripts (5 min each = 25 min)
- [ ] Category 1: Fix 5 most-frequently-used hardcoding scripts (2 hr each = 10 hr)
- [ ] Category 4: Remove timestamps from 3 config-generating scripts (1 hr each = 3 hr)

**Scripts to focus on:**
- scripts/ops/production-readiness-check.sh
- scripts/ops/infrastructure-health-check.sh
- scripts/ops/deployment-pipeline.sh
- scripts/ops/setup-production-alerts.sh
- scripts/lib/nas.sh

### Phase 2: High Priority (Do Next)
**Priority:** Standardize core infrastructure scripts  
**Effort:** ~12 hours total

- [ ] Category 3: Add @governance headers to 12 scripts (5 min each = 1 hr)
- [ ] Category 1: Fix remaining 33 hardcoding scripts (15-20 min each = 10 hr)
- [ ] Category 4: Remove timestamps from remaining 20 scripts (15 min each = 5 hr)

**Distribution:**
- scripts/ci/ directory: 7 scripts (3 hr)
- scripts/ops/ directory: 20 scripts (9 hr)

### Phase 3: Nice-to-Have (Can Defer)
**Priority:** Technical debt cleanup  
**Effort:** ~6 hours total

- [ ] Category 1: Pre-deploy validation scripts (3 scripts, 1 hr)
- [ ] Category 4: Backup and archival scripts (3 scripts, 2 hr)
- [ ] Documentation: Add usage examples (1 hr)

---

## 📋 Per-Script Remediation Template

### Example: scripts/ops/production-readiness-check.sh

**Current Status:**
```bash
❌ Hardcoded assignments (3 violations)
❌ Missing error handling
⚠️  Has @governance header but incomplete
❌ Dynamic timestamps in logs
```

**Remediation Checklist:**
- [ ] Add `set -euo pipefail` on line 2
- [ ] Review @governance header (complete if needed)
- [ ] Find all hardcoded values:
  - [ ] `HOST="192.168.168.31"` → `HOST="${DEPLOY_HOST:-192.168.168.31}"`
  - [ ] `PORT="3100"` → `PORT="${API_PORT:-3100}"`
  - [ ] [Other hardcoding]
- [ ] Remove timestamp generation:
  - [ ] Replace `$(date)` with static date or version
  - [ ] Use git commit time for audit trail
- [ ] Test with `bash -n` (syntax check)
- [ ] Run: `bash scripts/ci/validate-iac-compliance.sh` to verify fixes
- [ ] Commit with message: `fix(iac): remediate hardcoding and error handling in production-readiness-check.sh`

**Estimated Time:** 45 minutes

---

## 🛠️ IaC Remediation Tools

### Tool 1: Automated Hardcoding Detection

```bash
# Find all hardcoded assignments
grep -rn "^[A-Z_]*=" scripts/ops/ | grep -v '${' | grep -v '#'

# Find all missing error handling
find scripts/ -name "*.sh" -exec grep -L "set -euo pipefail" {} \;

# Find all missing @governance headers
find scripts/ -name "*.sh" -exec grep -L "@governance" {} \;
```

### Tool 2: Timestamp Finder

```bash
# Find all $(date) calls in scripts
grep -rn '\$(date' scripts/

# Find all date-based variable assignments
grep -rn 'date.*=' scripts/
```

### Tool 3: Compliance Report Generator

```bash
# Run IaC compliance audit (existing script)
bash scripts/ci/validate-iac-compliance.sh

# Filter results by category
bash scripts/ci/validate-iac-compliance.sh 2>&1 | grep "hardcoding"
bash scripts/ci/validate-iac-compliance.sh 2>&1 | grep "set -euo"
```

---

## 📈 Success Metrics

### Phase 1 Completion
- [ ] 5 critical scripts 100% IaC-compliant
- [ ] Zero `set -euo pipefail` violations in critical paths
- [ ] Zero hardcoded IPs in deployed services
- [ ] Production deployment scripts remain pristine

### Phase 2 Completion
- [ ] 30/38 hardcoding violations fixed (79%)
- [ ] 12/12 @governance headers added
- [ ] 20/23 timestamps removed (87%)
- [ ] 5/5 error handling violations fixed

### Phase 3 Completion
- [ ] 100% of non-legacy scripts IaC-compliant
- [ ] Automated remediation checklist in CI
- [ ] Documentation of patterns for new scripts
- [ ] Training guide for team members

---

## 📝 Best Practices for Future Scripts

### Checklist for New Infrastructure Scripts

```bash
#!/bin/bash
# @governance: <Purpose> — <Brief description>
# Purpose: <What does this script do>
# Author: <Your name>
# Date: <YYYY-MM-DD>
# Related issues: #<issue-number>, #<issue-number>

set -euo pipefail

# ✅ Use environment variables with defaults
readonly TARGET_HOST="${DEPLOY_HOST:-192.168.168.31}"
readonly TARGET_PORT="${DEPLOY_PORT:-3100}"
readonly TIMEOUT="${DEPLOYMENT_TIMEOUT:-600}"

# ✅ Avoid timestamps in configs
# Instead of: echo "Generated: $(date)" > config.yml
# Do this: echo "Generated: $(date -u +%Y-%m-%d)" > config.yml
# Or better: Let git track the timestamp via commit history

# ✅ Error handling everywhere
if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker not installed" >&2
    exit 1
fi

# ✅ Use readonly for immutable values
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="${SCRIPT_DIR}/../.."
```

---

## 🔗 Related Documentation

- **IaC Standards:** docs/IaC-STANDARDS.md (to be created)
- **Script Template:** scripts/_templates/bash-iac-template.sh (to be created)
- **Compliance Audit:** scripts/ci/validate-iac-compliance.sh
- **Deployment Automation:** scripts/ops/deploy-*.sh (all 100% compliant)

---

## 📅 Implementation Timeline

**Estimated Effort:**
- Phase 1: 8 hours (1-2 days)
- Phase 2: 12 hours (2-3 days)
- Phase 3: 6 hours (1 day)
- **Total:** ~26 hours (~1 week part-time)

**Recommended Schedule:**
1. **Day 1:** Phase 1 (critical path)
2. **Days 2-3:** Phase 2 (bulk of work)
3. **Day 4:** Phase 3 + verification

---

## 🎓 Lessons Captured

### What Went Right
- ✅ Compliance audit identified all violations automatically
- ✅ New code is 100% IaC-compliant
- ✅ Patterns are clear and repeatable
- ✅ Existing tools can validate fixes

### What to Improve
- ❌ Pre-existing violations accumulated over time
- ❌ No enforcement in CI for legacy scripts
- ❌ No standardized template for new scripts
- ❌ Training gap on IaC principles

### Prevention Going Forward
1. **CI Integration:** Enforce IaC compliance on all PRs
2. **Script Template:** Provide standardized bash template
3. **Code Review:** Require @governance headers + error handling
4. **Documentation:** Link IaC standards in CONTRIBUTING.md
5. **Training:** Share best practices with team

---

## ✅ Completion Criteria

- [ ] All 38 hardcoding violations remediated
- [ ] All 5 error handling violations fixed
- [ ] All 12 @governance headers added
- [ ] All 23 timestamps removed from configs
- [ ] Zero violations reported by `validate-iac-compliance.sh`
- [ ] All fixes committed to main branch
- [ ] Documentation updated with lessons learned

---

**Status:** Ready for Phase 1 Implementation  
**Approver:** Autonomous Agent  
**Date Created:** April 25, 2026  
**Next Review:** After Phase 1 completion  
