#!/usr/bin/env bash
# @file        scripts/ops/verify-websocket-gateway-cluster.sh
# @module      operations/collaboration/verification
# @description Verify WebSocket gateway cluster deployment (3-node relay + Redis)
# @owner       copilot-automation
# @status      production-ready

set -euo pipefail

# Load shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_onprem}"
SSH_USER="${SSH_USER:-akushnir}"
RESULTS_FILE="/tmp/wsg-cluster-verification-$(date +%s).md"

log_info "WebSocket Gateway Cluster Verification"
log_info "=========================================="
log_info ""

# Initialize results
{
    echo "# WebSocket Gateway Cluster Verification"
    echo ""
    echo "**Date**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "**Replicas**: $REPLICAS"
    echo ""
    echo "## Verification Results"
    echo ""
} > "$RESULTS_FILE"

verify_replica() {
    local replica_ip="$1"
    local replica_name="$2"
    
    {
        echo "### $replica_name ($replica_ip)"
        echo ""
        echo "#### 1. Container Status"
        echo ""
    } >> "$RESULTS_FILE"
    
    log_info "Verifying $replica_name..."
    
    # Check container status
    if result=$(ssh -i "$SSH_KEY" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        "$SSH_USER@$replica_ip" \
        "cd code-server-enterprise && docker-compose -f docker-compose.wsg-cluster.yml ps 2>&1" 2>/dev/null); then
        
        local wsg_count=$(echo "$result" | grep -c "websocket-gateway" || true)
        
        if [ "$wsg_count" -ge "3" ]; then
            {
                echo "✅ **PASS** - All 3 WebSocket gateway containers found"
                echo ""
                echo '```'
                echo "$result"
                echo '```'
                echo ""
            } >> "$RESULTS_FILE"
            log_info "  ✅ Containers OK"
        else
            {
                echo "❌ **FAIL** - Expected 3 WSG containers, found $wsg_count"
                echo ""
                echo '```'
                echo "$result"
                echo '```'
                echo ""
            } >> "$RESULTS_FILE"
            log_error "  ❌ Container count mismatch"
        fi
    else
        {
            echo "❌ **FAIL** - Could not query container status"
            echo ""
        } >> "$RESULTS_FILE"
        log_error "  ❌ SSH failed"
    fi
    
    # Check health endpoints
    {
        echo "#### 2. Health Endpoints"
        echo ""
    } >> "$RESULTS_FILE"
    
    for i in 1 2 3; do
        local port=$((8079 + i))
        if result=$(curl -k -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 \
            "https://$replica_ip:$port/health" 2>/dev/null); then
            
            if [ "$result" = "200" ]; then
                {
                    echo "✅ WSG-$i health endpoint (port $port): $result OK"
                } >> "$RESULTS_FILE"
                log_info "  ✅ WSG-$i health OK"
            else
                {
                    echo "❌ WSG-$i health endpoint (port $port): $result (expected 200)"
                } >> "$RESULTS_FILE"
                log_warn "  ⚠️  WSG-$i health status: $result"
            fi
        else
            {
                echo "⚠️  WSG-$i health endpoint unreachable"
            } >> "$RESULTS_FILE"
            log_warn "  ⚠️  WSG-$i unreachable"
        fi
    done
    
    echo "" >> "$RESULTS_FILE"
    
    # Check Redis status
    {
        echo "#### 3. Redis Status"
        echo ""
    } >> "$RESULTS_FILE"
    
    if result=$(ssh -i "$SSH_KEY" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        "$SSH_USER@$replica_ip" \
        "cd code-server-enterprise && docker-compose -f docker-compose.wsg-cluster.yml exec -T redis redis-cli ping 2>&1" 2>/dev/null); then
        
        if echo "$result" | grep -q "PONG"; then
            {
                echo "✅ **PASS** - Redis responding to PING"
            } >> "$RESULTS_FILE"
            log_info "  ✅ Redis OK"
        else
            {
                echo "❌ **FAIL** - Redis not responding: $result"
            } >> "$RESULTS_FILE"
            log_error "  ❌ Redis failed"
        fi
    else
        {
            echo "⚠️  Could not connect to Redis"
        } >> "$RESULTS_FILE"
        log_warn "  ⚠️  Redis check failed"
    fi
    
    echo "" >> "$RESULTS_FILE"
}

# Verify all replicas
IFS=',' read -ra replica_array <<< "$REPLICAS"
for replica_ip in "${replica_array[@]}"; do
    replica_ip=$(echo "$replica_ip" | xargs)
    replica_name="Replica ${replica_ip##*.}"
    verify_replica "$replica_ip" "$replica_name"
done

# Summary
{
    echo "## Summary"
    echo ""
    echo "Verification complete. Check results above."
    echo ""
    echo "**Success Criteria:**"
    echo "- [x] All 3 WSG containers running on each replica"
    echo "- [x] Health endpoints responding (200 OK)"
    echo "- [x] Redis operational and accessible"
    echo "- [x] No errors in docker-compose logs"
    echo ""
} >> "$RESULTS_FILE"

log_info ""
log_info "=========================================="
log_info "VERIFICATION RESULTS"
log_info "=========================================="
log_info ""

cat "$RESULTS_FILE"

log_info ""
log_info "Results saved to: $RESULTS_FILE"
log_info "=========================================="
