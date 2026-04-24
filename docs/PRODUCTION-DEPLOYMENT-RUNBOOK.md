# Production Deployment Runbook

**Version**: 1.0  
**Last Updated**: April 22, 2026  
**Status**: ✅ PRODUCTION READY  
**Target Date**: April 30, 2026  

---

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Deployment Steps](#deployment-steps)
3. [Monitoring & Verification](#monitoring--verification)
4. [Troubleshooting](#troubleshooting)
5. [Rollback Procedures](#rollback-procedures)
6. [Post-Deployment Validation](#post-deployment-validation)

---

## Pre-Deployment Checklist

### 1. Security & Compliance (24 hours before)

- [x] **Security Audit** (#1463): Zero vulnerabilities confirmed
  - Command: `pnpm audit`
  - Expected: No critical or high CVEs
  - Evidence: `artifacts/security/security-audit-report-apr22-complete.md`

- [ ] **Compliance Review**: All policies met
  - Data handling policies ✓
  - Access control policies ✓
  - Encryption policies ✓
  - Audit logging policies ✓

### 2. Performance Validation (Scheduled Apr 24-25)

- [ ] **Baseline Load Test** (#1474):
  - Target: 100 concurrent users, 10 minutes
  - Success Criteria: p99 < 500ms, error rate < 0.1%
  - Command: `bash scripts/loadtest/run-performance-tests.sh baseline`

- [ ] **Spike Test** (#1474):
  - Target: 1000 concurrent users, 5 minutes
  - Success Criteria: p99 < 1500ms, error rate < 1%
  - Command: `bash scripts/loadtest/run-performance-tests.sh spike`

- [ ] **Sustained Load Test** (#1474):
  - Target: 500 concurrent users, 30 minutes
  - Success Criteria: No memory growth > 100MB
  - Command: `bash scripts/loadtest/run-performance-tests.sh sustained`

### 3. Team Sign-Offs (Apr 27-29)

- [ ] **Security Team**: Approved security audit
- [ ] **Infrastructure Team**: Infrastructure readiness confirmed
- [ ] **Engineering Team**: Code quality and stability verified
- [ ] **Operations Team**: Deployment procedures reviewed
- [ ] **Release Manager**: Final approval for production deployment

### 4. Database Backup (6 hours before deployment)

```bash
# Backup production database
ssh akushnir@192.168.168.31 "docker exec postgres pg_dump -U codeserver > /mnt/nas/backups/production/pre-deployment-$(date +%Y%m%d-%H%M%S).sql"

# Verify backup
ssh akushnir@192.168.168.31 "ls -lh /mnt/nas/backups/production/ | head -5"

# Expected: Latest backup should be < 1 hour old
```

### 5. NAS Sync (6 hours before deployment)

```bash
# Verify NAS connectivity
ssh akushnir@192.168.168.31 "mount | grep nas"

# Verify backup capacity
ssh akushnir@192.168.168.31 "df -h /mnt/nas"

# Expected: /mnt/nas mounted, > 500GB available
```

### 6. Replica Health Check (6 hours before deployment)

```bash
# Check replica SSH access
ssh akushnir@192.168.168.42 "docker ps"

# Check replication status
ssh akushnir@192.168.168.31 "docker exec postgres psql -U codeserver -c \"SELECT * FROM pg_stat_replication;\""

# Expected: Replication lag < 100ms
```

### 7. Monitoring Setup (3 hours before deployment)

```bash
# Verify Prometheus running
curl http://192.168.168.31:9090/api/v1/status/tsdb | jq '.data.seriesCount'

# Verify alerting enabled
curl http://192.168.168.31:9090/api/v1/alerts | jq '.data | length'

# Verify dashboards ready
# - System Overview
# - Application Performance
# - Database Health
# - Cache Statistics
```

---

## Deployment Steps

### Phase 1: Pre-Deployment (30 minutes before)

#### 1.1 Final Validation

```bash
# SSH to primary deployment host
ssh akushnir@192.168.168.31

# Verify current version
docker inspect --format='{{.Config.Image}}' code-server | grep -o ':.*' | head -c 20

# Expected: Current version tag (e.g., :v2.1-prod-stable)
```

#### 1.2 Enable Maintenance Mode (if needed)

```bash
# Create maintenance page
cat > /opt/code-server/maintenance.html <<EOF
<!DOCTYPE html>
<html><head><title>Maintenance</title></head>
<body><h1>System Maintenance - Check back in 15 minutes</h1></body>
</html>
EOF

# Optional: Route requests to maintenance page
# nginx -t && systemctl reload nginx
```

#### 1.3 Notification to Users (if applicable)

```bash
# Via Slack/email (manual):
# "Production deployment scheduled: [START_TIME] UTC"
# "Expected downtime: ~10 minutes"
# "Services may be unavailable during this period"
```

### Phase 2: Deployment (10-15 minutes)

#### 2.1 Pull Latest Images

```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Navigate to deployment directory
cd /opt/code-server

# Update docker-compose.yml to latest version
git pull origin main

# Expected: "Already up to date" or shows new commits
```

#### 2.2 Pre-Deployment Database Migration (if needed)

```bash
# Check if migrations needed
docker exec postgres psql -U codeserver -c "\dt" | wc -l

# Run migrations if needed
docker exec code-server npm run migrate:up

# Verify migration success
docker logs code-server --tail 50 | grep -i "migration\|error"

# Expected: "Migration completed successfully" or "No pending migrations"
```

#### 2.3 Stop Current Services

```bash
# Stop services gracefully (30 second grace period)
docker compose down --timeout 30

# Verify stopped
docker compose ps

# Expected: All containers stopped
```

#### 2.4 Update and Start New Services

```bash
# Update docker images
docker compose pull

# Start with new version
docker compose up -d code-server postgres redis oauth2-proxy caddy

# Wait for services to be healthy
sleep 10
docker compose ps

# Expected: All services "Up" status
```

#### 2.5 Verify Deployment

```bash
# Check application health
curl -s http://localhost:8080/healthz | jq '.status'

# Expected: "healthy" or "ok"

# Check database connection
curl -s http://localhost:8080/api/health | jq '.database'

# Expected: "connected" or "ok"

# Check cache connection
curl -s http://localhost:8080/api/health | jq '.cache'

# Expected: "connected" or "ok"
```

### Phase 3: Replica Sync (5-10 minutes)

#### 3.1 Primary Replication Status

```bash
# Verify replication to replica (192.168.168.42)
docker exec postgres psql -U codeserver -c "SELECT client_addr, state, write_lag FROM pg_stat_replication;"

# Expected: One row with client_addr=192.168.168.42, state=streaming, write_lag < 100ms
```

#### 3.2 Replica Verification

```bash
# SSH to replica
ssh akushnir@192.168.168.42

# Check replica is in standby
docker exec postgres psql -U codeserver -c "SELECT pg_is_in_recovery();"

# Expected: true

# Verify data synced
docker exec postgres psql -U codeserver -c "SELECT COUNT(*) FROM users;" 

# Expected: Same count as primary
```

### Phase 4: Monitoring & Alerting (Post-Deployment)

#### 4.1 Enable Full Monitoring

```bash
# Restart monitoring collection
docker exec prometheus kill -HUP 1

# Verify metrics flowing
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result | length'

# Expected: > 10 (multiple services reporting)
```

#### 4.2 Verify Alert Rules

```bash
# Check alert rules loaded
curl -s 'http://localhost:9090/api/v1/rules' | jq '.data.groups | length'

# Expected: > 5 alert groups

# List active alerts (should be none)
curl -s 'http://localhost:9090/api/v1/alerts' | jq '.data.alerts | length'

# Expected: 0 (no unexpected alerts)
```

---

## Monitoring & Verification

### 1. Application Metrics (First 30 minutes)

Monitor these metrics continuously:

```bash
# Request latency (p99 should be < 500ms)
curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,rate(http_request_duration_seconds_bucket[5m]))' | jq '.data.result[0].value[1]'

# Error rate (should be < 0.1%)
curl -s 'http://localhost:9090/api/v1/query?query=rate(http_requests_failed_total[5m])' | jq '.data.result[0].value[1]'

# Active connections (should be stable)
curl -s 'http://localhost:9090/api/v1/query?query=pg_stat_activity_count' | jq '.data.result[0].value[1]'
```

### 2. System Resources (First hour)

Monitor system health:

```bash
# CPU usage (should be < 30% baseline)
curl -s 'http://localhost:9090/api/v1/query?query=node_cpu_usage_percent' | jq '.data.result[0].value[1]'

# Memory usage (should be < 2GB)
curl -s 'http://localhost:9090/api/v1/query?query=node_memory_usage_bytes' | jq '.data.result[0].value[1] / 1024 / 1024 / 1024'

# Disk usage (should be stable)
curl -s 'http://localhost:9090/api/v1/query?query=node_disk_used_bytes' | jq '.data.result[0].value[1] / 1024 / 1024 / 1024'
```

### 3. Database Health (First hour)

Verify database stability:

```bash
# Connection count
docker exec postgres psql -U codeserver -c "SELECT count(*) FROM pg_stat_activity;"

# Long-running queries (should be none)
docker exec postgres psql -U codeserver -c "SELECT pid, usename, query, query_start FROM pg_stat_activity WHERE state = 'active' AND query NOT ILIKE '%pg_stat_activity%' ORDER BY query_start;"

# Replication lag
docker exec postgres psql -U codeserver -c "SELECT client_addr, write_lag, flush_lag FROM pg_stat_replication;"
```

### 4. Service Verification

```bash
# Application responding
curl -w "HTTP %{http_code}\n" -s http://localhost:8080/healthz

# API endpoints available
curl -w "HTTP %{http_code}\n" -s http://localhost:8080/api/v1/status

# WebSocket connectivity
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" http://localhost:8080/api/ws

# Cache responsive
curl -s http://localhost:8080/api/cache/health | jq '.status'
```

---

## Troubleshooting

### Issue: Application Not Responding (HTTP 502/503)

**Symptoms**: Gateway errors, requests timing out

**Diagnosis**:
```bash
# Check application logs
docker logs code-server --tail 100 | grep -i "error\|exception"

# Check if port 8080 is listening
docker ps | grep code-server

# Check database connection
docker logs code-server | grep -i "database\|connection"
```

**Resolution**:
```bash
# Restart application
docker compose restart code-server

# Wait for health check
sleep 5
curl http://localhost:8080/healthz

# If still failing, check logs for specific errors
docker logs code-server --since 5m
```

### Issue: Database Replication Lag High (> 1s)

**Symptoms**: Replica falling behind, write_lag > 1000ms

**Diagnosis**:
```bash
# Check replication status
docker exec postgres psql -U codeserver -c "SELECT write_lag, flush_lag, replay_lag FROM pg_stat_replication;"

# Check if replica is overloaded
ssh akushnir@192.168.168.42 "top -bn1 | head -20"

# Check network between hosts
ping -c 5 192.168.168.42
```

**Resolution**:
```bash
# Option 1: Optimize write rate on primary
# Batch writes where possible
# Check for long-running transactions

# Option 2: Restart replica PostgreSQL
ssh akushnir@192.168.168.42 "docker restart postgres"

# Wait for catch-up
sleep 30
docker exec postgres psql -U codeserver -c "SELECT write_lag FROM pg_stat_replication;"
```

### Issue: High Memory Usage (> 2GB)

**Symptoms**: Docker OOM kills, slow performance

**Diagnosis**:
```bash
# Check memory usage per container
docker stats --no-stream

# Check for memory leaks in logs
docker logs code-server --since 1h | grep -i "memory\|gc\|heap"

# Check database memory
docker exec postgres psql -U codeserver -c "SELECT sum(heap_blks_read) FROM pg_stat_user_tables;"
```

**Resolution**:
```bash
# Check for data accumulation
# - Are old logs being archived?
# - Are sessions being cleaned up?
# - Is cache eviction working?

# Graceful restart if needed
docker compose restart code-server --timeout 30

# Monitor memory after restart
watch -n 2 'docker stats --no-stream | grep code-server'
```

### Issue: High Error Rate (> 1%)

**Symptoms**: User complaints, alert triggered, 5xx responses

**Diagnosis**:
```bash
# Check application logs for errors
docker logs code-server --since 30m | grep -i "error" | tail -20

# Check for specific error codes
curl -s 'http://localhost:9090/api/v1/query?query=increase(http_requests_total{status=~"5.."}[5m])' | jq '.'

# Check database errors
docker logs postgres | grep -i "error\|fail" | tail -10
```

**Resolution**:
```bash
# Identify specific error pattern
# Common causes:
# 1. Database timeout: Increase connection pool
# 2. Out of memory: Restart services
# 3. Disk full: Check /opt and /mnt/nas
# 4. Long queries: Optimize slow queries

# Check disk space
df -h /opt /mnt/nas

# Check slow queries
docker exec postgres psql -U codeserver -c "SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"
```

---

## Rollback Procedures

### Scenario: Critical Issue Found (< 30 minutes)

#### Step 1: Make Decision
```bash
# Consult: VP Engineering, Infrastructure Lead, Release Manager
# Timeline: Decision within 5 minutes
# Criteria: Multiple critical errors, data corruption risk, or availability < 99%
```

#### Step 2: Immediate Rollback (< 5 minutes)

```bash
# SSH to primary
ssh akushnir@192.168.168.31

# Get previous image tag
git log --oneline -5 | head -1

# Revert docker-compose.yml
git checkout HEAD~1 -- docker-compose.yml

# Stop current services
docker compose down --timeout 10

# Pull previous image
docker compose pull

# Start with previous version
docker compose up -d code-server postgres redis oauth2-proxy caddy

# Verify health
sleep 10
curl http://localhost:8080/healthz
```

#### Step 3: Verify Rollback

```bash
# Check application responding
curl -s http://localhost:8080/api/health | jq '.status'

# Check data integrity
docker exec postgres psql -U codeserver -c "SELECT COUNT(*) FROM users;"

# Monitor metrics
curl -s 'http://localhost:9090/api/v1/query?query=rate(http_requests_failed_total[1m])'
```

#### Step 4: Notify Stakeholders

```bash
# Message: "Critical issue detected, rolled back to previous version"
# Include: Rollback time, impact duration, root cause (when determined)
# Action: Post-incident review scheduled for [DATE]
```

### Scenario: Database-Level Issue (Transaction Rollback)

```bash
# If corrupted data detected:

# 1. Stop application
docker compose stop code-server

# 2. Restore from backup
ssh akushnir@192.168.168.31 "docker exec postgres psql -U codeserver < /mnt/nas/backups/production/pre-deployment-TIMESTAMP.sql"

# 3. Verify restore
docker exec postgres psql -U codeserver -c "SELECT COUNT(*) FROM users;"

# 4. Restart application
docker compose start code-server

# 5. Verify health
curl http://localhost:8080/healthz
```

---

## Post-Deployment Validation

### 1. First 24 Hours

#### Hourly Checks
```bash
# Every hour for first 24 hours:

# Application health
curl -s http://localhost:8080/healthz | jq '.status'

# Error rate
curl -s 'http://localhost:9090/api/v1/query?query=rate(http_requests_failed_total[1h])' | jq '.data.result[0].value[1]'

# Database replication lag
docker exec postgres psql -U codeserver -c "SELECT write_lag FROM pg_stat_replication;"

# Memory trend
docker stats --no-stream | grep code-server | awk '{print $6}'
```

#### Critical Thresholds
- Error rate stays < 0.5%
- Response time p99 < 1 second
- Memory stays < 2.5GB
- Replication lag < 500ms

### 2. First Week

- Daily review of error patterns
- Daily performance metric review
- Weekly database optimization check
- Weekly backup verification

### 3. First Month

- Comprehensive performance baseline vs pre-deployment
- Capacity planning analysis
- Security event review
- Team retrospective

---

## Success Criteria

✅ **Deployment Successful When:**
- Application responds to all health checks
- No critical or high-severity alerts
- Error rate < 0.1% for first hour
- Database replication in sync (lag < 100ms)
- All user-facing services operational
- No data corruption detected
- All team approvals obtained

🟡 **Rollback If:**
- Any critical error detected
- Error rate > 5% sustained
- Data corruption confirmed
- Replication broken or lag > 10 seconds
- Application availability < 99% in first hour

---

## Contact & Escalation

**On-Call Engineer**: Available [24/7]  
**Infrastructure Lead**: Escalation authority  
**VP Engineering**: Emergency decision maker  
**Release Manager**: Deployment execution authority

---

**Runbook Status**: ✅ READY FOR PRODUCTION  
**Last Updated**: April 22, 2026  
**Next Review**: April 30, 2026 (post-deployment)

