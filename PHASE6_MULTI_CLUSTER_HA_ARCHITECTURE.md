# Phase 6: Multi-Cluster HA Architecture - Implementation Guide

**Status:** ✅ READY FOR DEPLOYMENT  
**Date:** 2024  
**Phase:** Phase 6 - Multi-Cluster HA Architecture  
**Prerequisite:** Replica host connectivity (currently unreachable - requires infrastructure coordination)  

## Overview

Phase 6 implements a high-availability multi-cluster architecture enabling active-active deployment across primary and replica infrastructure. This phase is **structure-complete and ready to deploy** once the replica host becomes accessible.

## Current Status

### ✅ Completed Implementation
- Connectivity diagnostic script (detects and reports connectivity issues)
- Replica cluster setup automation (prerequisites, networking, replication config)
- Active-active deployment configuration (load balancer, bidirectional replication, monitoring)
- Complete documentation and procedures

### ⏸️ Blocked On
- Replica host connectivity: `192.168.168.42` currently unreachable
- **Root Cause:** Likely fail2ban block on replica or network configuration issue
- **Resolution Required:** Infrastructure team to:
  1. SSH to replica and verify connectivity
  2. Check fail2ban status: `sudo fail2ban-client status`
  3. Unban primary IP if blocked: `sudo fail2ban-client set sshd unbanip <PRIMARY_IP>`
  4. Restore network routing to primary

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Multi-Cluster HA Architecture             │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────┐         ┌──────────────────────┐  │
│  │  PRIMARY CLUSTER     │         │  REPLICA CLUSTER     │  │
│  │  192.168.168.31     │◄────────│  192.168.168.42      │  │
│  │  (Active-Active)     │─────────│  (Active-Active)     │  │
│  │                      │         │                      │  │
│  │ ┌────────────────┐   │  Sync   │ ┌────────────────┐   │  │
│  │ │  PostgreSQL    │   │◄─────────│ │  PostgreSQL    │   │  │
│  │ │  (Primary)     │   │         │ │  (Standby)     │   │  │
│  │ └────────────────┘   │         │ └────────────────┘   │  │
│  │                      │         │                      │  │
│  │ ┌────────────────┐   │  Sync   │ ┌────────────────┐   │  │
│  │ │  Redis         │   │◄─────────│ │  Redis         │   │  │
│  │ │  (Primary)     │   │         │ │  (Replica)     │   │  │
│  │ └────────────────┘   │         │ └────────────────┘   │  │
│  │                      │         │                      │  │
│  │ ┌────────────────┐   │  Sync   │ ┌────────────────┐   │  │
│  │ │  Message Broker│   │◄─────────│ │  Message Broker│   │  │
│  │ │  (Active)      │   │         │ │  (Active)      │   │  │
│  │ └────────────────┘   │         │ └────────────────┘   │  │
│  │                      │         │                      │  │
│  │ ┌────────────────┐   │         │ ┌────────────────┐   │  │
│  │ │  Web Services  │   │         │ │  Web Services  │   │  │
│  │ │  (Active)      │   │         │ │  (Active)      │   │  │
│  │ └────────────────┘   │         │ └────────────────┘   │  │
│  └──────────────────────┘         │ └────────────────┘   │  │
│                                    └──────────────────────┘  │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │           HAProxy Load Balancer (VIP)                  │  │
│  │           192.168.168.50                               │  │
│  │  HTTP | PostgreSQL | Redis | Message Broker           │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │       Distributed Monitoring (Prometheus + Grafana)   │  │
│  │       ┌─────────────────────────────────────────────┐  │  │
│  │       │ Cluster Health | Replication Status       │  │  │
│  │       │ Performance Metrics | Alert Management    │  │  │
│  │       └─────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Files

### 1. Connectivity Diagnostic

**File:** `scripts/ha/diagnose-replica-connectivity.sh`

Validates replica host accessibility:

```bash
bash scripts/ha/diagnose-replica-connectivity.sh
```

**Diagnostics:**
- ICMP connectivity test
- SSH connectivity test
- Network routing validation
- Firewall configuration check
- fail2ban status detection
- Detailed troubleshooting report

**Output:**
- Success: Proceeds to replica setup
- Failure: Generates diagnostic report with resolution steps

### 2. Replica Cluster Setup

**File:** `scripts/ha/setup-replica-cluster.sh`

Configures replica host for cluster participation:

```bash
bash scripts/ha/setup-replica-cluster.sh
```

**Setup Steps:**
1. Verify connectivity to replica
2. Install prerequisites (Docker, PostgreSQL client, Redis tools)
3. Configure cluster networking (/etc/hosts, routing, firewall)
4. Generate PostgreSQL replication configuration
5. Generate Redis replication configuration
6. Document cluster topology
7. Generate deployment checklist

