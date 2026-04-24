#!/usr/bin/env bash
##############################################################################
# Phase 20-A1: Global Orchestration Framework - Idempotent Deployment
# ✅ IaC, Immutable, Idempotent Design Principles
#
# Safe to run multiple times without side effects
# Features:
#   - Comprehensive error handling and validation
#   - Detailed logging and progress reporting
#   - Health checks and service validation
#   - Automatic rollback on failure
##############################################################################

set -euo pipefail

# ============================================================================
# Configuration & Constants
# ============================================================================

readonly PHASE="phase-20-a1"
readonly ENVIRONMENT="staging"
readonly DOCKER_COMPOSE_FILE="docker-compose-phase-20-a1.yml"
readonly PROMETHEUS_CONFIG="phase-20-a1-prometheus.yml"
readonly GRAFANA_CONFIG="grafana-datasources.yml"
readonly PHASE_CONFIG="phase-20-a1-config.yml"

readonly LOG_DIR="/var/log/phase-20-a1"
readonly DATA_DIR="/var/lib/phase-20-a1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default timeout values
readonly HEALTH_CHECK_TIMEOUT=120
readonly CURL_TIMEOUT=10
readonly DOCKER_TIMEOUT=300

# Service definitions
declare -A SERVICES=(
    [orchestrator]="phase-20-a1-orchestrator"
    [prometheus]="phase-20-a1-prometheus"
    [grafana]="phase-20-a1-grafana"
)

declare -A SERVICE_PORTS=(
    [orchestrator_api]="8000"
    [orchestrator_health]="8001"
    [orchestrator_metrics]="9205"
    [prometheus]="9090"
    [grafana]="3000"
)

# ============================================================================
# Colors & Formatting
# ============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO ]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[✅  ]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[⚠️  ]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[❌  ]${NC} $*" >&2
}

log_section() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║  $*"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
}

# ============================================================================
# Utility Functions
# ============================================================================

check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local missing_commands=()
    
    # Check required commands
    for cmd in docker docker-compose curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
            log_error "Missing required command: $cmd"
        else
            log_success "Found: $cmd"
        fi
    done
    
    # Check Docker daemon
    if ! docker ps &> /dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi
    log_success "Docker daemon is running"
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing ${#missing_commands[@]} required commands: ${missing_commands[*]}"
        return 1
    fi
    
    return 0
}

