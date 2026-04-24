# Production Deployment Checklist - Post E2E Testing

**Timeline**: Execute after all E2E tests (#986-990) pass  
**Duration**: 30-60 minutes  
**Owner**: Infrastructure/SRE team  
**Backup**: Available on replica (192.168.168.42)

---

## Pre-Deployment Verification (5 min)

### Infrastructure Health

- [ ] Primary host (192.168.168.31) responsive
  ```bash
  ssh akushnir@192.168.168.31 "docker ps --format 'table {{.Names}}\t{{.Status}}'" | head -20
  ```
  Expected: All services showing "Up" or "Healthy"

- [ ] Replica host (192.168.168.42) in sync
  ```bash
  ssh akushnir@192.168.168.42 "git log --oneline -1"
  ```
  Expected: Same commit SHA as primary

- [ ] Database backups verified
  ```bash
  ssh akushnir@192.168.168.31 "ls -lh /backups/postgres/ | tail -5"
  ```
  Expected: Recent backup (within 24h)

- [ ] Redis snapshots verified
  ```bash
  ssh akushnir@192.168.168.31 "redis-cli --rdb /tmp/redis-test.rdb && ls -lh /tmp/redis-test.rdb"
  ```
  Expected: Snapshot created successfully (~1MB+)

### Secrets & Credentials

- [ ] All GSM secrets accessible
  ```bash
  gcloud secrets list --project=kushin77-ops | grep -E "qa-user|oauth|cert"
  ```
  Expected: All secrets present

- [ ] Service account permissions verified
  ```bash
  gcloud iam service-accounts get-iam-policy \
    code-server-sa@kushin77-ops.iam.gserviceaccount.com
  ```
  Expected: Correct roles (artifactRegistry.reader, secretmanager.secretAccessor)

- [ ] SSL certificates valid (>30 days remaining)
  ```bash
  openssl x509 -in config/certs/kushnir.cloud.crt -noout -dates
  ```
  Expected: notAfter date > 30 days away

### Network & DNS

- [ ] DNS resolution correct
  ```bash
  nslookup kushnir.cloud
  # Expected: 192.168.168.31
  ```

- [ ] Firewall rules active
  ```bash
  ssh akushnir@192.168.168.31 "sudo ufw status | grep -E '80|443|3306|5432'"
  ```
  Expected: 80/tcp, 443/tcp, 5432/tcp ALLOW

- [ ] Caddy reverse proxy healthy
  ```bash
  curl -s -I https://kushnir.cloud/health | head -5
  ```
  Expected: HTTP/2 200 or 404 (not 502)

---

## Deployment Execution (20 min)

### 1. Final Code Sync (1 min)

```bash
ssh akushnir@192.168.168.31

cd /home/akushnir/code-server-enterprise

# Verify clean working directory
git status
# Expected: "nothing to commit, working tree clean"

# Pull latest from main
git pull origin main
# Expected: Already up to date (E2E tests verified code)
```

### 2. Pre-Deployment Testing (3 min)

```bash
# Health check all services
docker ps --format 'table {{.Names}}\t{{.Status}}'
# Expected: All containers "Up" or "Healthy"

# Test critical endpoints
curl -s https://kushnir.cloud/health | jq .status
# Expected: "ok"

curl -s https://kushnir.cloud:8080/health | jq .status
# Expected: "ok"

# Test OAuth flow (unauthenticated)
curl -s -I https://kushnir.cloud/oauth2/sign_in | head -3
# Expected: HTTP/2 200 or 302 (not 403/502)
```

### 3. Database Backup (2 min)

```bash
# Create pre-deployment backup
docker exec postgres-primary pg_dump -U postgres code_server_db | \
  gzip > /backups/postgres/pre-deployment-$(date +%Y%m%d-%H%M%S).sql.gz

# Verify backup created
ls -lh /backups/postgres/*.sql.gz | tail -1
# Expected: >10MB file with recent timestamp
```

### 4. Graceful Service Restart (10 min)

```bash
# Restart services in dependency order
# DO NOT use "docker-compose down/up" - use restart

# 1. Session-broker (graceful shutdown with 30s timeout)
docker restart session-broker
sleep 5
docker logs session-broker | tail -20  # Verify startup logs

# 2. Code-server
docker restart code-server
sleep 5
docker logs code-server | tail -20

# 3. OAuth services (portal + main)
docker restart oauth2-proxy-portal
sleep 3
docker restart oauth2-proxy
sleep 5

# 4. Monitoring & observability (no impact on users)
docker restart prometheus alertmanager grafana
sleep 3

# 5. Verify all services healthy
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E "Up|Healthy"
# Expected: All showing "Up" or "Healthy"
```

### 5. Immediate Smoke Tests (3 min)

```bash
# Health endpoints
curl -s https://kushnir.cloud/health | jq . && echo "✅ Main health OK"
curl -s https://kushnir.cloud:8080/health | jq . && echo "✅ IDE health OK"

# OAuth flow (no login needed)
curl -s -I https://kushnir.cloud/oauth2/sign_in | grep -E "200|302" && \
  echo "✅ OAuth sign_in accessible"

# Session broker (internal)
curl -s http://session-broker:5000/health | jq . && \
  echo "✅ Session-broker responding"

# Prometheus metrics
curl -s http://prometheus:9090/api/v1/query?query=up | jq '.data.result | length' && \
  echo "✅ Prometheus collecting metrics"
```

---

## Post-Deployment Validation (10 min)

### 1. Monitor Service Startup (2 min)

```bash
# Watch for any errors in logs
docker logs -f code-server --tail=50 &
docker logs -f oauth2-proxy --tail=50 &
docker logs -f session-broker --tail=50 &

# Wait 30 seconds, verify no ERROR or FATAL messages
sleep 30
kill %1 %2 %3
```

### 2. Run Smoke Tests (5 min)

```bash
# Run subset of E2E tests to verify deployment
cd /home/akushnir/code-server-enterprise/tests/e2e

# Run critical smoke tests only
npx playwright test --grep="@smoke" \
  --reporter=json \
  --reporter=list

# Expected: All smoke tests pass
# Check: artifacts/e2e-smoke-results.json
```

### 3. Verify Database Integrity (2 min)

```bash
# Check PostgreSQL connection
docker exec postgres-primary psql -U postgres code_server_db \
  -c "SELECT version();"
# Expected: PostgreSQL version info

# Check Redis connection
docker exec redis redis-cli ping
# Expected: PONG

# Check Prometheus scrape health
curl -s http://prometheus:9090/api/v1/targets | jq \
  '.data.activeTargets | length'
# Expected: 30+ targets up
```

### 4. Verify User Authentication (3 min)

```bash
# Test OAuth with QA user (requires test credentials)
E2E_USER_EMAIL="qa@kushnir.cloud" \
E2E_USER_PASSWORD=$(gcloud secrets versions access latest \
  --secret=qa-user-password --project=kushin77-ops) \
  npx playwright test oauth-login.spec.ts --grep="successful_login" \
  --reporter=list

# Expected: Login test passes
```

---

## Failover Test (10 min)

### 1. Verify Replica Readiness

```bash
ssh akushnir@192.168.168.42

# Check replica services status
docker ps --format 'table {{.Names}}\t{{.Status}}'
# Expected: All services running

# Verify Git sync
git log --oneline -1
# Expected: Same SHA as primary
```

### 2. Test Failover Trigger

```bash
# Simulate primary failure (graceful shutdown)
ssh akushnir@192.168.168.31
docker-compose down --timeout=30

# Verify all containers stopped
docker ps --filter "status=exited" | wc -l
# Expected: ~10 exited containers

# From replica, verify it's still running
ssh akushnir@192.168.168.42
curl -s https://kushnir.cloud/health | jq .
# Expected: 200 OK (requests route to replica)
```

### 3. Test Failback to Primary

```bash
# Restart primary
ssh akushnir@192.168.168.31
docker-compose up -d

# Wait for startup
sleep 30

# Verify health
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E "Up|Healthy"
# Expected: All services up

# Verify requests route back to primary
curl -s -H "X-Forwarded-For: 0.0.0.0" https://kushnir.cloud/health | jq .
# Expected: 200 OK from primary
```

---

## Performance Validation (5 min)

### 1. Load Testing (2 min)

```bash
# Run k6 load test against deployed service
docker run -i loadimpact/k6 run - << 'EOF' < /dev/null
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  vus: 10,
  duration: '30s',
  thresholds: {
    'http_req_duration': ['p(95)<5000'],
    'http_req_failed': ['rate<0.1'],
  },
};

export default function() {
  let res = http.get('https://kushnir.cloud/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 1s': (r) => r.timings.duration < 1000,
  });
  sleep(1);
}
EOF
```

Expected results:
- p95 latency < 5 seconds
- Error rate < 10%
- All health checks pass

### 2. Resource Usage (2 min)

```bash
# Check CPU and memory after load test
docker stats --no-stream --format \
  "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Expected:
# - CPU: <50% per service
# - Memory: 
#   - code-server: <500MB
#   - postgres: <200MB
#   - redis: <100MB
#   - prometheus: <300MB
```

### 3. Latency Baseline (1 min)

```bash
# Record p50, p95, p99 latencies for monitoring
# This becomes the baseline for future deployments

echo "Latency Baseline - $(date)" >> /home/akushnir/deployment-metrics.txt
echo "p50: $(curl -s https://kushnir.cloud/health | jq '.latency.p50')" >> \
  /home/akushnir/deployment-metrics.txt
echo "p95: $(curl -s https://kushnir.cloud/health | jq '.latency.p95')" >> \
  /home/akushnir/deployment-metrics.txt
echo "p99: $(curl -s https://kushnir.cloud/health | jq '.latency.p99')" >> \
  /home/akushnir/deployment-metrics.txt
```

---

## Rollback Plan (If Issues Detected)

### Immediate Rollback (5 min)

If any critical issues detected:

```bash
# Stop problematic service
docker stop <service-name>

# Restore from backup
docker exec postgres-primary pg_restore -U postgres -d code_server_db \
  /backups/postgres/pre-deployment-*.sql.gz

# Or revert to previous image
docker-compose pull  # Gets previous tag from registry
docker-compose up -d
```

### Full Rollback to Replica (10 min)

If primary completely broken:

```bash
# From primary
git revert HEAD

# Restore from backup
docker exec postgres-primary dropdb code_server_db
docker exec postgres-primary createdb code_server_db
docker exec postgres-primary pg_restore -U postgres -d code_server_db \
  /backups/postgres/backup-before-deploy.sql.gz

# Or switch DNS to replica
# ssh admin@dns-server
# zone file edit: kushnir.cloud A 192.168.168.42
# rndc reload
```

---

## Post-Deployment Monitoring (Ongoing, 24-48 hours)

### 1. Alert Monitoring

```bash
# Check AlertManager for any active alerts
curl -s http://localhost:9093/api/v1/alerts | jq '.data | length'

# Expected: 0 active alerts (or only pre-existing ones)

# View Grafana dashboards
# Login: https://kushnir.cloud:3000 (admin/admin123)
# Check:
# - Code-server health dashboard
# - Infrastructure dashboard
# - Error rates dashboard
```

### 2. Log Monitoring

```bash
# Monitor service logs for errors
docker logs --since 5m --until now code-server | grep -i error
docker logs --since 5m --until now oauth2-proxy | grep -i error
docker logs --since 5m --until now postgres-primary | grep -i error

# Expected: No ERROR or FATAL messages (warnings OK)
```

### 3. User Activity Monitoring

```bash
# Check that users can authenticate and use system
docker logs oauth2-proxy | grep "successful login" | wc -l

# Expected: Increasing count of successful logins

# Check active sessions
docker exec redis redis-cli keys "session:*" | wc -l

# Expected: Increasing as users log in
```

### 4. Capacity Monitoring

```bash
# Check disk usage
docker exec postgres-primary df -h / | tail -1

# Expected: <80% used (plenty of headroom)

# Check database size
docker exec postgres-primary psql -U postgres code_server_db \
  -c "SELECT pg_size_pretty(pg_database_size('code_server_db'));"

# Expected: <5GB (normal operation)
```

---

## Sign-Off Checklist

### ✅ Infrastructure Ready
- [ ] All 9 core services healthy
- [ ] Database backups verified
- [ ] SSL certificates valid
- [ ] Firewall rules correct

### ✅ Deployment Successful
- [ ] All services restarted cleanly
- [ ] No error logs
- [ ] Health endpoints responding
- [ ] Smoke tests pass

### ✅ Failover Tested
- [ ] Primary → Replica failover works
- [ ] Replica → Primary failback works
- [ ] Requests route correctly
- [ ] No data loss observed

### ✅ Performance Validated
- [ ] p95 latency < 5s
- [ ] Error rate < 10%
- [ ] CPU < 50% per service
- [ ] Memory usage reasonable

### ✅ User Experience Verified
- [ ] QA user can login
- [ ] IDE loads and responsive
- [ ] Session state persists
- [ ] Error messages helpful

### ✅ Monitoring Active
- [ ] Prometheus scraping targets
- [ ] AlertManager active
- [ ] Grafana dashboards populated
- [ ] Logs being collected

### ✅ Documentation Complete
- [ ] Deployment metrics recorded
- [ ] Any issues documented
- [ ] Rollback plan noted (if needed)
- [ ] Next review scheduled

---

## Sign-Off Email Template

```
Subject: Production Deployment Complete - kushnir.cloud

Date: YYYY-MM-DD HH:MM UTC
Deployed by: [Your name]
Commit: [SHA from git log]
Duration: [X minutes]

✅ DEPLOYMENT SUCCESSFUL

All systems deployed and verified:
- 9/9 core services healthy
- 110+/110+ E2E tests passed
- Failover tested and working
- Performance baseline established
- Monitoring active

No rollbacks needed. System ready for production use.

Next review: [Date] or upon issue escalation

Questions? Contact: SRE team or @kushin77
```

---

## References

**Critical Files**:
- /home/akushnir/code-server-enterprise/docker-compose.yml
- /backups/postgres/ (database backups)
- config/certs/ (SSL certificates)
- prometheus.yml (monitoring config)

**Contacts**:
- Infrastructure Lead: kushin77 (@kushin77)
- SRE On-Call: [Check runbook]
- Database Admin: [Check runbook]

**Related Issues**:
- #983: QA user creation (completed)
- #984: OAuth whitelist (completed)
- #986-990: E2E tests (all passing)
- #1000: Matrix Epic (complete)

---

**Checklist Version**: 1.0  
**Last Updated**: April 20, 2026  
**Status**: Ready for use after E2E tests pass
