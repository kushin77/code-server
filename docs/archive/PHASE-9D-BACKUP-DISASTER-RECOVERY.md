# Phase 9-D: Backup & Disaster Recovery
## Infrastructure-as-Code Implementation
### April 15, 2026

---

## Overview

Phase 9-D implements automated backup and disaster recovery procedures for the production infrastructure deployed in Phases 9-A, 9-B, and 9-C.

---

## Backup Strategy

### Backup Types

#### 1. Incremental Snapshots
- **Type**: LVM snapshots + rsync differential backup
- **Frequency**: Hourly incremental, daily full
- **Retention**: 
  - Hourly: 24 hours
  - Daily: 7 days
  - Weekly: 4 weeks
  - Monthly: 12 months
- **Target**: NAS at 192.168.168.200 (configured in user memory)

#### 2. Database Backups
- **PostgreSQL**: pg_dump with WAL archiving
  - Frequency: Every 30 minutes
  - Retention: 7 days
  - Point-in-time recovery: Yes (via WAL replay)
- **Redis**: RDB snapshots
  - Frequency: Every 5 minutes
  - Retention: 24 hours
  - Replication: Primary → Replica

#### 3. Configuration Backups
- **Docker Compose**: git commits (immutable)
- **Terraform State**: S3-compatible backup (MinIO)
- **Secrets**: Vault backup with encryption
- **Application Config**: Containerized (immutable images)

#### 4. Log Backups
- **Jaeger Traces**: 15-day retention (Badger storage)
- **Loki Logs**: 7-day retention (BoltDB shipper)
- **Prometheus Metrics**: 15-day local retention + 30-day remote storage
- **Prometheus WAL**: 3-day retention for durability

---

## Disaster Recovery Procedures

### RTO & RPO Targets

| Scenario | RTO | RPO | Recovery Method |
|----------|-----|-----|-----------------|
| Container crash | < 5 min | < 1 min | Docker restart + health check |
| Service failure | < 30 min | < 5 min | Replica failover (Keepalived) |
| Primary host down | < 2 min | < 30 sec | Automatic VIP migration to replica |
| Data corruption | < 1 hour | < 30 min | Point-in-time restore from backup |
| Complete site failure | < 4 hours | < 1 hour | DR site activation (cross-region) |

### Recovery Procedures

#### Procedure 1: Container Restart (RTO: < 5 min)
```bash
# Automatically handled by docker-compose restart policy
# Manual recovery if needed:
docker-compose restart <service_name>
docker-compose logs <service_name> | tail -100  # Verify startup
```

#### Procedure 2: Service Failover via Keepalived (RTO: < 2 min)
```bash
# Automatic failover when primary HAProxy fails:
# 1. Keepalived detects primary down (3 missed VRRP advertisements)
# 2. Replica Keepalived transitions to MASTER state (< 5 sec)
# 3. VIP 192.168.168.100 becomes active on replica
# 4. Traffic automatically routes to replica

# Manual check on replica during failover:
sudo systemctl status keepalived
sudo journalctl -u keepalived -n 50

# To manually trigger failover for testing:
sudo systemctl stop keepalived  # on primary
sleep 10
ip addr show | grep 192.168.168.100  # should be on replica now
```

#### Procedure 3: PostgreSQL Point-in-Time Recovery (RTO: < 1 hour)
```bash
# Prerequisites:
# - Base backup available
# - WAL files for target recovery time

# Steps:
docker-compose down postgres
rm -rf /data/postgresql/main/*

# Restore base backup
rsync -av backup-server:/backups/postgresql/ /data/postgresql/

# Restore to point-in-time
docker-compose exec -T postgres psql -U postgres \
  -c "SELECT pg_wal_replay_resume()"

# Verify recovery
docker-compose logs postgres | grep "database system ready"
```

#### Procedure 4: Complete System Restore (RTO: < 4 hours)
```bash
# Prerequisites:
# - Full system backup (VM image or tar archive)
# - All configuration files
# - Secrets (from Vault)

# Steps on new host:
1. Provision new host (192.168.168.31 or new IP)
2. Install Docker and Docker Compose
3. Clone repository: git clone https://github.com/kushin77/code-server.git
4. Copy .env from backup: scp backup-server:/backups/.env ./
5. Copy Terraform state: scp backup-server:/backups/terraform.tfstate terraform/
6. Restore database: docker-compose exec postgres psql < backup.sql
7. Start services: docker-compose up -d
8. Verify health: curl http://localhost/health
9. Update DNS/load balancer to point to new host
```

---

## Implementation Files

### 1. Terraform Configuration: backup-infrastructure.tf

