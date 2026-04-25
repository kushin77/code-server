#!/bin/bash
# @governance: External Ollama deployment — separate AI services from main stack
# Purpose: Deploy Ollama LLM services to external host with IaC compliance
# Author: Autonomous Agent
# Date: April 25, 2026

set -euo pipefail

# Deployment configuration (all env-var driven)
readonly OLLAMA_HOST="${OLLAMA_HOST:-192.168.168.31}"
readonly OLLAMA_USER="${OLLAMA_USER:-admin}"
readonly OLLAMA_PORT="${OLLAMA_PORT:-11434}"
readonly OLLAMA_REPO="${OLLAMA_REPO:-https://github.com/kushin77/ollama.git}"
readonly OLLAMA_BRANCH="${OLLAMA_BRANCH:-main}"
readonly OLLAMA_TIMEOUT="${OLLAMA_TIMEOUT:-300}"
readonly HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-20}"
readonly HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() {
    echo -e "${GREEN}[OLLAMA]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Verify Ollama deployment prerequisites
verify_ollama_prerequisites() {
    log_info "Verifying Ollama deployment prerequisites..."
    
    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 "${OLLAMA_USER}@${OLLAMA_HOST}" "echo 'SSH OK'" &>/dev/null; then
        log_error "Cannot connect to Ollama host ${OLLAMA_HOST}"
        return 1
    fi
    log_info "✓ Ollama host connectivity verified"
    
    # Check Docker
    if ! ssh "${OLLAMA_USER}@${OLLAMA_HOST}" "command -v docker &>/dev/null" &>/dev/null; then
        log_error "Docker not available on Ollama host"
        return 1
    fi
    log_info "✓ Docker available"
    
    # Check available disk space (Ollama models can be large)
    local disk_free
    disk_free=$(ssh "${OLLAMA_USER}@${OLLAMA_HOST}" "df /root | tail -1 | awk '{print \$4}'" || echo "0")
    if [ "$disk_free" -lt 50000000 ]; then
        log_warn "Low disk space available: ${disk_free}KB (recommend 50GB+)"
    fi
    log_info "✓ Prerequisites verified"
    
    return 0
}

# Deploy Ollama repository
deploy_ollama_repo() {
    log_info "Deploying Ollama repository..."
    
    local deploy_script
    deploy_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

OLLAMA_PATH="${OLLAMA_PATH:-/root/ollama}"
OLLAMA_REPO="${OLLAMA_REPO:-https://github.com/kushin77/ollama.git}"
OLLAMA_BRANCH="${OLLAMA_BRANCH:-main}"

if [ -d "$OLLAMA_PATH" ]; then
    echo "[OLLAMA-DEPLOY] Updating repository..."
    cd "$OLLAMA_PATH"
    git fetch origin
    git checkout "$OLLAMA_BRANCH"
    git pull origin "$OLLAMA_BRANCH"
else
    echo "[OLLAMA-DEPLOY] Cloning repository..."
    git clone --branch "$OLLAMA_BRANCH" "$OLLAMA_REPO" "$OLLAMA_PATH"
    cd "$OLLAMA_PATH"
fi

echo "[OLLAMA-DEPLOY] Verifying docker-compose.yml..."
if [ ! -f "docker-compose.yml" ]; then
    echo "[OLLAMA-DEPLOY] ERROR: docker-compose.yml not found"
    exit 1
fi

git log --oneline -1
echo "[OLLAMA-DEPLOY] Repository deployment complete"
EOFSCRIPT
)
    
    if ! ssh "${OLLAMA_USER}@${OLLAMA_HOST}" \
        "OLLAMA_PATH=/root/ollama OLLAMA_REPO=${OLLAMA_REPO} OLLAMA_BRANCH=${OLLAMA_BRANCH}" \
        bash -s <<< "$deploy_script"; then
        log_error "Ollama repository deployment failed"
        return 1
    fi
    
    log_info "✓ Ollama repository deployed"
    return 0
}

# Start Ollama services with Docker Compose
start_ollama_services() {
    log_info "Starting Ollama services..."
    
    local start_script
    start_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

OLLAMA_PATH="${OLLAMA_PATH:-/root/ollama}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"

cd "$OLLAMA_PATH"

echo "[OLLAMA-START] Pulling latest images..."
docker compose pull

echo "[OLLAMA-START] Starting Ollama services..."
docker compose up -d

echo "[OLLAMA-START] Services started, listening on port ${OLLAMA_PORT}"
docker compose ps

EOFSCRIPT
)
    
    if ! ssh "${OLLAMA_USER}@${OLLAMA_HOST}" \
        "OLLAMA_PATH=/root/ollama OLLAMA_PORT=${OLLAMA_PORT}" \
        bash -s <<< "$start_script"; then
        log_error "Failed to start Ollama services"
        return 1
    fi
    
    log_info "✓ Ollama services started"
    return 0
}

