# Staging Deployment Validation Checklist
## April 27-29, 2026

**Purpose**: Complete dry-run test of production deployment procedures on staging host (192.168.168.42)  
**Timeline**: Apr 27 8:00 AM - Apr 27 1:00 PM (estimated 5 hours)  
**Team**: Release engineer, infrastructure lead, observability engineer  
**Host**: 192.168.168.42 (akushnir@failover)

---

## Pre-Deployment Phase (Apr 27, 7:30-8:00 AM)

### Team Preparation
- [ ] All team members have SSH access to 192.168.168.42
- [ ] Each team member has required tools (docker, git, curl, psql)
- [ ] Slack #deployment channel is active for real-time updates
- [ ] PagerDuty/monitoring dashboards are open
- [ ] Runbook is accessible: `docs/PRODUCTION-DEPLOYMENT-RUNBOOK.md`
- [ ] Alert rules are ready: `config/prometheus/alert-rules-production.yml`
- [ ] Incident response runbook accessible: `docs/INCIDENT-RESPONSE-RUNBOOK.md`

### Environment Verification
- [ ] Staging host is reachable: `ssh akushnir@192.168.168.42`
- [ ] Current deployment on staging verified
- [ ] Backup created: `docker exec postgres pg_dump > staging-backup-apr27.sql`
- [ ] Disk space sufficient: `df -h /` shows >20% free
- [ ] Docker services running: `docker compose ps`
- [ ] Database replication status checked: `psql -c "SELECT * FROM pg_stat_replication;"`
- [ ] Current metrics baseline captured (CPU, memory, disk)

### Documentation Setup
- [ ] Created deployment log file: `artifacts/staging/staging-deployment-apr27.log`
- [ ] Opened results tracking sheet
- [ ] Timestamps are synced: `date -u`

---

## Deployment Execution Phase (Apr 27, 8:00 AM - 12:00 PM)

### Pre-Deployment Checklist (Follow from #1453)
- [ ] **Environment Config** (10 min)
  - [ ] Load environment variables: `source .env.staging`
  - [ ] Verify config separation: no hardcoded values
  - [ ] Check credentials are env vars, not in Caddyfile
  - [ ] Verify secret sources (GSM preferred, .env fallback)

- [ ] **Security Baseline** (10 min)
  - [ ] Verify zero critical CVEs: `pnpm audit --production | grep critical`
  - [ ] Check container images: no root user (verify UID > 0)
  - [ ] Confirm Redis authentication: `redis-cli CONFIG GET requirepass`
  - [ ] Verify CSRF cookie settings (SameSite=none for cross-site)
  - [ ] Check SSL/TLS versions (1.2+ only)

- [ ] **Database Backup** (5 min)
  - [ ] Create staging backup: `docker exec postgres pg_dump -U postgres > staging-pre-deploy.sql`
  - [ ] Verify backup size: `ls -lh staging-pre-deploy.sql`
  - [ ] Test restore on dummy DB: `createdb test_restore; pg_restore < staging-pre-deploy.sql`
  - [ ] Verify restore successful

- [ ] **Replica Health** (5 min)
  - [ ] SSH to replica: `ssh failover` (if available)
  - [ ] Check replica lag: `psql -c "SELECT now() - pg_last_wal_receive_lsn();"`
  - [ ] Verify lag < 1 second
  - [ ] Check replica services: `docker compose ps`

- [ ] **Monitoring Setup** (10 min)
  - [ ] Prometheus is collecting metrics
  - [ ] Grafana dashboards loading: `curl http://localhost:3000/api/dashboards/db/prod-monitoring`
  - [ ] Alert rules loaded: `curl http://localhost:9090/api/v1/rules | jq '.data.groups[] | length'`
  - [ ] AlertManager receiving alerts: `curl http://localhost:9093/api/v1/alerts`

**Subtotal Pre-Deployment**: 40 min ✓

### Deployment Steps (Follow from #1453 - 4 phases)

#### Phase 1: Pre-Deployment (8:40-8:55 AM) - 15 min
- [ ] Stop all services gracefully
  ```bash
  docker compose down
  echo "[$(date -u)] Phase 1: Services stopped" >> deployment.log
  ```
