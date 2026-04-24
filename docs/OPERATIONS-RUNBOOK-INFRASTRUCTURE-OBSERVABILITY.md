# Infrastructure Observability - Operations Runbook

**Last Updated**: April 22, 2026  
**Related Issue**: #1069  
**Scope**: postgres_exporter, redis_exporter, Grafana dashboards, alerting rules

---

## Quick Reference

### Exporter Ports
- **postgres_exporter**: 9187
- **redis_exporter**: 9121

### Dashboard URLs (after deployment)
- PostgreSQL Performance: http://grafana.kushnir.cloud/d/postgres-performance-2026
- Redis Health: http://grafana.kushnir.cloud/d/redis-health-2026
- Session-Broker: http://grafana.kushnir.cloud/d/session-broker-2026
- Infrastructure Overview: http://grafana.kushnir.cloud/d/infrastructure-overview-2026

### Critical Alerts
- PostgreSQL replication lag > 10s (P1) - **Check replica connectivity immediately**
- Redis evictions > 5 keys/sec (P1) - **Increase Redis memory or review session TTLs**
- Session-broker spawn errors > 5% (P1) - **Check Docker resources and kernel limits**
- Caddy 5xx errors > 1% (P1) - **Check backend service health**

---

## Section 1: Health Checks

### 1.1 Verify Exporters Are Running

#### postgres_exporter Health Check
```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Check container status
docker ps | grep postgres_exporter

# Expected output:
# postgres_exporter  prometheuscommunity/postgres_exporter:v0.15.0  Up X minutes

# Check metrics endpoint
curl -s http://localhost:9187/metrics | head -20

# Should see metrics like:
# pg_up 1
# pg_stat_statements_calls_total 1234
# pg_replication_lag_seconds 0.5
```

#### redis_exporter Health Check
```bash
# Check container status
docker ps | grep redis_exporter

# Expected output:
# redis_exporter  oliver006/redis_exporter:1.59.1  Up X minutes

# Check metrics endpoint
curl -s http://localhost:9121/metrics | head -20

# Should see metrics like:
# redis_up 1
# redis_connected_clients 42
# redis_memory_used_bytes 1234567
```

### 1.2 Verify Prometheus Scrape Targets

```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {labels: .labels, health: .health}' | grep -A1 -B1 "postgres_exporter\|redis_exporter"

# Expected: Both should show "health": "up"
```

### 1.3 Verify Grafana Dashboards

```bash
# Check Grafana API for dashboards
curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" http://localhost:3000/api/search | jq '.[] | {title: .title, type: .type}' | grep -i "postgres\|redis\|session\|infrastructure"

# Should list 4 dashboards with state: "dashboard"
```

---

## Section 2: Alert Troubleshooting

### 2.1 PostgreSQL Replication Lag Alert

**Alert**: `PostgreSQLReplicationLag` (P1)  
**Threshold**: Lag > 10 seconds for 5 minutes  
**Severity**: Critical - indicates replica is falling behind

#### Diagnosis Steps
```bash
# 1. Check replication status on primary
ssh akushnir@192.168.168.31
docker exec postgres psql -U postgres -d postgres -c "
  SELECT 
    slot_name, 
    active, 
    restart_lsn, 
    confirmed_flush_lsn 
  FROM pg_replication_slots;
"

# 2. Check replica lag from postgres_exporter metric
curl -s http://localhost:9187/metrics | grep pg_replication_lag_seconds

# 3. Check PostgreSQL logs for replication errors
docker logs postgres | tail -50 | grep -i "replication\|wal\|sync"

# 4. Verify network connectivity between primary and replica
ping 192.168.168.42
ssh 192.168.168.42 'echo "Replica reachable"'
```

#### Resolution Steps
```bash
# If replica is stuck:
# 1. Check disk space on replica
ssh akushnir@192.168.168.42 'df -h /mnt/postgres'

# 2. Restart PostgreSQL on replica if needed
ssh akushnir@192.168.168.42 'docker-compose restart postgres'

# 3. Monitor lag until it returns to < 1 second
watch -n 5 'curl -s http://localhost:9187/metrics | grep pg_replication_lag_seconds'
```

