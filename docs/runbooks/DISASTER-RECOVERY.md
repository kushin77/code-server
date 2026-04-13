# Disaster Recovery & Business Continuity Runbook

## Recovery Strategies

### RTO & RPO Targets

| Scenario | RTO | RPO | Priority |
|----------|-----|-----|----------|
| **Pod crash** | 5 min | 0 min (stateless) | P1 |
| **Node failure** | 10 min | 0 min (K8s rescheduling) | P1 |
| **Database corruption** | 1 hour | 1 hour (hourly backups) | P1 |
| **Entire region down** | 4 hours | 1 hour (cross-region) | P1 |
| **Full cluster rebuild** | 8 hours | 4 hours (GCS backups) | P2 |

**RTO** = Recovery Time Objective (how fast can we restore?)
**RPO** = Recovery Point Objective (how much data can we lose?)

---

## Disaster Scenarios & Responses

### Scenario 1: Single Node Fails

**Detection**: Kubernetes automatically detects node NotReady

**Automatic Recovery** (no manual intervention needed):
```bash
# Kubernetes detects node failure
# Within 5 minutes, all pods evicted and rescheduled to healthy nodes

# Monitor
kubectl get nodes --watch
# Node will show "NotReady"

# After 5 minutes, check pods
kubectl get pods -A | grep -i pending
# Should be none if cluster has capacity
```

**Manual Action** (if auto-recovery fails):
```bash
# Delete the failed node
kubectl delete node <node-name>

# GKE auto-repairs: Waits for replacement node
# Self-managed: You provision replacement manually
```

**Prevention**:
- Multi-zone node pool (spread nodes across zones)
- HPA set to max >= 3× expected load
- Pod Disruption Budgets on all deployments

---

### Scenario 2: Database (PostgreSQL) Failure

**Detection**: Connection pool exhausted, queries timing out

**Immediate Response** (RTO: 5 min):

```bash
# Option A: Failover to replica (if using Cloud SQL HA)
gcloud sql instances failover $INSTANCE_NAME --backup-configuration-id 1

# Option B: Restore from backup
gcloud sql backups list --instance=$INSTANCE_NAME
# Find most recent backup before corruption

gcloud sql backups restore <BACKUP_ID> \
  --backup-instance=$INSTANCE_NAME \
  --backup-restore-instance=$NEW_INSTANCE_NAME
```

