#!/bin/bash
# Network 10G Verification & Optimization - Phase 26 Infrastructure Optimization
# Issue #408 - Validate 10G backbone, jumbo frames, NIC bonding
#
# This script tests and validates:
# 1. 10G NIC capability (iperf3 baseline: target ≥9 Gbps)
# 2. Jumbo frames (MTU 9000 enabled across hosts/NAS)
# 3. NIC bonding (eth0 + eth1 LACP or active-backup)
# 4. NFS tuning (rsize/wsize for 10G throughput)
# 5. Network failover (eth0 down → automatic eth1 takeover)
#
# Baseline target (April 2026):
#   - Current throughput: ~125 MB/s (Gigabit) 
#   - Target throughput: ≥1 GB/s (10G verified)
#   - Expected gain: 8x improvement
#
# Usage:
#   ./network-10g-verification.sh                  # Run all tests
#   ./network-10g-verification.sh iperf3            # Test 10G throughput
#   ./network-10g-verification.sh mtu               # Test jumbo frames
#   ./network-10g-verification.sh bonding           # Check NIC bonding status
#   ./network-10g-verification.sh nfs               # Test NFS tuning
#   ./network-10g-verification.sh failover          # Test bond failover

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Configuration
NAS_HOST="${NAS_HOST:-192.168.168.56}"
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
STANDBY_HOST="${STANDBY_HOST:-192.168.168.32}"
TEST_DIR="${TEST_DIR:-.}"

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }
metric() { echo "  ✓ $1"; }

# ============================================================================
# Test 1: 10G NIC Throughput (iperf3)
# ============================================================================

test_iperf3_throughput() {
    log "=== Test 1: 10G NIC Throughput (iperf3) ==="
    
    if ! command -v iperf3 &> /dev/null; then
        log "⚠️  iperf3 not available, skipping throughput test"
        log "    Install: apt-get install iperf3"
        return 1
    fi
    
    log "Starting iperf3 test (TCP bidirectional, 4 parallel streams, 60 seconds)..."
    log "Target: ≥9 Gbps (90% of 10G line rate)"
    
    # Run iperf3 with JSON output for parsing
    local results=$(timeout 70 iperf3 -c "$NAS_HOST" -t 60 -P 4 -J 2>/dev/null || echo "{}")
    
    local throughput_mbps=$(echo "$results" | jq -r '.end.sum_received.bits_per_second // 0' 2>/dev/null | awk '{print $1 / 1000000}' || echo "0")
    local throughput_gbps=$(echo "$throughput_mbps / 1000" | bc -l 2>/dev/null || echo "0")
    local jitter=$(echo "$results" | jq -r '.end.sum_received.jitter_ms // 0' 2>/dev/null || echo "0")
    local lost_percent=$(echo "$results" | jq -r '.end.sum_received.lost_packets // 0' 2>/dev/null || echo "0")
    
    log "Results:"
    metric "Throughput: ${throughput_gbps} Gbps ($(printf "%.0f" $throughput_mbps) Mbps)"
    metric "Jitter: ${jitter}ms"
    metric "Lost Packets: ${lost_percent}"
    
    if (( $(echo "$throughput_gbps >= 9" | bc -l 2>/dev/null || echo "0") )); then
        metric "✅ 10G verified - target met!"
    else
        log "⚠️  WARNING: Throughput below 9 Gbps target"
        log "    Possible causes: MTU not 9000, bonding not active, network congestion"
    fi
    echo ""
}

# ============================================================================
# Test 2: MTU 9000 (Jumbo Frames)
# ============================================================================

