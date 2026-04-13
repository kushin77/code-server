# Storage & Data Management - On-Premises

## Storage Architecture

### PersistentVolume (PV) Planning

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgresql-pv
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain  # IMPORTANT: Don't delete data
  nfs:
    server: 192.168.1.100  # NAS IP
    path: /exports/postgresql
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: redis-pv
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  nfs:
    server: 192.168.1.100
    path: /exports/redis
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: backups-pv
spec:
  capacity:
    storage: 2Ti
  accessModes:
    - ReadWriteMany  # Multiple pods can access
  nfs:
    server: 192.168.1.100
    path: /exports/backups
```

### StorageClass Configuration

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-fast
provisioner: nfs.csi.k8s.io
parameters:
  server: 192.168.1.100
  share: /exports/fast  # SSD-backed NAS share
reclaimPolicy: Retain
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-archive
provisioner: nfs.csi.k8s.io
parameters:
  server: 192.168.1.100
  share: /exports/archive  # HDD-backed NAS share for backups
reclaimPolicy: Delete
```

## Database Backup Strategy

### Automated PostgreSQL Backups

```bash
# Create backup namespace
kubectl create namespace backups

# Create backup script ConfigMap
kubectl create configmap backup-scripts \
  -n backups \
  --from-literal=backup.sh='#!/bin/bash
set -e

BACKUP_DIR="/mnt/backups/postgresql/$(date +%Y-%m-%d)"
mkdir -p $BACKUP_DIR

# Full backup
kubectl exec -n databases postgresql-0 -- \
  pg_dump -U postgres --verbose --format=custom code_server > $BACKUP_DIR/code_server.dump

# WAL archival
kubectl exec -n databases postgresql-0 -- \
  pg_basebackup -U postgres --format=tar --wal-method=stream > $BACKUP_DIR/base_backup.tar

# Backup metadata
echo "Backup Size: $(du -sh $BACKUP_DIR)" > $BACKUP_DIR/metadata.txt
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> $BACKUP_DIR/metadata.txt

# Compress
tar -czf $BACKUP_DIR.tar.gz $BACKUP_DIR
rm -rf $BACKUP_DIR

echo "Backup completed: $BACKUP_DIR.tar.gz"
' \
  --from-literal=restore.sh='#!/bin/bash
# Restore from backup

BACKUP_FILE=$1

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: restore.sh <backup_file>"
  exit 1
fi

tar -xzf $BACKUP_FILE

# Stop applications
kubectl scale deployment code-server --replicas=0 -n code-server

# Restore database
kubectl cp $(tar -tzf $BACKUP_FILE | grep code_server.dump | head -1) \
  - -n databases postgresql-0:/tmp/restore.dump

kubectl exec -n databases postgresql-0 -- \
  pg_restore -U postgres --clean --if-exists -d code_server /tmp/restore.dump

# Restart applications
kubectl scale deployment code-server --replicas=3 -n code-server

echo "Restore completed"
'

# Create backup CronJob
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgresql-backup
  namespace: backups
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: backup-sa
          containers:
          - name: backup
            image: bitnami/postgresql:14
            command:
            - /bin/bash
            - /scripts/backup.sh
            volumeMounts:
            - name: backup-scripts
              mountPath: /scripts
            - name: backups
              mountPath: /mnt/backups
          volumes:
          - name: backup-scripts
            configMap:
              name: backup-scripts
          - name: backups
            persistentVolumeClaim:
              claimName: backups-pvc
          restartPolicy: OnFailure
EOF
```

### Point-in-Time Recovery (PITR)

```yaml
# Enable WAL archiving in PostgreSQL
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: backup-alerts
spec:
  groups:
  - name: backup.rules
    rules:
    - alert: BackupMissing
      expr: time() - pg_backup_timestamp_seconds > 86400
      for: 1h
      annotations:
        summary: "PostgreSQL backup older than 24 hours"

    - alert: WALArchiveFailing
      expr: pg_wal_archive_status_failed_count > 0
      for: 10m
      annotations:
        summary: "PostgreSQL WAL archiving failing"

    - alert: BackupStorageLow
      expr: kubelet_volume_stats_available_bytes{persistentvolumeclaim=~".*backup.*"} < 100000000000
      for: 5m
      annotations:
        summary: "Backup storage < 100GB available"
```

## Data Migration & Replication

### Initial Data Sync to On-Premises

```bash
#!/bin/bash
# migrate-data.sh - Sync data from existing system to on-prem

SOURCE_DB="postgres://user:pass@cloud.db.host:5432/code_server"
DEST_DB="postgres://user:pass@postgresql.databases.svc:5432/code_server"

echo "Starting data migration..."

# 1. Create dump from source
pg_dump -h cloud.db.host -U user code_server --verbose --format=custom \
  > code_server_migration.dump

# 2. Create database on destination
kubectl exec -n databases postgresql-0 -- \
  psql -U postgres -c "CREATE DATABASE code_server;"

# 3. Restore to destination
cat code_server_migration.dump | kubectl exec -i -n databases postgresql-0 -- \
  pg_restore -U postgres --clean -d code_server

# 4. Verify data integrity
kubectl exec -n databases postgresql-0 -- \
  psql -U postgres code_server -c "SELECT COUNT(*) as row_count FROM pg_catalog.pg_tables WHERE schemaname = 'public';"

echo "Migration completed"
```

