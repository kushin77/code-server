# Phase 11: Advanced Resilience, HA/DR & Observability
## High Availability & Disaster Recovery Implementation Guide

**Status**: Ready for Implementation  
**Priority**: CRITICAL (Production Reliability)  
**Target Metrics**: RTO <1h, RPO <15min  

---

## Part I: High Availability Configuration

### 1. PostgreSQL Streaming Replication Setup

#### Primary Server Configuration (production-primary.conf)
```bash
# Enable WAL archiving for backup
wal_level = replica
max_wal_senders = 10
wal_keep_segments = 64
hot_standby = on

# Synchronous replication (wait for standby confirmation)
synchronous_commit = remote_apply
synchronous_standby_names = 'standby1'

# Archive command for off-site backup
archive_mode = on
archive_command = 'cp %p /archive/%f'
archive_timeout = 300
```

#### Standby Server Configuration (standby.conf)
```bash
standby_mode = 'on'
primary_conninfo = 'host=primary.example.com port=5432 user=replication password=xxxxx'
restore_command = 'cp /archive/%f %p'
recovery_timeout = 300
```

**Setup Steps**:
1. Create replication user on primary: `CREATE USER replication WITH REPLICATION ENCRYPTED PASSWORD 'password';`
2. Add to pg_hba.conf: `host replication replication standby_ip/32 md5`
3. Start base backup: `pg_basebackup -h primary -D /var/lib/postgresql/main -U replication -v -P`
4. Create recovery.conf on standby
5. Start standby: `pg_ctl start`

**Verification**:
```sql
-- On primary
SELECT slot_name, slot_type, active FROM pg_replication_slots;
SELECT application_name, state FROM pg_stat_replication;

-- On standby
SELECT pg_last_xlog_receive_location(), pg_last_xlog_replay_location();
```

---

### 2. Redis Cluster Setup for Distributed Caching

#### Redis Cluster Configuration (redis-cluster.conf)
```yaml
# Cluster settings
cluster-enabled yes
cluster-config-file /var/lib/redis/nodes.conf
cluster-node-timeout 15000
cluster-require-full-coverage no

# Replication
replicaof-no-one
replica-priority 100

# Persistence
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfsync everysec

# Memory management
maxmemory 4gb
maxmemory-policy allkeys-lru

# Eviction
activerehashing yes
```

**Cluster Creation**:
```bash
# Create 6 nodes (3 primary, 3 replica)
redis-cli --cluster create \
  127.0.0.1:7000 127.0.0.1:7001 127.0.0.1:7002 \
  127.0.0.1:7003 127.0.0.1:7004 127.0.0.1:7005 \
  --cluster-replicas 1

# Verify cluster health
redis-cli -c CLUSTER INFO
```

---

### 3. Load Balancing with Caddy/HAProxy

#### HAProxy Configuration (haproxy.cfg)
```ini
global
    log stdout local0
    maxconn 4096
    daemon
    balance roundrobin

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend api_in
    bind *:8080
    mode tcp
    default_backend api_servers

backend api_servers
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 3001
    
    server api1 192.168.1.10:3001 check
    server api2 192.168.1.11:3001 check
    server api3 192.168.1.12:3001 check
    
    # Sticky sessions for stateful services
    cookie SERVERID insert indirect nocache

listen stats
    bind *:8404
    stats enable
    stats admin if TRUE
```

---

### 4. Service Discovery with Consul

#### Consul Configuration (consul.hcl)
```hcl
server = true
node_id = "primary-1"
node_name = "primary-node-1"
datacenter = "dc1"
bind_addr = "0.0.0.0"
bootstrap_expect = 3

services = [
  {
    id      = "code-server-1"
    name    = "code-server"
    tags    = [ "primary", "production" ]
    port    = 8080
    address = "192.168.1.10"
    
    check = {
      http     = "http://localhost:8080/healthz"
      interval = "10s"
      timeout  = "5s"
    }
  }
]
```

**Service Registration**:
```bash
# Register service
consul services register /etc/consul.d/code-server.hcl

# Query services
consul catalog services
consul catalog nodes -service=code-server
```

---

## Part II: Automatic Failover Procedures

### Failover Detection & Automation

