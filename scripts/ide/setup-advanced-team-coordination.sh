#!/bin/bash
# Advanced Team Coordination Setup Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

log_info "Advanced Team Coordination setup"
log_info "Ensuring VS Code workspace settings for team coordination..."

WORKSPACE_DIR="${REPO_ROOT}/.vscode"
mkdir -p "${WORKSPACE_DIR}"

# Shared launch configurations
LAUNCH_FILE="${WORKSPACE_DIR}/launch.json"
if [[ ! -f "${LAUNCH_FILE}" ]]; then
  cat > "${LAUNCH_FILE}" <<'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug auth-server",
      "type": "python",
      "request": "launch",
      "module": "uvicorn",
      "args": ["main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"],
      "cwd": "${workspaceFolder}/apps/auth-server"
    },
    {
      "name": "Debug execution-scheduler",
      "type": "python",
      "request": "launch",
      "module": "uvicorn",
      "args": ["main:app", "--host", "0.0.0.0", "--port", "8030", "--reload"],
      "cwd": "${workspaceFolder}/apps/execution-scheduler"
    }
  ]
}
EOF
  log_info "Created .vscode/launch.json"
else
  log_info ".vscode/launch.json already exists (skipping)"
fi

# Recommended extensions for the team
EXTENSIONS_FILE="${WORKSPACE_DIR}/extensions.json"
if [[ ! -f "${EXTENSIONS_FILE}" ]]; then
  cat > "${EXTENSIONS_FILE}" <<'EOF'
{
  "recommendations": [
    "ms-python.python",
    "ms-python.pylance",
    "ms-azuretools.vscode-docker",
    "hashicorp.terraform",
    "timonwong.shellcheck",
    "eamodio.gitlens",
    "esbenp.prettier-vscode"
  ]
}
EOF
  log_info "Created .vscode/extensions.json"
else
  log_info ".vscode/extensions.json already exists (skipping)"
fi

log_info "Team coordination setup complete"
exit 0
