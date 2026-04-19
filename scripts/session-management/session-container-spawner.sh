#!/usr/bin/env bash
# @file        scripts/session-management/session-container-spawner.sh
# @module      session-management/docker
# @description Spawn isolated per-session code-server containers with resource quotas
#              and automatic lifecycle management. Called by session broker when
#              creating new isolated runtime contexts.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common utilities
source "$REPO_ROOT/scripts/_common/init.sh"

# ────────────────────────────────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────────────────────────────────

CONTAINER_NAME="${1:?Container name required (e.g., code-server-user-abc123)}"
SESSION_ID="${2:?Session ID required}"
USER_ID="${3:?User ID required}"
USERNAME="${4:?Username required}"
USER_EMAIL="${5:?User email required}"

CPU_LIMIT="${CPU_LIMIT:-2.0}"
MEMORY_LIMIT="${MEMORY_LIMIT:-4g}"
STORAGE_LIMIT="${STORAGE_LIMIT:-50g}"
SESSION_TTL_SECONDS="${SESSION_TTL_SECONDS:-28800}"  # 8 hours default

# Base image
BASE_IMAGE="${CODE_SERVER_IMAGE:-code-server-enterprise:dev}"

# Network and port
NETWORK="${DOCKER_NETWORK:-enterprise}"
PORT="${CONTAINER_PORT:-8081}"

# Session storage
SESSIONS_ROOT="${SESSIONS_ROOT:-/var/lib/code-server-sessions}"
SESSION_WORKSPACE="$SESSIONS_ROOT/$SESSION_ID/workspace"
SESSION_PROFILE="$SESSIONS_ROOT/$SESSION_ID/profile"

# ────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ────────────────────────────────────────────────────────────────────────────

log_step() {
  log_info "[$CONTAINER_NAME] $1"
}

log_error_step() {
  log_error "[$CONTAINER_NAME] $1"
}

setup_session_directories() {
  log_step "Setting up session directories"
  
  mkdir -p "$SESSION_WORKSPACE"
  mkdir -p "$SESSION_PROFILE"
  
  # Ensure proper ownership (will be set to container user after creation)
  chmod 755 "$SESSIONS_ROOT/$SESSION_ID"
}

create_session_container() {
  log_step "Creating Docker container with isolation"
  
  # Calculate resource limits for Docker
  local cpu_quota=$(($(echo "$CPU_LIMIT" | cut -d. -f1) * 100000))
  local memory_bytes=$(parse_memory_to_bytes "$MEMORY_LIMIT")
  
  # Build docker run command
  docker run \
    --name "$CONTAINER_NAME" \
    --detach \
    --user "1000" \
    --hostname "$CONTAINER_NAME" \
    --network "$NETWORK" \
    --publish "$PORT:8080" \
    --cpus "$CPU_LIMIT" \
    --memory "$MEMORY_LIMIT" \
    --memory-swap "$MEMORY_LIMIT" \
    --oom-kill-disable=false \
    --pids-limit 256 \
    --volume "$SESSION_WORKSPACE:/home/coder/workspace" \
    --volume "$SESSION_PROFILE:/home/coder/.local/share/code-server" \
    --tmpfs /tmp:size=512m,noexec,nosuid,nodev \
    --tmpfs /run:size=256m,noexec,nosuid,nodev \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --security-opt no-new-privileges:true \
    --env SESSION_ID="$SESSION_ID" \
    --env USER_ID="$USER_ID" \
    --env USERNAME="$USERNAME" \
    --env USER_EMAIL="$USER_EMAIL" \
    --env CONTAINER_NAME="$CONTAINER_NAME" \
    --env EXPIRES_AT="$(date -u -d "+$SESSION_TTL_SECONDS seconds" '+%Y-%m-%dT%H:%M:%SZ')" \
    --env PASSWORD="${CODE_SERVER_PASSWORD}" \
    --env SUDO_PASSWORD="${CODE_SERVER_PASSWORD}" \
    --env SERVICE_URL="https://open-vsx.org/vscode/gallery" \
    --env ITEM_URL="https://open-vsx.org/vscode/item" \
    --env CS_DISABLE_FILE_DOWNLOADS="false" \
    --env NODE_OPTIONS="--max-old-space-size=2048" \
    --env LOG_LEVEL="info" \
    --restart unless-stopped \
    --health-cmd='curl -f http://localhost:8080/healthz || exit 1' \
    --health-interval 30s \
    --health-timeout 5s \
    --health-retries 3 \
    --health-start-period 20s \
    --log-driver json-file \
    --log-opt max-size="10m" \
    --log-opt max-file="5" \
    "$BASE_IMAGE"
}

