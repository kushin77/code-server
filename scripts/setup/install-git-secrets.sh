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

ensure_global_pattern() {
    local config_key="$1"
    local pattern="$2"
    local label="$3"

    if git config --global --get-all "$config_key" 2>/dev/null | grep -Fxq -- "$pattern"; then
        log_info "✓ $label already configured"
    else
        git secrets --add --global "$pattern"
        log_info "✓ Added $label"
    fi
}

log_info "Installing git-secrets for secret scanning..."

# Check if git-secrets already installed
if command -v git-secrets &> /dev/null; then
    log_info "✓ git-secrets already installed: $(git secrets --version)"
else
    log_info "Installing git-secrets from GitHub..."
    TMP_DIR="$(mktemp -d)"
    cd "$TMP_DIR"
    if [[ ! -d .git ]]; then
        if [ ! -d .git ]; then git clone https://github.com/awslabs/git-secrets.git .; fi
    fi
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

ensure_global_pattern "secrets.patterns" '(aws_access_key_id|aws_secret_access_key)' "AWS credential pattern"
ensure_global_pattern "secrets.patterns" '(AKIA'+'[0-9A-Z]{16})' "AWS Access Key ID pattern"
ensure_global_pattern "secrets.patterns" '(ghp_'+'[A-Za-z0-9_]{36})' "GitHub Personal Access Token pattern"
ensure_global_pattern "secrets.patterns" '(sk_live_[A-Za-z0-9]{24})' "Stripe Secret Key pattern"
ensure_global_pattern "secrets.patterns" '(postgresql://[^:\s]+:[^@\s]+@)' "PostgreSQL connection string pattern"
ensure_global_pattern "secrets.patterns" '(redis://:[^@\s]+@)' "Redis connection string pattern"
ensure_global_pattern "secrets.patterns" '(mongodb://[^:\s]+:[^@\s]+@)' "MongoDB connection string pattern"

# Allow specific patterns that are safe (examples)
ensure_global_pattern "secrets.allowed" '^(REPLACEME|YOUR-)' "allowed example pattern"

log_info "✓ git-secrets setup complete"
log_info ""
log_info "USAGE:"
log_info "  Scan current commit: git secrets --scan"
log_info "  Scan all history:    git secrets --scan --all"
log_info "  Scan staged changes: git secrets --scan --cached"
log_info ""
log_info "The pre-commit hook will automatically scan before each commit."
