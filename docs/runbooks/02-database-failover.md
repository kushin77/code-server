# PostgreSQL Failover Procedure

## Automatic Failover (HA Ready)

When primary PostgreSQL fails:
1. Replica detects no connection (5s timeout)
2. Promotes itself to primary
3. Applications reconnect automatically
4. Old primary becomes replica when recovered

## Manual Failover (Planned Maintenance)

```bash
# 1. Verify replica is caught up
ssh akushnir@192.168.168.42 'docker exec code-server-postgres psql -U postgres -tc "SELECT pg_last_wal_receive_lsn();"'

# 2. Promote replica to primary
ssh akushnir@192.168.168.42 'docker exec code-server-postgres pg_ctl promote -D /var/lib/postgresql/data'

# 3. Verify new primary is ready
ssh akushnir@192.168.168.42 'docker exec code-server-postgres psql -U postgres -tc "SELECT pg_is_in_recovery();"'

# 4. Update old primary as replica (when ready)
ssh akushnir@192.168.168.31 'docker restart code-server-postgres'

# 5. Verify replication restored
ssh akushnir@192.168.168.42 'docker exec code-server-postgres psql -U postgres -tc "SELECT client_addr, state FROM pg_stat_replication;"'
```

## Failover Testing

```bash
# Test failover without actual primary failure

# 1. Stop primary gracefully
ssh akushnir@192.168.168.31 'docker stop code-server-postgres'

# 2. Verify replica detects primary down
sleep 6
ssh akushnir@192.168.168.42 'docker exec code-server-postgres psql -U postgres -tc "SELECT pg_is_in_recovery();" | grep f' # Should show f (false = primary)

# 3. Restart primary
ssh akushnir@192.168.168.31 'docker start code-server-postgres'
sleep 10

# 4. Verify primary becomes replica
ssh akushnir@192.168.168.31 'docker exec code-server-postgres psql -U postgres -tc "SELECT pg_is_in_recovery();"' # Should show t (true = replica)

# 5. Verify replication resumes
ssh akushnir@192.168.168.42 'docker exec code-server-postgres psql -U postgres -tc "SELECT client_addr FROM pg_stat_replication;"'
```

## Redis Failover (Sentinel)

```bash
# Monitor Redis Sentinel
docker exec code-server-redis redis-cli SENTINEL masters

# Manual trigger failover (if needed)
docker exec code-server-redis redis-cli SENTINEL failover mymaster

# Verify new master
docker exec code-server-redis redis-cli INFO replication
```

## Recovery Procedures

### Primary Corrupted
- Use replica as new primary
- Rebuild old primary from scratch or from backup
- Restore replication

### Replica Corrupted
- Remove replica from cluster
- Create new replica from primary base backup
- Add new replica to service

### Both Down
- Restore from latest backup
- Re-initialize replication
- Resume operations

