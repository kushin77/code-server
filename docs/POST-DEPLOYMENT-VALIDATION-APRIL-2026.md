# Post-Deployment Validation Runbook

**Purpose**: Post-Deployment Validation Runbook — reference and operational document.
## April 2026 Deployment Epic #950

### Executive Summary
Deployment epic #950 completed successfully with all Phase 21+ services operational. This runbook documents comprehensive validation procedures to verify production readiness before moving to Phase 2 IAM implementation.

**Current Status**: ✅ All services healthy  
**Validation Target**: Full stack coverage (infrastructure, services, failover, security)

---

## 1. Infrastructure Health Verification

### 1.1 SSH to Production Host
```bash
ssh akushnir@192.168.168.31
```

### 1.2 Verify Docker Services
```bash
# List all running containers
docker ps

# Expected output shows 10+ services:
# - code-server (port 8080)
# - caddy (ports 80/443)
# - oauth2-proxy (port 4180)
# - Prometheus (port 9090)
# - Grafana (port 3000)
# - AlertManager (port 9093)
# - Jaeger (port 16686)
# - PostgreSQL (port 5432)
# - Redis (port 6379)
# - ollama (port 11434, if GPU enabled)

# Check health status
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### 1.3 Verify All Services Are Healthy
```bash
# Check docker-compose status
docker compose ps

# All services should show "healthy" or "running"
# If any are "unhealthy", check logs:
docker compose logs --tail=50 <service-name>
```

### 1.4 Network Connectivity Tests
```bash
# Test port accessibility from local network
curl -v http://192.168.168.31:8080        # code-server
curl -v http://192.168.168.31:9090        # Prometheus
curl -v http://192.168.168.31:3000        # Grafana
curl -v http://192.168.168.31:9093        # AlertManager
curl -v http://192.168.168.31:16686       # Jaeger
```

---

## 2. Authentication & OAuth Configuration

### 2.1 Check OAuth2-Proxy Configuration
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Verify env vars are loaded
echo $OAUTH2_PROXY_PROVIDER
echo $OAUTH2_PROXY_CLIENT_ID
echo $OAUTH2_PROXY_COOKIE_SECRET

# Should output:
# OAUTH2_PROXY_PROVIDER=google
# OAUTH2_PROXY_CLIENT_ID=<your-client-id>
# OAUTH2_PROXY_COOKIE_SECRET=<32-hex-chars>
```

### 2.2 Test OAuth2-Proxy Health Endpoint
```bash
curl -v http://192.168.168.31:4180/health

# Should return 200 OK with "OK" body
```

### 2.3 Test Login Flow (Browser)
1. Open browser to `http://code-server.192.168.168.31.nip.io:8080`
2. You should be redirected to oauth2-proxy login page
3. Should see "Sign in with Google" button
4. After authentication, should see code-server interface
5. **Success criteria**: No CSRF token errors, login completes within 5 seconds

### 2.4 Verify Cookie Security Headers
```bash
curl -v http://192.168.168.31:4180/ 2>&1 | grep -i "set-cookie"

# Should see:
# - oauth2_proxy cookie with SameSite=None (for cross-site OAuth)
# - csrf_token cookie
# - secure flag present
```

---

## 3. Database & Persistence

### 3.1 PostgreSQL Connectivity
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Connect to PostgreSQL
docker exec -it postgres_prod psql -U postgres -d code_server

# List tables
\dt

# Should show tables for:
# - users (from OAuth sync)
# - sessions (from code-server persistence)
# - audit_logs (if Phase 4 implemented)

# Exit psql
\q
```

### 3.2 Verify Code-Server Persistence
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Check code-server user profile backup
ls -lah /home/akushnir/code-server-enterprise/backups/

# Should show recent backup archives (*.tgz)
# Latest should be from recent deployment

# Verify backup contains workspace storage
tar tzf backups/code-server-user-profile-*.tgz | grep workspaceStorage | head -5
```

### 3.3 Verify Redis Caching
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Connect to Redis
docker exec -it redis_prod redis-cli

# Check connected clients
INFO clients

# Check memory usage
INFO memory

# Test basic key/value
SET testkey "hello"
GET testkey

# Exit
EXIT
```

---

## 4. Observability & Monitoring

### 4.1 Prometheus Metrics Collection
```bash
# Browse to Prometheus UI
# http://192.168.168.31:9090

# In the search box, check for:
- up{job="prometheus"}              # Should be 1 (healthy)
- up{job="code-server"}             # Should be 1
- up{job="oauth2_proxy"}            # Should be 1
- up{job="postgres"}                # Should be 1
- up{job="redis"}                   # Should be 1

