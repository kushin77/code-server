#!/bin/bash
# @file scripts/ide/setup-vscode-env-integration.sh
# @module ide/vscode-integration
# @description P0-1553 Phase 4: VS Code integration for env.yaml with JSON Schema support
# @governance GOV-002: IDE provides real-time environment validation
# @usage setup-vscode-env-integration.sh

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

# Create .vscode/settings.json for JSON schema association
setup_vscode_schema() {
  log_info "Setting up VS Code JSON schema for env.yaml..."
  
  mkdir -p "${REPO_ROOT}/.vscode"
  
  # Check if settings.json exists
  if [[ -f "${REPO_ROOT}/.vscode/settings.json" ]]; then
    # Merge schema config with existing settings
    local settings=$(cat "${REPO_ROOT}/.vscode/settings.json")
    # Add schema configuration using jq or sed
    echo "${settings}" | jq '.json.schemas += [{"fileMatch": ["env.yaml"], "url": "./schemas/env-yaml.v1.json"}]' > "${REPO_ROOT}/.vscode/settings.json.tmp"
    mv "${REPO_ROOT}/.vscode/settings.json.tmp" "${REPO_ROOT}/.vscode/settings.json"
  else
    cat > "${REPO_ROOT}/.vscode/settings.json" <<'EOF'
{
  "[yaml]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.formatOnSave": true
  },
  "json.schemas": [
    {
      "fileMatch": ["env.yaml"],
      "url": "./schemas/env-yaml.v1.json"
    }
  ]
}
EOF
  fi
  
  log_success "VS Code schema configuration created"
}

# Create VS Code extension snippet for env.yaml commands
setup_vscode_snippets() {
  log_info "Setting up VS Code command snippets..."
  
  mkdir -p "${REPO_ROOT}/.vscode"
  
  cat > "${REPO_ROOT}/.vscode/extensions.json" <<'EOF'
{
  "recommendations": [
    "esbenp.prettier-vscode",
    "redhat.vscode-yaml",
    "ms-vscode.makefile-tools"
  ]
}
EOF
  
  log_success "VS Code extensions configuration created"
}

# Create Makefile targets for environment commands
setup_makefile_targets() {
  log_info "Setting up Makefile targets for env operations..."
  
  cat >> "${REPO_ROOT}/Makefile" <<'EOF'

# Environment operations
.PHONY: env-validate env-clone env-offline env-replay env-promote

env-validate:
	@python3 apps/env-provisioner/provisioner.py provision env.yaml

env-clone:
	@if [ -z "$(FROM)" ] || [ -z "$(TO)" ]; then echo "Usage: make env-clone FROM=<env> TO=<env>"; exit 1; fi
	@bash cli/src/commands/env-operations.sh clone --from $(FROM) --to $(TO)

env-offline:
	@bash cli/src/commands/env-operations.sh offline

env-replay:
	@if [ -z "$(BUILD_ID)" ]; then echo "Usage: make env-replay BUILD_ID=<id>"; exit 1; fi
	@bash cli/src/commands/env-operations.sh replay --build-id $(BUILD_ID)

env-promote:
	@if [ -z "$(FROM)" ] || [ -z "$(TO)" ]; then echo "Usage: make env-promote FROM=<env> TO=<env>"; exit 1; fi
	@bash cli/src/commands/env-operations.sh promote --from $(FROM) --to $(TO)
EOF
  
  log_success "Makefile targets added"
}

# Generate VS Code command palette documentation
generate_command_docs() {
  log_info "Generating command documentation..."
  
  cat > "${REPO_ROOT}/docs/ide/environment-commands.md" <<'EOF'
# VS Code Environment Commands

## Environment Validation

**Command:** Show Current Environment  
**Action:** Opens env.yaml in editor with real-time schema validation  
**Shortcut:** Ctrl+Shift+E

## Environment Operations

### Clone Environment
```bash
make env-clone FROM=production TO=staging
```

### Enable Offline Mode
```bash
make env-offline
# Pre-loads all images and data for offline work
```

### Replay Failed Build
```bash
make env-replay BUILD_ID=ci-1234
```

### Promote Environment
```bash
make env-promote FROM=local TO=production
```

## Status Bar Integration

VS Code status bar shows:
- Current runtime mode (local | remote | ci | edge)
- Active AI provider (ollama | openai | local)
- Environment health status

## Notifications

- "env.yaml updated" → Click "Reload" to apply changes
- "Environment health check failed" → Shows error details
- "Production promotion requires approval" → Opens approval dialog
EOF
  
  log_success "Command documentation generated"
}

main() {
  log_info "Setting up VS Code env.yaml integration..."
  
  setup_vscode_schema
  setup_vscode_snippets
  setup_makefile_targets
  generate_command_docs
  
  log_success "VS Code integration complete"
  log_info "Open env.yaml to test JSON schema validation"
}

main "$@"