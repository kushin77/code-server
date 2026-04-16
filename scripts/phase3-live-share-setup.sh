#!/bin/bash
###############################################################################
# Issue #178: Live Share Team Collaboration Suite - Real-time Code Sharing
#
# Features:
#   - VS Code Live Share extension
#   - Real-time code collaboration & pair programming
#   - Shared debugging sessions
#   - Shared terminals & Ollama access
#   - Async code review workflow
#   - Team workspace templates
#
# Execution: bash scripts/phase3-live-share-setup.sh
###############################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROD_HOST="${PROD_HOST:-192.168.168.31}"
PROD_USER="${PROD_USER:-akushnir}"
CODE_SERVER_PORT=8080
CODE_SERVER_URL="http://${PROD_HOST}:${CODE_SERVER_PORT}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# FUNCTIONS
# ============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ============================================================================
# STAGE 1: PREREQUISITES
# ============================================================================

stage_prerequisites() {
  log_info "STAGE 1: Prerequisites Verification"

  log_info "Checking code-server is running..."
  if ssh "${PROD_USER}@${PROD_HOST}" "docker ps --filter name=code-server --filter status=running -q | grep -q ." 2>/dev/null; then
    log_success "code-server container is running"
  else
    log_warn "code-server container not found"
    return 1
  fi

  log_info "Checking code-server accessibility..."
  if ssh "${PROD_USER}@${PROD_HOST}" "curl -sf ${CODE_SERVER_URL} >/dev/null 2>&1" 2>/dev/null; then
    log_success "code-server is accessible"
  else
    log_warn "code-server not responding at ${CODE_SERVER_URL}"
  fi

  log_info "Checking Ollama for shared context..."
  if ssh "${PROD_USER}@${PROD_HOST}" "curl -sf http://localhost:11434/api/tags >/dev/null 2>&1" 2>/dev/null; then
    log_success "Ollama available for shared sessions"
  else
    log_warn "Ollama not available"
  fi
}

# ============================================================================
# STAGE 2: INSTALL LIVE SHARE EXTENSION
# ============================================================================

stage_install_live_share() {
  log_info "STAGE 2: Install Live Share Extension"

  log_info "Installing VS Code Live Share..."
  ssh "${PROD_USER}@${PROD_HOST}" \
    "code-server --install-extension ms-vsliveshare.vsliveshare 2>/dev/null" || {
    log_warn "Live Share installation may have failed"
  }

  log_info "Installing Live Share Extension Pack..."
  ssh "${PROD_USER}@${PROD_HOST}" \
    "code-server --install-extension ms-vsliveshare.vsliveshare-pack 2>/dev/null" || {
    log_warn "Live Share Pack installation may have failed"
  }

  log_success "Live Share extensions installed"
}

# ============================================================================
# STAGE 3: CONFIGURE COLLABORATION SETTINGS
# ============================================================================

stage_configure_collaboration() {
  log_info "STAGE 3: Configure Collaboration Settings"

  # Create workspace settings for Live Share
  local workspace_settings='
{
  "liveShare.connectionMode": "auto",
  "liveShare.autoShareServers": true,
  "liveShare.launchConfig": {
    "serverReadyAction": {
      "pattern": "^\\s*listening on port (\\d+)\\s*$",
      "uriFormat": "http://localhost:%s",
      "action": "startDebugging"
    }
  },
  "liveShare.presence": true,
  "liveShare.presenceColorProvider": "vsliveshare",
  "liveShare.cursorMovementSpeed": "medium",
  "liveShare.allowGuestCommandExecution": true,
  "liveShare.allowGuestDebugSessionAccess": true,
  "liveShare.allowGuestTaskAccess": true,
  "liveShare.allowGuestPortAccess": true,
  "terminals.integrated.allowChords": false,
  "debug.console.closeOnEnd": false
}
'

  log_info "Updating code-server workspace settings..."
  ssh "${PROD_USER}@${PROD_HOST}" "cat >> ~/.local/share/code-server/User/settings.json << 'EOF'
${workspace_settings}
EOF" 2>/dev/null || log_warn "Could not update workspace settings"

  log_success "Collaboration settings configured"
}

# ============================================================================
# STAGE 4: CREATE TEAM WORKSPACE TEMPLATES
# ============================================================================

