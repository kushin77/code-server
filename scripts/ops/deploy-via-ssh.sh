#!/bin/bash
# @file scripts/ops/deploy-via-ssh.sh
# @module infrastructure/deployment
# @description Phase 3: SSH orchestration for remote docker-compose deployment
# @governance OPS-001: All deployments managed via scripts, version-controlled

set -euo pipefail

# Source canonical bootstrap (provides log_info, log_error, and shared configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Trap handlers for error handling and cleanup
trap 'log_error "Deployment failed at line $LINENO"; cleanup; exit 1' ERR
trap 'log_info "Cleaning up temporary files..."; cleanup' EXIT

# ============================================================================
# Configuration & Defaults
# ============================================================================

WORKSPACE_ROOT="${1:-${REPO_ROOT}}"
DRY_RUN="${DRY_RUN:-false}"
DEPLOYMENT_LOG="${WORKSPACE_ROOT}/artifacts/deployment-$(date +%Y%m%d_%H%M%S).log"
RESULTS_FILE="${WORKSPACE_ROOT}/artifacts/deployment-results.json"

# SSH Configuration from environment
PRIMARY_HOST="${PRIMARY_HOST:-}"
REPLICA_HOST="${REPLICA_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-}"
SSH_PORT="${SSH_PORT:-22}"
SSH_TIMEOUT="${SSH_TIMEOUT:-300}"

# Deployment options
FORCE_RECREATE="${FORCE_RECREATE:-true}"
PROFILES="${PROFILES:-ai governance infrastructure all}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"

# Create artifacts directory
mkdir -p "${WORKSPACE_ROOT}/artifacts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    local msg="$1"
    echo -e "${BLUE}[INFO]${NC} ${msg}" | tee -a "$DEPLOYMENT_LOG"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[✓]${NC} ${msg}" | tee -a "$DEPLOYMENT_LOG"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[✗]${NC} ${msg}" | tee -a "$DEPLOYMENT_LOG"
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}[!]${NC} ${msg}" | tee -a "$DEPLOYMENT_LOG"
}

log_section() {
    echo "" | tee -a "$DEPLOYMENT_LOG"
    echo -e "${BLUE}════════════════════════════════════════${NC}" | tee -a "$DEPLOYMENT_LOG"
    echo -e "${BLUE}$1${NC}" | tee -a "$DEPLOYMENT_LOG"
    echo -e "${BLUE}════════════════════════════════════════${NC}" | tee -a "$DEPLOYMENT_LOG"
}

# ============================================================================
# Cleanup Function
# ============================================================================

cleanup() {
    # Remove temporary files
    rm -f /tmp/ssh-deploy-*.tmp 2>/dev/null || true
}

# ============================================================================
# Configuration Loading
# ============================================================================

