# Monitoring & Observability Operations Guide

**Document Version**: 1.0  
**Last Updated**: April 29, 2026  
**Status**: READY FOR OPERATIONS  
**Maintained By**: Operations Team / Site Reliability Engineer  

---

## Executive Summary

This guide provides comprehensive monitoring, observability, and alerting procedures for the code-server enterprise platform. It covers:
- ✅ Access to monitoring dashboards and tools
- ✅ Key metrics to monitor and interpret
- ✅ Alert configuration and escalation
- ✅ Troubleshooting via logs and metrics
- ✅ Performance baselining and trending
- ✅ SLA/SLO tracking

**Monitoring Stack**:
- Prometheus (metrics collection): 192.168.168.31:9090
- Grafana (visualization): 192.168.168.31:3000
- Loki (log aggregation): 192.168.168.31:3100
- Tempo (distributed tracing): 192.168.168.31:3200-3201
- AlertManager (alert routing): 192.168.168.31:9093

**Key Metrics Targets**:
- Availability: 99.99%
- RTO (failover): 2-3 minutes
- RPO (data loss): < 5 minutes
- Response Time: < 200ms (p95)
- Error Rate: < 0.1%

---

## Part 1: Monitoring Dashboard Access

### 1.1 Prometheus

**Purpose**: Metrics collection and querying  
**URL**: http://192.168.168.31:9090  
**Default Auth**: No authentication (configure if needed)

**Key Pages**:
- `Status → Targets`: View scraped targets (40+ exporters)
- `Status → Service Discovery`: Automatic service discovery status
- `Alerts`: Current active alerts
- `Graph`: Custom metric queries
- `Query Range`: Time-series analysis

**Common Prometheus Queries**:
```promql
# Container health (all running)
up{job="docker"} == 1

# CPU usage by container
rate(container_cpu_usage_seconds_total[5m])

# Memory usage by container
container_memory_usage_bytes / 1024 / 1024 / 1024

# Network I/O
rate(container_network_receive_bytes_total[5m])

# Disk usage
node_filesystem_avail_bytes{mountpoint="/"} / 1024 / 1024 / 1024

# PostgreSQL connections
pg_stat_activity_count

# PostgreSQL replication lag
pg_replication_lag_seconds

# Redis memory usage
redis_memory_used_bytes / 1024 / 1024 / 1024
```

### 1.2 Grafana

**Purpose**: Visualization dashboards and alerting  
**URL**: http://192.168.168.31:3000  
**Default Credentials**: admin / (check secrets vault)  
**Auth**: LDAP/OAuth2 (configure for team)

**Pre-built Dashboards**:
1. **Container Health** - All 87/88 containers status
   - Container count trend
   - CPU/Memory/Disk usage over time
   - Restart frequency
   - Health check status

2. **PostgreSQL** - Database performance
   - Connection count
   - Query latency (p50/p95/p99)
   - Replication lag
   - Transaction rate
   - Cache hit ratio

3. **Network I/O** - Network performance
   - Bandwidth in/out
   - Error rates
   - Packet loss
   - Latency between hosts

4. **System Resources** - Host-level metrics
   - CPU utilization
   - Memory pressure
   - Disk I/O latency
   - Load average

5. **Microservices** - Application performance
   - API endpoint response times
   - Error rates by service
   - Throughput (requests/sec)
   - Dependency latency

**Accessing Dashboards**:
```bash
# View dashboard list
curl -s http://192.168.168.31:3000/api/dashboards/home | jq '.dashboards[]'

# Access via browser (login required):
1. Navigate to http://192.168.168.31:3000
2. Use Grafana credentials
3. Click "Dashboards" (home icon)
4. Search for "Container Health" or other dashboard name
```

### 1.3 Loki

**Purpose**: Log aggregation and querying  
**URL**: http://192.168.168.31:3100  
**Query Language**: LogQL

**Log Access Methods**:

