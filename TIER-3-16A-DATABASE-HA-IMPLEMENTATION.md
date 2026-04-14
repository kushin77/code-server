# Phase 16-A: PostgreSQL High Availability & Redundancy

**Status:** IN PROGRESS  
**Effort:** 6 hours  
**Target Completion:** April 17, 2026  
**Dependencies:** None (parallel with 16-B)  
**Owner:** DevOps Team  

---

## Overview

Transform single-node PostgreSQL into highly available, redundant system with:
- **Primary + Standby nodes** (2-node minimum)
- **Automatic failover** (<30 seconds RTO)
- **Zero data loss** (streaming replication)
- **Connection pooling** (pgBouncer for performance)
- **Monitoring & alerting** (Prometheus rules)

### Current State vs Target

```
CURRENT (Single node - not HA):
  ┌─────────────────────┐
  │  PostgreSQL 14.5    │
  │  192.168.168.31:5432│
  │  Single point of    │
  │  failure! ❌        │
  └─────────────────────┘

TARGET (High Availability):
  ┌──────────────────────────────────────────┐
  │                                          │
  │  Primary (192.168.168.31:5432)           │
  │  ├─ Accepts writes                       │
  │  ├─ Replication streaming ACTIVE         │
  │  └─ Leader election ACTIVE               │
  │      ↓ (replication stream)              │
  │  Standby (192.168.168.32:5433)           │
  │  ├─ Read-only replica                    │
  │  ├─ Automatic promotion on failure       │
  │  └─ Zero data loss during promotion      │
  │                                          │
  │  pgBouncer (Load Balancer)               │
  │  ├─ Connection pooling (100 → 5000)     │
  │  ├─ Node failover detection              │
  │  └─ Automatic routing to primary         │
  │                                          │
  └──────────────────────────────────────────┘
  
RPO: 0 seconds (zero-loss replication)
RTO: <30 seconds (automatic failover)
```

---

## Implementation: 6 Hours

### Hour 1: Standby Node Setup

**Steps:**
1. Provision second VM (192.168.168.32)
   ```bash
   # Terraform for second node
   resource "aws_instance" "db_standby" {
     ami = data.aws_ami.ubuntu_20_04.id
     instance_type = "t3.large"
     private_ip = "192.168.168.32"
     security_groups = [aws_security_group.database.id]
     tags = {role = "database-standby"}
   }
   ```

2. Install PostgreSQL 14.5
   ```bash
   sudo apt-get install postgresql-14 postgresql-contrib-14
   ```

3. Initialize as standby from primary
   ```bash
   pg_basebackup -h 192.168.168.31 -D /var/lib/postgresql/14/main
   ```

### Hour 2: Configure Replication

**Primary (192.168.168.31) Config:**
```ini
# /etc/postgresql/14/main/postgresql.conf

# Streaming replication settings
wal_level = replica
max_wal_senders = 5
wal_keep_segments = 64
hot_standby_feedback = on

# Archive settings
archive_mode = on
archive_command = 'test ! -f /archive/%f && cp %p /archive/%f'
restore_command = 'cp /archive/%f "%p"'

# Monitoring
log_replication_commands = on
log_duration = on
```

**Standby (192.168.168.32) Config:**
```ini
# /etc/postgresql/14/main/postgresql.conf

# Standby mode
standby_mode = 'on'
recovery_target_timeline = 'latest'
hot_standby = on
```

**Replication User:**
```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'secure-password';
```

### Hour 3: pgBouncer Connection Pooling

**Installation & Setup:**
```bash
# Install pgBouncer
sudo apt-get install pgbouncer

# Configuration: /etc/pgbouncer/pgbouncer.ini
sudo tee /etc/pgbouncer/pgbouncer.ini << 'EOF'
[databases]
code_server = host=192.168.168.31 port=5432 dbname=code_server

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
reserve_pool_size = 5
reserve_pool_timeout = 5

# Connection timeout
server_lifetime = 3600
server_idle_in_transaction_session_timeout = 1800

# Monitoring
stats_users = metrics_user
EOF

# Start pgBouncer
sudo systemctl restart pgbouncer
```

**Verify Connection Pooling:**
```bash
# Monitor
echo "SHOW POOLS;" | psql -h localhost -p 6432 -U pgbouncer -d pgbouncer

# Load test
pgbench -h localhost -p 6432 -c 500 -j 10 -T 60 code_server
```

### Hour 4: Promote Standby (Failover)

**Manual Failover Procedure:**
```bash
# On standby: Promote to primary
sudo -u postgres pg_ctl promote -D /var/lib/postgresql/14/main

# Verify
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
# Should return: f (not in recovery = now primary)
```

**Automatic Failover with pg_failover_slots:**
```bash
# Install pg_failover_slots extension
git clone https://github.com/EnterpriseDB/pg_failover_slots.git
cd pg_failover_slots && make && sudo make install

# Configure in postgresql.conf
shared_preload_libraries = 'pg_failover_slots'
```

### Hour 5: Monitoring & Alerting

**Replication Lag Monitoring (Prometheus):**
```yaml
# /etc/prometheus/rules/postgresql.yml

groups:
  - name: postgresql
    rules:
      - alert: ReplicationLag
        expr: pg_stat_replication_write_lag_bytes > 1048576
        for: 1m
        annotations:
          summary: "PostgreSQL replication lag > 1MB"
          severity: warning

      - alert: ReplicationDown
        expr: count(pg_stat_replication_status) == 0
        for: 2m
        annotations:
          summary: "PostgreSQL replication not active"
          severity: critical

      - alert: PrimaryDown
        expr: pg_up{job="postgresql_primary"} == 0
        for: 30s
        annotations:
          summary: "PostgreSQL primary is down"
          severity: critical
          runbook: "https://wiki/runbooks/postgresql-failover"
```

