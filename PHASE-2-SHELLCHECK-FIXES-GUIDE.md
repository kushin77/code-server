# P0 #1604 Phase 2: Shellcheck Violations - Resolution Guide

**Date**: April 23, 2026  
**Status**: DOCUMENTED & READY FOR EXECUTION  
**Related Issue**: #1600  
**Part of**: P0 #1604 CRITICAL Auto-Issue Creation System Diagnostics

---

## Overview

Phase 2 requires fixing shellcheck violations in 6 scripts that are blocking the governance workflow. This document provides the exact fixes needed.

## Affected Scripts

1. **scripts/_common/issue-create-unified.sh** (SC2145, SC2199)
2. **scripts/ci/check-error-handling-consistency.sh**
3. **scripts/error-triage-engine.sh**
4. **scripts/infrastructure/fix-ssl-protocol-error.sh**
5. **scripts/ops/error-fingerprint-triage.sh**
6. **scripts/triage/generate-weekly-error-triage-report.sh**

## Violation Types & Fixes

### SC2168 - `local` in script scope (ERROR)
**Problem**: Using `local` keyword outside functions
```bash
# ❌ WRONG
local ARRAY=()
```
**Solution**: Remove `local` at script scope
```bash
# ✅ CORRECT
ARRAY=()
```

### SC2199 - Array subscript out of range (ERROR)
**Problem**: Using `@` in wrong context
```bash
# ❌ WRONG
echo "${array[@]}"  # in arithmetic context
```
**Solution**: Use `*` or proper array iteration
```bash
# ✅ CORRECT
echo "${array[*]}"
for item in "${array[@]}"; do ...; done
```

### SC2145 - Operator precedence (ERROR)
**Problem**: Mixing strings and arrays in arithmetic
```bash
# ❌ WRONG
RESULT=$((${ARRAY[@]} + 5))
```
**Solution**: Extract value first
```bash
# ✅ CORRECT
VALUE="${ARRAY[0]}"
RESULT=$((VALUE + 5))
```

### SC1072/SC1073 - Quote parsing errors (ERROR)
**Problem**: Unescaped quotes in strings
```bash
# ❌ WRONG
MESSAGE="Failed: $ERROR_MSG with "quotes""
```
**Solution**: Escape internal quotes
```bash
# ✅ CORRECT
MESSAGE="Failed: $ERROR_MSG with \"quotes\""
```

## Implementation Steps

1. **scripts/_common/issue-create-unified.sh**
   - Line 40: Remove `local` from `declare -A PRIORITY_LABELS=(...)`
   - Line 48: Remove `local` from `declare -A TYPE_LABELS=(...)`
   - Verify array access uses proper syntax

2. **scripts/ci/check-error-handling-consistency.sh**
   - Check for `local` declarations at script scope
   - Fix any array subscript issues

3. **scripts/error-triage-engine.sh**
   - Fix string/array mixing in conditions
   - Escape any embedded quotes

4. **scripts/infrastructure/fix-ssl-protocol-error.sh**
   - Review quote escaping
   - Fix any array operations

5. **scripts/ops/error-fingerprint-triage.sh**
   - Remove script-scope `local` declarations
   - Fix array iteration syntax

6. **scripts/triage/generate-weekly-error-triage-report.sh**
   - Correct array subscripting
   - Fix quote parsing

## Validation

After fixes, run:
```bash
# Check all scripts individually
for script in scripts/_common/issue-create-unified.sh \
              scripts/ci/check-error-handling-consistency.sh \
              scripts/error-triage-engine.sh \
              scripts/infrastructure/fix-ssl-protocol-error.sh \
              scripts/ops/error-fingerprint-triage.sh \
              scripts/triage/generate-weekly-error-triage-report.sh; do
  shellcheck -x --severity=error "$script" || echo "FAIL: $script"
done

# Run full governance check
bash scripts/ci/run-governance-checks.sh
```

## Expected Outcome

- ✅ All shellcheck errors resolved (exit code 0)
- ✅ Governance workflow unblocked
- ✅ Issue creation system operational
- ✅ CI/CD pipeline operational

## Timeline

- Phase 1: ✅ COMPLETE (integrations label, TruffleHog 2.2.1, IDE_SESSION_LB_SECRET)
- Phase 2: 📋 DOCUMENTED (this file - ready for automated execution)
- Phase 3: ⏳ QUEUED (Unicode handling, API 404 investigation)

---

**Next Session Action**: Execute Phase 2 fixes by applying corrections to 6 affected scripts, then re-run governance validation to unblock CI/CD pipeline.
