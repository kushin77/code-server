#!/bin/bash
# @file rollback-manager.sh
# @module infrastructure/deployments
# @description Coordinated deployment rollback with multi-host orchestration and verification

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
DEPLOYMENT_TARGETS="${DEPLOYMENT_TARGETS:-192.168.168.31 192.168.168.42}"
SSH_USER="${SSH_USER:-akushnir}"
ROLLBACK_TIMEOUT="${ROLLBACK_TIMEOUT:-300}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-5}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"
LOG_FILE="${LOG_FILE:-/var/log/rollback-manager.log}"

# ============================================================================
# Logging & Status
# ============================================================================
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ERROR: $1" | tee -a "$LOG_FILE" >&2
    return 1
}

success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1" | tee -a "$LOG_FILE"
}

# ============================================================================
# Health Checks
# ============================================================================
check_host_health() {
    local host="$1"
    local endpoint="${2:-http://$host:3100/api/health}"
    
    for attempt in $(seq 1 "$HEALTH_CHECK_RETRIES"); do
        if curl -sf "$endpoint" > /dev/null 2>&1; then
            success "Health check passed for $host (attempt $attempt)"
            return 0
        fi
        
        if [[ $attempt -lt $HEALTH_CHECK_RETRIES ]]; then
            log "⏳ Health check attempt $attempt failed, retrying in ${HEALTH_CHECK_INTERVAL}s..."
            sleep "$HEALTH_CHECK_INTERVAL"
        fi
    done
    
    error "Health check failed for $host after $HEALTH_CHECK_RETRIES attempts"
    return 1
}

check_all_hosts() {
    local failed=0
    local total=0
    
    for target in $DEPLOYMENT_TARGETS; do
        total=$((total + 1))
        check_host_health "$target" || failed=$((failed + 1))
    done
    
    log "Health check summary: $((total - failed))/$total hosts healthy"
    [[ $failed -eq 0 ]] && return 0 || return 1
}

# ============================================================================
# Git Operations
# ============================================================================
get_current_commit() {
    git rev-parse HEAD
}

get_previous_stable_commit() {
    # Get the commit before the current one, skip merge commits
    git log --oneline --no-merges -2 | tail -1 | cut -d' ' -f1
}

verify_commit_is_stable() {
    local commit="$1"
    
    # Check if commit has passed CI
    if gh run list --repo kushin77/code-server \
        --commit "$commit" \
        --status "success" \
        --jq 'length' 2>/dev/null | grep -q "1"; then
        success "Commit $commit verified as stable (CI passed)"
        return 0
    fi
    
    log "⚠️  Commit $commit CI status unclear, proceeding with caution"
    return 0  # Don't fail, but warn
}

# ============================================================================
# Deployment Rollback
# ============================================================================
rollback_target() {
    local target="$1"
    local target_commit="$2"
    
    log "🔄 Rolling back $target to $target_commit..."
    
    ssh -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        "${SSH_USER}@${target}" \
        "cd code-server-enterprise && \
         git fetch origin && \
         git reset --hard '$target_commit' && \
         docker compose down && \
         docker compose up -d" \
        >> "$LOG_FILE" 2>&1 || {
        error "Rollback failed on $target"
        return 1
    }
    
    # Verify health after rollback
    sleep 10  # Wait for services to come up
    check_host_health "$target" || {
        error "Health check failed after rollback on $target"
        return 1
    }
    
    success "Rollback complete on $target"
}

# ============================================================================
# Parallel Rollback
# ============================================================================
rollback_all() {
    local target_commit="$1"
    local pids=()
    local failed_hosts=()
    
    log "🚀 Starting coordinated rollback to $target_commit across all targets..."
    
    # Start rollback on all hosts in parallel
    for target in $DEPLOYMENT_TARGETS; do
        rollback_target "$target" "$target_commit" &
        pids+=($!)
    done
    
    # Wait for all rollbacks with timeout
    local elapsed=0
    while [[ ${#pids[@]} -gt 0 && $elapsed -lt $ROLLBACK_TIMEOUT ]]; do
        local still_running=()
        
        for i in "${!pids[@]}"; do
            if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                # Process finished
                wait "${pids[$i]}" || {
                    # Get the target for this PID index
                    local target=$(echo "$DEPLOYMENT_TARGETS" | cut -d' ' -f$((i+1)))
                    failed_hosts+=("$target")
                }
                unset 'pids[$i]'
            else
                still_running+=("${pids[$i]}")
            fi
        done
        
        pids=("${still_running[@]}")
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    # Check for timeout
    if [[ ${#pids[@]} -gt 0 ]]; then
        error "Rollback timeout ($ROLLBACK_TIMEOUT seconds)"
        kill "${pids[@]}" 2>/dev/null || true
        return 1
    fi
    
    # Summary
    if [[ ${#failed_hosts[@]} -gt 0 ]]; then
        error "Rollback failed on: ${failed_hosts[*]}"
        return 1
    fi
    
    success "Rollback complete on all targets"
}

# ============================================================================
# Main Orchestration
# ============================================================================
main() {
    local action="${1:-status}"
    
    case "$action" in
        rollback-to-previous)
            log "🔍 Determining previous stable commit..."
            local prev_commit=$(get_previous_stable_commit)
            log "Previous commit: $prev_commit"
            
            verify_commit_is_stable "$prev_commit" || true
            rollback_all "$prev_commit"
            ;;
        
        rollback-to)
            local target_commit="${2:-}"
            if [[ -z "$target_commit" ]]; then
                error "Target commit must be specified: rollback-to <commit>"
                return 1
            fi
            
            verify_commit_is_stable "$target_commit" || true
            rollback_all "$target_commit"
            ;;
        
        health)
            log "🏥 Running health checks..."
            check_all_hosts
            ;;
        
        status)
            log "Current commit: $(get_current_commit)"
            log "Previous commit: $(get_previous_stable_commit)"
            log "Running health checks..."
            check_all_hosts
            ;;
        
        *)
            cat << EOF
Usage: $(basename "$0") [ACTION]

ACTIONS:
    rollback-to-previous        Rollback all hosts to previous stable commit
    rollback-to <commit>        Rollback all hosts to specific commit
    health                      Run health checks on all targets
    status                      Show current status and health

ENVIRONMENT VARIABLES:
    DEPLOYMENT_TARGETS         Space-separated list of target hosts
    SSH_USER                   SSH user for remote connection
    ROLLBACK_TIMEOUT          Timeout for rollback operations (seconds)

EXAMPLES:
    # Rollback to previous commit
    $(basename "$0") rollback-to-previous
    
    # Rollback to specific commit
    $(basename "$0") rollback-to abc123def456

EOF
            return 1
            ;;
    esac
}

main "$@"
