# Deployment Runbook — kushin77/code-server

**Last Updated**: April 21, 2026  
**Status**: 🟢 PRODUCTION READY (All phases complete)  
**Deployment Model**: Dual-host active-passive failover on-prem behind Cloudflare

---

## Quick Start

### Prerequisites
- SSH access to both hosts (192.168.168.31 primary, 192.168.168.42 replica)
- Docker and Docker Compose installed on both hosts
- Google OAuth client credentials (for oauth2-proxy)
- Google Secret Manager setup (for credential rotation)

### Deploy to Both Hosts (Parallel)
```bash
# Terminal 1: Deploy to Primary
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server-enterprise
docker compose down
docker compose pull
docker compose up -d
docker ps --format "table {{.Names}}\t{{.Status}}"  # Verify all 8 services healthy

# Terminal 2: Deploy to Replica (in parallel)
ssh akushnir@192.168.168.42
cd /home/akushnir/code-server-enterprise
docker compose down
docker compose pull
docker compose up -d
docker ps --format "table {{.Names}}\t{{.Status}}"  # Verify all 8 services healthy
```

### Estimated Time
- Primary deployment: 8-12 minutes
- Replica deployment: 8-12 minutes
- Parallel execution: 12-15 minutes total
- Failover verification: 3-5 minutes
- **Total**: ~20 minutes

---

## Deployment Phases

### Phase 1: Pre-Deployment Verification

**Objective**: Ensure both hosts are ready for deployment

```bash
# On BOTH hosts:
ssh akushnir@192.168.168.31
# or
ssh akushnir@192.168.168.42

# Check Docker is running
docker ps
# Expected: Shows current containers (may be empty/stopped)

# Check disk space
df -h | grep -E "/$|/home"
# Expected: >20GB free on both / and /home

# Check network connectivity
ping -c 1 192.168.168.31  # From .42
ping -c 1 192.168.168.42  # From .31
# Expected: No packet loss

# Verify .env file exists and contains credentials
cat .env | grep -E "OAUTH|POSTGRES"
# Expected: All env vars set (no empty values)

# Verify docker-compose.yml syntax
docker-compose config > /dev/null && echo "✅ Config valid" || echo "❌ Config invalid"
```

**Success Criteria**:
- ✅ Docker daemon running
- ✅ >20GB disk available
- ✅ Network connectivity between hosts
- ✅ .env file has all required credentials
- ✅ docker-compose.yml valid syntax

---

### Phase 2: Primary Host Deployment (192.168.168.31)

**Objective**: Deploy all services to primary host

```bash
ssh akushnir@192.168.168.31

# Step 1: Stop and clean current deployment
docker compose down
docker system prune --volumes -f  # CAREFUL: Deletes volumes!
# To preserve data: use "docker compose down" only (don't prune volumes)

# Step 2: Pull latest images
docker compose pull

# Step 3: Start all services
docker compose up -d

# Step 4: Wait for services to be healthy (use loop for verification)
echo "Waiting for services to become healthy..."
for i in {1..30}; do
  HEALTHY=$(docker ps --filter "status=running" --format "{{.Names}}" | wc -l)
  TOTAL=$(docker ps -a --format "{{.Names}}" | wc -l)
  echo "Services: $HEALTHY/$TOTAL running (attempt $i/30)"
  if [ "$HEALTHY" -ge 8 ]; then
    echo "✅ All services running"
    break
  fi
  sleep 5
done

# Step 5: Verify all services are healthy
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.State}}"
```

**Expected Output**:
```
NAMES                        STATUS        STATE
caddy                        Up 10s        running
oauth2-proxy                 Up 5s         running
code-server                  Healthy (5s)  running
postgres                     Healthy (12s) running
redis                        Healthy (8s)  running
grafana                      Healthy (15s) running
prometheus                   Up 3s         running
alertmanager                 Up 1s         running
```

**Success Criteria**:
- ✅ All 8 services show "Up" or "Healthy"
- ✅ No services in "Restarting" state
- ✅ No error messages in logs

**Verification Commands**:
```bash
# Check service logs for errors
docker logs caddy --tail 20
docker logs oauth2-proxy --tail 20
docker logs code-server --tail 20
docker logs postgres --tail 20

# Test health endpoints
curl http://192.168.168.31/health
# Expected: "OK" with HTTP 200

# Test proxy chain
curl -I http://192.168.168.31/
# Expected: HTTP 403 (OAuth gate, not authenticated)
```