**Method 1: Via Grafana Dashboard**
- Navigate to Grafana → Dashboards → Loki Logs
- LogQL query examples:
  ```
  {job="docker"} | level="error"
  {job="docker", container="postgres"}
  {job="docker"} | "OOM" | "memory"
  ```

**Method 2: Direct via Loki API**
```bash
# Query logs (last hour)
curl 'http://192.168.168.31:3100/loki/api/v1/query' \
  --data-urlencode 'query={job="docker"} | level="error"' \
  --data-urlencode 'time=1h'

# Tail logs
curl 'http://192.168.168.31:3100/loki/api/v1/tail' \
  --data-urlencode 'query={job="docker"}' | jq
```

**Method 3: Via Docker logs**
```bash
# Get logs from all containers
ssh akushnir@192.168.168.31 "
docker logs -f code-server-postgres 2>&1 | grep -i error
docker logs code-server-redis --tail 100
docker logs --all --since 1h ago | grep -i warn
"
```

### 1.4 Tempo

**Purpose**: Distributed tracing  
**URL**: http://192.168.168.31:3200-3201  
**Status**: Operational (for debugging complex request flows)

**Accessing Traces**:
- Via Grafana: Explore tab → Tempo data source
- Trace ID lookup: Find trace ID in service logs
- Dependency graph: Service call flow visualization

---

## Part 2: Key Metrics Explained

### 2.1 Container Health Metrics

| Metric | Target | Warning | Critical | Action |
|--------|--------|---------|----------|--------|
| `up{job="docker"}` | All 1 | Any 0 | Multiple 0 | Investigate crashed container |
| `container_cpu_usage%` | <70% | >75% | >90% | Scale CPU or optimize |
| `container_memory_mb` | <60% | >75% | >85% | Scale memory or reduce load |
| `container_restart_count` | 0 | >2 per day | >5 per day | Check container logs |
| `disk_free_gb` | >50 | <30 | <10 | Clean up disk space |

**Interpretation**:
```
✅ GREEN (All good):
   - All containers up (up == 1)
   - CPU: 40-60%
   - Memory: 45-65%
   - Restarts: 0 per day
   - Disk free: >100 GB

🟡 YELLOW (Monitor closely):
   - 1-2 containers temporarily down (restart happening)
   - CPU: 70-80%
   - Memory: 70-80%
   - Restarts: 2-5 per day
   - Disk free: 30-50 GB

🔴 RED (Immediate action needed):
   - 3+ containers down
   - CPU: >85%
   - Memory: >85%
   - Restarts: >5 per day
   - Disk free: <10 GB
```

### 2.2 PostgreSQL Metrics

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| `pg_is_in_recovery` | Primary: 0, Replica: 1 | Mismatch | Either 0 or unexpected 1 |
| `pg_replication_lag_seconds` | <5 sec | >10 sec | >60 sec |
| `pg_stat_connections` | <50 | >75 | >100 |
| `pg_database_size_bytes` | <200 GB | >250 GB | >300 GB |
| `pg_query_latency_p99` | <100ms | >200ms | >500ms |
| `pg_cache_hit_ratio` | >99% | >95% | <90% |

**Interpretation**:
```promql
# Check replication status (should see output for primary)
SELECT usename, client_addr, state, sync_state FROM pg_stat_replication;

# Check replica status (should be TRUE)
SELECT pg_is_in_recovery();

# Monitor query performance
SELECT query, mean_time, max_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;

# Check active connections
SELECT count(*) FROM pg_stat_activity;
```

### 2.3 Network Metrics

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Network latency | <2ms | >5ms | >10ms |
| Network loss | 0% | >0.1% | >1% |
| Bandwidth usage | <50% | >70% | >90% |
| Replication bandwidth | ~100MB/min | >200MB/min | >500MB/min |

