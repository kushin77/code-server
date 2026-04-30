# Hermes Agent Portal - Deployment Execution Guide

**Date:** April 30, 2026  
**Status:** Ready for Deployment  
**Target:** Primary Server (192.168.168.31)  
**Execution Time:** 2-3 minutes  

---

## Quick Start (TL;DR)

```bash
# SSH to primary server
ssh akushnir@192.168.168.31

# Navigate to deployment directory
cd /home/akushnir/code-server

# Set OAuth credentials (from Google Cloud Console)
nano .env

# Run pre-flight verification
./verify-appsmith-integration.sh

# Execute deployment (watch terminal output)
./deploy-production.sh

# Wait 2-3 minutes for services to become healthy
# Then access: https://kushnir.cloud
```

---

## Detailed Execution Steps

### Step 1: Prepare OAuth Credentials (REQUIRED)

Before deployment, you need OAuth credentials from Google Cloud Console:

**Google Cloud Console Setup:**
1. Go to: https://console.cloud.google.com/
2. Select your project
3. Navigate to: APIs & Services → Credentials
4. Copy: `OAUTH_GOOGLE_CLIENT_ID`
5. Copy: `OAUTH_GOOGLE_CLIENT_SECRET`

**Set Credentials on Primary Server:**

```bash
# SSH to primary
ssh akushnir@192.168.168.31

# Navigate to directory
cd /home/akushnir/code-server

# Edit .env file
nano .env

# Add the following lines:
OAUTH_GOOGLE_CLIENT_ID=<paste-your-client-id>
OAUTH_GOOGLE_CLIENT_SECRET=<paste-your-client-secret>
APPSMITH_INSTANCE_NAME=kushnir-cloud-prod
DB_PASSWORD=<your-secure-db-password>

# Save and exit: Ctrl+X, Y, Enter
```

**Verify Credentials:**

```bash
# Check if credentials are set
grep "OAUTH_GOOGLE_CLIENT_ID" .env

# Should output: OAUTH_GOOGLE_CLIENT_ID=<your-client-id>
```

### Step 2: Run Pre-Deployment Verification

```bash
# Execute verification script
./verify-appsmith-integration.sh

# Script will check:
# ✓ Configuration files present
# ✓ Docker installation
# ✓ docker-compose version
# ✓ Network connectivity
# ✓ File permissions
# ✓ Service ports available
# ✓ JSON validation
# ✓ Security settings

# Expected output: "ALL CHECKS PASSED - READY FOR DEPLOYMENT"
```

**If verification fails:**
- Review the error message carefully
- Check Prerequisites section below
- Verify all configuration files exist
- Ensure Docker daemon is running: `sudo systemctl start docker`

### Step 3: Execute Deployment

```bash
# Start the deployment
./deploy-production.sh

# Script output will show:
# 1. Pre-flight checks starting...
# 2. Stopping existing services (if any)...
# 3. Starting Appsmith...
# 4. Starting hermes-integration...
# 5. Starting code-server...
# 6. Starting PostgreSQL...
# 7. Starting Redis...
# 8. Waiting for services to become healthy...
# 9. Testing API connectivity...
# 10. Deployment complete!
```

**Expected Timeline:**
- Pre-flight checks: 30 seconds
- Service startup: 60-120 seconds
- Health verification: 30-60 seconds
- API testing: 10 seconds
- **Total: 2-3 minutes**

### Step 4: Monitor Deployment in Real-Time

**Open a second terminal while deployment runs:**

```bash
# SSH to primary server (second terminal)
ssh akushnir@192.168.168.31

# Watch service status in real-time
cd /home/akushnir/code-server
watch -n 2 'docker-compose -f docker-compose.enterprise.yml ps'

# Expected output (after ~2 minutes):
# NAME                        COMMAND                PORTS           STATUS
# appsmith                    "/bin/sh -c ./start"   8084/tcp        Up (healthy)
# hermes-integration          "uvicorn main:app"     8000/tcp        Up (healthy)
# code-server-ide             "dumb-init /entryp"    8080/tcp        Up (healthy)
# code-server-postgres        "postgres"             5432/tcp        Up (healthy)
# code-server-redis           "redis-server"         6379/tcp        Up (healthy)
```

**View deployment logs:**

```bash
# In third terminal, watch logs
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server

# View all service logs
docker-compose -f docker-compose.enterprise.yml logs -f

# View specific service
docker logs -f hermes-integration      # API service
docker logs -f appsmith                # Portal service
docker logs -f code-server-ide         # IDE service
```

### Step 5: Verify Deployment Success

```bash
# Wait for all services to show "Up (healthy)"
docker-compose -f docker-compose.enterprise.yml ps

# Test API health endpoint
curl -k https://kushnir.cloud/api/hermes/health

# Expected response:
# {"status": "healthy", "service": "hermes-integration"}

# Test Appsmith health
curl -k https://kushnir.cloud/ | head -20

# Expected: HTML response starting with <!DOCTYPE html>

# Check metrics
curl -k https://kushnir.cloud/api/hermes/metrics

# Expected: JSON with platform_phases, total_tests, quality_percentage
```

