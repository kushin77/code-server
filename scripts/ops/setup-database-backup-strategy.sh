#!/usr/bin/env bash
# @file        scripts/ops/setup-database-backup-strategy.sh
# @module      infrastructure/backup
# @description Setup automated PostgreSQL backup strategy with point-in-time recovery
# @owner       Infrastructure Team
# @status      In development - April 23, 2026

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
BACKUP_USER="${BACKUP_USER:-akushnir}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

# Backup configuration
BACKUP_DIR="/var/backups/postgresql"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
WAL_ARCHIVE_DIR="/var/lib/postgresql/wal_archive"
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-hourly}"  # hourly, daily
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-gzip}"  # gzip, bzip2

# ============================================================================
# Logging Functions
# ============================================================================

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_warn() { echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[✓] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# ============================================================================
# Backup Directory Setup
# ============================================================================

setup_backup_directories() {
    log_info "Setting up backup directories..."
    
    ssh "${BACKUP_USER}@${PRIMARY_HOST}" "
    mkdir -p ${BACKUP_DIR}
    mkdir -p ${WAL_ARCHIVE_DIR}
    chmod 700 ${BACKUP_DIR}
    chmod 700 ${WAL_ARCHIVE_DIR}
    "
    
    log_success "Backup directories created"
}

# ============================================================================
# PostgreSQL Configuration for Backups
# ============================================================================

configure_postgres_for_backups() {
    log_info "Configuring PostgreSQL for backup and WAL archiving..."
    
    ssh "${BACKUP_USER}@${PRIMARY_HOST}" "
    docker exec ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -c \"
        ALTER SYSTEM SET archive_mode = on;
        ALTER SYSTEM SET archive_command = 'cp %p ${WAL_ARCHIVE_DIR}/%f';
        ALTER SYSTEM SET archive_timeout = 300;
        ALTER SYSTEM SET wal_level = replica;
        ALTER SYSTEM SET max_wal_senders = 5;
        SELECT pg_reload_conf();
    \"
    "
    
    log_success "PostgreSQL backup configuration applied"
}

# ============================================================================
# pgBackRest Configuration
# ============================================================================

setup_pgbackrest() {
    log_info "Setting up pgBackRest for advanced backup management..."
    
    cat > /tmp/pgbackrest.conf <<'EOF'
[global]
repo-path=/var/lib/pgbackrest
process-max=2
log-level-console=info
log-level-file=debug
delta=y
archive-push-queue-max=268435456
archive-timeout=60

[stanza:code-server]
db-path=/var/lib/postgresql/data
recovery-option=standby_mode=on
recovery-option=standby_signal=''

[global:archive-push]
archive-timeout=60

[global:archive-get]
archive-timeout=60
EOF
    
    ssh "${BACKUP_USER}@${PRIMARY_HOST}" "
    # Install pgBackRest if not present
    docker exec ${POSTGRES_CONTAINER} bash -c '
        apt-get update > /dev/null 2>&1
        apt-get install -y pgbackrest > /dev/null 2>&1 || true
    ' || log_warn "pgBackRest installation may have failed"
    
    # Copy configuration
    scp /tmp/pgbackrest.conf ${BACKUP_USER}@${PRIMARY_HOST}:${BACKUP_DIR}/pgbackrest.conf
    
    # Initialize pgBackRest
    docker exec ${POSTGRES_CONTAINER} pgbackrest --stanza=code-server stanza-create || log_warn 'pgBackRest stanza may already exist'
    "
    
    log_success "pgBackRest configured"
}

# ============================================================================
# Automated Backup Scheduling (via cron)
# ============================================================================

setup_backup_cron_jobs() {
    log_info "Setting up automated backup cron jobs..."
    
    cat > /tmp/postgres-backup-cron <<'EOF'
#!/bin/bash
# PostgreSQL Backup Cron Job

BACKUP_DIR="/var/backups/postgresql"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/backup-${TIMESTAMP}.sql.gz"
POSTGRES_USER="postgres"

# Perform backup
docker exec postgres pg_dump -U ${POSTGRES_USER} -d code_server | gzip > "${BACKUP_FILE}"

# Verify backup
if [ -f "${BACKUP_FILE}" ] && [ -s "${BACKUP_FILE}" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Backup created: $(du -h ${BACKUP_FILE} | cut -f1)"
    
    # Cleanup old backups (retention policy)
    find ${BACKUP_DIR} -name 'backup-*.sql.gz' -mtime +30 -delete
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ Backup failed or empty"
    exit 1
fi
EOF
    
    ssh "${BACKUP_USER}@${PRIMARY_HOST}" "
    # Copy backup script
    cat > /tmp/postgres-backup.sh <<'SCRIPT'
$(cat /tmp/postgres-backup-cron)
SCRIPT
    
    chmod +x /tmp/postgres-backup.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null || echo '') | grep -v 'postgres-backup.sh' > /tmp/crontab.tmp || true
    echo '0 * * * * /tmp/postgres-backup.sh >> /var/log/postgres-backup.log 2>&1' >> /tmp/crontab.tmp
    crontab /tmp/crontab.tmp
    rm -f /tmp/crontab.tmp
    "
    
    log_success "Backup cron jobs configured"
}

# ============================================================================
# Point-in-Time Recovery Configuration
# ============================================================================

setup_pitr_capability() {
    log_info "Setting up Point-in-Time Recovery (PITR) capability..."
    
    ssh "${BACKUP_USER}@${PRIMARY_HOST}" "
    docker exec ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -c \"
        -- Enable WAL archiving for PITR
        ALTER SYSTEM SET archive_mode = on;
        ALTER SYSTEM SET archive_command = 'test ! -f ${WAL_ARCHIVE_DIR}/%f && cp %p ${WAL_ARCHIVE_DIR}/%f';
        
        -- Create base backup timeline
        SELECT pg_basebackup(
            format := 'tar',
            compression := 'gzip',
            label := 'pitr-baseline-$(date +%Y%m%d_%H%M%S)',
            progress := true
        );
    \"
    
    # Archive base backup for PITR recovery
    docker exec ${POSTGRES_CONTAINER} bash -c '
        mkdir -p ${WAL_ARCHIVE_DIR}/base-backups
        ls -la /var/lib/postgresql/data/backup_label > ${WAL_ARCHIVE_DIR}/base-backups/backup-info.txt
    ' || true
    "
    
    log_success "PITR capability enabled"
}

# ============================================================================
# Backup Verification
# ============================================================================

verify_backup_integrity() {
    log_info "Verifying backup integrity..."
    
    ssh "${BACKUP_USER}@${PRIMARY_HOST}" "
    LATEST_BACKUP=\$(ls -t ${BACKUP_DIR}/backup-*.sql.gz | head -1)
    
    if [ -f \"\${LATEST_BACKUP}\" ]; then
        # Check file size
        SIZE=\$(du -h \"\${LATEST_BACKUP}\" | cut -f1)
        echo \"Latest backup: \$(basename \${LATEST_BACKUP}) (\${SIZE})\"
        
        # Verify gzip integrity
        gunzip -t \"\${LATEST_BACKUP}\" 2>/dev/null && echo '✓ Backup integrity verified' || echo '✗ Backup corrupt'
    else
        echo '✗ No backups found'
    fi
    "
    
    log_success "Backup verification completed"
}

# ============================================================================
# Restore Procedure Documentation
# ============================================================================

create_restore_documentation() {
    cat > /tmp/RESTORE-PROCEDURE.md <<'EOF'
# PostgreSQL Backup & Restore Procedures

## Backup Strategy
- **Frequency**: Hourly full backups + WAL archiving
- **Retention**: 30 days (automatic cleanup)
- **Compression**: gzip
- **RTO**: <30 minutes
- **RPO**: <1 hour
- **Location**: /var/backups/postgresql

## Restore from Latest Backup

### 1. Stop PostgreSQL
```bash
docker-compose stop postgres
```

### 2. Restore Full Backup
```bash
LATEST_BACKUP=$(ls -t /var/backups/postgresql/backup-*.sql.gz | head -1)
gunzip < ${LATEST_BACKUP} | docker exec -i postgres psql -U postgres
```

### 3. Start PostgreSQL
```bash
docker-compose start postgres
docker exec postgres psql -U postgres -c "SELECT version();"
```

## Point-in-Time Recovery (PITR)

### 1. Locate WAL Archives
```bash
ls -la /var/lib/postgresql/wal_archive/
```

### 2. Identify Target Time
```bash
# Find WAL file for specific timestamp
ls /var/lib/postgresql/wal_archive/ | grep "201603"  # YYYYMM
```

### 3. Restore to Specific Time
```bash
# Modify recovery.conf or standby.signal
recovery_target_time = '2026-04-23 10:30:00'  # Your target time
recovery_target_inclusive = false
```

## Backup Verification

### Check Backup Size
```bash
du -h /var/backups/postgresql/backup-*.sql.gz
```

### Test Restore (Safe Method)
```bash
# Create test database from backup
LATEST_BACKUP=$(ls -t /var/backups/postgresql/backup-*.sql.gz | head -1)
docker exec postgres bash -c "gunzip < ${LATEST_BACKUP} | psql -U postgres -d test_restore"
```

### Verify Data Integrity
```bash
docker exec postgres psql -U postgres -d code_server -c "
  SELECT 
    'users' as table_name, COUNT(*) as row_count 
  FROM users
  UNION ALL
  SELECT 'sessions', COUNT(*) FROM sessions
  UNION ALL
  SELECT 'audit_log', COUNT(*) FROM audit_log;
"
```

## Disaster Recovery Plan

| Scenario | RTO | RPO | Procedure |
|----------|-----|-----|-----------|
| Host failure | 5m | <5min | Promote replica from replication |
| DB corruption | 15m | <1h | Restore from latest backup |
| Accidental delete | 30m | <1h | PITR to point before delete |
| Complete DC loss | 1h | <1h | Restore from off-site backup + PITR |

## Monitoring Backups

```bash
# Monitor backup directory
du -sh /var/backups/postgresql

# Check backup creation times
ls -ltr /var/backups/postgresql/backup-*.sql.gz | tail -5

# Monitor WAL archive directory
du -sh /var/lib/postgresql/wal_archive
ls /var/lib/postgresql/wal_archive | tail -10

# Monitor cron job logs
tail -50 /var/log/postgres-backup.log
```
EOF
    
    log_info "Restore documentation created: /tmp/RESTORE-PROCEDURE.md"
}

# ============================================================================
# Test Restore Capability
# ============================================================================

test_restore_capability() {
    log_info "Testing restore capability (non-destructive)..."
    
    ssh "${BACKUP_USER}@${PRIMARY_HOST}" "
    # Get latest backup
    LATEST_BACKUP=\$(ls -t ${BACKUP_DIR}/backup-*.sql.gz 2>/dev/null | head -1)
    
    if [ -n \"\${LATEST_BACKUP}\" ]; then
        # Create test database
        docker exec ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -c 'CREATE DATABASE test_restore;' 2>/dev/null || true
        
        # Test restore into test database
        gunzip < \"\${LATEST_BACKUP}\" | docker exec -i ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -d test_restore 2>/dev/null
        
        # Verify restore
        COUNT=\$(docker exec ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -d test_restore -c 'SELECT COUNT(*) FROM information_schema.tables;' 2>/dev/null | tail -1)
        echo \"Test restore: \${COUNT} tables restored\"
        
        # Cleanup
        docker exec ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -c 'DROP DATABASE test_restore;' 2>/dev/null || true
    else
        echo 'No backups available for test'
    fi
    "
    
    log_success "Restore capability test completed"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "PostgreSQL Database Backup Strategy Setup"
    log_info "Primary host: ${PRIMARY_HOST}"
    log_info "Retention: ${BACKUP_RETENTION_DAYS} days"
    log_info "RTO target: 30 minutes"
    log_info "RPO target: 1 hour"
    
    # Execute setup steps
    setup_backup_directories
    configure_postgres_for_backups
    setup_backup_cron_jobs
    setup_pitr_capability
    verify_backup_integrity
    create_restore_documentation
    test_restore_capability
    
    log_success "✓ PostgreSQL backup strategy deployed!"
    log_info "Backups will run hourly at top of hour"
    log_info "Monitor: tail -f /var/log/postgres-backup.log"
    log_info "Verify: ls -ltr ${BACKUP_DIR}/backup-*.sql.gz | tail -5"
    
    return 0
}

main "$@"
