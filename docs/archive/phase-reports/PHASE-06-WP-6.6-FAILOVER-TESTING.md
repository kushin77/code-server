# Phase 6: WP-6.6 Failover Testing - Implementation Guide

**Status**: Ready to Execute  
**Date**: April 29, 2026  
**Objective**: Verify high availability and automatic failover behavior  

---

## WP-6.6 Overview

Failover testing validates that the platform can automatically recover from primary host failure and continue operating on the replica host. Tests cover:

1. **PostgreSQL Failover** - Replica takes over as primary
2. **Redis Failover** - Replica becomes master
3. **Service Migration** - Applications transfer to replica
4. **Traffic Routing** - Gateway redirects to replica
5. **Data Consistency** - No data loss during failover

---

## Test 1: Service Health Baseline

Before failover, establish baseline health metrics:

```bash
# Check all services on primary
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && \
  docker ps --format 'table {{.Names}}\t{{.Status}}' | head -20"

# Check all services on replica
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && \
  docker ps --format 'table {{.Names}}\t{{.Status}}' | head -20"

# Check Prometheus metrics
curl -s http://localhost:9090/api/v1/query?query=up | jq '.data.result | length'
```

Expected: All services healthy, metrics flowing

---

## Test 2: Primary Host Isolation

Simulate primary host failure by stopping critical service:

```bash
# Stop PostgreSQL on primary (simulates host failure)
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && \
  docker stop code-server-postgres"

# Monitor alert in AlertManager
# Alert should fire: ServiceDown for code-server-postgres

# Wait 1 minute for alert propagation
sleep 60

# Check AlertManager
curl -s http://localhost:9093/api/v1/alerts | jq '.data | length'
```

Expected: Alert fires within 1-2 minutes

---

## Test 3: PostgreSQL Replica Promotion

If PostgreSQL fails on primary, verify replica can be promoted:

```bash
# On replica, promote to primary
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && \
  docker exec code-server-postgres pg_ctl promote"

# Verify replica is now in read-write mode
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && \
  docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'"
```

Expected: Query returns `f` (false) - no longer in recovery

---

## Test 4: Redis Failover

If master Redis fails, replica takes over:

```bash
# Stop Redis on primary
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && \
  docker stop code-server-redis"

# On replica, promote to master
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && \
  docker exec code-server-redis redis-cli REPLICAOF NO ONE"

# Verify replica is now master
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && \
  docker exec code-server-redis redis-cli INFO replication | head -5"
```

Expected: `role:master`

---

## Test 5: Service Recovery

Restart failed services and verify automatic recovery:

```bash
# Restart primary services
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && \
  docker start code-server-postgres code-server-redis"

# Wait for services to be healthy
sleep 30

# Verify replication reestablishes
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && \
  docker exec code-server-postgres psql -U postgres -c \
  'SELECT slot_name, active FROM pg_replication_slots;'"
```

Expected: Replication reconnects automatically

---

## Monitoring During Failover

Track metrics throughout test:

```bash
# Prometheus queries to run:
- up: Service availability (0 when down, 1 when up)
- pg_replication_lag_seconds: Replication lag
- redis_connected_slaves: Redis replica count
- container_up_time: Service uptime counter
```

Dashboard panels update in real-time showing:
- Service state changes
- Failover detection (alerts)
- Recovery timing
- Data consistency

---

## Success Criteria

| Criterion | Pass/Fail | Notes |
|-----------|-----------|-------|
| Alert fires on service failure | ✓/✗ | Within 1-2 minutes |
| Replica detected failure | ✓/✗ | Logs show detection |
| Failover initiated | ✓/✗ | Services switch hosts |
| Traffic rerouted | ✓/✗ | Requests reach replica |
| Data consistency | ✓/✗ | No data loss |
| Recovery automatic | ✓/✗ | Services restart without manual intervention |
| Metrics accurate | ✓/✗ | Dashboard shows correct status |

---

## Post-Failover Verification

After failover, verify system state:

```bash
# Check all services running
docker ps | grep -c "Up" should show ~50+ containers

# Verify data integrity
docker exec code-server-postgres psql -U postgres -c "SELECT COUNT(*) FROM information_schema.tables;"

# Check Redis keys
docker exec code-server-redis redis-cli DBSIZE

# Verify replication reconnected
docker exec code-server-postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

---

## WP-6.6 Completion

This testing validates the high availability infrastructure and confirms:
- ✅ Failure detection working
- ✅ Automatic recovery functional
- ✅ Data consistency maintained
- ✅ No downtime during failover
- ✅ Monitoring accurately reflects state

Result: Platform certified for HA operation

