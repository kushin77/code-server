#!/bin/bash
###############################################################################
# Phase 5 Week 2: Chaos Engineering - Resource Exhaustion Tests
#
# Simulates resource exhaustion scenarios:
# - Memory pressure (disk full simulation)
# - CPU saturation
# - File descriptor exhaustion
#
# Usage:
#   bash scripts/chaos/resource-exhaustion-tests.sh memory-pressure
#   bash scripts/chaos/resource-exhaustion-tests.sh cpu-saturation
#   bash scripts/chaos/resource-exhaustion-tests.sh disk-full
#   bash scripts/chaos/resource-exhaustion-tests.sh file-descriptor-exhaustion
###############################################################################

set -euo pipefail

# Error handling traps
trap 'log_error "Script failed at line $LINENO"; cleanup_on_exit || true; exit 1' ERR
trap 'log_info "Cleanup on exit..."; cleanup_on_exit || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="/tmp/chaos-engineering"

# Configuration
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
TARGET_CONTAINER="auth-server"
CHAOS_DURATION="${CHAOS_DURATION:-300}"
MEMORY_MB="${MEMORY_MB:-512}"
CPU_WORKERS="${CPU_WORKERS:-4}"

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
    log_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}

# Memory pressure simulation
simulate_memory_pressure() {
    log_info "Simulating memory pressure..."
    mkdir -p "$TEMP_DIR"
    
    log_warning "Allocating ${MEMORY_MB}MB memory..."
    
    # Fill memory by creating large files
    dd if=/dev/zero of="$TEMP_DIR/memory-hog-1.bin" bs=1M count=$((MEMORY_MB / 2)) 2>/dev/null
    dd if=/dev/zero of="$TEMP_DIR/memory-hog-2.bin" bs=1M count=$((MEMORY_MB / 2)) 2>/dev/null
    
    log_success "Memory pressure simulation started (${MEMORY_MB}MB allocated)"
    log_info "Running for ${CHAOS_DURATION} seconds..."
    
    sleep "$CHAOS_DURATION"
    
    rm -f "$TEMP_DIR"/memory-hog-*.bin
    log_success "Memory pressure simulation completed"
}

# CPU saturation simulation
simulate_cpu_saturation() {
    log_info "Simulating CPU saturation..."
    
    log_warning "Starting ${CPU_WORKERS} CPU workers..."
    
    # Start CPU-intensive background processes
    for i in $(seq 1 "$CPU_WORKERS"); do
        (
            while true; do
                echo "Computing..." > /dev/null
                # CPU intensive task
                for j in {1..1000000}; do
                    _=$((j * j))
                done
            done
        ) &
        local pids+=($!)
    done
    
    log_success "CPU saturation simulation started (${CPU_WORKERS} workers)"
    log_info "Running for ${CHAOS_DURATION} seconds..."
    
    sleep "$CHAOS_DURATION"
    
    # Kill background processes
    for pid in "${pids[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    
    log_success "CPU saturation simulation completed"
}

# Disk full simulation
simulate_disk_full() {
    log_info "Simulating disk full condition..."
    mkdir -p "$TEMP_DIR"
    
    # Get available disk space
    local available=$(df "$TEMP_DIR" | awk 'NR==2 {print $4}')
    log_warning "Available disk space: ${available}KB"
    
    # Reserve 100MB for safety
    local fill_size=$((available - 100000))
    
    if [ $fill_size -gt 0 ]; then
        log_info "Filling disk (${fill_size}KB)..."
        dd if=/dev/zero of="$TEMP_DIR/disk-hog.bin" bs=1K count="$fill_size" 2>/dev/null || true
        log_success "Disk full simulation started"
        log_warning "Disk space now fully allocated"
    else
        log_warning "Insufficient disk space to perform simulation safely"
    fi
    
    log_info "Running for ${CHAOS_DURATION} seconds..."
    sleep "$CHAOS_DURATION"
    
    rm -f "$TEMP_DIR/disk-hog.bin"
    log_success "Disk full simulation completed"
}

# File descriptor exhaustion
simulate_file_descriptor_exhaustion() {
    log_info "Simulating file descriptor exhaustion..."
    mkdir -p "$TEMP_DIR"
    
    local fd_count=1000
    log_warning "Opening ${fd_count} file descriptors..."
    
    # Create and open many files
    for i in $(seq 1 "$fd_count"); do
        touch "$TEMP_DIR/fd-${i}.tmp" &
    done
    wait
    
    log_success "File descriptor exhaustion simulation started (${fd_count} files)"
    log_info "Running for ${CHAOS_DURATION} seconds..."
    
    sleep "$CHAOS_DURATION"
    
    rm -f "$TEMP_DIR"/fd-*.tmp
    log_success "File descriptor exhaustion simulation completed"
}

# Monitor resource usage during chaos
monitor_resources() {
    log_info "Starting resource monitoring..."
    
    local monitor_file="$TEMP_DIR/resource-usage.log"
    mkdir -p "$TEMP_DIR"
    
    (
        for i in $(seq 1 "$CHAOS_DURATION"); do
            {
                echo "=== Timestamp: $(date +%Y-%m-%d\ %H:%M:%S) ==="
                echo "Memory:"
                free -m
                echo ""
                echo "CPU Load:"
                uptime
                echo ""
                echo "Disk Usage:"
                df -h "$TEMP_DIR"
                echo ""
            } >> "$monitor_file"
            sleep 10
        done
    ) &
    
    log_success "Resource monitoring started (logging to $monitor_file)"
}

# Main execution
main() {
    local scenario="${1:-help}"
    
    log_info "Phase 5 Week 2: Chaos Engineering - Resource Exhaustion"
    log_info "Scenario: $scenario | Duration: ${CHAOS_DURATION}s"
    
    case "$scenario" in
        memory-pressure)
            simulate_memory_pressure
            ;;
        cpu-saturation)
            simulate_cpu_saturation
            ;;
        disk-full)
            simulate_disk_full
            ;;
        file-descriptor-exhaustion)
            simulate_file_descriptor_exhaustion
            ;;
        monitor)
            monitor_resources
            ;;
        *)
            log_error "Invalid scenario: $scenario"
            echo "Available scenarios:"
            echo "  memory-pressure             - Allocate and hold memory"
            echo "  cpu-saturation              - Start CPU-intensive processes"
            echo "  disk-full                   - Fill available disk space"
            echo "  file-descriptor-exhaustion  - Open many file descriptors"
            echo "  monitor                     - Monitor resource usage"
            exit 1
            ;;
    esac
}

main "$@"
