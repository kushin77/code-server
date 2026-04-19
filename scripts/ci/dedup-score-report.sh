#!/usr/bin/env bash
# @file        scripts/ci/dedup-score-report.sh
# @module      governance/deduplication
# @description Calculate deduplication score for PR/branch (0-100 scale)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Metrics
TOTAL_CHECKS=0
CHECKS_PASSED=0
DUPLICATE_PATTERNS=()
REFACTORING_CANDIDATES=()
SCORE=100

# ============================================================================
# CHECK 1: Logging patterns use canonical helpers
# ============================================================================
check_logging_patterns() {
  echo "[1/5] Checking logging patterns..."
  
  local violations=0
  while IFS= read -r file; do
    [[ ! -f "$file" ]] && continue
    
    if grep -E 'echo\s+"(ERROR|WARN|INFO|DEBUG):' "$file" &>/dev/null; then
      ((violations++))
      DUPLICATE_PATTERNS+=("$file: uses echo instead of log_* helpers")
      REFACTORING_CANDIDATES+=("$file: replace echo logging with canonical log_* calls")
    fi
  done < <(find "$SCRIPT_DIR" -type f -name "*.sh" ! -path "*/ci/*" ! -path "*/test/*" 2>/dev/null || true)
  
  ((TOTAL_CHECKS++))
  if [[ $violations -eq 0 ]]; then
    ((CHECKS_PASSED++))
  else
    SCORE=$((SCORE - 20))
  fi
  
  return 0
}

# ============================================================================
# CHECK 2: Error handling uses canonical die function
# ============================================================================
check_error_handling() {
  echo "[2/5] Checking error handling patterns..."
  
  local violations=0
  while IFS= read -r file; do
    [[ ! -f "$file" ]] && continue
    
    if grep -E '(exit\s+1|return\s+1)\s*$' "$file" &>/dev/null && \
       ! grep -q "die\|log_fatal" "$file"; then
      ((violations++))
      DUPLICATE_PATTERNS+=("$file: uses direct exit/return instead of die")
      REFACTORING_CANDIDATES+=("$file: replace direct exit 1 with die function")
    fi
  done < <(find "$SCRIPT_DIR" -type f -name "*.sh" ! -path "*/ci/*" ! -path "*/test/*" 2>/dev/null || true)
  
  ((TOTAL_CHECKS++))
  if [[ $violations -eq 0 ]]; then
    ((CHECKS_PASSED++))
  else
    SCORE=$((SCORE - 15))
  fi
  
  return 0
}

# ============================================================================
# CHECK 3: Variable validation uses canonical require_var
# ============================================================================
check_variable_validation() {
  echo "[3/5] Checking variable validation patterns..."
  
  local violations=0
  while IFS= read -r file; do
    [[ ! -f "$file" ]] && continue
    
    if grep -E '\[\s*-z\s+"\$' "$file" &>/dev/null && \
       ! grep -q "require_var" "$file"; then
      ((violations++))
      DUPLICATE_PATTERNS+=("$file: uses manual [ -z ] instead of require_var")
      REFACTORING_CANDIDATES+=("$file: replace manual [ -z ] checks with require_var")
    fi
  done < <(find "$SCRIPT_DIR" -type f -name "*.sh" ! -path "*/ci/*" ! -path "*/test/*" 2>/dev/null || true)
  
  ((TOTAL_CHECKS++))
  if [[ $violations -eq 0 ]]; then
    ((CHECKS_PASSED++))
  else
    SCORE=$((SCORE - 10))
  fi
  
  return 0
}

