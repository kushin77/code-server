#!/usr/bin/env bash
# @file        scripts/ci/detect-duplicate-helpers.sh
# @module      governance/deduplication
# @description Detect duplicate helper functions and logging patterns across shell scripts (CI gate)
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Canonical helper locations
CANONICAL_LOGGING="${SCRIPT_DIR}/_common/logging.sh"
CANONICAL_UTILS="${SCRIPT_DIR}/_common/utils.sh"
CANONICAL_CONFIG="${SCRIPT_DIR}/_common/config.sh"

# Tracking
DUPLICATES_FOUND=0
HIGH_CONFIDENCE_DUPLICATES=()
WARNINGS=()

# Helper: Log a finding
log_duplicate() {
  local file="$1"
  local pattern="$2"
  local canonical="$3"
  local confidence="$4"
  
  echo -e "${RED}DUPLICATE${NC} [$confidence] in $file:"
  echo "  Pattern: $pattern"
  echo "  Canonical: $canonical"
  echo ""
  
  if [[ "$confidence" == "HIGH" ]]; then
    ((DUPLICATES_FOUND++))
    HIGH_CONFIDENCE_DUPLICATES+=("$file: $pattern → $canonical")
  fi
}

log_warning() {
  local file="$1"
  local message="$2"
  
  echo -e "${YELLOW}WARNING${NC} in $file:"
  echo "  $message"
  echo ""
  
  WARNINGS+=("$file: $message")
}

# ============================================================================
# PHASE 1: Detect duplicate logging patterns
# ============================================================================
echo "=== Phase 1: Detecting duplicate logging patterns ==="

# Find all shell scripts
while IFS= read -r file; do
  [[ ! -f "$file" ]] && continue
  
  # Pattern 1: echo with ERROR/WARN/INFO prefix (should use log_* instead)
  if grep -E 'echo\s+"(ERROR|WARN|INFO|DEBUG):' "$file" &>/dev/null; then
    log_duplicate "$file" 'echo "ERROR/WARN/INFO:..."' "$CANONICAL_LOGGING" "HIGH"
  fi
  
  # Pattern 2: printf with status messages (should use log_* instead)
  if grep -E 'printf\s+".*[Ee]rror|[Ff]ail|[Dd]one' "$file" &>/dev/null && \
     ! grep -q "log_" "$file"; then
    log_duplicate "$file" 'printf "error/fail/done message"' "$CANONICAL_LOGGING" "MEDIUM"
  fi
  
done < <(find "$SCRIPT_DIR" -type f -name "*.sh" ! -path "*/_template.sh" ! -path "*/ci/*")

# ============================================================================
# PHASE 2: Detect duplicate error handling patterns
# ============================================================================
echo "=== Phase 2: Detecting duplicate error handling patterns ==="

while IFS= read -r file; do
  [[ ! -f "$file" ]] && continue
  
  # Pattern 1: exit 1 directly without cleanup (should use die)
  if grep -E '(exit\s+1|return\s+1)\s*$' "$file" &>/dev/null && \
     ! grep -q "die\|log_fatal" "$file"; then
    log_warning "$file" "Direct 'exit 1' found — should use 'die' from $CANONICAL_UTILS"
  fi
  
done < <(find "$SCRIPT_DIR" -type f -name "*.sh" ! -path "*/ci/*")

# ============================================================================
# PHASE 3: Detect duplicate utility patterns
# ============================================================================
echo "=== Phase 3: Detecting duplicate utility patterns ==="

while IFS= read -r file; do
  [[ ! -f "$file" ]] && continue
  
  # Pattern: Manual variable validation (should use require_var)
  if grep -E '\[\s*-z\s+"\$\{?[A-Z_]+' "$file" &>/dev/null && \
     ! grep -q "require_var" "$file"; then
    log_warning "$file" "Manual variable validation detected — should use 'require_var' from $CANONICAL_UTILS"
  fi
  
  # Pattern: Manual command check (should use require_command)
  if grep -E 'which\s+[a-z-]+|command\s+-v' "$file" &>/dev/null && \
     ! grep -q "require_command" "$file"; then
    log_warning "$file" "Manual 'which' or 'command -v' detected — should use 'require_command' from $CANONICAL_UTILS"
  fi
  
done < <(find "$SCRIPT_DIR" -type f -name "*.sh" ! -path "*/ci/*")

# ============================================================================
# PHASE 4: Detect duplicate retry logic
# ============================================================================
echo "=== Phase 4: Detecting duplicate retry logic ==="

while IFS= read -r file; do
  [[ ! -f "$file" ]] && continue
  
  # Pattern: Manual retry loop (should use retry function)
  if grep -E 'for\s+[a-z]+\s+in.*\{1,5\}|while.*[Rr]etr' "$file" &>/dev/null && \
     ! grep -q "retry" "$file"; then
    log_warning "$file" "Manual retry loop detected — should use 'retry' from $CANONICAL_UTILS"
  fi
  
done < <(find "$SCRIPT_DIR" -type f -name "*.sh" ! -path "*/ci/*")

# ============================================================================
# PHASE 5: Summary and exit
# ============================================================================
echo ""
echo "=== Deduplication Detection Summary ==="
echo ""

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo -e "${YELLOW}Warnings: ${#WARNINGS[@]}${NC}"
  for warning in "${WARNINGS[@]}"; do
    echo "  - $warning"
  done
  echo ""
fi

if [[ $DUPLICATES_FOUND -gt 0 ]]; then
  echo -e "${RED}HIGH-CONFIDENCE DUPLICATES: $DUPLICATES_FOUND${NC}"
  for dup in "${HIGH_CONFIDENCE_DUPLICATES[@]}"; do
    echo "  - $dup"
  done
  echo ""
  echo -e "${RED}ERROR: Duplication detected. Refactor to use canonical helpers.${NC}"
  exit 1
else
  echo -e "${GREEN}✓ No high-confidence duplicates detected${NC}"
  exit 0
fi