### Continuous Replication (Optional)

```yaml
# Setup pglogical for bidirectional replication
apiVersion: v1
kind: ConfigMap
metadata:
  name: pglogical-config
  namespace: databases
data:
  setup.sql: |
    CREATE EXTENSION pglogical;
    
    SELECT pglogical.create_node(
      node_name := 'on-prem-primary',
      dsn := 'port=5432 dbname=code_server'
    );
    
    SELECT pglogical.create_subscription(
      subscription_name := 'from-cloud',
      provider_dsn := 'postgres://user:pass@cloud.db.host:5432/code_server',
      replication_sets := ARRAY['default']
    );
```

## Disaster Recovery - Data Perspective

### Backup Retention Policy

```bash
# Keep backups with tiered retention:
# - 7 daily backups (1 week)
# - 4 weekly backups (1 month)
# - 12 monthly backups (1 year)

# Automated cleanup script
#!/bin/bash
BACKUP_BASE="/mnt/backups/postgresql"

# Delete backups older than 1 year
find $BACKUP_BASE -name "*.tar.gz" -mtime +365 -delete

# Keep only 4 most recent weekly backups
ls -t $BACKUP_BASE | tail -n +5 | while read old_backup; do
  rm -rf "$BACKUP_BASE/$old_backup"
done

echo "Backup retention policy applied"
```

### Testing Backup Restoration

```bash
#!/bin/bash
# test-restore.sh - Monthly restore test

TEST_DB="test_restore_$(date +%Y%m%d)"
LATEST_BACKUP=$(ls -t /mnt/backups/postgresql/*.tar.gz | head -1)

echo "Testing restore from: $LATEST_BACKUP"

# Extract backup
tar -xzf $LATEST_BACKUP

# Create test database
kubectl exec -n databases postgresql-0 -- \
  psql -U postgres -c "CREATE DATABASE $TEST_DB;"

# Restore to test database
DUMP_FILE=$(tar -tzf $LATEST_BACKUP | grep ".dump" | head -1)
tar -xzOf $LATEST_BACKUP "$DUMP_FILE" | \
  kubectl exec -i -n databases postgresql-0 -- \
    pg_restore -U postgres -d $TEST_DB

# Validate
ROWS=$(kubectl exec -n databases postgresql-0 -- \
  psql -U postgres $TEST_DB -t -c "SELECT COUNT(*) FROM pg_catalog.pg_tables WHERE schemaname='public';")

if [ "$ROWS" -gt 0 ]; then
  echo "✅ Restore test PASSED - $ROWS tables restored"
else
  echo "❌ Restore test FAILED - No tables found"
  exit 1
fi

# Cleanup
kubectl exec -n databases postgresql-0 -- \
  psql -U postgres -c "DROP DATABASE $TEST_DB;"

echo "Monthly restore test completed successfully"
```

### Backup Encryption

```bash
# Encrypt backups at rest
#!/bin/bash

BACKUP_FILE=$1
ENCRYPTION_KEY="/secure/encryption.key"

# Encrypt backup
openssl enc -aes-256-cbc -in $BACKUP_FILE \
  -out $BACKUP_FILE.enc \
  -pass file:$ENCRYPTION_KEY

rm $BACKUP_FILE  # Remove unencrypted

# Decrypt when needed
openssl enc -aes-256-cbc -d -in $BACKUP_FILE.enc \
  -pass file:$ENCRYPTION_KEY > $BACKUP_FILE.restored
```

## Storage Sizing Calculator

```
┌────────────────────────────────────┐
│ Storage Sizing Worksheet           │
├────────────────────────────────────┤
│ Database Size:                 100GB│
│ Daily Change Rate:               5%│
│ Backup Frequency:          Daily   │
│ Retention: 365 days        365 × 5GB│
│                            = 1825GB │
│                                    │
│ Overhead (compression):       -30%  │
│ Actual Needed:             1.3TB   │
│                                    │
│ Safe Capacity (80% rule):   1.6TB   │
│ Recommended NAS Size:       2TB     │
└────────────────────────────────────┘
```

## Monitoring Storage Health

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: storage-alerts
spec:
  groups:
  - name: storage.rules
    rules:
    - alert: PersistentVolumeAlmostFull
      expr: |
        (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) > 0.9
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "PV {{ $labels.persistentvolumeclaim }} is {{ $value | humanizePercentage }} full"

    - alert: PersistentVolumeInodesFull
      expr: |
        (kubelet_volume_stats_inodes_used / kubelet_volume_stats_inodes) > 0.95
      for: 5m
      annotations:
        summary: "PV inodes {{ $value | humanizePercentage }} full"

    - alert: BackupStorageFillingUp
      expr: |
        rate(kubelet_volume_stats_used_bytes{persistentvolumeclaim=~".*backup.*"}[1d]) > 0
      annotations:
        summary: "Backup storage growth rate exceeded"
```

---

**Key Takeaway**: On-premises storage is simpler, predictable, and cheaper than cloud. Plan retention carefully and test restores monthly.
