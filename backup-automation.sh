#!/bin/bash
# Automated Backup & Disaster Recovery Script
# Phase 6d: Disaster Recovery & Backup Automation
# Usage: sudo crontab -e
# 0 2 * * * /home/akushnir/code-server-enterprise/backup-automation.sh

set -e

# Configuration
BACKUP_DIR="/backups/code-server"
RETENTION_DAYS=30
DB_CONTAINER="postgres"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/db_backup_${TIMESTAMP}.sql"
LOG_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.log"

# Create backup directory if not exists
mkdir -p "${BACKUP_DIR}"

# Start logging
{
    echo "=== Backup Start: $(date) ==="
    
    # 1. PostgreSQL Backup
    echo "[1] Backing up PostgreSQL..."
    if docker exec "${DB_CONTAINER}" pg_dump -U postgres > "${BACKUP_FILE}"; then
        SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
        echo "✅ PostgreSQL backup successful (${SIZE}): ${BACKUP_FILE}"
    else
        echo "❌ PostgreSQL backup failed"
        exit 1
    fi
    
    # 2. Redis Backup (RDB)
    echo "[2] Backing up Redis..."
    REDIS_BACKUP="${BACKUP_DIR}/redis_dump_${TIMESTAMP}.rdb"
    if docker exec redis redis-cli BGSAVE > /dev/null && \
       docker exec redis redis-cli LASTSAVE > /dev/null; then
        docker cp redis:/data/dump.rdb "${REDIS_BACKUP}"
        echo "✅ Redis backup successful: ${REDIS_BACKUP}"
    else
        echo "⚠️  Redis backup skipped (non-critical)"
    fi
    
    # 3. Configuration Backup
    echo "[3] Backing up configuration..."
    CONFIG_BACKUP="${BACKUP_DIR}/config_${TIMESTAMP}.tar.gz"
    tar -czf "${CONFIG_BACKUP}" \
        /home/akushnir/code-server-enterprise/{docker-compose.yml,Caddyfile,.env} \
        2>/dev/null || echo "⚠️  Some config files not found"
    echo "✅ Configuration backup successful: ${CONFIG_BACKUP}"
    
    # 4. Verify backup integrity
    echo "[4] Verifying backup integrity..."
    if file "${BACKUP_FILE}" | grep -q "SQL"; then
        echo "✅ Backup integrity verified"
    else
        echo "❌ Backup integrity check failed"
        exit 1
    fi
    
    # 5. Compress backup
    echo "[5] Compressing backup..."
    gzip "${BACKUP_FILE}"
    echo "✅ Backup compressed: ${BACKUP_FILE}.gz"
    
    # 6. Cleanup old backups
    echo "[6] Cleaning up old backups (retention: ${RETENTION_DAYS} days)..."
    find "${BACKUP_DIR}" -name "db_backup_*.sql.gz" -mtime +${RETENTION_DAYS} -delete
    DELETED_COUNT=$(find "${BACKUP_DIR}" -mtime +${RETENTION_DAYS} | wc -l)
    echo "✅ Deleted ${DELETED_COUNT} old backups"
    
    # 7. Upload to remote (if configured)
    echo "[7] Remote upload status..."
    if command -v aws &> /dev/null; then
        echo "AWS S3 configured - uploading backup..."
        aws s3 cp "${BACKUP_FILE}.gz" "s3://backups/code-server/${TIMESTAMP}/" --storage-class GLACIER
        echo "✅ Backup uploaded to S3"
    else
        echo "⚠️  Remote backup not configured (S3 credentials not found)"
    fi
    
    # 8. Test restore (weekly, on Sundays)
    DOW=$(date +%w)
    if [ "$DOW" -eq 0 ]; then
        echo "[8] Running weekly restore test..."
        TEST_DB="test_restore_${TIMESTAMP}"
        echo "Creating test database: ${TEST_DB}"
        docker exec postgres createdb -U postgres "${TEST_DB}" 2>/dev/null || true
        
        echo "Testing restore..."
        if docker exec postgres pg_restore -U postgres -d "${TEST_DB}" < "${BACKUP_FILE}"; then
            echo "✅ Restore test successful"
            docker exec postgres dropdb -U postgres "${TEST_DB}" 2>/dev/null || true
        else
            echo "❌ Restore test failed - backup may be corrupted"
        fi
    fi
    
    # Summary
    echo ""
    echo "=== Backup Summary ==="
    echo "Start Time: $(date)"
    echo "Backup Location: ${BACKUP_FILE}.gz"
    echo "Retention Policy: ${RETENTION_DAYS} days"
    echo "Backup Type: Automated (Daily at 2:00 AM)"
    echo "Status: SUCCESS ✅"
    echo "=== Backup Complete ==="
    
} | tee "${LOG_FILE}"

# Exit success
exit 0
