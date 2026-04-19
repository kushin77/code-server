# Phase 12: Multi-Region Operations Guide

**Document**: Day-2 operations for federated code-server system
**Date**: April 13, 2026

## Quick Start

### Pre-Deployment Checklist

- [ ] 3+ Kubernetes clusters provisioned across regions (Phase 11)
- [ ] Network connectivity verified (latency < 200ms between regions)
- [ ] PostgreSQL BDR extension installed
- [ ] Kafka/Kinesis event streaming provisioned
- [ ] Global DNS (Route 53 / Cloudflare) configured
- [ ] mTLS certificates deployed for inter-region traffic

### Deployment Steps

```bash
# 1. Initialize first region (US-East as primary)
./scripts/phase-12/deploy-multi-region.sh --region us-east --role primary

# 2. Add secondary regions (EU-Central)
./scripts/phase-12/deploy-multi-region.sh --region eu-central --role secondary \
  --replicate-from us-east

# 3. Add tertiary region (APAC-Singapore)
./scripts/phase-12/deploy-multi-region.sh --region apac-singapore --role tertiary \
  --replicate-from us-east

# 4. Activate geographic routing
./scripts/phase-12/activate-geo-routing.sh --provider route53

# 5. Verify replication
./scripts/phase-12/health-check.sh --show-replication-lag
```

## Daily Operations

### Monitoring Replication Health

```bash
# Check all regions
./scripts/phase-12/replication-monitor.sh --all-regions --interval 10

# Output example:
# Region        | Lag (ms) | Queue Depth | Status
# --------------|----------|-------------|--------
# US-East       | local    | -           | ✓ Primary
# EU-Central    | 45       | 12          | ✓ Healthy
# APAC-Sg       | 62       | 8           | ✓ Healthy
# US-West       | 78       | 15          | ✓ Healthy
```

### Event Stream Monitoring

```bash
# Monitor Kinesis/Kafka
aws kinesis describe-stream --stream-name code-server-events

# Consumer lag
aws kinesis get-shard-iterator --stream-name code-server-events \
  --shard-id shardId-000000000000 \
  --shard-iterator-type LATEST

# Check consumer group lag
kafka-consumer-groups --bootstrap-server kafka:9092 \
  --group code-server-consumer \
  --describe
```

### Manual Failover Procedure

**When to trigger**:
- Primary region unresponsive for > 5 minutes
- Primary data corruption detected
- Planned maintenance

**Steps**:

```bash
#!/bin/bash
# Execute if primary (US-East) fails

echo "[FAILOVER] Starting failover to EU-Central..."

# 1. Verify primary is really down
ping -c 3 us-east-primary || echo "Primary unreachable - confirmed"

# 2. Promote secondary to primary
kubectl patch -n production \
  deployment code-server-primary \
  -p '{"spec":{"replicas":0}}'

kubectl patch -n production \
  deployment code-server-secondary \
  -p '{"metadata":{"labels":{"role":"primary"}}}'

# 3. Switch database primary
kubectl exec -n production postgres-secondary-0 -- \
  pg_ctl promote

# 4. Update connection strings
kubectl set env deployment/code-server \
  DATABASE_URL="postgresql://user:pass@eu-central-postgres:5432/code-server"

# 5. Update Route 53
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456789ABC \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "code-server.example.com",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{"Value": "eu-central-lb.example.com"}]
      }
    }]
  }'

# 6. Wait for replication to catch up
./scripts/phase-12/health-check.sh --wait-convergence

echo "[FAILOVER] Failover to EU-Central complete"
```

### Scheduled Maintenance

**Rolling maintenance** (zero downtime):