### 2.2 Redis Memory Usage Alert

**Alert**: `RedisMemoryUsageHigh` (P2)  
**Threshold**: Memory usage > 80% for 5 minutes  
**Severity**: High - risk of evictions and key loss

#### Diagnosis Steps
```bash
# 1. Check Redis memory stats
redis-cli INFO memory

# 2. Check memory usage from exporter metric
curl -s http://localhost:9121/metrics | grep -E "redis_memory_used_bytes|redis_memory_max_bytes"

# 3. Check eviction rate
curl -s http://localhost:9121/metrics | grep redis_evicted_keys_total

# 4. List largest keys in Redis
redis-cli --bigkeys

# 5. Check key TTLs and expiration
redis-cli --scan --pattern "session:*" | redis-cli --eval /path/to/script.lua , 5
```

#### Resolution Steps
```bash
# Option 1: Increase Redis memory limit
# Edit docker-compose.yml:
# redis:
#   command: redis-server --maxmemory 2gb --maxmemory-policy allkeys-lru

# Option 2: Review session TTLs
# Query application code for session retention policy
grep -r "SESSION_TTL\|TTL\|expire" apps/backend/src | head -20

# Option 3: Evict old sessions manually
redis-cli EVAL "
  local keys = redis.call('keys', 'session:*')
  for i, key in ipairs(keys) do
    local ttl = redis.call('ttl', key)
    if ttl == -1 then redis.call('del', key) end
  end
  return #keys
" 0
```

### 2.3 Session-Broker Spawn Errors Alert

**Alert**: `SessionBrokerSpawnErrorRate` (P1)  
**Threshold**: Error rate > 5% for 2 minutes  
**Severity**: Critical - users cannot start sessions

#### Diagnosis Steps
```bash
# 1. Check session-broker logs
docker logs session-broker | tail -100 | grep -i "error\|fail\|spawn"

# 2. Check Docker resource availability
docker stats --no-stream | grep -E "session|docker" | head -10

# 3. Check kernel limits
cat /proc/sys/fs/file-max
ulimit -n

# 4. Check disk space for container images and workspace volumes
docker system df
df -h /mnt/c/code-server-enterprise/workspace

# 5. Check failed container creation events
docker events --filter 'type=container' --since 10m | grep -i "error\|die\|kill"
```

#### Resolution Steps
```bash
# Option 1: Increase Docker memory limits
# Edit docker-compose.yml:
# session-broker:
#   deploy:
#     resources:
#       limits:
#         memory: 4g
#         cpus: '2.0'

# Option 2: Clean up stopped containers
docker container prune -f

# Option 3: Increase kernel limits (if needed)
# Edit /etc/security/limits.conf:
# *   soft  nofile  65536
# *   hard  nofile  1048576

# Option 4: Restart session-broker
docker-compose restart session-broker

# Option 5: Check available disk space
df -h /
# If < 20% free space remaining, delete old session backups
find /mnt/c/code-server-enterprise/workspace -name '*.backup' -mtime +7 -delete
```

### 2.4 Caddy HTTP Error Rate Alert

**Alert**: `CaddyHTTPErrorRateHigh` (P1)  
**Threshold**: 5xx error rate > 1% for 5 minutes  
**Severity**: Critical - users experiencing service errors

#### Diagnosis Steps
```bash
# 1. Check Caddy logs
docker logs caddy | tail -100 | grep -E "error|5[0-9]{2}" | tail -20

# 2. Check backend service health
curl -i http://localhost:8080/health  # Code-server health
curl -i http://localhost:5432/health  # PostgreSQL health
curl -i http://localhost:6379/ping   # Redis health

# 3. Check Caddy configuration for routing errors
docker exec caddy cat /etc/caddy/Caddyfile | grep -A5 -B5 "error\|reverse_proxy"

# 4. Check response codes from metrics
curl -s http://localhost:2019/metrics | grep 'caddy_http_requests_total{status="5'

# 5. Check upstream backend status
curl -s http://localhost:2019/config/apps/http/servers | jq '.[] | .routes[] | .handle[]'
```

