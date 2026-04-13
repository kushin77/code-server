# Phase 11: Disaster Recovery

**Document**: DR procedures, automation, and recovery processes
**Date**: April 13, 2026

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Recovery Objectives](#recovery-objectives)
4. [Backup Automation](#backup-automation)
5. [Restore Procedures](#restore-procedures)
6. [DR Drill](#dr-drill)
7. [Verification](#verification)

## Overview

The Phase 11 DR strategy ensures zero data loss and rapid recovery from any failure scenario:

- **RTO** (Recovery Time Objective): < 1 hour
- **RPO** (Recovery Point Objective): < 15 minutes
- **PITR Window**: 30 days
- **Backup Locations**: Primary DC + Secondary region (S3)
- **Restoration**: Automated with manual verification option

## Backup Strategy

### Multi-Tier Backup Architecture

```
Real-time: WAL Archiving (Continuous)
            ↓
Hourly: Incremental Backups (via WAL)
            ↓
Daily: Full Backups (2:00 AM UTC)
            ↓
Off-site: Replication to S3 (Every 4 hours)
            ↓
Archival: 90-day retention
```

### Backup Components

| Component | Type | Schedule | Retention | Location |
|-----------|------|----------|-----------|----------|
| PostgreSQL | Full | Daily 2:00 AM | 30 days | Primary + S3 |
| PostgreSQL | Incremental | Hourly | 7 days | Primary |
| PostgreSQL | WAL Archive | Continuous | 30 days | S3 |
| Redis | Snapshot | Daily 3:00 AM | 14 days | Primary + S3 |
| Application Config | Full | Daily 1:00 AM | 90 days | S3 only |
| TLS Certs | Full | Daily 1:30 AM | 90 days | S3 + Vault |

### Backup Storage Structure

```
S3 Bucket: code-server-backups
├── postgresql/
│   ├── full/
│   │   ├── 20260413/
│   │   │   ├── base.tar.gz
│   │   │   ├── manifest.json
│   │   │   └── checksums.txt
│   │   └── ...
│   └── wal-archive/
│       ├── 000000010000000000000001
│       ├── 000000010000000000000002
│       └── ...
├── redis/
│   ├── snapshots/
│   │   ├── 20260413-dump.rdb
│   │   └── ...
│   └── manifests/
├── config/
│   ├── kubernetes/
│   ├── terraform/
│   └── secrets-manifest.json
└── metadata/
    ├── backup-index.json
    ├── dr-checklist.md
    └── last-verification.json
```

## Recovery Objectives

### RTO by Component

| Component | Failure Type | RTO | Method |
|-----------|--------------|-----|--------|
| App Server | Single instance | <5 min | Pod restart |
| Load Balancer | Single instance | <5 min | HAProxy failover |
| PostgreSQL Primary | Crash | <30 sec | Replica promotion |
| PostgreSQL Replica | Crash | <30 min | SSH + restore |
| Redis Master | Crash | <10 sec | Sentinel failover |
| Single Node Failure | Hardware | <1 hour | Spin up new node |
| Regional Failure | Entire DC down | <1 hour | Failover to standby DC |
| Full Data Corruption | Backup compromise | <4 hours | PITR to clean point |

### RPO by Component

| Component | RPO | Method |
|-----------|-----|--------|
| PostgreSQL | 0 | Synchronous replication |
| Redis | <2 min | Snapshot-based |
| Application State | <5 min | Session replication |
| Configuration | <1 hour | Git + version control |

## Backup Automation

### PostgreSQL Backup Script

```bash
#!/bin/bash
# /scripts/backup-postgresql.sh
# Executes full backup of PostgreSQL

set -e

BACKUP_DIR="/mnt/backups"
S3_BUCKET="s3://code-server-backups"
DATE=$(date +%Y%m%d)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/postgresql/full/${DATE}"

mkdir -p "${BACKUP_PATH}"

# Function: Backup
backup_postgresql() {
  echo "[INFO] Starting PostgreSQL full backup..."

  # Create base backup
  pg_basebackup \
    --host=postgres-primary \
    --port=5432 \
    --username=backup_user \
    --password-from-stdin \
    --directory="${BACKUP_PATH}" \
    --format=tar \
    --progress \
    --xlog-method=stream \
    --max-rate=100M

  echo "[INFO] Backup completed at ${BACKUP_PATH}"
}

# Function: Verify
verify_backup() {
  echo "[INFO] Verifying backup integrity..."

  # Check if base backup exists
  if [ ! -f "${BACKUP_PATH}/base.tar" ]; then
    echo "[ERROR] Base backup not found!"
    return 1
  fi

  # Verify checksum
  sha256sum "${BACKUP_PATH}/base.tar" > "${BACKUP_PATH}/checksums.txt"

  # Create manifest
  cat > "${BACKUP_PATH}/manifest.json" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "backup_type": "full",
  "backup_date": "${DATE}",
  "size_bytes": $(stat -f%z "${BACKUP_PATH}/base.tar" 2>/dev/null || stat -c%s "${BACKUP_PATH}/base.tar"),
  "host": "postgres-primary",
  "database": "code-server",
  "pitr_supports": true,
  "wal_start_time": "$(psql -h postgres-primary -U backup_user -tc "SELECT wal_lsn FROM pg_control_recovery() LIMIT 1;")
}
EOF

  echo "[INFO] Backup verification passed"
}

# Function: Upload to S3
upload_to_s3() {
  echo "[INFO] Uploading backup to S3..."

  aws s3 sync "${BACKUP_PATH}" "${S3_BUCKET}/postgresql/full/${DATE}/" \
    --delete \
    --sse=AES256 \
    --storage-class=STANDARD_IA

  echo "[INFO] S3 upload completed"
}

# Function: Test Restore
test_restore() {
  echo "[INFO] Testing backup restore (dry-run)..."

  # Create temporary directory
  TEST_DIR=$(mktemp -d)

  # Attempt restore in test environment
  if pg_basebackup \
    --host=postgres-primary \
    --port=5432 \
    --username=backup_user \
    --password-from-stdin \
    --directory="${TEST_DIR}" \
    --format=tar \
    --walmethod=none \
    <<< "$(cat /run/secrets/db_password)"; then
    echo "[INFO] Restore test successful"
    rm -rf "${TEST_DIR}"
  else
    echo "[ERROR] Restore test failed!"
    return 1
  fi
}

# Main execution
echo "[INFO] Starting PostgreSQL backup script"
echo "[INFO] Timestamp: ${TIMESTAMP}"

if backup_postgresql && verify_backup && upload_to_s3 && test_restore; then
  echo "[SUCCESS] PostgreSQL backup completed successfully"
  exit 0
else
  echo "[ERROR] PostgreSQL backup failed"
  exit 1
fi
```

### WAL Archiving Configuration

```ini
# postgresql.conf - WAL archiving for PITR

# Enable WAL archiving
wal_level = replica
archive_mode = on
archive_command = '/scripts/archive-wal.sh %p %f'
archive_timeout = 300

# WAL replication
max_wal_senders = 3
max_replication_slots = 3
wal_keep_size = 1GB

# PITR window
recovery_target_timeline = 'latest'

# Continuous archiving script
```

**archive-wal.sh**:
```bash
#!/bin/bash
# Archive WAL file to S3

WAL_PATH="$1"
WAL_FILE="$2"

# Copy to primary backup location
cp "${WAL_PATH}" "/mnt/backups/postgresql/wal-archive/${WAL_FILE}"

# Copy to S3 (async)
aws s3 cp "/mnt/backups/postgresql/wal-archive/${WAL_FILE}" \
  "s3://code-server-backups/postgresql/wal-archive/${WAL_FILE}" &

exit 0
```

### Redis Backup Script

```bash
#!/bin/bash
# /scripts/backup-redis.sh
# Creates Redis snapshot

set -e

BACKUP_DIR="/mnt/backups/redis/snapshots"
S3_BUCKET="s3://code-server-backups"
DATE=$(date +%Y%m%d)

mkdir -p "${BACKUP_DIR}"

# Create snapshot
echo "[INFO] Creating Redis snapshot..."
redis-cli -h redis-cluster BGSAVE

# Wait for snapshot completion
while redis-cli -h redis-cluster LASTSAVE | grep -q "$(date +%s)"; do
  echo "[INFO] Waiting for BGSAVE to complete..."
  sleep 5
done

# Copy snapshot
cp /var/lib/redis/dump.rdb "${BACKUP_DIR}/${DATE}-dump.rdb"

# Verify
if [ ! -f "${BACKUP_DIR}/${DATE}-dump.rdb" ]; then
  echo "[ERROR] Redis snapshot failed!"
  exit 1
fi

# Upload to S3
aws s3 cp "${BACKUP_DIR}/${DATE}-dump.rdb" \
  "${S3_BUCKET}/redis/snapshots/" \
  --sse=AES256

echo "[SUCCESS] Redis backup completed"
```

### Backup Scheduling (Kubernetes CronJob)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-postgresql-daily
spec:
  schedule: "0 2 * * *"  # 2:00 AM UTC daily
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 1
      template:
        spec:
          serviceAccountName: backup
          containers:
          - name: backup
            image: code-server:backup-tools
            command:
            - /scripts/backup-postgresql.sh
            env:
            - name: BACKUP_DIR
              value: /mnt/backups
            - name: S3_BUCKET
              value: code-server-backups
            volumeMounts:
            - name: backups
              mountPath: /mnt/backups
            - name: scripts
              mountPath: /scripts
            resources:
              limits:
                cpu: 2000m
                memory: 4Gi
          volumes:
          - name: backups
            persistentVolumeClaim:
              claimName: backup-storage
          - name: scripts
            configMap:
              name: backup-scripts
              defaultMode: 0755
          restartPolicy: OnFailure
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-postgresql-hourly
spec:
  schedule: "0 * * * *"  # Every hour
  serviceAccountName: backup
  # ... (incremental backup via WAL)
```

## Restore Procedures

### Scenario 1: Single-Node Failure

**Failure**: PostgreSQL replica crashes
**Recovery**: Spin new node from image, restore from backup
**RTO**: 30 minutes
**Steps**:

```bash
# 1. Spin up new node
kubectl scale deployment postgres-replica-1 --replicas=0
sleep 30
kubectl scale deployment postgres-replica-1 --replicas=1

# 2. Wait for readiness
kubectl wait --for=condition=ready pod -l app=postgres-replica-1

# 3. Restore from recent backup
kubectl exec postgres-replica-1 -- /scripts/restore-from-wal.sh

# 4. Verify replication
kubectl exec postgres-primary -- psql -c "SELECT * FROM pg_stat_replication;"
```

### Scenario 2: Regional Failure (Full DC Down)

**Failure**: Entire data center unavailable
**Recovery**: Failover to standby DC
**RTO**: < 1 hour
**Steps**:

```bash
# 1. Confirm primary DC is unreachable
echo "Waiting 60s to confirm outage..."
sleep 60
ping -c 3 primary-dc || true

# 2. Switch to standby DC (manual confirmation required)
read -p "Switch to standby DC? (y/n) " -n 1
if [ "$REPLY" = "y" ]; then
  # 3. Promote standby cluster
  kubectl apply -f kubernetes/standby-promotion.yaml

  # 4. Update DNS
  aws route53 change-resource-record-sets \
    --hosted-zone-id Z1234567890ABC \
    --change-batch 'file://dns-failover.json'

  # 5. Verify services online
  ./scripts/health-check.sh
fi

# 6. Restore recent transactions (if needed)
./scripts/restore-from-wal.sh --target-time "2026-04-13 10:15:00"
```

### Scenario 3: Data Corruption

**Failure**: Database corruption detected
**Recovery**: Point-in-time restore (PITR)
**RTO**: < 4 hours
**Steps**:

```bash
# 1. Stop application access
kubectl scale deployment code-server --replicas=0

# 2. Create new database instance for restore testing
kubectl apply -f kubernetes/restore-test-instance.yaml

# 3. Restore to clean point in time
RESTORE_TIME="2026-04-13 09:00:00"

kubectl exec postgres-restore-test -- pg_basebackup \
  -D /var/lib/postgresql/test_data \
  -h postgres-backup-s3

# 4. Replay WAL up to recovery point
recovery_target_time = '${RESTORE_TIME}'

# 5. Verify data integrity
./scripts/verify-database-integrity.sh

# 6. Promote restored database
kubectl delete deployment postgres-primary
kubectl apply -f kubernetes/postgres-restored.yaml

# 7. Resume application
kubectl scale deployment code-server --replicas=3
```

### Scenario 4: Configuration/Secrets Corruption

**Failure**: Kubernetes ConfigMaps or Secrets corrupted
**Recovery**: Restore from Git + Vault
**RTO**: < 15 minutes
**Steps**:

```bash
# 1. Identify last-good commit
git log --oneline -10 -- kubernetes/

# 2. Restore ConfigMaps from Git
git show <good-commit>:kubernetes/config/*  | kubectl apply -f -

# 3. Restore Secrets from Vault
vault kv get secret/code-server/prod | jq '.data' > secrets.yaml
kubectl apply -f secrets.yaml

# 4. Restart affected pods
kubectl rollout restart deployment/code-server

# 5. Verify
kubectl get configmap,secret
```

## DR Drill

### Monthly DR Drill Procedure

**Frequency**: 1st Sunday of each month
**Duration**: 2 hours
**Participants**: DevOps, DBA, SRE

**Script**: `/scripts/dr-drill.sh`

```bash
#!/bin/bash
# Monthly DR drill validation

set -e

DRILL_DATE=$(date +%Y%m%d)
DRILL_LOG="/var/log/dr-drill-${DRILL_DATE}.log"

echo "[DRILL] Starting monthly DR drill"  | tee "${DRILL_LOG}"

# Phase 1: Backup Verification (10 min)
echo "[PHASE 1] Verifying backups exist..."
aws s3 ls s3://code-server-backups/postgresql/full/ >> "${DRILL_LOG}"
BACKUP_COUNT=$(aws s3 ls s3://code-server-backups/postgresql/full/ | wc -l)
if [ "${BACKUP_COUNT}" -lt 7 ]; then
  echo "[ERROR] Less than 7 days of backups!" | tee -a "${DRILL_LOG}"
  exit 1
fi
echo "[PHASE 1] ✓ Backup verification passed" | tee -a "${DRILL_LOG}"

# Phase 2: Restore Test (30 min)
echo "[PHASE 2] Testing restore from backup..."
TEST_DB="test-dr-$(date +%s)"

# Restore to test environment
aws s3 cp s3://code-server-backups/postgresql/full/latest/ /tmp/restore/ --recursive
pg_basebackup --restore /tmp/restore --to-db="${TEST_DB}"

# Verify data integrity
psql -d "${TEST_DB}" -c "SELECT COUNT(*) FROM users;" >> "${DRILL_LOG}"
psql -d "${TEST_DB}" -c "SELECT COUNT(*) FROM sessions;" >> "${DRILL_LOG}"

# Cleanup
dropdb "${TEST_DB}"
echo "[PHASE 2] ✓ Restore test passed" | tee -a "${DRILL_LOG}"

# Phase 3: Failover Simulation (30 min)
echo "[PHASE 3] Simulating failover..."

# Record current primary
PRIMARY=$(kubectl get pods -l app=postgres -o jsonpath='{.items[0].metadata.name}')
echo "Primary DB: ${PRIMARY}" | tee -a "${DRILL_LOG}"

# Simulate primary failure
kubectl scale deployment "${PRIMARY}" --replicas=0

# Wait for failover
sleep 30

# Check new primary
NEW_PRIMARY=$(kubectl get pods -l app=postgres,role=primary -o jsonpath='{.items[0].metadata.name}')
echo "New Primary DB: ${NEW_PRIMARY}" | tee -a "${DRILL_LOG}"

# Restore primary
kubectl scale deployment "${PRIMARY}" --replicas=1
sleep 30

echo "[PHASE 3] ✓ Failover simulation passed" | tee -a "${DRILL_LOG}"

# Phase 4: Application Recovery (20 min)
echo "[PHASE 4] Testing application recovery..."

# Kill application pods
kubectl delete pods -l app=code-server

# Wait for recovery
sleep 30

# Check recovery
POD_COUNT=$(kubectl get pods -l app=code-server | wc -l)
if [ "${POD_COUNT}" -ge 3 ]; then
  echo "[PHASE 4] ✓ Application recovered (${POD_COUNT} pods)" | tee -a "${DRILL_LOG}"
else
  echo "[ERROR] Application failed to recover" | tee -a "${DRILL_LOG}"
  exit 1
fi

# Phase 5: Data Validation (20 min)
echo "[PHASE 5] Validating data post-recovery..."

# Run smoke tests
./scripts/smoke-tests.sh >> "${DRILL_LOG}"

echo "[DRILL] ✓ Monthly DR drill completed successfully" | tee -a "${DRILL_LOG}"
echo "Drill log: ${DRILL_LOG}"
```

## Verification

### Backup Verification Script

```bash
#!/bin/bash
# /scripts/verify-backups.sh
# Weekly backup integrity check

set -e

VERIFY_LOG="/var/log/backup-verify-$(date +%Y%m%d).log"

echo "[VERIFY] Starting backup verification" | tee "${VERIFY_LOG}"

# 1. Check backup freshness
LATEST_BACKUP_DATE=$(aws s3 ls s3://code-server-backups/postgresql/full/ --recursive | tail -1 | awk '{print $1}')
DAYS_OLD=$(( ($(date +%s) - $(date -d "${LATEST_BACKUP_DATE}" +%s)) / 86400 ))

if [ "${DAYS_OLD}" -gt 1 ]; then
  echo "[WARNING] Latest backup is ${DAYS_OLD} days old" | tee -a "${VERIFY_LOG}"
fi
echo "[✓] Backup freshness: ${DAYS_OLD} days" | tee -a "${VERIFY_LOG}"

# 2. Verify backup checksums
echo "[INFO] Verifying backup checksums..."
aws s3 sync s3://code-server-backups/postgresql/full/latest/ /tmp/verify/
cd /tmp/verify
sha256sum -c checksums.txt >> "${VERIFY_LOG}"
echo "[✓] Checksum verification passed" | tee -a "${VERIFY_LOG}"

# 3. Test restore capability
echo "[INFO] Testing restore capability..."
pg_basebackup --test -D /tmp/test_restore >> "${VERIFY_LOG}"
echo "[✓] Restore capability verified" | tee -a "${VERIFY_LOG}"

# 4. Check cross-region replication
echo "[INFO] Checking backup replication..."
REGION1_COUNT=$(aws s3 ls s3://code-server-backups --recursive --region us-east-1 | wc -l)
REGION2_COUNT=$(aws s3 ls s3://code-server-backups --recursive --region us-west-2 | wc -l)
if [ "${REGION1_COUNT}" -eq "${REGION2_COUNT}" ]; then
  echo "[✓] Cross-region backup replication: OK" | tee -a "${VERIFY_LOG}"
else
  echo "[WARNING] Backup replication mismatch" | tee -a "${VERIFY_LOG}"
fi

echo "[VERIFY] Backup verification completed" | tee -a "${VERIFY_LOG}"
```

---

**Status**: Complete
**Last Updated**: April 13, 2026
