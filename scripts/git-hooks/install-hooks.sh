#!/usr/bin/env bash
###############################################################################
# @file scripts/git-hooks/install-hooks.sh
# @module git-hooks
# @description Install pre-commit hooks for development
# @governance GOV-002: Enforce script quality standards
# @author Infrastructure Audit Bot
# @date 2026-04-28
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GIT_HOOKS_DIR="${REPO_ROOT}/.git/hooks"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[!]${NC} $*"
}

###############################################################################
# Main hook installation
###############################################################################
main() {
  log_info "Installing pre-commit hooks..."
  
  # Create hooks directory if it doesn't exist
  if [[ ! -d "$GIT_HOOKS_DIR" ]]; then
    mkdir -p "$GIT_HOOKS_DIR"
  fi
  
  # Install pre-commit-trap-handler-check hook
  local hook_source="${SCRIPT_DIR}/pre-commit-trap-handler-check"
  local hook_dest="${GIT_HOOKS_DIR}/pre-commit"
  
  if [[ ! -f "$hook_source" ]]; then
    log_warn "Hook source not found: $hook_source"
    return 1
  fi
  
  # Check if pre-commit hook already exists
  if [[ -f "$hook_dest" ]]; then
    if grep -q "pre-commit-trap-handler-check" "$hook_dest"; then
      log_info "Trap handler check already installed"
    else
      # Append to existing hook
      log_info "Appending trap handler check to existing pre-commit hook..."
      echo "" >> "$hook_dest"
      echo "# Trap handler validation" >> "$hook_dest"
      cat "$hook_source" >> "$hook_dest"
    fi
  else
    # Create new hook
    log_info "Creating new pre-commit hook..."
    cp "$hook_source" "$hook_dest"
  fi
  
  # Make hook executable
  chmod +x "$hook_dest"
  
  log_success "Pre-commit hooks installed successfully!"
  log_info "Hooks will enforce:"
  echo "  - Bash scripts must have trap handlers"
  echo "  - Error handling validation on commit"
  
  return 0
}

main
