#!/usr/bin/env bash
# @file        scripts/_common/setup-github-security.sh
# @module      github-security/setup
# @description Enable GitHub security features (secret scanning, CodeQL, push protection)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
source "$SCRIPT_DIR/_common/github-api-client.sh"

readonly REPO="${REPO:-kushin77/code-server}"

# Enable secret scanning via API
enable_secret_scanning() {
  log_info "Enabling secret scanning for $REPO..."
  
  local token
  token=$(github_get_token)
  
  github_api_call PATCH "/repos/$REPO/secret-scanning" \
    '{"secret_scanning": true}' || log_warn "Secret scanning may already be enabled"
  
  log_info "✓ Secret scanning enabled"
}

# Enable push protection
enable_push_protection() {
  log_info "Enabling push protection for $REPO..."
  
  local token
  token=$(github_get_token)
  
  github_api_call PATCH "/repos/$REPO/secret-scanning/push-protection" \
    '{"push_protection_enabled": true}' || log_warn "Push protection may already be enabled"
  
  log_info "✓ Push protection enabled"
}

# Create CodeQL workflow
create_codeql_workflow() {
  log_info "Creating CodeQL analysis workflow..."
  
  mkdir -p .github/workflows
  cat > .github/workflows/codeql-analysis.yml <<'EOF'
name: CodeQL Analysis

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 0 * * 0'

permissions:
  contents: read
  security-events: write

jobs:
  analyze:
    name: Analyze
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        language: [ 'typescript', 'python', 'javascript' ]
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v2
        with:
          languages: ${{ matrix.language }}

      - name: Build (TypeScript)
        if: matrix.language == 'typescript'
        run: |
          pnpm install
          pnpm build

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v2
        with:
          category: /language:${{ matrix.language }}
EOF
  
  log_info "✓ CodeQL workflow created"
}

# Create dependabot configuration
create_dependabot_config() {
  log_info "Creating Dependabot configuration..."
  
  mkdir -p .github
  cat > .github/dependabot.yml <<'EOF'
version: 2
updates:
  # Enable version updates for npm
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
    reviewers:
      - "kushin77"

  # Enable version updates for GitHub Actions
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"

  # Enable version updates for Docker
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"

  # Enable version updates for Python
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
EOF
  
  log_info "✓ Dependabot config created"
}

export -f enable_secret_scanning enable_push_protection create_codeql_workflow create_dependabot_config

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-all}" in
    all)
      enable_secret_scanning
      enable_push_protection
      create_codeql_workflow
      create_dependabot_config
      log_info "✓ GitHub security setup complete"
      ;;
    secret-scan) enable_secret_scanning ;;
    push-protect) enable_push_protection ;;
    codeql) create_codeql_workflow ;;
    dependabot) create_dependabot_config ;;
    *) echo "Usage: $0 {all|secret-scan|push-protect|codeql|dependabot}" ;;
  esac
fi