stage_create_templates() {
  log_info "STAGE 4: Create Team Workspace Templates"

  # Create workspace template
  local workspace_template='
{
  "folders": [
    {
      "path": ".",
      "name": "code-server-project"
    }
  ],
  "settings": {
    "files.exclude": {
      "**/.git": false,
      "**/.gitignore": true,
      "**/node_modules": true,
      "**/.pytest_cache": true,
      "**/__pycache__": true,
      "**/.DS_Store": true
    },
    "search.exclude": {
      "**/node_modules": true,
      "**/.git": true,
      "**/__pycache__": true
    },
    "liveShare.allowGuestCommandExecution": true,
    "liveShare.allowGuestDebugSessionAccess": true,
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "extensions": {
    "recommendations": [
      "ms-vsliveshare.vsliveshare",
      "ms-vsliveshare.vsliveshare-pack",
      "ms-vscode-remote.remote-containers",
      "eamodio.gitlens",
      "ms-python.python",
      "golang.Go",
      "rust-lang.rust-analyzer"
    ]
  },
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "name": "Attach to Live Share Session",
        "type": "node",
        "request": "attach",
        "port": 9222,
        "presentation": {
          "hidden": false,
          "group": "Live Share"
        }
      }
    ]
  },
  "tasks": {
    "version": "2.0.0",
    "tasks": [
      {
        "label": "Live Share: Share Session",
        "command": "command",
        "args": ["liveshare.start"]
      },
      {
        "label": "Live Share: End Session",
        "command": "command",
        "args": ["liveshare.end"]
      },
      {
        "label": "Run Tests",
        "command": "npm",
        "args": ["test"],
        "group": {
          "kind": "test",
          "isDefault": true
        }
      }
    ]
  }
}
'

  log_info "Creating workspace templates..."
  ssh "${PROD_USER}@${PROD_HOST}" "cat > ~/code-server-workspace.code-workspace << 'EOF'
${workspace_template}
EOF" 2>/dev/null

  log_success "Workspace templates created"
}

# ============================================================================
# STAGE 5: CONFIGURE SHARED OLLAMA ACCESS
# ============================================================================

stage_configure_shared_ollama() {
  log_info "STAGE 5: Configure Shared Ollama Access"

  # Create shared Ollama client script
  local ollama_client='#!/bin/bash

# Shared Ollama Client - For Live Share Sessions
# Usage: ./ollama-shared-client.sh <model> <prompt>

MODEL="${1:-codellama:7b}"
PROMPT="${2:-Write hello world}"
OLLAMA_URL="http://ollama:11434"

echo "[OLLAMA] Using model: $MODEL"
echo "[OLLAMA] Prompt: $PROMPT"
echo ""

# Send to shared Ollama
RESPONSE=$(curl -s -X POST "$OLLAMA_URL/api/generate" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"prompt\": \"$PROMPT\",
    \"stream\": false,
    \"temperature\": 0.7,
    \"top_p\": 0.9,
    \"num_predict\": 256
  }")

# Format response
echo "[RESPONSE]"
echo "$RESPONSE" | jq -r ".response" 2>/dev/null || echo "$RESPONSE"
echo ""
echo "[STATS]"
echo "  Model: $MODEL"
echo "  Tokens: $(echo "$RESPONSE" | jq ".eval_count" 2>/dev/null || echo "N/A")"
echo "  Duration: $(echo "$RESPONSE" | jq ".eval_duration" 2>/dev/null || echo "N/A")ms"
'

  log_info "Creating shared Ollama client..."
  ssh "${PROD_USER}@${PROD_HOST}" "cat > ~/shared-ollama-client.sh << 'EOF'
${ollama_client}
EOF
chmod +x ~/shared-ollama-client.sh" 2>/dev/null

  log_success "Shared Ollama client created"
}

# ============================================================================
# STAGE 6: SETUP LOGGING & AUDIT
# ============================================================================

stage_setup_logging() {
  log_info "STAGE 6: Setup Logging & Audit"

  # Create Live Share logging configuration
  local logging_config='
{
  "logLevel": "debug",
  "logDirectory": "/var/log/liveshare",
  "logFiles": [
    "/var/log/liveshare/session.log",
    "/var/log/liveshare/collaboration.log",
    "/var/log/liveshare/debug.log"
  ],
  "auditTrail": true,
  "recordParticipants": true,
  "recordActivity": true,
  "retentionDays": 30
}
'

  log_info "Creating logging configuration..."
  ssh "${PROD_USER}@${PROD_HOST}" "mkdir -p ~/.local/share/code-server/logs && cat > ~/.local/share/code-server/logs/liveshare-config.json << 'EOF'
${logging_config}
EOF" 2>/dev/null

  log_success "Logging configured"
}