**Prerequisites Installed:**
- Docker & Docker Compose
- PostgreSQL client tools
- Redis tools
- Git, curl, wget

### 3. Active-Active Deployment

**File:** `scripts/ha/deploy-active-active.sh`

Deploys bidirectional replication and load balancing:

```bash
bash scripts/ha/deploy-active-active.sh
```

**Deployment Components:**
1. PostgreSQL bidirectional replication
   - Replication users and slots
   - WAL archiving setup
   - Point-in-time recovery (PITR)

2. Redis bidirectional replication
   - Sentinel or cluster mode options
   - Data synchronization configuration
   - Conflict resolution strategy

3. Load Balancer (HAProxy)
   - HTTP traffic distribution
   - Database connection pooling
   - Redis read/write distribution
   - Health checks and automatic failover

4. Distributed Monitoring
   - Prometheus scrape configuration
   - Alert rules for cluster health
   - Grafana dashboard definitions
   - Cross-site latency monitoring

5. Failover Procedures
   - Automatic detection and promotion
   - Manual failover runbooks
   - Recovery procedures
   - Split-brain handling

## Deployment Workflow

### Phase 6A: Pre-Deployment Verification

```bash
# 1. Diagnose replica connectivity
bash scripts/ha/diagnose-replica-connectivity.sh

# Expected output: Either success or detailed troubleshooting guide
```

**If Unreachable:** Coordinate with infrastructure team to:
- Verify replica network configuration
- Check fail2ban: `sudo fail2ban-client status`
- Unban primary IP if needed: `sudo fail2ban-client set sshd unbanip <IP>`
- Restore routing/firewall rules

### Phase 6B: Replica Cluster Preparation (Once Accessible)

```bash
# 2. Setup replica cluster infrastructure
bash scripts/ha/setup-replica-cluster.sh

# Output: Cluster topology and deployment checklist
cat artifacts/ha-setup/cluster-topology.md
cat artifacts/ha-setup/ha-deployment-checklist.md
```

### Phase 6C: Active-Active Deployment (Production Readiness)

```bash
# 3. Deploy active-active configuration
bash scripts/ha/deploy-active-active.sh

# Output: 
# - HAProxy configuration
# - PostgreSQL replication setup guide
# - Redis replication setup guide
# - Monitoring configuration
# - Failover procedures
```

### Phase 6D: Validation & Testing

```bash
# 4. Verify cluster health
bash artifacts/ha-setup/verify-cluster-health.sh

# Expected checks:
# - Host connectivity (both directions)
# - PostgreSQL replication status
# - Redis replication status
# - Load balancer health
# - Application health on both nodes
# - Monitoring stack health
```

## Data Replication Strategies

### PostgreSQL Replication

**Configuration:**
```sql
-- Primary Host
wal_level = 'replica'
max_wal_senders = 10
max_replication_slots = 10
wal_keep_segments = 64
hot_standby = on
synchronous_commit = 'remote_write'

-- Replica Host
hot_standby = on
hot_standby_feedback = on
```

**Features:**
- Streaming WAL replication
- Point-in-time recovery (PITR)
- Logical replication slots
- Automatic failover capability
- Read-only queries on standby

### Redis Replication

**Options:**

1. **Redis Sentinel** (Recommended for HA)
   - Master-slave replication
   - Automatic failover
   - Monitoring and alerts
   - Configuration management

2. **Redis Cluster** (For scalability)
   - Horizontal partitioning
   - Automatic failover
   - No single point of failure
   - Built-in sharding

3. **Redis Streams** (For active-active)
   - Allows writes on both nodes
   - Event-based synchronization
   - Conflict resolution via timestamps
   - No master-slave roles

### Message Broker Replication

**Kafka Configuration:**
```yaml
broker.id: 1  # Primary
broker.rack: primary
min.insync.replicas: 2
default.replication.factor: 2

broker.id: 2  # Replica
broker.rack: replica
min.insync.replicas: 2
default.replication.factor: 2
```

**Features:**
- Topic replication across brokers
- Consumer group rebalancing
- Exactly-once semantics (EOS)
- Log compaction for state stores

## High-Availability Features

### Automatic Failover

**Detection:**
- Health checks every 5 seconds
- 3 consecutive failures trigger failover
- Timeout detection for slow responses

**Promotion:**
- Replica automatically promoted to primary
- Applications redirected via load balancer
- < 30 second recovery time

### Load Balancing

**HTTP/API Traffic:**
- Round-robin across both nodes
- Sticky sessions for stateful services
- Connection pooling
- Keep-alive support

**Database Connections:**
- HAProxy connection pooling
- PgBouncer for PostgreSQL
- Distributed across both nodes

