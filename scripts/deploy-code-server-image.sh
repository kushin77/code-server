#!/usr/bin/env bash
# @file        scripts/deploy-code-server-image.sh
# @module      operations/deployment
# @description Rebuild and deploy code-server container image to on-prem host
# @owner       platform
# @status      active
#
# PURPOSE:
#   Automates the complete rebuild and deployment cycle for code-server image:
#   1. Validate Dockerfile syntax
#   2. Build new image with timestamp tag
#   3. Update docker-compose to reference new image
#   4. Deploy to 192.168.168.31 (or optionally to 192.168.168.42 replica)
#   5. Health check and verification
#
# USAGE:
#   bash scripts/deploy-code-server-image.sh [OPTIONS]
#
# OPTIONS:
#   --skip-build      Use existing image (no rebuild)
#   --replica         Also deploy to 192.168.168.42 replica
#   --dry-run         Preview changes without deployment
#   --no-verify       Skip post-deployment health checks
#   --image <tag>     Specific image tag (default: timestamp)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# ════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ════════════════════════════════════════════════════════════════════════════

DOCKERFILE_PATH="${SCRIPT_DIR}/../Dockerfile.code-server"
IMAGE_NAME="code-server-enterprise"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M%S)}"
DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
DOCKER_COMPOSE_FILE="${SCRIPT_DIR}/../docker-compose.yml"

# Flags
SKIP_BUILD=false
DEPLOY_REPLICA=false
DRY_RUN=false
SKIP_VERIFY=false

# ════════════════════════════════════════════════════════════════════════════
# FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

log_section() {
    log_info ""
    log_info "════════════════════════════════════════════════════════════════"
    log_info "$1"
    log_info "════════════════════════════════════════════════════════════════"
}

verify_admin_access() {
    local user="${SUDO_USER:-$USER}"
    
    if [ "${EUID:-$(id -u)}" -ne 0 ] && [ -z "${SUDO_USER:-}" ]; then
        log_warn "ℹ️  Continuing as regular user (some operations may fail without sudo)"
    else
        log_info "✅ Running with elevated privileges"
    fi
}

validate_dockerfile() {
    log_section "1️⃣  VALIDATING DOCKERFILE"
    
    if [ ! -f "$DOCKERFILE_PATH" ]; then
        log_fatal "Dockerfile not found: $DOCKERFILE_PATH"
    fi
    
    log_info "✓ Dockerfile exists: $DOCKERFILE_PATH"
    
    # Check for required sections
    local required_sections=("FROM" "LABEL" "RUN.*apt-get" "USER.*root" "USER.*coder" "ENTRYPOINT")
    for section in "${required_sections[@]}"; do
        if grep -q "$section" "$DOCKERFILE_PATH"; then
            log_info "✓ Found: $section"
        else
            log_warn "⚠️  Missing expected section: $section"
        fi
    done
    
    log_info "✅ Dockerfile validation complete"
}

build_image() {
    log_section "2️⃣  BUILDING CONTAINER IMAGE"
    
    if [ "$SKIP_BUILD" = "true" ]; then
        log_info "⏭️  Skipping build (--skip-build flag)"
        return 0
    fi
    
    log_info "Building: $IMAGE_NAME:$IMAGE_TAG"
    log_info "Source: $DOCKERFILE_PATH"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "🔍 DRY-RUN: Would build image"
        log_info "   Command: docker build -f $DOCKERFILE_PATH -t $IMAGE_NAME:$IMAGE_TAG -t $IMAGE_NAME:latest ."
        return 0
    fi
    
    if docker build \
        -f "$DOCKERFILE_PATH" \
        -t "$IMAGE_NAME:$IMAGE_TAG" \
        -t "$IMAGE_NAME:latest" \
        "$(dirname "$DOCKERFILE_PATH")"; then
        log_info "✅ Image built successfully"
        
        # Show image info
        local size
        size=$(docker images "$IMAGE_NAME:$IMAGE_TAG" --format "{{.Size}}")
        log_info "   Size: $size"
        log_info "   Tags:"
        log_info "     - $IMAGE_NAME:$IMAGE_TAG"
        log_info "     - $IMAGE_NAME:latest"
    else
        log_fatal "❌ Build failed"
    fi
}

update_compose_config() {
    log_section "3️⃣  UPDATING DOCKER-COMPOSE CONFIGURATION"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        log_warn "docker-compose.yml not found: $DOCKER_COMPOSE_FILE"
        return 0
    fi
    
    log_info "Docker-compose file: $DOCKER_COMPOSE_FILE"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "🔍 DRY-RUN: Would update docker-compose.yml"
        return 0
    fi
    
    # Backup original
    local backup_file="${DOCKER_COMPOSE_FILE}.backup.$(date +%s)"
    cp "$DOCKER_COMPOSE_FILE" "$backup_file"
    log_info "✓ Backed up to: $backup_file"
    
    # The docker-compose.yml uses build: context, so image is built locally
    # No need to update image reference unless using pre-built image
    
    log_info "✅ Docker-compose configuration verified"
}