#### Keepalived Configuration (keepalived.conf)
```bash
global_defs {
  router_id HA_PRIMARY
  script_user root root
}

vrrp_script check_api {
  script "/usr/local/bin/check-api-health.sh"
  interval 2
  weight -20
  fall 3
  rise 2
}

vrrp_instance VI_1 {
  state MASTER
  interface eth0
  virtual_router_id 51
  priority 150
  advert_int 1
  
  virtual_ipaddress {
    192.168.1.100/24
  }
  
  track_script {
    check_api
  }
  
  notify_master "/usr/local/bin/on-master.sh"
  notify_backup "/usr/local/bin/on-backup.sh"
  notify_fault "/usr/local/bin/on-fault.sh"
}
```

#### Health Check Script (check-api-health.sh)
```bash
#!/bin/bash
set -e

# Check multiple health indicators
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/healthz)
DB_CONNECTED=$(psql -h localhost -U postgres -c "SELECT 1" 2>&1)
REDIS_WORKING=$(redis-cli ping)

if [ "$STATUS_CODE" = 200 ] && [ -n "$DB_CONNECTED" ] && [ "$REDIS_WORKING" = "PONG" ]; then
  exit 0  # Healthy
else
  exit 1  # Unhealthy
fi
```

#### Failover Script (on-backup.sh)
```bash
#!/bin/bash
set -e

# Notify team
curl -X POST https://slack.example.com/hooks/... \
  -d '{"text":"FAILOVER INITIATED: Promoting backup to primary"}'

# Promote backup to primary (PostgreSQL)
pg_ctl promote -D /var/lib/postgresql/main

# Wait for promotion to complete
sleep 5

# Verify promotion
psql -c "SELECT pg_is_in_recovery();"  # Should return false

# Update service discovery
consul services deregister code-server-backup
consul services register -id code-server-primary -name code-server

# Start services that require primary
systemctl restart code-server-api

echo "Failover completed successfully" | logger -t failover
```

---

## Part III: Disaster Recovery Procedures

### Backup Strategy

#### Automated Daily Backups (backup-cron.sh)
```bash
#!/bin/bash
BACKUP_DIR="/backups/daily"
DATE=$(date +%Y%m%d_%H%M%S)

# PostgreSQL backup
mkdir -p $BACKUP_DIR/postgres
pg_dump -h localhost -U postgres code_server | \
  gzip > $BACKUP_DIR/postgres/database_$DATE.sql.gz

# Off-site replication
aws s3 sync $BACKUP_DIR s3://backups.example.com/ \
  --sse AES256 \
  --storage-class GLACIER

# Verify backup integrity
gunzip -t $BACKUP_DIR/postgres/database_$DATE.sql.gz || \
  echo "ERROR: Backup verification failed" | logger -t backup-alert
```

**Cron Schedule**:
```bash
# Hourly snapshots (keep 24 hours)
0 * * * * /usr/local/bin/backup-hourly.sh

# Daily backups (keep 30 days)
0 2 * * * /usr/local/bin/backup-daily.sh

# Weekly full backups (keep 52 weeks)
0 3 * * 0 /usr/local/bin/backup-weekly.sh
```

### Point-in-Time Recovery

#### Recovery Procedure
```bash
#!/bin/bash
set -e

RECOVERY_TARGET_TIME="2026-04-13 12:00:00"
RECOVERY_DIR="/var/lib/postgresql/recovery"

# Stop the database
systemctl stop postgresql

# Create recovery directory
mkdir -p $RECOVERY_DIR
cp /backups/daily/postgres/database_latest.sql.gz .

# Extract base backup
gunzip database_latest.sql.gz

# Create recovery.conf
cat > /var/lib/postgresql/recovery.conf <<EOF
restore_command = 'cp /archive/%f %p'
recovery_target_timeline = 'latest'
recovery_target_time = '$RECOVERY_TARGET_TIME'
pause_at_recovery_target = on
EOF

# Start recovery
systemctl start postgresql

# Monitor recovery progress (check logs)
tail -f /var/log/postgresql/postgresql.log | grep "recovery"

# Once recovered to target time
psql -c "SELECT pg_wal_replay_resume();"
```

---

## Part IV: Chaos Engineering & Resilience Testing

### Failure Scenarios

#### 1. Database Connection Failure
```bash
# Simulate connection loss
iptables -A OUTPUT -d 192.168.1.20 -p tcp --dport 5432 -j DROP

# Expected behavior:
# - Connection pool exhaustion alerts trigger
# - Failover to read-only replica after 30s
# - API gracefully degrades to read-only mode

# Restore connection
iptables -D OUTPUT -d 192.168.1.20 -p tcp --dport 5432 -j DROP
```