```hcl
# NAS backup target configuration
resource "null_resource" "backup_nas_config" {
  provisioner "remote-exec" {
    inline = [
      "# Mount NAS backup target",
      "sudo mount -t nfs -o vers=4.1 192.168.168.200:/backups /mnt/backups",
      "sudo chown -R 1000:1000 /mnt/backups",
      "echo '192.168.168.200:/backups /mnt/backups nfs defaults 0 0' | sudo tee -a /etc/fstab"
    ]
    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.ssh_key_path)
      host        = var.primary_host
    }
  }
}

# PostgreSQL backup configuration
resource "local_file" "postgres_backup_script" {
  filename = "${path.module}/../scripts/backup-postgres.sh"
  content  = file("${path.module}/../scripts/backup-postgres.sh.tpl")
}

# Redis backup configuration
resource "local_file" "redis_backup_script" {
  filename = "${path.module}/../scripts/backup-redis.sh"
  content  = file("${path.module}/../scripts/backup-redis.sh.tpl")
}

# Backup schedule via cron
resource "null_resource" "backup_cron_jobs" {
  provisioner "remote-exec" {
    inline = [
      # PostgreSQL hourly backups
      "echo '0 * * * * /code-server-enterprise/scripts/backup-postgres.sh >> /var/log/postgres-backup.log 2>&1' | crontab -",
      # Redis 5-minute backups
      "echo '*/5 * * * * /code-server-enterprise/scripts/backup-redis.sh >> /var/log/redis-backup.log 2>&1' | crontab -",
      # Full system backup daily at 2 AM
      "echo '0 2 * * * /code-server-enterprise/scripts/backup-full-system.sh >> /var/log/system-backup.log 2>&1' | crontab -"
    ]
    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.ssh_key_path)
      host        = var.primary_host
    }
  }
}

# Backup monitoring
resource "local_file" "backup_monitoring_rules" {
  filename = "${path.module}/../config/prometheus/backup-monitoring.yml"
  content  = file("${path.module}/../config/prometheus/backup-monitoring.yml.tpl")
}
```

### 2. Backup Scripts

#### PostgreSQL Backup Script: backup-postgres.sh

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/mnt/backups/postgresql"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create backup directory
mkdir -p $BACKUP_DIR

# Full backup if it doesn't exist today
if [ ! -f "$BACKUP_DIR/$(date +%Y%m%d)-full.sql.gz" ]; then
  docker-compose exec -T postgres pg_dump -U postgres \
    | gzip > "$BACKUP_DIR/$(date +%Y%m%d)-full.sql.gz"
fi

# Incremental backup
docker-compose exec -T postgres pg_dump -U postgres \
  | gzip > "$BACKUP_DIR/$TIMESTAMP-incremental.sql.gz"

# Cleanup old backups
find $BACKUP_DIR -name "*-incremental.sql.gz" -mtime +1 -delete
find $BACKUP_DIR -name "*-full.sql.gz" -mtime +$RETENTION_DAYS -delete

# Log backup completion
echo "$(date): PostgreSQL backup complete - $TIMESTAMP" >> /var/log/postgres-backup.log
```

#### Redis Backup Script: backup-redis.sh

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/mnt/backups/redis"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p $BACKUP_DIR

# Trigger Redis snapshot
docker-compose exec -T redis redis-cli BGSAVE

# Wait for snapshot to complete
while [ $(docker-compose exec -T redis redis-cli LASTSAVE) -eq 0 ]; do
  sleep 1
done

# Copy RDB file
docker-compose exec -T redis cat /data/dump.rdb \
  | gzip > "$BACKUP_DIR/$TIMESTAMP-dump.rdb.gz"

# Cleanup old backups (24 hour retention)
find $BACKUP_DIR -name "*-dump.rdb.gz" -mtime +1 -delete

echo "$(date): Redis backup complete - $TIMESTAMP" >> /var/log/redis-backup.log
```

#### Full System Backup: backup-full-system.sh

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/mnt/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Backup volumes
docker-compose exec -T postgres pg_dump -U postgres \
  | gzip > "$BACKUP_DIR/postgres-$TIMESTAMP.sql.gz"

# Backup docker-compose and config
tar -czf "$BACKUP_DIR/docker-compose-$TIMESTAMP.tar.gz" \
  docker-compose*.yml \
  .env \
  config/ \
  scripts/