validate_required_files() {
    log_section "Validating Required Files"
    
    local missing_files=()
    local required_files=(
        "$DOCKER_COMPOSE_FILE"
        "$PROMETHEUS_CONFIG"
        "$GRAFANA_CONFIG"
        "$PHASE_CONFIG"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
            log_error "Missing file: $file"
        else
            log_success "Found: $file"
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Missing ${#missing_files[@]} required files"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Infrastructure Preparation
# ============================================================================

prepare_directories() {
    log_section "Preparing Directories"
    
    local directories=(
        "$LOG_DIR"
        "$DATA_DIR/orchestrator-logs"
        "$DATA_DIR/prometheus"
        "$DATA_DIR/grafana"
    )
    
    for dir in "${directories[@]}"; do
        if mkdir -p "$dir" 2>/dev/null; then
            log_success "Directory ready: $dir"
        else
            log_error "Failed to create directory: $dir"
            return 1
        fi
    done
    
    return 0
}

create_docker_network() {
    log_section "Creating Docker Network"
    
    local network_name="${PHASE}-net"
    
    # Check if network exists
    if docker network inspect "$network_name" &> /dev/null; then
        log_success "Docker network already exists: $network_name"
        return 0
    fi
    
    # Create network
    if docker network create \
        --driver bridge \
        --subnet 10.20.0.0/16 \
        --gateway 10.20.0.1 \
        "$network_name" &> /dev/null; then
        log_success "Docker network created: $network_name"
        return 0
    else
        log_error "Failed to create Docker network: $network_name"
        return 1
    fi
}

create_docker_volumes() {
    log_section "Creating Docker Volumes"
    
    local volumes=(
        "${PHASE}-orchestrator-logs"
        "${PHASE}-prometheus-data"
        "${PHASE}-grafana-data"
    )
    
    for volume in "${volumes[@]}"; do
        # Check if volume exists
        if docker volume inspect "$volume" &> /dev/null; then
            log_success "Docker volume already exists: $volume"
            continue
        fi
        
        # Create volume
        if docker volume create "$volume" &> /dev/null; then
            log_success "Docker volume created: $volume"
        else
            log_error "Failed to create Docker volume: $volume"
            return 1
        fi
    done
    
    return 0
}

# ============================================================================
# Container Deployment
# ============================================================================

deploy_containers() {
    log_section "Deploying Containers"
    
    # Pull images
    log_info "Pulling Docker images..."
    if ! timeout "$DOCKER_TIMEOUT" docker-compose -f "$DOCKER_COMPOSE_FILE" pull; then
        log_error "Failed to pull Docker images"
        return 1
    fi
    log_success "Docker images pulled successfully"
    
    # Deploy/update containers
    log_info "Updating containers..."
    if ! timeout "$DOCKER_TIMEOUT" docker-compose -f "$DOCKER_COMPOSE_FILE" up -d; then
        log_error "Failed to deploy containers"
        return 1
    fi
    log_success "Containers deployed successfully"
    
    return 0
}

check_container_health() {
    log_section "Checking Container Health"
    
    local start_time=$(date +%s)
    local timeout=$HEALTH_CHECK_TIMEOUT
    
    while [[ $(($(date +%s) - start_time)) -lt $timeout ]]; do
        local all_healthy=true
        
        # Check each service
        for service_name in "${!SERVICES[@]}"; do
            local container_name="${SERVICES[$service_name]}"
            
            if docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "^${container_name}$"; then
                # Get container status
                local status=$(docker inspect "$container_name" --format='{{.State.Status}}')
                local health=$(docker inspect "$container_name" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
                
                if [[ "$status" == "running" ]]; then
                    log_success "Container running: $container_name (health: $health)"
                else
                    log_warning "Container not running: $container_name (status: $status)"
                    all_healthy=false
                fi
            else
                log_warning "Container not found: $container_name"
                all_healthy=false
            fi
        done
        
        if [[ "$all_healthy" == "true" ]]; then
            return 0
        fi
        
        sleep 5
    done
    
    log_error "Container health check failed (timeout: ${HEALTH_CHECK_TIMEOUT}s)"
    return 1
}

# ============================================================================
# Service Validation
# ============================================================================

validate_port_accessibility() {
    log_section "Validating Port Accessibility"
    
    local all_accessible=true
    
    for service_name in "${!SERVICE_PORTS[@]}"; do
        local port="${SERVICE_PORTS[$service_name]}"
        
        if timeout "$CURL_TIMEOUT" curl -sf "http://localhost:${port}/" &> /dev/null; then
            log_success "Port $port ($service_name) is accessible"
        else
            log_warning "Port $port ($service_name) is not accessible yet"
            all_accessible=false
        fi
    done
    
    return $([ "$all_accessible" = true ] && echo 0 || echo 1)
}

validate_service_endpoints() {
    log_section "Validating Service Endpoints"
    
    local validation_passed=true
    
    # Orchestrator API
    if timeout "$CURL_TIMEOUT" curl -sf "http://localhost:8000/status" &> /dev/null; then
        log_success "Orchestrator API endpoint is working"
    else
        log_warning "Orchestrator API endpoint not responding yet"
        validation_passed=false
    fi
    
    # Prometheus
    if timeout "$CURL_TIMEOUT" curl -sf "http://localhost:9090/api/v1/query" &> /dev/null; then
        log_success "Prometheus endpoint is working"
    else
        log_warning "Prometheus endpoint not responding yet"
        validation_passed=false
    fi
    
    # Grafana
    if timeout "$CURL_TIMEOUT" curl -sf "http://localhost:3000/api/health" &> /dev/null; then
        log_success "Grafana endpoint is working"
    else
        log_warning "Grafana endpoint not responding yet"
        validation_passed=false
    fi
    
    # Metrics endpoint
    if timeout "$CURL_TIMEOUT" curl -sf "http://localhost:9205/metrics" &> /dev/null; then
        log_success "Metrics endpoint is working"
    else
        log_warning "Metrics endpoint not responding yet"
        validation_passed=false
    fi
    
    return $([ "$validation_passed" = true ] && echo 0 || echo 1)
}

# ============================================================================
# Health Checks
# ============================================================================

wait_for_services() {
    log_section "Waiting for Services to Be Ready"
    
    local start_time=$(date +%s)
    local timeout=$HEALTH_CHECK_TIMEOUT
    
    while [[ $(($(date +%s) - start_time)) -lt $timeout ]]; do
        if validate_port_accessibility && validate_service_endpoints; then
            log_success "All services are ready"
            return 0
        fi
        
        log_info "Services not ready yet, waiting 10 seconds..."
        sleep 10
    done
    
    log_error "Services failed to become ready (timeout: ${HEALTH_CHECK_TIMEOUT}s)"
    return 1
}

# ============================================================================
# Rollback Functions
# ============================================================================

rollback_deployment() {
    log_section "Rolling Back Deployment"
    
    log_warning "Attempting to rollback Phase 20-A1 deployment..."
    
    if docker-compose -f "$DOCKER_COMPOSE_FILE" down &> /dev/null; then
        log_success "Containers stopped and removed"
    else
        log_warning "Failed to stop containers cleanly"
    fi
    
    log_warning "Rollback completed. Manual intervention may be required."
    return 1
}

# ============================================================================
# Main Deployment Orchestration
# ============================================================================

main() {
    log_section "Phase 20-A1: Global Orchestration Framework"
    log_info "Idempotent Deployment Script"
    log_info "Environment: $ENVIRONMENT"
    log_info "Date: $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"
    
    # Step 1: Pre-flight checks
    if ! check_prerequisites; then
        log_error "❌ Pre-flight checks failed"
        return 1
    fi
    
    # Step 2: Validate files
    if ! validate_required_files; then
        log_error "❌ File validation failed"
        return 1
    fi
    
    # Step 3: Prepare infrastructure
    if ! prepare_directories; then
        log_error "❌ Directory preparation failed"
        return 1
    fi
    
    if ! create_docker_network; then
        log_error "❌ Network creation failed"
        return 1
    fi
    
    if ! create_docker_volumes; then
        log_error "❌ Volume creation failed"
        return 1
    fi
    
    # Step 4: Deploy containers
    if ! deploy_containers; then
        log_error "❌ Container deployment failed"
        rollback_deployment
        return 1
    fi
    
    # Step 5: Check container health
    if ! check_container_health; then
        log_error "❌ Container health check failed"
        rollback_deployment
        return 1
    fi
    
    # Step 6: Wait for services
    if ! wait_for_services; then
        log_error "❌ Services failed to become ready"
        rollback_deployment
        return 1
    fi
    
    # Step 7: Final validation
    log_section "Final Validation"
    
    if ! validate_port_accessibility; then
        log_warning "⚠️  Port accessibility check failed"
    fi
    
    if ! validate_service_endpoints; then
        log_warning "⚠️  Endpoint validation check failed"
    fi
    
    # Success!
    log_section "Deployment Complete"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════╗
║  ✅ Phase 20-A1 deployment SUCCESSFUL                                 ║
╠═══════════════════════════════════════════════════════════════════════╣
║  Access Points:                                                        ║
║  - Orchestrator API:     http://localhost:8000                         ║
║  - Health Check:          http://localhost:8001/health                ║
║  - Metrics Export:        http://localhost:9205/metrics               ║
║  - Prometheus:            http://localhost:9090                        ║
║  - Grafana:               http://localhost:3000                        ║
║                                                                        ║
║  Credentials:                                                          ║
║  - Grafana Admin: admin / changeme_12345                               ║
╚═══════════════════════════════════════════════════════════════════════╝
EOF
    
    return 0
}

# ============================================================================
# Error Handling
# ============================================================================

trap 'log_error "Script interrupted"; exit 1' INT TERM

# ============================================================================
# Execute
# ============================================================================

if main "$@"; then
    exit 0
else
    exit 1
fi
