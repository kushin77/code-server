#!/bin/bash
###############################################################################
# Phase 5 Week 2: Chaos Engineering - Network Failures Simulation
# 
# Simulates various network failure scenarios to validate system resilience:
# - Packet loss (1%, 5%, 10%)
# - Latency injection (100ms, 500ms, 1s)
# - Network partitioning
#
# Requirements: tc (traffic control), iptables or firewall tools
#
# Usage:
#   bash scripts/chaos/simulate-network-failures.sh packet-loss 5
#   bash scripts/chaos/simulate-network-failures.sh latency 500
#   bash scripts/chaos/simulate-network-failures.sh partition eth0
#   bash scripts/chaos/simulate-network-failures.sh restore eth0
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Error handling traps
trap 'log_error "Script failed at line $LINENO"; cleanup_on_exit || true; exit 1' ERR
trap 'log_info "Performing cleanup..."; cleanup_on_exit || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
INTERFACE="${INTERFACE:-eth0}"
DOCKER_NETWORK="code-server"
TEST_DURATION="${TEST_DURATION:-300}"

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
    log_info "Restoring network configuration..."
    restore_network || true
}

# Network restoration
restore_network() {
    if command -v tc &> /dev/null; then
        sudo tc qdisc del dev "$INTERFACE" root 2>/dev/null || true
    fi
}

# Packet loss simulation
simulate_packet_loss() {
    local loss_percent=$1
    
    log_info "Simulating packet loss: ${loss_percent}%"
    log_warning "This requires root privileges"
    
    if ! command -v tc &> /dev/null; then
        log_error "tc (traffic control) not found. Install iproute2 package."
        return 1
    fi
    
    sudo tc qdisc add dev "$INTERFACE" root netem loss "${loss_percent}%"
    log_success "Packet loss simulation started (${loss_percent}%)"
    log_info "Running for ${TEST_DURATION} seconds..."
    
    sleep "$TEST_DURATION"
    restore_network
    log_success "Packet loss simulation completed"
}

# Latency injection
simulate_latency() {
    local latency_ms=$1
    
    log_info "Simulating latency: ${latency_ms}ms"
    log_warning "This requires root privileges"
    
    if ! command -v tc &> /dev/null; then
        log_error "tc (traffic control) not found. Install iproute2 package."
        return 1
    fi
    
    sudo tc qdisc add dev "$INTERFACE" root netem delay "${latency_ms}ms"
    log_success "Latency simulation started (${latency_ms}ms)"
    log_info "Running for ${TEST_DURATION} seconds..."
    
    sleep "$TEST_DURATION"
    restore_network
    log_success "Latency simulation completed"
}

# Network partition simulation
simulate_partition() {
    local target_ip=$1
    
    log_info "Simulating network partition: blocking traffic to ${target_ip}"
    log_warning "This requires root privileges"
    
    if command -v iptables &> /dev/null; then
        sudo iptables -A OUTPUT -d "$target_ip" -j DROP
        sudo iptables -A INPUT -s "$target_ip" -j DROP
        log_success "Network partition started (${target_ip})"
        log_info "Running for ${TEST_DURATION} seconds..."
        
        sleep "$TEST_DURATION"
        
        sudo iptables -D OUTPUT -d "$target_ip" -j DROP
        sudo iptables -D INPUT -s "$target_ip" -j DROP
        log_success "Network partition ended"
    else
        log_error "iptables not found"
        return 1
    fi
}

# Main execution
main() {
    local scenario="${1:-help}"
    
    case "$scenario" in
        packet-loss)
            simulate_packet_loss "${2:-5}"
            ;;
        latency)
            simulate_latency "${2:-500}"
            ;;
        partition)
            simulate_partition "${2:-10.0.0.0/8}"
            ;;
        restore)
            restore_network
            log_success "Network restored"
            ;;
        *)
            log_error "Invalid scenario: $scenario"
            echo "Usage:"
            echo "  $0 packet-loss <percent>"
            echo "  $0 latency <milliseconds>"
            echo "  $0 partition <ip_address>"
            echo "  $0 restore"
            exit 1
            ;;
    esac
}

main "$@"
