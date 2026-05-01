# 24-Hour Post-Deployment Monitoring & Baseline Collection

**Start Date:** May 1, 2026, 1:20 PM EDT  
**Duration:** 24 hours (Until May 2, 2026, 1:20 PM EDT)  
**Status:** NOW ACTIVE  

---

## Monitoring Objectives

### Primary Objectives
1. ✅ Verify platform stability for first 24 hours
2. ✅ Collect baseline performance metrics
3. ✅ Validate high availability functionality
4. ✅ Monitor for any unexpected behavior or errors
5. ✅ Document baseline for future comparisons

### Key Metrics to Track
```
Performance Baselines:
  • Trace throughput:        Target 10,000+ spans/sec
  • Metrics throughput:      Target 100,000+ metrics/sec
  • Query latency (p95):     Target <100ms
  • Dashboard load time:     Target <2 seconds
  • Forecast latency:        Target <500ms

Availability Baselines:
  • Overall system:          Target 99.99%
  • Service availability:    Target 99.95% average
  • Data layer HA:           Target 100% redundancy

Replication Baselines:
  • PostgreSQL replication lag: Target <100ms
  • Redis replication lag:      Target <50ms
  • Redpanda lag:               Target <500ms
```

---

## Monitoring Dashboard Setup

### Prometheus Queries to Configure

#### Infrastructure Metrics
```promql
# CPU Usage
node_cpu_seconds_total{job="node-exporter"}

# Memory Usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk Usage
(1 - (node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"})) * 100

# Network I/O
rate(node_network_receive_bytes_total[5m])
rate(node_network_transmit_bytes_total[5m])
```

#### Service Metrics
```promql
# Docker container status
docker_container_status{job="docker"}

# PostgreSQL connections
postgresql_stat_activity_count

# Redis connected clients
redis_connected_clients

# Prometheus scrape duration
scrape_duration_seconds
```

#### Application Metrics
```promql
# HTTP request rate
rate(http_requests_total[5m])

# Error rate
rate(http_requests_total{status=~"5.."}[5m])

# Request latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Active traces
rate(traces_total[5m])

# Active metrics
rate(metrics_total[5m])
```

---

## Monitoring Checklist (Hourly)

### Hour-By-Hour Verification Points

**Every Hour (on the hour):**
- [ ] Verify all containers still running
- [ ] Check Prometheus scrape success rate (>99%)
- [ ] Verify no error spikes in logs
- [ ] Check replication lag on all HA pairs
- [ ] Monitor disk usage trend
- [ ] Check memory usage trend

**Every 4 Hours:**
- [ ] Run health check script
- [ ] Verify backup jobs completed
- [ ] Check alert configuration (no false positives)
- [ ] Validate trace collection flowing
- [ ] Confirm metrics export working

**Every 8 Hours:**
- [ ] Review error logs for patterns
- [ ] Check for any resource constraints
- [ ] Verify network connectivity stable
- [ ] Validate multi-tenancy isolation
- [ ] Confirm audit logs being collected

---

## Critical Alerts to Monitor

### Immediate Action Required (Page On-Call)
```
1. Service Down
   • Alert: Any critical service unavailable
   • Action: Immediate investigation
   • SLA: < 5 minutes

2. Data Loss Risk
   • Alert: Replication lag > 5 minutes
   • Action: Immediate investigation
   • SLA: < 5 minutes

3. Storage Crisis
   • Alert: Disk > 90% full
   • Action: Manual intervention required
   • SLA: < 15 minutes

4. Memory Crisis
   • Alert: Any node > 95% memory
   • Action: Manual intervention required
   • SLA: < 15 minutes
```

### Warning Alerts (Slack Notification)
```
1. High CPU
   • Alert: Sustained > 80% for 10 minutes
   • Action: Monitor for escalation
   • Check: Is there a workload spike?

2. Memory Warning
   • Alert: > 85% for sustained period
   • Action: Monitor trend
   • Check: Memory leak detection needed?

3. Replication Lag
   • Alert: > 1 minute
   • Action: Check network connectivity
   • Check: Are replicas available?

4. Query Slowdown
   • Alert: > 5% slower than baseline
   • Action: Check database load
   • Check: Need to tune queries?
```

---

## Performance Baseline Collection

### Metrics Collection Strategy

**Frequency:** Every 5 minutes
**Retention:** Full 24-hour dataset
**Storage:** `/home/akushnir/code-server/artifacts/baseline-metrics/`

**Metrics to Collect:**
```
1. Infrastructure Metrics
   • CPU per core
   • Memory (total, used, available, cached)
   • Disk I/O (read, write, queue length)
   • Network (bytes in/out, packets, errors)
   • Load average (1, 5, 15 minute)

2. Container Metrics
   • Memory usage per container
   • CPU usage per container
   • Network traffic per container
   • I/O operations per container

3. Database Metrics
   • PostgreSQL: Connections, queries, transactions
   • Redis: Commands, memory, keys
   • Redpanda: Messages, throughput, lag

4. Application Metrics
   • Request rate (per second)
   • Request latency (p50, p95, p99)
   • Error rate (4xx, 5xx)
   • Trace throughput
   • Metrics throughput

5. System Metrics
   • Uptime
   • Context switches
   • Interrupts
   • Process count
   • File descriptor usage
```

