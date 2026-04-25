#!/bin/bash
# @governance: Production deployment automation — ensures IaC compliance during deployment
# Purpose: Deploy code-server-enterprise to production with validation
# Author: Autonomous Agent
# Date: April 25, 2026

set -euo pipefail

# Source common utilities
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Deployment configuration (all env-var driven)
readonly TARGET_HOST="${DEPLOY_HOST:-192.168.168.31}"
readonly TARGET_USER="${DEPLOY_USER:-admin}"
readonly REPO_URL="${GIT_REPO_URL:-https://github.com/kushin77/code-server.git}"
readonly DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
readonly DEPLOY_TIMEOUT_SECONDS="${DEPLOY_TIMEOUT:-600}"
readonly HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-30}"
readonly HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"

# Color output for readability
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Verify prerequisites
verify_prerequisites() {
    log_info "Verifying deployment prerequisites..."
    
    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 "${TARGET_USER}@${TARGET_HOST}" "echo 'SSH connection OK'" &>/dev/null; then
        log_error "Cannot connect to ${TARGET_HOST}"
        return 1
    fi
    log_info "✓ SSH connectivity verified"
    
    # Check git available on target
    if ! ssh "${TARGET_USER}@${TARGET_HOST}" "command -v git &>/dev/null" &>/dev/null; then
        log_error "Git not available on target host"
        return 1
    fi
    log_info "✓ Git available on target"
    
    # Check docker available on target
    if ! ssh "${TARGET_USER}@${TARGET_HOST}" "command -v docker &>/dev/null" &>/dev/null; then
        log_error "Docker not available on target host"
        return 1
    fi
    log_info "✓ Docker available on target"
    
    return 0
}

# Deploy code to production
deploy_code() {
    log_info "Deploying code to production..."
    
    # SSH script to execute on target
    local deploy_script
    deploy_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
REPO_URL="${REPO_URL:-https://github.com/kushin77/code-server.git}"

# Clone or update repository
if [ -d "$REPO_PATH" ]; then
    echo "[DEPLOY] Updating existing repository..."
    cd "$REPO_PATH"
    git fetch origin
    git checkout "$DEPLOY_BRANCH"
    git pull origin "$DEPLOY_BRANCH"
else
    echo "[DEPLOY] Cloning repository..."
    git clone --branch "$DEPLOY_BRANCH" "$REPO_URL" "$REPO_PATH"
    cd "$REPO_PATH"
fi

# Validate repository state
echo "[DEPLOY] Validating repository state..."
git log --oneline -1
git status

echo "[DEPLOY] Code deployment successful"
EOFSCRIPT
)
    
    # Execute on target
    if ! ssh "${TARGET_USER}@${TARGET_HOST}" \
        "REPO_PATH=/root/code-server-enterprise DEPLOY_BRANCH=${DEPLOY_BRANCH} REPO_URL=${REPO_URL}" \
        bash -s <<< "$deploy_script"; then
        log_error "Code deployment failed"
        return 1
    fi
    
    log_info "✓ Code deployed successfully"
    return 0
}

# Validate IaC compliance on deployed code
validate_iac_on_target() {
    log_info "Validating IaC compliance on target..."
    
    local validate_script
    validate_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
cd "$REPO_PATH"

if [ ! -f "scripts/ci/validate-iac-compliance.sh" ]; then
    echo "[VALIDATE] ERROR: IaC compliance script not found"
    exit 1
fi

echo "[VALIDATE] Running IaC compliance checks..."
bash scripts/ci/validate-iac-compliance.sh

echo "[VALIDATE] IaC compliance validation passed"
EOFSCRIPT
)
    
    if ! ssh "${TARGET_USER}@${TARGET_HOST}" \
        "REPO_PATH=/root/code-server-enterprise" \
        bash -s <<< "$validate_script"; then
        log_error "IaC compliance validation failed on target"
        return 1
    fi
    
    log_info "✓ IaC compliance verified on target"
    return 0
}

# Start services with Docker Compose
start_services() {
    log_info "Starting services with docker-compose..."
    
    local start_script
    start_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
cd "$REPO_PATH"

echo "[SERVICES] Pulling latest images..."
docker compose pull

echo "[SERVICES] Starting services..."
docker compose up -d

echo "[SERVICES] Services started"
EOFSCRIPT
)
    
    if ! ssh "${TARGET_USER}@${TARGET_HOST}" \
        "REPO_PATH=/root/code-server-enterprise" \
        bash -s <<< "$start_script"; then
        log_error "Failed to start services"
        return 1
    fi
    
    log_info "✓ Services started"
    return 0
}

# Health check for deployment
health_check() {
    log_info "Running health checks (${HEALTH_CHECK_RETRIES} retries, ${HEALTH_CHECK_INTERVAL}s interval)..."
    
    local attempt=0
    local health_endpoint="http://${TARGET_HOST}:3100/api/health"
    
    while [ $attempt -lt "$HEALTH_CHECK_RETRIES" ]; do
        attempt=$((attempt + 1))
        
        if curl -sf "$health_endpoint" &>/dev/null; then
            log_info "✓ Health check passed on attempt ${attempt}"
            return 0
        fi
        
        log_warn "Health check attempt ${attempt}/${HEALTH_CHECK_RETRIES} failed, retrying in ${HEALTH_CHECK_INTERVAL}s..."
        sleep "$HEALTH_CHECK_INTERVAL"
    done
    
    log_error "Health check failed after ${HEALTH_CHECK_RETRIES} attempts"
    return 1
}

# Rollback deployment if needed
rollback_deployment() {
    log_warn "Rolling back deployment..."
    
    local rollback_script
    rollback_script=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/root/code-server-enterprise}"
cd "$REPO_PATH"

echo "[ROLLBACK] Stopping services..."
docker compose down

echo "[ROLLBACK] Resetting to previous commit..."
git reset --hard HEAD~1

echo "[ROLLBACK] Restarting previous version..."
docker compose up -d

echo "[ROLLBACK] Rollback complete"
EOFSCRIPT
)
    
    if ! ssh "${TARGET_USER}@${TARGET_HOST}" \
        "REPO_PATH=/root/code-server-enterprise" \
        bash -s <<< "$rollback_script"; then
        log_error "Rollback failed - MANUAL INTERVENTION REQUIRED"
        return 1
    fi
    
    log_info "✓ Rollback successful"
    return 0
}

# Main deployment workflow
main() {
    log_info "=== Code-Server-Enterprise Production Deployment ==="
    log_info "Target: ${TARGET_USER}@${TARGET_HOST}"
    log_info "Branch: ${DEPLOY_BRANCH}"
    log_info "Repository: ${REPO_URL}"
    
    # Execute deployment steps
    if ! verify_prerequisites; then
        log_error "Prerequisite checks failed"
        exit 1
    fi
    
    if ! deploy_code; then
        log_error "Code deployment failed"
        exit 1
    fi
    
    if ! validate_iac_on_target; then
        log_error "IaC validation failed"
        rollback_deployment || true
        exit 1
    fi
    
    if ! start_services; then
        log_error "Service startup failed"
        rollback_deployment || true
        exit 1
    fi
    
    if ! health_check; then
        log_error "Health check failed"
        rollback_deployment || true
        exit 1
    fi
    
    log_info "=== Deployment Complete ==="
    log_info "Services running at http://${TARGET_HOST}:3100"
    log_info "All IaC compliance checks passed"
    
    return 0
}

# Execute main workflow
main "$@"
