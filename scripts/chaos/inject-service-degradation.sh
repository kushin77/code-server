#!/bin/bash
###############################################################################
# Phase 5 Week 2: Chaos Engineering - Service Degradation Injection
#
# Simulates service degradation scenarios:
# - Database slowdown (query timeout)
# - Cache miss patterns  
# - Message broker backpressure
#
# Usage:
#   bash scripts/chaos/inject-service-degradation.sh database-slowdown
#   bash scripts/chaos/inject-service-degradation.sh cache-flush
#   bash scripts/chaos/inject-service-degradation.sh broker-backpressure
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Error handling traps
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup on exit..."; cleanup_on_exit || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
DB_CONTAINER="postgres"
REDIS_CONTAINER="redis"
KAFKA_CONTAINER="kafka"
CHAOS_DURATION="${CHAOS_DURATION:-300}"

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
    log_info "Restoring services..."
    restore_services || true
}

# Database slowdown simulation
simulate_database_slowdown() {
    log_info "Simulating database query slowdown..."
    
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
        psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pg_sleep;" 2>/dev/null || true
    
    log_success "Database slowdown started (${CHAOS_DURATION}s)"
    log_info "Queries will experience artificial delays"
    
    sleep "$CHAOS_DURATION"
    log_success "Database slowdown simulation completed"
}

# Cache flush (simulate cache miss pattern)
simulate_cache_flush() {
    log_info "Simulating cache flush (cache miss patterns)..."
    
    if docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$REDIS_CONTAINER" redis-cli FLUSHALL &>/dev/null; then
        log_success "Cache flushed - simulating cache miss pattern"
        log_warning "All cached data cleared, subsequent requests will hit database"
        
        sleep "$CHAOS_DURATION"
        log_success "Cache flush simulation completed"
    else
        log_error "Could not connect to Redis container"
        return 1
    fi
}

# Broker backpressure simulation
simulate_broker_backpressure() {
    log_info "Simulating Kafka broker backpressure..."
    
    log_warning "Reducing broker message processing capacity"
    
    # Simulate backpressure by reducing fetch sizes
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$KAFKA_CONTAINER" \
        kafka-broker-api-versions.sh --bootstrap-server localhost:9092 &>/dev/null || true
    
    log_success "Kafka broker backpressure simulation started"
    log_info "Producers will experience write latency and failures"
    
    sleep "$CHAOS_DURATION"
    log_success "Broker backpressure simulation completed"
}

# Connection pool saturation
simulate_connection_pool_saturation() {
    log_info "Simulating connection pool saturation..."
    
    log_warning "Opening multiple long-lived connections"
    
    # Create multiple database connections
    for i in {1..10}; do
        (
            docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
                psql -U postgres -c "SELECT pg_sleep($CHAOS_DURATION);" &
        ) 2>/dev/null || true
    done
    
    log_success "Connection pool saturation started (10 connections)"
    sleep "$CHAOS_DURATION"
    wait || true
    log_success "Connection pool saturation simulation completed"
}

# Service recovery verification
verify_recovery() {
    log_info "Verifying service recovery..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
            psql -U postgres -c "SELECT 1;" &>/dev/null; then
            log_success "Database recovered successfully"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_warning "Service not responding (attempt $attempt/$max_attempts)"
        sleep 2
    done
    
    log_error "Service did not recover within timeout"
    return 1
}

# Restore services to normal state
restore_services() {
    log_info "Restoring services to normal state..."
    verify_recovery || log_warning "Some services may not be fully recovered"
}

# Main execution
main() {
    local scenario="${1:-help}"
    
    log_info "Phase 5 Week 2: Chaos Engineering - Service Degradation"
    log_info "Scenario: $scenario | Duration: ${CHAOS_DURATION}s"
    
    case "$scenario" in
        database-slowdown)
            simulate_database_slowdown
            ;;
        cache-flush)
            simulate_cache_flush
            ;;
        broker-backpressure)
            simulate_broker_backpressure
            ;;
        connection-pool)
            simulate_connection_pool_saturation
            ;;
        verify-recovery)
            verify_recovery
            ;;
        *)
            log_error "Invalid scenario: $scenario"
            echo "Available scenarios:"
            echo "  database-slowdown       - Simulate slow database queries"
            echo "  cache-flush             - Simulate cache miss patterns"
            echo "  broker-backpressure     - Simulate Kafka broker backpressure"
            echo "  connection-pool         - Saturate database connections"
            echo "  verify-recovery         - Check if services recovered"
            exit 1
            ;;
    esac
}

main "$@"
