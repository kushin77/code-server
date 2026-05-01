#!/bin/bash
# @file scripts/ide/setup-memory-vscode-integration.sh
# @module ide/vscode-integration
# @description P3-1562 Phase 4: VS Code integration for organizational memory search
# @governance GOV-002: IDE provides access to collective organizational knowledge
# @usage setup-memory-vscode-integration.sh

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

source "${REPO_ROOT}/.env.infrastructure" 2>/dev/null || true

# Create VS Code command for memory search
setup_vscode_commands() {
  log_info "Setting up VS Code memory search commands..."
  
  mkdir -p "${REPO_ROOT}/.vscode"
  
  # Add memory commands to settings
  cat >> "${REPO_ROOT}/.vscode/settings.json" <<EOF
,
  "elevatediq.memory": {
    "enabled": true,
    "endpoint": "${MEMORY_SERVICE_ENDPOINT}",
    "defaultCollection": "incidents"
  }
EOF
  
  log_success "VS Code memory commands configured"
}

# Create keybinding for memory search
setup_keybindings() {
  log_info "Setting up keybindings for memory search..."
  
  cat > "${REPO_ROOT}/.vscode/keybindings.json" <<'EOF'
[
  {
    "key": "ctrl+shift+m",
    "command": "elevatediq.searchMemory",
    "when": "editorFocus"
  },
  {
    "key": "ctrl+shift+i",
    "command": "elevatediq.recordIncident",
    "when": "editorFocus"
  }
]
EOF
  
  log_success "Keybindings configured"
}

# Generate documentation for memory commands
generate_memory_docs() {
  log_info "Generating memory search documentation..."
  
  cat > "${REPO_ROOT}/docs/ide/memory-commands.md" <<'EOF'
# VS Code Organizational Memory Commands

## Search Memory

**Command:** ElevatedIQ: Search Memory  
**Shortcut:** Ctrl+Shift+M  
**Action:** Opens semantic search panel to query organizational memory

### Usage
1. Press Ctrl+Shift+M
2. Type your query (e.g., "502 error after restart")
3. Select collection (incidents, runbooks, PRs, etc.)
4. Results show with relevance scores

### Collections
- **incidents**: Historical incident reports and resolutions
- **runbooks**: Standard operating procedures
- **pr_descriptions**: Pull request descriptions and summaries
- **retrospectives**: Postmortems and lessons learned
- **agent_learnings**: AI agent task outcomes and patterns

## Record Incident

**Command:** ElevatedIQ: Record Incident  
**Shortcut:** Ctrl+Shift+I  
**Action:** Add current error/incident to organizational memory

### Usage
1. Press Ctrl+Shift+I
2. Fill in incident details:
   - Title: Brief description
   - Description: Full context
   - Resolution (optional): How it was fixed
3. Incident saved to memory and searchable

## Memory in Hover

When your cursor is over an error message, hover tooltip shows:
- "Similar past incidents" (if any found)
- Click to open search results

## Status Bar Integration

VS Code status bar shows:
- Memory service status (connected/disconnected)
- Last search query results count
- Available collections

## Performance

- Semantic search completes in <3 seconds
- Results sorted by relevance (0.0-1.0)
- Only results with >0.7 similarity shown by default
EOF
  
  log_success "Memory search documentation generated"
}

main() {
  log_info "Setting up VS Code organizational memory integration..."
  
  setup_vscode_commands
  setup_keybindings
  generate_memory_docs
  
  log_success "VS Code memory integration complete"
  log_info "Use Ctrl+Shift+M to search organizational memory"
}

main "$@"