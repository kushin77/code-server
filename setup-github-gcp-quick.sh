#!/usr/bin/env bash
set -e
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# GitHub Issue Sync - Quick Setup with GCP GSM Token
# ============================================================================
# For users already authenticated to GCP
# ============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  GitHub Issue Sync - Quick Setup (GCP GSM Token)              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Install GitHub CLI if not present
if ! command -v gh &> /dev/null; then
  log_info "Installing GitHub CLI..."
  if command -v apt-get &> /dev/null; then
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y gh
  fi
fi

log_success "GitHub CLI installed"

# Retrieve token from GSM
log_info "Retrieving GitHub token from GSM..."
GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-fine-grained-token" 2>/dev/null)

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Failed to retrieve token. Ensure you're authenticated:"
  echo "  gcloud auth application-default login"
  exit 1
fi

# Authenticate with token
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || true

log_success "GitHub CLI authenticated with GSM token"

# Configure shell
SHELL_RC="$HOME/.bashrc"
[ -n "$ZSH_VERSION" ] && SHELL_RC="$HOME/.zshrc"

if ! grep -q "GITHUB_REPO.*kushin77" "$SHELL_RC" 2>/dev/null; then
  cat >> "$SHELL_RC" << 'EOF'

# GitHub Configuration (GSM Integration)
export GITHUB_REPO="kushin77/code-server"
export GITHUB_OWNER="kushin77"
EOF
  log_success "Shell environment configured"
fi

# Verify
log_info "Verifying setup..."
gh auth status && log_success "GitHub CLI authenticated" || echo "Warning: Could not verify auth status"
gh repo view kushin77/code-server &>/dev/null && log_success "Repository accessible" || echo "Warning: Could not access repository"

echo ""
echo "✓ Setup complete!"
echo ""
echo "Next: source $SHELL_RC && restart VS Code"
echo ""
