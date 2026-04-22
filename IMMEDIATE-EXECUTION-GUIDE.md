# IMMEDIATE EXECUTION GUIDE — Option 1: Docker Compose Consolidation

**Estimated Execution Time**: 45 minutes  
**Risk Level**: 🟢 LOW (config fixes only, no migrations)  
**Rollback Time**: 5 minutes (revert DNS + restart services)

---

## PRE-EXECUTION CHECKLIST

- [ ] Have SSH access to 192.168.168.31 (primary)
- [ ] Have DNS provider credentials (Cloudflare, registrar, etc.)
- [ ] Current DNS for kushnir.cloud identified (check `nslookup kushnir.cloud`)
- [ ] Backup of current `.env` file on primary
- [ ] Slack/team notification sent about 30-min maintenance window

---

## EXECUTION STEPS

### STEP 1: SSH to Primary Host (2 min)

```bash
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server-enterprise
pwd
ls -la docker-compose.yml .env
```

**Expected Output**:
```
/home/akushnir/code-server-enterprise
total 48
-rw-rw-r--  1 akushnir akushnir  8723 Mar 15 02:35 docker-compose.yml
-rw-rw-r--  1 akushnir akushnir  2150 Apr 20 15:22 .env
```

**If not found**:
- ❌ Stop. SSH might be to wrong host.
- ✅ Verify: `hostname -I` should show `192.168.168.31`

---

### STEP 2: Verify Caddy is Running & Healthy (2 min)

```bash
docker ps | grep caddy

# Expected: caddy       Up 8+ hours (healthy)

# Check logs for errors
docker logs caddy 2>&1 | grep -E "error|warning|failed" | head -5

# Check TLS certificate
docker exec caddy caddy version
# Expected: v2.9.1

# Verify Let's Encrypt cert is active
docker exec caddy curl -s http://localhost:2019/config/apps/http/servers/main | jq '.tls'
```

**If Caddy not healthy**:
- ❌ Restart: `docker-compose restart caddy`
- ⏳ Wait: `sleep 10 && docker logs caddy | tail -20`
- Check for port 80/443 conflicts: `sudo lsof -i :80 -i :443`

---

### STEP 3: Fix Prometheus Configuration (5 min)

**Problem**: prometheus-rules-phase-23.yml is a directory, not a file

```bash
# Check current config
docker exec prometheus cat /etc/prometheus/prometheus.yml | grep "rule_files" -A 2

# Expected error:
# rule_files:
#   - '/etc/prometheus/prometheus-rules-phase-23.yml'  ← Directory!

# Check what's actually in that directory
docker exec prometheus ls -la /etc/prometheus/prometheus-rules-phase-23.yml/
# Expected: List of .yml files

# Solution: Update prometheus.yml to point to individual files
# Create a volume mount update in docker-compose.yml

# First, backup current config
docker exec prometheus cat /etc/prometheus/prometheus.yml > /tmp/prometheus-backup.yml

# Fix: Edit docker-compose.yml volume for prometheus service
```

**Edit docker-compose.yml** (find prometheus service):

Change from:
```yaml
prometheus:
  volumes:
    - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    - prometheus-data:/prometheus
```

To:
```yaml
prometheus:
  volumes:
    - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    - ./config/prometheus/prometheus-rules-phase-23/:/etc/prometheus/rules:ro
    - prometheus-data:/prometheus
```

And update the yml file to reference the directory with glob pattern:

```bash
# Check if prometheus.yml has correct rule reference
grep -n "rule_files:" config/prometheus/prometheus.yml

# Should reference a directory with *.yml pattern, e.g.:
# rule_files:
#   - '/etc/prometheus/rules/*.yml'
```

If not found, edit:
```bash
# Edit config/prometheus/prometheus.yml
sudo nano config/prometheus/prometheus.yml

# Find rule_files section and update to:
rule_files:
  - '/etc/prometheus/rules/*.yml'

# Or point to specific file:
rule_files:
  - '/etc/prometheus/prometheus-rules.yml'
```

**Restart Prometheus**:
```bash
docker-compose restart prometheus
sleep 10
docker ps | grep prometheus | grep -E "Up|Exited"
```

**Verify**:
```bash
docker logs prometheus 2>&1 | grep -E "Listening|Ready|listening|loading"
# Expected: "level=info msg="Server is ready to receive requests"
```

---

### STEP 4: Fix session-broker Image Reference (5 min)

**Problem**: `CODE_SERVER_IMAGE_ID must be a sha256 digest-pinned image reference`

