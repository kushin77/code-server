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
    
    # Copy dashboard to replica
    log_info "[$replica_clean] Copying dashboard configuration..."
    scp -i "$SSH_KEY" -o BatchMode=yes \
        "$DASHBOARD_DIR/cluster-health-dashboard.json" \
        "$SSH_USER@$replica_clean:/tmp/cluster-health-dashboard.json" \
        >/dev/null 2>&1 || {
        log_error "[$replica_clean] SCP failed"
        return 1
    }
    
    # Get Grafana API token
    log_info "[$replica_clean] Authenticating with Grafana..."
    local token=$(ssh_exec "$replica_clean" \
        "curl -s -X POST -H 'Content-Type: application/json' \
         -d '{\"name\":\"cluster-health\",\"role\":\"Editor\"}' \
         http://localhost:${GRAFANA_API_PORT}/api/auth/keys 2>/dev/null | jq -r '.key'" || echo "")
    
    if [[ -z "$token" ]]; then
        log_error "[$replica_clean] Failed to get Grafana API token"
        return 1
    fi
    
    # Load dashboard JSON and update metadata
    log_info "[$replica_clean] Updating dashboard metadata..."
    local dashboard_payload=$(ssh_exec "$replica_clean" \
        "cat /tmp/cluster-health-dashboard.json | jq '.dashboard |= . + {id: 1, version: 0, timezone: \"UTC\"}' | jq '{dashboard: .dashboard, overwrite: true}'")
    
    # Deploy dashboard via API
    log_info "[$replica_clean] Posting dashboard to Grafana API..."
    local response=$(ssh_exec "$replica_clean" \
        "curl -s -X POST -H 'Authorization: Bearer $token' \
         -H 'Content-Type: application/json' \
         -d '$dashboard_payload' \
         http://localhost:${GRAFANA_API_PORT}/api/dashboards/db" || echo "{}")
    
    # Check response
    local status=$(echo "$response" | jq -r '.status // "error"')
    if [[ "$status" == "success" ]] || echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        local dashboard_id=$(echo "$response" | jq -r '.id // "unknown"')
        log_info "[$replica_clean] ✅ Dashboard deployed successfully (ID: $dashboard_id)"
        return 0
    else
        local error_msg=$(echo "$response" | jq -r '.message // "unknown error"')
        log_error "[$replica_clean] Dashboard deployment failed: $error_msg"
        return 1
    fi
}

deploy_to_all_replicas() {
    log_info "=========================================="
    log_info "DEPLOYING DASHBOARD TO ALL REPLICAS"
    log_info "=========================================="
    
    local failed=0
    IFS=',' read -ra REPLICA_ARRAY <<< "$REPLICAS"
    
    for replica in "${REPLICA_ARRAY[@]}"; do
        replica=$(echo "$replica" | xargs)
        if ! deploy_dashboard_to_replica "$replica"; then
            failed=$((failed + 1))
        fi
    done
    
    if [[ $failed -gt 0 ]]; then
        log_error "❌ $failed replica(s) failed"
        return 1
    fi
    
    log_info "✅ All replicas deployed successfully"
}

verify_dashboard_access() {
    log_info "=========================================="
    log_info "VERIFYING DASHBOARD ACCESS"
    log_info "=========================================="
    
    IFS=',' read -ra REPLICA_ARRAY <<< "$REPLICAS"
    
    for replica in "${REPLICA_ARRAY[@]}"; do
        replica=$(echo "$replica" | xargs)
        log_info "[$replica] Verifying dashboard accessibility..."
        
        local health=$(ssh_exec "$replica" \
            "curl -s http://localhost:${GRAFANA_API_PORT}/api/dashboards/uid/${DASHBOARD_UID} | jq -r '.dashboard.title // \"NOT_FOUND\"'" || echo "ERROR")
        
        if [[ "$health" != "NOT_FOUND" && "$health" != "ERROR" ]]; then
            log_info "[$replica] ✅ Dashboard accessible: $health"
        else
            log_error "[$replica] ❌ Dashboard not accessible"
        fi
    done
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "=========================================="
    log_info "GRAFANA CLUSTER HEALTH DASHBOARD"
    log_info "=========================================="
    log_info "Dashboard UID: $DASHBOARD_UID"
    log_info "Dry Run: $DRY_RUN"
    log_info ""
    
    validate_dashboard_json
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "🔍 DRY RUN MODE - No changes will be made"
        log_info ""
        log_info "Would deploy dashboard:"
        log_info "  From: $DASHBOARD_DIR/cluster-health-dashboard.json"
        log_info "  To replicas: $REPLICAS"
        log_info "  Grafana URL: http://localhost:${GRAFANA_API_PORT}"
        log_info "  Dashboard UID: $DASHBOARD_UID"
        log_info ""
        log_info "✅ Dry run validation complete"
        return 0
    fi
    
    deploy_to_all_replicas || return 1
    verify_dashboard_access || return 1
    
    log_info ""
    log_info "=========================================="
    log_info "✅ DASHBOARD DEPLOYMENT COMPLETE"
    log_info "=========================================="
    log_info ""
    log_info "Access dashboard at:"
    IFS=',' read -ra REPLICA_ARRAY <<< "$REPLICAS"
    for replica in "${REPLICA_ARRAY[@]}"; do
        replica=$(echo "$replica" | xargs)
        log_info "  http://$replica:${GRAFANA_API_PORT}/d/$DASHBOARD_UID/cluster-health"
    done
    log_info ""
}

main "$@"
