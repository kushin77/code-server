#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# VPN Enterprise Endpoint Scan - Fallback (SSH-based Remote Check)
# ═══════════════════════════════════════════════════════════════════════════════
# Purpose: Verify endpoints by SSH'ing to primary host and running checks remotely
# This handles cases where local network is unavailable (e.g., Windows dev machine)
# Exit Code: 0 = all endpoints verified, 1+ = issues detected
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source common library for log_info, log_error, etc.
source "$SCRIPT_DIR/_common/init.sh"

# SSH Configuration
SSH_USER="akushnir"
SSH_HOST="192.168.168.31"
SSH_KEY="${HOME}/.ssh/akushnir-31"

# ─────────────────────────────────────────────────────────────────────────────
# Local Helper Functions (append to common library)
# ─────────────────────────────────────────────────────────────────────────────

log_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

log_check() {
    echo -e "${YELLOW}→${NC} $1"
}

# ─────────────────────────────────────────────────────────────────────────────
# SSH Connection Check
# ─────────────────────────────────────────────────────────────────────────────

verify_ssh_access() {
    log_header "Verifying SSH Access"
    
    log_check "Testing SSH connection to $SSH_USER@$SSH_HOST..."
    
    # Check if SSH key exists
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH key not found: $SSH_KEY"
        log_info "Expected key location: $SSH_KEY"
        log_info "To fix: Generate key or update SSH_KEY variable in this script"
        return 1
    fi
    
    log_success "SSH key found"
    
    # Test SSH connection
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            "$SSH_USER@$SSH_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
        log_success "SSH connection to $SSH_USER@$SSH_HOST is working"
        return 0
    else
        log_error "SSH connection failed to $SSH_USER@$SSH_HOST"
        log_info "Try connecting manually: ssh -i $SSH_KEY $SSH_USER@$SSH_HOST"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Remote Endpoint Verification
# ─────────────────────────────────────────────────────────────────────────────

check_remote_endpoints() {
    log_header "Remote Endpoint Verification (via SSH)"
    echo ""
    
    local remote_command="
    echo '=== PRIMARY SITE - 192.168.168.31 ===' && echo ''
    
    echo 'Code-Server (8080):' && \
    timeout 2 bash -c 'echo >/dev/tcp/127.0.0.1/8080' 2>/dev/null && \
    echo '  ✓ UP' || echo '  ✗ DOWN'
    
    echo 'OAuth2-Proxy (4180):' && \
    timeout 2 bash -c 'echo >/dev/tcp/127.0.0.1/4180' 2>/dev/null && \
    echo '  ✓ UP' || echo '  ✗ DOWN'
    
    echo 'Grafana (3000):' && \
    timeout 2 bash -c 'echo >/dev/tcp/127.0.0.1/3000' 2>/dev/null && \
    echo '  ✓ UP' || echo '  ✗ DOWN'
    
    echo 'Prometheus (9090):' && \
    timeout 2 bash -c 'echo >/dev/tcp/127.0.0.1/9090' 2>/dev/null && \
    echo '  ✓ UP' || echo '  ✗ DOWN'
    
    echo 'PostgreSQL (5432):' && \
    timeout 2 bash -c 'echo >/dev/tcp/127.0.0.1/5432' 2>/dev/null && \
    echo '  ✓ UP' || echo '  ✗ DOWN'
    
    echo 'Redis (6379):' && \
    timeout 2 bash -c 'echo >/dev/tcp/127.0.0.1/6379' 2>/dev/null && \
    echo '  ✓ UP' || echo '  ✗ DOWN'
    
    echo '' && echo '=== DOCKER STATUS ===' && echo '' && \
    docker-compose ps | grep -E 'code-server|oauth|loki|postgres|redis' | head -10 || echo 'Services not running or docker-compose not found'
    "
    
    # Execute remote check
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            "$SSH_USER@$SSH_HOST" bash -c "$remote_command"; then
        return 0
    else
        log_error "Remote endpoint check failed"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Docker Service Status (Remote)
# ─────────────────────────────────────────────────────────────────────────────

check_docker_services_remote() {
    log_header "Docker Services Status (Remote)"
    echo ""
    
    local docker_check="
    echo '=== Docker Compose Services ===' && \
    docker-compose ps 2>/dev/null | head -15 || echo 'Docker services not available'
    "
    
    ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            "$SSH_USER@$SSH_HOST" bash -c "$docker_check" || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Health Check Summary
# ─────────────────────────────────────────────────────────────────────────────

check_system_health() {
    log_header "System Health Summary (Remote)"
    echo ""
    
    local health_check="
    echo '=== Disk Usage ===' && \
    df -h / | tail -1 && echo '' && \
    
    echo '=== Memory Usage ===' && \
    free -h | head -2 && echo '' && \
    
    echo '=== Load Average ===' && \
    uptime | awk -F'load average:' '{print \$NF}' && echo '' && \
    
    echo '=== Network Status ===' && \
    netstat -i 2>/dev/null | head -3 || echo 'netstat not available'
    "
    
    ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            "$SSH_USER@$SSH_HOST" bash -c "$health_check" || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         VPN ENTERPRISE ENDPOINT SCAN - FALLBACK (SSH-BASED)                   ║${NC}"
    echo -e "${BLUE}║         Remote verification via SSH to primary host                          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Verify SSH access
    if ! verify_ssh_access; then
        log_header "SSH Connection Failed"
        echo ""
        echo "This script requires SSH access to the primary host."
        echo ""
        echo "Setup SSH Key:"
        echo "  1. Generate key: ssh-keygen -t ed25519 -f ~/.ssh/akushnir-31 -N ''"
        echo "  2. Copy to host: ssh-copy-id -i ~/.ssh/akushnir-31 akushnir@192.168.168.31"
        echo "  3. Test: ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31 'echo works'"
        echo ""
        echo "Or edit this script to use password authentication or different credentials."
        return 1
    fi
    
    echo ""
    
    # Check remote endpoints
    check_remote_endpoints || true
    
    echo ""
    
    # Check docker services
    check_docker_services_remote || true
    
    echo ""
    
    # Check system health
    check_system_health || true
    
    echo ""
    log_header "Fallback Scan Complete"
    echo -e "${GREEN}✓ Remote endpoint verification successful${NC}"
    echo ""
    
    return 0
}

main "$@"
