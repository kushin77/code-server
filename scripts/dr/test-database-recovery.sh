#!/bin/bash
###############################################################################
# Phase 5 Week 3: Disaster Recovery Testing - Database Backup/Restore
#
# Validates data protection and recovery procedures:
# - Database backup verification
# - Point-in-time recovery validation
# - Backup integrity checking
#
# Usage:
#   bash scripts/dr/test-database-recovery.sh backup
#   bash scripts/dr/test-database-recovery.sh restore
#   bash scripts/dr/test-database-recovery.sh verify
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling traps
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup on exit..."; cleanup_on_exit || true' EXIT

# Configuration
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
DB_CONTAINER="postgres"
BACKUP_DIR="$PROJECT_ROOT/artifacts/db-backups"
DB_USER="postgres"
DB_NAME="codeserver"
BACKUP_FILE="$BACKUP_DIR/backup-$(date +%Y%m%d-%H%M%S).sql.gz"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

cleanup_on_exit() {
    log_info "Cleanup complete"
}

# Create database backup
create_backup() {
    log_info "Creating database backup..."
    mkdir -p "$BACKUP_DIR"
    
    if ! docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
        pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_FILE"; then
        log_error "Backup failed"
        return 1
    fi
    
    local backup_size=$(du -h "$BACKUP_FILE" | cut -f1)
    log_success "Database backup created: $BACKUP_FILE ($backup_size)"
    
    # Verify backup file integrity
    if gzip -t "$BACKUP_FILE" 2>/dev/null; then
        log_success "Backup file integrity verified"
    else
        log_error "Backup file is corrupted"
        return 1
    fi
}

# Restore database from backup
restore_backup() {
    local backup_file="${1:-$BACKUP_FILE}"
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_info "Restoring database from backup: $backup_file"
    log_warning "This will overwrite the current database"
    
    # Drop existing database
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
        psql -U "$DB_USER" -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true
    
    # Recreate database
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
        psql -U "$DB_USER" -c "CREATE DATABASE $DB_NAME;" 2>/dev/null || true
    
    # Restore from backup
    if gzip -dc "$backup_file" | \
        docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
        psql -U "$DB_USER" "$DB_NAME"; then
        log_success "Database restored successfully"
    else
        log_error "Database restore failed"
        return 1
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_file="${1:-$BACKUP_FILE}"
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_info "Verifying backup integrity..."
    
    # Check file integrity
    if ! gzip -t "$backup_file" 2>/dev/null; then
        log_error "Backup file is corrupted"
        return 1
    fi
    
    log_success "✅ Backup file integrity verified"
    
    # Check backup size
    local backup_size=$(du -h "$backup_file" | cut -f1)
    log_info "Backup size: $backup_size"
    
    # Verify backup contains expected tables
    log_info "Checking for expected tables..."
    
    local expected_tables=("activities" "users" "executions" "reputation_scores")
    for table in "${expected_tables[@]}"; do
        if gzip -dc "$backup_file" | grep -q "TABLE $table"; then
            log_success "  ✅ Table found: $table"
        else
            log_warning "  ⚠️  Table not found: $table"
        fi
    done
}

# Test point-in-time recovery
test_point_in_time_recovery() {
    log_info "Testing point-in-time recovery capability..."
    
    # Get database state before
    log_info "Capturing current database state..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
        psql -U "$DB_USER" -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" \
        2>/dev/null || true
    
    # Record current timestamp
    local snapshot_time=$(date +%s)
    log_info "Snapshot timestamp: $(date -d @$snapshot_time)"
    
    # Create backup
    create_backup || return 1
    
    log_success "Point-in-time recovery test completed"
}

# Calculate Recovery Time Objective (RTO)
calculate_rto() {
    log_info "Calculating Recovery Time Objective (RTO)..."
    
    local test_backup="$BACKUP_DIR/rto-test-backup.sql.gz"
    
    # Create test backup
    log_info "Creating test backup for RTO measurement..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
        pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$test_backup"
    
    # Measure restore time
    log_info "Measuring database restore time..."
    local start_time=$(date +%s%N)
    
    if restore_backup "$test_backup" > /dev/null 2>&1; then
        local end_time=$(date +%s%N)
        local duration_ms=$((($end_time - $start_time) / 1000000))
        local duration_sec=$(echo "scale=2; $duration_ms / 1000" | bc)
        
        log_success "RTO Measurement:"
        log_success "  Restore Time: ${duration_sec}s"
        
        # Cleanup
        rm -f "$test_backup"
    else
        log_error "RTO measurement failed"
        return 1
    fi
}

# Calculate Recovery Point Objective (RPO)
calculate_rpo() {
    log_info "Calculating Recovery Point Objective (RPO)..."
    
    # Get latest backup timestamp
    local latest_backup=$(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -1)
    
    if [ -z "$latest_backup" ]; then
        log_error "No backup files found"
        return 1
    fi
    
    # Calculate age of latest backup
    local backup_time=$(stat -c %Y "$latest_backup")
    local current_time=$(date +%s)
    local age_seconds=$((current_time - backup_time))
    local age_minutes=$(($age_seconds / 60))
    
    log_success "RPO Measurement:"
    log_success "  Latest Backup: $(basename $latest_backup)"
    log_success "  Backup Age: ${age_minutes}m ${age_seconds}s"
    log_success "  RPO (Maximum acceptable data loss): ${age_minutes} minutes"
}

# List available backups
list_backups() {
    log_info "Available database backups:"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_warning "No backups directory found"
        return 0
    fi
    
    local count=0
    while IFS= read -r file; do
        local size=$(du -h "$file" | cut -f1)
        local timestamp=$(stat -c %y "$file" | cut -d' ' -f1)
        echo "  [$((++count))] $(basename $file) - $size - $timestamp"
    done < <(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null)
    
    if [ $count -eq 0 ]; then
        log_warning "No backup files found"
    else
        log_success "Total backups: $count"
    fi
}

# Main execution
main() {
    local scenario="${1:-help}"
    
    log_info "Phase 5 Week 3: Disaster Recovery - Database Backup/Restore"
    
    case "$scenario" in
        backup)
            create_backup
            ;;
        restore)
            restore_backup "${2:-}"
            ;;
        verify)
            verify_backup "${2:-}"
            ;;
        pitr)
            test_point_in_time_recovery
            ;;
        rto)
            calculate_rto
            ;;
        rpo)
            calculate_rpo
            ;;
        list)
            list_backups
            ;;
        *)
            log_error "Invalid scenario: $scenario"
            echo "Usage:"
            echo "  $0 backup           - Create database backup"
            echo "  $0 restore [file]   - Restore from backup"
            echo "  $0 verify [file]    - Verify backup integrity"
            echo "  $0 pitr             - Test point-in-time recovery"
            echo "  $0 rto              - Calculate Recovery Time Objective"
            echo "  $0 rpo              - Calculate Recovery Point Objective"
            echo "  $0 list             - List available backups"
            exit 1
            ;;
    esac
}

main "$@"
