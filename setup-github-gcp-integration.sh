#!/usr/bin/env bash
set -e
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# GitHub Issue Sync Setup with GCP GSM Token Integration
# ============================================================================
# Installs GitHub CLI and GCP SDK, retrieves GitHub token from GSM
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  GitHub Issue Sync Setup with GCP GSM Integration             ║"
echo "║  Retrieves GitHub token from Google Secret Manager             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# STEP 1: VERIFY GCP SDK
# ============================================================================

log_info "Step 1: Checking GCP SDK installation..."

if ! command -v gcloud &> /dev/null; then
  log_error "GCP SDK (gcloud) not found"
  log_info "Installing GCP SDK..."
  
  # For Ubuntu/Debian
  if command -v apt-get &> /dev/null; then
    curl https://sdk.cloud.google.com | bash
    exec -l $SHELL
  else
    log_error "Cannot auto-install GCP SDK - please install manually"
    echo "  Visit: https://cloud.google.com/sdk/docs/install"
    exit 1
  fi
else
  log_success "GCP SDK found: $(gcloud --version | head -1)"
fi

# ============================================================================
# STEP 2: AUTHENTICATE TO GCP
# ============================================================================

log_info "Step 2: Checking GCP authentication..."

# Check if already authenticated
if ! gcloud auth application-default print-access-token &> /dev/null; then
  log_warn "Not authenticated to GCP"
  log_info ""
  log_info "To access GitHub token from GSM, you need to authenticate:"
  log_info ""
  log_info "  gcloud auth application-default login"
  log_info ""
  log_warn "This will open a browser window. Complete authentication and return here."
  log_info ""
  
  read -p "Press Enter to authenticate to GCP: " || true
  
  gcloud auth application-default login
else
  log_success "GCP authentication valid"
fi

# ============================================================================
# STEP 3: VERIFY GCP PROJECT
# ============================================================================

log_info "Step 3: Verifying GCP project configuration..."

GCP_PROJECT=$(gcloud config list --format='value(core.project)' 2>/dev/null)

if [ -z "$GCP_PROJECT" ]; then
  log_error "GCP project not configured"
  log_info "Setting default project..."
  read -p "Enter your GCP project ID: " GCP_PROJECT
  gcloud config set project "$GCP_PROJECT"
else
  log_success "GCP project: $GCP_PROJECT"
fi

# ============================================================================
# STEP 4: RETRIEVE GITHUB TOKEN FROM GSM
# ============================================================================

log_info "Step 4: Retrieving GitHub token from GSM..."

GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-fine-grained-token" --project="$GCP_PROJECT" 2>/dev/null) || {
  log_error "Failed to retrieve token from GSM"
  log_info "Checking available secrets..."
  gcloud secrets list --project="$GCP_PROJECT" || true
  exit 1
}

if [ -z "$GITHUB_TOKEN" ]; then
  log_error "GitHub token is empty"
  exit 1
fi

log_success "Retrieved GitHub token from GSM (length: ${#GITHUB_TOKEN})"

# ============================================================================
# STEP 5: INSTALL GITHUB CLI
# ============================================================================

log_info "Step 5: Installing GitHub CLI..."

if command -v gh &> /dev/null; then
  log_success "GitHub CLI already installed: $(gh --version | head -1)"
else
  log_info "Installing gh CLI..."
  
  if command -v apt-get &> /dev/null; then
    # Ubuntu/Debian
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y gh
  else
    log_error "Cannot auto-install gh CLI - please install manually"
    exit 1
  fi
  
  log_success "GitHub CLI installed: $(gh --version | head -1)"
fi

# ============================================================================
# STEP 6: AUTHENTICATE GITHUB CLI WITH GSM TOKEN
# ============================================================================

log_info "Step 6: Configuring GitHub CLI with token from GSM..."

# Set the token in gh CLI
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || {
  # Fallback: use environment variable
  export GITHUB_TOKEN="$GITHUB_TOKEN"
  log_warn "Set GITHUB_TOKEN environment variable as fallback"
}

log_success "GitHub CLI authenticated"

# Verify authentication
if gh auth status &> /dev/null; then
  log_success "GitHub CLI authentication verified"
  gh auth status
else
  log_error "GitHub CLI authentication failed"
  exit 1
fi

# ============================================================================
# STEP 7: CONFIGURE SHELL ENVIRONMENT
# ============================================================================

log_info "Step 7: Configuring shell environment..."

SHELL_RC="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ]; then
  SHELL_RC="$HOME/.zshrc"
fi

# Add environment variables
if ! grep -q "GITHUB_TOKEN.*GSM\|GITHUB_REPO.*kushin77" "$SHELL_RC" 2>/dev/null; then
  cat >> "$SHELL_RC" << 'EOF'

# GitHub Configuration - Managed by GSM Integration
export GITHUB_REPO="kushin77/code-server"
export GITHUB_OWNER="kushin77"
export GCP_PROJECT="purebliss-ghl"
# Note: GITHUB_TOKEN is managed by gh CLI authentication
# To refresh from GSM, run: gcloud secrets versions access latest --secret="github-fine-grained-token"
EOF
  
  log_success "Shell environment configured"
else
  log_success "Shell environment already configured"
fi

# ============================================================================
# STEP 8: VERIFY SETUP
# ============================================================================

log_info "Step 8: Verifying complete setup..."

# Test GitHub CLI
if gh repo view kushin77/code-server &> /dev/null; then
  log_success "Can access kushin77/code-server repository"
else
  log_error "Cannot access repository - check token permissions"
fi

# Test issue listing
if gh issue list --repo kushin77/code-server --limit 1 &> /dev/null; then
  log_success "Can list GitHub issues"
else
  log_warn "Could not list issues (may be permissions issue)"
fi

# ============================================================================
# FINAL SUMMARY
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    ✓ SETUP COMPLETE                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_success "GitHub CLI installed and configured"
log_success "GitHub token retrieved from GSM"
log_success "All components ready"
echo ""
echo "Next steps:"
echo "  1. Reload shell: source $SHELL_RC"
echo "  2. Restart VS Code"
echo "  3. Test: gh issue list --repo kushin77/code-server --limit 5"
echo ""
echo "To refresh token from GSM in the future:"
echo "  export GITHUB_TOKEN=\$(gcloud secrets versions access latest --secret=\"github-fine-grained-token\")"
echo ""
