#!/usr/bin/env bash
# @file        scripts/ops/restore-appsmith.sh
# @module      ops/recovery
# @description Standardized Appsmith data restoration from NAS across replicas
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

################################################################################
# CONFIGURATION
################################################################################

REPLICAS="${REPLICAS:-${REPLICA_1_IP:-},${REPLICA_2_IP:-}}"
DEPLOY_USER="${DEPLOY_USER:-${SSH_USER:-}}"
BACKUP_FILE="${1:-}"

if [[ -z "$REPLICAS" || "$REPLICAS" == "," ]]; then
    log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP"
fi

if [[ -z "$DEPLOY_USER" ]]; then
    log_fatal "Set DEPLOY_USER or SSH_USER"
fi

if [[ -z "$BACKUP_FILE" ]]; then
    log_fatal "Usage: $0 <backup_file_path_on_nas>"
fi

################################################################################
# RESTORE LOGIC
################################################################################

restore_appsmith_on_node() {
    local replica="$1"
    local backup="$2"
    
    log_info "🛠️  Restoring Appsmith on $replica from $backup..."
    
    # 1. Stop appsmith
    ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && docker compose stop appsmith"
    
    # 2. Extract backup (destructive to current state)
    ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && \
        docker run --rm -v code_server_appsmith_data:/data -v $backup:/backup.tar.gz:ro \
        alpine tar -xzf /backup.tar.gz -C /data"
        
    # 3. Start appsmith
    ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && docker compose start appsmith"
    
    log_info "✅ Restored Appsmith on $replica"
}

################################################################################
# MAIN
################################################################################

main() {
    log_warn "🔥 RESTORE WARNING: This will overwrite appsmith data across the cluster!"
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        restore_appsmith_on_node "$replica" "$BACKUP_FILE"
    done
    
    log_info "✅ Global Appsmith restoration complete"
}

main "$@"
