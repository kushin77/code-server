#!/usr/bin/env bash
# @file        scripts/ci/validate-dedup-registry.sh
# @module      governance/deduplication
# @description Validate canonical helper registry against actual script usage
#
# Phase 2: Registry Validation — Ensures registry is complete and patterns are discoverable
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source logging utilities
source "$SCRIPT_DIR/../_common/logging.sh" || {
  echo "ERROR: Cannot source logging utilities" >&2
  exit 1
}

log_info "Starting canonical helper registry validation (Phase 2)"

# ==============================================================================
# Phase 1: Detect Unregistered Helpers
# ==============================================================================

log_info "Phase 1: Scanning for unregistered helper functions..."

UNREGISTERED=0
FOUND_HELPERS=()

# Look for function definitions in scripts
while IFS= read -r script_file; do
  while IFS= read -r func_def; do
    # Extract function name
    func_name=$(echo "$func_def" | sed -E 's/^[^a-zA-Z_]*([a-zA-Z_][a-zA-Z0-9_]*).*$/\1/')
    
    # Check if function is registered in policy
    if ! grep -q "\"$func_name\"" "$PROJECT_ROOT/docs/DEDUPLICATION-POLICY.md" 2>/dev/null; then
      if [[ "$func_name" != "main" ]] && [[ "$func_name" != "test" ]] && [[ ! "$func_name" =~ ^test_ ]]; then
        log_warn "Unregistered function: $func_name in $script_file"
        UNREGISTERED=$((UNREGISTERED + 1))
        FOUND_HELPERS+=("$func_name")
      fi
    fi
  done < <(grep -E "^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)" "$script_file" 2>/dev/null || true)
done < <(find "$PROJECT_ROOT/scripts" -name "*.sh" -type f 2>/dev/null | head -20)

if [ $UNREGISTERED -gt 0 ]; then
  log_warn "Found $UNREGISTERED potentially unregistered helpers"
fi

# ==============================================================================
# Phase 2: Detect Pattern Violations in Active Scripts
# ==============================================================================

log_info "Phase 2: Validating canonical patterns in active scripts..."

VIOLATIONS=0

# Check for unregistered logging patterns
if grep -r "^\s*echo " "$PROJECT_ROOT/scripts/_common" 2>/dev/null | grep -v "log_"; then
  log_warn "Common library contains unregistered echo patterns"
  VIOLATIONS=$((VIOLATIONS + 1))
fi

# Check for unregistered error handling
if grep -r "exit 1" "$PROJECT_ROOT/scripts/_common" 2>/dev/null | grep -v "die\|trap"; then
  log_warn "Common library contains unregistered exit patterns"
  VIOLATIONS=$((VIOLATIONS + 1))
fi

# ==============================================================================
# Phase 3: Validate Registry Completeness
# ==============================================================================

log_info "Phase 3: Validating registry completeness..."

REGISTRY_COMPLETENESS=100

# Check for documented examples in registry
DOCUMENTED_PATTERNS=$(grep -c "usage_examples" "$PROJECT_ROOT/docs/DEDUPLICATION-POLICY.md" || true)
TOTAL_HELPERS=$(grep -c "\"canonical_function\"" "$PROJECT_ROOT/docs/DEDUPLICATION-POLICY.md" || true)

if [ "$DOCUMENTED_PATTERNS" -lt "$TOTAL_HELPERS" ]; then
  MISSING=$((TOTAL_HELPERS - DOCUMENTED_PATTERNS))
  log_warn "Registry has $MISSING patterns without documented examples"
  REGISTRY_COMPLETENESS=$((100 - (MISSING * 5)))
fi

# ==============================================================================
# Phase 4: Validate Policy File Structure
# ==============================================================================

log_info "Phase 4: Validating policy file structure..."

STRUCTURE_VALID=true

# Check for required top-level keys
for key in "deduplication_hints" "enforcement_rules" "workspace_defaults"; do
  if ! grep -q "\"$key\"" "$PROJECT_ROOT/config/code-server/DEDUP-HINTS.json" 2>/dev/null; then
    log_warn "DEDUP-HINTS.json missing required key: $key"
    STRUCTURE_VALID=false
  fi
done

# Validate JSON syntax
if ! jq empty "$PROJECT_ROOT/config/code-server/DEDUP-HINTS.json" 2>/dev/null; then
  log_error "DEDUP-HINTS.json has invalid JSON syntax"
  STRUCTURE_VALID=false
fi

# ==============================================================================
# Phase 5: Generate Validation Report
# ==============================================================================

log_info "Phase 5: Generating validation report..."

REPORT_FILE="/tmp/dedup-registry-validation.txt"
{
  echo "=========================================="
  echo "Canonical Helper Registry Validation"
  echo "=========================================="
  echo ""
  echo "Scan Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Registry File: docs/DEDUPLICATION-POLICY.md"
  echo "Hints File: config/code-server/DEDUP-HINTS.json"
  echo ""
  echo "Phase 1: Unregistered Helpers"
  echo "  Found: $UNREGISTERED potentially unregistered functions"
  if [ $UNREGISTERED -gt 0 ]; then
    echo "  Examples: ${FOUND_HELPERS[*]}"
  fi
  echo ""
  echo "Phase 2: Pattern Violations"
  echo "  Found: $VIOLATIONS violations in common library"
  echo ""
  echo "Phase 3: Registry Completeness"
  echo "  Score: $REGISTRY_COMPLETENESS/100"
  echo "  Documented Patterns: $DOCUMENTED_PATTERNS/$TOTAL_HELPERS"
  echo ""
  echo "Phase 4: Policy File Structure"
  echo "  Valid: $([ "$STRUCTURE_VALID" = true ] && echo 'YES' || echo 'NO')"
  echo ""
  echo "Overall Assessment"
  if [ $VIOLATIONS -eq 0 ] && [ "$STRUCTURE_VALID" = true ] && [ $REGISTRY_COMPLETENESS -ge 90 ]; then
    echo "  Status: ✅ PASS - Registry is complete and consistent"
  elif [ $VIOLATIONS -eq 0 ] && [ "$STRUCTURE_VALID" = true ]; then
    echo "  Status: ⚠️  WARNING - Registry needs documentation updates"
  else
    echo "  Status: ❌ FAIL - Registry requires remediation"
  fi
  echo "=========================================="
} | tee "$REPORT_FILE"

log_info "Validation report saved to $REPORT_FILE"

# Exit with appropriate code
if [ $VIOLATIONS -eq 0 ] && [ "$STRUCTURE_VALID" = true ]; then
  log_info "Registry validation PASSED ✅"
  exit 0
else
  log_error "Registry validation FAILED ❌"
  exit 1
fi