# ============================================================================
# CHECK 4: Compose files use env vars instead of hardcoded values
# ============================================================================
check_compose_patterns() {
  echo "[4/5] Checking docker-compose patterns..."
  
  local violations=0
  while IFS= read -r file; do
    [[ ! -f "$file" ]] && continue
    
    # Look for hardcoded ports that should be parameterized
    if grep -E 'ports:\s*"[0-9]+:' "$file" &>/dev/null; then
      ((violations++))
      DUPLICATE_PATTERNS+=("$file: hardcoded ports found")
      REFACTORING_CANDIDATES+=("$file: parameterize ports using \${VAR:-default} syntax")
    fi
    
    # Look for hardcoded environment values
    if grep -E '(DOMAIN|HOST|PORT)=[-0-9.a-z]+' "$file" | grep -v '\${' &>/dev/null; then
      ((violations++))
      DUPLICATE_PATTERNS+=("$file: hardcoded domain/host/port values")
    fi
  done < <(find "$REPO_ROOT" -name "docker-compose*.yml" -o -name "*compose*.yaml" 2>/dev/null || true)
  
  ((TOTAL_CHECKS++))
  if [[ $violations -eq 0 ]]; then
    ((CHECKS_PASSED++))
  else
    SCORE=$((SCORE - 15))
  fi
  
  return 0
}

# ============================================================================
# CHECK 5: No duplicate function definitions
# ============================================================================
check_duplicate_functions() {
  echo "[5/5] Checking for duplicate function definitions..."
  
  local violations=0
  local temp_funcs=$(mktemp)
  trap "rm -f $temp_funcs" EXIT
  
  while IFS= read -r file; do
    [[ ! -f "$file" ]] && continue
    
    # Extract function names
    grep -E '^[a-z_]+\s*\(\)\s*\{' "$file" | sed 's/^\([a-z_]*\).*/\1/' >> "$temp_funcs" 2>/dev/null || true
  done < <(find "$SCRIPT_DIR" -type f -name "*.sh" ! -path "*/ci/*" ! -path "*/test/*" 2>/dev/null || true)
  
  # Check for duplicates
  if [[ -f "$temp_funcs" ]]; then
    violations=$(sort "$temp_funcs" | uniq -d | wc -l || echo 0)
  fi
  
  ((TOTAL_CHECKS++))
  if [[ $violations -eq 0 ]]; then
    ((CHECKS_PASSED++))
  else
    SCORE=$((SCORE - 25))
    DUPLICATE_PATTERNS+=("$violations duplicate function names found across scripts")
  fi
  
  return 0
}

# ============================================================================
# Score interpretation
# ============================================================================
interpret_score() {
  if [[ $SCORE -ge 90 ]]; then
    echo "EXCELLENT"
  elif [[ $SCORE -ge 80 ]]; then
    echo "GOOD"
  elif [[ $SCORE -ge 70 ]]; then
    echo "ACCEPTABLE"
  elif [[ $SCORE -ge 60 ]]; then
    echo "NEEDS_IMPROVEMENT"
  else
    echo "POOR"
  fi
}

# ============================================================================
# Main execution
# ============================================================================
echo "=== Deduplication Score Report ==="
echo ""

check_logging_patterns
check_error_handling
check_variable_validation
check_compose_patterns
check_duplicate_functions

echo ""
echo "=== Results ==="
echo "Score: $SCORE / 100"
echo "Level: $(interpret_score)"
echo "Checks Passed: $CHECKS_PASSED / $TOTAL_CHECKS"
echo ""

if [[ ${#DUPLICATE_PATTERNS[@]} -gt 0 ]]; then
  echo "Duplicates Found:"
  for pattern in "${DUPLICATE_PATTERNS[@]}"; do
    echo "  - $pattern"
  done
  echo ""
fi

if [[ ${#REFACTORING_CANDIDATES[@]} -gt 0 ]]; then
  echo "Refactoring Candidates:"
  for candidate in "${REFACTORING_CANDIDATES[@]}"; do
    echo "  - $candidate"
  done
  echo ""
fi

# Output metrics for CI
cat > /tmp/dedup-score.txt <<EOF
DEDUP_SCORE=$SCORE
DEDUP_LEVEL=$(interpret_score)
DUPLICATE_COUNT=${#DUPLICATE_PATTERNS[@]}
REFACTORING_CANDIDATES=${#REFACTORING_CANDIDATES[@]}
CHECKS_PASSED=$CHECKS_PASSED
EOF

cat /tmp/dedup-score.txt

# Fail if score is too low
if [[ $SCORE -lt 60 ]]; then
  echo ""
  echo "ERROR: Deduplication score too low. Score must be >= 60 to merge."
  exit 1
fi

exit 0
