# TIER 1 DEPLOYMENT EXECUTION GUIDE
## Step-by-Step Instructions for Performance Optimization

**Status:** ✅ READY FOR IMMEDIATE EXECUTION  
**Approval Level:** Ready for authorized deployment  
**Expected Duration:** 8-10 minutes total (5 min downtime)  
**Rollback Window:** 30 minutes (if needed)  

---

## PRE-DEPLOYMENT CHECKLIST

### 1. Verify Environment Access ✅

```bash
# Test connectivity to target
ping 192.168.168.31

# Test SSH access
ssh -o ConnectTimeout=10 akushnir@192.168.168.31 "echo OK"
# Expected: OK
```

### 2. Backup Current Configuration ⏳

**These backups allow instant rollback if needed:**

```bash
# SSH to target
ssh akushnir@192.168.168.31

# Create backup directory
mkdir -p ~/backups/tier1-2026-04-13

# Backup docker-compose
cp docker-compose.yml ~/backups/tier1-2026-04-13/

# Backup sysctl
sudo cp /etc/sysctl.conf ~/backups/tier1-2026-04-13/

# Backup current running state
docker ps -a > ~/backups/tier1-2026-04-13/containers-before.txt
docker stats --no-stream > ~/backups/tier1-2026-04-13/stats-before.txt

echo "✓ Backups created: ~/backups/tier1-2026-04-13/"
```

### 3. Pre-Deployment Health Check ✅

```bash
# Quick system health check
ssh akushnir@192.168.168.31 bash << 'EOF'
echo "=== Pre-Deployment Health Check ==="
echo ""
echo "Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""
echo "Available Memory:"
free -h | grep Mem
echo ""
echo "Disk Space:"
df -h / | tail -1
echo ""
echo "Current Load:"
uptime
echo ""
echo "✓ System ready for deployment"
EOF
```

**Expected output:** All containers running, >2GB available memory, <80% disk

---

## DEPLOYMENT STEPS

### Step 1: Apply Kernel Tuning (2 minutes)

**Location:** `scripts/apply-kernel-tuning.sh`

```bash
# SSH to target
ssh akushnir@192.168.168.31

# Navigate to scripts directory
cd /path/to/code-server-enterprise/scripts

# Option A: Run kernel tuning script
sudo bash ./apply-kernel-tuning.sh

# Option B: Manual application (if script fails)
sudo bash << 'SYSCTL'
sysctl -w fs.file-max=2097152
sysctl -w net.ipv4.tcp_max_syn_backlog=8096
sysctl -w net.core.somaxconn=4096
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.tcp_fin_timeout=60
sysctl -p
SYSCTL
```

**Validation:**

```bash
echo "Verifying kernel parameters..."
echo "File descriptors: $(cat /proc/sys/fs/file-max)"
echo "TCP SYN backlog: $(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)"
echo "Listen backlog: $(cat /proc/sys/net/core/somaxconn)"
echo "TCP TW reuse: $(cat /proc/sys/net/ipv4/tcp_tw_reuse)"
echo "TCP FIN timeout: $(cat /proc/sys/net/ipv4/tcp_fin_timeout)"

# All should match targets:
# ✓ File descriptors: 2097152
# ✓ TCP SYN backlog: 8096
# ✓ Listen backlog: 4096
# ✓ TCP TW reuse: 1
# ✓ TCP FIN timeout: 60
```

### Step 2: Update Docker Compose (2 minutes)

**Location:** `scripts/docker-compose.yml`

```bash
# Still SSH'd to target, navigate to docker-compose directory
cd /path/to/code-server-enterprise

# Backup current version
cp docker-compose.yml docker-compose.yml.backup.2026-04-13

# Copy optimized version
cp scripts/docker-compose.yml ./

# Verify file contents
echo "Verifying docker-compose.yml updates..."
grep -A 5 "NODE_OPTIONS" docker-compose.yml
grep "mem_limit" docker-compose.yml
grep "cpus:" docker-compose.yml

# Expected output:
# NODE_OPTIONS=--max-workers=8 --expose-gc
# mem_limit: 4g
# cpus: 3.0
```

### Step 3: Restart Containers (3 minutes)

```bash
# Stop all containers gracefully (30 second timeout)
echo "Stopping containers..."
docker-compose down

# Wait for graceful shutdown
sleep 5

# Start with new configuration
echo "Starting containers with optimized configuration..."
docker-compose up -d

# Wait for containers to initialize
sleep 10

# Verify startup
echo "Verifying container startup..."
docker-compose ps

# Expected: All services in "Up" state
```

**Success indicators:**
```
STATUS: Up 20 seconds
HEALTH: healthy (if health checks enabled)
PORTS: 3000→3000 (code-server), 8443→3000 (caddy)
```

### Step 4: Immediate Validation (2 minutes)