---

## Pre-Deployment Prerequisites

### Server Requirements

```bash
# Verify on 192.168.168.31:

# 1. Operating System
cat /etc/os-release
# Expected: Linux (any recent distribution)

# 2. Docker installation
docker --version
# Expected: Docker version 20.10 or higher

# 3. docker-compose installation
docker-compose --version
# Expected: Docker Compose version 2.0 or higher

# 4. Available disk space
df -h /home
# Expected: > 10 GB available

# 5. Available memory
free -h
# Expected: > 4 GB RAM

# 6. Network connectivity
ping google.com
# Expected: 4 packets transmitted

# 7. DNS resolution
nslookup kushnir.cloud
# Expected: Resolves to 192.168.168.31
```

### Port Availability

```bash
# Verify required ports are available
sudo netstat -tulpn | grep LISTEN | grep -E ':(80|443|8080|8084|8000)'

# Ports that MUST be available:
# - 80 (HTTP)
# - 443 (HTTPS)
# - 8080 (code-server IDE)
# - 8084 (Appsmith)
# - 8000 (Hermes API)
# - 5432 (PostgreSQL)
# - 6379 (Redis)

# If any port is in use, the deployment will fail
```

### File Permissions

```bash
# Verify deployment scripts are executable
ls -la deploy-production.sh verify-appsmith-integration.sh
# Expected: -rwxr-xr-x (755 permissions)

# If not executable, fix:
chmod +x deploy-production.sh verify-appsmith-integration.sh
```

---

## During Deployment: What to Expect

### Normal Startup Sequence

```
[00:00] Starting pre-flight checks...
[00:15] Pre-flight checks complete
[00:30] Stopping existing containers (if any)...
[00:45] Pulling latest images...
[01:00] Starting services...
[01:15] Appsmith starting (port 8084)...
[01:30] API service starting (port 8000)...
[01:45] IDE service starting (port 8080)...
[02:00] Database service starting (port 5432)...
[02:15] Cache service starting (port 6379)...
[02:30] Waiting for services to become healthy...
[02:45] Testing API connectivity...
[02:50] All services healthy!
[02:55] Deployment complete!
```

### Common Output Messages (Normal)

```
"waiting for service to be ready"     → Normal, service is starting
"health check failed, retrying"       → Normal, retrying health checks
"service ready: port 8084"            → Good, service is healthy
"database initialized"                → Good, database is ready
"migration completed"                 → Good, schema is set up
```

---

## Post-Deployment Verification

### Immediate Verification (Right After Deployment)

```bash
# 1. Check all services are healthy
docker-compose -f docker-compose.enterprise.yml ps
# Expected: All "Up (healthy)"

# 2. Verify API is responding
curl -k https://kushnir.cloud/api/hermes/health | jq .
# Expected: {"status": "healthy", "service": "hermes-integration"}

# 3. Verify database connectivity
docker exec code-server-postgres psql -U postgres -d code-server-db -c "SELECT 1;"
# Expected: (1 row) - 1

# 4. Check logs for errors
docker-compose -f docker-compose.enterprise.yml logs | grep -i "error\|failed" | head -20
# Expected: No critical errors

# 5. Verify DNS
nslookup kushnir.cloud
# Expected: Resolves to 192.168.168.31
```

### User Acceptance Tests

```bash
# 1. Access Appsmith Dashboard
# Browser: https://kushnir.cloud
# Expected: Login page with "Sign in with Google"

# 2. Complete OAuth Login
# Click "Sign in with Google"
# Complete Google authentication
# Expected: Dashboard with Hermes metrics displayed

# 3. Check Dashboard Metrics
# Expected to see:
#   - Total Phases: 250
#   - Total Tests: 2,542
#   - Quality Score: 100%

# 4. Test Phase Management
# Click "Phase Management" page
# Select phase "250"
# Click "Get Phase Info"
# Expected: Phase information displays

# 5. Test Run Tests
# In Phase Management, click "Run Tests"
# Expected: Tests execute and results display

# 6. Test IDE Access
# Browser: https://kushnir.cloud/ide
# Expected: VS Code interface loads

# 7. Test API Endpoint
curl -k https://kushnir.cloud/api/hermes/phases/250 | jq .
# Expected: Phase 250 information

# 8. Test Git Log
curl -k https://kushnir.cloud/api/hermes/git/log | jq '.commits | length'
# Expected: Number of commits in repository
```

### 24-Hour Stability Monitoring