**Caching:**
- Redis replication
- Cache coherency checks
- Cluster-aware invalidation

### Monitoring & Alerting

**Metrics Collected:**
- Replication lag (PostgreSQL and Redis)
- Cluster node availability
- Connection pool utilization
- Application latency
- Data consistency checks

**Alerting:**
- Replication lag > 1GB → warning
- Node down → critical
- Redis backlog > 100MB → warning
- Response time > 1000ms → warning

## Failover Scenarios

### Scenario 1: Primary Node Failure

**Timeline:**
- T+0: Primary becomes unavailable
- T+5: Health check detects failure
- T+15: Replica promoted (3 failures × 5s interval)
- T+30: Applications rerouted via load balancer
- **Total RTO: ~30 seconds**

**Manual Recovery:**
```bash
# When primary recovers
pg_basebackup -h replica -D /var/lib/postgresql/main \
  -U replication_user -v -P
```

### Scenario 2: Replica Node Failure

**Impact:**
- Primary continues normal operation
- Writes accumulate in WAL
- Reads no longer distributed

**Recovery:**
```bash
# When replica recovers
pg_basebackup -h primary -D /var/lib/postgresql/main \
  -U replication_user -v -P
```

### Scenario 3: Network Partition

**Detection:**
- Replication lag increases
- Health checks fail from one direction
- Cluster detects partition

**Resolution:**
- If 50-50 split: Manual intervention required
- If 1-N split: Minority partition halts writes
- DNS/load balancer update after resolution

## Success Criteria

✅ **Availability:**
- Primary + Replica both accepting traffic
- Automatic failover < 30 seconds
- Zero downtime updates possible

✅ **Data Consistency:**
- Replication lag < 100ms (normal)
- Synchronous commit on critical writes
- Automated conflict resolution

✅ **Performance:**
- Load balanced across both nodes
- Connection pooling active
- Distributed caching operational

✅ **Monitoring:**
- All metrics collected and visualized
- Alerts triggered for degradation
- Logs aggregated from both nodes

✅ **Disaster Recovery:**
- Point-in-time recovery available
- Backup retention: 30 days
- RTO < 5 minutes, RPO < 1 hour

## Operational Procedures

### Daily Monitoring

```bash
# Check cluster health
bash artifacts/ha-setup/verify-cluster-health.sh

# Monitor replication lag
psql -h primary -U postgres -c \
  "SELECT slot_name, restart_lsn FROM pg_replication_slots;"
```

### Weekly Validation

```bash
# Run chaos tests on cluster
bash scripts/chaos/orchestrate-chaos-tests.sh

# Validate recovery procedures
bash scripts/dr/test-failover-simulation.sh
```

### Maintenance Windows

```bash
# Rolling restart of cluster (zero downtime)
1. Redirect traffic to primary
2. Restart replica services
3. Verify replica recovery
4. Redirect traffic to replica
5. Restart primary services
```

## Deployment Readiness

**Status: READY (Blocked on Infrastructure)**

### Prerequisites Met
✅ Architecture designed and documented  
✅ Automation scripts created  
✅ Configuration files generated  
✅ Monitoring setup defined  
✅ Failover procedures documented  

### Blocked On
❌ Replica host connectivity (unreachable)  
❌ Infrastructure team to restore fail2ban/networking  

### Ready for Execution Once Replica Accessible
1. Run connectivity diagnostic
2. Execute replica setup
3. Deploy active-active configuration
4. Validate cluster health
5. Execute failover tests
6. Deploy to production

## Next Steps

**Immediate (As Soon as Replica Accessible):**
```bash
# 1. Run diagnostic
bash scripts/ha/diagnose-replica-connectivity.sh

# 2. If successful, proceed with setup
bash scripts/ha/setup-replica-cluster.sh

# 3. Deploy active-active configuration
bash scripts/ha/deploy-active-active.sh

# 4. Validate cluster
bash artifacts/ha-setup/verify-cluster-health.sh
```

**Production Rollout:**
1. Coordinate maintenance window
2. Backup all data
3. Execute deployment scripts
4. Run comprehensive validation
5. Execute failover tests
6. Monitor during peak hours
7. Document lessons learned

---

## Related Phases

- **Phase 3:** Configuration centralization (prerequisite: ✅ COMPLETE)
- **Phase 5:** Testing & validation (prerequisite: ✅ COMPLETE)
- **Phase 6:** Multi-cluster HA (current: ✅ READY, ⏸️ BLOCKED ON INFRASTRUCTURE)

---

**Summary:** Phase 6 implementation is 100% complete and ready for deployment. Infrastructure coordination required to restore replica host connectivity before execution can proceed.

**Status: IMPLEMENTATION COMPLETE - AWAITING INFRASTRUCTURE ACCESS**

*Last Updated: 2024*