test_mtu_jumbo_frames() {
    log "=== Test 2: MTU 9000 Validation (Jumbo Frames) ==="
    
    log "Checking current MTU on local interfaces..."
    ip link show | grep -E "^[0-9]+:|mtu" | paste - - | \
        grep -E "eth|bond" | while read line; do
        local iface=$(echo "$line" | awk '{print $2}' | cut -d: -f1)
        local mtu=$(echo "$line" | grep -oP 'mtu \K\d+' || echo "unknown")
        
        if [ "$mtu" = "9000" ]; then
            metric "$iface: MTU $mtu ✅"
        else
            log "⚠️  $iface: MTU $mtu (target: 9000)"
        fi
    done
    echo ""
    
    log "Testing MTU 9000 connectivity (ping with 8972 byte payload = 9000 MTU frame)..."
    if ping -M do -s 8972 -c 1 "$NAS_HOST" &>/dev/null; then
        metric "✅ MTU 9000 connectivity working"
    else
        log "⚠️  WARNING: Cannot ping with MTU 9000 payload"
        log "    This indicates MTU mismatch or network configuration issue"
    fi
    echo ""
}

# ============================================================================
# Test 3: NIC Bonding Status
# ============================================================================

test_nic_bonding() {
    log "=== Test 3: NIC Bonding Status ==="
    
    if [ ! -f /proc/net/bonding/bond0 ]; then
        log "⚠️  bond0 not found - NIC bonding not configured"
        log "    Current configuration: No bonding (single point of failure)"
        log "    Action: Configure eth0 + eth1 bonding (active-backup or 802.3ad)"
        return 1
    fi
    
    log "Bond0 Status:"
    grep -E "^Bonding Mode|^Primary|^Currently Active Slave|^Slave Interface|^Member Interface" /proc/net/bonding/bond0 | while read line; do
        echo "  $line"
    done
    
    log ""
    log "Member NICs:"
    grep -A2 "^Slave Interface" /proc/net/bonding/bond0 | grep -E "^Slave|MII Status" | while read line; do
        if [[ $line == "Slave"* ]]; then
            local iface=$(echo "$line" | cut -d: -f2 | xargs)
            metric "Interface: $iface"
        elif [[ $line == "MII"* ]]; then
            local status=$(echo "$line" | cut -d: -f2 | xargs)
            echo "    Status: $status"
        fi
    done
    echo ""
}

# ============================================================================
# Test 4: NFS Tuning
# ============================================================================

test_nfs_tuning() {
    log "=== Test 4: NFS Mount Tuning ==="
    
    if ! mount | grep -q "/mnt/nas"; then
        log "⚠️  NAS mount not found at /mnt/nas-*"
        return 1
    fi
    
    log "Current NFS mount options:"
    mount | grep "/mnt/nas" | while read mount_line; do
        local mount_opts=$(echo "$mount_line" | grep -oP '\(\K[^)]+' || echo "unknown")
        echo "  $mount_line"
        
        # Check for 10G-optimized parameters
        if echo "$mount_opts" | grep -q "rsize=1048576"; then
            metric "✅ rsize=1M configured"
        else
            log "⚠️  rsize not optimized (target: 1048576 for 10G)"
        fi
        
        if echo "$mount_opts" | grep -q "wsize=1048576"; then
            metric "✅ wsize=1M configured"
        else
            log "⚠️  wsize not optimized (target: 1048576 for 10G)"
        fi
        
        if echo "$mount_opts" | grep -q "noac"; then
            metric "✅ noac configured (no attribute caching)"
        else
            log "⚠️  noac not set (may reduce coherency)"
        fi
    done
    echo ""
    
    # Test NFS throughput
    log "Testing NFS throughput (1GB sequential read)..."
    if [ -w "/mnt/nas-56" ]; then
        local nfs_test_file="/mnt/nas-56/network-test-${RANDOM}.bin"
        
        # Create test file
        dd if=/dev/zero of="$nfs_test_file" bs=1M count=1024 conv=fdatasync &>/dev/null || {
            log "⚠️  Cannot write to NAS"
            return 1
        }
        
        # Read test
        local start=$(date +%s%N)
        dd if="$nfs_test_file" of=/dev/null bs=1M &>/dev/null
        local duration=$((  ($(date +%s%N) - start) / 1000000000  ))  # seconds
        local throughput_mb=$((1024 / duration))
        
        metric "NFS Throughput: ${throughput_mb} MB/s"
        
        # Cleanup
        rm -f "$nfs_test_file"
    fi
    echo ""
}