```bash
# Throughout the first 24 hours after deployment, monitor:

# 1. Service Stability (every hour)
docker-compose -f docker-compose.enterprise.yml ps

# 2. Resource Usage (every hour)
docker stats --no-stream

# 3. Log Errors (every 2 hours)
docker-compose -f docker-compose.enterprise.yml logs --tail 1000 | grep -i "error\|failed"

# 4. API Responsiveness (every 30 minutes)
curl -k https://kushnir.cloud/api/hermes/health

# 5. Database Connections (every 4 hours)
docker exec code-server-postgres psql -U postgres -d code-server-db -c "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;"

# 6. Disk Usage (every 12 hours)
df -h /home

# Expected: Stable usage, no errors, all services healthy
```

---

## Troubleshooting

### Deployment Hangs at "Waiting for services to become healthy"

```bash
# This usually means services are taking longer to start
# OR a service failed to start properly

# In another terminal, check service status:
docker-compose -f docker-compose.enterprise.yml ps

# If any service shows "Exited" or "Restarting", check logs:
docker logs -f <service-name>

# Common causes:
# - Port already in use: sudo lsof -i :<port>
# - Out of disk space: df -h
# - Out of memory: free -h
# - Permission issues: sudo chown -R akushnir:akushnir /home/akushnir/code-server

# If a service keeps failing, manually restart it:
docker-compose -f docker-compose.enterprise.yml restart <service-name>
```

### OAuth Login Returns "Invalid Client"

```bash
# This means OAuth credentials are incorrect

# Verify credentials in .env:
cat .env | grep OAUTH_GOOGLE_CLIENT

# If blank, set credentials again:
nano .env

# Restart Appsmith with new credentials:
docker-compose -f docker-compose.enterprise.yml restart appsmith

# Wait 30 seconds then try login again
```

### API Returns 502 Bad Gateway

```bash
# This means hermes-integration service is not responding

# Check if service is running:
docker ps | grep hermes-integration

# If not running, check logs:
docker logs hermes-integration | tail -50

# Restart the service:
docker-compose -f docker-compose.enterprise.yml restart hermes-integration

# Test again:
curl -k https://kushnir.cloud/api/hermes/health
```

### Dashboard Won't Load

```bash
# Check if Appsmith service is running
docker ps | grep appsmith

# If not running, restart:
docker-compose -f docker-compose.enterprise.yml restart appsmith

# Check Appsmith logs:
docker logs appsmith | tail -50

# Wait 60 seconds for Appsmith to fully start, then try again
```

### SSL Certificate Errors

```bash
# Caddy (reverse proxy) automatically generates certificates

# For production with valid domain:
# Caddy will automatically get Let's Encrypt certificate
# Just ensure DNS points to correct IP

# To bypass certificate errors in testing:
curl -k https://kushnir.cloud/

# To check certificate details:
echo | openssl s_client -connect kushnir.cloud:443 2>/dev/null | grep -E "subject|issuer|dates"
```

---

## Emergency Procedures

### Quick Stop (if something goes wrong)

```bash
# Stop all services immediately
docker-compose -f docker-compose.enterprise.yml down

# Wait 10 seconds
sleep 10

# Restart everything
docker-compose -f docker-compose.enterprise.yml up -d
```

### Full Rollback

```bash
# If deployment is critically broken:

# 1. Stop all services
docker-compose -f docker-compose.enterprise.yml down

# 2. Remove all volumes (WARNING: deletes data)
docker volume prune -f

# 3. Clean up containers
docker system prune -a

# 4. Restore from previous git commit
git checkout HEAD~1

# 5. Redeploy
./deploy-production.sh
```

### Reset Database

```bash
# If database is corrupted:

# 1. Stop PostgreSQL
docker-compose -f docker-compose.enterprise.yml stop code-server-postgres

# 2. Remove database volume
docker volume rm hermes-agent_postgres-data

# 3. Start PostgreSQL (will recreate database)
docker-compose -f docker-compose.enterprise.yml up -d code-server-postgres

# 4. Restart all services
docker-compose -f docker-compose.enterprise.yml restart
```

---

## Success Criteria

✅ All services running and healthy  
✅ HTTPS working with valid certificate  
✅ OAuth authentication functional  
✅ Dashboard accessible at https://kushnir.cloud  
✅ IDE accessible at https://kushnir.cloud/ide  
✅ API responding at https://kushnir.cloud/api/hermes  
✅ All 250 phases accessible  
✅ Tests executable and passing  
✅ No errors in logs  
✅ Performance acceptable (< 2s page load)  

---

## Support & Contact

For deployment issues:

1. **Check logs first:** `docker-compose -f docker-compose.enterprise.yml logs`
2. **Review documentation:** OPERATIONAL_HANDOFF_FOR_OPS_TEAM.md
3. **Run verification:** `./verify-appsmith-integration.sh`
4. **Consult troubleshooting:** See section above

---

**Execution Ready:** April 30, 2026  
**Status:** ✅ READY FOR DEPLOYMENT  
**Time to Deployment:** 2-3 minutes  
