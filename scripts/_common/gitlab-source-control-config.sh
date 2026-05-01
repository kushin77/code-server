#!/usr/bin/env bash
# @file        scripts/_common/gitlab-source-control-config.sh
# @module      github/gitlab-integration
# @description GitLab source control integration configuration
#
# Manages:
# - GitLab repo mirror sync (kushin77/source-control)
# - Integration with code-server repo
# - Source control code separation
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# ============================================================================
# Configuration
# ============================================================================

readonly CODE_SERVER_REPO="${CODE_SERVER_REPO:-https://github.com/kushin77/code-server.git}"
readonly GITLAB_REPO="${GITLAB_REPO:-https://github.com/kushin77/source-control.git}"
readonly GITLAB_WORK_DIR="${GITLAB_WORK_DIR:-${WORK_DIR:-/tmp/gitlab-source-control}}"

# Repos managed by source-control repo
readonly SOURCE_CONTROL_MODULES=(
  "gitlab-integration"
  "git-extensions"
  "source-code-analysis"
  "vcs-adapters"
)

# ============================================================================
# Repository Strategy
# ============================================================================

gitlab_write_repo_strategy() {
  cat > "$SCRIPT_DIR/../docs/governance/repository-standards.md" <<'EOF'
# Repository Strategy Map

## Current State (April 2026)

| Repo | Purpose | Owner | Scope |
|------|---------|-------|-------|
| `kushin77/code-server` | Main IDE platform + infrastructure | Internal | End-user IDE, extensions, backend APIs, deployment |
| `kushin77/source-control` | GitLab + VCS integrations | Internal | GitLab customization, source control tooling, git extensions |
| `kushin77/ollama` | AI/Ollama workloads (future) | Internal | Ollama integration, LLM fine-tuning, local AI |

## Code Organization

### code-server Repo (Main)
```
apps/
  extensions/          # VS Code extensions
    kc-branding/       # KC IDE branding
    kc-collab-intelligence/  # Real-time collaboration
    kc-github-oauth/   # GitHub OAuth
    team-hub/          # Team features
  backend/             # Backend APIs
  api/                 # REST/GraphQL endpoints
scripts/
  _common/             # Shared libraries
    github-api-client.sh      # GitHub API wrapper
    gitlab-source-control-config.sh  # GitLab config (this file)
docs/
  REPO-STRATEGY.md     # This document
  BRANDING-SSOT.md     # KC branding canonical reference
```

### source-control Repo (GitLab Specialization)
```
gitlab-integration/
  manifests/           # GitLab deploy templates
  apis/                # GitLab API wrappers
  cli-extensions/      # GitLab CLI customizations
git-extensions/
  hooks/               # Custom git hooks
  workflows/           # Git workflow templates
vcs-adapters/
  github-bridge/       # GitHub ↔ GitLab sync
  gitlab-bridge/       # GitLab customizations
```

## Integration Pattern

1. **Pure code-server work** → stays in `kushin77/code-server`
   - IDE extensions, user features, branding
   - Backend APIs, infrastructure
   - Deployment, scaling

2. **GitLab-specific work** → pushed to `kushin77/source-control`
   - GitLab integration code
   - Custom GitLab API workflows
   - Source control adapters

3. **Shared utilities** → `scripts/_common/` in both repos
   - GitHub API client (github-api-client.sh)
   - GitLab config wrapper (gitlab-source-control-config.sh)
   - Common deployment helpers

## Sync Strategy

**code-server → source-control** (one-way push):
- When GitLab integration changes in code-server, mirror to source-control
- Example: `scripts/_common/gitlab-source-control-config.sh` pushed to both repos
- Every code-server PR that touches GitLab → also sync to source-control

**source-control → code-server** (selective pull):
- GitLab-specific features pull from source-control as needed
- Never merge unstable code-server → pull tested GitLab code only
- Via git subtree or explicit copy + test

## Why Separate Repos?

✅ **Clear ownership**: GitLab team owns source-control repo, IDE team owns code-server  
✅ **Focused PRs**: source-control PRs only about GitLab, no IDE noise  
✅ **Independent releases**: Can release GitLab updates without IDE cycle  
✅ **Access control**: GitLab team has restricted access (not full code-server)  
✅ **Reduced complexity**: 10K LOC GitLab code doesn't clutter IDE repo  

## Guidelines

1. **New feature**: Start in appropriate repo (code-server for IDE, source-control for GitLab)
2. **Shared utility**: Put in `scripts/_common/`, commit to both (sync via git)
3. **Testing**: Test in native repo first, then mirror
4. **Documentation**: Document in repo-specific docs/ (reference other repo as "external")
5. **GitHub Issues**: File issues in kushin77/code-server (master), link to source-control work

---

**Last Updated**: April 24, 2026  
**Owner**: Architecture Team  
**Status**: Active (in use)
EOF

  log_info "✓ Repository strategy documented in docs/governance/repository-standards.md"
}

