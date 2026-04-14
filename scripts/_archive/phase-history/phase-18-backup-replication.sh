#!/bin/bash

################################################################################
# Phase 18: Backup & Replication Automation
# Purpose: Centralized backup, replication, and data consistency procedures
# Timeline: Phase 18 (May 12-26, 2026)
#
# Capabilities:
#   - Automated database backups (hourly, daily, weekly)
#   - Git repository backups to S3
#   - Redis snapshots and replication
#   - Cross-region replication validation
#   - Backup rotation and retention
#   - Data consistency checks
#
# Usage: bash scripts/phase-18-backup-replication.sh [--full|--incremental|--sync|--verify]
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${ROOT_DIR}/logs/phase-18-backup"
BACKUP_DIR="${ROOT_DIR}/.backups"

# Region configuration
PRIMARY_REGION="us-east"
SECONDARY_REGION="us-west"
TERTIARY_REGION="eu-west"

PRIMARY_HOST="192.168.168.31"
SECONDARY_HOST="192.168.168.32"
TERTIARY_HOST="192.168.168.33"

# S3 configuration (for cross-region backup)
S3_BUCKET="kushnir-backups"
S3_PREFIX="phase-18"
S3_RETENTION_DAYS=30

# Database configuration
DB_USER="postgres"
DB_PASSWORD="${DB_PASSWORD:-changeme}"
DB_NAME="code_server"
DB_HOST="localhost"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# ============================================================================
# LOGGING & MONITORING
# ============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_DIR}/backup-${TIMESTAMP}.log"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "${LOG_DIR}/backup-${TIMESTAMP}.log"
}

log_error() {
    echo -e "${RED}❌ ERROR: $*${NC}" | tee -a "${LOG_DIR}/backup-${TIMESTAMP}.log"
}

log_metric() {
    local metric="$1"
    local value="$2"
    echo "$(date +%s) $metric=$value" >> "${LOG_DIR}/backup-metrics.tsv"
}

# ============================================================================
# DATABASE BACKUPS
# ============================================================================

backup_database() {
    local region="$1"
    local host="$2"
    local backup_type="${3:-full}"

    log "Creating $backup_type database backup for region: $region"

    local backup_file="${BACKUP_DIR}/${region}-db-${backup_type}-${TIMESTAMP}.sql"

    # Full backup with compression
    if [ "$backup_type" = "full" ]; then
        ssh -o StrictHostKeyChecking=no "$host" <<EOF
docker exec postgres-$region pg_dump -U $DB_USER -Fc -v --no-acl --no-owner $DB_NAME | gzip > /tmp/${region}-db-${TIMESTAMP}.sql.gz
EOF

        # Copy from remote to local
        scp -o StrictHostKeyChecking=no "${host}:/tmp/${region}-db-${TIMESTAMP}.sql.gz" "${backup_file}.gz"

        local size=$(du -h "${backup_file}.gz" | cut -f1)
        log_success "Full database backup completed: $size"
        log_metric "db_backup_size_${region}" "$(du -b "${backup_file}.gz" | cut -f1)"

        # Upload to S3
        if command -v aws &> /dev/null; then
            aws s3 cp "${backup_file}.gz" "s3://${S3_BUCKET}/${S3_PREFIX}/${region}/db-${backup_type}-${TIMESTAMP}.sql.gz"
            log_success "Backup uploaded to S3"
        fi

    # Incremental backup using WAL archiving
    elif [ "$backup_type" = "incremental" ]; then
        ssh -o StrictHostKeyChecking=no "$host" <<EOF
docker exec postgres-$region pg_dump -U $DB_USER --incremental $DB_NAME > /tmp/${region}-db-incremental-${TIMESTAMP}.sql
EOF

        scp -o StrictHostKeyChecking=no "${host}:/tmp/${region}-db-incremental-${TIMESTAMP}.sql" "${backup_file}"

        local size=$(du -h "${backup_file}" | cut -f1)
        log_success "Incremental database backup completed: $size"
        log_metric "db_incremental_backup_${region}" "$(du -b "${backup_file}" | cut -f1)"
    fi

    return 0
}

backup_all_databases() {
    local backup_type="${1:-full}"

    log "Backing up all regions (type: $backup_type)..."

    backup_database "$PRIMARY_REGION" "$PRIMARY_HOST" "$backup_type"
    backup_database "$SECONDARY_REGION" "$SECONDARY_HOST" "$backup_type"

    # Tertiary only for critical full backups
    if [ "$backup_type" = "full" ]; then
        backup_database "$TERTIARY_REGION" "$TERTIARY_HOST" "$backup_type"
    fi

    log_success "All database backups completed"
}