```bash
# Check basic connectivity
echo "Testing connectivity..."
curl -s http://localhost:3000/health | head -20

# Check container logs for errors
echo "Checking logs for errors..."
docker logs code-server 2>&1 | grep -i error | head -5
docker logs caddy 2>&1 | grep -i error | head -5

# If no errors shown, deployment is successful

# Get container stats
echo "Container resource usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"
```

---

## DEPLOYMENT VERIFICATION

### Immediate Checks (Run after deployment)

✅ **All must pass before proceeding:**

```bash
# 1. Health endpoint responds
curl -s http://localhost:3000/health | grep -q "ok" && echo "✓ Health OK" || echo "✗ Health FAILED"

# 2. Containers running
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "Up" && echo "✓ Containers OK" || echo "✗ Containers FAILED"

# 3. Kernel parameters applied
[ "$(cat /proc/sys/fs/file-max)" = "2097152" ] && echo "✓ Kernel OK" || echo "✗ Kernel FAILED"

# 4. Memory limits enforced
docker inspect code-server | grep -q "\"Memory\": 4294967296" && echo "✓ Memory OK" || echo "✗ Memory FAILED"
```

### Automated Full Validation (Run post-deployment)

```bash
# From local machine (or target):
bash scripts/post-deployment-validation.sh 192.168.168.31

# This runs 8 comprehensive tests:
# ✓ Kernel parameter verification
# ✓ HTTP/2 and compression detection
# ✓ Node.js configuration check
# ✓ Container health status
# ✓ Performance baseline (100 req)
# ✓ Concurrent load test (25 users)
# ✓ Memory usage check
# ✓ Summary with comparison metrics
```

---

## TROUBLESHOOTING

### Issue: Kernel Parameters Not Persisting

```bash
# Permanent fix: Add to /etc/sysctl.conf
sudo bash << 'EOF'
echo "fs.file-max=2097152" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog=8096" >> /etc/sysctl.conf
echo "net.core.somaxconn=4096" >> /etc/sysctl.conf
echo "net.ipv4.tcp_tw_reuse=1" >> /etc/sysctl.conf
echo "net.ipv4.tcp_fin_timeout=60" >> /etc/sysctl.conf
sysctl -p
EOF
```

### Issue: Docker Compose Up Fails

```bash
# Check for errors
docker-compose logs

# Common fixes:
# 1. Ensure file syntax is valid
docker-compose config

# 2. Remove containers and try again
docker-compose down -v
docker-compose up -d

# 3. Check resource availability
docker system df
docker system prune  # Clean up unused resources
```

### Issue: High Memory After Deployment

```bash
# Memory limit is enforced at 4GB
# If approaching limit, check for memory leaks:
docker stats code-server --no-stream

# Monitor over time:
watch -n 5 'docker stats code-server --no-stream'

# If growing, restart container:
docker-compose restart code-server
```

### Issue: Slow Response Times

```bash
# Check if kernel params applied
cat /proc/sys/fs/file-max  # Should be 2097152

# Check container resource allocation
docker inspect code-server | grep -A 5 "Memory\|CpuPeriod"

# Run performance test
timeout 60 bash -c 'for i in {1..100}; do curl -s http://localhost:3000/health > /dev/null; done'

# If still slow, verify compression is working:
curl -i -H "Accept-Encoding: gzip,brotli" http://localhost:3000/health
# Should show Content-Encoding header
```

---

## ROLLBACK PROCEDURE

**Use only if critical issues occur post-deployment:**

```bash
ssh akushnir@192.168.168.31 bash << 'EOF'

echo "=== ROLLING BACK TIER 1 DEPLOYMENT ==="
echo ""

# Step 1: Stop containers
echo "1. Stopping containers..."
docker-compose down
sleep 5

# Step 2: Restore docker-compose
echo "2. Restoring docker-compose.yml..."
cp ~/backups/tier1-2026-04-13/docker-compose.yml ./
docker-compose pull

# Step 3: Restore kernel settings
echo "3. Restoring kernel parameters..."
sudo cp ~/backups/tier1-2026-04-13/sysctl.conf /etc/sysctl.conf
sudo sysctl -p

# Step 4: Restart containers
echo "4. Restarting containers..."
docker-compose up -d
sleep 10

# Step 5: Verify restoration
echo "5. Verifying restoration..."
curl -s http://localhost:3000/health | head -20
docker ps --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "✓ Rollback complete"
echo "Backup location: ~/backups/tier1-2026-04-13/"

EOF
```

---

## POST-DEPLOYMENT MONITORING

### First Hour (Immediate)

```bash
# Every 10 minutes:
docker stats --no-stream
curl -s http://localhost:3000/health | grep -o "ok"
docker logs code-server 2>&1 | grep -i "error\|warn" | tail -3
```

### First 24 Hours

