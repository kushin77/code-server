# PRODUCTION INCIDENT RESPONSE RUNBOOK
## Emergency Response Procedures & Troubleshooting Guide

**Version:** 1.0 Production  
**Status:** ACTIVE  
**Last Updated:** 2026-04-13  

---

## Table of Contents

1. [Incident Classification](#incident-classification)
2. [Immediate Response (First 5 Minutes)](#immediate-response-first-5-minutes)
3. [Common Incident Scenarios](#common-incident-scenarios)
4. [Service-Specific Troubleshooting](#service-specific-troubleshooting)
5. [Recovery & Escalation Procedures](#recovery--escalation-procedures)
6. [Post-Incident Review](#post-incident-review)

---

## Incident Classification

### Severity Levels

| Level | Duration | Action | SLA |
|-------|----------|--------|-----|
| **P1** | Ongoing | Declare incident, page all on-call | <5 min MTTR |
| **P2** | > 5 min | Page on-call lead, investigate | <15 min |
| **P3** | > 30 min | Log issue, investigate during business hours | < 4 hours |
| **P4** | Intermittent | Monitor and log, plan maintenance | < 1 week |

### Incident Types

```
P1 - CRITICAL (Page immediately)
├── Complete service outage (all users affected)
├── Data loss or corruption
├── Security breach or suspicious activity
├── Database down (failover unavailable)
└── Revenue-impacting system down

P2 - HIGH (Investigate within 5 min)
├── Partial service outage (>10% users affected)
├── Significant latency degradation (>500ms p99)
├── High error rate (>1%)
├── Storage capacity critical (>90% used)
└── Backup failure detected

P3 - MEDIUM (Address same business day)
├── Single user reports issue
├── Minor latency increase (<500ms p99)
├── Graceful degradation active
├── Non-critical service flapping
└── Monitoring alert firing intermittently

P4 - LOW (Schedule for next maintenance)
├── Documentation updates needed
├── Code quality issues
├── Non-blocking warnings in logs
├── Optimization opportunities
└── Feature requests
```

---

## Immediate Response (First 5 Minutes)

### Step 1: Verify the Issue (0-1 minute)

```bash
# Check service status from jump host
ssh akushnir@192.168.168.31

# Execute quick health check
docker-compose ps

# Expected: All 13 services showing "Up" or "healthy"
# If not: Note which services are down/restarting

# Check for obvious errors in recent logs (last 5 minutes)
docker-compose logs --tail=100 | grep -iE "error|exception|panic" | wc -l

# Check if this is truly affecting users
curl -L https://ide.kushnir.cloud/health -H "User-Agent: monitoring-bot"
# Should get HTTP 200
```

### Step 2: Assess Impact (1-2 minutes)

```bash
# How many users affected?
curl 'http://localhost:9090/api/v1/query?query=http_requests_total' | \
  jq '.data.result | map(.value[1]) | add'

# What's the error rate?
curl 'http://localhost:9090/api/v1/query?query=rate(http_errors_total[5m])' | \
  jq '.data.result[].value[1]'

# Is it P1 or lower?
if [ $(curl -s 'http://192.168.168.31:9090/api/v1/query?query=up{job="code-server"}' | \
  jq '.data.result[].value[1]' | head -1) -eq 0 ]; then
  echo "P1: Code-Server DOWN"
  PAGE_ONCALL=true
else
  echo "Not P1, but investigate"
  PAGE_ONCALL=false
fi
```

### Step 3: Declare Incident (2-3 minutes)

```bash
# If P1:
# 1. Page PagerDuty on-call engineer immediately
curl -X POST https://events.pagerduty.com/v2/enqueue \
  -H 'Content-Type: application/json' \
  -d '{
    "routing_key": "YOUR_PAGERDUTY_KEY",
    "event_action": "trigger",
    "payload": {
      "summary": "P1: Code-Server Service Down",
      "severity": "critical",
      "source": "MonitoringBot",
      "custom_details": {
        "runbook": "https://github.com/kushin77/code-server-enterprise/blob/main/INCIDENT-RESPONSE.md#code-server-down"
      }
    }
  }'

# 2. Post to incident Slack channel
curl -X POST https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK \
  -d '{
    "channel": "#incidents",
    "text": "🚨 *P1 INCIDENT* 🚨",
    "attachments": [{
      "color": "danger",
      "fields": [
        {"title": "Service", "value": "Code-Server", "short": true},
        {"title": "Severity", "value": "P1 - CRITICAL", "short": true},
        {"title": "Start Time", "value": "'"$(date)"'", "short": false},
        {"title": "Runbook", "value": "See links below", "short": false}
      ]
    }]
  }'

# 3. Update status page
# Go to http://status.ide.kushnir.cloud and set "Investigating"
```

### Step 4: Start Troubleshooting (3-5 minutes)

Proceed to the relevant scenario below based on what's failing.

---

## Common Incident Scenarios

### Scenario 1: Code-Server Down (Can't Connect to UI)

**Symptoms:**
- Users can't reach https://ide.kushnir.cloud
- `curl https://ide.kushnir.cloud` returns connection refused or 503

**Diagnosis:**
```bash
# Check if Code-Server container is running
docker-compose ps code-server
# If "Exited" or "Restarting": container is crashing

# Check logs for crash reason
docker-compose logs code-server --tail=50

# Common crash reasons:
# 1. Out of memory: "OOMKilled" in logs
# 2. Port conflict: "Address already in use"
# 3. Missing dependency: "command not found"
# 4. Configuration error: "invalid configuration"
```

**Recovery:**
```bash
# Option 1: Restart container
docker-compose restart code-server
wait 30 seconds
docker-compose ps code-server  # Check if healthy now

# Option 2: If restart fails, check resource availability
docker stats --no-stream | grep code-server
# If MEMORY% > 90%: need to increase limit or debug memory leak
# If CPU% > 100%: container is CPU-bound, check for infinite loop

# Option 3: Scale up resources (temporary mitigation)
# Edit docker-compose.yml:
# services:
#   code-server:
#     deploy:
#       resources:
#         limits:
#           cpus: '2.0'  # <- increase from 1.0
#           memory: 8G   # <- increase from 4G

docker-compose up -d code-server

# Option 4: Check if Caddy reverse proxy is the issue
docker-compose logs caddy --tail=50
# Look for "502 Bad Gateway" errors

# If Caddy is healthy but Code-Server responds with 50x:
curl http://localhost:7680/api/v1/info  # talk directly to Code-Server
if [ $? -eq 0 ]; then
  echo "Code-Server is fine, issue is in ingress"
else
  echo "Code-Server is not responding"
fi
```

**SLA Target:**
- Detection: <1 minute
- Recovery: <5 minutes
- Status page update: <2 minutes

---

### Scenario 2: High Error Rate / 500 Errors

**Symptoms:**
- Metrics show error_rate_5m > 1%
- Users report "Internal Server Error"
- Alerts firing: "HighErrorRate"

**Diagnosis:**
```bash
# Find which service is returning errors
curl 'http://localhost:9090/api/v1/query?query=rate(http_client_requests_seconds_bucket{status=~"5.+"}[5m])' | \
  jq '.data.result | sort_by(.value[1]) | reverse | .[:10]'

# Get detailed error logs from that service
# If it's code-server:
docker-compose logs code-server --tail=200 | \
  grep -iE "error|exception" | \
  tail -20

# Check if the error is transient or persistent
docker-compose logs code-server --since 5m | \
  grep -c "Error"  # high count = persistent issue
```

**Common Root Causes:**

```bash
# 1. Database connection failure
docker-compose logs code-server | grep -i "database\|postgres\|connection"
# Fix: Check PostgreSQL status
docker-compose ps postgres
docker-compose exec postgres pg_isready

# 2. Redis connection failure
docker-compose logs code-server | grep -i "redis\|cache"
# Fix: Check Redis status
docker-compose exec redis redis-cli ping

# 3. Out of memory
docker stats --no-stream code-server | awk '{print $4}'  # check MEMORY%

# 4. Disk full
df -h /data | awk 'NR==3 {print $5}'  # check %USE

# 5. Rate limiting (Caddy throwing 429s)
docker-compose logs caddy | grep "429\|Too Many"

# 6. OAuth2 Proxy auth failure
docker-compose logs oauth2-proxy | tail -50
```

**Recovery:**
```bash
# For transient errors (1-2 per minute):
# No action needed, let circuit breaker handle

# For persistent high error rate:
# 1. Identify failing service from logs
# 2. Check service status
docker-compose restart <service-name>
# 3. Wait 10 seconds for recovery
sleep 10
# 4. Verify error rate dropped
curl 'http://localhost:9090/api/v1/query?query=rate(http_errors_total[5m])'

# For database/cache connection issues:
# 1. Verify dependent service is healthy
docker-compose ps postgres redis

# 2. Check network connectivity
docker-compose exec code-server \
  curl -v postgresql://postgres:5432  # test connection

# 3. If stuck, restart all dependent services:
docker-compose restart postgres code-server
```

**SLA Target:**
- Detection: <1 minute (alert fires automatically)
- Recovery: <5 minutes

---

### Scenario 3: High Latency / Slow Responses

**Symptoms:**
- p99 latency > 500ms
- Users report "slow to load"
- Alert: "HighLatency"

**Diagnosis:**
```bash
# Current latency percentiles
curl 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.99, http_request_duration_seconds_bucket)' | \
  jq '.data.result[0].value'

# Which endpoints are slowest?
curl 'http://localhost:9090/api/v1/query?query=topk(5, histogram_quantile(0.99, http_request_duration_seconds_bucket{endpoint="*"}))' | \
  jq '.data.result | map({endpoint:.metric.endpoint, latency:.value[1]})'

# Is it CPU-bound?
docker stats --no-stream | grep -E "CPU"

# Is it I/O-bound?
iostat -x 1 2 | grep -E "r/s|await"

# Is it network-bound?
# Check bandwidth usage: iftop or nethogs
```

**Common Causes:**

```bash
# 1. Ollama model inference (expected to be slow)
# First check if request is going to Ollama
docker-compose logs code-server | grep -i "ollama\|model"

# 2. Large file operations
# Check disk I/O
iostat -x /dev/sda 1 2 | tail -1 | awk '{print $6}'  # await time

# 3. Database query performance
# Check slow query log
docker-compose exec postgres \
  psql -c "SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5"

# 4. Resource contention
docker stats --no-stream --all  # any service at >90%?

# 5. Network latency to upstream services
docker-compose exec code-server \
  latencycheck.sh  # test latency to postgresql, redis, etc.
```

**Recovery:**
```bash
# For Ollama latency (expected):
# No action, document expected latency in runbook

# For database latency:
# Check if query is problematic
docker-compose exec postgres \
  psql -c "SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 1"

# Add index if needed:
docker-compose exec postgres \
  psql -c "CREATE INDEX idx_<table>_<column> ON <table>(<column>)"

# For high CPU:
# Check which process is consuming CPU
docker top code-server | grep -E "CPU\|%CPU" | head -5

# For high disk I/O:
# Check which process is doing I/O
iotop -o | head -10

# Temporary mitigation: Scale endpoints
# Add more replicas if using orchestration
# Or increase resource limits in docker-compose.yml
```

**SLA Target:**
- Detection: <1 minute
- Recovery: <10 minutes (may involve optimization, not immediate fix)

---

### Scenario 4: Database Connection Pool Exhausted

**Symptoms:**
- Errors in logs: "connection pool is full" or "timeout acquiring connection"
- All database queries failing
- Alert: "DBConnectionPoolExhausted"

**Diagnosis:**
```bash
# Check active connections
docker-compose exec postgres \
  psql -c "SELECT count(*) as active_connections FROM pg_stat_activity"

# Check max connections setting
docker-compose exec postgres \
  psql -c "SHOW max_connections"  # default usually 100

# Check which application has the most connections
docker-compose exec postgres \
  psql -c "SELECT application_name, count(*) FROM pg_stat_activity GROUP BY application_name"

# Check for idle connections
docker-compose exec postgres \
  psql -c "SELECT * FROM pg_stat_activity WHERE state = 'idle'"
```

**Recovery:**
```bash
# Option 1: Increase max_connections (requires restart)
# Edit docker-compose.yml:
# services:
#   postgres:
#     environment:
#       - POSTGRES_INITDB_ARGS=-c max_connections=200

docker-compose restart postgres

# Option 2: Kill idle connections (temporary)
docker-compose exec postgres \
  psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND idleinxact_session_expires < now()"

# Option 3: Restart application (close all connections)
docker-compose restart code-server

# Option 4: Enable connection pooling (PgBouncer)
# Add to docker-compose.yml:
# pgbouncer:
#   image: pgbouncer:latest
#   environment:
#     DATABASES_HOST: postgres
#     DATABASES_USER: ide_app
#     DATABASES_PASSWORD: ...
#     POOL_MODE: transaction
#     MAX_CLIENT_CONN: 100
#     DEFAULT_POOL_SIZE: 25
```

**Prevention:**
```bash
# Configure connection limits application-side
# In code-server configuration:
DATABASE_POOL_MIN: 5
DATABASE_POOL_MAX: 20  # don't exceed 20 per instance
DATABASE_POOL_IDLE_TIMEOUT: 30s
DATABASE_STATEMENT_TIMEOUT: 5s
```

**SLA Target:**
- Detection: <1 minute
- Recovery: <5 minutes

---

### Scenario 5: Storage / Disk Full

**Symptoms:**
- Commands fail with "No space left on device"
- Alert: "DiskSpaceCritical"
- Writes to database/logs failing

**Diagnosis:**
```bash
# Check disk usage
df -h /data

# Find what's consuming space
du -sh /data/* | sort -h | tail -10

# Check PostgreSQL logs
du -sh /data/postgres/**

# Check Elasticsearch indices
curl http://localhost:9200/_cat/indices?v | sort -k9 -h
```

**Quick Recovery (5-10 minutes):**

```bash
# 1. Check what's growing rapidly
# Most likely: Elasticsearch indices or PostgreSQL transaction logs

# If Elasticsearch is huge:
# Delete old indices
curl -X DELETE "localhost:9200/logs-*-2026-01-*"  # delete January logs
curl -X DELETE "localhost:9200/metrics-*-2026-01-*"

# If PostgreSQL is huge:
# Check for bloat
docker-compose exec postgres \
  psql -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) FROM pg_tables ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10"

# Vacuum and analyze (clean up space)
docker-compose exec postgres \
  psql -c "VACUUM FULL ANALYZE"

# 2. Check application logs
du -sh /var/log/*
# Delete old logs
find /var/log -name "*.log" -mtime +30 -delete

# 3. Expand disk (if underlying storage allows)
# For Docker volumes: Usually need to expand at VM level
sudo lvresize -L +100G /dev/vg0/var
sudo resize2fs /dev/vg0/var
```

**Long-term Fix:**
```bash
# 1. Reduce retention policies
# Edit prometheus-production.yml
# Change: retention: "365d" to "90d" (for prod, adjust as needed)

# Edit .env.production
# Change: LOG_RETENTION=90  # 90 days instead of 730

# Edit alertmanager config
# Reduce history retention

# 2. Implement tiering (hot/warm/cold storage)
# Move cold data to cheaper storage
# Use Elasticsearch ILM policies

# 3. Set up automatic cleanup
# Cron job to delete logs older than X days
crontab -e
# Add: 0 2 * * * find /data/elasticsearch -name "*.log" -mtime +30 -delete
```

**SLA Target:**
- Detection: <1 minute (automatic alert)
- Recovery: <10 minutes (delete old data or expand)

---

### Scenario 6: OAuth/Authentication Down

**Symptoms:**
- Users can't log in
- Redirects to Google OAuth, but callback fails
- Users see "Unauthorized" or blank page

**Diagnosis:**
```bash
# Check OAuth2-Proxy status
docker-compose ps oauth2-proxy
docker-compose logs oauth2-proxy --tail=50

# Test OAuth flow manually
curl -L https://ide.kushnir.cloud/oauth2/start

# Check if Google OAuth is reachable
curl -L https://accounts.google.com/o/oauth2/v2/auth

# Check Vault for OAuth secrets
vault kv get secret/production/google/oauth

# Verify secrets are loaded in .env
grep GOOGLE .env

# Check if credentials are still valid
# Go to Google Cloud Console and verify OAuth2 credentials
```

**Common Issues:**

```bash
# 1. Redirect URI mismatch
# Your app registered callback: https://ide.kushnir.cloud/oauth2/callback
# But your .env might have: https://ide.kushnir.dev/oauth2/callback
# Match them exactly

# 2. OAuth client secret expired
# Log into Google Cloud Console
# Verify OAuth2 client is still valid
# If needed, create new credentials and update Vault

# 3. OAuth2-Proxy lost connection to Vault
docker-compose logs oauth2-proxy | grep -i "vault\|connection"

# 4. Cookie encryption key changed
# If you restart oauth2 without persistent cookie secret:
# All existing cookies become invalid
# Users must log in again (OK, not a critical issue)
```

**Recovery:**
```bash
# Option 1: Restart OAuth2-Proxy
docker-compose restart oauth2-proxy
wait 10 seconds

# Option 2: Verify credentials in Vault
vault kv get secret/production/google/oauth
vault kv get secret/production/oauth2-proxy

# If missing:
vault kv put secret/production/google/oauth \
  client-id='<new-value>' \
  client-secret='<new-value>'

docker-compose restart oauth2-proxy

# Option 3: Test OAuth locally (bypass Caddy)
docker-compose exec oauth2-proxy \
  curl -L http://localhost:4180/oauth2/start

# Option 4: Check Caddy OAuth configuration
docker-compose logs caddy | grep -iE "oauth|error"

# If Caddy has wrong config, edit Caddyfile.production and reload
docker-compose exec caddy \
  caddy reload --config /etc/caddy/Caddyfile
```

**SLA Target:**
- Detection: <1 minute (users can't log in)
- Recovery: <5 minutes

---

## Service-Specific Troubleshooting

### Redis Issues

**Connection Failing:**
```bash
# Check if Redis is running
docker-compose ps redis

# Check Redis logs
docker-compose logs redis --tail=50

# Test connection
docker-compose exec redis redis-cli ping  # should return PONG

# Check memory usage
docker-compose exec redis redis-cli info memory | grep used

# Check number of connected clients
docker-compose exec redis redis-cli info clients | grep connected
```

**High Memory Usage:**
```bash
# Check eviction policy
docker-compose exec redis redis-cli CONFIG GET maxmemory-policy

# If policy is set correctly (allkeys-lru), eviction should happen automatically
# If memory still high:

# 1. Check for memory leaks in application
# 2. Reduce data retention
# 3. Increase Redis max memory limit
```

### PostgreSQL Issues

**Connection Failing:**
```bash
# Check if PostgreSQL is running
docker-compose ps postgres

# Check logs
docker-compose logs postgres --tail=50

# Test connection
docker-compose exec postgres pg_isready

# Check number of connections
docker-compose exec postgres \
  psql -c "SELECT count(*) FROM pg_stat_activity"

# Check if WAL is filling disk
du -sh /data/postgres/  # if > 100GB, may be WAL problem
```

**Slow Queries:**
```bash
# Enable slow query log
docker-compose exec postgres \
  psql -c "ALTER SYSTEM SET log_min_duration_statement = 1000"  # log > 1s

docker-compose exec postgres psql -c "SELECT pg_reload_conf()"

# View slow queries
docker compose logs postgres | grep "duration: " | tail -20

# Analyze and optimize
docker-compose exec postgres \
  psql -c "ANALYZE <table>_name"
```

### Elasticsearch Issues

**Cluster Not Healthy:**
```bash
# Check cluster health
curl http://localhost:9200/_cluster/health?pretty

# Check for red indices
curl http://localhost:9200/_cat/indices?health=red

# List all shards
curl http://localhost:9200/_cat/shards?v

# If shard allocation failing:
curl -X PUT http://localhost:9200/_cluster/settings \
  -H "Content-Type: application/json" \
  -d '{"transient": {"cluster.routing.allocation.node_concurrent_recoveries": 2}}'
```

**Disk Space Issues:**
```bash
# Check disk usage
curl http://localhost:9200/_cat/allocation?v

# Force merge to save space
curl -X POST "localhost:9200/<index>/_forcemerge?max_num_segments=1"

# Delete old indices
curl -X DELETE "localhost:9200/<old-index>"
```

---

## Recovery & Escalation Procedures

### Escalation Decision Tree

```
Issue detected
    ↓
Is service completely down? (P1)
    ├─ YES → Page on-call engineer immediately
    │         Activate incident response
    │         Update status page: "MAJOR OUTAGE"
    │         Try automated recovery: docker-compose restart
    │         If not fixed in 5 min: Escalate to SRE lead
    │
    └─ NO → Is error rate > 1%? (P2)
             ├─ YES → Investigate root cause
             │         Check logs, metrics, resource utilization
             │         Try targeted restart of failing service
             │         If not fixed in 10 min: Page on-call
             │
             └─ NO → Is latency > 500ms p99? (P2)
                     ├─ YES → Investigate performance issues
                     │         Check database, Ollama, disk I/O
                     │         May be expected (Ollama inference)
                     │         No page needed if expected
                     │
                     └─ NO → Is alert firing intermittently? (P3-P4)
                             └─ Log issue for investigation during business hours
```

### Standard Recovery Procedures

**Restart Service (30 seconds):**
```bash
docker-compose restart <service-name>
sleep 10
docker-compose ps <service-name>
```

**Full Stack Restart (3 minutes):**
```bash
docker-compose down
sleep 30
docker-compose up -d
sleep 30
docker-compose ps
```

**Drain Traffic & Restart (5 minutes):**
```bash
# Stop receiving new traffic
docker-compose exec caddy \
  caddy respond /health "" 503

# Wait for in-flight requests to complete
sleep 60

# Restart problematic service
docker-compose restart <service-name>
sleep 30

# Resume traffic
docker-compose exec caddy \
  caddy reload --config /etc/caddy/Caddyfile
```

**Rollback to Previous Version (10 minutes):**
```bash
# Get previous git commit
git log --oneline -5
git checkout <previous-commit-hash>

# Rebuild and restart
docker-compose build
docker-compose up -d
```

---

## Post-Incident Review

### Incident Report Template

```markdown
# Incident Report: [SERVICE] - [DATE]

## Summary
- **Severity:** P1 / P2 / P3 / P4
- **Duration:** HH:MM (start → resolved)
- **Impact:** X users, Y transactions lost
- **Root Cause:** [Brief description]

## Timeline
- HH:MM - Alert fired: [description]
- HH:MM - Issue confirmed by [who]
- HH:MM - Recovery started: [action]
- HH:MM - Service recovered
- HH:MM - Incident declared resolved

## Root Cause Analysis
[Detailed explanation of what went wrong]

## Impact Assessment
- Users affected: X
- Transactions failed: Y
- Data loss: Z
- SLA impact: [Yes/No] - [explanation]

## Resolution Steps Taken
1. [Step 1]
2. [Step 2]
3. [Step 3]

## Post-Incident Improvements
- [ ] Action 1: [Description]
- [ ] Action 2: [Description]
- [ ] Action 3: [Description]

## Timeline to Close
- [ ] Action 1: Due [DATE]
- [ ] Action 2: Due [DATE]
- [ ] Action 3: Due [DATE]

## Attendees
- [Name] - Team
- [Name] - Team
```

### Blameless Culture Guidelines

✅ **DO:**
- Celebrate quick detection and recovery
- Thank people for helping
- Focus on systemic improvements
- Ask "What can we improve?" not "Who failed?"

❌ **DON'T:**
- Blame individuals
- Punish for incidents
- Hide issues from the team
- Repeat the same mistake twice

---

**This runbook is a living document. Update with new incidents and learnings.**