# Health check for Ollama endpoint
ollama_health_check() {
    log_info "Checking Ollama health (${HEALTH_CHECK_RETRIES} retries)..."
    
    local attempt=0
    local health_endpoint="http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/tags"
    
    while [ $attempt -lt "$HEALTH_CHECK_RETRIES" ]; do
        attempt=$((attempt + 1))
        
        if curl -sf "$health_endpoint" &>/dev/null; then
            log_info "✓ Ollama health check passed on attempt ${attempt}"
            # Get available models
            local models
            models=$(curl -s "$health_endpoint" | grep -o '"name":"[^"]*"' | head -3 || true)
            [ -n "$models" ] && log_info "Available models: $models"
            return 0
        fi
        
        log_warn "Attempt ${attempt}/${HEALTH_CHECK_RETRIES} failed, retrying in ${HEALTH_CHECK_INTERVAL}s..."
        sleep "$HEALTH_CHECK_INTERVAL"
    done
    
    log_error "Ollama health check failed after ${HEALTH_CHECK_RETRIES} attempts"
    return 1
}

# Configure main deployment to use external Ollama
configure_main_deployment() {
    log_info "Configuring main deployment for external Ollama..."
    
    if [ ! -f ".env.local" ]; then
        log_warn ".env.local not found, creating with Ollama configuration..."
        cat > .env.local <<EOF
# @governance: Environment configuration for external Ollama deployment
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Ollama configuration (external deployment)
OLLAMA_HOST=http://${OLLAMA_HOST}:${OLLAMA_PORT}
OLLAMA_API_KEY=\${OLLAMA_API_KEY:-}

# Services configuration
MEMORY_ENGINE_OLLAMA_HOST=\${OLLAMA_HOST}
MULTIMODAL_AI_OLLAMA_HOST=\${OLLAMA_HOST}

EOF
        log_info "✓ Created .env.local with Ollama configuration"
    else
        log_info "✓ .env.local already exists (review manually if needed)"
    fi
    
    return 0
}

# Verify connectivity between deployments
verify_deployment_connectivity() {
    log_info "Verifying connectivity between main and Ollama deployments..."
    
    local connectivity_check
    connectivity_check=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

MAIN_HOST="${MAIN_HOST:-192.168.168.31}"
MAIN_PORT="${MAIN_PORT:-3100}"
OLLAMA_HOST="${OLLAMA_HOST:-192.168.168.31}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"

echo "[CONNECTIVITY] Testing main deployment health..."
if ! curl -sf "http://${MAIN_HOST}:${MAIN_PORT}/api/health" &>/dev/null; then
    echo "[CONNECTIVITY] WARN: Main deployment not yet healthy"
fi

echo "[CONNECTIVITY] Testing Ollama endpoint..."
if ! curl -sf "http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/tags" &>/dev/null; then
    echo "[CONNECTIVITY] ERROR: Ollama not reachable"
    exit 1
fi

echo "[CONNECTIVITY] Both endpoints reachable"

EOFSCRIPT
)
    
    if ! ssh "${OLLAMA_USER}@${OLLAMA_HOST}" \
        "MAIN_HOST=192.168.168.31 MAIN_PORT=3100 OLLAMA_HOST=${OLLAMA_HOST} OLLAMA_PORT=${OLLAMA_PORT}" \
        bash -s <<< "$connectivity_check"; then
        log_warn "Connectivity check encountered issues"
        return 1
    fi
    
    log_info "✓ Deployment connectivity verified"
    return 0
}

# Main Ollama deployment workflow
main() {
    log_info "=== External Ollama Deployment (IaC Compliant) ==="
    log_info "Target: ${OLLAMA_USER}@${OLLAMA_HOST}:${OLLAMA_PORT}"
    log_info "Repository: ${OLLAMA_REPO}"
    log_info "Branch: ${OLLAMA_BRANCH}"
    
    if ! verify_ollama_prerequisites; then
        log_error "Prerequisite checks failed"
        exit 1
    fi
    
    if ! deploy_ollama_repo; then
        log_error "Ollama repository deployment failed"
        exit 1
    fi
    
    if ! start_ollama_services; then
        log_error "Ollama service startup failed"
        exit 1
    fi
    
    if ! ollama_health_check; then
        log_error "Ollama health check failed"
        exit 1
    fi
    
    if ! verify_deployment_connectivity; then
        log_warn "Deployment connectivity check encountered issues (may resolve after main deployment)"
    fi
    
    log_info "=== External Ollama Deployment Complete ==="
    log_info "Ollama API: http://${OLLAMA_HOST}:${OLLAMA_PORT}"
    log_info "Configure main deployment with: OLLAMA_HOST=http://${OLLAMA_HOST}:${OLLAMA_PORT}"
    
    return 0
}

main "$@"
