#!/usr/bin/env bash
set -e
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# GitHub CLI Installation (Non-Interactive for Ubuntu)
# ============================================================================
# This script installs GitHub CLI without interactive prompts
# Run with: bash install-gh-cli.sh
# ============================================================================

echo "Installing GitHub CLI on Ubuntu (non-interactive)..."
echo ""

# Add GitHub CLI repository
echo "Step 1: Adding GitHub CLI repository..."
wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

# Update package index
echo "Step 2: Updating package index..."
sudo apt-get update

# Install gh CLI
echo "Step 3: Installing gh CLI..."
sudo apt-get install -y gh

# Verify installation
echo ""
echo "✓ Installation complete!"
gh --version
echo ""
echo "Next steps:"
echo "  1. Authenticate: gh auth login"
echo "  2. Paste your fine-grained token from: https://github.com/settings/tokens?type=beta"
echo "  3. Test: gh issue list --repo kushin77/code-server --limit 5"
