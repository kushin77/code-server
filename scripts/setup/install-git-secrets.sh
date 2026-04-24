#!/usr/bin/env bash
################################################################################
# @file        scripts/setup/install-git-secrets.sh
# @module      security/git-secrets
# @description Install and configure git-secrets for local secret scanning
# @owner       platform
# @status      active
#
# USAGE
#   scripts/setup/install-git-secrets.sh
#
# Last Updated: April 23, 2026
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

require_command "git" "git is required to install git-secrets"
require_command "sudo" "sudo is required to install git-secrets"
require_command "mktemp" "mktemp is required for temporary checkout"

TMP_DIR=""

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT

log_info "Installing git-secrets for secret scanning..."

# Check if git-secrets already installed
if command -v git-secrets &> /dev/null; then
    log_info "✓ git-secrets already installed: $(git secrets --version)"
else
    log_info "Installing git-secrets from GitHub..."
    TMP_DIR="$(mktemp -d)"
    cd "$TMP_DIR"
    git clone https://github.com/awslabs/git-secrets.git .
    sudo ./install.sh
    cd - >/dev/null
    log_info "✓ git-secrets installed successfully"
fi

# Install pre-commit hook
log_info "Installing git-secrets pre-commit hook..."
git secrets --install -f
log_info "✓ Pre-commit hook installed"

# Add secret patterns (AWS, GitHub, Stripe, Database)
log_info "Configuring secret detection patterns..."

git secrets --add --global '(aws_access_key_id|aws_secret_access_key)' || true
log_info "✓ Added AWS credential pattern"

git secrets --add --global '(AKIA[0-9A-Z]{16})' || true
log_info "✓ Added AWS Access Key ID pattern"

git secrets --add --global '(ghp_[A-Za-z0-9_]{36})' || true
log_info "✓ Added GitHub Personal Access Token pattern"

git secrets --add --global '(sk_live_[A-Za-z0-9]{24})' || true
log_info "✓ Added Stripe Secret Key pattern"

git secrets --add --global '(postgresql://[^:\s]+:[^@\s]+@)' || true
log_info "✓ Added PostgreSQL connection string pattern"

git secrets --add --global '(redis://:[^@\s]+@)' || true
log_info "✓ Added Redis connection string pattern"

git secrets --add --global '(mongodb://[^:\s]+:[^@\s]+@)' || true
log_info "✓ Added MongoDB connection string pattern"

# Allow specific patterns that are safe (examples)
git secrets --add --allow '^(REPLACEME|YOUR-)' || true
log_info "✓ Added allowed example pattern"

log_info "✓ git-secrets setup complete"
log_info ""
log_info "USAGE:"
log_info "  Scan current commit: git secrets --scan"
log_info "  Scan all history:    git secrets --scan --all"
log_info "  Scan staged changes: git secrets --scan --cached"
log_info ""
log_info "The pre-commit hook will automatically scan before each commit."
