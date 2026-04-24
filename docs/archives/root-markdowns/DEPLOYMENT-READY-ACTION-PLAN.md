# Database Resilience Deployment - Ready-to-Execute Action Plan

**Date**: April 23, 2026  
**Status**: 🟢 READY FOR EXECUTION  
**Priority**: P1 (Production Blocker)

## Executive Summary

Database resilience infrastructure prerequisites are met:
- ✅ SSH connectivity verified to both hosts
- ✅ Docker operational on both hosts  
- ✅ PostgreSQL containers operational
- ✅ Existing failover scripts available for testing

**Missing**: 5-layer resilience deployment (replication, backup, health checks, failover monitoring, partition recovery)

## Quick Start - Execute These Commands

### On Primary Host (192.168.168.31)

```bash
# Step 1: Verify connectivity to replica
ssh akushnir@192.168.168.42 "echo 'Replica reachable'"

# Step 2: Check current PostgreSQL status
docker exec postgres psql -U postgres -c "SELECT version();"

# Step 3: Run production failover test (dry-run mode first)
cd code-server-enterprise
DRY_RUN=1 RUN_PREFLIGHT=1 bash scripts/ops/run-production-failover-test.sh

# Step 4: If preflight passes, run actual failover test
# WARNING: This is a real test of your infrastructure!
# DRY_RUN=0 bash scripts/ops/run-production-failover-test.sh
```

## Phased Deployment Plan

### Phase 1: PostgreSQL Streaming Replication (Est. 15-20 min)

**Goal**: Enable zero-data-loss failover with <30s RTO

**Prerequisite Checks**:
```bash
# On primary:
docker exec postgres psql -U postgres -c "SHOW wal_level;"  # Should be 'replica' or higher
docker exec postgres psql -U postgres -c "SHOW max_wal_senders;"  # Should be >= 2
```

**Setup Steps**:
1. Configure primary for replication:
   ```bash
   docker exec postgres psql -U postgres -c "
     ALTER SYSTEM SET wal_level = replica;
     ALTER SYSTEM SET max_wal_senders = 3;
     ALTER SYSTEM SET max_replication_slots = 3;
   "
   docker exec postgres psql -U postgres -c "SELECT pg_reload_conf();"
   ```

2. Create replication user:
   ```bash
   docker exec postgres psql -U postgres -c "
     CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'secure_password';
     GRANT CONNECT ON DATABASE postgres TO replicator;
   "
   ```

3. Create replication slot:
   ```bash
   docker exec postgres psql -U postgres -c "
     SELECT * FROM pg_create_physical_replication_slot('replica_slot');
   "
   ```

4. Start streaming replication on replica (192.168.168.42):
   ```bash
   ssh akushnir@192.168.168.42 "
     docker exec postgres bash -c '
       pg_basebackup -h 192.168.168.31 -D /var/lib/postgresql/data -U replicator -P -v -R
     '
   "
   ```

5. Verify replication:
   ```bash
   # On primary:
   docker exec postgres psql -U postgres -c "
     SELECT slot_name, active, restart_lsn FROM pg_replication_slots;
   "
   
   # On replica:
   docker exec postgres psql -U postgres -c "
     SELECT pg_last_xlog_receive_location();
   "
   ```

### Phase 2: Automated Backup (Est. 10 min)

**Goal**: Point-in-time recovery with RTO <30min, RPO <1hr

**Setup**:
```bash
# On primary - create backup directory
mkdir -p /var/lib/postgresql/backups && chmod 700 /var/lib/postgresql/backups

# Create backup script
cat > /tmp/backup-postgres.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/lib/postgresql/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
docker exec postgres pg_dump -U postgres -F c postgres > "$BACKUP_DIR/postgres_${TIMESTAMP}.dump"
echo "Backup: $BACKUP_DIR/postgres_${TIMESTAMP}.dump"
EOF

chmod +x /tmp/backup-postgres.sh
/tmp/backup-postgres.sh

# Schedule hourly backups via cron
(crontab -l 2>/dev/null; echo "0 * * * * /tmp/backup-postgres.sh") | crontab -
```

### Phase 3: Health Checks (Est. 10 min)

**Goal**: <5s detection of failures

**Setup**:
```bash
# Deploy health check endpoints on port 8081
docker run -d --name postgres-health \
  -p 8081:8080 \
  --network net-app \
  priyabrata/healthcheck:latest \
  -H postgresql://postgres:password@postgres:5432/postgres

# Test
curl -s http://localhost:8081/health | jq .
```

### Phase 4: Failover Monitoring (Est. 15 min)

**Goal**: Automatic failover without manual intervention

**Setup**:
```bash
# Review existing failover script
cat code-server-enterprise/scripts/ops/run-production-failover-test.sh

# Test automatic failover (DRY-RUN FIRST!)
cd code-server-enterprise
DRY_RUN=1 bash scripts/ops/run-production-failover-test.sh

# If test passes, enable real failover:
# DRY_RUN=0 bash scripts/ops/run-production-failover-test.sh
```

### Phase 5: Network Partition Recovery (Est. 10 min)

**Goal**: Graceful degradation during network splits

**Configuration**:
```bash
# Deploy quorum monitor on port 8083
docker run -d --name quorum-monitor \
  -p 8083:8080 \
  --network net-app \
  -e PRIMARY_HOST=192.168.168.31 \
  -e REPLICA_HOST=192.168.168.42 \
  -e ARBITER_HOST=192.168.168.50 \
  quorum-monitor:latest

# Verify quorum status
curl -s http://localhost:8083/quorum-status | jq .
```

## Validation Checklist

After each phase, verify:

- [ ] Phase 1: Replication lag < 100ms
- [ ] Phase 2: Backup files created hourly
- [ ] Phase 3: Health endpoints respond within 5s
- [ ] Phase 4: Failover test passes (dry-run first!)
- [ ] Phase 5: Quorum monitor operational

## Rollback Plan

If any phase fails:

```bash
# Stop services
docker stop postgres-health quorum-monitor postgres

# Restore from backup
LATEST_BACKUP=$(ls -t /var/lib/postgresql/backups/* | head -1)
docker exec postgres pg_restore -U postgres -C -d postgres "$LATEST_BACKUP"

# Restart
docker-compose up -d postgres
```

## Success Criteria

✅ All phases complete  
✅ Replication lag < 100ms  
✅ Failover time < 30s  
✅ Zero data loss on failover  
✅ Health checks detect failures < 5s  
✅ Automatic failover without manual intervention  

## Next Steps After Deployment

1. Run staging validation: `bash scripts/ops/validate-staging-database-resilience.sh`
2. Collect evidence for production decision (#1467)
3. Present to team for GO/NO-GO approval (#1464)
4. Execute production deployment
5. Post-deployment retrospective (#1471)

## Support & Questions

- Consult: [DATABASE-RESILIENCE-EXECUTION-PLAN.md](../DATABASE-RESILIENCE-EXECUTION-PLAN.md)
- Issues: #1518 (Replication), #1521 (Backup), #1522 (Health), #1519 (Failover), #1520 (Partition)
- Runbooks: code-server-enterprise/docs/RUNBOOK-*.md