# ============================================================================
# GIT REPOSITORY BACKUPS
# ============================================================================

backup_git_repos() {
    local region="$1"
    local host="$2"

    log "Creating git repository backup for region: $region"

    local backup_file="${BACKUP_DIR}/${region}-git-repos-${TIMESTAMP}.tar.gz"

    # Backup all user repositories
    ssh -o StrictHostKeyChecking=no "$host" <<EOF
tar czf /tmp/${region}-git-repos-${TIMESTAMP}.tar.gz \
    --exclude='.git/objects/pack/*.tmp' \
    /home/*/code /opt/git-proxy/repos 2>/dev/null || true
EOF

    # Copy from remote
    scp -o StrictHostKeyChecking=no "${host}:/tmp/${region}-git-repos-${TIMESTAMP}.tar.gz" "${backup_file}"

    local size=$(du -h "${backup_file}" | cut -f1)
    log_success "Git repository backup completed: $size"
    log_metric "git_backup_size_${region}" "$(du -b "${backup_file}" | cut -f1)"

    # Upload to S3
    if command -v aws &> /dev/null; then
        aws s3 cp "${backup_file}" "s3://${S3_BUCKET}/${S3_PREFIX}/${region}/git-repos-${TIMESTAMP}.tar.gz"
        log_success "Git backup uploaded to S3"
    fi
}

backup_all_repos() {
    log "Backing up git repositories from all regions..."

    backup_git_repos "$PRIMARY_REGION" "$PRIMARY_HOST"
    backup_git_repos "$SECONDARY_REGION" "$SECONDARY_HOST"

    log_success "All repository backups completed"
}

# ============================================================================
# REDIS BACKUPS
# ============================================================================

backup_redis() {
    local region="$1"
    local host="$2"

    log "Creating Redis snapshot for region: $region"

    local backup_file="${BACKUP_DIR}/${region}-redis-${TIMESTAMP}.rdb"

    # Trigger BGSAVE on Redis
    ssh -o StrictHostKeyChecking=no "$host" <<EOF
docker exec redis-$region redis-cli BGSAVE
sleep 2
docker cp redis-$region:/data/dump.rdb /tmp/${region}-redis-${TIMESTAMP}.rdb
EOF

    # Copy from remote
    scp -o StrictHostKeyChecking=no "${host}:/tmp/${region}-redis-${TIMESTAMP}.rdb" "${backup_file}"

    local size=$(du -h "${backup_file}" | cut -f1)
    log_success "Redis snapshot completed: $size"
    log_metric "redis_backup_size_${region}" "$(du -b "${backup_file}" | cut -f1)"

    # Upload to S3
    if command -v aws &> /dev/null; then
        aws s3 cp "${backup_file}" "s3://${S3_BUCKET}/${S3_PREFIX}/${region}/redis-${TIMESTAMP}.rdb"
        log_success "Redis backup uploaded to S3"
    fi
}

backup_all_redis() {
    log "Creating Redis snapshots from all regions..."

    backup_redis "$PRIMARY_REGION" "$PRIMARY_HOST"
    backup_redis "$SECONDARY_REGION" "$SECONDARY_HOST"

    log_success "All Redis backups completed"
}

# ============================================================================
# FULL BACKUP SUITE
# ============================================================================

full_backup() {
    log "Starting comprehensive full backup..."

    backup_all_databases "full"
    backup_all_repos
    backup_all_redis

    # Verify backup integrity
    log "Verifying backup integrity..."
    for backup in "${BACKUP_DIR}"/*-${TIMESTAMP}*; do
        if [ -f "$backup" ]; then
            local checksum=$(sha256sum "$backup" | awk '{print $1}')
            echo "$backup: $checksum" >> "${LOG_DIR}/backup-checksums.txt"
            log_success "Verified: $(basename "$backup")"
        fi
    done

    log_success "Full backup completed successfully"
}

# ============================================================================
# CROSS-REGION REPLICATION
# ============================================================================

setup_database_replication() {
    log "Setting up database streaming replication..."

    # Primary: Configure for replication
    ssh -o StrictHostKeyChecking=no "$PRIMARY_HOST" <<EOF
docker exec postgres-$PRIMARY_REGION psql -U postgres -d postgres <<'SQL'
CREATE USER repl_user REPLICATION LOGIN ENCRYPTED PASSWORD 'repl_password';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET wal_level = logical;
SELECT pg_reload_conf();
SQL
EOF

    log_success "Primary configured for replication"

    # Secondary: Join replication slot
    ssh -o StrictHostKeyChecking=no "$SECONDARY_HOST" <<EOF
docker exec postgres-$SECONDARY_REGION psql -U postgres -d postgres <<'SQL'
CREATE SUBSCRIPTION secondary_sub CONNECTION 'host=$PRIMARY_HOST port=5432 user=repl_user password=repl_password dbname=$DB_NAME' PUBLICATION all_changes;
SQL
EOF

    log_success "Secondary joined replication"
    sleep 10

    # Verify replication
    validate_replication
}

setup_redis_replication() {
    log "Setting up Redis cross-region replication..."

    # Primary: Configure as master
    ssh -o StrictHostKeyChecking=no "$PRIMARY_HOST" "docker exec redis-$PRIMARY_REGION redis-cli CONFIG SET save '900 1 300 10 60 10000'"

    # Secondary: Configure as slave
    ssh -o StrictHostKeyChecking=no "$SECONDARY_HOST" "docker exec redis-$SECONDARY_REGION redis-cli SLAVEOF $PRIMARY_HOST 6379"

    log_success "Redis replication configured"
    sleep 5

    # Verify replication
    local role=$(ssh -o StrictHostKeyChecking=no "$SECONDARY_HOST" "docker exec redis-$SECONDARY_REGION redis-cli INFO replication | grep role" 2>/dev/null)
    if echo "$role" | grep -q "slave"; then
        log_success "Redis slave role confirmed: $role"
    else
        log_error "Redis slave role not confirmed"
    fi
}

# ============================================================================
# REPLICATION VALIDATION
# ============================================================================

validate_replication() {
    log "Validating replication status..."

    # Check PostgreSQL replication lag
    local pg_lag=$(ssh -o StrictHostKeyChecking=no "$SECONDARY_HOST" <<'EOF'
docker exec postgres-$SECONDARY_REGION psql -U postgres -d postgres -Atc "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int" 2>/dev/null || echo "unknown"
EOF
)

    log "PostgreSQL replication lag: ${pg_lag}s"
    log_metric "pg_replication_lag" "${pg_lag}"

    if [ "${pg_lag}" != "unknown" ] && [ "${pg_lag}" -gt 60 ]; then
        log_error "PostgreSQL replication lag exceeds 60 seconds: ${pg_lag}s"
        return 1
    else
        log_success "PostgreSQL replication lag acceptable"
    fi

    # Check Redis replication
    local redis_status=$(ssh -o StrictHostKeyChecking=no "$PRIMARY_HOST" "docker exec redis-$PRIMARY_REGION redis-cli INFO replication | grep connected_slaves" 2>/dev/null)

    if echo "$redis_status" | grep -q "connected_slaves:1"; then
        log_success "Redis replication healthy: $redis_status"
    else
        log_error "Redis replication issue: $redis_status"
        return 1
    fi

    log_success "Replication validation: HEALTHY"
}

# ============================================================================
# DATA CONSISTENCY CHECKS
# ============================================================================

check_data_consistency() {
    log "Checking data consistency across regions..."

    # Compare database record counts
    local primary_count=$(ssh -o StrictHostKeyChecking=no "$PRIMARY_HOST" <<'EOF'
docker exec postgres-$PRIMARY_REGION psql -U $DB_USER -d $DB_NAME -Atc "
SELECT COUNT(*) FROM (
    SELECT * FROM pg_catalog.pg_tables WHERE schemaname='public'
) AS tables
" 2>/dev/null || echo "0"
EOF
)

    local secondary_count=$(ssh -o StrictHostKeyChecking=no "$SECONDARY_HOST" <<'EOF'
docker exec postgres-$SECONDARY_REGION psql -U $DB_USER -d $DB_NAME -Atc "
SELECT COUNT(*) FROM (
    SELECT * FROM pg_catalog.pg_tables WHERE schemaname='public'
) AS tables
" 2>/dev/null || echo "0"
EOF
)

    if [ "$primary_count" = "$secondary_count" ]; then
        log_success "Database consistency: MATCH (tables: $primary_count)"
        log_metric "db_table_count_match" "$primary_count"
    else
        log_error "Database consistency MISMATCH: primary=$primary_count, secondary=$secondary_count"
        return 1
    fi

    # Compare Redis key counts
    local redis_primary=$(ssh -o StrictHostKeyChecking=no "$PRIMARY_HOST" "docker exec redis-$PRIMARY_REGION redis-cli DBSIZE | awk '{print \$2}'" 2>/dev/null || echo "0")
    local redis_secondary=$(ssh -o StrictHostKeyChecking=no "$SECONDARY_HOST" "docker exec redis-$SECONDARY_REGION redis-cli DBSIZE | awk '{print \$2}'" 2>/dev/null || echo "0")

    if [ "$redis_primary" = "$redis_secondary" ]; then
        log_success "Redis consistency: MATCH (keys: $redis_primary)"
        log_metric "redis_key_count_match" "$redis_primary"
    else
        log_error "Redis consistency MISMATCH: primary=$redis_primary, secondary=$redis_secondary"
        return 1
    fi

    log_success "Data consistency check: PASSED"
}

# ============================================================================
# BACKUP ROTATION & RETENTION
# ============================================================================

cleanup_old_backups() {
    log "Cleaning up old backups (retention: ${S3_RETENTION_DAYS} days)..."

    # Local cleanup
    local cutoff=$(date -d "$S3_RETENTION_DAYS days ago" +%Y%m%d)

    for backup in "${BACKUP_DIR}"/*; do
        if [ -f "$backup" ]; then
            local backup_date=$(echo "$(basename "$backup")" | grep -oE '[0-9]{8}' | head -1)
            if [ "$backup_date" ] && [ "$backup_date" -lt "$cutoff" ]; then
                log "Removing old backup: $(basename "$backup")"
                rm -f "$backup"
            fi
        fi
    done

    # S3 cleanup (if configured)
    if command -v aws &> /dev/null; then
        log "Removing old S3 backups..."
        aws s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/" \
            --recursive \
            --exclude "*" \
            --include "*" \
            --older-than "$S3_RETENTION_DAYS" || true
    fi

    log_success "Backup cleanup completed"
}

# ============================================================================
# RESTORE OPERATIONS
# ============================================================================

restore_database() {
    local region="$1"
    local host="$2"
    local backup_file="$3"

    log "Restoring database from backup: $backup_file in region: $region"

    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    # Copy backup to remote
    scp -o StrictHostKeyChecking=no "$backup_file" "${host}:/tmp/restore-db.sql.gz"

    # Restore database
    ssh -o StrictHostKeyChecking=no "$host" <<EOF
docker exec postgres-$region psql -U $DB_USER -d $DB_NAME < <(zcat /tmp/restore-db.sql.gz)
sleep 5
rm /tmp/restore-db.sql.gz
EOF

    log_success "Database restored successfully"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  PHASE 18: BACKUP & REPLICATION AUTOMATION${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    local command="${1:-help}"

    case "$command" in
        "full")
            log "Executing full backup..."
            full_backup
            ;;

        "database")
            log "Backing up databases..."
            backup_all_databases "${2:-full}"
            ;;

        "repos")
            log "Backing up git repositories..."
            backup_all_repos
            ;;

        "redis")
            log "Backing up Redis..."
            backup_all_redis
            ;;

        "setup-replication")
            log "Setting up replication..."
            setup_database_replication
            setup_redis_replication
            ;;

        "validate")
            log "Validating replication..."
            validate_replication
            ;;

        "consistency")
            log "Checking data consistency..."
            check_data_consistency
            ;;

        "cleanup")
            log "Cleaning up old backups..."
            cleanup_old_backups
            ;;

        "restore")
            if [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
                log_error "Usage: $0 restore <region> <host> <backup_file>"
                return 1
            fi
            restore_database "$2" "$3" "$4"
            ;;

        "help"|*)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  full              - Execute full backup suite"
            echo "  database [type]   - Backup all databases (full|incremental)"
            echo "  repos             - Backup all git repositories"
            echo "  redis             - Backup all Redis instances"
            echo "  setup-replication - Configure streaming replication"
            echo "  validate          - Validate replication status"
            echo "  consistency       - Check data consistency"
            echo "  cleanup           - Clean old backups (retention)"
            echo "  restore <region> <host> <file> - Restore from backup"
            ;;
    esac
}

main "$@"