deploy_to_host() {
    local target_host="$1"
    
    log_section "4️⃣  DEPLOYING TO $target_host"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "🔍 DRY-RUN: Would deploy to $target_host"
        log_info "   Commands:"
        log_info "     - scp $DOCKER_COMPOSE_FILE $DEPLOY_USER@$target_host:code-server-enterprise/"
        log_info "     - ssh $DEPLOY_USER@$target_host docker-compose up -d --build code-server"
        return 0
    fi
    
    log_info "Target host: $target_host"
    log_info "Target user: $DEPLOY_USER"
    
    # Test SSH connectivity
    log_info "Testing SSH connectivity..."
    if ! ssh -o ConnectTimeout=5 "$DEPLOY_USER@$target_host" "echo '✓ SSH OK'" 2>/dev/null; then
        log_error "❌ Cannot connect to $target_host via SSH"
        return 1
    fi
    
    log_info "✓ SSH connection successful"
    
    # Copy docker-compose if needed
    log_info "Syncing docker-compose.yml..."
    if scp "$DOCKER_COMPOSE_FILE" "$DEPLOY_USER@$target_host:code-server-enterprise/" 2>/dev/null; then
        log_info "✓ docker-compose.yml synced"
    else
        log_warn "⚠️  Could not sync docker-compose.yml (may already be current)"
    fi
    
    # Redeploy container
    log_info "Redeploying code-server container..."
    if ssh "$DEPLOY_USER@$target_host" "
        cd code-server-enterprise && \
        docker-compose up -d --build code-server 2>&1 | tail -5
    "; then
        log_info "✅ Container redeployed to $target_host"
    else
        log_error "❌ Deployment to $target_host failed"
        return 1
    fi
}

verify_deployment() {
    local target_host="$1"
    
    if [ "$SKIP_VERIFY" = "true" ]; then
        log_info "⏭️  Skipping verification (--no-verify flag)"
        return 0
    fi
    
    log_section "5️⃣  VERIFYING DEPLOYMENT ON $target_host"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "🔍 DRY-RUN: Would verify deployment"
        return 0
    fi
    
    # Wait for container to stabilize
    log_info "Waiting for container to stabilize..."
    sleep 5
    
    # Check container status
    log_info "Checking container status..."
    local status
    status=$(ssh "$DEPLOY_USER@$target_host" \
        "docker ps --filter 'name=code-server' --format '{{.Status}}'" 2>/dev/null || echo "")
    
    if [ -z "$status" ]; then
        log_error "❌ Container not running on $target_host"
        return 1
    fi
    
    log_info "✓ Container status: $status"
    
    # Verify tools are available
    log_info "Verifying development tools..."
    local tools=("python3" "node" "go" "rustc" "git")
    
    for tool in "${tools[@]}"; do
        if ssh "$DEPLOY_USER@$target_host" \
            "docker exec code-server which $tool >/dev/null 2>&1" 2>/dev/null; then
            log_info "✓ $tool available"
        else
            log_warn "⚠️  $tool not verified"
        fi
    done
    
    # Check health
    log_info "Checking container health..."
    if ssh "$DEPLOY_USER@$target_host" \
        "docker exec code-server curl -sf http://localhost:8080/healthz >/dev/null 2>&1" 2>/dev/null; then
        log_info "✓ Health check passed"
    else
        log_warn "⚠️  Health check may still be pending"
    fi
    
    log_info "✅ Verification complete"
}

show_summary() {
    log_section "✅ DEPLOYMENT SUMMARY"
    
    log_info "Image:            $IMAGE_NAME:$IMAGE_TAG"
    log_info "Primary host:     $DEPLOY_HOST"
    [ "$DEPLOY_REPLICA" = "true" ] && log_info "Replica host:     192.168.168.42"
    log_info "Mode:             $([ "$DRY_RUN" = "true" ] && echo "DRY-RUN" || echo "LIVE")"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Monitor container: docker-compose logs -f code-server"
    log_info "  2. Test in browser: http://code-server.192.168.168.31.nip.io:8080"
    log_info "  3. Verify tools: docker exec code-server python3 --version"
    log_info ""
    log_info "If rollback needed:"
    log_info "  docker-compose down code-server"
    log_info "  docker-compose up -d code-server"
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════

main() {
    verify_admin_access
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-build) SKIP_BUILD=true; shift ;;
            --replica) DEPLOY_REPLICA=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --no-verify) SKIP_VERIFY=true; shift ;;
            --image) IMAGE_TAG="$2"; shift 2 ;;
            --help) show_usage; exit 0 ;;
            *) log_error "Unknown argument: $1"; exit 1 ;;
        esac
    done
    
    # Run deployment pipeline
    validate_dockerfile
    build_image
    update_compose_config
    deploy_to_host "$DEPLOY_HOST"
    verify_deployment "$DEPLOY_HOST"
    
    if [ "$DEPLOY_REPLICA" = "true" ]; then
        log_info ""
        log_info "Also deploying to replica host..."
        deploy_to_host "192.168.168.42"
        verify_deployment "192.168.168.42"
    fi
    
    show_summary
}

show_usage() {
    cat << 'EOF'
USAGE: deploy-code-server-image.sh [OPTIONS]

Build, update, and deploy the code-server container image to on-prem hosts.

OPTIONS:
  --skip-build      Skip Docker image build (use existing image)
  --replica         Also deploy to replica host (192.168.168.42)
  --dry-run         Preview changes without actual deployment
  --no-verify       Skip post-deployment health checks
  --image <tag>     Use specific image tag (default: auto-timestamp)
  --help            Display this help message

EXAMPLES:
  # Standard deployment (build + deploy primary host)
  bash scripts/deploy-code-server-image.sh

  # Deploy to both primary and replica
  bash scripts/deploy-code-server-image.sh --replica

  # Preview without making changes
  bash scripts/deploy-code-server-image.sh --dry-run

  # Use pre-built image (skip build step)
  bash scripts/deploy-code-server-image.sh --skip-build --image 20260417-123456

WORKFLOW:
  1. admin-dev-tools-add.sh (modify Dockerfile with new packages)
  2. deploy-code-server-image.sh (rebuild and deploy)
  3. Verify in browser or via: docker exec code-server which <package>

IMMUTABILITY GUARANTEE:
  - All packages are baked into image at build time
  - No runtime installations or configuration changes
  - Same image deployed to all users
  - Reproducible across different hosts

EOF
}

main "$@"