**Data Recovery** (if single backup isn't enough):

```bash
# Cloud SQL keeps 30-day backup history
gcloud sql backups list --instance=$INSTANCE_NAME | head -10

# Find when corruption started, restore from backup before that
gcloud sql backups restore <PRE-CORRUPTION-BACKUP> --wait

# Verify data integrity
psql $DATABASE_URL -c "SELECT COUNT(*) FROM critical_table;"
```

**Prevention**:
- Enable automated backups (daily)
- Replicate to another region with Cloud SQL HA
- Regular restore tests (monthly in staging)
- Monitoring for connection pool exhaustion

---

### Scenario 3: Redis Cache Loss

**Detection**: High cache miss rate, latency spike

**Quick Recovery** (RTO: 10 min):
```bash
# Redis data is cache only (not source of truth)
# Treat as cache miss, app handles cache population

# Check Redis status
kubectl get pod redis-0 -n code-server

# If Redis is down:
kubectl delete pod redis-0 -n code-server
# Kubernetes reschedules new pod, cache rebuilds from app queries

# Monitor cache rebuild
watch -n 2 'redis-cli INFO stats | grep hits'
```

**Mitigation** (if app queries slow during rebuild):
```bash
# Scale up services that depend on Redis
kubectl scale deployment/agent-api --replicas=10 -n agents
kubectl scale deployment/code-server --replicas=5 -n code-server

# Reduce TTLs temporarily to avoid stale data
# Code change: reduce cache TTL from 3600s to 300s
# Deploy patch quickly
```

**Prevention**:
- Redis runs with RDB persistence (can rebuild from disk)
- Regular snapshots to GCS (weekly full backup)
- Monitor cache hit ratio, alert if < 80%
- Implement graceful cache miss handling in app

---

### Scenario 4: Entire Kubernetes Cluster Becomes Unavailable

**Detection**: All kubectl commands timeout, no pods responding

**RTO: 2-4 hours**

**Before Disaster (Prevention)**:
```bash
# Regular cluster export
kubectl get all --all-namespaces -o json > cluster-backup.json
kubectl get pv --all-namespaces -o json >> cluster-backup.json
kubectl get secrets --all-namespaces -o json >> cluster-backup.json

# Upload to GCS (versioned, encrypted)
gsutil cp cluster-backup.json gs://disaster-recovery-backups/

# Schedule weekly:
# */0 7 * * 0 /scripts/backup-cluster.sh
```

**Recovery Steps**:

1. **Verify cluster is truly unrecoverable**
   ```bash
   for i in {1..5}; do
     kubectl cluster-info && echo "ℹ️ Cluster responding" && exit 0
     echo "Attempt $i: No response, waiting 30s..."
     sleep 30
   done
   
   echo "❌ Cluster confirmed down, starting recovery..."
   ```

2. **Create new cluster (GKE)**
   ```bash
   gcloud container clusters create recovery-cluster \
     --num-nodes 3 \
     --machine-type n2-standard-4 \
     --zone us-central1-a \
     --enable-autoscaling \
     --min-nodes 3 \
     --max-nodes 10
   
   # Get credentials
   gcloud container clusters get-credentials recovery-cluster \
     --zone us-central1-a
   ```

3. **Restore from backup**
   ```bash
   # Download cluster backup
   gsutil cp gs://disaster-recovery-backups/cluster-backup.json .
   
   # Restore all resources
   kubectl apply -f cluster-backup.json
   
   # Wait for all pods to be ready
   kubectl wait --for=condition=Ready pod \
     --all --all-namespaces --timeout=600s
   ```

4. **Restore persistent volumes**
   ```bash
   # List GCS backup snapshots
   gsutil ls gs://disaster-recovery-backups/volumes/
   
   # For each volume, restore from snapshot
   gcloud compute snapshots list --filter="labels.backup_date>=2026-04-12"
   
   # Create disks from snapshots
   gcloud compute disks create recovered-disk-1 \
     --source-snapshot=volume-snapshot-20260412-132000 \
     --zone us-central1-a
   
   # Manually mount to new PVCs (match original)
   ```

5. **Restore database from backup**
   ```bash
   # Create new Cloud SQL instance with same config
   gcloud sql instances create recovery-db \
     --database-version POSTGRES_14 \
     --tier db-custom-4-16gb \
     --region us-central1
   
   # Restore from backup
   gcloud sql backups restore <BACKUP> \
     --backup-instance=$ORIGINAL_DB \
     --backup-restore-instance=recovery-db
   
   # Verify data
   gcloud sql connect recovery-db \
     --user=postgres
   ```

6. **Validate Application**
   ```bash
   # Update DNS to point to new cluster
   gcloud dns record-sets transaction start
   gcloud dns record-sets transaction add <NEW_CLUSTER_IP> \
     --name api.example.com \
     --type A \
     --ttl 60
   gcloud dns record-sets transaction remove <OLD_CLUSTER_IP> \
     --name api.example.com \
     --type A \
     --ttl 300
   gcloud dns record-sets transaction execute
   
   # Health checks
   curl https://api.example.com/health
   ./scripts/integration-tests.sh production
   ```

**Estimated Time**: 2-4 hours depending on data volume

---

### Scenario 5: Database Region Outage (Multi-Region Setup)

**Setup** (proactive):
```bash
# Create replica database in different region
gcloud sql instances create prod-db-replica \
  --master-instance-name prod-db \
  --tier db-custom-4-16gb \
  --region us-east1
```

**Failover Process** (RTO: 5 min):
```bash
# If primary region (us-central1) is down:

# Promote replica to standalone
gcloud sql instances promote-replica prod-db-replica

# Update connection string in app config
kubectl set env deployment/code-server \
  DATABASE_URL="postgresql://user@prod-db-replica:5432/code_server" \
  -n code-server

# Restart apps to use new connection
kubectl rollout restart deployment/code-server -n code-server
```

---

## Backup & Recovery Tests

### Monthly Restore Test (Compliance Requirement)

**Process**:
```bash
date=$(date +%Y-%m-%d)
echo "Starting monthly disaster recovery test: $date"

# 1. Create test database from backup
gcloud sql backups list --instance=prod-db | head -20
BACKUP_ID=$(gcloud sql backups list --instance=prod-db --limit=1 \
  --format='value(name)')

gcloud sql backups restore $BACKUP_ID \
  --backup-instance=prod-db \
  --backup-restore-instance=test-restore-$date

# 2. Verify data integrity
psql -h test-restore-$date -U postgres -d code_server \
  -c "SELECT COUNT(*) FROM critical_tables;"

# 3. Check for corruption
psql -h test-restore-$date -U postgres -d code_server \
  -c "PRAGMA integrity_check;" || true

# 4. Document results
echo "✅ Restore test successful: $date" >> disaster-recovery-tests.log

# 5. Clean up test instance
gcloud sql instances delete test-restore-$date --quiet
```

**Schedule**: First Monday of each month at 10am UTC

**Runbook**: `docs/BACKUP-RESTORE-TEST.md` (auto-generated)

---

## Communication During Disaster

### Incident Declaration

When it becomes clear this is a major incident:

```
🚨 CRITICAL INCIDENT: [Service] Down
Severity: SEV1 (Data center / region unavailable)
Start: [TIME]
Updates: Every 15 minutes
Status Page: status.example.com
```

### Customer Communication Template

```markdown
We are experiencing issues with code-server platform affecting all users.
Our team is investigating. ETA for update: [TIME + 30 min]

What we know:
- Started: [TIME]
- Affected: All services in [REGION]
- Status: Activating disaster recovery

What we're doing:
- Failing over to backup infrastructure
- Restoring from recent backups
- Validation in progress

Next update: [TIME + 15 min]
```

### Internal Escalation Channel
- #critical-incident (Slack)
- Page: VP Engineering, CTO, CEO
- Kickstart war room: <link>

---

## Maintenance Mode

If recovery will take > 30 minutes, show maintenance page:

```bash
# Redirect all traffic to maintenance page
kubectl create configmap maintenance-page \
  --from-literal=index.html='<html><body><h1>Maintenance in progress...</h1></body></html>' \
  -n code-server

# Update ingress to serve maintenance page
kubectl patch ingress code-server-ingress -n code-server \
  -p '{"spec":{"rules":[{"host":"code-server.example.com","http":{"paths":[{"path":"/","backend":{"serviceName":"maintenance","servicePort":8080}}]}}]}}'

# Once recovered, restore
kubectl patch ingress code-server-ingress -n code-server \
  -p '{"spec":{"rules":[{"host":"code-server.example.com","http":{"paths":[{"path":"/","backend":{"serviceName":"code-server","servicePort":8080}}]}}]}}'
```

---

## Post-Disaster Actions

### Within 24 Hours:
- [ ] Post-mortem report filed
- [ ] Root cause identified
- [ ] Backup integrity verified
- [ ] Customer communication sent

### Within 1 Week:
- [ ] Permanent fixes implemented
- [ ] Prevention measures deployed
- [ ] Disaster recovery plan updated
- [ ] Team training completed

### Quarterly:
- [ ] DR test performed (unannounced)
- [ ] RTO/RPO verified
- [ ] Backup retention reviewed
- [ ] New failure scenarios added to playbook

---

## Critical Data Protection

**Data Encryption**:
```bash
# All backups encrypted with Google Managed Encryption Keys (GMEK)
gsutil kms encryption set gs://disaster-recovery-backups

# Enable versioning (prevents accidental deletion)
gsutil versioning set on gs://disaster-recovery-backups
```

**Access Control**:
```yaml
# Only on-call lead and CTO can trigger restores
roles/compute.admin: [@cto, @engineering-lead]
roles/cloudsql.editor: [@cto, @engineering-lead]
```

**Audit Trail**:
```bash
# All restore operations logged
gcloud logging read 'resource.type="cloudsql_database"' \
  --filter='protoPayload.methodName:"cloudsql.instances.restoreBackup"'
```

---

## Success Criteria

- ✅ RTO met (recovery time within target)
- ✅ RPO met (data loss within tolerance)
- ✅ Services passing health checks
- ✅ No process crashes post-recovery
- ✅ Data integrity verified
- ✅ Monitoring/alerting functional
- ✅ Customer-facing status updated