- [ ] Document action
  - [ ] Time: $(date -u +%H:%M)
  - [ ] Status: ✓ Success
  - [ ] Issues: None

#### Phase 2: Deployment (8:55-9:10 AM) - 15 min
- [ ] Pull latest code
  ```bash
  git fetch origin
  git checkout main
  echo "[$(date -u)] Phase 2: Code updated" >> deployment.log
  ```
- [ ] Start services
  ```bash
  docker compose up -d
  sleep 30
  docker compose ps
  echo "[$(date -u)] Phase 2: Services started" >> deployment.log
  ```
- [ ] Monitor startup
  - [ ] All containers in "Up" state
  - [ ] No restart loops: `docker compose logs --tail 50 | grep -i error`
  - [ ] Health check passing
- [ ] Document action
  - [ ] Time: $(date -u +%H:%M)
  - [ ] Status: ✓ Success
  - [ ] Errors encountered: (list any, then resolved?)

#### Phase 3: Replica Sync (9:10-9:20 AM) - 10 min
- [ ] Check replication status
  ```bash
  psql -c "SELECT * FROM pg_stat_replication;"
  psql -c "SELECT now() - pg_last_wal_receive_lsn();"
  echo "[$(date -u)] Phase 3: Replica status OK" >> deployment.log
  ```
- [ ] Verify data consistency (if applicable)
- [ ] Document action
  - [ ] Replication lag: ___ seconds (target: <1s)
  - [ ] Status: ✓ Success
  - [ ] Issues: None

#### Phase 4: Monitoring Startup (9:20-9:30 AM) - 10 min
- [ ] Verify monitoring is active
  ```bash
  curl http://localhost:9090/api/v1/query?query=up
  curl http://localhost:3000/api/health
  echo "[$(date -u)] Phase 4: Monitoring active" >> deployment.log
  ```
- [ ] Check alert rules are loaded
- [ ] Verify metrics collection started
- [ ] Document action
  - [ ] Time: $(date -u +%H:%M)
  - [ ] Status: ✓ Success
  - [ ] Issues: None

**Subtotal Deployment Execution**: 50 min ✓  
**Actual Deployment Complete**: 9:30 AM ✓

---

## Post-Deployment Verification Phase (Apr 27, 9:30 AM - 10:30 AM)

### Service Health (10 min)
- [ ] **Health Check Endpoint**
  ```bash
  curl -s http://localhost:3000/api/health | jq '.status'
  # Expected: "healthy"
  ```
  - [ ] Status: ✓ Healthy
  - [ ] Response time: ___ms (target: <100ms)

- [ ] **API Endpoints**
  ```bash
  curl -s http://localhost:3000/api/workspaces | jq '.data | length'
  # Expected: Returns workspace list
  ```
  - [ ] Workspaces endpoint: ✓ Responding
  - [ ] Response time: ___ms

  ```bash
  curl -s http://localhost:3000/api/users/me | jq '.id'
  # Expected: Returns current user
  ```
  - [ ] Auth endpoint: ✓ Responding
  - [ ] Response time: ___ms

- [ ] **Web UI**
  ```bash
  curl -I http://localhost:3000
  # Expected: HTTP 200
  ```
  - [ ] Status code: 200 ✓
  - [ ] Response time: ___ms

### Database Health (10 min)
- [ ] **Connection Test**
  ```bash
  psql -c "SELECT version();"
  # Expected: PostgreSQL version output
  ```
  - [ ] Status: ✓ Connected
  - [ ] Version: ____________

- [ ] **Replication Check**
  ```bash
  psql -c "SELECT now() - pg_last_wal_receive_lsn() AS replication_lag;"
  # Expected: <1 second
  ```
  - [ ] Replication lag: ___ms (target: <100ms)
  - [ ] Status: ✓ In sync

- [ ] **Query Performance**
  ```bash
  psql -c "SELECT query, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5;"
  # Expected: No query > 1 second
  ```
  - [ ] Slow queries: None detected ✓
  - [ ] Highest avg time: ___ms

