#!/usr/bin/env bash
# @file        scripts/ops/setup-automated-backups.sh
# @module      ops/backups
# @description Configure automated backups for PostgreSQL and NAS volumes
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

BACKUP_USER="${BACKUP_USER:-${SSH_USER:-${DEPLOY_USER:-}}}"
BACKUP_REPLICAS="${BACKUP_REPLICAS:-}"
NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/mnt/nas/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 2 * * *}"  # 2 AM daily

if [[ -z "$BACKUP_USER" ]]; then
    log_fatal "Set BACKUP_USER, SSH_USER, or DEPLOY_USER before running backup setup"
fi

if [[ -z "$BACKUP_REPLICAS" ]]; then
    if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
        BACKUP_REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
    else
        log_fatal "Set BACKUP_REPLICAS or REPLICA_1_IP/REPLICA_2_IP before running backup setup"
    fi
fi

################################################################################
# VALIDATION
################################################################################

validate_prerequisites() {
    log_info "Validating backup environment..."
    
    require_command crontab
    require_command ssh
    
    # Check NAS mount locally
    if ! mountpoint -q "$NAS_MOUNT_POINT" 2>/dev/null; then
        log_warn "NAS not mounted at $NAS_MOUNT_POINT - backup script may fail if remote host relies on it"
    fi
}

################################################################################
# BACKUP CONFIGURATION
################################################################################

install_backup_cron() {
    local replica="$1"
    
    log_info "Installing backup cron job on $replica..."
    
    # Define remote backup script content
    local backup_script_path="/home/$BACKUP_USER/scripts/perform-nightly-backup.sh"
    
    # Push perform-nightly-backup.sh if it exists locally or create it
    # For now, we'll create a robust inline script on the remote host
    
    ssh "$BACKUP_USER@$replica" "mkdir -p /home/$BACKUP_USER/scripts"
    
    ssh "$BACKUP_USER@$replica" "cat << 'EOF' > $backup_script_path
#!/usr/bin/env bash
set -euo pipefail

# Automated Backup Script (deployed by setup-automated-backups.sh)
TIMESTAMP=\$(date +%Y%m%d-%H%M%S)
BACKUP_ROOT=\"$NAS_MOUNT_POINT/db\"
DATA_ROOT=\"$NAS_MOUNT_POINT/data\"
HOST_NAME=\$(hostname)

echo \"Starting backup on \${HOST_NAME} at \${TIMESTAMP}\"

# 1. PostgreSQL logical backup (pg_dump)
mkdir -p \"\${BACKUP_ROOT}\"
cd code-server-enterprise && \
  docker compose exec -T db pg_dumpall -U postgres | gzip > \"\${BACKUP_ROOT}/full-cluster-\${HOST_NAME}-\${TIMESTAMP}.sql.gz\"

# 2. Application data archive (NAS-to-NAS/Local-to-NAS)
mkdir -p \"\${DATA_ROOT}\"
tar -czf \"\${DATA_ROOT}/app-data-\${HOST_NAME}-\${TIMESTAMP}.tar.gz\" -C /var/lib/docker/volumes/ code_server_data 2>/dev/null || true

# 3. Retention policy (pruning old backups)
find \"\${BACKUP_ROOT}\" -name \"*.sql.gz\" -mtime +$RETENTION_DAYS -delete
find \"\${DATA_ROOT}\" -name \"*.tar.gz\" -mtime +$RETENTION_DAYS -delete

echo \"Backup completed successfully\"
EOF"

    ssh "$BACKUP_USER@$replica" "chmod +x $backup_script_path"
    
    # Add to crontab
    ssh "$BACKUP_USER@$replica" "(crontab -l 2>/dev/null | grep -v '$backup_script_path'; echo '$CRON_SCHEDULE $backup_script_path >> /home/$BACKUP_USER/backup.log 2>&1') | crontab -"
    
    log_info "✅ Nightly backup configured on $replica"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Setting up Automated Backups for Cluster..."
    
    validate_prerequisites
    
    # Convert replicas string to array
    local replica_array
    IFS=',' read -ra replica_array <<< "$BACKUP_REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        install_backup_cron "$replica"
    done
    
    log_info "✅ All replicas configured for automated backups"
}

main "$@"
