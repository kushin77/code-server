# Phase 6: WP-6.5 Database Replication Setup - Implementation

**Status**: In Progress  
**Date**: April 29, 2026  
**Objective**: Configure primary-replica replication for PostgreSQL, Redis, and Redpanda  

---

## WP-6.5 Overview

Database replication enables high availability by replicating data from primary to replica hosts. This work package configures:

1. **PostgreSQL Streaming Replication** (primary-replica)
2. **Redis Master-Replica Replication** (if not already configured)
3. **Redpanda Cluster Formation** (multi-node Kafka-compatible)
4. **Data Consistency Verification**

---

## Prerequisites Verified ✅

- Primary PostgreSQL: Running on 192.168.168.31 (healthy)
- Replica PostgreSQL: Ready on 192.168.168.42
- Primary Redis: Running (data persistence enabled)
- Replica Redis: Ready for replication
- Redpanda: Running on both hosts
- Network connectivity: Verified (<5ms latency)
- Monitoring: Active (Prometheus tracking replication metrics)

---

## Step 1: PostgreSQL Streaming Replication

### Current Status
- Replication slot `replica_1` exists on primary ✅
- Slot is currently inactive (no replica connected)
- Both PostgreSQL instances running and healthy

### Implementation

**1a. Create pg_basebackup on replica**

The replica needs a base backup from primary:

```bash
# On replica (192.168.168.42)
docker exec -u postgres code-server-postgres pg_basebackup \
  -h 192.168.168.31 \
  -U postgres \
  -D /var/lib/postgresql/data-backup \
  -v -P \
  -W
```

**1b. Configure recovery.conf on replica**

Create recovery configuration to enable streaming replication:

```ini
standby_mode = 'on'
primary_conninfo = 'host=192.168.168.31 port=5432 user=postgres password=XXXX'
restore_command = 'cp /var/lib/postgresql/pg_wal/%f "%p"'
recovery_target_timeline = 'latest'
wal_receiver_status_interval = 10s
wal_receiver_timeout = 60s
wal_retrieve_retry_interval = 5s
```

**1c. Restart PostgreSQL on replica**

Once configured, restart to activate replication mode.

### Expected Outcome
- Replica enters recovery/standby mode
- WAL streaming begins from primary
- Replication lag metric becomes available in Prometheus

### Monitoring
- Prometheus alert: `PostgreSQLReplicationLag` (threshold >10s)
- Dashboard: PostgreSQL Performance (replication lag panel)
- Query: `pg_replication_lag_seconds`

---

## Step 2: Redis Master-Replica Replication

### Current Status
- Redis running on primary and replica
- Persistence enabled on both
- Master-replica configuration ready

### Implementation

**2a. Configure replica to replicate from primary**

```bash
# On replica (192.168.168.42)
docker exec code-server-redis redis-cli -h 127.0.0.1 -p 6379 \
  SLAVEOF 192.168.168.31 6379
```

**2b. Monitor replication status**

```bash
docker exec code-server-redis redis-cli -h 127.0.0.1 -p 6379 INFO replication
```

Expected output:
```
# Replication
role:slave
master_host:192.168.168.31
master_port:6379
master_link_status:up
master_replication_offset:XXXX
slave_replication_offset:XXXX
```

### Expected Outcome
- Replica synchronizes with primary
- All writes to primary replicate to replica
- Replication offset advances as writes occur

### Monitoring
- Redis memory metrics visible in Prometheus
- Dashboard: No specific replication panel yet (can add in WP-6.6)

---

## Step 3: Redpanda Cluster Formation

### Current Status
- Redpanda running on both hosts (single-node each)
- Port 9092 (broker), 9644 (admin API)
- No cluster formed yet

### Implementation

**3a. Get cluster metadata from primary**

```bash
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && \
  docker exec code-server-redpanda rpk cluster info"
```

**3b. Configure replica as cluster node**

Add replica as cluster member (requires Redpanda admin API):

```bash
docker exec code-server-redpanda rpk cluster add-node \
  --host 192.168.168.42:33145
```

**3c. Verify cluster formation**

```bash
docker exec code-server-redpanda rpk cluster info
```

Expected output:
- 2 nodes in cluster
- Replication factor for topics
- Leader distribution

### Expected Outcome
- Primary and replica form Redpanda cluster
- Topic replication across both nodes
- Broker failover capability enabled

### Monitoring
- Redpanda metrics visible in Prometheus
- Cluster health tracked by AlertManager

---

## Step 4: Data Consistency Verification

### Verification Checklist

**PostgreSQL**:
```bash
# On primary
docker exec code-server-postgres psql -U postgres -c \
  "SELECT * FROM pg_stat_replication;"
# Should show active replica connection

# Check replication lag
docker exec code-server-postgres psql -U postgres -c \
  "SELECT pg_last_xact_replay_timestamp();"
```

**Redis**:
```bash
# On primary
docker exec code-server-redis redis-cli -h 127.0.0.1 -p 6379 \
  INFO replication

# Compare connected_slaves
# Should show replica as connected
```

**Redpanda**:
```bash
# On primary
docker exec code-server-redpanda rpk cluster info
# Should show 2 nodes, healthy
```

### Expected Results
- PostgreSQL: Replica in standby mode, lag <1 second
- Redis: Master shows 1 connected slave, offsets match
- Redpanda: 2-node cluster, topic replication active

---

## Monitoring Integration

All replication metrics now visible:

### Prometheus Metrics
- `pg_replication_lag_seconds`: PostgreSQL replication lag
- `redis_connected_slaves`: Redis replica count
- Redpanda broker metrics: `redpanda_cluster_brokers`

### Grafana Dashboards
- PostgreSQL Performance Dashboard: Shows replication lag graph
- Monitoring dashboards track cluster status
- Alert triggered if replication lag exceeds threshold

### Alerts Active
- `PostgreSQLReplicationLag` (>10s) → WARNING
- Service health alerts if replication stops

---

## Timeline

| Task | Duration | Status |
|------|----------|--------|
| PostgreSQL streaming replication | 10 min | Ready |
| Redis master-replica setup | 5 min | Ready |
| Redpanda cluster formation | 15 min | Ready |
| Verification and monitoring | 10 min | Ready |
| **Total WP-6.5** | **40 min** | Ready to execute |

---

## Dependencies Met

- ✅ Infrastructure deployed (WP-6.3)
- ✅ Applications running (WP-6.2)
- ✅ Monitoring active (WP-6.4)
- ✅ Network connectivity verified
- ✅ All services healthy

**Status**: WP-6.5 prerequisites complete, ready for execution