```bash
# Get current code-server digest
docker images code-server-enterprise:dev --digests --quiet

# Expected output: sha256:abc123...@abc123...
# If empty, try:
docker images | grep code-server-enterprise
# Expected: code-server-enterprise   dev    <digest>  ...

# Get the full digest
CODE_SERVER_DIGEST=$(docker images code-server-enterprise:dev --digests --quiet | head -1)
echo "Code-server digest: $CODE_SERVER_DIGEST"

# Check if .env already has this set
grep CODE_SERVER_IMAGE_ID .env || echo "Not set"

# Add/update in .env
if grep -q "CODE_SERVER_IMAGE_ID" .env; then
    # Update existing
    sed -i.bak "s|CODE_SERVER_IMAGE_ID=.*|CODE_SERVER_IMAGE_ID=code-server-enterprise@${CODE_SERVER_DIGEST}|" .env
else
    # Add new
    echo "CODE_SERVER_IMAGE_ID=code-server-enterprise@${CODE_SERVER_DIGEST}" >> .env
fi

# Verify
grep CODE_SERVER_IMAGE_ID .env
```

**Restart session-broker**:
```bash
docker-compose restart session-broker
sleep 10
docker logs session-broker 2>&1 | tail -20
```

**Verify**:
```bash
docker ps | grep session-broker
# Expected: Up X seconds (no "Restarting" or "Exited")

# Check logs for success
docker logs session-broker 2>&1 | grep -E "listening|started|ready" | head -1
```

---

### STEP 5: Verify Redis Sentinel Cluster (3 min)

```bash
# Check sentinel status
docker ps | grep -E "sentinel|pgbouncer" 

# Restart sentinels (they depend on session-broker)
docker-compose restart redis-sentinel-1 redis-sentinel-arbiter pgbouncer
sleep 10

# Verify all are Up
docker ps | grep -E "sentinel|pgbouncer|redis" | grep -v "redis-exporter"
# Expected: All showing "Up" state
```

**Test cluster**:
```bash
# Check if sentinels are aware of redis master
docker exec redis-sentinel-1 redis-cli -p 26379 sentinel masters
# Expected: 1 master with quorum=2, parallel-syncs=1

# Or simpler ping check
docker exec redis-sentinel-1 redis-cli -p 26379 ping
# Expected: PONG
```

---

### STEP 6: Verify Alertmanager & Other Services (2 min)

```bash
# Check all container status
docker compose ps
# Expected: All services either "Up" or specific expected state

# Quick health check
for svc in prometheus alertmanager jaeger grafana code-server; do
    status=$(docker ps | grep "^.*${svc}" | awk '{print $NF}')
    echo "${svc}: ${status:-NOT RUNNING}"
done
```

---

### STEP 7: Update DNS (5 min)

**Options based on your DNS provider**:

#### 🟢 Option A: Cloudflare
```
1. Login to Cloudflare Dashboard
2. Select kushnir.cloud domain
3. Go to DNS Records
4. Find/Edit A record for kushnir.cloud
5. Change value to: 192.168.168.31
6. Save (TTL: 3600 or lower for faster failover)
```

#### 🟢 Option B: GoDaddy / Domain Registrar
```
1. Login to domain registrar
2. Find DNS Management
3. Edit A record: kushnir.cloud → 192.168.168.31
4. Save
5. Wait 5-15 minutes for propagation
```

#### 🟢 Option C: Route53 (AWS)
```bash
# Via AWS CLI
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "kushnir.cloud",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "192.168.168.31"}]
      }
    }]
  }'
```

#### 🟢 Option D: Local /etc/hosts (Testing Only)
```bash
# On a Linux workstation (or via SSH if applying remotely)
# Edit: /etc/hosts
# Add:
192.168.168.31 kushnir.cloud
192.168.168.31 ide.kushnir.cloud
```

**Verify DNS propagation**:
```bash
# From a Linux shell
nslookup kushnir.cloud
# Expected: Name: kushnir.cloud, Address: 192.168.168.31

# Or use dig
dig kushnir.cloud @8.8.8.8
```

---

### STEP 8: Test HTTPS Access (5 min)

**From a Linux shell or SSH session**:

```bash
# Test basic HTTPS connectivity
curl -v https://kushnir.cloud --insecure 2>&1 | grep -E "HTTP/|SSL|certificate"

# If cert is valid (Let's Encrypt), remove --insecure:
curl -v https://kushnir.cloud 2>&1 | grep -E "HTTP/|certificate"

# Expected output:
# < HTTP/1.1 200 OK
# or
# < HTTP/1.1 307 Temporary Redirect (if OAuth required)
```

**Browser test**:
```
1. Open browser
2. Navigate to: https://kushnir.cloud
3. Expected:
   - No SSL warning
   - Let's Encrypt certificate visible
   - Either:
     a) code-server login page, OR
     b) oauth2-proxy authentication flow
```

