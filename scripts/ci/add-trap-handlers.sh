#!/bin/bash
###############################################################################
# @file        scripts/ci/add-trap-handlers.sh
# @module      ci/add-trap-handlers
# @description Automatically add ERR and EXIT trap handlers to scripts lacking them
# @governance  GOV-002: All scripts MUST have proper error handling
# @author      Infrastructure Audit Bot
# @date        2026-04-28
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source logging functions
source "${SCRIPT_DIR}/../_common/init.sh" 2>/dev/null || {
  log_info() { echo "[INFO] $*"; }
  log_error() { echo "[ERROR] $*" >&2; }
  log_success() { echo "[SUCCESS] $*"; }
}

# Count of scripts updated
UPDATED=0
SKIPPED=0
FAILED=0

# Standard trap handler block to inject
readonly TRAP_BLOCK='
# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap '"'"'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1'"'"' ERR
trap '"'"'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true'"'"' EXIT
'

###############################################################################
# Function: add_trap_handlers
# Purpose: Add trap handlers to a script if missing
###############################################################################
add_trap_handlers() {
  local script_path="$1"
  
  # Check if script already has trap handlers
  if grep -q "trap.*ERR\|trap.*EXIT" "$script_path"; then
    SKIPPED+=1
    return 0
  fi
  
  # Don't add to non-executable or non-bash scripts
  if ! head -1 "$script_path" | grep -q "bash"; then
    SKIPPED+=1
    return 0
  fi
  
  # Find where to insert (after set -euo pipefail and initial comments)
  local line_num=$(grep -n "^set -euo pipefail\|^set -e\|^[^#]" "$script_path" | head -1 | cut -d: -f1)
  
  if [ -z "$line_num" ]; then
    FAILED+=1
    log_error "Could not find insertion point in $script_path"
    return 1
  fi
  
  # Create temp file with trap handlers inserted
  local temp_file=$(mktemp)
  
  # Copy file up to insertion point
  head -n "$line_num" "$script_path" > "$temp_file"
  
  # Add blank line if needed
  if ! sed -n "${line_num}p" "$script_path" | grep -q "^$"; then
    echo "" >> "$temp_file"
  fi
  
  # Add trap handler block
  echo "$TRAP_BLOCK" >> "$temp_file"
  
  # Add rest of file
  tail -n +$((line_num + 1)) "$script_path" >> "$temp_file"
  
  # Replace original with new version
  if mv "$temp_file" "$script_path"; then
    UPDATED+=1
    log_success "Added trap handlers to $script_path"
    return 0
  else
    FAILED+=1
    log_error "Failed to update $script_path"
    rm -f "$temp_file"
    return 1
  fi
}

###############################################################################
# Main: Process all scripts
###############################################################################

log_info "Starting automated trap handler injection..."

# Process ops directory
log_info "Processing scripts/ops/..."
while IFS= read -r script; do
  add_trap_handlers "$script"
done < <(find "${REPO_ROOT}/scripts/ops" -name "*.sh" -type f)

# Process ci directory
log_info "Processing scripts/ci/..."
while IFS= read -r script; do
  add_trap_handlers "$script"
done < <(find "${REPO_ROOT}/scripts/ci" -name "*.sh" -type f)

# Process edge-agent directory
log_info "Processing scripts/edge-agent/..."
while IFS= read -r script; do
  add_trap_handlers "$script"
done < <(find "${REPO_ROOT}/scripts/edge-agent" -name "*.sh" -type f 2>/dev/null || true)

log_success "Trap handler injection complete!"
log_info "Updated: $UPDATED scripts"
log_info "Skipped: $SKIPPED scripts (already have handlers)"
log_info "Failed: $FAILED scripts"

exit 0
