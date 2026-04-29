# Disaster Recovery Plan

## RPO & RTO Targets

- **RPO (Recovery Point Objective)**: < 1 second (streaming replication)
- **RTO (Recovery Time Objective)**: < 5 minutes (automatic failover)
- **Backup Retention**: 30 days (Loki logs), 7 days (database backups)

## Backup Strategy

### Automated Backups
```bash
# Database: Daily base backup to /backups/pgbackup/
0 2 * * * root pg_basebackup -D /backups/pgbackup/daily-$(date +\%Y\%m\%d) -F tar -z

# Configuration: Daily to git (already implemented)
# Logs: Retained in Loki for 30 days
```

### Manual Backup
```bash
ssh akushnir@192.168.168.31 'docker exec code-server-postgres pg_basebackup -D /tmp/backup -F tar -z'
tar czf /backups/manual-backup-$(date +%Y%m%d).tar.gz -C /tmp backup/
```

## Disaster Scenarios & Recovery

### Scenario 1: Single Node Failure

**Primary Down:**
- Replica automatically promotes
- Applications continue on replica (slightly degraded)
- Restore primary when recovered: `docker-compose up -d code-server-postgres`

**Replica Down:**
- Primary continues
- No automatic failover capability
- Rebuild replica: `pg_basebackup -D /var/lib/postgresql/data`

**Recovery Time:** < 5 minutes

### Scenario 2: Network Partition

**Split Brain Risk:**
- Quorum-based protection ensures only one master (if Sentinel enabled)
- OPA audit logging continues on both sides
- Recovery: Restore network, prefer newer primary

**Recovery Time:** < 10 minutes

### Scenario 3: Both Nodes Down

**Data Recovery from Backup:**
```bash
# 1. Restore from latest backup
tar xzf /backups/pgbackup/latest.tar.gz -C /var/lib/postgresql/

# 2. Apply WAL archive (if available)
pg_wal_restore /var/lib/postgresql/pg_wal

# 3. Start primary
docker-compose up -d code-server-postgres

# 4. Build replica from new primary
pg_basebackup -D /var/lib/postgresql/data -h PRIMARY_IP
```

**Recovery Time:** 30 minutes - 1 hour (depends on data volume)

### Scenario 4: Data Corruption

**Detection:**
```bash
docker exec code-server-postgres pg_verify_checksums /var/lib/postgresql/data
```

**Recovery:**
```bash
# 1. Stop all writes to primary
docker stop code-server-SERVICE1 code-server-SERVICE2 ...

# 2. Restore replica from backup
# 3. Promote replica to primary
# 4. Rebuild corrupted primary
# 5. Add back to cluster
```

**Recovery Time:** 1-2 hours

## Testing & Validation

### Weekly Test (10 minutes)
```bash
# 1. Query Tempo: verify traces flowing
# 2. Query Loki: verify logs flowing
# 3. Check replication: `pg_stat_replication`
# 4. Restart one service: `docker restart code-server-SERVICE`
# 5. Verify it recovered
```

### Monthly Drill (1 hour)
```bash
# Full failover test:
# 1. Stop primary database
# 2. Wait for replica to promote
# 3. Verify applications running
# 4. Restart primary as replica
# 5. Verify replication restored
```

### Quarterly Full Recovery (4 hours)
```bash
# Restore from backup to test infrastructure
# Verify all services start
# Run smoke tests
# Document any issues
```

## Communication Plan

### During Outage
- Page: On-call engineer
- Notify: Slack #incident-response
- Escalate: Director after 15 min
- Stakeholder update: Every 15 min

### Post-Recovery
- Document: What failed, how fixed, lessons learned
- Update: Runbooks based on what we learned
- Schedule: Postmortem meeting within 24 hours

## Contact List

- **On-Call Engineer**: [Phone/Slack]
- **Database DBA**: [Phone/Slack]
- **DevOps Lead**: [Phone/Slack]
- **Director**: [Phone/Slack]
- **Escalation**: [Company phone tree]

