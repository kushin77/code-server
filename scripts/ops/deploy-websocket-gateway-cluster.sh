#!/usr/bin/env bash
# @file        scripts/ops/deploy-websocket-gateway-cluster.sh
# @module      operations/collaboration/deployment
# @description Deploy WebSocket gateway cluster (3-node relay) to production replicas with IaC patterns
# @owner       copilot-automation
# @status      production-ready

set -euo pipefail

# Load shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration from environment or defaults
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_onprem}"
SSH_USER="${SSH_USER:-akushnir}"
DEPLOY_DIR="code-server-enterprise"
COMPOSE_FILE="docker-compose.wsg-cluster.yml"
DRY_RUN="${DRY_RUN:-0}"
WAIT_HEALTHY="${WAIT_HEALTHY:-300}"
PARALLEL="${PARALLEL:-1}"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --replicas)
            REPLICAS="$2"
            shift 2
            ;;
        --no-wait)
            WAIT_HEALTHY=0
            shift
            ;;
        --wait)
            WAIT_HEALTHY="$2"
            shift 2
            ;;
        --help)
            log_info "Usage: $0 [OPTIONS]"
            log_info "Options:"
            log_info "  --dry-run           Show what would be deployed (no changes)"
            log_info "  --replicas LIST     Comma-separated list of replica IPs (default: $REPLICAS)"
            log_info "  --no-wait           Don't wait for containers to become healthy"
            log_info "  --wait SECONDS      Wait this many seconds for health (default: $WAIT_HEALTHY)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
deploy_to_replica() {
    local replica_ip="$1"
    local replica_name="$2"
    
    log_info "Deploying WebSocket gateway cluster to $replica_name ($replica_ip)..."
    
    # Build SSH command
    local deploy_cmd="cd $DEPLOY_DIR && docker-compose -f $COMPOSE_FILE up -d"
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY RUN] Would execute on $replica_name:"
        log_info "  ssh -i $SSH_KEY $SSH_USER@$replica_ip '$deploy_cmd'"
        return 0
    fi
    
    # Execute deployment
    if ssh -i "$SSH_KEY" \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        "$SSH_USER@$replica_ip" \
        "set -e; $deploy_cmd && docker-compose -f $COMPOSE_FILE ps" 2>&1; then
        log_info "✅ Deployment to $replica_name succeeded"
        return 0
    else
        log_error "❌ Deployment to $replica_name failed"
        return 1
    fi
}

wait_for_healthy() {
    local replica_ip="$1"
    local replica_name="$2"
    local max_wait="$3"
    local elapsed=0
    
    if [ "$WAIT_HEALTHY" = "0" ]; then
        log_info "Skipping health check (--no-wait specified)"
        return 0
    fi
    
    log_info "Waiting for $replica_name to become healthy (max $max_wait seconds)..."
    
    while [ "$elapsed" -lt "$max_wait" ]; do
        # Check if all 3 WSG containers are running
        if result=$(ssh -i "$SSH_KEY" \
            -o BatchMode=yes \
            -o ConnectTimeout=5 \
            "$SSH_USER@$replica_ip" \
            "cd $DEPLOY_DIR && docker-compose -f $COMPOSE_FILE ps websocket-gateway-* | grep -c 'Up'" 2>/dev/null); then
            
            if [ "$result" -ge "3" ]; then
                log_info "✅ All 3 WebSocket gateway containers are UP on $replica_name"
                return 0
            fi
        fi
        
        log_info "  Waiting... ($elapsed/$max_wait seconds)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    log_warn "⚠️  Timeout waiting for $replica_name to become healthy"
    return 1
}

# Main deployment logic
log_info "=========================================="
log_info "WebSocket Gateway Cluster Deployment"
log_info "=========================================="
log_info "Configuration:"
log_info "  Replicas: $REPLICAS"
log_info "  SSH User: $SSH_USER"
log_info "  Compose File: $COMPOSE_FILE"
log_info "  Dry Run: $DRY_RUN"
log_info "  Wait Healthy: $WAIT_HEALTHY seconds"
log_info ""

# Convert comma-separated list to array
IFS=',' read -ra replica_array <<< "$REPLICAS"

# Deploy to each replica
declare -a pids=()
for replica_ip in "${replica_array[@]}"; do
    replica_ip=$(echo "$replica_ip" | xargs)  # Trim whitespace
    replica_name="REPLICA-${replica_ip##*.}"
    
    if [ "$PARALLEL" = "1" ]; then
        deploy_to_replica "$replica_ip" "$replica_name" &
        pids+=($!)
    else
        deploy_to_replica "$replica_ip" "$replica_name"
    fi
done

# Wait for parallel deployments
if [ "$PARALLEL" = "1" ] && [ ${#pids[@]} -gt 0 ]; then
    for pid in "${pids[@]}"; do
        wait "$pid" || log_error "Parallel deployment failed (PID: $pid)"
    done
fi

log_info ""
log_info "=========================================="
log_info "Deployment Phase Complete"
log_info "=========================================="

# Wait for health checks
if [ "$WAIT_HEALTHY" -gt "0" ]; then
    log_info ""
    log_info "Starting health checks..."
    log_info ""
    
    for replica_ip in "${replica_array[@]}"; do
        replica_ip=$(echo "$replica_ip" | xargs)
        replica_name="REPLICA-${replica_ip##*.}"
        wait_for_healthy "$replica_ip" "$replica_name" "$WAIT_HEALTHY"
    done
fi

log_info ""
log_info "=========================================="
log_info "WebSocket Gateway Cluster Deployment Complete ✅"
log_info "=========================================="
log_info ""
log_info "Next Steps:"
log_info "1. Run verification: bash scripts/ops/verify-websocket-gateway-cluster.sh"
log_info "2. Load test staging: k6 run tests/load/websocket-gateway-load-test.js"
log_info "3. Deploy to production (when ready)"
log_info ""