### Baseline File Structure
```
artifacts/baseline-metrics/
├── metrics_2026-05-01T13:25:00Z.json      # Hourly snapshot
├── metrics_2026-05-01T14:25:00Z.json
├── metrics_2026-05-01T15:25:00Z.json
├── ...
├── health_checks/
│   ├── postgresql_2026-05-01T13:25:00Z.log
│   ├── redis_2026-05-01T13:25:00Z.log
│   ├── prometheus_2026-05-01T13:25:00Z.log
│   └── ...
├── replication/
│   ├── postgresql_lag_2026-05-01T13:25:00Z.json
│   ├── redis_lag_2026-05-01T13:25:00Z.json
│   └── ...
└── baseline_summary_2026-05-02.json       # Final analysis
```

---

## Replication & HA Monitoring

### PostgreSQL HA

**Primary Node (192.168.168.31):**
```sql
-- Check replication status
SELECT slot_name, active, restart_lsn FROM pg_replication_slots;

-- Check write lag
SELECT now() - pg_last_xact_replay_timestamp() as replication_lag;

-- Monitor WAL archiving
SELECT name, setting FROM pg_settings WHERE name LIKE '%archive%';
```

**Replica Node (192.168.168.42):**
```sql
-- Verify recovery status
SELECT pg_is_in_recovery();

-- Check applied LSN
SELECT pg_last_wal_receive_lsn();
```

**Monitoring Points:**
- ✅ Replication lag < 100ms
- ✅ All slots active
- ✅ WAL archiving working
- ✅ No connection drops

### Redis HA

**Primary Node (192.168.168.31):**
```bash
redis-cli info replication
redis-cli info stats
```

**Replica Node (192.168.168.42):**
```bash
redis-cli info replication
redis-cli info stats
```

**Monitoring Points:**
- ✅ Replica connected
- ✅ Sync lag < 50ms
- ✅ Commands synchronized
- ✅ No evictions

### Redpanda Cluster

**Cluster Status:**
```bash
docker exec code-server-redpanda rpk cluster health
docker exec code-server-redpanda rpk broker list
```

**Monitoring Points:**
- ✅ All brokers healthy
- ✅ Leaders elected
- ✅ Replicas in sync
- ✅ No under-replicated partitions

---

## Error Pattern Monitoring

### Log Aggregation Points

**PostgreSQL Logs:**
- Connection failures
- Query timeouts
- Replication errors
- Checkpoint warnings
- File I/O errors

**Redis Logs:**
- Memory warnings
- Replication disconnects
- Eviction notices
- AOF rewrites
- Slowlog entries

**Application Logs:**
- Trace export failures
- Metric collection errors
- API errors
- Timeout exceptions
- Memory issues

**System Logs:**
- OOM killer events
- Disk full warnings
- Network interface issues
- Process crashes
- File handle exhaustion

---

## Network & Connectivity Monitoring

### Critical Connections to Monitor
```
1. Primary to Replica
   • PostgreSQL replication: Port 5432
   • Redis replication: Port 6379
   • Redpanda replication: Port 9092
   • Health check: ICMP ping

2. External Connectivity
   • Ingress: Port 80, 443 (Caddy)
   • Metrics export: Port 9100 (Node Exporter)
   • Trace export: Port 14268 (Jaeger)

3. Internal Services
   • Service mesh: Port 9000 (if enabled)
   • Service discovery: Port 8500 (if Consul)
   • Event bus: Port 5672 (RabbitMQ if used)
```

### Network Monitoring Checks
- ✅ Latency between hosts < 10ms
- ✅ Packet loss rate < 0.1%
- ✅ No TCP retransmits
- ✅ No dropped connections
- ✅ Bandwidth utilization reasonable

---

## Post-24-Hour Actions

### Data Analysis
1. Compare actual baseline to expected metrics
2. Identify any anomalies or deviations
3. Document any warnings or concerns
4. Adjust alert thresholds if needed

### Documentation Updates
1. Create baseline metrics report
2. Update runbooks with actual performance
3. Document any surprises found
4. Record lessons learned

### Team Communication
1. Brief operations team on findings
2. Share baseline metrics dashboard
3. Clarify alert response procedures
4. Schedule weekly review meetings

### Next Steps
1. Approve for unrestricted operations (if all good)
2. Schedule first maintenance window
3. Plan Phase 25+ enhancements
4. Begin formal operations handoff

---

## Monitoring Tools & Access

### Grafana Dashboards
- **URL:** http://192.168.168.31:3000
- **Dashboards:**
  - System Overview
  - Application Performance
  - Database Metrics
  - Network Traffic
  - Trace Analysis
  - HA Status

### Prometheus
- **URL:** http://192.168.168.31:9090
- **Query:** Custom PromQL queries
- **Retention:** 15 days (default)

### Jaeger Tracing
- **URL:** http://192.168.168.31:16686
- **Features:** Trace search, flame graphs, latency analysis

### AlertManager
- **URL:** http://192.168.168.31:9093
- **Routing:** Slack, email, PagerDuty

---

## Contact & Escalation

**Monitoring Period:** May 1-2, 2026  
**Primary Contact:** ops-team@example.com  
**Escalation:** platform-eng@example.com  
**Emergency:** incidents@example.com  

---

**Status:** Baseline collection active  
**Start:** May 1, 2026, 1:20 PM EDT  
**Expected Completion:** May 2, 2026, 1:20 PM EDT  
**Estimated Duration:** 24 hours  
