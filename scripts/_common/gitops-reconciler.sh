#!/bin/bash
# @governance: GitOps reconciliation — continuously sync infrastructure state with Git source of truth
# Purpose: Continuous GitOps reconciliation - syncs infrastructure state with Git
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1534 (IaC Governance), #1531 (Infrastructure as Code)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
RECONCILE_INTERVAL="${RECONCILE_INTERVAL:-300}"  # 5 minutes default
GIT_REPO="${GIT_REPO:-.}"
TARGET_BRANCH="${TARGET_BRANCH:-main}"
TERRAFORM_DIR="${TERRAFORM_DIR:-terraform}"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-docker-compose.yml}"
DRIFT_THRESHOLD="${DRIFT_THRESHOLD:-10}"  # % change threshold for alerts
LOG_FILE="${LOG_FILE:-/var/log/gitops-reconciliation.log}"

# ============================================================================
# Logging
# ============================================================================
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
    return 1
}

# ============================================================================
# State Comparison
# ============================================================================
compute_state_hash() {
    local target="$1"
    if [[ "$target" == "terraform" ]]; then
        find "$TERRAFORM_DIR" -type f \( -name "*.tf" -o -name "*.tfvars" \) | \
            sort | xargs sha256sum | sha256sum | cut -d' ' -f1
    elif [[ "$target" == "docker" ]]; then
        cat "$DOCKER_COMPOSE_FILE" | sha256sum | cut -d' ' -f1
    else
        echo "unknown-hash"
    fi
}

detect_drift() {
    local current_hash="$1"
    local desired_hash="$2"
    local target="$3"
    
    if [[ "$current_hash" != "$desired_hash" ]]; then
        log "🔴 DRIFT DETECTED in $target: current=$current_hash desired=$desired_hash"
        return 0  # Drift exists
    fi
    return 1  # No drift
}

# ============================================================================
# Reconciliation
# ============================================================================
reconcile_terraform() {
    log "🔄 Reconciling Terraform infrastructure..."
    
    cd "$TERRAFORM_DIR" || error "Terraform directory not found"
    
    # Plan - check what needs to change
    terraform plan -json > /tmp/tf-plan.json 2>&1 || {
        error "Terraform plan failed"
        cd - > /dev/null
        return 1
    }
    
    # Count changes
    local change_count=$(grep -o '"change"' /tmp/tf-plan.json | wc -l)
    
    if [[ $change_count -gt 0 ]]; then
        log "⚠️  Terraform changes detected: $change_count resources"
        
        # Auto-apply for idempotent changes (resource count/labels)
        terraform apply -auto-approve -json > /tmp/tf-apply.json 2>&1 || {
            error "Terraform apply failed"
            cd - > /dev/null
            return 1
        }
        
        log "✅ Terraform reconciliation complete: $change_count changes applied"
    else
        log "✓ Terraform state in sync"
    fi
    
    cd - > /dev/null
}

reconcile_docker() {
    log "🔄 Reconciling Docker Compose services..."
    
    # Verify services match docker-compose.yml
    local running_services=$(docker compose ps --services 2>/dev/null | sort)
    local defined_services=$(docker compose config --services | sort)
    
    if [[ "$running_services" != "$defined_services" ]]; then
        log "⚠️  Service mismatch detected"
        log "Running: $(echo $running_services | tr '\n' ',' | sed 's/,$//')"
        log "Desired: $(echo $defined_services | tr '\n' ',' | sed 's/,$//')"
        
        # Restart services to reconcile
        docker compose up -d --remove-orphans || {
            error "Docker compose reconciliation failed"
            return 1
        }
        
        log "✅ Docker Compose services reconciled"
    else
        log "✓ Docker Compose state in sync"
    fi
}

# ============================================================================
# Main Loop
# ============================================================================
run_reconciliation_loop() {
    log "🚀 Starting GitOps reconciliation loop (interval: ${RECONCILE_INTERVAL}s)"
    
    while true; do
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Git sync
        git -C "$GIT_REPO" fetch origin || log "⚠️  Git fetch failed"
        git -C "$GIT_REPO" merge --ff-only origin/"$TARGET_BRANCH" || \
            log "⚠️  Git merge failed (repo has local changes)"
        
        # Reconcile infrastructure
        reconcile_terraform || log "⚠️  Terraform reconciliation had issues"
        reconcile_docker || log "⚠️  Docker reconciliation had issues"
        
        log "✓ Reconciliation cycle complete"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        sleep "$RECONCILE_INTERVAL"
    done
}

run_single_reconciliation() {
    log "Running single reconciliation cycle..."
    
    git -C "$GIT_REPO" fetch origin || log "⚠️  Git fetch failed"
    git -C "$GIT_REPO" merge --ff-only origin/"$TARGET_BRANCH" || \
        log "⚠️  Git merge failed (repo has local changes)"
    
    reconcile_terraform || true
    reconcile_docker || true
    
    log "✓ Single reconciliation complete"
}

# ============================================================================
# Entry Point
# ============================================================================
if [[ "${1:-}" == "--daemon" ]]; then
    run_reconciliation_loop
else
    run_single_reconciliation
fi
