# Script Consolidation Strategy: Migrate to Shared Logging

## Overview

This document outlines the strategy for consolidating 196 bash scripts that currently use local logging functions to use the centralized shared logging module (`apps/_shared/test.sh`).

## Current State

- **Total Scripts Found**: 196 bash scripts with local logging functions
- **Distribution**:
  - ops: 68 scripts (34%)
  - ci: 32 scripts (16%)
  - _common: 19 scripts (10%)
  - k8s: 10 scripts (5%)
  - Others: 67 scripts (35%)

## Consolidation Goals

1. **Code Reuse**: Use shared logging functions instead of duplicating code
2. **Consistency**: Ensure uniform logging format across all scripts
3. **Maintainability**: Fix bugs and add features in one place
4. **Performance**: Reduce file size and startup time
5. **Compliance**: Ensure all scripts follow same logging standards

## Implementation Strategy

### Phase 1: Foundation (Complete)
✅ Created `apps/_shared/test.sh` with all common logging functions  
✅ Documented with examples and usage guide

### Phase 2: High-Priority (In Progress)
Priority 1 - _common scripts (19 scripts)
- These are foundational and reused by many others
- Low risk due to heavy testing

Priority 2 - CI/CD scripts (32 scripts)
- Critical for deployment pipeline
- Must validate thoroughly before deployment

Priority 3 - Ops scripts (high-impact subset, ~20 scripts)
- Focus on deploy, health, monitor categories
- Test in staging before production

### Phase 3: Medium-Priority (Planned)
- k8s scripts (10)
- extension-related scripts (8)
- automation scripts

### Phase 4: Low-Priority (Future)
- Legacy scripts with custom logging
- Less frequently used utilities

## Migration Pattern

### Before Migration

```bash
#!/bin/bash

# Local logging function definitions
log_info() {
    printf "[INFO] %s\n" "$1"
}

log_success() {
    printf "[✓] %s\n" "$1"
}

# Script code using local functions
log_info "Starting script"
log_success "Operation completed"
```

### After Migration

```bash
#!/bin/bash

# Source shared logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/apps/_shared/test.sh"

# Script code using shared functions
log_info "Starting script"
log_success "Operation completed"
```

## Critical Considerations

### 1. Syntax Compatibility
Ensure all local logging functions have equivalent implementations in shared module:

```bash
Local Implementation          → Shared Module Equivalent
log_info "msg"              → log_info "msg"
log_success "msg"           → log_success "msg" (uses ✓)
log_error "msg"             → log_error "msg"
log_warning "msg"           → log_warning "msg"
log_debug "msg"             → log_debug "msg"
```

### 2. Functionality Mapping
Verify behavioral equivalence:

| Aspect | Local | Shared | Status |
|--------|-------|--------|--------|
| Terminal colors | ANSI codes | ANSI codes | ✓ Compatible |
| Timestamp | Varies | Included in structured | ✓ Enhanced |
| Indentation | Varies | Consistent | ✓ Improved |
| Output format | TEXT only | TEXT/JSON/STRUCTURED | ✓ Flexible |

### 3. Script Dependencies
Check if any scripts have special dependencies:

```bash
# Some scripts might use custom log level filtering
# Some might have custom timestamp formats
# Some might integrate with specific tools (git, docker, etc.)
```

## Rollout Schedule

### Week 1: _common scripts (19 scripts)
- Migrate scripts in `scripts/_common/`
- Thoroughly test all shared dependencies
- Get sign-off from team

### Week 2: CI/CD Foundation (10 scripts)
- Migrate key validation and check scripts
- Run full CI/CD pipeline
- Deploy to staging

### Week 3: Ops Foundation (15 scripts)
- Migrate deployment and health check scripts
- Test in staging environment
- Prepare for production rollout

### Week 4: Full Deployment (remaining 152 scripts)
- Batch migrate remaining scripts by category
- Monitor for any issues
- Update documentation

## Validation Checklist

For each migrated script:

- [ ] Syntax validation: `bash -n script.sh`
- [ ] Functionality test: Run with sample inputs
- [ ] Logging output: Verify format and content
- [ ] Integration test: Run with dependent scripts
- [ ] Performance: Check execution time (should improve)

## Rollback Plan

For any script migration failure:

