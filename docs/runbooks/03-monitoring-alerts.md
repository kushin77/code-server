# Monitoring & Alerting Guide

## Key Metrics Dashboard

Access Grafana: http://localhost:3000 (admin / PASSWORD from .env.production)

### Critical Dashboards
1. **Cluster Health**: Node status, container count, replication lag
2. **Database**: Query latency, transaction rate, replication slots
3. **Cache**: Hit rate, evictions, memory usage
4. **Tracing**: P50/P95/P99 latencies, error rate by service
5. **Audit Trail**: Policy decisions, violations, trends

## Alert Rules

### Database Alerts
- `PostgreSQLDown`: Primary not responding
- `ReplicationLagHigh`: Replica more than 10s behind
- `WalSegmentBacklog`: More than 10 segments queued

### Cache Alerts
- `RedisMasterDown`: Primary not responding
- `RedisMemoryHigh`: Usage > 80% of limit

### Application Alerts
- `HighErrorRate`: > 5% of requests failing
- `HighLatency`: P95 > 5 seconds
- `ContainerCrashing`: Container restart loop

### System Alerts
- `HighCPU`: > 80% sustained
- `HighMemory`: > 85% sustained
- `DiskSpace`: < 10% free

## Querying Logs

### Loki Queries
```
# All errors in last hour
{level="error"} | 1h

# Specific service
{service="code-server-api"} | last 1h

# Policy violations
{job="opa"} | json | result="deny"

# Request latency
{job="prometheus"} | json | duration > 1000
```

### Tempo Queries
```
# Slow requests (> 5s)
{ duration > 5s }

# Failed requests
{ status = error }

# Specific service
{ service.name = "code-server-api" }

# Database queries
{ db.system = "postgresql" }
```

## On-Call Procedures

### Alert Received
1. Go to dashboard: Check affected service
2. Query logs: Find root cause
3. Check traces: Identify service interaction failure
4. Decide: Auto-recovery or manual intervention

### Escalation Path
- Level 1 (Auto): Health checks trigger restart
- Level 2 (Monitoring): Alert team via PagerDuty
- Level 3 (Manual): Execute failover procedure
- Level 4 (Executive): Notify stakeholders

