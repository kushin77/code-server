#!/bin/bash

################################################################################
# Hermes Agent Portal - Backup and Recovery Automation
# Purpose: Automated backup and recovery procedures
# Usage: ./backup-recovery.sh backup              # Create backup
#        ./backup-recovery.sh restore <backup-id>  # Restore from backup
#        ./backup-recovery.sh list                 # List backups
# Date: April 30, 2026
################################################################################

set -e

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/backup_*.tmp 2>/dev/null || true' EXIT

BACKUP_DIR="backups"
CONFIG_FILE="docker-compose.enterprise.yml"
ACTION=${1:-help}
BACKUP_ID=${2:-}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$BACKUP_DIR"

################################################################################
# Helper Functions
################################################################################

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

################################################################################
# Backup Functions
################################################################################

create_backup() {
    log_info "Starting backup..."
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/backup_${timestamp}"
    mkdir -p "$backup_path"
    
    log_info "Step 1: Backing up database..."
    docker exec code-server-postgres pg_dump -U postgres code-server-db > "$backup_path/database.sql"
    log_success "Database backed up"
    
    log_info "Step 2: Backing up configuration files..."
    cp Caddyfile "$backup_path/" 2>/dev/null || true
    cp docker-compose.enterprise.yml "$backup_path/" 2>/dev/null || true
    cp .env "$backup_path/" 2>/dev/null || true
    cp -r apps/paperclip "$backup_path/paperclip_config" 2>/dev/null || true
    log_success "Configuration files backed up"
    
    log_info "Step 3: Backing up application volumes..."
    docker exec code-server-redis redis-cli BGSAVE > /dev/null 2>&1 || true
    docker cp code-server-redis:/data/dump.rdb "$backup_path/redis_dump.rdb" 2>/dev/null || true
    log_success "Redis data backed up"
    
    log_info "Step 4: Creating backup metadata..."
    cat > "$backup_path/backup_info.txt" << EOF
Backup Timestamp: $(date -I'seconds')
Backup ID: backup_${timestamp}
Services: appsmith, hermes-integration, code-server-ide, postgres, redis
Configuration: Caddyfile, docker-compose.enterprise.yml
Database: code-server-db
EOF
    log_success "Backup metadata created"
    
    log_info "Step 5: Compressing backup..."
    tar -czf "$BACKUP_DIR/backup_${timestamp}.tar.gz" -C "$BACKUP_DIR" "backup_${timestamp}" >/dev/null 2>&1
    rm -rf "$backup_path"
    log_success "Backup compressed"
    
    local backup_size=$(du -h "$BACKUP_DIR/backup_${timestamp}.tar.gz" | cut -f1)
    log_success "Backup completed successfully"
    echo -e "${GREEN}Backup ID: backup_${timestamp}${NC}"
    echo -e "Size: $backup_size"
    echo -e "Location: $BACKUP_DIR/backup_${timestamp}.tar.gz"
}

list_backups() {
    log_info "Available backups:"
    echo ""
    echo "Backup ID                Size    Date"
    echo "════════════════════════════════════════════════════════════"
    
    ls -lh "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | awk '{
        filename=$9
        gsub(/.*\//, "", filename)
        gsub(/\.tar\.gz/, "", filename)
        size=$5
        date=$6" "$7" "$8
        printf "%-30s %-8s %s\n", filename, size, date
    }' || echo "No backups found"
}

restore_backup() {
    [ -z "$BACKUP_ID" ] && log_error "Backup ID required for restore"
    
    local backup_file="$BACKUP_DIR/${BACKUP_ID}.tar.gz"
    [ ! -f "$backup_file" ] && log_error "Backup not found: $backup_file"
    
    log_warn "This will restore the system to the backup point. Continue? (yes/no)"
    read -r response
    [ "$response" != "yes" ] && { log_info "Restore cancelled"; exit 0; }
    
    log_info "Starting restore process..."
    
    log_info "Step 1: Stopping services..."
    docker-compose -f "$CONFIG_FILE" down
    log_success "Services stopped"
    
    log_info "Step 2: Extracting backup..."
    tar -xzf "$backup_file" -C "$BACKUP_DIR"
    log_success "Backup extracted"
    
    log_info "Step 3: Restoring configuration..."
    cp "$BACKUP_DIR/${BACKUP_ID}/Caddyfile" . 2>/dev/null || true
    cp "$BACKUP_DIR/${BACKUP_ID}/docker-compose.enterprise.yml" . 2>/dev/null || true
    cp "$BACKUP_DIR/${BACKUP_ID}/.env" . 2>/dev/null || true
    log_success "Configuration restored"
    
    log_info "Step 4: Starting services..."
    docker-compose -f "$CONFIG_FILE" up -d
    sleep 10
    log_success "Services started"
    
    log_info "Step 5: Restoring database..."
    docker exec -i code-server-postgres psql -U postgres code-server-db < "$BACKUP_DIR/${BACKUP_ID}/database.sql"
    log_success "Database restored"
    
    log_info "Step 6: Restoring Redis data..."
    docker cp "$BACKUP_DIR/${BACKUP_ID}/redis_dump.rdb" code-server-redis:/data/dump.rdb 2>/dev/null || true
    docker exec code-server-redis redis-cli BGSAVE > /dev/null 2>&1 || true
    log_success "Redis data restored"
    
    log_info "Cleaning up..."
    rm -rf "$BACKUP_DIR/${BACKUP_ID}"
    
    log_success "Restore completed successfully"
}

emergency_shutdown() {
    log_warn "EMERGENCY SHUTDOWN - Stopping all services immediately"
    docker-compose -f "$CONFIG_FILE" down
    log_success "All services stopped"
}

recovery_from_failure() {
    log_warn "Attempting recovery from failure..."
    
    log_info "Step 1: Stopping failed services..."
    docker-compose -f "$CONFIG_FILE" down || true
    
    log_info "Step 2: Cleaning up containers..."
    docker system prune -f
    
    log_info "Step 3: Restarting services..."
    docker-compose -f "$CONFIG_FILE" up -d
    
    log_info "Step 4: Waiting for services to stabilize..."
    sleep 15
    
    log_info "Step 5: Verifying recovery..."
    if curl -s -k https://kushnir.cloud/api/hermes/health | grep -q "healthy"; then
        log_success "Recovery successful"
        return 0
    else
        log_error "Recovery failed - manual intervention required"
    fi
}

show_help() {
    cat << EOF
${BLUE}Hermes Agent Portal - Backup and Recovery${NC}

Usage:
  backup-recovery.sh backup              Create a full system backup
  backup-recovery.sh restore <backup-id> Restore from a specific backup
  backup-recovery.sh list                List all available backups
  backup-recovery.sh emergency           Emergency shutdown of all services
  backup-recovery.sh recover             Attempt recovery from failure

Examples:
  ./backup-recovery.sh backup
  ./backup-recovery.sh list
  ./backup-recovery.sh restore backup_20260430_120000
  ./backup-recovery.sh recover

EOF
}

################################################################################
# Main
################################################################################

main() {
    case "$ACTION" in
        backup)
            create_backup
            ;;
        restore)
            restore_backup
            ;;
        list)
            list_backups
            ;;
        emergency)
            emergency_shutdown
            ;;
        recover)
            recovery_from_failure
            ;;
        *)
            show_help
            ;;
    esac
}

main "$@"
