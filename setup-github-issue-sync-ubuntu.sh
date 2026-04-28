#!/usr/bin/env bash
set -e
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# Ubuntu GitHub Issue Sync - Automated Setup Script
# ============================================================================
# 
# This script sets up GitHub issue sync on Ubuntu after Windows migration
# Prerequisites: bash, sudo access (for gh CLI installation)
#
# Usage: bash ./setup-github-issue-sync-ubuntu.sh
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_LOG="${SCRIPT_DIR}/github-sync-setup.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# UTILITIES
# ============================================================================

log_info() { echo -e "${BLUE}ℹ${NC} $*" | tee -a "$SETUP_LOG"; }
log_success() { echo -e "${GREEN}✓${NC} $*" | tee -a "$SETUP_LOG"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*" | tee -a "$SETUP_LOG"; }
log_error() { echo -e "${RED}✗${NC} $*" | tee -a "$SETUP_LOG"; }

check_command() {
  if command -v "$1" &> /dev/null; then
    log_success "$1 is installed"
    return 0
  else
    log_error "$1 is NOT installed"
    return 1
  fi
}

# ============================================================================
# STEP 1: CHECK PREREQUISITES
# ============================================================================

step_check_prerequisites() {
  log_info "Step 1: Checking prerequisites..."
  
  local missing=0
  
  check_command "bash" || missing=$((missing + 1))
  check_command "curl" || {
    log_warn "curl not installed (optional, can use apt without it)"
  }
  check_command "jq" || {
    log_warn "jq not installed (optional, needed for some GitHub API queries)"
  }
  
  [ $missing -eq 0 ] && log_success "Prerequisites check passed" || {
    log_warn "Some optional tools missing (non-blocking)"
  }
}

# ============================================================================
# STEP 2: INSTALL GITHUB CLI
# ============================================================================

step_install_gh_cli() {
  log_info "Step 2: Installing GitHub CLI..."
  
  if command -v gh &> /dev/null; then
    log_success "GitHub CLI already installed: $(gh --version)"
    return 0
  fi
  
  log_info "Installing gh CLI from official repository..."
  
  # For Ubuntu/Debian using apt
  if command -v apt &> /dev/null; then
    log_info "Adding GitHub CLI repository..."
    
    # Try with curl first, fall back to wget if needed
    if command -v curl &> /dev/null; then
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
    else
      log_info "curl not found, trying wget..."
      wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
    fi
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    
    log_info "Running apt update..."
    sudo apt-get update
    
    log_info "Installing gh package..."
    sudo apt-get install -y gh
    
    log_success "GitHub CLI installed: $(gh --version)"
  else
    log_error "apt not found - cannot auto-install"
    log_error "Please install gh manually: https://cli.github.com/"
    return 1
  fi
}

# ============================================================================
# STEP 3: AUTHENTICATE GITHUB CLI
# ============================================================================

step_authenticate_gh() {
  log_info "Step 3: Authenticating GitHub CLI..."
  
  if gh auth status &> /dev/null; then
    log_success "GitHub CLI already authenticated:"
    gh auth status
    return 0
  fi
  
  log_info "Starting interactive GitHub authentication..."
  log_info ""
  log_info "You will be prompted to:"
  log_info "  1. Choose 'GitHub.com' (not GitHub Enterprise)"
  log_info "  2. Choose 'HTTPS' for protocol"
  log_info "  3. Choose 'Paste an authentication token'"
  log_info "  4. Paste your fine-grained GitHub token"
  log_info ""
  log_warn "To generate a token:"
  log_warn "  1. Go to: https://github.com/settings/tokens?type=beta"
  log_warn "  2. Create a new fine-grained personal access token"
  log_warn "  3. Required scopes:"
  log_warn "     - repo:read, repo:write"
  log_warn "     - issues:read, issues:write"
  log_warn "     - pull_requests:read, pull_requests:write"
  log_warn "     - projects:read"
  log_info ""
  
  read -p "Press Enter to open GitHub authentication, or Ctrl+C to skip: " -t 30 || true
  
  gh auth login
  
  log_success "GitHub CLI authenticated:"
  gh auth status
}

# ============================================================================
# STEP 4: CONFIGURE ENVIRONMENT VARIABLES
# ============================================================================

step_configure_env() {
  log_info "Step 4: Configuring environment variables..."
  
  local shell_rc=""
  if [ -n "$BASH_VERSION" ]; then
    shell_rc="$HOME/.bashrc"
  elif [ -n "$ZSH_VERSION" ]; then
    shell_rc="$HOME/.zshrc"
  else
    shell_rc="$HOME/.bashrc"
  fi
  
  log_info "Using shell RC file: $shell_rc"
  
  # Check if already configured
  if grep -q "export GITHUB_REPO" "$shell_rc" 2>/dev/null; then
    log_success "Environment variables already configured in $shell_rc"
    grep "GITHUB_REPO\|GITHUB_OWNER" "$shell_rc" || true
  else
    log_info "Adding environment variables to $shell_rc..."
    
    cat >> "$shell_rc" << 'EOF'

# GitHub Configuration (added by setup-github-issue-sync-ubuntu.sh)
export GITHUB_REPO="kushin77/code-server"
export GITHUB_OWNER="kushin77"
# Note: GITHUB_TOKEN is managed by 'gh' CLI authentication
EOF
    
    log_success "Environment variables added to $shell_rc"
    log_info "Run: source $shell_rc (to apply in current shell)"
  fi
}

# ============================================================================
# STEP 5: VERIFY SETUP
# ============================================================================

step_verify_setup() {
  log_info "Step 5: Verifying setup..."
  
  local errors=0
  
  # Check gh CLI
  if ! check_command "gh"; then
    log_error "GitHub CLI not available"
    errors=$((errors + 1))
  fi
  
  # Check authentication
  if ! gh auth status &> /dev/null; then
    log_error "GitHub CLI not authenticated"
    errors=$((errors + 1))
  else
    log_success "GitHub CLI authenticated"
  fi
  
  # Check repository access
  if gh repo view kushin77/code-server &> /dev/null; then
    log_success "Can access kushin77/code-server repository"
  else
    log_error "Cannot access kushin77/code-server repository"
    errors=$((errors + 1))
  fi
  
  # Test issue listing
  if gh issue list --repo kushin77/code-server --limit 1 &> /dev/null; then
    log_success "Can list GitHub issues"
  else
    log_error "Cannot list GitHub issues (may be permission issue)"
  fi
  
  return $errors
}

# ============================================================================
# STEP 6: TEST SYNC INFRASTRUCTURE
# ============================================================================

step_test_sync() {
  log_info "Step 6: Testing GitHub sync infrastructure..."
  
  if [ -f "scripts/automation/sync-projects-board-status.sh" ]; then
    log_info "Found sync script: scripts/automation/sync-projects-board-status.sh"
    
    if [ -f "scripts/_common/github-api-client.sh" ]; then
      log_success "Found GitHub API client: scripts/_common/github-api-client.sh"
    else
      log_error "Missing GitHub API client"
    fi
    
    log_info "To test sync (dry-run):"
    log_info "  bash scripts/automation/sync-projects-board-status.sh 123 --dry-run"
  else
    log_warn "Sync scripts not found in expected location"
  fi
}

# ============================================================================
# STEP 7: VS CODE COPILOT SETUP
# ============================================================================

step_vscode_copilot() {
  log_info "Step 7: VS Code Copilot configuration..."
  
  log_info "To enable GitHub issue sync in Copilot:"
  log_info "  1. Restart VS Code (File → Close Folder)"
  log_info "  2. Reload: Cmd+Shift+P → Developer: Reload Window"
  log_info "  3. Verify: Cmd+Shift+P → Copilot: Show GitHub Status"
  log_info ""
  log_warn "Note: Environment variables loaded at VS Code startup"
  log_warn "If GITHUB_TOKEN not recognized, restart VS Code completely"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║   Ubuntu GitHub Issue Sync Setup                              ║"
  echo "║   Fixes: GitHub issue sync after Windows → Ubuntu migration   ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  log_info "Setup starting at: $(date)"
  log_info "Log file: $SETUP_LOG"
  echo ""
  
  # Run all steps
  step_check_prerequisites
  echo ""
  
  step_install_gh_cli
  echo ""
  
  step_authenticate_gh
  echo ""
  
  step_configure_env
  echo ""
  
  step_verify_setup
  verify_errors=$?
  echo ""
  
  step_test_sync
  echo ""
  
  step_vscode_copilot
  echo ""
  
  # Summary
  echo "╔════════════════════════════════════════════════════════════════╗"
  if [ $verify_errors -eq 0 ]; then
    echo "║                  ✓ SETUP COMPLETE                             ║"
    echo "║                                                                ║"
    echo "║  Next steps:                                                   ║"
    echo "║  1. Reload shell: source ~/.bashrc  (or ~/.zshrc)             ║"
    echo "║  2. Restart VS Code                                            ║"
    echo "║  3. Test: gh issue list --repo kushin77/code-server --limit 5 ║"
  else
    echo "║                  ⚠ SETUP INCOMPLETE                           ║"
    echo "║                                                                ║"
    echo "║  Some checks failed - review errors above                     ║"
    echo "║  Troubleshooting guide: UBUNTU_GITHUB_ISSUE_SYNC_SETUP.md     ║"
  fi
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  log_info "Setup completed at: $(date)"
  
  return $verify_errors
}

# Run main function
main "$@"