load_config() {
    if [[ -f "${WORKSPACE_ROOT}/scripts/_common/config.env" ]]; then
        source "${WORKSPACE_ROOT}/scripts/_common/config.env"
        log_success "Loaded config.env"
    else
        log_warning "config.env not found, using environment variables"
    fi
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_configuration() {
    log_section "Configuration Validation"

    if [[ -z "$PRIMARY_HOST" ]]; then
        log_error "PRIMARY_HOST is not set"
        exit 1
    fi
    log_success "PRIMARY_HOST: $PRIMARY_HOST"

    if [[ -n "$REPLICA_HOST" && "$REPLICA_HOST" != "$PRIMARY_HOST" ]]; then
        log_success "REPLICA_HOST: $REPLICA_HOST"
    else
        log_warning "REPLICA_HOST not configured or same as primary"
    fi

    log_success "SSH_USER: $SSH_USER"
    log_success "SSH_PORT: $SSH_PORT"

    if [[ -n "$SSH_KEY" && ! -f "$SSH_KEY" ]]; then
        log_error "SSH_KEY file not found: $SSH_KEY"
        exit 1
    fi
    if [[ -n "$SSH_KEY" ]]; then
        log_success "SSH_KEY: $SSH_KEY"
    else
        log_info "SSH_KEY not specified, will use SSH agent or default key"
    fi
}

validate_docker_compose_files() {
    log_section "Docker-Compose Validation"

    local compose_files=(
        "${WORKSPACE_ROOT}/docker-compose.yml"
        "${WORKSPACE_ROOT}/docker-compose.override.yml"
    )

    for file in "${compose_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            exit 1
        fi
        log_success "File exists: $(basename "$file")"
    done

    # Validate docker-compose syntax
    if ! docker-compose -f "${WORKSPACE_ROOT}/docker-compose.yml" config >/dev/null 2>&1; then
        log_error "docker-compose.yml has syntax errors"
        exit 1
    fi
    log_success "docker-compose.yml syntax valid"
}

# ============================================================================
# SSH Connection Functions
# ============================================================================

build_ssh_command() {
    local host="$1"
    local cmd="ssh"
    
    # Add SSH key if specified
    if [[ -n "$SSH_KEY" ]]; then
        cmd="$cmd -i $SSH_KEY"
    fi
    
    # Add SSH options
    cmd="$cmd -o StrictHostKeyChecking=no"
    cmd="$cmd -o UserKnownHostsFile=/dev/null"
    cmd="$cmd -o ConnectTimeout=10"
    cmd="$cmd -o BatchMode=yes"
    cmd="$cmd -p $SSH_PORT"
    
    # Add user and host
    cmd="$cmd ${SSH_USER}@${host}"
    
    echo "$cmd"
}

test_ssh_connectivity() {
    local host="$1"
    local ssh_cmd=$(build_ssh_command "$host")
    
    log_info "Testing SSH connectivity to $host..."
    
    if $ssh_cmd "echo 'SSH connection successful'" >/dev/null 2>&1; then
        log_success "SSH connectivity to $host verified"
        return 0
    else
        log_error "Cannot connect to $host via SSH"
        return 1
    fi
}

check_remote_docker() {
    local host="$1"
    local ssh_cmd=$(build_ssh_command "$host")
    
    log_info "Checking Docker on $host..."
    
    if $ssh_cmd "docker --version && docker-compose --version" >/dev/null 2>&1; then
        log_success "Docker and docker-compose available on $host"
        return 0
    else
        log_error "Docker or docker-compose not available on $host"
        return 1
    fi
}

# ============================================================================
# Deployment Functions
# ============================================================================

deploy_to_host() {
    local host="$1"
    local host_type="$2"  # "primary" or "replica"
    
    log_section "Deploying to ${host_type} host: $host"
    
    if ! test_ssh_connectivity "$host"; then
        log_error "Cannot deploy to $host: SSH connection failed"
        return 1
    fi
    
    if ! check_remote_docker "$host"; then
        log_error "Cannot deploy to $host: Docker not available"
        return 1
    fi
    
    local ssh_cmd=$(build_ssh_command "$host")
    
    # Build docker-compose command with profiles
    local profile_flags=""
    for profile in $PROFILES; do
        profile_flags="$profile_flags --profile $profile"
    done
    
    # Build deployment commands
    local commands=(
        "set -e"
        "echo '[INFO] Deploying to $host_type host'"
        "cd code-server || cd ~/code-server || cd /opt/code-server"
        "echo '[INFO] Pulling latest configuration...'"
        "git pull origin main 2>/dev/null || echo '[WARN] Git pull not available'"
        "echo '[INFO] Starting Docker Compose with profiles: $PROFILES'"
    )
    
    # Add force-recreate if enabled
    if [[ "$FORCE_RECREATE" == "true" ]]; then
        commands+=("docker-compose $profile_flags up -d --force-recreate")
    else
        commands+=("docker-compose $profile_flags up -d")
    fi
    
    commands+=(
        "echo '[INFO] Waiting for services to stabilize (${HEALTH_CHECK_TIMEOUT}s)...'"
        "sleep ${HEALTH_CHECK_TIMEOUT}"
        "echo '[INFO] Checking health endpoint...'"
        "curl -fsS http://localhost:80/health || echo '[WARN] Health check pending, services may still be starting'"
        "echo '[SUCCESS] Deployment to $host_type host complete'"
    )
    
    # Join commands with semicolons for remote execution
    local remote_cmd=$(printf "%s; " "${commands[@]}" | sed 's/; $//')
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN - Would execute:"
        echo "$remote_cmd" | tee -a "$DEPLOYMENT_LOG"
        return 0
    fi
    
    # Execute deployment
    log_info "Executing deployment commands on $host..."
    if $ssh_cmd "$remote_cmd" 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
        log_success "Deployment to $host_type host ($host) completed successfully"
        return 0
    else
        log_error "Deployment to $host_type host ($host) failed"
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_section "Docker-Compose SSH Deployment"
    
    log_info "Start time: $(date -Iseconds)"
    log_info "Log file: $DEPLOYMENT_LOG"
    log_info "Dry run: $DRY_RUN"
    
    # Load configuration
    load_config
    
    # Validate configuration
    validate_configuration
    validate_docker_compose_files
    
    # Deploy to primary host
    if ! deploy_to_host "$PRIMARY_HOST" "primary"; then
        log_error "Primary host deployment failed"
        exit 1
    fi
    
    # Deploy to replica host if configured
    if [[ -n "$REPLICA_HOST" && "$REPLICA_HOST" != "$PRIMARY_HOST" ]]; then
        if ! deploy_to_host "$REPLICA_HOST" "replica"; then
            log_error "Replica host deployment failed"
            exit 1
        fi
    fi
    
    # Generate results
    log_section "Deployment Summary"
    
    local hosts_deployed=1
    if [[ -n "$REPLICA_HOST" && "$REPLICA_HOST" != "$PRIMARY_HOST" ]]; then
        hosts_deployed+=1
    fi
    
    log_success "Deployment complete!"
    log_info "Hosts deployed: $hosts_deployed"
    log_info "End time: $(date -Iseconds)"
    
    # Write JSON results
    cat > "$RESULTS_FILE" << EOJSON
{
  "timestamp": "$(date -Iseconds)",
  "status": "SUCCESS",
  "dry_run": "$DRY_RUN",
  "hosts_deployed": $hosts_deployed,
  "primary_host": "$PRIMARY_HOST",
  "replica_host": "${REPLICA_HOST:-none}",
  "profiles": "$PROFILES",
  "deployment_log": "$DEPLOYMENT_LOG"
}
EOJSON
    
    log_success "Results file: $RESULTS_FILE"
    
    return 0
}

# ============================================================================
# Execution
# ============================================================================

# Show usage if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << 'HELP'
Usage: deploy-via-ssh.sh [WORKSPACE_ROOT] [OPTIONS]

Description:
  Deploy Docker Compose services to remote hosts via SSH

Environment Variables:
  PRIMARY_HOST          Target primary host (required)
  REPLICA_HOST          Target replica host (optional)
  SSH_USER              SSH user (default: root)
  SSH_KEY               SSH private key path (optional)
  SSH_PORT              SSH port (default: 22)
  DRY_RUN               If 'true', show what would be executed (default: false)
  FORCE_RECREATE        If 'true', force recreate containers (default: true)
  PROFILES              Docker-compose profiles (default: ai governance infrastructure all)

Examples:
  # Deploy to primary host
  PRIMARY_HOST=10.0.1.10 bash scripts/ops/deploy-via-ssh.sh

  # Dry run
  DRY_RUN=true PRIMARY_HOST=10.0.1.10 bash scripts/ops/deploy-via-ssh.sh

  # Deploy to primary and replica
  PRIMARY_HOST=10.0.1.10 REPLICA_HOST=10.0.1.11 bash scripts/ops/deploy-via-ssh.sh

  # With specific SSH key
  PRIMARY_HOST=10.0.1.10 SSH_KEY=~/.ssh/deploy_key bash scripts/ops/deploy-via-ssh.sh
HELP
    exit 0
fi

main "$@"