#
# Clone source-control repo for local development
#
gitlab_clone_repo() {
  local work_dir="${1:-$GITLAB_WORK_DIR}"
  
  if [[ -d "$work_dir/.git" ]]; then
    log_info "Source-control repo already cloned at $work_dir"
    return 0
  fi
  
  log_info "Cloning GitLab source-control repo..."
  git clone "$GITLAB_REPO" "$work_dir"
  
  log_info "✓ Cloned to $work_dir"
}

#
# Sync GitLab integration files to source-control repo
#
gitlab_sync_to_repo() {
  local work_dir="${1:-$GITLAB_WORK_DIR}"
  local source_file="${2:?Source file required}"
  local target_dir="${3:-${source_file%/*}}"  # Keep same dir structure
  
  gitlab_clone_repo "$work_dir"
  
  log_info "Syncing $source_file to source-control repo..."
  
  cp "$SCRIPT_DIR/../$source_file" "$work_dir/$target_dir/"
  
  cd "$work_dir"
  git add "$target_dir/$(basename $source_file)"
  git commit -m "chore: sync GitLab integration from code-server" || log_warn "No changes to commit"
  git push origin main
  
  log_info "✓ Synced to source-control repo"
}

#
# Verify source-control repo has all required modules
#
gitlab_verify_structure() {
  local work_dir="${1:-$GITLAB_WORK_DIR}"
  
  gitlab_clone_repo "$work_dir"
  
  log_info "Verifying source-control repo structure..."
  
  local missing=0
  for module in "${SOURCE_CONTROL_MODULES[@]}"; do
    if [[ ! -d "$work_dir/$module" ]]; then
      log_warn "Missing module: $module"
      (( missing++ ))
    fi
  done
  
  if (( missing > 0 )); then
    log_error "Source-control repo missing $missing modules. Initialize them:"
    for module in "${SOURCE_CONTROL_MODULES[@]}"; do
      echo "  mkdir -p $work_dir/$module && git add $work_dir/$module/.gitkeep"
    done
    return 1
  fi
  
  log_info "✓ All modules present"
  return 0
}

# ============================================================================
# Exports
# ============================================================================

export -f gitlab_clone_repo
export -f gitlab_sync_to_repo
export -f gitlab_verify_structure
export -f gitlab_write_repo_strategy

# ============================================================================
# Main Entry Point
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-help}" in
    clone)
      gitlab_clone_repo "${2:-$GITLAB_WORK_DIR}"
      ;;
    sync)
      gitlab_sync_to_repo "${3:-$GITLAB_WORK_DIR}" "${2:?Source file required}"
      ;;
    verify)
      gitlab_verify_structure "${2:-$GITLAB_WORK_DIR}"
      ;;
    doc-strategy)
      gitlab_write_repo_strategy
      ;;
    help|*)
      cat <<EOF
GitLab Source Control Integration

Usage:
  ./gitlab-source-control-config.sh clone [work_dir]           Clone source-control repo
  ./gitlab-source-control-config.sh sync <file> [work_dir]    Sync file to source-control
  ./gitlab-source-control-config.sh verify [work_dir]         Verify repo structure
  ./gitlab-source-control-config.sh doc-strategy              Generate repo strategy docs
  
Environment:
  GITLAB_WORK_DIR    Working directory for repo (default: /tmp/gitlab-source-control)
EOF
      ;;
  esac
fi