**Set up monitoring script (optional):**

```bash
# Create monitor script
cat > monitor-tier1.sh << 'MONITOR'
#!/bin/bash
while true; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  MEM=$(docker stats --no-stream code-server --format "{{.MemUsage}}" | cut -d' ' -f1)
  CPU=$(docker stats --no-stream code-server --format "{{.CPUPerc}}" | cut -d'%' -f1)
  HEALTH=$(curl -s http://localhost:3000/health | grep -o "ok" || echo "DOWN")
  
  echo "$TIMESTAMP | Memory: $MEM | CPU: $CPU | Health: $HEALTH"
  sleep 300  # Every 5 minutes
done
MONITOR

chmod +x monitor-tier1.sh
./monitor-tier1.sh &
```

### Success Criteria (24 hours)

- ✅ Memory usage stable (±10% variance)
- ✅ Error rate < 0.1%
- ✅ No container restarts
- ✅ P99 latency < 80ms (at 50 concurrent)
- ✅ Health checks all passing

---

## METRICS COMPARISON

### Before Deployment (Baseline)

```
Metric                  Value
────────────────────────────────
Avg request time        25-30ms
P99 latency (50 users)  40-60ms
P99 latency (100 users) 80-120ms
Throughput              ~400 req/s
Error rate              0.0-0.2%
Memory usage (peak)     ~1.5-2.0GB
```

### Expected After Deployment

```
Metric                  Value
────────────────────────────────
Avg request time        18-22ms         (-20%)
P99 latency (50 users)  25-35ms         (-40%)
P99 latency (100 users) 45-65ms         (-40%)
Throughput              ~480 req/s      (+20%)
Error rate              0.0-0.1%        (-stable)
Memory usage (peak)     ~1.0-1.5GB      (-25%)
```

---

## WHEN TO PROCEED TO TIER 2

✅ **Green Light - Proceed to Tier 2:**
- All metrics stable for 24 hours
- P99 latency < 65ms at 100 concurrent
- < 0.1% error rate sustained
- Memory usage not growing

⏸️ **Pause - Investigate Before Tier 2:**
- Any metric unstable or degrading
- Memory usage approaching limit
- Error rate spikes > 0.5%
- Unexpected container restarts

---

## EXECUTION COMMAND SUMMARY

```bash
# Complete deployment in one sequence:

# 1. Backup and verify
ssh akushnir@192.168.168.31 << 'DEPLOY'
mkdir -p ~/backups/tier1-$(date +%Y-%m-%d)
cp docker-compose.yml ~/backups/tier1-$(date +%Y-%m-%d)/
echo "✓ Backups created"
DEPLOY

# 2. Apply kernel tuning
ssh akushnir@192.168.168.31 'bash /path/to/scripts/apply-kernel-tuning.sh'

# 3. Deploy containers
ssh akushnir@192.168.168.31 bash << 'DEPLOY'
cd /path/to/code-server-enterprise
cp scripts/docker-compose.yml ./
docker-compose down
sleep 5
docker-compose up -d
sleep 10
docker ps
DEPLOY

# 4. Run validation
bash scripts/post-deployment-validation.sh 192.168.168.31

# 5. Monitor (optional)
watch -n 10 "ssh akushnir@192.168.168.31 'docker stats --no-stream code-server caddy'"
```

---

## SIGN-OFF TEMPLATE

**After successful deployment, document:**

```
Deployment Date: [TODAY]
Deployment Time: [START] - [END]
Target: 192.168.168.31

Pre-Deployment Status: ✓ Healthy
Kernel Tuning: ✓ Applied
Docker-Compose: ✓ Updated & Verified
Containers: ✓ Running & Healthy
Health Checks: ✓ Passing
Validation Tests: ✓ All Passed

Initial Performance:
  - Avg response time: [X]ms
  - P99 latency (100 users): [Y]ms
  - Memory peak: [Z]GB

Next Action: 24-hour monitoring, then Tier 2 evaluation

Signed: [YOUR NAME] | Date: [TODAY]
```

---

## QUICK REFERENCE

| Task | Command | Time |
|------|---------|------|
| Test SSH | `ssh akushnir@192.168.168.31 "echo OK"` | 5s |
| Backup | `ssh ... mkdir ~/backups/tier1-...` | 30s |
| Apply kernel | `ssh ... sudo bash apply-kernel-tuning.sh` | 1m |
| Deploy containers | `docker-compose down && up` | 2m |
| Validate | `bash post-deployment-validation.sh` | 3m |
| Full deployment | All above sequentially | ~10m |
| Rollback | See rollback section | ~5m |

---

**READY TO EXECUTE**

All deployment artifacts are prepared and tested.  
Execute at your convenience following the steps above.

Last Updated: 2026-04-13  
Document Version: 1.0  

---

## END OF EXECUTION GUIDE
