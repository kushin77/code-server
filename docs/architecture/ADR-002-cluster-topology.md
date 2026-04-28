# ADR: Cluster Topology Decision — Active-Passive vs Active-Active

**Status:** PROPOSED  
**Date:** 2026-04-28  
**Issue:** P1 #2425 - Replica host runs identical compose profiles with no state reconciliation  
**Author:** Autonomous Agent  
**Deciders:** Infrastructure Team

## Context

Currently, the deployment has two hosts:
- **Primary:** `192.168.168.31` (`dev-elevatediq`)
- **Replica:** `192.168.168.42` (`dev-elevatediq-2`)

**Current State:** Both hosts run identical `docker-compose` with all profiles (`ai`, `governance`, `infrastructure`, `all`), resulting in:
- Two independent copies of stateful services (postgres, redis, qdrant, minio)
- No replication channel between the databases
- No shared load balancer handling failover
- Container sets already diverge without any detection

This is **neither true active-active nor proper active-passive** — it's two independent stacks that happen to share a name.

## Decision Needed

Choose the cluster topology:

### Option 1: Active-Passive Failover (Recommended for Phase 1)

**Architecture:**
```
┌─ Primary (active) ─────────┐
│ All 41 services running    │
│ Handles all traffic        │
│ Replicates to Secondary    │
└────────────────────────────┘
         ↓ replication
┌─ Replica (standby) ───────┐
│ 41 services ready but      │
│ NOT handling traffic       │
│ Read-only replicas         │
└────────────────────────────┘
```

**Failover Trigger:** Primary health check fails → DNS switches → Replica becomes primary

**Pros:**
- ✅ Simple architecture, well-tested patterns
- ✅ Clear replication topology (primary → replica)
- ✅ Consistent state (replica always lags but follows primary)
- ✅ No split-brain risk (only one active writer)
- ✅ Can implement quickly with Patroni (PostgreSQL) + Redis Sentinel

**Cons:**
- ❌ Replica resources underutilized in steady state
- ❌ Failover has RTO ~30-60s (DNS propagation)
- ❌ No write-affinity routing

**Implementation:**
- PostgreSQL: Patroni + etcd for automated failover
- Redis: Redis Sentinel with witness node
- DNS: TTL 30s, health-check based switching
- Application: Connection pooling with failover support

**Timeline:** 2-3 weeks

---

### Option 2: Active-Active Clustering (Future Phase)

**Architecture:**
```
┌─ Load Balancer (VIP) ──────────────┐
│ Distributes read traffic across    │
│ Primary and Replica                │
└────────────────────────────────────┘
   ↙                            ↖
Primary (active)           Replica (active)
- All 41 services         - All 41 services
- Single write leader     - Reads only
(CockroachDB/Vitess style)
```

**Failover Trigger:** Primary fails → Quorum elects replica as leader → LB routes to new leader

**Pros:**
- ✅ Both hosts utilized (read distribution)
- ✅ Better resource efficiency
- ✅ Sub-second automatic failover (quorum-based)

**Cons:**
- ❌ Complex: requires distributed consensus (Raft, Paxos)
- ❌ Split-brain risk if not properly implemented
- ❌ Operational complexity (monitor quorum health)
- ❌ Application must handle dual writers (conflict resolution)

**Implementation:**
- PostgreSQL: CockroachDB or Vitess (distributed SQL)
- Redis: Redis Cluster mode (shard + replicate)
- Consensus: Raft-based leader election (Patroni with HA, or etcd)
- Application: Multi-master prepared for conflicts

**Timeline:** 6-8 weeks

---

## Decision

**RECOMMEND: Option 1 (Active-Passive) for Phase 1 Deployment**

**Rationale:**
1. **Risk Mitigation:** One clear authoritative state (primary), no conflict resolution needed
2. **Timeline:** Achievable in 2-3 weeks with Patroni + Sentinel
3. **Operational:** Simpler monitoring, clear responsibility ownership
4. **Proven Patterns:** Active-passive is industry-standard for 99.99% SLA
5. **Roadmap:** Can evolve to active-active in Phase 3-4 once data consistency patterns proven

**Future Evolution:** Opt for active-active in Phase 4 once:
- Multi-region failover requirements emerge
- Read scaling needs exceed single-host capacity
- Team has operational confidence with distributed consensus

## Implementation Plan (Active-Passive)

### Phase 1a: PostgreSQL Failover (Week 1-2)

```hcl
# Deploy Patroni HA orchestrator
resource "docker_container" "patroni_primary" {
  ...
  environment = [
    "PATRONI_SCOPE=code-server-db-cluster",
    "PATRONI_TTL=30",
    "PATRONI_LOOP_WAIT=10",
    "PATRONI_MAXIMUM_LAG_ON_FAILOVER=1048576"
  ]
}

# Deploy etcd for distributed consensus
resource "docker_container" "etcd" {
  # 3-node cluster for quorum
}
```

**Validation:**
- Promote replica: `patronictl switchover`
- Verify writes go to new primary: `SELECT pg_stat_replication`
- Test RTO: measure time from failure detection to write availability

### Phase 1b: Redis Failover (Week 2)

```hcl
resource "docker_container" "redis_sentinel" {
  # 3 Sentinel instances
  # Monitors Redis primary + replica
  # Elects new primary on failure
}
```

**Validation:**
- Kill Redis primary: `docker kill redis`
- Sentinel elects replica as new primary < 3s
- Application reconnects automatically

### Phase 1c: DNS & Load Balancer Failover (Week 2-3)

```hcl
# Caddy health-check based upstream failover
# Updates DNS on primary failure
resource "aws_route53_health_check" "primary" {
  # Health checks /health endpoint
  # Fails if timeout > 5s or HTTP != 200
}

resource "aws_route53_record" "cluster_vip" {
  # Updates A record: primary → replica if health check fails
  # TTL=30s for fast propagation
}
```

**Validation:**
- Kill primary: `ssh primary 'sudo shutdown -h now'`
- Verify DNS switches to replica < 30s
- All traffic routes to replica
- Test write failover: applications retry on failure

### Phase 1d: Cluster Health Monitoring & Alerts (Week 3)

```hcl
# Add to prometheus/alertmanager
- alert: PostgreSQL_FailoverTimeoutWarning
  if: patroni_failover_time_seconds > 10
  annotations:
    summary: "PostgreSQL failover took {{ $value }}s (target: <5s)"

- alert: Redis_SentinelQuorumLost
  if: redis_sentinel_masters < 1
  annotations:
    summary: "Redis Sentinel lost quorum"
```

## ADR Outcome: Active-Passive Cluster

**Decision:** Implement active-passive PostgreSQL/Redis failover using:
1. **PostgreSQL:** Patroni + etcd for leader election
2. **Redis:** Redis Sentinel with witness node
3. **DNS:** Route53 health check based A record switching
4. **Application:** Connection pooling + retry on disconnect

**Success Criteria:**
- ✅ Failover time (RTO): < 30 seconds
- ✅ Replication lag: < 1 second
- ✅ Data loss (RPO): 0 seconds (synchronous replication)
- ✅ Monitoring: Patroni + Sentinel + Prometheus alerts
- ✅ Failover drills: Automated monthly via `scripts/phase6/enable-failover-drills.sh`

**Next Ticket:** Implement PostgreSQL Patroni failover (Week 1)
