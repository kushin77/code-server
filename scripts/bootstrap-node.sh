#!/usr/bin/env bash
# @file        scripts/bootstrap-node.sh
# @module      bootstrap
# @description bootstrap node — on-prem code-server
# @owner       platform
# @status      active
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
if [[ -f "$SCRIPT_DIR/_common/init.sh" ]]; then
    source "$SCRIPT_DIR/_common/init.sh"
elif [[ -f "$(pwd)/scripts/_common/init.sh" ]]; then
    # CI smoke tests execute a temporary copy from /tmp; fall back to repo-relative path.
    source "$(pwd)/scripts/_common/init.sh"
else
    echo "FATAL: Cannot source _common/init.sh" >&2
    exit 1
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Bootstrap options
ROLE="${ROLE:-}"
ENVIRONMENT="${ENVIRONMENT:-production}"
DRY_RUN=false
VERBOSE=false
SKIP_DNS=false

# Derived from inventory (dedicated names avoid collisions with readonly globals from _common)
BOOTSTRAP_REPO_URL="${BOOTSTRAP_REPO_URL:-${REPO_URL:-https://github.com/kushin77/code-server.git}}"
BOOTSTRAP_REPO_BRANCH="${BOOTSTRAP_REPO_BRANCH:-${REPO_BRANCH:-main}}"
BOOTSTRAP_REPO_DIR="${BOOTSTRAP_REPO_DIR:-${REPO_DIR:-/opt/code-server}}"  # Configurable deployment path

# Bootstrap stages (ordered — names map to shell functions)
BOOTSTRAP_STAGES=(
    validate_prerequisites
    install_docker
    clone_repository
    load_inventory
    configure_os
    generate_certificates
    register_dns
    deploy_services
    configure_keepalived
    register_prometheus
    verify_health
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
    if [[ "$EUID" != 0 && "$DRY_RUN" != "true" ]]; then
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
    local available_gb
    available_gb=$(df /opt 2>/dev/null | awk 'NR==2 {print $4/1024/1024}' || echo 0)
    local required_gb=100
    
    if (( $(echo "$available_gb < $required_gb" | bc -l) )); then
        log_error "Insufficient disk space: ${available_gb}GB available, ${required_gb}GB required"
        return 1
    fi
    
    log_info "✓ Prerequisites validated"
    log_info "  Role: $ROLE"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Verbose: $VERBOSE"
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
    
    if [[ -d "$BOOTSTRAP_REPO_DIR" ]]; then
        log_info "Repository already exists at $BOOTSTRAP_REPO_DIR"
        cd "$BOOTSTRAP_REPO_DIR" && git pull origin "$BOOTSTRAP_REPO_BRANCH"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clone $BOOTSTRAP_REPO_URL -> $BOOTSTRAP_REPO_DIR"
        return 0
    fi
    
    log_info "Cloning repository..."
    mkdir -p "$(dirname "$BOOTSTRAP_REPO_DIR")"
    git clone -b "$BOOTSTRAP_REPO_BRANCH" "$BOOTSTRAP_REPO_URL" "$BOOTSTRAP_REPO_DIR"
    
    log_info "✓ Repository cloned to $BOOTSTRAP_REPO_DIR"
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
    
    cd "$BOOTSTRAP_REPO_DIR"
    
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

    cd "$BOOTSTRAP_REPO_DIR"

    log_info "Starting Docker Compose services..."
    if [[ "$ROLE" == "primary" ]]; then
        docker compose up -d
    else
        docker compose up -d code-server caddy redis postgres
    fi

    log_info "✓ Services deployed"
    docker compose ps
}

# =============================================================================
# OS HARDENING
# =============================================================================

configure_os() {
    log_stage "Configure OS"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure OS hardening and sysctl tuning"
        return 0
    fi

    # Increase file descriptor limits for VS Code
    if ! grep -q "code-server" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf <<'EOF'
# code-server enterprise — file descriptor limits
*    soft nofile 65536
*    hard nofile 65536
EOF
    fi

    # Tune kernel networking for enterprise use
    cat > /etc/sysctl.d/99-code-server.conf <<'EOF'
# code-server enterprise tuning
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.overcommit_memory = 1
EOF
    sysctl -p /etc/sysctl.d/99-code-server.conf >/dev/null 2>&1 || true

    log_info "✓ OS configured"
}

