# Phase 2 Implementation Roadmap — Tasks 3 & 4

**Status**: Tasks 1-2 COMPLETE (commit pushed), Tasks 3-4 IN PROGRESS
**Timeline**: Remaining 10-16 hours (Task 3: 5-6h, Task 4: 8-10h)

---

## Task 3: Config Drift CI Gate (5-6 hours)

### Objective
Enforce single source of truth (SSOT) for all configuration. Master config file: `.env.template`

### Current State
- `DEPLOY_HOST` defined in 6 places (drift = 5 redundant copies)
- Hardcoded IPs in docker-compose, scripts, terraform
- Inconsistent domain references across codebase

### Implementation Steps

#### Step 3.1: Create Config Drift Detection Script (2 hours)
**File**: `scripts/ci/detect-config-drift.sh`

```bash
#!/usr/bin/env bash
source "$SCRIPT_DIR/_common/init.sh"

# Validate .env.template is SSOT
# Check for hardcoded IP patterns: 192.168.168.\d+
# Check for hardcoded domain patterns: kushnir.cloud, prod.internal
# Report findings and suggest remediation

# Exit codes:
# 0 = No drift (PASS)
# 1 = Drift found (FAIL PR)
```

**Search patterns**:
```bash
# IPs that should be variables
grep -rn "192\.168\.168\." --include="*.yml" --include="*.yaml" --include="*.sh" --include="*.tf"

# Hardcoded domains
grep -rn "kushnir\.cloud\|prod\.internal" --include="*.yml" --include="*.yaml" --include="*.conf"

# Hardcoded ports
grep -rn ":9090\|:3000\|:8080" docker-compose*.yml Caddyfile Terraform
```

**Exceptions** (allowed locations):
- `.env.template` (SSOT)
- `terraform/variables.tf` (IaC config)
- Documentation files
- Comments

#### Step 3.2: Create CI Job in ci-validate.yml (1.5 hours)
**File**: `.github/workflows/ci-validate.yml` (add new job)

```yaml
config-drift-detector:
  runs-on: ubuntu-latest
  name: Check config drift
  steps:
    - uses: actions/checkout@1f9a0c22d41e8f586a814688e619ab8849d6668b
    - name: Detect config drift
      run: bash scripts/ci/detect-config-drift.sh
      # Exits 1 if drift found → PR blocked
```

#### Step 3.3: Remediate Current Drift (2-3 hours)
**Files to update**:
1. `docker-compose.yml`: Replace IPs with env vars
   ```yaml
   # Before:
   command: http://192.168.168.31:9090
   
   # After:
   command: http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}
   ```

2. `docker-compose.production.yml`: Same pattern

3. `Caddyfile`: Replace hardcoded upstreams
   ```
   # Before:
   backend 192.168.168.31:8080
   
   # After:
   backend ${DEPLOY_HOST}:8080
   ```

4. `terraform/variables.tf`: Already has IP defaults (OK)

5. Scripts: Already use env vars via init.sh (OK)

### Success Criteria
- [ ] `scripts/ci/detect-config-drift.sh` created and tested locally
- [ ] CI job added to ci-validate.yml
- [ ] All current drift remediated (IPs→env vars, domains→vars)
- [ ] Run CI check: confirms 0 drift found
- [ ] Document SSOT pattern in code-server governance guide

---

## Task 4: Refactor 8 Scripts to Use `_common/` Libraries (8-10 hours)

### Objective
Eliminate 500+ LOC of duplicate utility code by using canonical library functions.

### Identified Scripts with Duplication

| Script | Duplicate Code | Canonical Function | Effort |
|--------|----------------|-------------------|--------|
| audit-logging.sh | Custom validation (20 LOC) | `require_var` | 1h |
| backup.sh | Custom error handling (15 LOC) | `log_error`, `log_fatal` | 1h |
| automated-oauth-configuration.sh | Custom retry logic (25 LOC) | `retry` function | 1.5h |
| docker-health-monitor.sh | Custom service checks (20 LOC) | `docker.sh` helpers | 1.5h |
| error-triage-engine.sh | Custom retry + error (30 LOC) | `retry`, `log_*` | 2h |
| enforce-governance.sh | Custom config validation (25 LOC) | `require_file`, `require_var` | 1.5h |
| incident-simulation.sh | Custom error handling (20 LOC) | `log_*` functions | 1h |
| infrastructure-assessment-31.sh | Custom checks (25 LOC) | `require_command`, `require_file` | 1.5h |

