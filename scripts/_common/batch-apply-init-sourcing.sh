#!/usr/bin/env bash
###############################################################################
# @file        scripts/_common/batch-apply-init-sourcing.sh
# @description Automatically apply init.sh sourcing to all remaining scripts
# @governance  GOV-002: Enforce SSOT compliance
###############################################################################

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

FIXED=0
SKIPPED=0

# Get relative path depth from script to repo root
get_depth() {
  local script="$1"
  local depth=1
  while [[ "$script" == */scripts/* ]]; do
    script="${script%/*}"
    depth+=1
  done
  echo $depth
}

# Fix a script by adding init.sh sourcing
fix_script() {
  local script="$1"
  local depth="$(get_depth "$script")"
  
  # Build relative path to init.sh
  local init_path="../"
  for ((i=2; i<depth; i++)); do
    init_path="../$init_path"
  done
  init_path="${init_path}_common/init.sh"

  # Skip if already has init.sh sourcing
  if grep -q "source.*init\.sh\|source.*_common/init\.sh" "$script"; then
    SKIPPED+=1
    return 0
  fi

  # Skip test/example scripts
  if [[ "$script" =~ (test|example|template|\.backups) ]]; then
    SKIPPED+=1
    return 0
  fi

  echo "[FIXING] $(basename "$script")"

  # Create temp file with modifications
  local temp="${script}.tmp"
  {
    local found_shebang=0
    local found_set=0
    
    while IFS= read -r line; do
      echo "$line"
      
      # After finding set -euo pipefail, add SCRIPT_DIR, REPO_ROOT, and init.sh sourcing
      if [[ "$line" =~ ^set\ -euo\ pipefail && $found_set -eq 0 ]]; then
        echo ""
        echo "SCRIPT_DIR=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)\""
        echo "REPO_ROOT=\"\$(cd \"\${SCRIPT_DIR}/$init_path\" && pwd)\""
        echo ""
        echo "# Source canonical configuration (SSOT)"
        echo "source \"\${SCRIPT_DIR}/$init_path\""
        found_set=1
      fi
    done < "$script"
  } > "$temp"

  mv "$temp" "$script"
  FIXED+=1
}

# Find and fix all scripts
echo "Batch applying init.sh sourcing to all scripts..."
echo ""

while IFS= read -r script; do
  fix_script "$script"
done < <(find "${SCRIPTS_DIR}" -name "*.sh" -type f ! -path "*/.backups/*")

echo ""
echo "============================================"
echo "Fixed: $FIXED"
echo "Skipped: $SKIPPED"
echo "============================================"