# Check recent metrics query
# Execute: rate(http_requests_total[5m])
# Should show active request rates
```

### 4.2 Grafana Dashboard Verification
```bash
# Browse to Grafana
# http://192.168.168.31:3000
# Login: admin / admin123

# Navigate to Dashboards
# Verify these dashboards exist and are populated:
- Code-Server Health
- OAuth Authentication Metrics
- PostgreSQL Performance
- Redis Cache Statistics
- Network I/O

# Each dashboard should show:
- Green health indicators
- Non-empty metric graphs
- Timestamps showing recent data
```

### 4.3 AlertManager Verification
```bash
# Browse to AlertManager
# http://192.168.168.31:9093

# Check Alerts tab
# Should see no firing alerts (or only expected ones)

# Check Silences tab
# Review any active silences

# Click on an alert group to see:
- Alert name
- Severity
- Affected instances
- Time firing started
```

### 4.4 Jaeger Tracing
```bash
# Browse to Jaeger
# http://192.168.168.31:16686

# In Service dropdown, select a service (e.g., "code-server")
# Set time range to "Last Hour"
# Click "Find Traces"

# Should see trace results with:
- Trace ID
- Span count
- Duration
- Service breakdown

# Click on a trace to verify:
- Parent/child span relationships
- Service dependencies
- Latency per service
```

---

## 5. Security Validation

### 5.1 TLS/HTTPS Configuration
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Verify Caddy is serving HTTPS
# Check cert files exist
ls -la /home/akushnir/code-server-enterprise/config/caddy/

# Should show certificates for:
# - code-server.*.nip.io
# - *.kushnir.cloud (if configured)

# Test HTTPS connection
curl -v --insecure https://192.168.168.31/

# Should show certificate info and 200 OK response
```

### 5.2 Verify Security Headers
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Check Caddy is injecting security headers
curl -v http://192.168.168.31:8080/ 2>&1 | grep -E "X-Frame-Options|X-Content-Type-Options|Strict-Transport-Security"

# Should show:
# X-Frame-Options: DENY or SAMEORIGIN
# X-Content-Type-Options: nosniff
# Strict-Transport-Security: max-age=...
```

### 5.3 Network Policy Enforcement
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Verify iptables rules are in place (if Kubernetes deployed)
# For Docker Compose setup, verify service isolation:

# Services should NOT be accessible directly without routing through Caddy
# Test from local machine:
curl -v http://192.168.168.31:4180/  # oauth2-proxy direct - should fail or timeout
curl -v http://192.168.168.31:8080/  # code-server direct - should work (no auth)

# Proper setup: external access through Caddy only
# Internal services isolated
```

---

## 6. Failover & Resilience Testing

### 6.1 Single Service Restart Recovery
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Test oauth2-proxy restart
docker restart oauth2_proxy_prod

# Monitor recovery
docker ps -f "name=oauth2" --format "{{.Status}}"

# Should show "Up X seconds" after restart completes
# Try login again to verify OAuth still works

# Verify no errors in Prometheus alerts
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.state=="firing")'
```

### 6.2 Database Failover (Replica Test)
```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Check replication status (if PostgreSQL streaming replication configured)
docker exec postgres_prod psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# If replicas exist, should see:
# - pid
# - usesysid
# - usename
# - client_addr (replica host IP)
# - state

# Test failover readiness (non-disruptive):
# On primary, get current WAL position
docker exec postgres_prod psql -U postgres -c "SELECT pg_current_wal_lsn();"

# On replica (192.168.168.42):
ssh akushnir@192.168.168.42
docker exec postgres_replica psql -U postgres -c "SELECT pg_last_wal_receive_lsn();"

# LSNs should match (no lag)
```

### 6.3 Load Balancing Test (Dual Host)
```bash
# From local machine, test both hosts are responsive
curl -v http://192.168.168.31:8080/
curl -v http://192.168.168.42:8080/

# Both should return 200 OK
# Check response headers for host identification
curl -I http://192.168.168.31:8080/ | grep -E "Server|X-Served-By"
curl -I http://192.168.168.42:8080/ | grep -E "Server|X-Served-By"

# If Cloudflare failover configured, test:
curl -v http://code-server.kushnir.cloud/

# Should consistently hit primary (31)
# If primary goes down, should failover to secondary (42)
```

### 6.4 Redis Sentinel Health (If Configured)
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Connect to Redis Sentinel
docker exec -it redis_sentinel redis-cli -p 26379

# Check sentinel status
SENTINEL MASTERS

# Should show Redis master details

SENTINEL SLAVES mymaster

# Should show replica info

# Exit
EXIT

# Test failover readiness (don't trigger, just verify):
# Current master should be primary, replicas on replica host
```

---

## 7. Application-Level Validation