### Application Metrics (10 min)
- [ ] **Request Latency** (from Prometheus)
  ```bash
  curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket[5m]))' | jq '.data.result[].value[1]'
  # Expected: <0.5 seconds
  ```
  - [ ] p95 latency: ___ms (target: <500ms)
  - [ ] Status: ✓ Acceptable

- [ ] **Error Rate** (from Prometheus)
  ```bash
  curl -s 'http://localhost:9090/api/v1/query?query=rate(http_requests_total{status=~"5.."}[5m])' | jq '.data.result[].value[1]'
  # Expected: <0.01 (1%)
  ```
  - [ ] 5xx error rate: _____% (target: <1%)
  - [ ] Status: ✓ Acceptable

- [ ] **Throughput**
  ```bash
  curl -s 'http://localhost:9090/api/v1/query?query=rate(http_requests_total[5m])' | jq '.data.result[].value[1]'
  # Expected: Normal baseline traffic
  ```
  - [ ] Requests/second: ___/s
  - [ ] Status: ✓ Normal

### System Resources (10 min)
- [ ] **CPU Usage**
  ```bash
  docker stats code-server --no-stream | awk 'NR==2 {print $3}'
  # Expected: <20% (normal baseline)
  ```
  - [ ] Current CPU: _____% (target: <20%)
  - [ ] Status: ✓ Acceptable

- [ ] **Memory Usage**
  ```bash
  docker stats code-server --no-stream | awk 'NR==2 {print $4}'
  # Expected: <2GB
  ```
  - [ ] Current Memory: ___MB (target: <2GB)
  - [ ] Status: ✓ Acceptable

- [ ] **Disk Space**
  ```bash
  df -h / | awk 'NR==2 {print $5}'
  # Expected: <60% used
  ```
  - [ ] Disk used: _____% (target: <60%)
  - [ ] Status: ✓ Acceptable

### Alert Rule Testing (10 min)
- [ ] **Create test alert** (verify notification works)
  ```bash
  curl -X POST http://localhost:9093/api/v1/alerts \
    -H 'Content-Type: application/json' \
    -d '{"alerts":[{"status":"firing","labels":{"alertname":"TestAlert"},"annotations":{"description":"Test"}}]}'
  ```
  - [ ] Alert appeared in AlertManager: ✓ Yes
  - [ ] Notification sent: ✓ Yes (check Slack/PagerDuty)
  - [ ] Response time: ___ms

**Subtotal Post-Deployment Verification**: 50 min ✓

---

## Monitoring Phase (Apr 27, 10:30 AM - 11:00 AM)

### Continuous Monitoring (30 min)
- [ ] **15-minute mark** (10:45 AM)
  - [ ] No alerts firing: ✓ / ✗
  - [ ] Error rate stable: ___% (normal baseline)
  - [ ] Memory stable: ___MB
  - [ ] Latency stable: ___ms

- [ ] **30-minute mark** (11:00 AM)
  - [ ] No new errors in logs: ✓ / ✗
  - [ ] Dashboard metrics normal: ✓ / ✗
  - [ ] All services healthy: ✓ / ✗
  - [ ] No memory growth: ✓ / ✗

---

## Rollback Testing (Apr 27, 11:00-11:30 AM)

### Test Rollback Procedure
- [ ] **Trigger rollback**
  ```bash
  docker compose down
  git revert HEAD
  docker compose up -d
  sleep 30
  curl http://localhost:3000/api/health
  ```
  - [ ] Rollback execution time: ___min
  - [ ] Services recovered: ✓ All healthy
  - [ ] Data intact: ✓ Yes

- [ ] **Verify data after rollback**
  ```bash
  psql -c "SELECT COUNT(*) FROM workspaces;"
  # Should match pre-deployment count
  ```
  - [ ] Data consistency: ✓ Verified
  - [ ] Database replication: ✓ Synced

- [ ] **Return to deployed version**
  ```bash
  git reset --hard HEAD~1
  docker compose up -d
  ```
  - [ ] Re-deployment successful: ✓ Yes

---

## Final Assessment (Apr 27, 11:30 AM - 12:00 PM)

### Success Criteria Evaluation