**Grafana Dashboard:**
- Replication lag (bytes, time)
- Connected replicas count
- WAL queue size
- Transaction throughput (writes/sec)
- Connection pool utilization
- Standby promotion readiness

### Hour 6: Testing & Validation

**Test 1: Replication Lag Under Load**
```bash
# Run load on primary
pgbench -h 192.168.168.31 -c 100 -j 10 -T 300 code_server

# Monitor replication lag
watch -n 1 'sudo -u postgres psql -c "SELECT now(), slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"'

# Expected: <1 second lag after ramp-down
```

**Test 2: Automatic Failover**
```bash
# Simulate primary failure (in one terminal)
sudo systemctl stop postgresql

# Observe automatic failover to standby (monitor from another terminal)
# In pgBouncer: Requests should retry and succeed
# Standby: Should automatically promote within 30s

# Verify
psql -h pgbouncer-host -c "SELECT current_primary();"
```

**Test 3: Rebuild Primary After Failure**
```bash
# After standby promoted, rebuild old primary as replica
sudo -u postgres pg_basebackup -h 192.168.168.32 -D /var/lib/postgresql/14/main

# Bring old primary back online (now as replica)
sudo systemctl start postgresql

# Verify replication
sudo -u postgres psql -c "SELECT now(), slot_name, restart_lsn FROM pg_replication_slots;"
```

---

## Deployment Architecture

```
┌────────────────────────────────────────────────────────────┐
│ Applications (Code-Server IDE, API Server)                 │
└────────────────────────────────────────────────────────────┘
                            ↓
            ┌───────────────────────────────┐
            │   pgBouncer Load Balancer     │
            │   (Connection Pooling)        │
            │   Port 6432                   │
            └───────────────────────────────┘
            /                               \
           /                                 \
    ┌─────────────────────┐          ┌─────────────────────┐
    │  PostgreSQL PRIMARY │          │ PostgreSQL STANDBY  │
    │  192.168.168.31:5432│◄─────────│ 192.168.168.32:5433 │
    │                     │ Streaming │                     │
    │ Write Operations    │ Replication│ Read Replicas      │
    │ Master-key data    │           │ Hot standby        │
    │ Users, sessions    │           │ Auto-promote ✓     │
    └─────────────────────┘          └─────────────────────┘
           ↓                                  ↓
    ┌──────────────────────────────────────────────────────┐
    │ Archive Storage (S3/MinIO)                           │
    │ WAL archival for disaster recovery                   │
    └──────────────────────────────────────────────────────┘
```

---

## Success Criteria

✅ **All Met** (After implementation):

1. **Replication Active**
   - [ ] `pg_stat_replication` shows connected replica
   - [ ] Write lag <100ms
   - [ ] Flush lag <1 second
   - [ ] Replay lag <100ms

2. **Connection Pooling**
   - [ ] 100 client connections pooled to 25 server connections
   - [ ] Throughput: >1000 tx/sec under load
   - [ ] Connection timeout: <5 seconds on failover

3. **Failover**
   - [ ] Primary failure detected <30 seconds
   - [ ] Standby automatic promotion <30 seconds
   - [ ] Zero client connection loss (retry-able transactions)
   - [ ] RTO: <60 seconds total

4. **Data Integrity**
   - [ ] RPO: 0 bytes (zero data loss)
   - [ ] No transaction loss on primary failure
   - [ ] Archive recovery works (test restore)

5. **Monitoring**
   - [ ] Prometheus metrics: `pg_*` all present
   - [ ] Grafana dashboard: Replication lag visible
   - [ ] Alerts firing for lag >1MB
   - [ ] Alerts firing for replication down

---

## Troubleshooting Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Replication lag high | Network bottleneck | Check wal_level=replica, increase wal_buffers |
| Standby won't catch up | Slow disk on replica | Add SSD, tune `wal_receiver_status_interval` |
| Failover takes >1min | Promotion slow | Tune `recovery_init_sync_method` to fastest |
| Connection pool exhausted | App holding connections | Tune pgBouncer `server_lifetime` |
| Data corruption after failover | Unclean shutdown | Use pg_controldata to verify consistency |

---

## Post-Implementation

**Handoff to Operations:**
- [ ] Operations team trained on failover procedures
- [ ] Runbooks created for common scenarios
- [ ] Monthly failover drills scheduled
- [ ] Monitoring dashboards reviewed
- [ ] On-call alerts tested
- [ ] DR recovery tested (restore from archive)

**Metrics to Track:**
- Replication lag (target: <1 second)
- Failover success rate (target: 100%)
- MTTR (Mean Time To Recovery) threshold: <2 minutes
- Data loss incidents: 0

---

## Next: Phase 16-B (Load Balancing)

After Phase 16-A completion, deploy:
- HAProxy for application load balancing
- Auto-scaling groups for horizontal scaling
- Health check probes
- Rate limiting per developer
- Session persistence

**Integration Point**: Load balancer routes to both database and application tier nodes.

---

## Files/Scripts Created

- `setup-postgresql-ha.sh` - Full HA setup automation
- `postgresql-ha-monitoring.yml` - Prometheus rules
- `failover-procedures.md` - Runbook for ops team
- `test-failover.sh` - Automated failover testing
- `postgres-prometheus-exporter.cfg` - Monitoring config
