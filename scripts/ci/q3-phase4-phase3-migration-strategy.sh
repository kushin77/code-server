#!/bin/bash
################################################################################
# Q3 Phase 4: Phase 3 Stateful Services Migration Strategy
# @governance IaC, immutable, idempotent, environment-driven
# @purpose Define migration procedures for stateful services (PostgreSQL, Redis, Kafka)
# @phase Q3 Phase 4 - Phase 3 (May 27 - Jun 9, 2026)
# @date $(date '+%Y-%m-%d %H:%M:%S')
################################################################################

set -euo pipefail
IFS=$'\n\t'

# Source environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

# Configuration
OUTPUT_DIR="${PROJECT_ROOT}/artifacts/q3-phase4-phase3"
TIMESTAMP=$(date '+%Y-%m-%d')
REPORT_FILE="${OUTPUT_DIR}/PHASE3-MIGRATION-STRATEGIES-${TIMESTAMP}.md"

mkdir -p "${OUTPUT_DIR}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$@"
}

log_success() {
    printf "${GREEN}[✓]${NC} %s\n" "$@"
}

log_warning() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$@"
}

log_error() {
    printf "${RED}[✗]${NC} %s\n" "$@"
}

################################################################################
# Generate Phase 3 Migration Strategy Report
################################################################################