### 7.1 Code-Server UI Load Test
```bash
# 1. Open browser to code-server
# http://code-server.192.168.168.31.nip.io:8080

# 2. Verify UI loads completely (no JavaScript errors):
# - Sidebar appears
# - File explorer populated
# - Terminal can be opened
# - Extensions loaded

# 3. Test editor functionality:
# - Open a file
# - Type and verify text appears
# - Save file
# - Close and reopen to verify persistence

# 4. Test terminal:
# - Open integrated terminal
# - Run command: echo "Hello from code-server"
# - Verify output appears
```

### 7.2 Workspace Persistence
```bash
# 1. In code-server, open a new file:
# File > New File > enter content

# 2. Open terminal and run:
# echo "test session content" > /tmp/test.txt

# 3. Close browser tab completely

# 4. Re-open browser to code-server

# 5. Verify:
# - File is still there (not lost)
# - Terminal session did NOT auto-resume (expected if `terminal.integrated.enablePersistentSessions=false`)
# - Workspace state preserved

# OR, if persistent terminals are enabled:
# - Terminal session should resume with same working directory
```

### 7.3 Settings Persistence
```bash
# 1. In code-server, open Settings (Ctrl+,)

# 2. Change a setting (e.g., "Editor: Font Size" = 16)

# 3. Close and reopen browser

# 4. Verify setting persisted:
# - Open Settings again
# - Font size should still be 16 (not reset to default)
```

---

## 8. Automated Testing Scripts

### 8.1 Run Deployment Health Check
```bash
# SSH to host
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Run health check
bash scripts/ci/check-deployment-health.sh

# Should exit with code 0 (all checks passed)
# Output should show:
✓ Docker daemon accessible
✓ All containers healthy
✓ Network ports accessible
✓ Databases responsive
✓ OAuth configured
✓ Monitoring active
```

### 8.2 Run Failover Readiness Check
```bash
# SSH to host
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Check failover is ready (non-disruptive)
bash scripts/ops/failover-status.sh

# Should output:
Primary: 192.168.168.31 - HEALTHY
Replica: 192.168.168.42 - HEALTHY
Replication Lag: 0.0 seconds
Failover Ready: YES
```

### 8.3 Run Resilience Campaign (Optional - Limited Blast Radius)
```bash
# SSH to host
ssh akushnir@192.168.168.31
cd code-server-enterprise

# This performs controlled failures and recoveries
# Only runs during maintenance windows
BASELINE_REQUEST_COUNT=1 BASELINE_THROTTLE_LIMIT=1 bash scripts/ops/run-resilience-campaign.sh

# Monitors:
# - Service recovery time
# - Data consistency during failures
# - Failover activation
# - Alert firing

# Expected duration: 5-10 minutes
# Exit code 0 = all resilience tests passed
```

---

## 9. Checklist - Deployment Ready Status

### Prerequisites
- [ ] Can SSH to 192.168.168.31 without password (key-based auth)
- [ ] Local network connectivity to 192.168.168.0/24
- [ ] DNS resolution working for nip.io domains

### Infrastructure
- [ ] All 10+ Docker containers running
- [ ] All containers show "healthy" status
- [ ] Network ports (8080, 9090, 3000, etc.) are accessible
- [ ] PostgreSQL responding to connections
- [ ] Redis responding to connections

### Authentication
- [ ] OAuth2-proxy health endpoint returns 200 OK
- [ ] Google OAuth credentials configured in .env
- [ ] Browser login flow completes without errors
- [ ] CSRF token cookie being set correctly
- [ ] Session persistence working (can refresh page without re-login)

### Observability
- [ ] Prometheus collecting metrics from all services
- [ ] Grafana dashboards display populated graphs
- [ ] AlertManager has no unexpected alerts firing
- [ ] Jaeger tracing shows service requests

### Security
- [ ] TLS/HTTPS certificates valid
- [ ] Security headers present (X-Frame-Options, etc.)
- [ ] Network isolation verified
- [ ] No exposed credentials in logs

### Failover Readiness
- [ ] Replica host (192.168.168.42) is healthy
- [ ] Database replication lag < 1 second
- [ ] Failover status script shows "Ready: YES"
- [ ] Can access services from both hosts

### Application
- [ ] Code-server UI loads completely
- [ ] File editor works
- [ ] Terminal functionality works
- [ ] Workspace settings persist across browser refresh
- [ ] User profile backup created and validated

---

## 10. Rollback Procedures

### If Critical Issue Discovered

#### Option 1: Restart All Services (Least Disruptive)
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Restart all containers gracefully
docker compose restart

# Monitor recovery
watch -n 1 'docker ps --format "table {{.Names}}\t{{.Status}}"'