# =============================================================================
# TLS CERTIFICATES
# =============================================================================

generate_certificates() {
    log_stage "Generate TLS Certificates"

    local cert_dir="/etc/ssl/prod-internal"

    if [[ -f "${cert_dir}/server.crt" && -f "${cert_dir}/server.key" ]]; then
        log_info "✓ TLS certificates already present at ${cert_dir}"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would generate self-signed TLS certs in ${cert_dir}"
        return 0
    fi

    mkdir -p "${cert_dir}"
    local hostname
    hostname="$(hostname -f)"

    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout "${cert_dir}/server.key" \
        -out    "${cert_dir}/server.crt" \
        -subj   "/CN=${hostname}/O=code-server-enterprise/OU=on-prem" \
        -extensions san \
        -config <(cat /etc/ssl/openssl.cnf; echo -e "[san]\nsubjectAltName=DNS:${hostname},DNS:*.prod.internal,IP:$(hostname -I | awk '{print $1}')") \
        2>/dev/null

    chmod 600 "${cert_dir}/server.key"
    chmod 644 "${cert_dir}/server.crt"
    log_info "✓ Self-signed TLS certificate generated: ${cert_dir}/server.crt"
}

# =============================================================================
# DNS REGISTRATION
# =============================================================================

register_dns() {
    log_stage "Register DNS"

    if [[ "$SKIP_DNS" == "true" ]]; then
        log_info "Skipping DNS registration (--no-dns)"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would register $(hostname -f) in CoreDNS zone"
        return 0
    fi

    local host_ip
    host_ip="$(hostname -I | awk '{print $1}')"
    local hostname
    hostname="$(hostname -s)"
    local fqdn="${hostname}.prod.internal"

    # Configure systemd-resolved for .prod.internal
    if command -v systemd-resolve >/dev/null 2>&1; then
        mkdir -p /etc/systemd/resolved.conf.d
        cat > /etc/systemd/resolved.conf.d/prod-internal.conf <<EOF
[Resolve]
DNS=${DNS_SERVER:-192.168.168.31}
Domains=~prod.internal
EOF
        systemctl restart systemd-resolved || true
        log_info "✓ systemd-resolved configured for .prod.internal (DNS: ${DNS_SERVER:-192.168.168.31})"
    fi

    # Add /etc/hosts fallback entry (idempotent)
    if ! grep -q "${fqdn}" /etc/hosts 2>/dev/null; then
        echo "${host_ip}  ${fqdn} ${hostname}" >> /etc/hosts
    fi

    log_info "✓ DNS registration complete: ${fqdn} → ${host_ip}"
}

# =============================================================================
# KEEPALIVED (primary/replica VRRP)
# =============================================================================

configure_keepalived() {
    log_stage "Configure Keepalived (VRRP)"

    if [[ "$ROLE" != "primary" && "$ROLE" != "replica" ]]; then
        log_info "Skipping keepalived (role: $ROLE is not primary/replica)"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure keepalived VRRP for role: $ROLE"
        return 0
    fi

    # Install keepalived if not present
    if ! command -v keepalived >/dev/null 2>&1; then
        apt-get install -y keepalived 2>/dev/null || true
    fi

    local host_ip
    host_ip="$(hostname -I | awk '{print $1}')"
    local vip="192.168.168.100"
    local iface
    iface="$(ip route | awk '/default/ {print $5; exit}')"
    local priority
    [[ "$ROLE" == "primary" ]] && priority=110 || priority=100

    mkdir -p /etc/keepalived
    cat > /etc/keepalived/keepalived.conf <<EOF
! code-server enterprise — keepalived VRRP (auto-generated by bootstrap-node.sh)
! Role: ${ROLE} | Priority: ${priority} | VIP: ${vip}

vrrp_instance VI_1 {
    state $([ "$ROLE" = "primary" ] && echo "MASTER" || echo "BACKUP")
    interface ${iface}
    virtual_router_id 51
    priority ${priority}
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass code-server-vrrp
    }
    virtual_ipaddress {
        ${vip}
    }
}
EOF

    systemctl enable keepalived >/dev/null 2>&1 || true
    systemctl restart keepalived || log_info "Warning: keepalived start failed (may need network)"
    log_info "✓ Keepalived configured (VIP: ${vip}, priority: ${priority})"
}