```bash
#!/bin/bash
# Update US-East cluster without outage

REGION="us-east"

# 1. Remove from geographic routing
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456789ABC \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"DELETE\",
      \"ResourceRecordSet\": {
        \"Name\": \"${REGION}.code-server.example.com\",
        \"Type\": \"A\",
        \"TTL\": 60
      }
    }]
  }"

# 2. Drain pods gracefully (60s grace period)
kubectl patch -n production statefulset code-server \
  -p '{"spec":{"template":{"spec":{"terminationGracePeriodSeconds":60}}}}'

# 3. Delete pods (will be rescheduled after cluster upgrade)
kubectl delete pods -n production -l region=us-east

# 4. Perform cluster upgrade
gcloud container clusters upgrade code-server-us-east \
  --node-pool default-pool \
  --zone us-east1-b

# 5. Re-add to geographic routing
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456789ABC \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"${REGION}.code-server.example.com\",
        \"Type\": \"A\",
        \"TTL\": 60,
        \"SetIdentifier\": \"${REGION}\",
        \"GeoLocation\": {\"CountryCode\": \"US\"}
      }
    }]
  }"

# 6. Wait for convergence
./scripts/phase-12/health-check.sh --region us-east --wait-convergence

echo "Maintenance complete"
```

## Troubleshooting

### High Replication Lag

**Symptom**: Replication lag > 500ms from 2+ regions

**Diagnosis**:
```bash
# Check event queue depth
aws kinesis describe-stream --stream-name code-server-events

# Check consumer lag
aws kinesis list-streams

# Check network latency
ping -c 10 eu-central-node.internal | grep -E 'min|avg|max'

# Check database replication status
psql -h us-east-primary -c "SELECT * FROM pg_stat_replication;"
```

**Recovery**:
```bash
# Increase Kinesis shard count
aws kinesis update-shard-count --stream-name code-server-events \
  --target-shard-count 16

# Scale up consumer threads
kubectl set env deployment/code-server-consumer \
  CONSUMER_THREADS=8

# Monitor recovery
watch -n 5 'aws kinesis get-shard-iterator ...'
```

### Data Divergence

**Symptom**: Hash mismatch between regions

**Diagnosis**:
```bash
# Compare record counts
for region in us-east eu-central apac-singapore; do
  count=$(psql -h ${region}-postgres -c "SELECT COUNT(*) FROM documents;")
  echo "${region}: ${count}"
done

# Identify divergent records
psql -h us-east-postgres -c "EXCEPT
  SELECT * FROM documents
  INTERSECT
  SELECT * FROM documents@eu-central
"
```

**Recovery**:
```bash
# Trigger data reconciliation
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: reconcile-data
spec:
  template:
    spec:
      containers:
      - name: reconciler
        image: code-server:reconcile
        env:
        - name: PRIMARY_REGION
          value: us-east
        - name: RECONCILE_SCOPE
          value: documents,sessions
      restartPolicy: Never
EOF

# Monitor reconciliation progress
kubectl logs -f job/reconcile-data
```

### Regional Isolation

**Symptom**: Region disconnected from others (partition)

**Behavior** (by design):
- Region continues operating locally
- Users in region see stale data but can write
- New writes queued locally
- After reconnection, events replayed

**Recovery**:
```bash
# 1. Verify network path
traceroute eu-central-kafka.internal

# 2. Check VPN status
aws ec2 describe-vpn-connections

# 3. Manually sync if needed
./scripts/phase-12/manual-sync.sh \
  --from us-east \
  --to eu-central \
  --since-timestamp 1681478400

# 4. Monitor event queue drain
watch -n 5 'aws kinesis list-streams'
```

## Multi-Region Testing

### Monthly Chaos Test

