#!/usr/bin/env bash
set -e
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# GitHub Authentication & Environment Setup (No Sudo Required)
# ============================================================================
# Configures GitHub CLI authentication and shell environment
# Run after gh CLI is installed
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  GitHub Authentication & Environment Setup                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Determine shell
SHELL_RC="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ]; then
  SHELL_RC="$HOME/.zshrc"
fi

echo "Using shell configuration file: $SHELL_RC"
echo ""

# Step 1: Authenticate with GitHub
echo "╔═ Step 1: GitHub CLI Authentication ════════════════════════════╗"
echo "║                                                                 ║"
echo "║ You need to create a GitHub fine-grained token:               ║"
echo "║                                                                 ║"
echo "║ 1. Go to: https://github.com/settings/tokens?type=beta        ║"
echo "║ 2. Click 'Generate new token'                                 ║"
echo "║ 3. Set name: 'Ubuntu Workstation'                             ║"
echo "║ 4. Set expiration: 90 days                                    ║"
echo "║ 5. Select these scopes:                                       ║"
echo "║    ✓ repo:read, repo:write                                    ║"
echo "║    ✓ issues:read, issues:write                                ║"
echo "║    ✓ pull_requests:read, pull_requests:write                  ║"
echo "║    ✓ projects:read                                            ║"
echo "║ 6. Copy the token (starts with github_pat_)                   ║"
echo "║                                                                 ║"
echo "║ Then run: gh auth login                                        ║"
echo "║ Choose: GitHub.com → HTTPS → Paste token                      ║"
echo "║                                                                 ║"
echo "╚═════════════════════════════════════════════════════════════════╝"
echo ""

read -p "Press Enter after creating your token and running 'gh auth login': " || true

# Verify authentication
echo ""
echo "Verifying GitHub CLI authentication..."
if gh auth status 2>/dev/null; then
  echo "✓ GitHub CLI authenticated successfully!"
else
  echo "✗ GitHub authentication failed. Please run: gh auth login"
  exit 1
fi

echo ""
echo "╔═ Step 2: Environment Variables ════════════════════════════════╗"
echo ""

# Configure environment variables
if grep -q "GITHUB_REPO.*kushin77/code-server" "$SHELL_RC" 2>/dev/null; then
  echo "✓ Environment variables already configured in $SHELL_RC"
else
  echo "Adding environment variables to $SHELL_RC..."
  
  cat >> "$SHELL_RC" << 'EOF'

# GitHub Configuration (added by configure-github-ubuntu.sh)
export GITHUB_REPO="kushin77/code-server"
export GITHUB_OWNER="kushin77"
EOF
  
  echo "✓ Environment variables added"
fi

echo ""
echo "╔═ Step 3: Verify Setup ═════════════════════════════════════════╗"
echo ""

# Source the shell config to load new variables
source "$SHELL_RC" 2>/dev/null || true

# Test repository access
echo "Testing repository access..."
if gh repo view kushin77/code-server --json name 2>/dev/null | grep -q "code-server"; then
  echo "✓ Can access kushin77/code-server repository"
else
  echo "✗ Cannot access repository - check token permissions"
  exit 1
fi

# Test issue listing
echo "Testing issue listing..."
if gh issue list --repo kushin77/code-server --limit 1 2>/dev/null | head -1; then
  echo "✓ Can list GitHub issues"
else
  echo "⚠ Warning: Could not list issues (may be permission or network issue)"
fi

echo ""
echo "╔═ Step 4: Final Instructions ═══════════════════════════════════╗"
echo ""
echo "✓ Setup complete! Do this now:"
echo ""
echo "  1. Reload your shell:"
echo "     source $SHELL_RC"
echo ""
echo "  2. Restart VS Code (Cmd+Q or Ctrl+Q, then reopen)"
echo ""
echo "  3. Verify GitHub sync works:"
echo "     gh issue list --repo kushin77/code-server --limit 5"
echo ""
echo "  4. Test issue creation:"
echo "     gh issue create --repo kushin77/code-server --title 'Test Issue' --body 'Testing GitHub sync'"
echo ""
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