#### Resolution Steps
```bash
# Option 1: Restart backend services
docker-compose restart code-server postgres redis

# Option 2: Check backend service logs
docker logs code-server | tail -50 | grep -i "error"

# Option 3: Verify Caddy configuration
docker-compose config | grep -A10 "caddy:"

# Option 4: Reload Caddy configuration (graceful reload)
curl -s -X POST http://localhost:2019/load -H "Content-Type: application/json" \
  -d @<(docker exec caddy cat /etc/caddy/Caddyfile | jq -Rs '{config: .}')

# Option 5: Increase Caddy timeouts (if backend is slow)
# Edit Caddyfile:
# reverse_proxy localhost:8080 {
#   timeout 30s
# }
```

---

## Section 3: Dashboard Interpretation

### 3.1 PostgreSQL Performance Dashboard

**Panel 1: Active Connections**
- Green (< 50): Healthy
- Yellow (50-80): Elevated, monitor for runaway queries
- Red (> 80): Critical, connection pool nearly exhausted
- Action: Check slow queries, kill idle sessions, increase pool size

**Panel 2: Queries Per Second**
- Normal range: 100-1000 QPS
- Spike > 2000 QPS: Check for query storms, may indicate missing indexes
- Drop to 0: Check if PostgreSQL is down

**Panel 3: Replication Lag**
- Normal: < 1 second
- Warning (1-10s): Monitor, may indicate network or I/O issues
- Critical (> 10s): Replica is falling behind, investigate immediately

**Panel 4: Cache Hit Ratio**
- Green (> 99%): Excellent, queries hitting cached data
- Yellow (95-99%): Good, some disk reads occurring
- Red (< 95%): Poor, adding indexes or increasing RAM would help

**Panel 5: Query Latency p95**
- Normal: < 100ms
- Good: < 500ms
- Poor: > 1s, investigate slow queries
- Critical: > 5s, check table locks and I/O performance

### 3.2 Redis Health Dashboard

**Panel 1: Memory Usage**
- Green (< 70%): Healthy
- Yellow (70-80%): Approaching eviction risk
- Red (> 80%): Immediate risk of key eviction
- Action: Increase maxmemory or reduce session TTLs

**Panel 2: Cache Hit Ratio**
- Target: > 95% (cache hits vs total)
- < 80%: Indicates insufficient cache size or poor key distribution

**Panel 3: Connected Clients**
- Baseline: 20-50 clients
- Spike: May indicate connection leak, check application code

**Panel 4: Evictions**
- Normal: 0 keys/sec (no evictions)
- Any spike: Indicates memory pressure, increase memory immediately

### 3.3 Session-Broker Dashboard

**Panel 1: Active Sessions**
- Green (< 50): Light load
- Yellow (50-100): Moderate load
- Red (> 100): Heavy load, monitor spawn latency

**Panel 2: Session Create Rate**
- Normal: 0.5-2 creates/sec (depending on user activity)
- Spike: Mass user login, expected during business hours

**Panel 3: Container Spawn Latency**
- p50: < 2s (normal)
- p95: < 5s (acceptable)
- p99: < 10s (starting to slow down)
- Red (> 10s): Docker resource contention, check CPU/memory

**Panel 4: Spawn Errors**
- Normal: 0 errors/sec
- Any error: Investigate immediately, may indicate Docker/kernel issues

### 3.4 Infrastructure Overview Dashboard

**System Health Status**
- Shows UP/DOWN status for all key services
- Any RED: Immediate investigation required

**Disk Usage**
- Green (< 70%): Healthy
- Yellow (70-85%): Monitor, clean old data
- Red (> 85%): Immediate cleanup needed

**Network Throughput**
- Baseline: 1-10 Mbps depending on load
- Spike: Check for backups or large data transfers

---

## Section 4: Common Issues and Solutions

### 4.1 Metrics Not Appearing in Prometheus

**Symptom**: Dashboard shows "No data" or metrics are missing  
**Cause**: Exporter not running or Prometheus not scraping