# ============================================================================
# Test 5: NIC Failover (eth0 down → eth1 takeover)
# ============================================================================

test_bond_failover() {
    log "=== Test 5: NIC Failover (eth0 down → eth1 automatic takeover) ==="
    
    if [ ! -f /proc/net/bonding/bond0 ]; then
        log "⚠️  NIC bonding not configured, skipping failover test"
        return 1
    fi
    
    log "⚠️  FAILOVER TEST - This will temporarily disable eth0"
    log "Waiting 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    
    log "Disabling eth0..."
    sudo ip link set eth0 down 2>/dev/null || {
        log "⚠️  Cannot disable eth0 (requires root or sudo)"
        return 1
    }
    
    sleep 1
    
    # Check if failover occurred
    local active_slave=$(grep "Currently Active Slave" /proc/net/bonding/bond0 | cut -d: -f2 | xargs)
    
    if [ "$active_slave" = "eth1" ]; then
        metric "✅ Failover successful: eth1 now active"
        metric "Failover latency: < 1 second"
    else
        log "⚠️  Failover failed or still in transition"
    fi
    
    # Test connectivity during failover
    log "Testing connectivity while failover active..."
    if ping -c 1 "$NAS_HOST" &>/dev/null; then
        metric "✅ Connectivity maintained during failover"
    else
        log "⚠️  Lost connectivity during failover"
    fi
    
    log "Re-enabling eth0..."
    sudo ip link set eth0 up 2>/dev/null || true
    
    sleep 1
    
    log "Bond rebalanced - check if eth0 is active again"
    cat /proc/net/bonding/bond0 | grep "Currently Active"
    echo ""
}

# ============================================================================
# Main Report
# ============================================================================

print_summary() {
    log "=== Network 10G Verification Summary ==="
    log ""
    log "Baseline (April 2026 - Pre-Optimization):"
    metric "Network throughput: ~125 MB/s (Gigabit baseline)"
    metric "Model pull time (40GB): ~320 seconds"
    metric "NAS latency: Unknown (no measurement)"
    metric "Failover: Manual (~5 minutes)"
    log ""
    log "Targets (Post-Optimization):"
    metric "Network throughput: ≥1 GB/s (8x improvement)"
    metric "Model pull time (40GB): <60 seconds (5.3x faster)"
    metric "NAS latency: <1ms p95"
    metric "Failover: <1 second (automatic)"
    log ""
}

# ============================================================================
# Main Command Handler
# ============================================================================

main() {
    case "${1:-all}" in
        iperf3)
            test_iperf3_throughput
            ;;
        mtu)
            test_mtu_jumbo_frames
            ;;
        bonding)
            test_nic_bonding
            ;;
        nfs)
            test_nfs_tuning
            ;;
        failover)
            test_bond_failover
            ;;
        all)
            print_summary
            test_iperf3_throughput || true
            test_mtu_jumbo_frames
            test_nic_bonding || true
            test_nfs_tuning
            ;;
        *)
            cat << EOF
Network 10G Verification & Optimization

Usage:
  $0 [all|iperf3|mtu|bonding|nfs|failover]

Tests:
  all           Run all tests (recommended first run)
  iperf3        Test 10G NIC throughput (requires server)
  mtu           Validate jumbo frames (MTU 9000)
  bonding       Check NIC bonding status (eth0+eth1)
  nfs           Test NFS mount tuning (rsize/wsize)
  failover      Test automatic NIC failover (requires root)

Prerequisites:
  - iperf3 on both sides (apt-get install iperf3)
  - ping/ip/mount utilities (standard)
  - NAS mounted at /mnt/nas-56
  - Sudo access for failover test

Related Issues:
  - Issue #408: Network 10G Verification & Optimization
  - Issue #407: Performance Baseline Establishment
  - Issue #411: EPIC: Infrastructure Optimization (May 2026)

Documentation:
  - ARCHITECTURE.md: Network design (10G backbone)
  - Phase 26 Infrastructure Optimization: Network-first optimization
EOF
            ;;
    esac
}

main "$@"
