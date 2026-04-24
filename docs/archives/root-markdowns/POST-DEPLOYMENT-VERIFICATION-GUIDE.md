# Post-Deployment Verification Guide - Issue #1000

**Objective**: Comprehensive verification checklist for production deployment  
**Owner**: DevOps/QA Team  
**Timing**: Execute after all E2E tests pass (Issues #986-990 complete)  
**Time Estimate**: 30-45 minutes  
**Status**: Ready for use after #984 completes

---

## Pre-Verification Checklist

Before starting verification, ensure:

- [ ] All 150+ E2E tests passing (from issues #986-990)
- [ ] QA user creation complete (issue #983)
- [ ] OAuth whitelist configured (issue #984)
- [ ] Monitoring stack operational (Prometheus, Grafana, AlertManager)
- [ ] Team ready for production signoff
- [ ] Communication channel open for status updates

---

## Phase 1: Service Health & Connectivity (10 min)

### 1.1: Core Service Health

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Check all services are running
docker-compose ps

# Expected: All services "Up (healthy)" status
```

**Verification Points**:
- [ ] code-server: Up (healthy)
- [ ] postgres: Up (healthy)
- [ ] redis: Up (healthy)
- [ ] caddy: Up (healthy)
- [ ] oauth2-proxy: Up (healthy)
- [ ] prometheus: Up (healthy)
- [ ] grafana: Up (healthy)
- [ ] alertmanager: Up (healthy)
- [ ] synapse (if deployed): Up (healthy)
- [ ] element-web (if deployed): Up (healthy)

### 1.2: Health Endpoint Verification

```bash
# Code-Server health
curl -sk https://localhost:8080/healthz
# Expected: HTTP 200, response body: "OK"

# OAuth Proxy health
curl -sk https://localhost:4180/ping
# Expected: HTTP 200

# Synapse health (if deployed)
curl -sk https://localhost:8008/_matrix/client/versions
# Expected: HTTP 200, JSON with version info

# Prometheus health
curl -sk https://localhost:9090/-/healthy
# Expected: HTTP 200

# Grafana health
curl -sk https://localhost:3000/api/health
# Expected: HTTP 200, JSON response

# AlertManager health
curl -sk https://localhost:9093/-/healthy
# Expected: HTTP 200
```

**Verification Points**:
- [ ] All health endpoints respond with 200
- [ ] No error responses
- [ ] Response times < 1 second

### 1.3: Network Connectivity

```bash
# Test DNS resolution
nslookup code-server.192.168.168.31.nip.io
nslookup kushnir.cloud  # or your domain
# Expected: Valid IP resolution

# Test TLS certificate validity
curl -v https://code-server.192.168.168.31.nip.io 2>&1 | grep -i "certificate\|issuer"
# Expected: Valid certificate chain

# Test reverse proxy routing
curl -sk https://code-server.192.168.168.31.nip.io/ | head -20
# Expected: HTML response (code-server login page)
```

**Verification Points**:
- [ ] DNS resolution working
- [ ] TLS certificate valid (not expired)
- [ ] Reverse proxy routing functional
- [ ] No SSL/TLS warnings

---

## Phase 2: Authentication & Authorization (8 min)

### 2.1: OAuth Login Flow

```bash
# Test login with QA user
# 1. Navigate to: https://code-server.192.168.168.31.nip.io/
# 2. Click "Login"
# 3. Enter: qa@kushnir.cloud
# 4. Enter password from GSM: gcloud secrets versions access latest --secret='qa-user-password'
# 5. Verify: Redirected to IDE workspace

# Via automation (if available):
curl -c /tmp/cookies.txt -d "username=qa@kushnir.cloud&password=<QA_PASSWORD>" \
  https://code-server.192.168.168.31.nip.io/login
```

**Verification Points**:
- [ ] OAuth redirect to Google/Workspace login works
- [ ] Login successful
- [ ] User redirected to IDE workspace
- [ ] Session cookie created and valid
- [ ] User info displayed in IDE (bottom left corner)

### 2.2: Authorization & Access Control

```bash
# Test RBAC enforcement
# 1. As QA user, verify access to:
#    - [ ] Code-Server IDE (read/write workspace)
#    - [ ] Prometheus metrics (read-only)
#    - [ ] Grafana dashboards (read-only)

# 2. Test forbidden access (should fail):
#    - [ ] Attempt direct PostgreSQL access (should fail)
#    - [ ] Attempt direct Redis access (should fail)
#    - [ ] Access to admin-only Grafana settings (should fail)

# 3. Verify audit log entries:
docker-compose exec postgres psql -U postgres -d synapse_db \
  -c "SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 10;"
```

**Verification Points**:
- [ ] User can access IDE
- [ ] User cannot access database directly
- [ ] User cannot access admin functions
- [ ] Audit logs recorded login attempts
- [ ] Role-based access control enforced

### 2.3: Session Management

```bash
# Test session expiry
# 1. Log in as QA user
# 2. Wait for session timeout (default: 24 hours)
# 3. Verify re-authentication required
# 4. Verify no data loss on re-login

# Test session persistence
# 1. Log in, open file in editor
# 2. Restart code-server service
# 3. Verify: Session and file state restored

# Test concurrent sessions
# 1. Log in from 2 different machines
# 2. Verify: Both sessions active
# 3. Modify file from machine A
# 4. Verify: Changes visible on machine B
```

**Verification Points**:
- [ ] Session timeout enforced
- [ ] Session data persisted across service restarts
- [ ] Concurrent sessions supported
- [ ] No data loss on re-authentication

---

## Phase 3: Core Functionality Validation (8 min)

### 3.1: Code-Server IDE Features

```bash
# As QA user, test:
# [ ] File browser navigation
# [ ] File creation/editing/deletion
# [ ] Terminal access (bash, python, etc.)
# [ ] Extension marketplace access
# [ ] Settings persistence
# [ ] Workspace switching (if configured)
# [ ] Workspace synchronization (if enabled)

# Via automation:
curl -sk https://code-server.192.168.168.31.nip.io/api/v1/user \
  -H "Authorization: Bearer $SESSION_TOKEN"
# Expected: Valid user info JSON response
```

**Verification Points**:
- [ ] File operations work (create/read/update/delete)
- [ ] Terminal functional (can run commands)
- [ ] Extensions can be installed
- [ ] Settings saved and restored
- [ ] No console errors in IDE

### 3.2: Database Operations

```bash
# Test PostgreSQL connectivity
docker-compose exec postgres psql -U postgres -d synapse_db -c "SELECT 1;"
# Expected: Response: 1

# Test database backup
docker-compose exec postgres pg_dump -U postgres synapse_db | wc -l
# Expected: Positive line count (database contains data)

# Test Redis connectivity
docker-compose exec redis redis-cli -a "${REDIS_PASSWORD}" ping
# Expected: PONG

# Test session persistence in Redis
docker-compose exec redis redis-cli -a "${REDIS_PASSWORD}" KEYS '*session*' | wc -l
# Expected: > 0 (sessions stored)
```

**Verification Points**:
- [ ] PostgreSQL responsive
- [ ] Database backup works
- [ ] Redis responsive
- [ ] Session data in Redis
- [ ] No database connection errors in logs

### 3.3: File Storage & Media

```bash
# Test file upload
# 1. In IDE terminal: touch /tmp/test-file.txt && echo "test" > /tmp/test-file.txt
# 2. Verify file exists: ls -l /tmp/test-file.txt
# 3. Verify file readable: cat /tmp/test-file.txt
# Expected: "test"

# Test workspace volume (if Matrix/media store enabled)
docker volume ls | grep -i workspace
# Expected: volume present and accessible

# Test persistence across container restart
docker-compose restart code-server
# 1. Reconnect to IDE
# 2. Verify file still exists and is readable
```

**Verification Points**:
- [ ] File uploads work
- [ ] Files persist across restarts
- [ ] File permissions correct
- [ ] Storage not full (>10% free)

---

## Phase 4: Monitoring & Observability (8 min)

### 4.1: Metrics Collection

```bash
# Check Prometheus scrape targets
curl -sk https://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance}' | head -20

# Expected: All services listed with "active" status
# Examples:
#   - code-server
#   - postgres
#   - redis
#   - synapse (if deployed)
#   - prometheus
#   - grafana

# Query Prometheus metrics
curl -sk 'https://localhost:9090/api/v1/query?query=up' | jq '.data.result[] | {job: .metric.job, up: .value[1]}'
# Expected: All jobs show value 1 (up)
```

**Verification Points**:
- [ ] All services appear in scrape targets
- [ ] No scrape errors
- [ ] Metrics flowing to Prometheus
- [ ] No "up == 0" results

### 4.2: Grafana Dashboards

```bash
# Log in to Grafana: https://localhost:3000
# Default: admin / admin123

# Verify dashboards exist:
# [ ] Matrix Overview (if Matrix deployed)
# [ ] Matrix Collaboration (if Matrix deployed)
# [ ] Redis Monitoring
# [ ] General infrastructure dashboard

# Test dashboard queries:
# 1. Navigate to each dashboard
# 2. Verify charts display data (not "No Data")
# 3. Verify time range selectors work
# 4. Verify no red/error indicators

# Create test query in Prometheus:
curl -sk 'https://localhost:9090/api/v1/query?query=node_memory_MemAvailable_bytes' | jq '.'
# Expected: Valid metric data
```

**Verification Points**:
- [ ] All dashboards load without errors
- [ ] Charts display actual metrics
- [ ] Time range selector works
- [ ] No dashboard warnings
- [ ] Query performance < 1s

### 4.3: Alert Rules

```bash
# Check AlertManager alerts
curl -sk https://localhost:9093/api/v1/alerts | jq '.data[] | {status: .status, labels: .labels}'

# Expected: Should show:
# - No FIRING alerts (unless simulated for testing)
# - All OK or RESOLVED status

# Verify alert rules loaded
curl -sk 'https://localhost:9090/api/v1/rules' | jq '.data.groups[] | {name: .name, rules: (.rules | length)}'

# Expected: Rules grouped by service (>5 alert rules)
```

**Verification Points**:
- [ ] No unexpected FIRING alerts
- [ ] Alert rules properly loaded
- [ ] AlertManager routing functional
- [ ] Alert severity configured (critical/warning/info)

---

## Phase 5: Security Verification (5 min)

### 5.1: Secrets Management

```bash
# Verify no secrets in code
git log --all -S "password\|secret\|token" --oneline | head
# Expected: No matches (or only in configs, not code)

# Verify GSM secrets accessible
gcloud secrets list --filter="labels.env=production"
# Expected: qa-user-email, qa-user-password, and other expected secrets

# Verify secrets not in environment (cleared from history)
history | grep -i "password\|secret"
# Expected: No matches
```

**Verification Points**:
- [ ] No hardcoded secrets in code
- [ ] All credentials in GSM
- [ ] No secrets in Git history
- [ ] Secrets rotated per policy

### 5.2: Network Isolation

```bash
# Test firewall rules
# (From production host)
telnet external-host 443  # Should timeout/fail
# Expected: Connection refused or timeout (no external access)

# Verify no external DNS queries
# (If DNS logging enabled)
# Check logs for external domain queries
# Expected: Only internal DNS queries logged

# Test OAuth provider connectivity (expected to work)
curl -I https://accounts.google.com
# Expected: HTTP 200 (OAuth provider accessible for authentication)
```

**Verification Points**:
- [ ] External internet blocked (except OAuth provider)
- [ ] Internal network accessible
- [ ] No DNS leaks
- [ ] Firewall rules enforced

### 5.3: TLS/SSL Configuration

```bash
# Check certificate validity
openssl s_client -connect localhost:443 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -dates
# Expected: Not Before and Not After dates valid

# Check TLS version
curl -I --tlsv1.2 https://localhost/
# Expected: HTTP 200 (TLS 1.2+ required)

# Verify no weak ciphers
openssl s_client -connect localhost:443 -cipher 'ECDHE-RSA-AES256-GCM-SHA384' </dev/null
# Expected: Successfully connected with strong cipher
```

**Verification Points**:
- [ ] Certificate valid and not expired
- [ ] TLS 1.2+ required
- [ ] No weak ciphers accepted
- [ ] HSTS headers present

---

## Phase 6: Performance Baseline (5 min)

### 6.1: Response Time Measurement

```bash
# Measure IDE page load
time curl -sk https://code-server.192.168.168.31.nip.io/ > /dev/null 2>&1
# Expected: < 1 second real time

# Measure API response
time curl -sk https://localhost/api/v1/user > /dev/null 2>&1
# Expected: < 500ms

# Measure Prometheus query
time curl -sk 'https://localhost:9090/api/v1/query?query=up' > /dev/null 2>&1
# Expected: < 1 second

# Baseline metrics to log:
echo "Performance Baseline $(date)"
for service in code-server postgres redis synapse; do
  echo "$service health check: $(curl -s -w '%{time_total}' https://localhost/healthz)"
done
```

**Verification Points**:
- [ ] IDE page load < 2 seconds
- [ ] API responses < 500ms
- [ ] Database queries < 1s (P95)
- [ ] No timeout issues

### 6.2: Resource Utilization

```bash
# Check system resources
docker stats --no-stream | head
# Expected: CPU < 50%, Memory < 70% (for core services)

# Check disk usage
docker volume ls -q | while read vol; do
  echo "$vol: $(docker volume inspect $vol | jq '.[0].UsageData.RefCounted')"
done
# Expected: No volumes at critical capacity (>90%)

# Check database size
docker-compose exec postgres psql -U postgres -c "\l" | grep synapse_db
# Expected: Size < configured limit
```

**Verification Points**:
- [ ] CPU usage reasonable (< 50% idle)
- [ ] Memory usage < 70% of allocation
- [ ] Disk space > 10% free
- [ ] No disk space warnings

---

## Phase 7: Disaster Recovery & Rollback (5 min)

### 7.1: Backup Verification

```bash
# Check latest backup
ls -lh /var/lib/backups/synapse-backup-*.sql.gz | tail -1
# Expected: Recent backup (within 24 hours)

# Test restore procedure
docker-compose down
# Make a test restore:
gunzip < /var/lib/backups/synapse-backup-$(date +%Y%m%d).sql.gz | \
  docker-compose exec -T postgres psql -U postgres
docker-compose up -d postgres

# Verify data restored
docker-compose exec postgres psql -U postgres -d synapse_db -c "SELECT COUNT(*) FROM events;"
# Expected: Row count > 0
```

**Verification Points**:
- [ ] Backup file exists and recent
- [ ] Restore procedure works
- [ ] Data integrity verified after restore
- [ ] Backup size reasonable

### 7.2: Rollback Procedure (Tested, not executed)

```bash
# Document rollback steps (should be tested in staging, not production):
# 1. Stop current deployment: docker-compose down
# 2. Pull previous image: docker pull code-server-enterprise:prev-tag
# 3. Restore from backup: pg_restore < backup.sql
# 4. Start with previous version: docker-compose up -d
# 5. Verify service health

# Time estimate: 10-15 minutes
# RPO (Recovery Point Objective): 6 hours (backup interval)
# RTO (Recovery Time Objective): 15 minutes

# Test in staging to validate
```

**Verification Points**:
- [ ] Rollback procedure documented
- [ ] Time estimate accurate
- [ ] Tested in staging (not production)
- [ ] Communication plan for rollback

---

## Phase 8: Compliance & Audit (3 min)

### 8.1: Audit Logging

```bash
# Check audit log entries
docker-compose exec postgres psql -U postgres -d synapse_db \
  -c "SELECT COUNT(*) FROM audit_log WHERE created_at > NOW() - INTERVAL '1 day';"
# Expected: > 100 entries (for active testing)

# Verify log retention
docker-compose exec postgres psql -U postgres -d synapse_db \
  -c "SELECT MIN(created_at) FROM audit_log;"
# Expected: Date within retention period (e.g., 90 days)

# Export audit logs for compliance
docker-compose exec postgres pg_dump -U postgres synapse_db -t audit_log > audit-export-$(date +%Y%m%d).sql
```

**Verification Points**:
- [ ] Audit logging active
- [ ] All actions logged (login, file ops, config changes)
- [ ] Log retention policy enforced
- [ ] Audit logs accessible for review

### 8.2: Compliance Documentation

```bash
# Generate compliance report
cat > DEPLOYMENT-VERIFICATION-REPORT-$(date +%Y%m%d).md << 'EOF'
# Production Deployment Verification Report

**Date**: $(date -Iseconds)
**Verifier**: $USER
**Environment**: Production (192.168.168.31)

## Verification Status
- [ ] Phase 1: Service Health ✓
- [ ] Phase 2: Authentication ✓
- [ ] Phase 3: Functionality ✓
- [ ] Phase 4: Monitoring ✓
- [ ] Phase 5: Security ✓
- [ ] Phase 6: Performance ✓
- [ ] Phase 7: Disaster Recovery ✓
- [ ] Phase 8: Compliance ✓

## Sign-Off
- Verified By: _________________ (Signature)
- Approved By: _________________ (Signature)
- Date: ________________________

## Issues Found
(List any issues and remediation)

EOF
```

**Verification Points**:
- [ ] Compliance report generated
- [ ] All phases documented
- [ ] Sign-offs collected
- [ ] Issues tracked and remediated

---

## Success Criteria

### Green Light for Production

✅ **Production Ready** if:
- All health endpoints return 200
- All services "Up (healthy)"
- Authentication working for QA user
- All dashboards displaying metrics
- No FIRING alerts (or explained/acknowledged)
- No security warnings
- Performance baselines acceptable
- Backup/restore verified
- Audit logging active
- Team sign-off collected

### Yellow Light (Investigate)

⚠️ **Investigate if**:
- Response times > baseline by >20%
- Any service resource usage > 80%
- Scrape errors for any target
- Missing metrics in dashboards
- Logs show warnings (not errors)

### Red Light (Do Not Deploy)

🔴 **DO NOT DEPLOY if**:
- Any service not "Up"
- Authentication failures
- Critical alerts FIRING
- Security vulnerabilities found
- Data loss detected
- Backup/restore fails

---

## Rollback Triggers

**Automatic Rollback** if within 1 hour of production deployment:
1. All services not healthy
2. Data loss detected
3. Security breach detected
4. Critical audit trail gap

**Decision Required** for:
- Performance degradation (>30%)
- Intermittent failures
- Authentication issues (non-user issues)

---

## Communication Template

### Go/No-Go Meeting

```
# Production Deployment - Go/No-Go Decision

**Status**: [GREEN / YELLOW / RED]

## Go Criteria Met
- [x] Service Health: PASS
- [x] Authentication: PASS
- [x] Monitoring: PASS
- [x] Security: PASS
- [x] Performance: PASS
- [x] Compliance: PASS

## Open Items
(List any outstanding items)

## Risk Assessment
- Technical Risk: LOW / MEDIUM / HIGH
- Business Risk: LOW / MEDIUM / HIGH

## Recommendation
[PROCEED / HOLD / INVESTIGATE]

## Approval
- Infrastructure Lead: _______ (Date)
- Security Lead: _______ (Date)
- Business Owner: _______ (Date)
```

---

## Post-Verification Actions

### Immediate (Day 1)
- [ ] Monitor error logs every 30 minutes
- [ ] Check system resources every 1 hour
- [ ] Verify no unexpected data changes
- [ ] Confirm all user activity logged

### Short-term (Days 2-3)
- [ ] Verify backup completion
- [ ] Analyze performance trends
- [ ] Review audit logs
- [ ] Gather user feedback

### Medium-term (Week 1)
- [ ] Complete full security scan
- [ ] Generate compliance report
- [ ] Document lessons learned
- [ ] Plan Phase 2 enhancements

---

**Document Version**: 1.0  
**Last Updated**: April 20, 2026  
**Next Review**: May 20, 2026  
**Status**: Ready for use after E2E tests pass