generate_migration_strategy_report() {
    cat > "${REPORT_FILE}" << 'REPORT'
# Phase 3 - Stateful Services Migration Strategy

**Generated**: $(date '+%Y-%m-%d %H:%M:%S')  
**Status**: STRATEGY COMPLETE  
**Phase**: Q3 Phase 4 - Phase 3 (May 27 - Jun 9, 2026)  
**Complexity**: HIGH (data migration, streaming replication, zero-data-loss requirement)

---

## Executive Summary

Phase 3 migrates critical stateful services from Docker Compose to Kubernetes with zero data loss. Focuses on PostgreSQL (primary application database), Redis (session/cache layer), and Kafka/Redpanda (event streaming). Two-week timeline with daily validation checkpoints and automated rollback procedures.

---

## 3 Stateful Services in Scope

### 1. PostgreSQL (PRIMARY)
- **Replicas**: 3 (Primary + 2 Standbys in HA configuration)
- **Data Size**: ~500GB application database
- **Strategy**: Streaming Replication with zero downtime
- **Recovery Point Objective (RPO)**: < 1 second
- **Recovery Time Objective (RTO)**: < 5 minutes
- **Validation**: Checksum verification, transaction log consistency

### 2. Redis (SESSION/CACHE)
- **Replicas**: 2 (Primary + 1 Standby)
- **Data Size**: ~50GB in-memory cache
- **Strategy**: RDB Snapshot + AOF (Append-Only File) for durability
- **Recovery Point Objective (RPO)**: < 1 minute
- **Recovery Time Objective (RTO)**: < 1 minute
- **Validation**: Memory content verification, key expiration testing

### 3. Kafka/Redpanda (EVENT STREAMING)
- **Brokers**: 3 nodes for fault tolerance
- **Topic Replication**: RF=3 (replication factor)
- **Data Size**: ~200GB event logs
- **Strategy**: Consumer lag monitoring during migration
- **Recovery Point Objective (RPO)**: < 5 seconds
- **Recovery Time Objective (RTO)**: < 2 minutes
- **Validation**: Message sequence verification, offset tracking

---

## PostgreSQL Migration (Days 1-4)

### Pre-Migration Setup (Day 1)

**Morning (2 hours)**:
1. Create PostgreSQL StatefulSet manifest in Kubernetes
2. Create PersistentVolume (500GB SSD)
3. Create Secrets for credentials (stored in sealed-secrets)
4. Configure streaming replication parameters
5. Deploy PostgreSQL primary pod to Kubernetes (read-only initially)

**Afternoon (2 hours)**:
1. Enable streaming replication from Docker Compose PostgreSQL to K8s pod
2. Verify WAL (Write-Ahead Log) shipping working
3. Monitor replication lag (should be < 100ms)
4. Take baseline backup of Docker Compose database
5. Create recovery procedure documentation

### Standby Promotion (Days 2-3)

**Day 2: Deploy Standby 1**:
1. Clone from primary (via pg_basebackup)
2. Start standby in hot standby mode
3. Verify replication lag < 50ms
4. Test failover procedure (manual)
5. Switch traffic monitoring to K8s replica 1

**Day 3: Deploy Standby 2**:
1. Clone from primary
2. Configure for HA quorum
3. Set up automatic failover via Patroni or etcd
4. Test full HA failover scenario
5. All 3 replicas in sync before cutover

### Production Cutover (Day 4)

**Morning (1 hour)**:
1. Stop all writes to Docker Compose PostgreSQL (read-only mode)
2. Wait for replication lag to reach zero
3. Verify all transactions replicated to Kubernetes

**Cutover (15 minutes)**:
1. Stop applications connecting to old database
2. Promote Kubernetes primary to writable
3. Update connection strings in all services
4. Redirect new writes to Kubernetes PostgreSQL
5. Verify write operations succeeding

**Validation (1 hour)**:
1. Run data integrity checks (row counts, checksums)
2. Verify no transaction loss (log sequence numbers)
3. Execute integration tests (schema validation)
4. Monitor replication with standby nodes
5. Document cutover completion timestamp

### Rollback Procedure (< 5 minutes)

If failures detected:
1. Stop all writes to Kubernetes PostgreSQL
2. Demote K8s primary back to standby
3. Promote Docker Compose standby to primary
4. Reconnect applications to old database
5. Investigate failure root cause

---

## Redis Migration (Days 5-7)

### Pre-Migration Setup (Day 5)

**Morning (1 hour)**:
1. Create Redis StatefulSet with PersistentVolume (50GB SSD)
2. Create Secrets for authentication
3. Configure RDB persistence (snapshots every 5 min)
4. Enable AOF (Append-Only File) for durability
5. Deploy Kubernetes Redis pod (initial empty state)

**Afternoon (1 hour)**:
1. Configure Redis replication from Docker Compose to K8s
2. Monitor replication offset synchronization
3. Verify no evicted keys during initial sync
4. Take snapshot of Docker Compose Redis
5. Load snapshot into Kubernetes Redis

### Data Synchronization (Days 6-7)

**Day 6: Live Replication**:
1. Configure Redis REPLICAOF to Docker Compose instance
2. Monitor slave offset catching up
3. Watch for memory pressure in Kubernetes pod
4. Verify no keys expiring during sync
5. Gradual traffic redirection (10% read requests → K8s)

**Day 7: Cutover**:
1. Pause write operations (brief 5-second window)
2. Verify master/replica offset equal
3. Promote Kubernetes Redis from slave to master
4. Update connection strings in application pods
5. Monitor connection pool adaptation
6. Gradually increase traffic percentage (25% → 50% → 100%)

### Validation (Continuous)

1. Cache hit ratio maintained (> 95%)
2. Response latencies < 10ms p99
3. Memory utilization stable
4. No connection errors observed
5. Session persistence verified

### Rollback Procedure (< 1 minute)

1. Demote Kubernetes Redis to slave status
2. Promote Docker Compose Redis to master
3. Clear Kubernetes cache (full rebuild on failback)
4. Redirect connections back to Docker Compose
5. Monitor application behavior stabilization

---

## Kafka/Redpanda Migration (Days 8-10)

### Pre-Migration Setup (Day 8)

**Morning (1 hour)**:
1. Create Redpanda StatefulSet (3 brokers)
2. Create PersistentVolumes (200GB each)
3. Configure authentication and TLS
4. Create initial topics in Kubernetes cluster
5. Set replication factor = 3 for all topics

**Afternoon (1 hour)**:
1. Enable MirrorMaker 2 to replicate topics Docker Compose → K8s
2. Configure consumer offset tracking
3. Monitor sync progress for all topics
4. Verify message order preservation (essential!)
5. Create offset reset procedure

### Consumer Migration (Days 9-10)

**Day 9: Read-Only Phase**:
1. Deploy MirrorMaker 2 replicating all topics
2. Create consumer group in Kubernetes cluster
3. Configure offset sync between clusters
4. Start consumer lag monitoring (both clusters)
5. Verify no message loss (checksum validation)

**Day 10: Producer Cutover**:
1. Redirect producers to Kubernetes Redpanda (5% traffic)
2. Monitor new message ingestion rate
3. Verify consumers still reading from Docker Compose (backfill)
4. Gradually increase producer traffic (25% → 50% → 100%)
5. Consumers will catch up automatically

### Validation (Continuous)

1. Message ordering preserved per partition
2. No duplicate messages (idempotent production)
3. End-to-end latency acceptable (< 100ms p99)
4. Consumer lag < 10 seconds for all groups
5. Dead letter queue empty (all messages processed)

### Rollback Procedure (< 2 minutes)

1. Pause producer writes (brief pause)
2. Switch producers back to Docker Compose Kafka
3. Keep MirrorMaker running for data sync
4. Monitor consumer lag on Docker Compose topic
5. Continue mirroring for safety period (24 hours)

---

## Phase 3 Daily Timeline

| Day | Date | Services | Duration | Status |
|-----|------|----------|----------|--------|
| 1 | May 27 | PostgreSQL setup | 4 hours | Setup + Replication |
| 2 | May 28 | PostgreSQL standby 1 | 4 hours | HA failover testing |
| 3 | May 29 | PostgreSQL standby 2 | 4 hours | Full HA ready |
| 4 | May 30 | PostgreSQL cutover | 3 hours | Production traffic |
| 5 | May 31 | Redis setup | 2 hours | Initial deployment |
| 6 | Jun 1 | Redis sync | 4 hours | Live replication |
| 7 | Jun 2 | Redis cutover | 2 hours | Production traffic |
| 8 | Jun 3 | Kafka setup | 2 hours | Initial deployment |
| 9 | Jun 4 | Kafka consumer | 4 hours | Consumer group creation |
| 10 | Jun 5-9 | Kafka cutover + validation | 5 hours/day | Producer switch + monitoring |

---

## Risk Assessment

### HIGH Risk Items

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Data corruption during migration | Low | CRITICAL | Checksum verification, transaction logs |
| Network partition during cutover | Low | HIGH | Automated failover, manual override |
| Consumer lag during Kafka cutover | Medium | MEDIUM | MirrorMaker offset tracking, lag monitoring |

### Mitigation Strategies

1. **Data Corruption**: Parallel run both clusters for 48 hours post-cutover before decommissioning old services
2. **Network Partition**: Manual quorum-based decision (majority of team agree on cutover)
3. **Consumer Lag**: Monitor offset sync real-time, hold cutover if lag > 5 seconds

---

## Post-Migration Validation (Jun 6-9)

### Database Verification
- ✅ Row count matches (exact)
- ✅ Checksum matches (table by table)
- ✅ Indexes properly built
- ✅ Constraints enforced
- ✅ Sequences at correct values

### Cache Verification
- ✅ Memory usage stable
- ✅ Hit ratio > 95%
- ✅ No stale data observed
- ✅ Session integrity verified
- ✅ TTL expiration working

### Event Stream Verification
- ✅ Message ordering preserved
- ✅ No duplicates (offset-based dedup)
- ✅ All consumers caught up
- ✅ Dead letter queue empty
- ✅ End-to-end latency acceptable

---

## Success Criteria (Jun 9)

✅ All 3 stateful services running on Kubernetes (zero downtime)  
✅ Zero data loss (verified by checksums and transaction logs)  
✅ Zero unplanned downtime (< 1 second per service)  
✅ Replication lag < 100ms (PostgreSQL streaming)  
✅ Cache hit ratio maintained (> 95%)  
✅ Message ordering preserved (Kafka/Redpanda)  
✅ All services health checks passing  
✅ Team confident in operation (all procedures tested)  
✅ Phase 4 (full production cutover) approved  

---

## Phase 4 Transition (Jun 10-23)

**Final Production Cutover**: Docker Compose services decommissioned  
**Full Kubernetes Production**: All services running on K8s (100% traffic)  
**Disaster Recovery**: Final testing of multi-region failover  

---

## Conclusion

Phase 3 successfully migrates stateful infrastructure to Kubernetes with zero data loss. Careful sequencing (PostgreSQL first for data consistency, then Redis for caching, finally Kafka for events) minimizes blast radius. Comprehensive validation at each step ensures production readiness.

**Status**: Strategy COMPLETE and READY FOR EXECUTION  
**Execution Window**: May 27 - Jun 9, 2026  
**Team Confidence Level**: HIGH (based on Phase 2 success)  

REPORT

    log_success "Phase 3 migration strategy report generated"
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "Starting Phase 3 Stateful Services Migration Strategy generation..."
    
    log_info "Generating comprehensive migration strategy..."
    generate_migration_strategy_report
    
    log_success "Phase 3 migration strategy complete!"
    log_success "Report: ${REPORT_FILE}"
    
    return 0
}

# Execute
main "$@"
exit $?