**Solution**:
```bash
# 1. Check exporter is running
docker ps | grep exporter

# 2. Check exporter is accessible
curl http://localhost:9187/metrics  # or 9121 for redis

# 3. Check Prometheus scrape targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | contains("exporter"))'

# 4. If target is DOWN, check logs
docker logs prometheus | grep "error" | tail -20
docker logs postgres_exporter | tail -50

# 5. Restart exporters
docker-compose restart postgres_exporter redis_exporter

# 6. Give Prometheus 30-60 seconds to scrape new data
# Then reload dashboard
```

### 4.2 False Positive Alerts

**Symptom**: Alert fires but service is actually healthy

**Solution**:
```bash
# 1. Verify actual metric value
curl -s http://localhost:9090/api/v1/query?query=ALERT_NAME | jq '.data.result'

# 2. If false positive, adjust alert threshold
# Edit alert-rules.yml:
# - alert: AlertName
#   expr: metric_value > NEW_THRESHOLD  # Increase threshold

# 3. Test alert with changed threshold
docker-compose restart prometheus

# 4. Monitor for 5-10 minutes to confirm it doesn't fire
```

### 4.3 Dashboard Panels Showing Wrong Metrics

**Symptom**: Panel title says "Replication Lag" but shows memory metric

**Cause**: Metric query misconfigured or metric name changed

**Solution**:
```bash
# 1. Check actual metric names exported
curl -s http://localhost:9187/metrics | grep -i "lag\|replication"

# 2. Edit dashboard JSON to fix metric query
vi config/grafana-dashboard-postgres-performance.json

# 3. Find and replace metric name in the panel
# Search for "expr": "OLD_METRIC_NAME"
# Replace with "expr": "NEW_METRIC_NAME"

# 4. Re-import dashboard in Grafana
```

---

## Section 5: Maintenance Tasks

### 5.1 Weekly Checks (every Monday)

```bash
# Check alert rule compliance
curl http://localhost:9090/api/v1/rules | jq '.data.groups | length'

# Verify all exporters running
docker ps | grep exporter | wc -l  # Should be 2

# Check Prometheus database size
du -h /mnt/c/code-server-enterprise/prometheus/data

# Review error logs
docker logs postgres_exporter | grep -i error | wc -l
docker logs redis_exporter | grep -i error | wc -l
```

### 5.2 Monthly Tasks (1st of month)

```bash
# Archive old Prometheus data (> 30 days)
# Prometheus keeps 15 days by default, older data is pruned

# Review and adjust alert thresholds based on production baselines
# Compare alert firing frequency month-to-month

# Update runbook with new procedures or lessons learned
# Document any manual interventions taken

# Test failover to replica
# Verify observability stack works on 192.168.168.42
```

### 5.3 Quarterly Review (every 3 months)

```bash
# Review dashboard usage (in Grafana)
# Remove unused dashboards, consolidate redundant panels

# Analyze alert effectiveness
# - Which alerts are most useful?
# - Which are false positives?
# - Any new alerts needed?

# Capacity planning
# Review growth trends in metrics
# Estimate when new resources may be needed

# Security review
# Verify Prometheus and Grafana access controls
# Rotate any API tokens or credentials
```

---

## Section 6: Escalation Procedures

### P1 Alert Escalation (Critical)

**When**: Alert fires and metric confirms issue  
**Action**: Immediate response required

```bash
# Step 1: Acknowledge alert (mark as read in Alertmanager)
# Step 2: Verify issue with metric query
# Step 3: Execute resolution steps from Section 2
# Step 4: Document incident in GitHub issue
# Step 5: If unable to resolve in 15 min, contact backup on-call

# Example incident creation:
curl -X POST https://api.github.com/repos/kushin77/code-server/issues \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -d '{
    "title": "P0 INCIDENT: PostgreSQL Replication Lag > 10s",
    "body": "Alert fired at 2026-04-22T17:00:00Z. Lag: 15s. Investigating...",
    "labels": ["P0", "incident", "infrastructure"]
  }'
```

### P2 Alert Escalation (High)

**When**: Alert fires and confirmed, SLA allows 1-2 hour response  
**Action**: Schedule resolution within business hours

```bash
# Step 1: Acknowledge alert
# Step 2: Verify issue
# Step 3: Create GitHub issue with label: P2, incident
# Step 4: Execute resolution during next maintenance window
# Step 5: Document solution as comment on issue
```