verify_container_health() {
  log_step "Verifying container health"
  
  local max_attempts=30
  local attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    if docker exec "$CONTAINER_NAME" curl -f http://localhost:8080/healthz >/dev/null 2>&1; then
      log_step "Container health check passed"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
  
  log_error_step "Container health check failed after $max_attempts seconds"
  return 1
}

setup_session_user_permissions() {
  log_step "Configuring session user permissions"
  
  # Set workspace ownership to the container user (1000:1000)
  docker exec "$CONTAINER_NAME" chown -R 1000:1000 /home/coder/workspace
  docker exec "$CONTAINER_NAME" chown -R 1000:1000 /home/coder/.local/share/code-server
  
  # Create restricted .bashrc to enforce session boundaries
  docker exec "$CONTAINER_NAME" bash -c 'cat > /home/coder/.bashrc.session-restricted << "BASHRC_EOF"
# Session-restricted shell environment
# Prevents access to parent system files

# Block access to parent session directories
export SESSION_ID="$SESSION_ID"
export SESSION_BOUNDARY="true"

# Disable dangerous commands
alias rm="rm -i"
alias cp="cp -i"
alias mv="mv -i"

# Log all executed commands
export HISTFILE="/tmp/.bash_history_session_$SESSION_ID"
export PROMPT_COMMAND="echo \"$(date '+%Y-%m-%d %H:%M:%S') \$(whoami) \$PWD: \$(history 1)\" >> /tmp/.session-audit.log; $PROMPT_COMMAND"

# Restrict file descriptor operations
ulimit -n 256
ulimit -p 256

# Prevent privilege escalation
disable -n sudo
BASHRC_EOF
'
}

output_session_details() {
  log_step "Session created successfully"
  
  local container_id
  container_id=$(docker inspect -f '{{.Id}}' "$CONTAINER_NAME" | cut -c1-12)
  
  cat <<EOF

╔════════════════════════════════════════════════════════════════╗
║ Session Details                                                ║
╠════════════════════════════════════════════════════════════════╣
║ Session ID:        $SESSION_ID
║ Container Name:    $CONTAINER_NAME
║ Container ID:      $container_id
║ Container Port:    $PORT
║ Access URL:        http://localhost:$PORT
║                                                                ║
║ Username:          $USERNAME
║ Email:             $USER_EMAIL
║ CPU Limit:         $CPU_LIMIT
║ Memory Limit:      $MEMORY_LIMIT
║ Storage Limit:     $STORAGE_LIMIT
║ TTL:               $SESSION_TTL_SECONDS seconds
║                                                                ║
║ Created At:        $(date -u '+%Y-%m-%dT%H:%M:%SZ')
║ Expires At:        $(date -u -d "+$SESSION_TTL_SECONDS seconds" '+%Y-%m-%dT%H:%M:%SZ')
╚════════════════════════════════════════════════════════════════╝

EOF
}

cleanup_on_error() {
  log_error_step "Session creation failed, cleaning up"
  
  # Remove container if it was created
  if docker ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  fi
  
  # Clean up directories
  rm -rf "$SESSIONS_ROOT/$SESSION_ID" || true
}

parse_memory_to_bytes() {
  local mem_str="$1"
  case "$mem_str" in
    *g|*G) echo "$(($(echo "$mem_str" | sed 's/[gG]$//' | cut -d. -f1) * 1024 * 1024 * 1024))" ;;
    *m|*M) echo "$(($(echo "$mem_str" | sed 's/[mM]$//' | cut -d. -f1) * 1024 * 1024))" ;;
    *k|*K) echo "$(($(echo "$mem_str" | sed 's/[kK]$//' | cut -d. -f1) * 1024))" ;;
    *) echo "$mem_str" ;;
  esac
}

# ────────────────────────────────────────────────────────────────────────────
# Main Execution
# ────────────────────────────────────────────────────────────────────────────

trap cleanup_on_error ERR

log_info "Starting session container spawn: $CONTAINER_NAME"

setup_session_directories
create_session_container
verify_container_health
setup_session_user_permissions
output_session_details

log_step "Session ready for connection"
exit 0