#### Pre-Deployment Checklist
- [ ] 100% complete: ✓ Yes / ✗ No
- [ ] Issues found: None / (list)
- [ ] Status: ✓ PASS

#### Deployment Execution
- [ ] All 4 phases completed: ✓ Yes
- [ ] Zero errors: ✓ Yes / ✗ Errors (describe)
- [ ] All steps 10/10 successful: ✓ Yes
- [ ] Status: ✓ PASS / ✗ CONDITIONAL PASS / ✗ FAIL

#### Post-Deployment
- [ ] All health checks passing: ✓ Yes
- [ ] Zero errors in logs: ✓ Yes
- [ ] Metrics normal: ✓ Yes
- [ ] Database synced: ✓ Yes
- [ ] Status: ✓ PASS

#### Monitoring
- [ ] No persistent errors: ✓ Yes
- [ ] Stable metrics: ✓ Yes
- [ ] Alert rules working: ✓ Yes
- [ ] Status: ✓ PASS

#### Rollback Test
- [ ] Rollback successful: ✓ Yes
- [ ] Data integrity maintained: ✓ Yes
- [ ] Quick recovery (<2 min): ✓ Yes
- [ ] Status: ✓ PASS / ✗ FAIL

### Overall Recommendation

**Choose one:**

#### ✅ GREEN LIGHT - GO FOR PRODUCTION
```
✓ Pre-deployment: 100% complete, no issues
✓ Deployment: 0 errors, 10/10 steps successful
✓ Post-deployment: 0 errors, all health checks passing
✓ Monitoring: Stable metrics, no errors
✓ Rollback tested: Works as documented
✓ Team confidence: HIGH
```
**Action**: Ready for April 30 production deployment

#### ⚠️  YELLOW LIGHT - CONDITIONAL GO
```
⚠ Pre-deployment: 1-2 minor issues (not blocking)
⚠ Deployment: 1-2 issues encountered but resolved
⚠ Post-deployment: Some metrics slightly elevated
⚠ Monitoring: Brief spikes but stable afterward
⚠ Team confidence: MEDIUM
```
**Action**: Ready for April 30 with enhanced monitoring
**Required**: Document issues and verify fixes before deployment

#### ❌ RED LIGHT - DO NOT DEPLOY
```
✗ Pre-deployment: Critical issues found
✗ Deployment: Rollback required or failed
✗ Post-deployment: Health checks failing
✗ Monitoring: Persistent errors/memory leaks
✗ Team confidence: LOW
```
**Action**: Do NOT proceed to production
**Required**: Fix issues and re-test staging

---

## Documentation & Sign-Off

### Deployment Report
**Report File**: `artifacts/staging/STAGING-DEPLOYMENT-APR27-RESULTS.md`

**Completed by**:
- [ ] Release Engineer: _____________ (signature)
- [ ] Infrastructure Lead: _____________ (signature)
- [ ] Observability Engineer: _____________ (signature)

**Date**: April 27, 2026  
**Time Completed**: ___:___ AM  
**Total Duration**: ____ hours

### Issues Encountered (if any)
1. **Issue**: (description)
   - **Severity**: CRITICAL / HIGH / MEDIUM / LOW
   - **Resolution**: (what was done)
   - **Status**: ✓ Resolved / ⚠️ Requires monitoring / ✗ Blocks deployment

### Action Items for Apr 28-29
- [ ] (if issues found, list follow-ups)

### Team Signature
```
Release Engineer: _________________________ Date: Apr 27, 2026
Infrastructure Lead: _________________________ Date: Apr 27, 2026
Observability Engineer: _________________________ Date: Apr 27, 2026
```

---

## Related Documentation

- **Runbook**: `docs/PRODUCTION-DEPLOYMENT-RUNBOOK.md`
- **Incident Response**: `docs/INCIDENT-RESPONSE-RUNBOOK.md`
- **Monitoring Setup**: `config/prometheus/alert-rules-production.yml`
- **Grafana Dashboard**: `config/grafana/dashboards/production-monitoring.json`

---

**Last Updated**: April 22, 2026  
**Next Review**: April 27, 2026 (before staging test)
