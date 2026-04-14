#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Ollama Model Initialization & Code Repository Indexing
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common/init.sh" || exit 1

# Configuration
OLLAMA_ENDPOINT="${OLLAMA_ENDPOINT:-http://localhost:11434}"
WORKSPACE_PATH="${WORKSPACE_PATH:-/home/coder/workspace}"
MODELS=(
  "llama2:70b-chat"
  "codegemma"
  "neural-chat"
  "mistral"
)

# ─────────────────────────────────────────────────────────────────────────────
# Utility Functions
# ─────────────────────────────────────────────────────────────────────────────

# Check Ollama health
check_health() {
  local endpoint=$1
  local max_retries=5
  local retry_count=0

  while [ $retry_count -lt $max_retries ]; do
    if curl -sf "${endpoint}/api/tags" > /dev/null 2>&1; then
      log "✅ Ollama is healthy"
      return 0
    fi
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      log "⏳ Waiting for Ollama... (attempt $retry_count/$max_retries)"
      sleep 5
    fi
  done

  log "⚠️  Ollama not responding after $max_retries attempts"
  return 1
}

# Pull a model from Ollama
pull_model() {
  local model=$1
  local endpoint=$2

  log "Pulling model: $model"
  if curl -sf "${endpoint}/api/pull" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$model\",\"stream\":false}" > /dev/null 2>&1; then
    log "✅ Successfully pulled $model"
    return 0
  else
    log "⚠️  Failed to pull $model (may be in progress or network issue)"
    return 1
  fi
}

# List available models
list_models() {
  local endpoint=$1
  log "📦 Fetching available models from Ollama..."
  curl -sf "${endpoint}/api/tags" 2>/dev/null || log "⚠️  Could not fetch model list"
}

# Build repository index for code context (idempotent)
build_repo_index() {
  local workspace=$1
  local index_file="$workspace/.ollama-index.json"
  local index_hash_file="$workspace/.ollama-index.sha256"

  # Calculate current workspace structure hash
  local current_hash=""
  if command -v find >/dev/null 2>&1; then
    current_hash=$(find "$workspace" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" -o -name "README*" \) 2>/dev/null | sort | sha256sum | awk '{print $1}' || echo "")
  fi

  # Check if index is already current (idempotent)
  if [ -n "$current_hash" ] && [ -f "$index_hash_file" ]; then
    local stored_hash=$(cat "$index_hash_file" 2>/dev/null || echo "")
    if [ "$stored_hash" = "$current_hash" ] && [ -f "$index_file" ]; then
      log "✅ Repository index already current (skipping rebuild)"
      return 0
    fi
  fi

  log "🔍 Building repository index..."

  cat > "$index_file" << 'EOF'
{
  "indexed_at": "TIMESTAMP_PLACEHOLDER",
  "workspace": "WORKSPACE_PLACEHOLDER",
  "hash": "HASH_PLACEHOLDER",
  "structure": {
    "root_files": [],
    "key_directories": [],
    "source_files": [],
    "config_files": [],
    "documentation_files": []
  }
}
EOF

  # Store hash for next run
  if [ -n "$current_hash" ]; then
    echo "$current_hash" > "$index_hash_file"
  fi

  log "✅ Repository index created at $index_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Initialization Flow
# ─────────────────────────────────────────────────────────────────────────────

main() {
  log "🚀 Initializing Ollama integration..."

  # Stage 1: Health check
  log "Stage 1: Checking Ollama connectivity..."
  if ! check_health "$OLLAMA_ENDPOINT"; then
    log "⚠️  Ollama not yet ready, continuing with startup..."
  fi

  # Stage 2: Attempt to pull models
  log "Stage 2: Pulling elite models..."
  for model in "${MODELS[@]}"; do
    pull_model "$model" "$OLLAMA_ENDPOINT" || true
  done

  # Stage 3: List available models
  log "Stage 3: Listing available models..."
  list_models "$OLLAMA_ENDPOINT" || true

  # Stage 4: Build repository index (idempotent)
  log "Stage 4: Building repository context index..."
  if [ -d "$WORKSPACE_PATH" ]; then
    build_repo_index "$WORKSPACE_PATH"
  else
    log "⚠️  Workspace path not found: $WORKSPACE_PATH"
  fi

  log "✅ Ollama integration initialization complete"
}

main "$@"