---

## Section 7: Disaster Recovery

### 7.1 Exporter Data Loss

**Scenario**: postgres_exporter or redis_exporter container crashes, losing historical metrics

**Recovery**:
```bash
# Metrics are not lost (Prometheus scrapes them, not exporters)
# Just restart the exporter:
docker-compose restart postgres_exporter redis_exporter

# Prometheus will resume scraping from where it left off
```

### 7.2 Prometheus Database Corruption

**Scenario**: Prometheus storage corrupted, historical data lost

**Recovery**:
```bash
# 1. Stop Prometheus
docker-compose stop prometheus

# 2. Delete corrupted data directory (WARNING: loses history)
rm -rf prometheus/data/

# 3. Restart Prometheus
docker-compose up -d prometheus

# 4. Prometheus will start fresh and begin collecting metrics
# Note: All historical data is lost, only future data available
```

### 7.3 Grafana Dashboard Data Loss

**Scenario**: Grafana deleted a dashboard accidentally

**Recovery**:
```bash
# Dashboards are stored in docker-compose volume
# If volume is intact, restart Grafana:
docker-compose restart grafana

# If volume is lost:
# 1. Re-import dashboards from backup JSON files:
#    config/grafana-dashboard-*.json
# 2. Or restore from git history:
#    git show HEAD:config/grafana-dashboard-postgres-performance.json

# Grafana stores dashboards in Grafana database (not affected by exporter/Prometheus)
```

---

## Section 8: Performance Tuning

### 8.1 Reduce Prometheus Scrape Interval

**Current**: 30 seconds  
**To change to 15 seconds**:

```bash
# Edit prometheus.yml:
# global:
#   scrape_interval: 15s  # Default is 15s, changed to 30s for #1069

# Tradeoff: More frequent data, higher storage use (2x), higher CPU

# Restart Prometheus
docker-compose restart prometheus
```

### 8.2 Reduce Metric Retention Period

**Current**: 15 days (Prometheus default)  
**To change to 7 days**:

```bash
# Edit docker-compose.yml prometheus service:
# command: --storage.tsdb.retention.time=7d

# Tradeoff: Less storage needed, lose historical data older than 7 days

# Restart Prometheus
docker-compose restart prometheus
```

### 8.3 Optimize Dashboard Queries

**Symptom**: Dashboard is slow to load (> 5 seconds)  
**Solution**:
```bash
# 1. Check which panels are slow
#    Open Grafana → Dashboard → Query Inspector

# 2. Optimize PromQL queries:
#    - Use recording rules for complex queries
#    - Use shorter time ranges if possible
#    - Avoid high-cardinality label combinations

# 3. Example optimization:
#    Before: histogram_quantile(0.95, rate(metric_bucket[5m]))
#    After: histogram_quantile(0.95, rate(metric_bucket[1m]))
#           (shorter range = faster query)
```

---

## Section 9: Backup and Recovery Checklist

**Last Backup**: [To be filled in operationally]

```
Backup Items:
- [ ] prometheus/data directory (metric database)
- [ ] grafana/data directory (dashboard configurations)
- [ ] alert-rules.yml (alert rules)
- [ ] prometheus.yml (Prometheus config)
- [ ] docker-compose.yml (service definitions)
- [ ] postgres_exporter_queries.yml (custom queries)

Recovery Procedure:
1. Stop all services: docker-compose down
2. Restore data directories from backup
3. Verify config files are present and valid
4. Start services: docker-compose up -d
5. Verify metrics flowing in Prometheus
6. Verify dashboards accessible in Grafana
```

---

## Contact & Escalation

**On-Call Engineer**: [To be defined]  
**Backup**: [To be defined]  
**Slack Channel**: #infrastructure  
**Incident Severity**: P0/P1 requires immediate response (< 15 min)

**Common Issues Slack Shortcuts**:
- `@infrastructure-alerts` - Page on-call for P1 alerts
- Thread in #infrastructure for P2 issues

---

**Document Revision History**:
- v1.0 - April 22, 2026 - Initial version, post #1069 implementation
