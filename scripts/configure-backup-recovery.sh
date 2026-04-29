#!/bin/bash

################################################################################
# Phase 7.2: Automated Backup & Disaster Recovery
# Purpose: Implement backup automation, point-in-time recovery, and DR procedures
# Usage: ./scripts/configure-backup-recovery.sh [--apply]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup: Removing temporary backup files..."; rm -f /tmp/backup-*.tmp 2>/dev/null || true' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

DR_DIR="${PROJECT_ROOT}/disaster-recovery"
BACKUP_DIR="/data/backups"

################################################################################
# 1. BACKUP POLICIES AND CONFIGURATION
################################################################################

create_backup_policies() {
    log_info "Creating backup policies..."

    mkdir -p "$DR_DIR"

    cat > "${DR_DIR}/backup-policies.yaml" << 'BACKUP_POLICIES'
---
# Backup and Disaster Recovery Policies

backup:
  # Backup schedule
  schedule:
    # Daily incremental backups at 2 AM UTC
    daily_incremental:
      frequency: daily
      time: "02:00"
      retention_days: 7
      type: incremental
    
    # Weekly full backups on Sunday at 3 AM UTC
    weekly_full:
      frequency: weekly
      day: sunday
      time: "03:00"
      retention_days: 30
      type: full
    
    # Monthly full backups on 1st of month at 4 AM UTC
    monthly_full:
      frequency: monthly
      day: 1
      time: "04:00"
      retention_days: 365
      type: full

  # Backup targets
  targets:
    # PostgreSQL database backups
    postgres:
      enabled: true
      container: code-server-postgres
      backup_type: sql_dump
      compression: gzip
      parallel_jobs: 4
      retention_days: 30
      location: s3://code-server-backups/postgres/
      
      # Point-in-time recovery setup
      wal_archiving:
        enabled: true
        destination: s3://code-server-backups/postgres/wal/
        format: custom
    
    # Redis data backups
    redis:
      enabled: true
      container: code-server-redis
      backup_type: rdb_snapshot
      compression: none
      retention_days: 7
      location: s3://code-server-backups/redis/
      
      # Replication backup during replication
      backup_during_replication: true
    
    # MinIO object storage backups
    minio:
      enabled: true
      container: code-server-minio
      backup_type: mc_mirror
      compression: gzip
      retention_days: 60
      location: s3://code-server-backups/minio/
      
      # Exclude certain buckets from backup
      exclude_buckets: [temp, cache, logs]
    
    # Vault secrets backup
    vault:
      enabled: true
      container: code-server-vault
      backup_type: raft_snapshot
      compression: gzip
      encryption: aes256
      retention_days: 90
      location: s3://code-server-backups/vault/
      
      # Offline backup location
      offline_location: /data/vault-offline-backup/
    
    # Docker configurations
    docker_configs:
      enabled: true
      backup_type: tar
      compression: gzip
      retention_days: 30
      location: s3://code-server-backups/docker-configs/
      paths:
        - /data/docker-compose*
        - /data/certs
        - /data/configs

  # Backup verification
  verification:
    enabled: true
    after_backup:
      - verify_checksum
      - restore_test_environment
      - data_integrity_check
    schedule: daily
    restore_test_host: 192.168.168.43  # Test environment

  # Backup encryption
  encryption:
    enabled: true
    algorithm: aes256
    key_location: vault://secret/data/backup-encryption-key
    key_rotation_frequency: monthly

  # Backup monitoring
  monitoring:
    enabled: true
    alerts:
      - backup_failed: critical
      - backup_slow: warning
      - backup_verification_failed: critical
      - insufficient_backup_retention: warning

# Disaster Recovery
disaster_recovery:
  # RTO and RPO targets
  rto: 4h              # Recovery Time Objective
  rpo: 1h              # Recovery Point Objective

  # DR runbook
  runbook:
    # Data center failure procedures
    full_datacenter_failure:
      steps:
        - "Verify primary data center is completely down"
        - "Promote replica data center to primary"
        - "Update DNS to point to new primary"
        - "Verify all services are operational"
        - "Begin restore of affected components"
        - "Perform data consistency checks"
      estimated_time: 2h
    
    # Database failure procedures
    database_failure:
      steps:
        - "Verify database is unreachable"
        - "Check replica status"
        - "Promote replica if master is down"
        - "Restore from latest backup if needed"
        - "Verify data integrity"
        - "Resume write operations"
      estimated_time: 30m
    
    # Partial data loss recovery
    data_loss_recovery:
      steps:
        - "Identify point of data loss"
        - "Stop write operations"
        - "Restore from PITR backup at pre-loss time"
        - "Validate restored data"
        - "Resume write operations"
      estimated_time: 1h

  # Failover automation
  failover:
    automatic_failover: true
    failover_threshold:
      consecutive_failures: 3
      time_window_seconds: 30
    
    pre_failover_validation:
      - check_replica_health
      - verify_replication_lag
      - validate_data_consistency
    
    post_failover_validation:
      - verify_write_operations
      - check_client_connections
      - monitor_error_rates

# Backup storage
storage:
  # Primary backup location
  primary:
    type: s3
    bucket: code-server-backups
    region: us-east-1
    storage_class: STANDARD_IA
    lifecycle:
      transition_to_glacier: 90 days
      expiration: 2555 days (7 years for compliance)
  
  # Secondary backup location (geo-redundancy)
  secondary:
    type: s3
    bucket: code-server-backups-secondary
    region: us-west-2
    replication: enabled
    replication_lag_sla: 24h

# Backup reports
reporting:
  enabled: true
  schedule: daily
  recipients: [ops-team@example.com, security@example.com]
  include_metrics:
    - backup_success_rate
    - backup_duration
    - data_size
    - recovery_test_results
    - compliance_status

BACKUP_POLICIES

    log_success "Backup policies created"
}