```bash
#!/bin/bash
# Run monthly multi-region chaos test

echo "[CHAOS] Starting monthly multi-region chaos engineering..."

# 1. Test single site failure
echo "[TEST 1] Simulating EU region failure..."
./scripts/phase-12/failover-test.sh --region eu-central --duration 5m

# Expected: Users route to US or APAC, no data loss

# 2. Test network partition
echo "[TEST 2] Simulating network partition..."
./scripts/phase-12/partition-test.sh --duration 10m

# Expected: Regions operate independently, converge on reconnect

# 3. Test full convergence
echo "[TEST 3] Verifying eventual consistency..."
./scripts/phase-12/convergence-test.sh --timeout 5m

# Expected: All regions converge within 5 minutes

# 4. Generate report
echo "[REPORT] Generating test report..."
./scripts/phase-12/chaos-report.sh > chaos-report-$(date +%Y%m%d).txt

echo "[CHAOS] Test suite complete"
```

### Disaster Recovery Drill (Quarterly)

```bash
#!/bin/bash
# Quarterly full DR drill - restore all 3 regions from backups

echo "[DR-DRILL] Starting quarterly disaster recovery drill..."

# 1. Create isolated test namespace
kubectl create namespace dr-test

# 2. Restore US-East from backup
./scripts/phase-12/restore-region.sh \
  --region us-east \
  --backup-date 2026-04-10 \
  --namespace dr-test

# 3. Restore EU and APAC
./scripts/phase-12/restore-region.sh --region eu-central --namespace dr-test
./scripts/phase-12/restore-region.sh --region apac-singapore --namespace dr-test

# 4. Wait for convergence
kubectl wait --for condition=Ready pod \
  -l app=code-server -n dr-test \
  --timeout=300s

# 5. Verify data integrity
./scripts/phase-12/verify-data-integrity.sh --namespace dr-test

# 6. Generate report and cleanup
./scripts/phase-12/dr-drill-report.sh

kubectl delete namespace dr-test

echo "[DR-DRILL] Drill complete"
```

## Capacity Planning

### Multi-Region Sizing

**Ingredient**: Account for total load + replication overhead

```
Total throughput: 10,000 req/s global
Distribute: ~2,500 req/s per region (4 active regions)

Per-region sizing:
- App servers: 10 pods × 2000m CPU = 20 CPUs
- Database: 16 vCPU (handles local writes + replication)
- Cache: 6 nodes × 4GB = 24GB
- Event processing: 4 consumer pods

Network usage:
- Intra-region: ~50 Mbps
- Inter-region: ~20 Mbps × 3 = 60 Mbps (typical)
- Backup: ~100 Mbps (scheduled, off-peak)
```

### Regional Growth Forecasting

```bash
# Forecast 12-month growth
./scripts/phase-12/capacity-forecast.sh \
  --metric throughput \
  --baseline 10000 \
  --growth-rate 0.05 \  # 5% monthly
  --periods 12

# Output:
# Month 1: 10,500 req/s
# Month 3: 11,576 req/s
# Month 6: 13,401 req/s
# Month 12: 17,959 req/s
```

**Action items**:
- Month 3: Add 5th region (Australia)
- Month 6: Scale existing regions to 2x capacity
- Month 12: Evaluate edge computing expansion

## On-Call Procedures

### Escalation Path

1. **Automated Alert** (PagerDuty)
   - High replication lag (> 1 second)
   - Region unavailable
   - Data divergence detected

2. **On-Call Engineer** (5 minute response)
   - Acknowledge alert
   - Run diagnostic scripts
   - Determine if auto-remediation applies

3. **Escalation to SRE Lead** (15 minute decision)
   - If manual failover needed
   - If data corruption suspected
   - If multiple regions affected

4. **War Room** (if critical)
   - Director of Engineering
   - VP/CTO
   - Communications lead (for customer updates)

### Common Runbook Decisions

| Alert | 1st Check | Action | Escalate if |
|-------|-----------|--------|-------------|
| High replication lag | Queue depth, network latency | Scale consumers, add shards | Persists > 10 min |
| Region unavailable | Ping, health checks | Auto-failover or manual | Multiple regions down |
| Data divergence | Hash comparison | Auto-reconcile | > 1000 divergent rows |

---

**Status**: Complete
**Last Updated**: April 13, 2026
**Maintained By**: SRE/Operations Team