**Total**: ~180 LOC deduplication, 11 hours effort

### Implementation Pattern

#### Before (Custom):
```bash
# audit-logging.sh (before)
if [ -z "$event_type" ] || [ -z "$developer_id" ]; then
    echo "ERROR: event_type and developer_id required" >&2
    return 1
fi
```

#### After (Canonical):
```bash
# audit-logging.sh (after)
require_var "event_type" "Audit event type required"
require_var "developer_id" "Developer ID required"
```

### Implementation Steps (Parallelizable)

#### Step 4.1: audit-logging.sh (1 hour)
```bash
# Replace 15 lines of custom validation:
-   if [ -z "$event_type" ] || [ -z "$developer_id" ]; then
-       echo "ERROR: event_type and developer_id required" >&2
-       return 1
-   fi
+   require_var "event_type" "Audit event type required"
+   require_var "developer_id" "Developer ID required"

# Uses: require_var (from _common/utils.sh)
```

#### Step 4.2: backup.sh (1 hour)
```bash
# Replace custom error function:
-   if ! backup_database; then
-       echo "ERROR: Backup failed" >&2
-       exit 1
-   fi
+   if ! backup_database; then
+       log_fatal "Backup failed"
+   fi

# Uses: log_fatal (from _common/logging.sh)
```

#### Step 4.3: automated-oauth-configuration.sh (1.5 hours)
```bash
# Replace custom retry loop (25 LOC):
-   for i in {1..5}; do
-       if oauth_validate; then
-           echo "✓ Validated"
-           break
-       fi
-       if [ $i -lt 5 ]; then
-           sleep $((2 ** i))
-       fi
-   done
+   retry 5 "oauth_validate" "OAuth validation"

# Uses: retry (from _common/utils.sh)
```

#### Step 4.4-4.8: Remaining 5 scripts (6.5 hours)
Similar patterns for:
- docker-health-monitor.sh → use `docker.sh` helpers (or create them)
- error-triage-engine.sh → use `retry` + `log_*`
- enforce-governance.sh → use `require_file`, `require_var`
- incident-simulation.sh → use `log_*`
- infrastructure-assessment-31.sh → use `require_command`, `require_file`

### Quick Reference: Canonical Functions

**From `_common/utils.sh`**:
```bash
require_var "VAR_NAME" "Error message"
require_command "command-name" "Error message"
require_file "/path/to/file" "Error message"
retry <attempts> "command" "description"
confirm "prompt message"
die "error message"
```

**From `_common/logging.sh`**:
```bash
log_debug "message"
log_info "message"
log_warn "message"
log_error "message"    # Does NOT exit
log_fatal "message"    # EXITS with code 1
```

**From `_common/docker.sh`** (if it exists):
```bash
docker_wait_healthy "container-name" <seconds>
docker_logs "container-name" [lines]
docker_exec "container-name" "command"
```

### Success Criteria
- [ ] All 8 scripts refactored to use canonical functions
- [ ] ~180 LOC of duplicate code removed
- [ ] Scripts tested locally: `bash scripts/my-script.sh`
- [ ] All scripts follow canonical patterns
- [ ] No custom error handling or retry logic remains

---

## Execution Timeline

**Recommended parallelization**:
- **Person A**: Task 3 (Config drift gate) — 5-6 hours sequential
- **Person B**: Task 4 (Script refactoring) — 8-10 hours parallelizable

**Critical path** (if solo):
1. Task 3: Config drift (5-6h)
2. Task 4: Script refactoring (8-10h)
3. **Total**: 13-16 hours (or 2 days at 6-8 hrs/day)

---

## Verification Commands

After Task 3:
```bash
bash scripts/ci/detect-config-drift.sh
# Should output: "✓ No config drift detected"
```

After Task 4:
```bash
# Verify each script sources init.sh and uses canonical functions
for script in scripts/audit-logging.sh scripts/backup.sh ...; do
    grep -c "require_var\|log_\|retry" "$script"  # Count canonical calls
done
```

---

## Next Steps After Phase 2

- Phase 3: Unify test utilities, archive deprecated functions
- Integration: Run full test suite with refactored scripts
- Monitoring: Watch for regressions in Phase 2-refactored scripts (1-2 weeks)
