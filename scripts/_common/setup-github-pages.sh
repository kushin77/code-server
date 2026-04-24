#!/usr/bin/env bash
# @file        scripts/_common/setup-github-pages.sh
# @module      github-pages/setup
# @description Setup and deploy GitHub Pages from docs/ directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
source "$SCRIPT_DIR/_common/github-api-client.sh"

readonly REPO="${REPO:-kushin77/code-server}"
readonly DOCS_DIR="${DOCS_DIR:-docs}"
readonly PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"

# Enable GitHub Pages via API
enable_github_pages() {
  log_info "Enabling GitHub Pages for $REPO..."
  
  local token pages_config
  token=$(github_get_token)
  
  # Configure Pages to build from docs/ on main branch
  pages_config='{
    "source": {
      "branch": "main",
      "path": "/docs"
    },
    "build_type": "workflow"
  }'
  
  github_api_call POST "/repos/$REPO/pages" "$pages_config" || log_error "Failed to enable Pages"
  log_info "✓ GitHub Pages enabled (docs/ on main branch)"
}

# Verify docs directory exists
verify_docs_directory() {
  if [[ ! -d "$DOCS_DIR" ]]; then
    log_error "Docs directory not found: $DOCS_DIR"
    return 1
  fi
  
  if [[ ! -f "$DOCS_DIR/index.md" ]]; then
    log_warn "Creating placeholder index.md..."
    mkdir -p "$DOCS_DIR"
    cat > "$DOCS_DIR/index.md" <<EOF
# Documentation

Welcome to the documentation site!

## Contents

- [Overview](overview.md)
- [API Reference](api-reference.md)
- [Deployment Guide](deployment.md)
EOF
  fi
  
  log_info "✓ Docs directory verified"
}

# Create GitHub Actions workflow for Pages build
create_pages_workflow() {
  log_info "Creating GitHub Pages build workflow..."
  
  mkdir -p .github/workflows
  cat > .github/workflows/deploy-pages.yml <<'EOF'
name: Deploy GitHub Pages

on:
  push:
    branches: [ main ]
    paths:
      - 'docs/**'
      - '.github/workflows/deploy-pages.yml'

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Pages
        uses: actions/configure-pages@v4
      - name: Build with Jekyll
        uses: actions/jekyll-build-pages@v1
        with:
          source: ./docs
          destination: ./_site
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v2
EOF
  
  log_info "✓ Pages workflow created at .github/workflows/deploy-pages.yml"
}

export -f enable_github_pages verify_docs_directory create_pages_workflow

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-setup}" in
    setup) verify_docs_directory && create_pages_workflow && log_info "✓ GitHub Pages setup complete" ;;
    enable) enable_github_pages ;;
    verify) verify_docs_directory ;;
    *) echo "Usage: $0 {setup|enable|verify}" ;;
  esac
fi