---

### Phase 3: Replica Host Deployment (192.168.168.42)

**Objective**: Deploy all services to replica host (identical to primary)

```bash
ssh akushnir@192.168.168.42

# Follow EXACT SAME steps as Phase 2:
# 1. Stop and clean
docker compose down

# 2. Pull latest
docker compose pull

# 3. Start services
docker compose up -d

# 4. Verify all 8 services running
docker ps --format "table {{.Names}}\t{{.Status}}"

# 5. Test health
curl http://192.168.168.42/health
```

**Expected Result**: Identical to Primary (all 8 services running, healthy)

---

### Phase 4: Load Balancing Configuration

**Objective**: Configure DNS and failover routing

**Option A: Cloudflare DNS (Recommended)**
```
DNS Zone: kushnir.cloud
Record: ide.kushnir.cloud → Primary IP (192.168.168.31)
Type: A record

Failover Setup:
- Monitor: HTTP health check to /health endpoint
- Timeout: 5 seconds
- Retry: 2 attempts
- Failover: If primary fails, route to 192.168.168.42 (replica)
```

**Option B: VRRP VIP (On-Prem High Availability)**
```bash
# Not configured yet - requires keepalived on both hosts
# Future enhancement for true HA without external DNS

# For now: Use Cloudflare or manual failover
```

**Current Configuration**: Cloudflare DNS with TCP health check

---

### Phase 5: Clustering & Failover Verification

**Objective**: Verify failover works correctly

```bash
# Terminal 1: Monitor primary
ssh akushnir@192.168.168.31
watch -n 2 'docker ps --format "{{.Names}}\t{{.Status}}"'

# Terminal 2: Simulate primary failure
ssh akushnir@192.168.168.31
docker stop code-server
docker ps  # code-server should show Exited

# Expected on Terminal 1: code-server briefly stopped
# Expected on replica: code-server continues running
# Expected via DNS: Cloudflare health check fails, routes to replica

# Terminal 3: Verify replica serving requests
curl http://192.168.168.42/
# Expected: HTTP 403 (oauth2-proxy working)

# Restart primary service
docker start code-server
docker ps  # Should be running again
```

**Failover Behavior**:
- ✅ Primary fails → DNS redirects to replica (2-5s latency)
- ✅ Replica continues serving requests
- ✅ Primary restarts → DNS redirects back
- ✅ Zero data loss (persistent volumes survive)

---

### Phase 6: Comprehensive Testing

**Objective**: Validate end-to-end functionality

#### Test 1: Health Checks
```bash
# From local machine
curl -I https://kushnir.cloud/health
# Expected: HTTP 200 OK

# From primary
curl http://192.168.168.31/health
# Expected: HTTP 200 OK

# From replica
curl http://192.168.168.42/health
# Expected: HTTP 200 OK
```

#### Test 2: OAuth Flow
```bash
# Open browser: https://kushnir.cloud
# Expected: Redirected to Google OAuth login
# Login with @kushnir.cloud email
# Expected: Authenticated, redirected to code-server IDE
```

#### Test 3: IDE Access
```bash
# In browser, after authentication
# Open VS Code web IDE
# Expected: Full IDE interface with terminal access
# Try creating/editing files
# Expected: Changes persist
```

#### Test 4: Session Persistence
```bash
# Create a file/open folder in IDE
# Stop primary: docker stop code-server
# Access via replica IP: http://192.168.168.42
# Expected: Same session/files visible
# Restart primary: docker start code-server
# Access via primary IP: http://192.168.168.31
# Expected: Same session restored
```

#### Test 5: Failover Failback
```bash
# Stop primary (simulates failure)
# Verify replica serving traffic
# Access https://kushnir.cloud → Should route to replica
# Restart primary
# Verify primary serving traffic again
# Access https://kushnir.cloud → Should route back to primary
# Check logs: No errors during failover
```

---

## Rollback Procedures

