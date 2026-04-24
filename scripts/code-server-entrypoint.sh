#!/usr/bin/env bash
# @file        scripts/code-server-entrypoint.sh
# @module      code-server/bootstrap
# @description Entrypoint for code-server container with initialization and health checks

set -euo pipefail

# Source common initialization (in container: /usr/local/bin/_common)
source /usr/local/bin/_common/init.sh

# Initialize logging
log_info "Starting code-server initialization"

# Set working directory
WORKSPACE_DIR="/home/coder/workspace"
PROFILE_DIR="/home/coder/.local/share/code-server"

# Create directories if they don't exist
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$PROFILE_DIR"

# Apply product patch for Copilot Chat if needed
if [ -f "/usr/local/lib/code-server/product.json.patch" ]; then
    log_info "Applying product.json patch for Copilot Chat"
    patch /usr/local/lib/code-server/product.json < /usr/local/lib/code-server/product.json.patch || log_warn "Failed to apply product patch (may already be applied)"
fi

# Export standard environment variables
export WORKSPACE_DIR
export PROFILE_DIR

# Health check: Ensure code-server binary exists
if ! command -v code-server &>/dev/null; then
    log_error "code-server command not found"
    exit 1
fi

log_info "Code-server initialization complete, starting service"

# Start code-server with provided arguments
exec code-server "$@"