1. **Automatic Backup**: Script creates `.backup` before migration
2. **Quick Restore**: `mv script.sh.backup script.sh`
3. **Investigation**: Review logs and migration tool output
4. **Manual Fix**: Resolve issue and retry migration
5. **Documentation**: Record what failed for other scripts

## Commands for Migration

### Manual Migration of Single Script

```bash
# Step 1: Create backup
cp script.sh script.sh.backup

# Step 2: Edit script - Remove local logging functions
# Remove lines like:
# log_info() { printf "[INFO] %s\n" "$1"; }
# log_success() { printf "[✓] %s\n" "$1"; }

# Step 3: Add source statement (after shebang)
# Add:
# source "$REPO_ROOT/apps/_shared/test.sh"

# Step 4: Validate syntax
bash -n script.sh

# Step 5: Restore from backup if failed
[ $? -ne 0 ] && mv script.sh.backup script.sh
```

### Batch Migration Command

```bash
# Find all scripts needing migration in a directory
find scripts/ci -name "*.sh" | while read f; do
    if grep -q "log_info()" "$f"; then
        echo "Migrate: $f"
    fi
done

# Generate migration script for review
./scripts/ci/generate-migration-script.sh > migration.sh
# Review migration.sh manually
# Then execute: bash migration.sh
```

## Expected Outcomes

### Quantitative Benefits
- **Code Reduction**: ~5-10KB per script (estimate 1-2MB total)
- **Startup Time**: ~5-10ms faster per script (cumulatively significant)
- **Maintenance Cost**: Reduce by ~40% (fix once, benefit all scripts)

### Qualitative Benefits
- **Consistency**: All scripts use identical logging format
- **Reliability**: Shared functions thoroughly tested
- **Flexibility**: Support for JSON/structured output when needed
- **Documentation**: Single point of reference for logging patterns

## Risk Mitigation

### High-Risk Scripts
Scripts with custom logging logic or unusual patterns:
- Manual review required
- Conservative migration (minimal changes)
- Extra testing before deployment

### Medium-Risk Scripts
Scripts with standard logging:
- Automated migration possible
- Standard testing sufficient
- Phased rollout acceptable

### Low-Risk Scripts
Simple scripts with basic logging:
- Automated migration with confidence
- Quick testing sufficient
- Batch deployment acceptable

## Monitoring & Alerts

After each phase, monitor:

```bash
# Check for migration-related failures
grep -r "command not found.*log_info" logs/

# Monitor script execution times
for script in scripts/*/*; do
    time bash "$script" --dry-run 2>&1 | tail -1
done

# Verify logging output format
bash script.sh 2>&1 | head -20
```

## Team Responsibilities

### Development Team
- Review migration strategy
- Test migrated scripts in local environment
- Report any issues or edge cases

### CI/CD Team
- Validate migration in CI/CD pipeline
- Run full test suite after each phase
- Sign off before production rollout

### Operations Team
- Test in staging environment
- Prepare rollout procedure
- Monitor production after deployment

### Documentation Team
- Update script documentation
- Record any deviations from standard
- Create runbooks for common issues

## Success Criteria

- [ ] All 196 scripts successfully migrated
- [ ] No regression in script functionality
- [ ] Logging output consistent across all scripts
- [ ] Startup performance maintained or improved
- [ ] Team confident with shared module approach

## Timeline

| Phase | Duration | Scripts | Status |
|-------|----------|---------|--------|
| Foundation | Week 1 | 3 | ✅ Complete |
| Phase 2 | Week 2 | 19 | 📋 Planned |
| Phase 3 | Week 3 | 32 | 📋 Planned |
| Phase 4 | Week 4 | 142 | 📋 Planned |
| **Total** | **1 Month** | **196** | 📋 In Progress |

## Related Resources

- [Shared Logging Module](../../apps/_shared/test.sh)
- [Script Development Guide](../../DEPLOYMENT_EXECUTION_PLAN.md)
- [GitHub Issue #1986](https://github.com/kushin77/code-server/issues/1986)

## Next Steps

1. **Immediate**: Review and approve this strategy
2. **This Week**: Start with _common scripts (Phase 2)
3. **Next Week**: CI/CD scripts (Phase 3)
4. **Following Week**: Ops scripts (Phase 4)
5. **Final Week**: Remaining scripts (Phase 5)

---

**Status**: Strategy Document Ready  
**Target Completion**: 4 weeks  
**Contact**: DevOps Team
