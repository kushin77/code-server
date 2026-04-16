#!/bin/bash
# Phase 2 Issue #184 - Git Proxy Deployment Script
# Production deployment automation for Git Credential Proxy

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
COMPOSE_FILE_1="${PROJECT_ROOT}/docker-compose.yml"
COMPOSE_FILE_2="${PROJECT_ROOT}/docker-compose.git-proxy.yml"
PROXY_PORT=8765
PROXY_CONTAINER="git-proxy-server"
DEPLOY_LOG="${PROJECT_ROOT}/deployment-phase2-#184.log"

# Colors
print_header() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_step() { echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# ============================================================================
# Validation Functions
# ============================================================================

validate_prerequisites() {
    print_header "Phase 2 #184: Git Proxy - Deployment Prerequisites"
    
    print_step "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        return 1
    fi
    print_success "Docker available: $(docker --version)"
    
    # Check Docker daemon
    if ! docker ps &> /dev/null; then
        print_error "Docker daemon is not running"
        return 1
    fi
    print_success "Docker daemon is running"
    
    # Check docker-compose
    if ! command -v docker-compose &> /dev/null; then
        print_error "docker-compose is not installed"
        return 1
    fi
    print_success "docker-compose available: $(docker-compose --version)"
    
    # Check compose files exist
    if [ ! -f "$COMPOSE_FILE_1" ]; then
        print_error "docker-compose.yml not found at $COMPOSE_FILE_1"
        return 1
    fi
    print_success "docker-compose.yml found"
    
    if [ ! -f "$COMPOSE_FILE_2" ]; then
        print_error "docker-compose.git-proxy.yml not found at $COMPOSE_FILE_2"
        return 1
    fi
    print_success "docker-compose.git-proxy.yml found"
    
    # Check SSH key exists
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        print_error "SSH key not found at $HOME/.ssh/id_rsa"
        return 1
    fi
    print_success "SSH key found at $HOME/.ssh/id_rsa"
    
    # Check git-proxy-server.py exists
    if [ ! -f "$SCRIPT_DIR/git-proxy-server.py" ]; then
        print_error "git-proxy-server.py not found at $SCRIPT_DIR/git-proxy-server.py"
        return 1
    fi
    print_success "git-proxy-server.py found"
    
    return 0
}

# ============================================================================
# Deployment Functions
# ============================================================================

build_container() {
    print_header "Step 1: Build Git Proxy Container"
    
    print_step "Building Dockerfile.git-proxy..."
    
    if docker-compose \
        -f "$COMPOSE_FILE_1" \
        -f "$COMPOSE_FILE_2" \
        build git-proxy-server 2>&1 | tee -a "$DEPLOY_LOG"; then
        print_success "Container image built successfully"
        return 0
    else
        print_error "Failed to build container image"
        return 1
    fi
}

start_service() {
    print_header "Step 2: Start Git Proxy Service"
    
    print_step "Starting git-proxy-server container..."
    
    if docker-compose \
        -f "$COMPOSE_FILE_1" \
        -f "$COMPOSE_FILE_2" \
        up -d git-proxy-server git-proxy-monitor 2>&1 | tee -a "$DEPLOY_LOG"; then
        print_success "Containers started successfully"
        sleep 5  # Wait for container to be ready
        return 0
    else
        print_error "Failed to start containers"
        return 1
    fi
}

verify_health() {
    print_header "Step 3: Verify Service Health"
    
    print_step "Checking if container is running..."
    
    if docker ps --filter "name=$PROXY_CONTAINER" --format "{{.State}}" | grep -q "running"; then
        print_success "Container is running"
    else
        print_error "Container is not running"
        docker logs "$PROXY_CONTAINER" 2>&1 | tail -20 | tee -a "$DEPLOY_LOG"
        return 1
    fi
    
    print_step "Waiting for health check to pass..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if docker exec "$PROXY_CONTAINER" curl -sf http://127.0.0.1:$PROXY_PORT/health &>/dev/null; then
            print_success "Health check passed"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 1
    done
    
    echo ""
    print_error "Health check failed after ${max_attempts}s"
    docker logs "$PROXY_CONTAINER" 2>&1 | tail -20 | tee -a "$DEPLOY_LOG"
    return 1
}

verify_endpoints() {
    print_header "Step 4: Verify API Endpoints"
    
    print_step "Checking /health endpoint..."
    
    # Check health without auth
    response=$(curl -sf http://127.0.0.1:$PROXY_PORT/health 2>/dev/null || echo "{}")
    if echo "$response" | grep -q '"status"'; then
        print_success "/health endpoint is working"
    else
        print_error "/health endpoint failed"
        return 1
    fi
    
    print_step "Checking /git/credentials endpoint (should be 401 without auth)..."
    
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST http://127.0.0.1:$PROXY_PORT/git/credentials \
        -H "Content-Type: application/json" \
        -d '{"operation":"get","host":"github.com"}' 2>/dev/null || echo "000")
    
    if [ "$response_code" = "401" ] || [ "$response_code" = "403" ]; then
        print_success "Authentication protection working (HTTP $response_code)"
    else
        print_error "Expected 401/403, got $response_code"
        return 1
    fi
    
    return 0
}

setup_credential_helper() {
    print_header "Step 5: Setup Git Credential Helper"
    
    local helper_script="$SCRIPT_DIR/git-credential-proxy.sh"
    
    if [ ! -f "$helper_script" ]; then
        print_error "git-credential-proxy.sh not found"
        return 1
    fi
    
    print_step "Installing credential helper to /usr/local/bin..."
    
    if sudo cp "$helper_script" /usr/local/bin/git-credential-proxy 2>/dev/null && \
       sudo chmod +x /usr/local/bin/git-credential-proxy 2>/dev/null; then
        print_success "Credential helper installed"
    else
        print_info "Credential helper installation skipped (requires sudo, do manually)"
    fi
    
    print_step "Configuring git to use proxy..."
    
    # Configure git to use proxy
    git config --global credential.helper proxy 2>&1 | tee -a "$DEPLOY_LOG"
    git config --global credential.useHttpPath true 2>&1 | tee -a "$DEPLOY_LOG"
    
    print_success "Git credential helper configured"
    return 0
}

test_deployment() {
    print_header "Step 6: Run Test Suite"
    
    local test_script="$SCRIPT_DIR/phase2-git-proxy-test.sh"
    
    if [ ! -f "$test_script" ]; then
        print_error "Test script not found at $test_script"
        return 1
    fi
    
    print_step "Running test suite..."
    
    if bash "$test_script" 2>&1 | tee -a "$DEPLOY_LOG"; then
        print_success "All tests passed"
        return 0
    else
        print_error "Some tests failed"
        return 1
    fi
}

generate_summary() {
    print_header "Phase 2 Issue #184: Deployment Summary"
    
    print_info "Git Proxy Server deployed successfully!"
    echo ""
    
    print_info "Service Details:"
    echo "  Container:     $PROXY_CONTAINER"
    echo "  Port:          $PROXY_PORT (local only)"
    echo "  Status:        $(docker ps --filter "name=$PROXY_CONTAINER" --format "{{.State}}")"
    echo ""
    
    print_info "Next Steps:"
    echo "  1. Export proxy URL and token:"
    echo "     export GIT_PROXY_URL=http://127.0.0.1:$PROXY_PORT"
    echo "     export GIT_PROXY_TOKEN=\$(cat ~/.git-proxy-token)"
    echo ""
    echo "  2. Test git operations:"
    echo "     cd /tmp && git clone https://github.com/example/repo.git"
    echo "     cd repo && git push origin feature-branch"
    echo ""
    echo "  3. Monitor audit logs:"
    echo "     docker exec $PROXY_CONTAINER tail -f /var/log/git-proxy/audit.log"
    echo ""
    echo "  4. Check Prometheus metrics:"
    echo "     curl http://127.0.0.1:9090/graph (search: git_proxy_*)"
    echo ""
    
    print_info "Deployment Log:"
    echo "  $DEPLOY_LOG"
    echo ""
}

# ============================================================================
# Rollback Functions
# ============================================================================

rollback() {
    print_header "ROLLBACK: Phase 2 Issue #184"
    
    print_step "Stopping git-proxy containers..."
    
    docker-compose \
        -f "$COMPOSE_FILE_1" \
        -f "$COMPOSE_FILE_2" \
        down git-proxy-server git-proxy-monitor 2>&1 | tee -a "$DEPLOY_LOG"
    
    print_success "Rollback complete"
    return 0
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    local exit_code=0
    
    echo "Git Proxy Deployment - Phase 2 Issue #184"
    echo "Started at: $(date)"
    echo "Log file: $DEPLOY_LOG"
    echo ""
    
    {
        # Step 0: Validate prerequisites
        if ! validate_prerequisites; then
            print_error "Prerequisites validation failed"
            exit 1
        fi
        
        # Step 1: Build container
        if ! build_container; then
            exit_code=1
            print_error "Build failed, rolling back..."
            rollback
            exit $exit_code
        fi
        
        # Step 2: Start service
        if ! start_service; then
            exit_code=1
            print_error "Service startup failed, rolling back..."
            rollback
            exit $exit_code
        fi
        
        # Step 3: Verify health
        if ! verify_health; then
            exit_code=1
            print_error "Health check failed, rolling back..."
            rollback
            exit $exit_code
        fi
        
        # Step 4: Verify endpoints
        if ! verify_endpoints; then
            exit_code=1
            print_error "Endpoint verification failed, rolling back..."
            rollback
            exit $exit_code
        fi
        
        # Step 5: Setup credential helper
        if ! setup_credential_helper; then
            print_error "Credential helper setup failed (non-fatal)"
        fi
        
        # Step 6: Run tests
        if ! test_deployment; then
            print_error "Deployment tests failed (non-fatal)"
        fi
        
        # Generate summary
        generate_summary
        
    } | tee -a "$DEPLOY_LOG"
    
    echo ""
    echo "Deployment finished at: $(date)"
    
    if [ $exit_code -eq 0 ]; then
        print_success "Deployment completed successfully!"
    else
        print_error "Deployment completed with errors (exit code: $exit_code)"
    fi
    
    return $exit_code
}

# Execute main
main "$@"
exit $?
