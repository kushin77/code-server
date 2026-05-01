# Troubleshooting Guide

## Common Issues & Solutions

### Issue: High Latency on Requests

**Diagnosis:**
```bash
# 1. Check if application is CPU-bound
docker stats --no-stream | grep code-server-SERVICE

# 2. Check database query performance
docker exec code-server-postgres psql -U postgres -tc "SELECT query, calls, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

# 3. Check trace for bottleneck
# Query Tempo for {duration > 1000ms} traces
```

**Solutions:**
- Add database index: `CREATE INDEX idx_name ON table(column);`
- Increase service resources: Update docker-compose limits
- Cache results: Add Redis caching layer
- Query optimization: Review slow query log

### Issue: Replication Lag Growing

**Diagnosis:**
```bash
# Check WAL position difference
ssh akushnir@192.168.168.31 'docker exec code-server-postgres psql -U postgres -tc "SELECT pg_current_wal_lsn();"'
ssh akushnir@192.168.168.42 'docker exec code-server-postgres psql -U postgres -tc "SELECT pg_last_wal_receive_lsn();"'

# Check replica apply time
ssh akushnir@192.168.168.42 'docker exec code-server-postgres psql -U postgres -tc "SELECT write_lag, flush_lag, replay_lag FROM pg_stat_replication;"'
```

**Solutions:**
- Check network between hosts: `ping 192.168.168.31` from replica
- Increase primary wal_keep_size: `SET wal_keep_size = 2GB;`
- Reduce replica workload
- Increase replica resources

### Issue: Redis Memory Growing

**Diagnosis:**
```bash
# Check memory usage
docker exec code-server-redis redis-cli INFO memory | grep used_memory_human

# Check eviction policy
docker exec code-server-redis redis-cli CONFIG GET maxmemory-policy

# Check hot keys
docker exec code-server-redis redis-cli --hotkeys
```

**Solutions:**
- Clear old cached data: `FLUSHDB ASYNC`
- Set TTL on keys: `EXPIRE key 3600`
- Change eviction policy: `CONFIG SET maxmemory-policy allkeys-lru`
- Increase Redis memory limit

### Issue: PostgreSQL Connection Pool Exhausted

**Diagnosis:**
```bash
docker exec code-server-postgres psql -U postgres -tc "SELECT count(*) FROM pg_stat_activity;"
```

**Solutions:**
- Increase max_connections: `ALTER SYSTEM SET max_connections = 200;`
- Restart PostgreSQL: `docker restart code-server-postgres`
- Reduce connection timeout on clients
- Use pgBouncer for connection pooling

### Issue: OPA Policy Denial Spike

**Diagnosis:**
```bash
# Query Loki for denied decisions
# {job="opa"} | json | result = "deny" | stats count by (policy)

# Check OPA logs
docker logs code-server-opa | tail -100
```

**Solutions:**
- Review recent policy changes
- Check requestor identity/permissions
- Temporarily relax policy for troubleshooting
- Debug with curl: `curl -X POST http://localhost:8181/data/policy -d '{"input":...}'`

### Issue: Distributed Trace Not Appearing

**Diagnosis:**
```bash
# Check if spans being sent
docker logs code-server-otel-collector | grep -i span

# Check Tempo data store
docker exec code-server-tempo tempo query --traceID TRACE_ID

# Verify service instrumentation
docker logs code-server-SERVICE | grep -i trace
```

**Solutions:**
- Increase sampling rate in environment: `OTEL_TRACES_SAMPLER_ARG=0.5`
- Verify OTEL collector is running: `docker ps | grep otel`
- Check network connectivity to Tempo
- Verify service has OTEL SDK installed