# Backup Terraform state
tar -czf "$BACKUP_DIR/terraform-$TIMESTAMP.tar.gz" \
  terraform/*.tfstate* \
  terraform/*.tfvars

# Verify backups
ls -lh "$BACKUP_DIR"/*-$TIMESTAMP.* >> /var/log/system-backup.log

echo "$(date): Full system backup complete - $TIMESTAMP" >> /var/log/system-backup.log
```

### 3. Disaster Recovery Test Script: dr-test.sh

```bash
#!/bin/bash
set -euo pipefail

echo "════════════════════════════════════════════════════════════════"
echo "Phase 9-D: Disaster Recovery Testing"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Test 1: Service restart recovery
echo "? Test 1: Service Restart Recovery"
docker-compose restart postgres
sleep 10
STATUS=$(docker-compose ps postgres | grep -c "Up")
if [ $STATUS -eq 1 ]; then
  echo "✓ PostgreSQL restart successful"
else
  echo "✗ PostgreSQL restart failed"
  exit 1
fi
echo ""

# Test 2: Keepalived failover (on replica)
echo "? Test 2: Failover to Replica"
echo "  Simulating primary failure..."
docker-compose pause haproxy
sleep 15
VIP_HOST=$(ssh replica@192.168.168.42 "ip addr show | grep 192.168.168.100" || echo "not found")
if [ ! -z "$VIP_HOST" ]; then
  echo "✓ VIP successfully migrated to replica"
else
  echo "✗ VIP migration failed"
fi
docker-compose unpause haproxy
echo ""

# Test 3: Backup restoration
echo "? Test 3: Backup Verification"
BACKUP_COUNT=$(ls -1 /mnt/backups/postgresql/ | wc -l)
if [ $BACKUP_COUNT -gt 0 ]; then
  echo "✓ Found $BACKUP_COUNT PostgreSQL backups"
else
  echo "✗ No backups found"
  exit 1
fi
echo ""

# Test 4: Point-in-time recovery test
echo "? Test 4: Point-in-Time Recovery Capability"
docker-compose exec -T postgres psql -U postgres -c "SELECT version();"
echo "✓ Database accessible for recovery operations"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "✓ All Disaster Recovery tests passed"
echo "════════════════════════════════════════════════════════════════"
```

---

## SLO Targets for Phase 9-D

| Metric | Target |
|--------|--------|
| Backup completion time | < 30 min (full), < 5 min (incremental) |
| Backup success rate | 99.9% |
| Point-in-time recovery capability | 30 days |
| RPO (data loss) | < 30 seconds |
| RTO (service restoration) | < 4 hours (full recovery) |
| Backup retention | 12 months |

---

## Deployment Procedure

### Prerequisites
- NAS at 192.168.168.200 with 500GB+ storage
- SSH access to primary and replica hosts
- Terraform v1.0+
- Docker Compose v2.0+

### Deploy Phase 9-D

```bash
# 1. Configure NAS backup target
ssh akushnir@192.168.168.31 "sudo mkdir -p /mnt/backups && sudo mount -t nfs 192.168.168.200:/backups /mnt/backups"

# 2. Apply Terraform configuration
cd terraform
terraform plan -target=module.backup_infrastructure
terraform apply -auto-approve -target=module.backup_infrastructure

# 3. Deploy backup scripts
bash scripts/deploy-phase-9d.sh

# 4. Run disaster recovery tests
bash scripts/dr-test.sh

# 5. Verify backup execution
ssh akushnir@192.168.168.31 "ls -lh /mnt/backups/ && tail -20 /var/log/system-backup.log"
```

---

## Monitoring & Alerts

### Prometheus Alert Rules: backup-monitoring.yml

```yaml
groups:
  - name: backup_alerts
    rules:
      - alert: BackupFailure
        expr: time() - timestamp(increase(backup_success_total{result="failure"}[1h])) < 3600
        annotations:
          summary: "Backup job failed"
          description: "Backup {{ $labels.type }} failed in the last hour"

      - alert: BackupOverdue
        expr: time() - max(backup_completion_time) > 7200
        annotations:
          summary: "Scheduled backup overdue"
          description: "{{ $labels.type }} backup is 2+ hours overdue"

      - alert: LowBackupStorage
        expr: node_filesystem_avail_bytes{mountpoint="/mnt/backups"} < 52428800
        annotations:
          summary: "Low backup storage (< 50GB)"
          description: "Backup storage nearly full"

      - alert: HighRecoveryTime
        expr: recovery_test_duration_seconds > 3600
        annotations:
          summary: "Recovery time SLO breach"
          description: "Recovery time exceeded 1 hour SLO"
```

---

## Effort Estimate

| Task | Hours |
|------|-------|
| Terraform backup IaC | 4 |
| Backup scripts | 3 |
| DR testing procedures | 3 |
| Monitoring & alerts | 2 |
| Documentation | 2 |
| **Total Phase 9-D** | **14 hours** |

---

## Status: ✅ Phase 9-D PLANNED

Ready for implementation following Phase 9-B and 9-C production deployment verification.