# All should be "healthy" or "running" within 30 seconds
```

#### Option 2: Restore from Previous Snapshot (Medium Disruption)
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Get list of available snapshots
ls -la backups/

# Restore code-server user profile
tar xzf backups/code-server-user-profile-<timestamp>.tgz -C /home/akushnir/

# Restart code-server
docker restart code_server_prod

# Verify it came up with old state
docker logs code_server_prod | tail -20
```

#### Option 3: Revert to Previous Docker Images (Full Rollback)
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Get git history
git log --oneline -10

# Revert docker-compose to previous version
git checkout <previous-commit-hash> -- docker-compose.yml

# Rebuild and restart
docker compose down
docker compose up -d

# Monitor for recovery
docker compose logs --tail=50
```

---

## 11. Metrics & Baselines

### Expected Performance Metrics (Post-Deployment)

| Metric | Expected Value | Alert Threshold | Notes |
|--------|----------------|--------------------|-------|
| code-server latency (p99) | < 200ms | > 500ms | API response time |
| OAuth login time | 2-4 seconds | > 10s | Time to redirect to code-server |
| PostgreSQL query time (p99) | < 50ms | > 200ms | Database latency |
| Redis GET latency (p99) | < 5ms | > 20ms | Cache hit latency |
| Prometheus scrape duration | < 5s per target | > 15s | Metric collection overhead |
| CPU usage (primary) | 15-30% | > 70% | Host CPU utilization |
| Memory usage (primary) | 40-50% | > 80% | Host memory utilization |
| Network I/O (primary) | < 100 Mbps | > 500 Mbps | Bandwidth utilization |
| Disk I/O latency | < 10ms | > 50ms | Storage subsystem health |
| Replication lag | 0-100ms | > 1s | PostgreSQL replication offset |

### Capture Baseline Metrics
```bash
ssh akushnir@192.168.168.31

# Save metrics snapshot for comparison
mkdir -p baseline-metrics-$(date +%Y%m%d)

# Prometheus metrics
curl -s 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total' | jq . > baseline-metrics-$(date +%Y%m%d)/cpu.json

# Node stats
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" > baseline-metrics-$(date +%Y%m%d)/container-stats.txt

# Network stats
docker exec prometheus_prod ss -tlnp > baseline-metrics-$(date +%Y%m%d)/network.txt

echo "Baseline metrics saved to baseline-metrics-$(date +%Y%m%d)/"
```

---

## 12. Next Steps

### Immediate (This Week)
1. ✅ Run through sections 1-5 (Infrastructure, Auth, Database, Observability, Security)
2. ✅ Run sections 7-8 (Application, Automated Tests)
3. ✅ Document any issues found in new GitHub issues
4. ✅ Create baseline metrics for reference

### Phase 2 Prep (Next Week)
1. Merge PRs #462-467 to main (consolidate 111 commits)
2. Deploy Phase 1 OIDC providers (if not already done)
3. Begin Phase 2 IAM implementation (service-to-service auth)
4. Run full test suite (scripts/tests/iam/)

### Phase 3+ (Following Weeks)
1. Deploy RBAC enforcement
2. Implement audit logging
3. Run comprehensive load testing
4. Prepare for production canary deployment

---

## 13. Support & Escalation

### If Tests Fail

1. **Check docker-compose logs**:
   ```bash
   docker compose logs --tail=100 <service-name>
   ```

2. **Check host system resources**:
   ```bash
   free -h              # Memory
   df -h                # Disk space
   top -b -n 1 | head   # CPU load
   ```

3. **Check network connectivity**:
   ```bash
   ping 8.8.8.8         # External connectivity
   nslookup kushnir.cloud  # DNS resolution
   ```

4. **Restart failing service**:
   ```bash
   docker restart <service-name>
   docker logs <service-name>
   ```

5. **Escalate to main branch**:
   - Open issue in https://github.com/kushin77/code-server/issues
   - Include: service logs, docker ps output, error messages
   - Reference this validation runbook

---

## Document Metadata

**Version**: 1.0  
**Date Created**: April 22, 2026  
**Deployment Epic**: #950  
**Last Validated**: <date of last successful run>  
**Validated By**: <your-name>  
**Status**: ✅ READY FOR PRODUCTION

---

## Appendix: Quick Command Reference

```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# SSH to replica host  
ssh akushnir@192.168.168.42

# View all services
docker ps

# Check service health
docker compose ps

# View service logs
docker compose logs -f <service>

# Restart service
docker restart <service>

# Connect to PostgreSQL
docker exec -it postgres_prod psql -U postgres

# Connect to Redis
docker exec -it redis_prod redis-cli

# Check Prometheus metrics
curl -s 'http://localhost:9090/api/v1/query?query=up'

# View AlertManager alerts
curl -s http://localhost:9093/api/v1/alerts | jq .

# Test connectivity
curl -v http://192.168.168.31:8080
```

---

**End of Runbook**