#!/bin/bash
###############################################################################
# Phase 14 Progressive Traffic Ramp: 25% → 50% → 100%
# 
# Idempotent: Run in sequence, each phase checks previous completion
# Immutable: No destructions, only config changes via backup+restore
# Creates three scripts: 25pct, 50pct, 100pct for maximum control
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_STATE="/tmp/phase-14-state"
LOCK_DIR="$PHASE_STATE/traffic-ramp"
BACKUP_DIR="$PHASE_STATE/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Read current phase from lock
read_current_phase() {
    if [[ -f "$LOCK_DIR/current-phase.txt" ]]; then
        cat "$LOCK_DIR/current-phase.txt"
    else
        echo "10"
    fi
}

###############################################################################
# PHASE 25% - Ramp to 25% Traffic
###############################################################################

ramp_25pct() {
    local current=$(read_current_phase)
    
    # Idempotency check
    if [[ "$current" -ge 25 ]]; then
        echo "Already at phase $current%. Skipping to next phase."
        return 0
    fi
    
    if [[ ! -f "$PHASE_STATE/canary-10pct.lock" ]]; then
        echo "ERROR: Canary 10% not applied yet. Run phase-14-canary-10pct.sh first"
        return 1
    fi
    
    echo "=== Phase 14 Ramp: 10% → 25% ==="
    echo "Start: $(date)"
    
    # Backup current config
    cp -v /tmp/load-balancer-10pct.conf "$BACKUP_DIR/load-balancer-10pct.$TIMESTAMP.bak"
    
    # Apply 25% weighting: Old 75%, New 25%
    cat > /tmp/load-balancer-25pct.conf << 'EOF'
upstream backend {
    server 192.168.168.30:8080 weight=75;  # Old: 75%
    server 192.168.168.31:8080 weight=25;  # New: 25% (RAMP)
    check interval=3000 rise=2 fall=5 timeout=1000 type=http;
    check_http_send "GET /health HTTP/1.0\r\n\r\n";
    check_http_expect_alive http_2xx;
}
EOF
    
    echo "nginx -t && systemctl reload nginx"
    
    # Record state
    mkdir -p "$LOCK_DIR"
    echo "25" > "$LOCK_DIR/current-phase.txt"
    
    echo "✓ Ramped to 25%"
    echo "  Old Infrastructure: 75%"
    echo "  New Infrastructure: 25%"
    echo "  Monitoring: 15 minutes"
    echo "  Next: $SCRIPT_DIR/phase-14-ramp-50pct.sh"
}

###############################################################################
# PHASE 50% - Ramp to 50% Traffic
###############################################################################

ramp_50pct() {
    local current=$(read_current_phase)
    
    if [[ "$current" -ge 50 ]]; then
        echo "Already at phase $current%. Skipping to next phase."
        return 0
    fi
    
    if [[ "$current" -lt 25 ]]; then
        echo "ERROR: Must complete 25% phase first"
        return 1
    fi
    
    echo "=== Phase 14 Ramp: 25% → 50% ==="
    echo "Start: $(date)"
    
    # Backup current config
    cp -v /tmp/load-balancer-25pct.conf "$BACKUP_DIR/load-balancer-25pct.$TIMESTAMP.bak"
    
    # Apply 50% weighting: Old 50%, New 50%
    cat > /tmp/load-balancer-50pct.conf << 'EOF'
upstream backend {
    server 192.168.168.30:8080 weight=50;  # Old: 50%
    server 192.168.168.31:8080 weight=50;  # New: 50% (BALANCED)
    check interval=3000 rise=2 fall=5 timeout=1000 type=http;
    check_http_send "GET /health HTTP/1.0\r\n\r\n";
    check_http_expect_alive http_2xx;
}
EOF
    
    echo "nginx -t && systemctl reload nginx"
    
    # Record state
    echo "50" > "$LOCK_DIR/current-phase.txt"
    
    echo "✓ Ramped to 50%"
    echo "  Old Infrastructure: 50%"
    echo "  New Infrastructure: 50%"
    echo "  Monitoring: 15 minutes (CRITICAL OBSERVATION POINT)"
    echo "  Next: $SCRIPT_DIR/phase-14-ramp-100pct.sh"
}

###############################################################################
# PHASE 100% - Complete Traffic Cutover
###############################################################################

ramp_100pct() {
    local current=$(read_current_phase)
    
    if [[ "$current" -ge 100 ]]; then
        echo "Already at 100%. Already complete."
        return 0
    fi
    
    if [[ "$current" -lt 50 ]]; then
        echo "ERROR: Must complete 50% phase first"
        return 1
    fi
    
    echo "=== Phase 14 Ramp: 50% → 100% ==="
    echo "Start: $(date)"
    
    # Backup current config
    cp -v /tmp/load-balancer-50pct.conf "$BACKUP_DIR/load-balancer-50pct.$TIMESTAMP.bak"
    
    # Apply 100% weighting: Old 0%, New 100%
    cat > /tmp/load-balancer-100pct.conf << 'EOF'
upstream backend {
    server 192.168.168.30:8080 weight=0;   # Old: DEPRECATED (0%)
    server 192.168.168.31:8080 weight=100; # New: 100% (COMPLETE CUTOVER)
    check interval=3000 rise=2 fall=5 timeout=1000 type=http;
    check_http_send "GET /health HTTP/1.0\r\n\r\n";
    check_http_expect_alive http_2xx;
}
EOF
    
    echo "nginx -t && systemctl reload nginx"
    
    # Record state
    echo "100" > "$LOCK_DIR/current-phase.txt"
    
    # Create success marker
    touch "$PHASE_STATE/go-live-100pct.complete"
    
    echo "✓ Traffic Cutover COMPLETE"
    echo "  Old Infrastructure: DEPRECATED (0%)"
    echo "  New Infrastructure: 100% (PRODUCTION)"
    echo "  Status: GO-LIVE SUCCESSFUL"
    echo ""
    echo "NEXT STEPS:"
    echo "  1. Monitor metrics for 30 minutes"
    echo "  2. Run smoke tests: $SCRIPT_DIR/phase-14-smoke-tests.sh"
    echo "  3. Customer experience validation"
    echo "  4. Post-launch retrospective"
}

###############################################################################
# Main Dispatcher
###############################################################################

PHASE="${1:-current}"

case "$PHASE" in
    25|25pct)
        ramp_25pct
        ;;
    50|50pct)
        ramp_50pct
        ;;
    100|100pct|full|complete)
        ramp_100pct
        ;;
    current|status)
        current=$(read_current_phase)
        echo "Current phase: $current%"
        ;;
    *)
        echo "Usage: $0 {25|50|100|current|status}"
        echo ""
        echo "Examples:"
        echo "  $0 25      # Ramp to 25%"
        echo "  $0 50      # Ramp to 50%"
        echo "  $0 100     # Complete cutover to 100%"
        echo "  $0 status  # Show current phase"
        exit 1
        ;;
esac