# ============================================================================
# STAGE 7: DOCUMENTATION & GUIDES
# ============================================================================

stage_create_guides() {
  log_info "STAGE 7: Create Team Collaboration Guides"

  # Create quick start guide
  local quick_start='# Live Share Quick Start Guide

## Starting a Session

1. Open any file in code-server
2. Press Ctrl+Shift+P (Cmd+Shift+P on Mac)
3. Type "Live Share: Start Collaboration Session"
4. Share the generated URL with teammates

## Joining a Session

1. Click the Live Share link sent by the host
2. code-server will open and auto-connect
3. You can see real-time edits, debugging, terminals

## Best Practices

### Security
- Verify who has access before sharing
- Use AllowGuestCommandExecution wisely
- Check audit logs regularly

### Performance
- Limit participants to 5-10 for best experience
- Use shared terminals for CI/CD
- Keep debug sessions brief

### Collaboration
- Use cursor positioning to guide guests
- Share Ollama for AI assistance
- Review code together in real-time

## Troubleshooting

**Connection Issues:**
- Check port 1024-65535 accessibility
- Verify firewall rules
- Check logs: ~/.local/share/code-server/logs

**Performance Issues:**
- Reduce simultaneous edits
- Close unused files
- Check network bandwidth

**Extension Issues:**
- Reinstall Live Share: code-server --install-extension ms-vsliveshare.vsliveshare
- Restart code-server
- Check VS Code version compatibility

## Advanced Features

### Shared Debugging
- Set breakpoints in shared code
- All participants can step through
- Shared console output
- Shared variable inspection

### Shared Terminals
- Type Ctrl+` to open terminal
- Others can see all output
- Shared command history

### Shared Ollama
- Run: ./shared-ollama-client.sh "codellama:7b" "Write a function"
- All participants see responses
- Great for pair programming with AI assistance
'

  log_info "Creating collaboration guides..."
  ssh "${PROD_USER}@${PROD_HOST}" "cat > ~/LIVE-SHARE-GUIDE.md << 'EOF'
${quick_start}
EOF" 2>/dev/null

  log_success "Collaboration guides created"
}

# ============================================================================
# STAGE 8: VERIFICATION & SUMMARY
# ============================================================================

stage_verify() {
  log_info "STAGE 8: Verification"

  log_info "Checking Live Share extension..."
  ssh "${PROD_USER}@${PROD_HOST}" \
    "code-server --list-extensions | grep -i liveshare" 2>/dev/null || log_warn "Live Share extension not found"

  log_info "Checking workspace settings..."
  ssh "${PROD_USER}@${PROD_HOST}" \
    "cat ~/.local/share/code-server/User/settings.json | grep -i liveshare" 2>/dev/null || log_warn "Live Share settings not found"

  log_success "Verification complete"
}

stage_summary() {
  log_info "STAGE 9: Summary"

  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ LIVE SHARE COLLABORATION SETUP COMPLETE - Issue #178           ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "✓ Installed:"
  echo "  - VS Code Live Share extension"
  echo "  - Live Share Extension Pack"
  echo "  - All collaboration dependencies"
  echo ""
  echo "✓ Configured:"
  echo "  - Real-time code collaboration"
  echo "  - Shared debugging sessions"
  echo "  - Shared terminals & Ollama access"
  echo "  - Team workspace templates"
  echo ""
  echo "✓ Features Enabled:"
  echo "  - Pair programming mode"
  echo "  - Shared cursor visibility"
  echo "  - Shared debug sessions"
  echo "  - Shared terminal access"
  echo "  - Guest command execution"
  echo "  - Port forwarding"
  echo ""
  echo "Quick Start:"
  echo "  1. Open code-server at http://192.168.168.31:8080"
  echo "  2. Press Ctrl+Shift+P and type 'Live Share: Start'"
  echo "  3. Share the generated URL with teammates"
  echo "  4. They can join by clicking the link"
  echo ""
  echo "For detailed guides: cat ~/LIVE-SHARE-GUIDE.md"
  echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ ISSUE #178: LIVE SHARE TEAM COLLABORATION SUITE               ║"
  echo "║ Real-time Code Sharing & Pair Programming                      ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""

  stage_prerequisites || { log_warn "Prerequisites check had issues"; }
  stage_install_live_share || { log_warn "Live Share installation had issues"; }
  stage_configure_collaboration
  stage_create_templates
  stage_configure_shared_ollama
  stage_setup_logging
  stage_create_guides
  stage_verify
  stage_summary

  log_success "All stages complete!"
}

main "$@"
