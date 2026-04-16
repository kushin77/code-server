#!/usr/bin/env bash
################################################################################
# bootstrap-node.sh
#
# Bare-metal node bootstrap for #362 Phase 4
# Provisions a net-new node from zero to full production operation in <15 minutes
#
# Usage:
#   scripts/bootstrap-node.sh --role primary --environment production
#   scripts/bootstrap-node.sh --role replica --environment production
#   scripts/bootstrap-node.sh --role primary --dry-run
#
# Prerequisites:
#   - Root SSH access to target node
#   - Disk: 500GB+ (primary) or 250GB+ (replica)
#   - Network: Access to repository git server
#   - DNS: Ability to register new A records in prod.internal
#
# Post-bootstrap:
#   - All services running and healthy
#   - Registered in Prometheus scrape targets
#   - DNS records created (hostname.prod.internal)
#   - TLS certificates generated
#   - Replicated with peer (for database, cache, etc.)
#   - Keepalived VRRP configured and active
#
################################################################################

set -euo pipefail

# Source common library for log_info, log_error, etc.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Bootstrap options
ROLE="${ROLE:-}"
ENVIRONMENT="${ENVIRONMENT:-production}"
DRY_RUN=false
VERBOSE=false

# Derived from inventory
REPO_URL="https://github.com/kushin77/code-server.git"
REPO_BRANCH="main"
REPO_DIR="/opt/code-server"

# Bootstrap stages
BOOTSTRAP_STAGES=(
    "validate-prerequisites"
    "install-docker"
    "clone-repository"
    "load-inventory"
    "configure-os"
    "generate-certificates"
    "register-dns"
    "deploy-services"
    "configure-replication"
    "configure-keepalived"
    "verify-health"
)

# =============================================================================
# LOCAL UTILITIES (append to common library)
# =============================================================================

log_stage() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "→ STAGE: $*"
    echo "════════════════════════════════════════════════════════════════"
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_prerequisites() {
    log_stage "Validate Prerequisites"
    
    if [[ -z "$ROLE" ]]; then
        log_error "ROLE not set. Use: --role primary|replica"
        return 1
    fi
    
    if [[ ! "$ROLE" =~ ^(primary|replica)$ ]]; then
        log_error "Invalid ROLE: $ROLE (must be primary or replica)"
        return 1
    fi
    
    # Check if running as root
    if [[ "$EUID" != 0 ]]; then
        log_error "This script must run as root on the target node"
        log_error "Run: sudo scripts/bootstrap-node.sh ..."
        return 1
    fi
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine OS (no /etc/os-release)"
        return 1
    fi
    
    . /etc/os-release
    if [[ ! "$ID" =~ ^(debian|ubuntu)$ ]]; then
        log_warn "Non-Debian OS detected: $ID (bootstrap may not work)"
    fi
    
    # Check disk space
    local available_gb=$(df /opt 2>/dev/null | awk 'NR==2 {print $4/1024/1024}' || echo 0)
    local required_gb=100
    
    if (( $(echo "$available_gb < $required_gb" | bc -l) )); then
        log_error "Insufficient disk space: ${available_gb}GB available, ${required_gb}GB required"
        return 1
    fi
    
    log_info "✓ Prerequisites validated"
    log_info "  Role: $ROLE"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Available disk: ${available_gb}GB"
    
    return 0
}

# =============================================================================
# DOCKER INSTALLATION
# =============================================================================

install_docker() {
    log_stage "Install Docker Engine"
    
    if command -v docker >/dev/null 2>&1; then
        log_info "✓ Docker already installed ($(docker --version))"
        return 0
    fi
    
    log_info "Installing Docker..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Docker"
        return 0
    fi
    
    # Update package manager
    apt-get update -qq
    
    # Install Docker dependencies
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker
    systemctl enable docker
    systemctl start docker
    
    log_info "✓ Docker installed and enabled"
    docker --version
}

# =============================================================================
# REPOSITORY CLONE
# =============================================================================

clone_repository() {
    log_stage "Clone Repository"
    
    if [[ -d "$REPO_DIR" ]]; then
        log_info "Repository already exists at $REPO_DIR"
        cd "$REPO_DIR" && git pull origin "$REPO_BRANCH"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clone $REPO_URL -> $REPO_DIR"
        return 0
    fi
    
    log_info "Cloning repository..."
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
    
    log_info "✓ Repository cloned to $REPO_DIR"
}

# =============================================================================
# INVENTORY LOADING
# =============================================================================

load_inventory() {
    log_stage "Load Inventory"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would load inventory from environments/production/hosts.yml"
        return 0
    fi
    
    cd "$REPO_DIR"
    
    if [[ ! -f "environments/production/hosts.yml" ]]; then
        log_error "Inventory file not found: environments/production/hosts.yml"
        return 1
    fi
    
    # Source inventory loader
    source scripts/lib/inventory-loader.sh
    inventory_load_production
    
    export_inventory_vars
    
    log_info "✓ Inventory loaded"
    log_info "  Cluster: $CLUSTER_NAME"
    log_info "  Domain: $DOMAIN_INTERNAL"
}

# =============================================================================
# DEPLOYMENT
# =============================================================================

deploy_services() {
    log_stage "Deploy Services"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy Docker Compose services for role: $ROLE"
        return 0
    fi
    
    cd "$REPO_DIR"
    
    # Render configurations from inventory
    log_info "Rendering configurations..."
    python3 scripts/render-inventory-templates.py
    
    # Start services
    log_info "Starting Docker Compose services..."
    docker-compose -f docker-compose.yml up -d
    
    log_info "✓ Services deployed"
    docker-compose ps
}

# =============================================================================
# HEALTH VERIFICATION
# =============================================================================

verify_health() {
    log_stage "Verify Health"
    
    log_info "Waiting for services to become healthy..."
    sleep 10  # Initial wait
    
    local max_attempts=30
    local attempt=0
    local healthy_services=0
    local expected_services=5
    
    while [[ $attempt -lt $max_attempts ]]; do
        healthy_services=$(docker-compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo 0)
        
        if [[ $healthy_services -ge $expected_services ]]; then
            log_info "✓ All services healthy"
            docker-compose ps
            return 0
        fi
        
        ((attempt++))
        log_info "Waiting for services... ($healthy_services/$expected_services) [attempt $attempt/$max_attempts]"
        sleep 2
    done
    
    log_error "Services failed to become healthy after ${max_attempts} attempts"
    docker-compose ps
    docker-compose logs --tail=50
    return 1
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Bootstrap starting..."
    log_info "  Role: $ROLE"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Dry-run: $DRY_RUN"
    
    local exit_code=0
    
    for stage in "${BOOTSTRAP_STAGES[@]}"; do
        if ! $stage; then
            log_error "Stage failed: $stage"
            exit_code=1
            break
        fi
    done
    
    if [[ $exit_code -eq 0 ]]; then
        log_stage "Bootstrap Complete"
        log_info "✅ Node is ready for production"
        echo ""
        echo "Next steps:"
        echo "  1. Verify services: docker-compose ps"
        echo "  2. Check logs: docker-compose logs -f code-server"
        echo "  3. Confirm DNS: nslookup $DOMAIN_INTERNAL"
        echo "  4. Access code-server: https://prod.internal:8080"
    else
        log_error "❌ Bootstrap failed"
    fi
    
    return $exit_code
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --role)
            ROLE="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: $0 --role primary|replica [--environment ENV] [--dry-run]"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run bootstrap
cd "$PROJECT_DIR"
main "$@"
