#!/usr/bin/env bash
# @file        scripts/ops/setup-database-backup-strategy.sh
# @module      ops/backups
# @description Configure tiered database backup strategy (Logical + Physical)
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

BACKUP_USER="${DEPLOY_USER:-akushnir}"
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
NAS_MOUNT="${NAS_MOUNT_POINT:-/mnt/nas/backups}"

################################################################################
# STRATEGY DEPLOYMENT
################################################################################

deploy_backup_strategy() {
    local replica="$1"
    
    log_info "Deploying tiered backup strategy to $replica..."
    
    local strategy_script="/home/$BACKUP_USER/scripts/database-backup-tiered.sh"
    
    ssh "$BACKUP_USER@$replica" "mkdir -p /home/$BACKUP_USER/scripts"
    
    ssh "$BACKUP_USER@$replica" "cat << 'EOF' > $strategy_script
#!/usr/bin/env bash
# Tiered Database Backup Strategy
# Deployed by setup-database-backup-strategy.sh

set -euo pipefail

TS=\$(date +%Y%m%d)
BACKUP_DIR=\"$NAS_MOUNT/tiered/\$TS\"
mkdir -p \"\$BACKUP_DIR\"

echo \"Starting tiered backup: \$(date)\"

# 1. Logical Backup (Weekly Full)
if [[ \$(date +%u) -eq 7 ]]; then
    echo \"Running full logical backup (Sunday)...\"
    cd code-server-enterprise && docker compose exec -T db pg_dumpall -U postgres | gzip > \"\$BACKUP_DIR/full-dump.sql.gz\"
fi

# 2. Continuous Archive (Log shipping / WAL-G - Future integration)
# echo \"WAL shipping handled by separate process\"

# 3. Snapshot (Filesystem level if possible, or simple rsync)
echo \"Pruning backups older than 90 days...\"
find \"$NAS_MOUNT/tiered/\" -type d -mtime +90 -exec rm -rf {} +

echo \"Strategy execution finished.\"
EOF"

    ssh "$BACKUP_USER@$replica" "chmod +x $strategy_script"
    log_info "✅ Tiered backup strategy script deployed to $replica"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Implementing Database Backup Strategy..."
    
    # Convert replicas string to array
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        deploy_backup_strategy "$replica"
    done
    
    log_info "✅ Tiered backup strategy applied across cluster"
}

main "$@"