#### 2. Network Partition
```bash
# Simulate network split (primary isolated)
tc qdisc add dev eth0 root netem loss 100%

# Expected behavior:
# - Health checks fail
# - Keepalived promotes backup to primary
# - Clients redirect to new primary via DNS

# Restore network
tc qdisc del dev eth0 root
```

#### 3. Resource Exhaustion
```bash
# Simulate memory pressure
stress-ng --vm 2 --vm-bytes 80% --timeout 5m

# Expected behavior:
# - Memory alerts trigger
# - Cache eviction policies activate
# - Auto-scaling initiates (if configured)
```

### Chaos Test Execution Script (chaos-test.sh)
```bash
#!/bin/bash

echo "=== Chaos Engineering Test Suite ==="
echo "Start time: $(date)"

SCENARIOS=(
  "db-failure"
  "network-partition"
  "cpu-exhaustion"
  "memory-pressure"
  "disk-full"
)

for scenario in "${SCENARIOS[@]}"; do
  echo "Running scenario: $scenario"
  
  case $scenario in
    db-failure)
      # Test database unavailability
      iptables -A OUTPUT -d 192.168.1.20 -p tcp --dport 5432 -j DROP
      sleep 30
      # Verify failover occurred
      curl -s http://localhost:8080/status | jq .database
      iptables -D OUTPUT -d 192.168.1.20 -p tcp --dport 5432 -j DROP
      ;;
    # ... other scenarios
  esac
  
  # Record results
  echo "Scenario: $scenario, Status: PASS" >> /var/log/chaos-results.log
  sleep 60  # Cool-down period
done

echo "End time: $(date)"
echo "Test summary: See /var/log/chaos-results.log"
```

---

## Part V: Observability & Monitoring

### SLO Definitions

| SLI | Target | Error Budget |
|-----|--------|--------------|
| Availability (uptime) | 99.9% | 43.2 minutes/month |
| Latency (p99) | <500ms | 2.5% of requests |
| Error Rate | <0.1% | 1000 errors/day |
| Recovery Time (RTO) | <1 hour | Measured per incident |

### Alert Rules (Prometheus)

```yaml
groups:
  - name: availability
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.001
        for: 5m
        annotations:
          summary: "High error rate detected"

      - alert: ServiceDown
        expr: up{job="code-server"} == 0
        for: 1m
        annotations:
          summary: "Service is down"

  - name: database
    rules:
      - alert: ReplicationLag
        expr: pg_replication_lag > 60
        annotations:
          summary: "Database replication lag > 1 minute"

      - alert: ConnectionPoolExhausted
        expr: pg_stat_activity_count > max_connections * 0.8
        annotations:
          summary: "Connection pool nearly exhausted"
```

---

## Implementation Timeline

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| **Week 1** | Database Replication & Redis Cluster | PostgreSQL standby, Redis cluster verified |
| **Week 2** | Load Balancing & Service Discovery | HAProxy/Caddy configured, Consul operational |
| **Week 3** | Automatic Failover | Keepalived active-passive setup, failover tested |
| **Week 4** | Disaster Recovery | Backup procedures, recovery scripts, offsite sync |
| **Week 5** | Chaos Testing | Test scenarios executed, results documented |
| **Week 6** | Production Validation | Full HA/DR test in production environment |

---

## Validation Checklist

- [ ] PostgreSQL synchronous replication verified
- [ ] Redis cluster health checked (all 6 nodes operational)
- [ ] Load balancer distributes traffic correctly (round-robin verified)
- [ ] Service discovery working (Consul DNS functional)
- [ ] Automatic failover tested (>3 successful failover tests)
- [ ] Backup integrity verified (hourly/daily/weekly all valid)
- [ ] Point-in-time recovery tested (successful restore to target time)
- [ ] Disaster recovery RTO <1 hour (verified in tests)
- [ ] Disaster recovery RPO <15 min (replication lag monitored)
- [ ] Chaos scenarios all pass (database, network, resource failures)
- [ ] Monitoring alerts trigger correctly
- [ ] SLOs documented and tracked

---

## Post-Implementation

1. **Weekly Chaos Test**: Execute one random failure scenario every Friday
2. **Monthly DR Drill**: Full failover and recovery test
3. **Quarterly Review**: Evaluate metrics, update procedures
4. **Training**: Team certification on failover and recovery procedures

---

**Document Status**: Ready for Implementation  
**Last Updated**: April 13, 2026
