#!/usr/bin/env bash
###############################################################################
# @file        scripts/_common/enforce-init-sourcing.sh
# @module      common/enforce-init-sourcing
# @description Enforce SSOT by ensuring all scripts source _common/init.sh
# @governance  GOV-002: All scripts MUST source init.sh for IaC compliance
# @automation  P3 #1533: Centralized configuration and logging
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

# Counters for reporting
FIXED=0
SKIPPED=0
ERRORS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Fix a single script by adding init.sh sourcing
fix_script() {
  local script_file="$1"
  local relative_depth="$2"  # How many levels deep from repo root

  # Skip if already sources init.sh
  if grep -q "source.*init\.sh\|source.*_common/init\.sh\|source.*_base-config" "$script_file"; then
    log_warn "Already sources init.sh: $(basename "$script_file")"
    SKIPPED+=1
    return 0
  fi

  # Build relative path to init.sh based on script depth
  local init_path="../"
  for ((i=1; i<relative_depth; i++)); do
    init_path="../$init_path"
  done
  init_path="${init_path}_common/init.sh"

  log_info "Fixing: $(basename "$script_file")"

  # Find where to insert the source statement (after set -euo pipefail)
  local temp_file="${script_file}.tmp"
  local inserted=0

  {
    while IFS= read -r line; do
      echo "$line"
      
      # After set -euo pipefail, insert init.sh sourcing
      if [[ "$line" =~ ^set\ -euo\ pipefail && $inserted -eq 0 ]]; then
        echo ""
        echo "# Source canonical configuration (SSOT)"
        echo "source \"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")/$init_path\" && pwd)\""
        inserted=1
      fi
    done < "$script_file"
  } > "$temp_file"

  if [ $inserted -eq 1 ]; then
    mv "$temp_file" "$script_file"
    FIXED+=1
    log_info "✅ Fixed: $(basename "$script_file")"
  else
    rm -f "$temp_file"
    log_error "Could not find insertion point in: $(basename "$script_file")"
    ERRORS+=1
    return 1
  fi
}

# Process all scripts recursively
process_scripts_dir() {
  local dir="$1"
  local depth="${2:-1}"

  while IFS= read -r script_file; do
    # Skip backup directories
    if [[ "$script_file" =~ .backups ]]; then
      continue
    fi
    
    # Skip if already sources init.sh
    if grep -q "source.*init\.sh\|source.*_common/init\.sh\|source.*_base-config" "$script_file"; then
      continue
    fi

    fix_script "$script_file" "$depth"
  done < <(find "$dir" -maxdepth 1 -name "*.sh" -type f)

  # Recurse into subdirectories
  while IFS= read -r subdir; do
    process_scripts_dir "$subdir" "$((depth + 1))"
  done < <(find "$dir" -maxdepth 1 -type d ! -name ".*" ! -name "_common" ! -name ".backups")
}

# Main
main() {
  echo ""
  echo "==================================================================="
  echo "Enforcing SSOT: Ensuring all scripts source _common/init.sh"
  echo "==================================================================="
  echo ""

  process_scripts_dir "$SCRIPTS_DIR" 1

  echo ""
  echo "==================================================================="
  echo "Summary:"
  echo "  ✅ Fixed:   $FIXED"
  echo "  ⏭️  Skipped: $SKIPPED"
  echo "  ❌ Errors:  $ERRORS"
  echo "==================================================================="
  echo ""

  if [ $ERRORS -eq 0 ]; then
    log_info "SSOT enforcement complete!"
    return 0
  else
    log_error "Some scripts had errors. Please review manually."
    return 1
  fi
}

main "$@"
