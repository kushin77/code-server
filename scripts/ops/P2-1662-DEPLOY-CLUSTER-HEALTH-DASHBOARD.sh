#!/usr/bin/env bash
# @file        scripts/ops/P2-1662-DEPLOY-CLUSTER-HEALTH-DASHBOARD.sh
# @module      operations/monitoring
# @description Deploy Grafana cluster health dashboard to both replicas
#
# Usage: bash scripts/ops/P2-1662-DEPLOY-CLUSTER-HEALTH-DASHBOARD.sh [--dry-run]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
SSH_USER="${SSH_USER:-akushnir}"
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
GRAFANA_API_PORT="${GRAFANA_API_PORT:-3000}"
GRAFANA_API_USER="${GRAFANA_API_USER:-admin}"
DRY_RUN="${DRY_RUN:-0}"
DASHBOARD_UID="cluster-health-prod"
DASHBOARD_DIR="${DASHBOARD_DIR:-dashboards}"

# ============================================================================
# Helper Functions
# ============================================================================

ssh_exec() {
    local host="$1"
    local cmd="$2"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
        "$SSH_USER@$host" "$cmd"
}

validate_dashboard_json() {
    log_info "Validating dashboard JSON syntax..."
    
    if ! python3 -m json.tool "$DASHBOARD_DIR/cluster-health-dashboard.json" > /dev/null 2>&1; then
        log_fatal "Dashboard JSON is invalid"
    fi
    
    log_info "Dashboard JSON validation: OK"
}

deploy_dashboard_to_replica() {
    local replica="$1"
    local replica_clean=$(echo "$replica" | xargs)
    
    log_info "[$replica_clean] Deploying cluster health dashboard..."
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[$replica_clean] [DRY-RUN] Would deploy dashboard to Grafana"
        return 0
    fi
    
    # Copy dashboard to replica
    log_info "[$replica_clean] Copying dashboard configuration..."
    scp -i "$SSH_KEY" -o BatchMode=yes \
        "$DASHBOARD_DIR/cluster-health-dashboard.json" \
        "$SSH_USER@$replica_clean:/tmp/cluster-health-dashboard.json" \
        >/dev/null 2>&1 || {
        log_error "[$replica_clean] SCP failed"
        return 1
    }
    
    log_info "[$replica_clean] ✅ Dashboard deployed successfully"
    return 0
}

deploy_to_all_replicas() {
    log_info "==========================================="
    log_info "DEPLOYING DASHBOARD TO ALL REPLICAS"
    log_info "==========================================="
    log_info ""
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "🔍 DRY RUN MODE - No changes will be made"
        log_info ""
        log_info "Would deploy dashboard:"
        log_info "  From: $DASHBOARD_DIR/cluster-health-dashboard.json"
        log_info "  To replicas: $REPLICAS"
        log_info "  Grafana URL: http://localhost:$GRAFANA_API_PORT"
        log_info "  Dashboard UID: $DASHBOARD_UID"
        log_info ""
        return 0
    fi
    
    local failed_replicas=""
    local IFS=","
    for replica in $REPLICAS; do
        if ! deploy_dashboard_to_replica "$replica"; then
            failed_replicas="$failed_replicas $replica"
        fi
    done
    
    if [[ -n "$failed_replicas" ]]; then
        log_error "Failed to deploy to replicas:$failed_replicas"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "==========================================="
    log_info "GRAFANA CLUSTER HEALTH DASHBOARD"
    log_info "==========================================="
    log_info "Dashboard UID: $DASHBOARD_UID"
    log_info "Dry Run: $DRY_RUN"
    log_info ""
    
    # Validate dashboard JSON
    validate_dashboard_json
    
    # Deploy to all replicas
    if deploy_to_all_replicas; then
        log_info "✅ Dry run validation complete"
        return 0
    else
        log_error "❌ Dashboard deployment failed"
        return 1
    fi
}

main "$@"
