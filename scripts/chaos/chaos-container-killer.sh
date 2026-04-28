#!/bin/bash
###############################################################################
# Phase 5 Week 2: Chaos Engineering - Container Failure Scenarios
#
# Simulates container failure scenarios:
# - Random container termination
# - Cascading failure scenarios
# - Recovery time measurement
#
# Usage:
#   bash scripts/chaos/chaos-container-killer.sh random-kill
#   bash scripts/chaos/chaos-container-killer.sh cascading-failure
#   bash scripts/chaos/chaos-container-killer.sh measure-recovery
###############################################################################

set -euo pipefail

# Error handling traps
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup on exit..."; cleanup_on_exit || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
CHAOS_DURATION="${CHAOS_DURATION:-300}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-http://localhost:3100/health}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

cleanup_on_exit() {
    log_info "Restoring all services..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d 2>/dev/null || true
}

# Get list of services
get_services() {
    docker-compose -f "$DOCKER_COMPOSE_FILE" config --services | grep -v "^$"
}

# Get running container for service
get_container_id() {
    local service=$1
    docker-compose -f "$DOCKER_COMPOSE_FILE" ps -q "$service" 2>/dev/null || echo ""
}

# Verify service health
check_service_health() {
    curl -sf "$HEALTH_CHECK_URL" > /dev/null 2>&1
    return $?
}

# Random container termination
simulate_random_kill() {
    log_info "Simulating random container termination..."
    
    local services=($(get_services))
    local service_count=${#services[@]}
    
    if [ $service_count -eq 0 ]; then
        log_error "No services found"
        return 1
    fi
    
    log_warning "Will randomly terminate containers every 30 seconds"
    log_info "Running for ${CHAOS_DURATION} seconds..."
    
    local start_time=$(date +%s)
    local current_time=$start_time
    
    while [ $((current_time - start_time)) -lt "$CHAOS_DURATION" ]; do
        # Select random service
        local random_index=$((RANDOM % service_count))
        local target_service="${services[$random_index]}"
        
        log_warning "Terminating container: $target_service"
        docker-compose -f "$DOCKER_COMPOSE_FILE" kill "$target_service" 2>/dev/null || true
        
        # Give time for restart
        sleep 30
        
        # Restart the service
        docker-compose -f "$DOCKER_COMPOSE_FILE" up -d "$target_service" 2>/dev/null || true
        
        # Wait for recovery
        sleep 10
        
        current_time=$(date +%s)
    done
    
    log_success "Random container termination simulation completed"
}

# Cascading failure scenario
simulate_cascading_failure() {
    log_info "Simulating cascading failure scenario..."
    
    local services=($(get_services))
    
    log_warning "Phase 1: Terminate database service..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" kill postgres 2>/dev/null || true
    sleep 15
    
    log_warning "Phase 2: Observe cascading failures in dependent services..."
    for i in {1..3}; do
        local status="FAILED"
        if check_service_health 2>/dev/null; then
            status="OK"
        fi
        log_info "Health check attempt $i: $status"
        sleep 10
    done
    
    log_info "Phase 3: Restore database service..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d postgres 2>/dev/null || true
    sleep 15
    
    log_info "Phase 4: Monitor system recovery..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if check_service_health 2>/dev/null; then
            log_success "System recovered ($(( (attempt + 1) * 2 )) seconds)"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log_error "System did not fully recover within timeout"
    return 1
}

# Measure recovery time
measure_recovery_time() {
    log_info "Measuring recovery time after container failure..."
    
    log_warning "Terminating auth-server container..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" kill auth-server 2>/dev/null || true
    
    # Record time of failure
    local failure_time=$(date +%s)
    log_info "Failure time: $(date -d @$failure_time '+%Y-%m-%d %H:%M:%S')"
    
    log_info "Restarting container..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d auth-server 2>/dev/null || true
    
    # Monitor recovery
    log_info "Monitoring recovery..."
    local max_attempts=60
    local attempt=0
    local recovery_time=0
    
    while [ $attempt -lt $max_attempts ]; do
        if check_service_health 2>/dev/null; then
            local recovery_timestamp=$(date +%s)
            recovery_time=$((recovery_timestamp - failure_time))
            log_success "Service recovered in ${recovery_time} seconds"
            return 0
        fi
        
        log_warning "Recovery attempt $((attempt + 1))/$max_attempts..."
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log_error "Service did not recover within timeout (120 seconds)"
    return 1
}

# Main execution
main() {
    local scenario="${1:-help}"
    
    log_info "Phase 5 Week 2: Chaos Engineering - Container Failures"
    log_info "Scenario: $scenario"
    
    case "$scenario" in
        random-kill)
            simulate_random_kill
            ;;
        cascading-failure)
            simulate_cascading_failure
            ;;
        measure-recovery)
            measure_recovery_time
            ;;
        *)
            log_error "Invalid scenario: $scenario"
            echo "Available scenarios:"
            echo "  random-kill              - Randomly terminate containers"
            echo "  cascading-failure        - Simulate cascading failure"
            echo "  measure-recovery         - Measure container recovery time"
            exit 1
            ;;
    esac
}

main "$@"
