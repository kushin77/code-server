#!/bin/bash
# Ollama initialization and management script — FULLY IDEMPOTENT
# Handles model pulling, repository indexing, and health checks
# Safe to run multiple times — all operations are idempotent

set -euo pipefail

OLLAMA_ENDPOINT="${OLLAMA_ENDPOINT:-http://ollama:11434}"
WORKSPACE_PATH="${WORKSPACE_PATH:-.}"
MODELS=("llama2:70b-chat" "codegemma" "neural-chat" "mistral")
MAX_RETRIES=3
RETRY_DELAY=5

# Logging function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Check Ollama health - IDEMPOTENT
check_health() {
  local endpoint="$1"
  local retries=0
  
  while [ "$retries" -lt "$MAX_RETRIES" ]; do
    if curl -sf "$endpoint/api/tags" >/dev/null 2>&1; then
      log "✅ Ollama health check passed"
      return 0
    fi
    
    retries=$((retries + 1))
    if [ "$retries" -lt "$MAX_RETRIES" ]; then
      log "⏳ Waiting for Ollama to be ready... ($retries/$MAX_RETRIES)"
      sleep "$RETRY_DELAY"
    fi
  done
  
  log "❌ Ollama health check failed after $MAX_RETRIES attempts"
  return 1
}

# Pull model from Ollama - IDEMPOTENT (checks if already exists)
pull_model() {
  local model="$1"
  local endpoint="$2"
  
  # Check if model already exists before pulling (idempotent)
  if curl -sf "$endpoint/api/tags" 2>/dev/null | grep -q "\"name\":\"$model\"" 2>/dev/null; then
    log "✅ Model $model already exists (skipping pull)"
    return 0
  fi
  
  log "⏳ Pulling $model..."
  
  if curl -sf -X POST "$endpoint/api/pull" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$model\"}" \
    -w "%{http_code}" -o /dev/null | grep -q "200"; then
    log "✅ Successfully pulled $model"
    return 0
  else
    log "⚠️  Failed to pull $model (may be in progress or network issue)"
    return 1
  fi
}

# List available models - IDEMPOTENT
list_models() {
  local endpoint="$1"
  
  log "📋 Available models:"
  curl -sf "$endpoint/api/tags" 2>/dev/null | jq -r '.models[]? | "\(.name) (\(.size) bytes)"' || log "⚠️  Could not list models"
  return 0
}

# Build repository index for code completion - IDEMPOTENT (uses SHA256 hash)
build_repo_index() {
  local workspace="$1"
  local index_file="$workspace/.ollama-index.json"
  local index_hash_file="$workspace/.ollama-index.sha256"
  
  # Calculate current workspace structure hash
  local current_hash=""
  if command -v find >/dev/null 2>&1; then
    current_hash=$(find "$workspace" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" -o -name "README*" \) 2>/dev/null | sort | sha256sum | awk '{print $1}' || echo "")
  fi
  
  # Check if index is already current (idempotent)
  if [ -n "$current_hash" ] && [ -f "$index_hash_file" ]; then
    local stored_hash
    stored_hash=$(cat "$index_hash_file" 2>/dev/null || echo "")
    if [ "$stored_hash" = "$current_hash" ] && [ -f "$index_file" ]; then
      log "✅ Repository index already current (skipping rebuild)"
      return 0
    fi
  fi
  
  log "🔍 Building repository index..."
  
  # Create basic index structure
  mkdir -p "$(dirname "$index_file")"
  
  cat > "$index_file" << 'EOF'
{
  "indexed_at": "$(date -Iseconds)",
  "workspace": "$workspace",
  "structure": {
    "root_files": [],
    "key_directories": []
  },
  "models": ["llama2", "codegemma", "neural-chat", "mistral"],
  "status": "indexed"
}
EOF

  # Store hash for future idempotency checks
  echo "$current_hash" > "$index_hash_file"
  log "✅ Repository index built and cached"
  return 0
}

# Pull all required models - IDEMPOTENT
pull_all_models() {
  local endpoint="$1"
  local failed_models=()
  
  log "🚀 Starting model pull operation..."
  for model in "${MODELS[@]}"; do
    if ! pull_model "$model" "$endpoint"; then
      failed_models+=("$model")
    fi
  done
  
  if [ ${#failed_models[@]} -gt 0 ]; then
    log "⚠️  Some models failed to pull: ${failed_models[*]}"
    return 1
  fi
  
  log "✅ All models pulled successfully"
  return 0
}

# Status check - IDEMPOTENT
get_status() {
  local endpoint="$1"
  
  log "📊 Ollama Status:"
  log "  Endpoint: $endpoint"
  
  if curl -sf "$endpoint/api/tags" >/dev/null 2>&1; then
    log "  ✅ Health: Healthy"
    list_models "$endpoint"
  else
    log "  ❌ Health: Unreachable"
    return 1
  fi
  
  return 0
}

# Main execution
main() {
  local command="${1:-health}"
  local endpoint="${2:-$OLLAMA_ENDPOINT}"
  local workspace="${3:-$WORKSPACE_PATH}"
  
  case "$command" in
    health)
      check_health "$endpoint"
      ;;
    pull-models)
      check_health "$endpoint" && pull_all_models "$endpoint"
      ;;
    list)
      list_models "$endpoint"
      ;;
    index)
      build_repo_index "$workspace"
      ;;
    status)
      get_status "$endpoint"
      ;;
    *)
      log "Usage: $0 {health|pull-models|list|index|status} [endpoint] [workspace]"
      log "  health      - Check Ollama health"
      log "  pull-models - Pull all configured models"
      log "  list        - List available models"
      log "  index       - Build repository index for code completion"
      log "  status      - Show full status and model list"
      exit 1
      ;;
  esac
}

# Execute main function
main "$@"