# =============================================================================
# PROMETHEUS SCRAPE TARGET REGISTRATION
# =============================================================================

register_prometheus() {
    log_stage "Register Prometheus Scrape Target"

    local hostname
    hostname="$(hostname -s)"
    local host_ip
    host_ip="$(hostname -I | awk '{print $1}')"
    local targets_dir="${BOOTSTRAP_REPO_DIR}/config/prometheus/targets"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would add ${hostname} to Prometheus scrape targets at ${targets_dir}/${hostname}.yml"
        return 0
    fi

    if [[ ! -d "$BOOTSTRAP_REPO_DIR" ]]; then
        log_info "Skipping Prometheus registration (repo not cloned)"
        return 0
    fi

    mkdir -p "${targets_dir}"
    cat > "${targets_dir}/${hostname}.yml" <<EOF
# Auto-generated by bootstrap-node.sh — do not edit manually
# Role: ${ROLE} | Bootstrapped: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- targets:
    - "${host_ip}:9100"
  labels:
    job: "node"
    role: "${ROLE}"
    hostname: "${hostname}"
    env: "${ENVIRONMENT}"
EOF

    log_info "✓ Prometheus scrape target created: ${targets_dir}/${hostname}.yml"

    # Reload Prometheus if running locally
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "prometheus"; then
        docker kill --signal=SIGHUP prometheus >/dev/null 2>&1 || true
        log_info "✓ Prometheus reloaded"
    fi
}

# =============================================================================
# HEALTH VERIFICATION
# =============================================================================

verify_health() {
    log_stage "Verify Health"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would verify container health"
        return 0
    fi
    
    log_info "Waiting for services to become healthy..."
    sleep 10  # Initial wait
    
    local max_attempts=30
    local attempt=0
    local healthy_services=0
    local expected_services=5
    
    while [[ $attempt -lt $max_attempts ]]; do
        if healthy_services=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l 2>/dev/null); then
            :
        else
            healthy_services=0
        fi
        healthy_services="${healthy_services//[^0-9]/}"
        healthy_services="${healthy_services:-0}"
        
        if [[ $healthy_services -ge $expected_services ]]; then
            log_info "✓ All services healthy"
            docker compose ps
            return 0
        fi
        
        ((attempt++))
        log_info "Waiting for services... ($healthy_services/$expected_services) [attempt $attempt/$max_attempts]"
        sleep 2
    done
    
    log_error "Services failed to become healthy after ${max_attempts} attempts"
    docker compose ps
    docker compose logs --tail=50
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
        echo "  3. Confirm DNS: nslookup ${DOMAIN_INTERNAL:-prod.internal}"
        echo "  4. Access code-server: https://${DOMAIN_INTERNAL:-prod.internal}:${PORT_CODE_SERVER:-8080}"
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
        --no-dns)
            SKIP_DNS=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            cat <<'HELP'
Usage: sudo ./scripts/bootstrap-node.sh --role <primary|replica> [OPTIONS]

Provisions a bare-metal or VM host to production role in <15 minutes.

Options:
  --role     primary|replica       Node role (required)
  --env      ENV                   Target environment (default: production)
  --dry-run                        Print all steps without executing (safe audit)
  --no-dns                         Skip DNS registration (CoreDNS already running)
  --verbose                        Verbose logging
  --help                           Show this help

Examples:
  sudo ./scripts/bootstrap-node.sh --role primary
  sudo ./scripts/bootstrap-node.sh --role replica --dry-run
  sudo ./scripts/bootstrap-node.sh --role primary --no-dns

After bootstrap:
  docker compose ps              # Verify services
  docker compose logs -f         # Tail logs
  nslookup hostname.prod.internal # Confirm DNS
HELP
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run bootstrap
cd "${PROJECT_DIR:-$(pwd)}"
main "$@"