### Quick Rollback (Last 5 Minutes)
```bash
# If deployment causes issues, rollback immediately:

ssh akushnir@192.168.168.31
docker compose down
git checkout Caddyfile docker-compose.yml
docker compose up -d

# Verify services recovering
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### Deep Rollback (Restore Previous Snapshot)
```bash
ssh akushnir@192.168.168.31

# Check git history
git log --oneline -10

# Rollback to previous commit
git checkout <PREVIOUS_COMMIT_HASH>

# Restart services
docker compose down
docker compose up -d
```

### Data Rollback (From Backup)
```bash
ssh akushnir@192.168.168.31

# PostgreSQL backup on NAS: /nas/cold/backups/postgres/
# Restore from backup:
docker exec postgres pg_restore -d code_server < /backup/code_server.dump

# Redis backup (via RDB):
docker exec redis redis-cli SAVE
# Restore from dump.rdb
```

---

## Monitoring During Deployment

### Real-Time Service Status
```bash
# Watch services starting
watch -n 1 'docker ps --format "table {{.Names}}\t{{.Status}}"'

# Watch container logs in real-time
docker compose logs -f caddy oauth2-proxy code-server

# Monitor resource usage
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

### Metrics & Dashboards
- **Prometheus**: http://192.168.168.31:9090 (metrics + queries)
- **Grafana**: http://192.168.168.31:3000 (dashboards, admin/admin123)
- **Jaeger**: http://192.168.168.31:16686 (distributed tracing)

---

## Troubleshooting

### Service Won't Start
```bash
# Check error logs
docker logs SERVICE_NAME

# Common issues:
# 1. Port already in use
docker ps | grep :8080
sudo lsof -i :8080

# 2. Volume mount failed
docker volume ls
docker inspect VOLUME_NAME

# 3. Network not found
docker network ls
docker network inspect net-edge
```

### Health Check Failing
```bash
# Check if service is responding
curl -v http://192.168.168.31:8080/health

# Check network connectivity
ping 192.168.168.31
traceroute 192.168.168.31

# Check DNS
nslookup ide.kushnir.cloud
# Should resolve to 192.168.168.31
```

### Failover Not Working
```bash
# Check Cloudflare health check configuration
# 1. Log into Cloudflare DNS
# 2. Navigate to kushnir.cloud zone
# 3. Check health check status: Should show primary as healthy
# 4. If showing unhealthy, check /health endpoint:
curl http://PRIMARY_IP/health

# Manual failover:
# 1. Update DNS record to point to replica IP
# 2. Wait 1-5 minutes for propagation
# 3. Test: curl https://kushnir.cloud
```

---

## Post-Deployment Checklist

- [ ] All 8 services running and healthy on primary
- [ ] All 8 services running and healthy on replica
- [ ] Health endpoints responding with 200 OK
- [ ] Proxy chain working (HTTP 403 for unauthenticated)
- [ ] OAuth login flow tested and working
- [ ] IDE accessible after authentication
- [ ] Failover tested (primary → replica → primary)
- [ ] Monitoring dashboards updated
- [ ] Backups configured and tested
- [ ] Team notified of deployment completion
- [ ] Issue #1017 documentation updated
- [ ] Incident runbook reviewed by team

---

## Emergency Contact & Escalation

**On-Call Engineer**: @kushin77  
**Incident Channel**: #incidents (Slack)  
**Production Status**: https://status.kushnir.cloud (TODO: Set up)  

### Escalation Path
1. **L1 (15 min)**: Check service logs and restart containers
2. **L2 (30 min)**: Execute failover to replica
3. **L3 (60 min)**: Rollback to previous version
4. **L4 (120 min)**: Restore from database backup

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Apr 21, 2026 | Initial comprehensive runbook |

---

## Related Documentation

- [FAILOVER-TESTING-RESULTS.md](FAILOVER-TESTING-RESULTS.md) — Test outcomes and performance metrics
- [INFRASTRUCTURE-RECOVERY-COMPLETE-APRIL-21-2026.md](../INFRASTRUCTURE-RECOVERY-COMPLETE-APRIL-21-2026.md) — Recovery procedures and diagnostics
- [DNS-ARCHITECTURE.md](#) — Cloudflare configuration guide (TODO)

---

**Last Updated**: April 21, 2026 10:15 UTC  
**Next Review**: April 28, 2026 (Weekly)  
**Owner**: @kushin77