**Advanced test - Check service backends**:
```bash
# Test code-server
curl -v https://ide.kushnir.cloud --insecure 2>&1 | head -20
# Expected: 200 or 401 (auth required)

# Test Prometheus
curl -v https://prometheus.kushnir.cloud --insecure 2>&1 | head -20
# Expected: 200 with Prometheus UI

# Test Grafana
curl -v https://grafana.kushnir.cloud --insecure 2>&1 | head -20
# Expected: 200 or 302 (redirect to login)
```

---

### STEP 9: Cleanup & Final Verification (5 min)

**On Primary Host**:
```bash
# Remove old backups
rm -f /tmp/prometheus-backup.yml

# Check disk usage
df -h | grep -E "Filesystem|/dev"
# Expected: Should have room for growth

# Check for error patterns in logs
for svc in prometheus session-broker redis-sentinel alertmanager; do
    echo "=== ${svc} ==="
    docker logs ${svc} 2>&1 | grep -i "error\|failed\|crash" | head -1 || echo "OK"
done
```

**Summary check**:
```bash
# Count healthy services
HEALTHY=$(docker ps | grep "healthy" | wc -l)
RUNNING=$(docker ps | grep "Up" | wc -l)
echo "Healthy: ${HEALTHY}, Running: ${RUNNING}"
# Expected: 8+ healthy, 10+ total running
```

---

## POST-EXECUTION VERIFICATION

### ✅ Success Criteria

| Check | Expected | Command |
|-------|----------|---------|
| Caddy running | Up & healthy | `docker ps \| grep caddy` |
| Prometheus healthy | Up & no errors | `docker logs prometheus \| grep -i error` |
| session-broker up | Up (not Restarting) | `docker ps \| grep session-broker` |
| HTTPS works | 200 OK | `curl -v https://kushnir.cloud \| grep HTTP` |
| Certificate valid | Let's Encrypt | Browser: https://kushnir.cloud (check cert) |
| DNS resolves | 192.168.168.31 | `nslookup kushnir.cloud` |

### ⚠️ If Something Fails

**Prometheus still crashing**:
```bash
docker exec prometheus prometheus --config.file=/etc/prometheus/prometheus.yml --validate-config
# Should output: "config file is valid"

# If not, fix the rule_files path:
docker-compose down prometheus
# Edit docker-compose.yml or config/prometheus/prometheus.yml
docker-compose up -d prometheus
```

**session-broker still restarting**:
```bash
docker logs session-broker 2>&1 | grep -A 5 "policyCode"
# If "provenance_image_not_pinned":
docker images code-server-enterprise:dev --digests
# Copy full digest and update CODE_SERVER_IMAGE_ID in .env
```

**HTTPS still failing**:
```bash
# Check DNS
nslookup kushnir.cloud
# If not resolving to 192.168.168.31, wait 5-15 min or check DNS settings

# Check if Caddy can reach the internet (Let's Encrypt validation)
docker logs caddy | grep -i "let's\|acme\|cloudflare"
# Should show successful ACME challenge
```

---

## ROLLBACK PROCEDURE (If Needed)

**If everything breaks during execution**:

```bash
# Stop all services
docker-compose down

# Restore from backup
git checkout .env docker-compose.yml config/

# Restart
docker-compose up -d

# Revert DNS (point back to replica if it was working)
# Login to DNS provider and change A record back to 192.168.168.42
```

---

## MONITORING AFTER FIX

```bash
# Watch all services for 1 hour
while true; do
    echo "=== $(date) ==="
    docker ps --format "table {{.Names}}\t{{.Status}}"
    echo ""
    sleep 60
done

# Check if any service has restarted
docker inspect --format='{{.RestartCount}}' $(docker ps -q)
# All should be 0 or stable
```

---

## SUCCESS INDICATORS

✅ When complete:
- [x] `curl https://kushnir.cloud` returns **HTTP 200 or 30x**
- [x] Browser shows **no SSL warning** 
- [x] Certificate **issuer = Let's Encrypt**
- [x] All Docker services **stable** (no Exited/Restarting)
- [x] DNS resolves **kushnir.cloud → 192.168.168.31**
- [x] User can **login to code-server or oauth2-proxy**
- [x] Monitoring tools accessible at subdomains

---

## TIMELINE REFERENCE

| Step | Duration | Cumulative |
|------|----------|-----------|
| 1. SSH + Verify | 2 min | 2 min |
| 2. Check Caddy | 2 min | 4 min |
| 3. Fix Prometheus | 5 min | 9 min |
| 4. Fix session-broker | 5 min | 14 min |
| 5. Verify Sentinel | 3 min | 17 min |
| 6. Check other services | 2 min | 19 min |
| 7. Update DNS | 5 min | 24 min |
| 8. Test HTTPS | 5 min | 29 min |
| 9. Cleanup | 5 min | 34 min |
| Buffer | 6-11 min | **40-45 min** |

---

**Last Updated**: April 21, 2026 03:45 UTC  
**Status**: Ready for execution  
**Author**: Infrastructure Team  