################################################################################
# 2. AUTOMATED BACKUP SCRIPTS
################################################################################

create_backup_scripts() {
    log_info "Creating automated backup scripts..."

    cat > "${DR_DIR}/backup-manager.sh" << 'BACKUP_MANAGER'
#!/bin/bash

# Automated Backup Manager
# Executes backup procedures per defined policies

set -euo pipefail

LOG_FILE="/var/log/backup-manager.log"
BACKUP_DIR="/data/backups"
REMOTE_BACKUP_BUCKET="s3://code-server-backups"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Backup PostgreSQL
backup_postgres() {
    log "Starting PostgreSQL backup..."
    
    backup_file="$BACKUP_DIR/postgres-$(date +%Y%m%d-%H%M%S).sql.gz"
    
    # Create backup
    docker exec code-server-postgres pg_dump -U postgres --format=plain | gzip > "$backup_file"
    
    # Verify backup
    if [ -f "$backup_file" ]; then
        size=$(du -h "$backup_file" | cut -f1)
        log "✓ PostgreSQL backup created: $backup_file ($size)"
        
        # Upload to S3
        aws s3 cp "$backup_file" "$REMOTE_BACKUP_BUCKET/postgres/"
        
        # Keep local copy for quick restore
        find "$BACKUP_DIR" -name "postgres-*.sql.gz" -mtime +7 -delete
    else
        log "✗ PostgreSQL backup failed"
        return 1
    fi
}

# Backup Redis
backup_redis() {
    log "Starting Redis backup..."
    
    backup_file="$BACKUP_DIR/redis-$(date +%Y%m%d-%H%M%S).rdb"
    
    # Create backup via BGSAVE
    docker exec code-server-redis redis-cli BGSAVE
    
    # Wait for backup to complete
    while docker exec code-server-redis redis-cli LASTSAVE | grep -q "$(date +%s)"; do
        sleep 1
    done
    
    # Copy RDB file
    docker cp code-server-redis:/data/dump.rdb "$backup_file"
    
    if [ -f "$backup_file" ]; then
        size=$(du -h "$backup_file" | cut -f1)
        log "✓ Redis backup created: $backup_file ($size)"
        
        # Upload to S3
        aws s3 cp "$backup_file" "$REMOTE_BACKUP_BUCKET/redis/"
        
        # Keep only recent backups
        find "$BACKUP_DIR" -name "redis-*.rdb" -mtime +7 -delete
    else
        log "✗ Redis backup failed"
        return 1
    fi
}

# Backup Vault
backup_vault() {
    log "Starting Vault backup..."
    
    backup_file="$BACKUP_DIR/vault-$(date +%Y%m%d-%H%M%S).snap"
    
    # Create Raft snapshot
    docker exec code-server-vault vault operator raft snapshot save "$backup_file"
    
    if [ -f "$backup_file" ]; then
        size=$(du -h "$backup_file" | cut -f1)
        log "✓ Vault backup created: $backup_file ($size)"
        
        # Encrypt backup
        openssl enc -aes-256-cbc -in "$backup_file" -out "$backup_file.enc" -k "$(docker exec vault vault kv get -field=key secret/encryption/master-keys)"
        
        # Upload encrypted backup
        aws s3 cp "$backup_file.enc" "$REMOTE_BACKUP_BUCKET/vault/"
        
        # Remove local copy after upload
        rm "$backup_file"
    else
        log "✗ Vault backup failed"
        return 1
    fi
}

# Backup verification
verify_backups() {
    log "Verifying backup integrity..."
    
    # Check backup files exist and have content
    for backup in $BACKUP_DIR/*; do
        if [ -s "$backup" ]; then
            checksum=$(sha256sum "$backup" | awk '{print $1}')
            log "✓ Backup verified: $backup (SHA256: $checksum)"
        else
            log "✗ Backup invalid: $backup"
        fi
    done
}

# Generate backup report
generate_report() {
    log "Generating backup report..."
    
    report_file="/tmp/backup-report-$(date +%Y%m%d).html"
    
    {
        echo "<html><head><title>Backup Report</title></head><body>"
        echo "<h1>Backup Report - $(date)</h1>"
        echo "<table border='1'>"
        echo "<tr><th>Backup Name</th><th>Size</th><th>Date</th><th>Status</th></tr>"
        
        for backup in $BACKUP_DIR/*; do
            name=$(basename "$backup")
            size=$(du -h "$backup" | cut -f1)
            date=$(stat -c %y "$backup" | cut -d' ' -f1,2)
            status="OK"
            echo "<tr><td>$name</td><td>$size</td><td>$date</td><td>$status</td></tr>"
        done
        
        echo "</table>"
        echo "</body></html>"
    } > "$report_file"
    
    # Email report
    mail -s "Daily Backup Report" ops-team@example.com < "$report_file" || log "WARNING: Could not email report"
}

# Main execution
main() {
    log "=== Backup Manager Started ==="
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Execute backups
    backup_postgres || log "ERROR: PostgreSQL backup failed"
    backup_redis || log "ERROR: Redis backup failed"
    backup_vault || log "ERROR: Vault backup failed"
    
    # Verify and report
    verify_backups
    generate_report
    
    log "=== Backup Manager Complete ==="
}

main "$@"
BACKUP_MANAGER

    chmod +x "${DR_DIR}/backup-manager.sh"
    log_success "Automated backup scripts created"
}

################################################################################
# 3. POINT-IN-TIME RECOVERY (PITR) PROCEDURES
################################################################################

create_pitr_procedures() {
    log_info "Creating point-in-time recovery procedures..."

    cat > "${DR_DIR}/pitr-recovery.sh" << 'PITR_RECOVERY'
#!/bin/bash

# Point-in-Time Recovery (PITR) Procedures
# Restores database to a specific point in time

set -euo pipefail

LOG_FILE="/var/log/pitr-recovery.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Recover to specific point in time
recover_to_point_in_time() {
    local target_time="$1"  # Format: 2026-05-02 10:30:00
    
    log "Starting PITR recovery to: $target_time"
    
    # Find base backup closest to target time
    base_backup=$(find /data/backups -name "postgres-*.sql.gz" -newermt "$target_time" | sort | head -1)
    
    if [ -z "$base_backup" ]; then
        log "ERROR: No suitable base backup found"
        return 1
    fi
    
    log "Using base backup: $base_backup"
    
    # Stop write operations
    log "Stopping write operations..."
    docker exec code-server-postgres psql -U postgres -c "SELECT pg_wal_replay_pause();" || true
    
    # Restore base backup to temporary database
    log "Restoring base backup to temporary database..."
    temp_db="postgres_recovery_$(date +%s)"
    docker exec code-server-postgres createdb -U postgres "$temp_db"
    docker exec code-server-postgres psql -U postgres "$temp_db" < <(gunzip -c "$base_backup")
    
    # Apply WAL files up to target time
    log "Applying WAL files up to $target_time..."
    for wal_file in $(find /data/backups/postgres/wal -type f -newermt "$target_time"); do
        docker exec code-server-postgres psql -U postgres "$temp_db" < "$wal_file" || log "WARNING: Could not apply WAL $wal_file"
    done
    
    # Verify recovered database
    log "Verifying recovered database..."
    row_count=$(docker exec code-server-postgres psql -U postgres "$temp_db" -c "SELECT COUNT(*) FROM information_schema.tables;" | grep -o '[0-9]*' | tail -1)
    log "Recovered database has $row_count tables"
    
    # Optionally swap databases
    log "To activate recovered database, run:"
    log "docker exec code-server-postgres psql -U postgres -c 'ALTER DATABASE postgres RENAME TO postgres_old;'"
    log "docker exec code-server-postgres psql -U postgres -c 'ALTER DATABASE $temp_db RENAME TO postgres;'"
    
    log "PITR recovery complete. Verify data before activating."
}

# Restore specific table
restore_table() {
    local table_name="$1"
    local target_time="$2"
    
    log "Restoring table $table_name to $target_time..."
    
    # Create temporary restore point
    temp_restore="restore_${table_name}_$(date +%s)"
    
    # Backup current table
    docker exec code-server-postgres pg_dump -U postgres -t "$table_name" > "/tmp/${table_name}_current.sql"
    
    # Restore from backup containing the table
    base_backup=$(find /data/backups -name "postgres-*.sql.gz" -newermt "$target_time" | sort | head -1)
    
    # Extract table from backup
    gunzip -c "$base_backup" | grep -A 1000 "CREATE TABLE.*$table_name" | grep -B 1000 "^--" | head -n -2 > "/tmp/${table_name}_restore.sql"
    
    # Create restore schema
    docker exec code-server-postgres psql -U postgres -c "CREATE SCHEMA $temp_restore;"
    docker exec code-server-postgres psql -U postgres -c "SET search_path TO $temp_restore;" < "/tmp/${table_name}_restore.sql"
    
    log "Table restored to schema $temp_restore. Verify before merging."
}

# Main execution
if [ $# -lt 1 ]; then
    echo "Usage: $0 <point-in-time> [table-name]"
    echo "Example: $0 '2026-05-02 10:30:00'"
    echo "Example: $0 '2026-05-02 10:30:00' users"
    exit 1
fi

recover_to_point_in_time "$1"
PITR_RECOVERY

    chmod +x "${DR_DIR}/pitr-recovery.sh"
    log_success "Point-in-time recovery procedures created"
}

################################################################################
# 4. DISASTER RECOVERY RUNBOOK
################################################################################

create_dr_runbook() {
    log_info "Creating disaster recovery runbook..."

    cat > "${DR_DIR}/disaster-recovery-runbook.md" << 'DR_RUNBOOK'
# Disaster Recovery Runbook

## Overview

This document defines procedures for recovering from various disaster scenarios.

## Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)

- **RTO (Recovery Time Objective):** 4 hours maximum downtime
- **RPO (Recovery Point Objective):** 1 hour maximum data loss

## Disaster Scenarios

### Scenario 1: Single Service Failure

**Symptoms:**
- One service (e.g., control-plane) is down
- Error rates in metrics dashboard spike
- Dependent services show connection errors

**Recovery Steps:**

1. Identify failed service:
   ```bash
   docker ps | grep code-server
   # Look for services not in "Up" state
   ```

2. Check service logs:
   ```bash
   docker logs code-server-control-plane
   # Look for error messages
   ```

3. Restart service:
   ```bash
   docker restart code-server-control-plane
   docker ps | grep code-server-control-plane
   # Verify service is running
   ```

4. Verify health:
   ```bash
   curl http://code-server-control-plane:8000/health
   ```

**Estimated Recovery Time:** 5 minutes

### Scenario 2: Database Failure

**Symptoms:**
- PostgreSQL connection timeout errors
- Activity feed and other data-dependent services failing
- Error rate > 50%

**Recovery Steps:**

1. Check database status:
   ```bash
   docker ps | grep postgres
   docker logs code-server-postgres
   ```

2. Check replica status:
   ```bash
   redis-cli -h 192.168.168.42 INFO replication
   # Verify replica is healthy
   ```

3. If master is down, promote replica:
   ```bash
   # On replica host:
   docker exec code-server-sentinel SENTINEL failover mymaster
   ```

4. Restore from backup if data is corrupted:
   ```bash
   bash /path/to/pitr-recovery.sh "2026-05-02 10:30:00"
   ```

**Estimated Recovery Time:** 30 minutes

### Scenario 3: Cache (Redis) Failure

**Symptoms:**
- Cache hit rate drops to 0%
- Response times increase 10x
- Memory-intensive operations timeout

**Recovery Steps:**

1. Check Redis status:
   ```bash
   redis-cli ping
   redis-cli INFO
   ```

2. Check Sentinel:
   ```bash
   redis-cli -p 26379 SENTINEL masters
   ```

3. If master is down, Sentinel will auto-failover:
   ```bash
   # Wait for failover to complete (< 10 seconds)
   redis-cli -p 26379 SENTINEL masters
   # Verify new master is promoted
   ```

4. Clear cache if corrupted:
   ```bash
   redis-cli FLUSHDB
   # Services will repopulate cache
   ```

**Estimated Recovery Time:** 15 seconds (auto) + 5 minutes (repopulation)

### Scenario 4: Storage Failure

**Symptoms:**
- MinIO connection errors
- File upload/download failures
- S3-compatible API returning errors

**Recovery Steps:**

1. Check MinIO status:
   ```bash
   docker ps | grep minio
   docker logs code-server-minio
   ```

2. Check disk space:
   ```bash
   docker exec code-server-minio df -h
   ```

3. Check replication status:
   ```bash
   docker exec code-server-minio mc ls -r replica/
   ```

4. Restore from backup if data is lost:
   ```bash
   aws s3 sync s3://code-server-backups/minio/ /data/minio-restore/
   docker cp /data/minio-restore/. code-server-minio:/data/
   docker restart code-server-minio
   ```

**Estimated Recovery Time:** 30 minutes

### Scenario 5: Full Primary Datacenter Failure

**Symptoms:**
- All services on primary (192.168.168.31) are down
- Network connectivity to primary is lost
- Monitoring shows complete primary failure

**Recovery Steps:**

1. **Verify primary failure (not just network issue):**
   ```bash
   # Try multiple connection methods
   ping 192.168.168.31
   ssh -T 192.168.168.31
   # If all fail, primary is down
   ```

2. **Promote replica to primary:**
   ```bash
   # On replica host (192.168.168.42):
   
   # Promote Redis replica
   redis-cli -p 26379 SENTINEL failover mymaster
   
   # Verify replication is now primary
   redis-cli INFO replication | grep role
   
   # Promote PostgreSQL replica
   docker exec code-server-postgres psql -U postgres -c "SELECT pg_promote();"
   ```

3. **Update DNS records:**
   ```bash
   # Point DNS to replica (192.168.168.42)
   aws route53 change-resource-record-sets \
       --hosted-zone-id Z123 \
       --change-batch file:///tmp/dns-change.json
   ```

4. **Verify all services are operational:**
   ```bash
   # Check all services are running
   docker ps | grep code-server | wc -l
   # Should see 45 services
   
   # Check connectivity
   curl -I https://code-server.local/
   ```

5. **Begin restoration of primary:**
   ```bash
   # Once replica is verified stable
   
   # Power on primary
   # Bring up services in correct order
   ./scripts/deploy-enterprise-idempotent.sh
   
   # Resync data from replica
   # Wait for replication to catch up
   ```

6. **Restore write operations to new configuration:**
   ```bash
   # Update connection strings if primary host changed
   # Update Vault with new master addresses
   ```

**Estimated Recovery Time:** 2-4 hours

### Scenario 6: Secrets/Credentials Compromise

**Symptoms:**
- Unusual API calls from unknown IPs
- Unauthorized access attempts in audit logs
- Security alert on compromised credentials

**Recovery Steps:**

1. **Immediately revoke compromised credentials:**
   ```bash
   docker exec vault vault lease revoke -prefix auth/approle/
   docker exec vault vault lease revoke -prefix secret/
   ```

2. **Rotate all secrets:**
   ```bash
   bash /path/to/tls/secrets-rotation.sh
   ```

3. **Update Vault policies to prevent reuse:**
   ```bash
   docker exec vault vault policy delete compromised-role
   ```

4. **Force service re-authentication:**
   ```bash
   docker service update --force code-server-control-plane
   docker service update --force code-server-agent-runtime
   # All services
   ```

5. **Review audit logs for unauthorized access:**
   ```bash
   curl -s 'http://loki:3100/loki/api/v1/query_range?query=audit_unauthorized' | jq
   ```

6. **Implement additional monitoring:**
   ```bash
   # Add alert for future attempts with same pattern
   ```

**Estimated Recovery Time:** 15 minutes

## Backup and Recovery Verification

### Monthly DR Drill

Every month, perform the following:

1. Restore database to point-in-time (previous day)
2. Verify data integrity in restored database
3. Run application integration tests
4. Document any issues and update procedures
5. Destroy test environment

### Backup Restoration Test

```bash
# Test PostgreSQL restore
bash /path/to/pitr-recovery.sh "$(date -d '1 hour ago' '+%Y-%m-%d %H:%M:%S')"

# Verify restored data
docker exec postgres_recovery_* psql -U postgres -c "SELECT COUNT(*) FROM users;"

# Compare with production
docker exec code-server-postgres psql -U postgres -c "SELECT COUNT(*) FROM users;"
```

## Communication During Disaster

1. **Within 5 minutes of detection:** Alert on-call team
2. **Within 15 minutes:** Update status page: "Investigating issue"
3. **Within 30 minutes:** Provide ETA for recovery
4. **Every 30 minutes:** Update status page with progress
5. **Upon recovery:** Update status page: "Issue resolved"
6. **Next business day:** Post-mortem analysis

## Prevention and Hardening

### Automated Recovery

- Sentinel auto-failover for Redis
- Replica promotion for PostgreSQL
- Service health checks with restart
- Automated backup verification

### Monitoring

- Real-time alerting for all critical services
- Capacity monitoring to prevent resource exhaustion
- Security monitoring for access anomalies
- Performance monitoring for degradation

### Testing

- Weekly failover testing
- Monthly PITR verification
- Quarterly full DR drill
- Annual security audit

## Contact Information

- **On-Call Team:** ops-team@example.com
- **Security:** security@example.com
- **DBA:** dba-team@example.com
- **SRE Lead:** sre-lead@example.com

DR_RUNBOOK

    log_success "Disaster recovery runbook created"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "Phase 7.2: Automated Backup & Disaster Recovery"
    log_info "=============================================="

    create_backup_policies
    create_backup_scripts
    create_pitr_procedures
    create_dr_runbook

    if $APPLY; then
        log_success "Phase 7.2 Complete - Backup & DR Configured"
    else
        log_info "Configurations created at: $DR_DIR"
        log_info "Run with --apply flag to deploy"
    fi
}

main "$@"
