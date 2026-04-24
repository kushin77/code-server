#!/usr/bin/env bash
# @file        scripts/ops/setup-network-partition-recovery.sh
# @module      ops/resilience
# @description Configure automatic recovery from network partitions (Split-Brain prevention)
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

REPLICAS="${REPLICAS:-}"
DEPLOY_USER="${DEPLOY_USER:-${SSH_USER:-}}"
GATEWAY_IP="${GATEWAY_IP:-}"
QUORUM_TIMEOUT=60 # seconds

if [[ -z "$REPLICAS" ]]; then
    if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
        REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
    else
        log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before running network partition recovery setup"
    fi
fi

if [[ -z "$DEPLOY_USER" ]]; then
    log_fatal "Set DEPLOY_USER or SSH_USER before running network partition recovery setup"
fi

if [[ -z "$GATEWAY_IP" ]]; then
    log_fatal "Set GATEWAY_IP before running network partition recovery setup"
fi

################################################################################
# RECOVERY IMPLEMENTATION
################################################################################

deploy_recovery_watcher() {
    local replica="$1"
    
    log_info "Deploying network partition recovery watcher to $replica..."
    
    local watcher_script="/home/$DEPLOY_USER/scripts/network-quorum-check.sh"
    
    ssh "$DEPLOY_USER@$replica" "mkdir -p /home/$DEPLOY_USER/scripts"
    
    # We use 'EOF' to prevent local variable expansion on the watcher script
    ssh "$DEPLOY_USER@$replica" "cat << 'EOF' > $watcher_script
#!/usr/bin/env bash
# Quorum check script - prevent split-brain by shutting down if isolated
# Deployed by setup-network-partition-recovery.sh

GATEWAY=\"$GATEWAY_IP\"
TIMEOUT=$QUORUM_TIMEOUT

check_quorum() {
    # If we can't ping the gateway, we are isolated
    if ! ping -c 3 -W 2 \$GATEWAY > /dev/null 2>&1; then
        return 1
    fi
    return 0
}

while true; do
    if ! check_quorum; then
        echo \"[$(date)] CRITICAL: Network isolation detected. Waiting \$TIMEOUT seconds...\" >&2
        sleep \$TIMEOUT
        
        if ! check_quorum; then
            echo \"[$(date)] FATAL: Quorum lost. Stopping services to prevent split-brain.\" >&2
            cd code-server-enterprise && docker compose down
            
            # Wait for restoration
            until check_quorum; do sleep 10; done
            
            echo \"[$(date)] INFO: Quorum restored. Restarting services.\" >&2
            cd code-server-enterprise && docker compose up -d
        fi
    fi
    sleep 30
done
EOF"

    ssh "$DEPLOY_USER@$replica" "chmod +x $watcher_script"
    
    # Setup as a background service or simple cron @reboot
    ssh "$DEPLOY_USER@$replica" "(crontab -l 2>/dev/null | grep -v '$watcher_script'; echo '@reboot nohup $watcher_script > /home/$DEPLOY_USER/quorum.log 2>&1 &') | crontab -"
    
    log_info "✅ Quorum watcher configured on $replica"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Initializing Cluster Resilience: Network Partition Recovery"
    
    # Convert replicas string to array
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        deploy_recovery_watcher "$replica"
    done
    
    log_info "✅ Network partition recovery logic distributed"
}

main "$@"