**Check network health**:
```bash
# Latency between hosts
for i in {1..10}; do
  ping -c 1 -W 1 192.168.168.42 | grep time
done | awk '{sum+=$(NF-1); count++} END {print "Avg latency: " sum/count "ms"}'

# Network interface errors
ethtool -S eth0 | grep -E "rx_errors|tx_errors|dropped"
```

---

## Part 3: Alert Configuration

### 3.1 Current Alerts

**Configured in AlertManager** (http://192.168.168.31:9093):

```
CRITICAL Alerts (Page on-call):
- ContainerDown (1+ container not running)
- PostgreSQLDown (primary unreachable)
- DiskFull (>90% used)
- MemoryOOM (>90% used)
- ReplicationLagHigh (>60 seconds)
- CertificateExpiring (<7 days)

WARNING Alerts (Email to team):
- ContainerRestarting (>2 per hour)
- HighCPUUsage (>80% for >5 min)
- HighMemoryUsage (>80% for >5 min)
- SlowQueries (p99 > 500ms)
- HighErrorRate (>1%)
- DiskUsageHigh (>80%)

INFO Alerts (Slack):
- DailyHealthCheck (00:00 UTC)
- WeeklyReportGeneration (Mondays 06:00)
- MonthlyCapacityReview (1st of month)
```

### 3.2 Adding Custom Alerts

**Alert Rule Format** (Prometheus):
```yaml
groups:
  - name: custom_alerts
    rules:
      - alert: CustomMetricHigh
        expr: custom_metric > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Custom metric too high"
          description: "Value: {{ $value }}"
```

**Steps to Add**:
1. Edit `/etc/prometheus/alerts.yml` on primary host
2. Add rule group (example above)
3. Reload Prometheus: `curl -X POST http://192.168.168.31:9090/-/reload`
4. Verify rule: `http://192.168.168.31:9090/alerts`

### 3.3 Alert Escalation

**Notification Channels**:
1. **CRITICAL**: PagerDuty (on-call page immediately)
2. **WARNING**: Email + Slack to #ops-alerts
3. **INFO**: Slack #ops-info

**Escalation Tree**:
```
T+0: Alert triggered → PagerDuty page
T+5: No ACK → SMS to on-call engineer
T+10: No response → Call on-call engineer
T+15: No resolution → Page backup engineer
T+30: Still unresolved → Page ops manager
```

**Configure Escalation** (AlertManager config):
```yaml
routes:
  - match:
      severity: critical
    receiver: pagerduty
    repeat_interval: 5m
    continue: true
  
  - match:
      severity: warning
    receiver: slack_alerts
    repeat_interval: 1h
```

---

## Part 4: Daily Monitoring Checklist

**Run at 08:00 UTC every day**:

```bash
#!/bin/bash
# daily_monitoring_check.sh

echo "=== Daily Monitoring Check $(date) ===" | tee -a /tmp/monitoring-daily.log

PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"

# Check 1: Container Count
for HOST in $PRIMARY $REPLICA; do
  COUNT=$(ssh akushnir@$HOST "docker ps -q | wc -l" 2>/dev/null || echo "error")
  echo "[$HOST] Containers: $COUNT (target: 43/44)" | tee -a /tmp/monitoring-daily.log
done

# Check 2: Database Replication
REP_LAG=$(ssh akushnir@$PRIMARY "
  docker exec code-server-postgres psql -U postgres -c 'SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::INT;' 2>/dev/null | tail -1
" || echo "error")
echo "[PostgreSQL] Replication lag: ${REP_LAG}s (target: <5s)" | tee -a /tmp/monitoring-daily.log

# Check 3: Disk Usage
for HOST in $PRIMARY $REPLICA; do
  DISK=$(ssh akushnir@$HOST "df -h / | tail -1 | awk '{print \$5}'" 2>/dev/null || echo "unknown")
  echo "[$HOST] Disk usage: $DISK (target: <70%)" | tee -a /tmp/monitoring-daily.log
done

# Check 4: Error Count (last 1h)
ERRORS=$(curl -s 'http://192.168.168.31:3100/loki/api/v1/query' \
  --data-urlencode 'query={job="docker"} | level="error"' \
  2>/dev/null | jq '.data.result | length' || echo "0")
echo "[Logs] Errors in last hour: $ERRORS (target: <10)" | tee -a /tmp/monitoring-daily.log

# Check 5: Alert Status
ACTIVE_ALERTS=$(curl -s http://192.168.168.31:9090/api/v1/alerts | jq '.data.alerts | length' || echo "0")
echo "[Alerts] Active alerts: $ACTIVE_ALERTS (target: 0)" | tee -a /tmp/monitoring-daily.log

echo "✅ Daily check complete" | tee -a /tmp/monitoring-daily.log
```

---

## Part 5: Troubleshooting via Observability

### 5.1 High CPU Usage Detected

```bash
# Step 1: Identify container causing high CPU
docker stats --no-stream --format 'table {{.Container}}\t{{.CPUPerc}}' | sort -t '%' -k2 -rn | head -5

# Step 2: Check container logs
docker logs <container-name> --tail 50 | grep -i error

# Step 3: Check Prometheus for CPU trend
# Query: rate(container_cpu_usage_seconds_total{name="<container>"}[5m])

# Step 4: If PostgreSQL high CPU:
docker exec code-server-postgres psql -U postgres -c '
  SELECT query, calls, mean_time FROM pg_stat_statements 
  ORDER BY mean_time DESC LIMIT 5;
'

# Step 5: Mitigation
# Option 1: Optimize slow query
# Option 2: Increase container CPU limit
# Option 3: Add resource limit to runaway query
```

### 5.2 Memory Pressure Detected

```bash
# Step 1: Identify container using most memory
docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}' | sort -t 'G' -k2 -rn | head -5

# Step 2: Check if OOMKilled
docker inspect <container-name> | jq '.State.OOMKilled'

# Step 3: Check available memory on host
free -h

# Step 4: If PostgreSQL memory high:
docker exec code-server-postgres psql -U postgres -c 'SHOW shared_buffers;'

# Step 5: Mitigation
# Option 1: Increase host memory
# Option 2: Reduce container memory limit
# Option 3: Increase swap (temporary)
# Option 4: Restart container to clear memory
```

### 5.3 Slow Queries Detected

```bash
# Step 1: Via Grafana dashboard → PostgreSQL → Query Latency
# Look for spike in response time

# Step 2: Query slow log
docker exec code-server-postgres psql -U postgres -c '
  SELECT query, calls, total_time, mean_time, max_time 
  FROM pg_stat_statements 
  WHERE mean_time > 1000 
  ORDER BY mean_time DESC;
'

# Step 3: Analyze execution plan
docker exec code-server-postgres psql -U postgres -c '
  EXPLAIN ANALYZE SELECT ... /* paste slow query */;
'

# Step 4: Check for missing indexes
docker exec code-server-postgres psql -U postgres -c '
  SELECT schemaname, tablename, indexname 
  FROM pg_indexes 
  WHERE tablename = "table_name";
'

# Step 5: Mitigation
# Option 1: Create missing index
# Option 2: Rewrite query
# Option 3: Update table statistics (ANALYZE)
# Option 4: Add query timeout limit
```

---

## Part 6: SLA/SLO Tracking

### 6.1 Service Level Objectives

**Target SLOs**:
- Availability: 99.99% (52 minutes downtime/year)
- Latency: p95 < 200ms, p99 < 500ms
- Error Rate: < 0.1%
- RTO: 2-3 minutes (failover)
- RPO: < 5 minutes (data loss)

### 6.2 Calculating SLI (Service Level Indicator)

```promql
# Monthly Availability SLI
(1 - (up{job="docker"} == 0 / ignoring(job) on() vector(1))) * 100

# Monthly Error Rate SLI
(1 - (rate(http_requests_total{status=~"5.."}[30d]) / rate(http_requests_total[30d]))) * 100

# Monthly Latency SLI (p95)
histogram_quantile(0.95, http_request_duration_seconds)

# Monthly Replication RPO SLI
(replication_lag_seconds < 300) * 100
```

### 6.3 SLO Reporting

**Monthly SLO Report** (1st of next month):

```
SERVICE LEVEL REPORT - APRIL 2026
==================================

Availability SLI: 99.98% (1 incident: 1.2 min)
Target: 99.99% → Status: ⚠️ SLIGHTLY BELOW TARGET
Recommendation: Review incident root cause

Error Rate SLI: 0.05% (total errors: 125 in 250K requests)
Target: <0.1% → Status: ✅ WITHIN SLO
Recommendation: Continue monitoring

Latency SLI (p95): 145ms
Target: <200ms → Status: ✅ WITHIN SLO
Recommendation: Continue monitoring

RTO Achieved: 2.1 minutes (last failover test)
Target: 2-3 minutes → Status: ✅ WITHIN SLO
Recommendation: Quarterly drills sufficient

RPO Achieved: 3.5 minutes
Target: <5 minutes → Status: ✅ WITHIN SLO
Recommendation: Continue weekly backup tests

Overall Status: ✅ ALL SLOs MET
Month Rating: A+ (1 minor incident, quickly resolved)

Sign-off: _____________________ Date: __________
```

---

## Part 7: Metrics Export & Integration

### 7.1 Export Metrics to External Monitoring

**Prometheus Remote Write** (ship to external provider):
```yaml
# Add to /etc/prometheus/prometheus.yml
remote_write:
  - url: "https://monitoring.example.com/api/v1/write"
    basic_auth:
      username: promuser
      password: prompass
    queue_config:
      capacity: 10000
      max_retries: 3
      min_backoff: 30ms
      max_backoff: 100ms
```

### 7.2 API Integration

**Get metrics via Prometheus API**:
```bash
# Query latest CPU usage
curl 'http://192.168.168.31:9090/api/v1/query?query=container_cpu_usage_seconds_total'

# Query time range
curl 'http://192.168.168.31:9090/api/v1/query_range' \
  --data-urlencode 'query=container_memory_usage_bytes' \
  --data-urlencode 'start=2026-04-29T00:00:00Z' \
  --data-urlencode 'end=2026-04-29T23:59:59Z' \
  --data-urlencode 'step=15m'
```

---

## Quick Reference

| Access | URL | Auth | Purpose |
|--------|-----|------|---------|
| Prometheus | http://192.168.168.31:9090 | None | Metrics queries |
| Grafana | http://192.168.168.31:3000 | OAuth2 | Dashboards |
| Loki | http://192.168.168.31:3100 | None | Log queries |
| Tempo | http://192.168.168.31:3200 | None | Distributed tracing |
| AlertManager | http://192.168.168.31:9093 | None | Alert management |

**Critical Metrics to Watch**:
- `up{job="docker"}` - Container health
- `pg_replication_lag_seconds` - Data sync
- `node_filesystem_avail_bytes{mountpoint="/"}` - Disk space
- `container_memory_usage_bytes` - Memory pressure
- `rate(container_cpu_usage_seconds_total[5m])` - CPU load

**Daily Checks**:
- [ ] Container count = 87-88
- [ ] Replication lag < 5 seconds
- [ ] No active CRITICAL alerts
- [ ] Disk usage < 70%
- [ ] Memory usage < 75%
- [ ] No recent container restarts

---

**Document History**

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | April 29, 2026 | Initial monitoring and observability guide |

---

**Related Documents**:
- OPERATIONS_HANDOFF_GUIDE.md (Section: Monitoring & Alerts)
- ADVANCED_TROUBLESHOOTING_SCENARIOS.md (Diagnosis via metrics)
- CAPACITY_PLANNING_SCALING_GUIDE.md (Resource trending)
