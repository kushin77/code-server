#!/usr/bin/env bash
# @file        scripts/_common/setup-github-discussions.sh
# @module      github-discussions/setup
# @description Enable GitHub Discussions for architecture and community conversations
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
source "$SCRIPT_DIR/_common/github-api-client.sh"

readonly REPO="${REPO:-kushin77/code-server}"

# Enable GitHub Discussions via API
enable_discussions() {
  log_info "Enabling GitHub Discussions for $REPO..."
  
  local token
  token=$(github_get_token)
  
  github_api_call PATCH "/repos/$REPO" \
    '{"has_discussions": true}' || log_warn "Discussions may already be enabled"
  
  log_info "✓ GitHub Discussions enabled"
}

# Create discussion categories config
create_discussion_categories() {
  log_info "Creating discussion category structure..."
  
  mkdir -p docs/discussions
  
  cat > docs/discussions/categories.md <<'EOF'
# GitHub Discussions Categories

## 🏗️ Architecture
Discuss system design, architecture patterns, and high-level decisions.

## 📚 Documentation
Discuss documentation improvements, clarifications, and examples.

## 🎓 Learning
Share knowledge, ask questions about how to use the system.

## 🚀 Ideas & Features
Propose new features and discuss product direction.

## 🐛 Help & Support
Ask for help with specific issues or problems.

## 📢 Announcements
Important announcements about releases and changes.
EOF
  
  log_info "✓ Discussion categories documented"
}

# Create discussion templates
create_discussion_templates() {
  log_info "Creating discussion templates..."
  
  mkdir -p .github/discussion-templates
  
  # Architecture discussion template
  cat > .github/discussion-templates/architecture.yml <<'EOF'
title: "[ARCH] "
labels: ["architecture"]
body:
  - type: textarea
    attributes:
      label: Design Overview
      description: Describe the architectural change or component design
  - type: textarea
    attributes:
      label: Context
      description: Why is this change needed?
  - type: textarea
    attributes:
      label: Components Affected
      description: Which components/modules are impacted?
EOF
  
  # Feature discussion template
  cat > .github/discussion-templates/feature.yml <<'EOF'
title: "[FEATURE] "
labels: ["feature-request"]
body:
  - type: textarea
    attributes:
      label: Feature Description
      description: What would you like to see?
  - type: textarea
    attributes:
      label: Use Case
      description: Why is this feature needed?
  - type: textarea
    attributes:
      label: Proposed Solution
      description: How should this be implemented?
EOF
  
  log_info "✓ Discussion templates created"
}

export -f enable_discussions create_discussion_categories create_discussion_templates

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-all}" in
    all)
      enable_discussions
      create_discussion_categories
      create_discussion_templates
      log_info "✓ GitHub Discussions setup complete"
      ;;
    enable) enable_discussions ;;
    categories) create_discussion_categories ;;
    templates) create_discussion_templates ;;
    *) echo "Usage: $0 {all|enable|categories|templates}" ;;
  esac
fi
