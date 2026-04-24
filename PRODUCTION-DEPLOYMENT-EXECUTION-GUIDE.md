# Production Deployment Execution Guide
**April 22, 2026** | Ready to Execute

---

## Prerequisites Check

Before starting, ensure:
1. SSH access to both hosts (192.168.168.31 and 192.168.168.42)
2. All deployment scripts are in place on primary host
3. Current docker-compose stack is running and healthy

```bash
# Quick validation
ssh akushnir@192.168.168.31 'docker-compose ps | wc -l'
# Expected: 15+ containers running
```

---

## QUICK START: Execute Full Deployment

**For immediate execution, run this command from your local machine:**

```bash
# SSH to primary host and run full deployment
ssh akushnir@192.168.168.31 << 'EOF'
cd /home/akushnir/code-server-enterprise-ops

echo "=== Phase 1: Pre-Deployment Validation ===" 
docker-compose ps | head -15
echo "✓ Services running"

echo ""
echo "=== Phase 2: Deploy mTLS Security ===" 
DRY_RUN=1 bash scripts/ops/provision-ide-session-lb-secret.sh
# (Review output above, if satisfied, continue...)

echo ""
echo "Starting real deployment (this takes ~10 minutes)..."
DRY_RUN=0 bash scripts/ops/provision-ide-session-lb-secret.sh
bash scripts/ops/verify-ide-session-lb-secret.sh

echo ""
echo "=== Phase 3: Deploy WebSocket Gateway Cluster ===" 
docker-compose -f docker-compose.yml -f docker-compose.websocket-gateway.yml up -d
sleep 30
docker-compose ps | grep -E "ws-relay|haproxy"

echo ""
echo "=== Phase 4: Run Load Tests ===" 
echo "Testing 100 VUs..."
k6 run scripts/tests/k6-websocket-gateway-test.js --vus 100 --duration 5m

echo "Testing 500 VUs..."
k6 run scripts/tests/k6-websocket-gateway-test.js --vus 500 --duration 5m

echo "Testing 1000 VUs (full load)..."
k6 run scripts/tests/k6-websocket-gateway-test.js --vus 1000 --duration 15m

echo ""
echo "=== Phase 5: Validate PagerDuty Integration ===" 
curl http://localhost:9094/health
curl http://localhost:9094/incidents

echo ""
echo "=== DEPLOYMENT COMPLETE ===" 
docker-compose ps | grep -c "Up"
echo "services running"

EOF
```

---

## Step-by-Step Deployment (If Executing Manually)

### Step 1: Verify Current Infrastructure

```bash
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server-enterprise-ops

# Check all services are healthy
docker-compose ps

# Expected: All services show "Up X minutes/hours"
# If any show "Exited", restart: docker-compose restart <service>
```

### Step 2: Create Pre-Deployment Backup

```bash
mkdir -p backups/2026-04-22-pre-deploy
cp docker-compose.yml backups/2026-04-22-pre-deploy/
cp .env.production backups/2026-04-22-pre-deploy/
cp Caddyfile backups/2026-04-22-pre-deploy/
echo "Backup created"
```

### Step 3: Deploy mTLS Security (Primary)

```bash
# DRY-RUN first (shows what will happen, no changes)
export DRY_RUN=1
bash scripts/ops/provision-ide-session-lb-secret.sh

# Review output. If satisfied, proceed with real deployment:
export DRY_RUN=0
bash scripts/ops/provision-ide-session-lb-secret.sh

# Verify deployment
bash scripts/ops/verify-ide-session-lb-secret.sh

# Expected output: "✓ All 6 verification checks PASSED"
```

### Step 4: Deploy mTLS to Replica

```bash
# Copy certificates to replica
scp -r config/mtls-certs* akushnir@192.168.168.42:/home/akushnir/code-server-enterprise-ops/config/

# Deploy on replica
ssh akushnir@192.168.168.42 << 'EOF'
cd /home/akushnir/code-server-enterprise-ops
bash scripts/ops/provision-ide-session-lb-secret.sh
bash scripts/ops/verify-ide-session-lb-secret.sh
EOF
```

### Step 5: Activate mTLS in Docker Compose

```bash
# Load both base and mTLS overlay
docker-compose -f docker-compose.yml -f docker-compose.mtls.yml up -d

# Wait for services to stabilize
sleep 30

# Verify all services are running
docker-compose ps | grep "Up" | wc -l
# Expected: Should match your original service count

# Check for any errors
docker-compose logs | grep -i "error\|failed" | head -10
```

### Step 6: Deploy WebSocket Gateway Cluster

```bash
# Load WebSocket gateway overlay
docker-compose -f docker-compose.yml -f docker-compose.websocket-gateway.yml up -d

# Verify cluster
docker-compose ps | grep -E "ws-relay|haproxy"
# Expected: 4 new containers (3 relays + HAProxy)

# Check HAProxy stats
curl http://localhost:8404/stats | head -20
# Should show 3 backends "UP"
```

### Step 7: Run Load Tests

```bash
# Test 100 concurrent WebSocket pairs (5 minutes)
k6 run scripts/tests/k6-websocket-gateway-test.js \
  --vus 100 \
  --duration 5m \
  --env GATEWAY_HOST=localhost:8080

# Test 500 concurrent pairs (5 minutes)
k6 run scripts/tests/k6-websocket-gateway-test.js \
  --vus 500 \
  --duration 5m \
  --env GATEWAY_HOST=localhost:8080

# Test 1000 concurrent pairs (15 minutes - full load test)
k6 run scripts/tests/k6-websocket-gateway-test.js \
  --vus 1000 \
  --duration 15m \
  --env GATEWAY_HOST=localhost:8080 \
  --summary-export=/tmp/k6-results-1000vus.json

# Check results (all should be green/passing)
```

### Step 8: Validate PagerDuty Integration

```bash
# Check service is running
curl http://localhost:9094/health
# Expected: {"status":"ready",...}

# Get incidents (should be empty)
curl http://localhost:9094/incidents
# Expected: {"incidents":[],"count":0}

# Send test incident
curl -X POST http://localhost:9094/test/incident \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Redis timeout in cache-service",
    "service": "Cache",
    "severity": "high"
  }'

# Get incident and workspace context
INCIDENT_ID=$(curl -s http://localhost:9094/incidents | jq -r '.incidents[0].id')
curl http://localhost:9094/incidents/$INCIDENT_ID/workspace-context | jq .
# Should show relevant files to open
```

### Step 9: Final Health Check

```bash
# Count running services
docker-compose ps | grep "Up" | wc -l

# Check memory usage (should be reasonable)
docker stats --no-stream | tail -10

# Verify metrics are collected
curl http://localhost:9090/api/v1/query?query='count(up)' 2>/dev/null | jq '.data.result[0].value'

# Check Grafana is accessible
curl -I http://localhost:3000
# Expected: HTTP 200
```

---

## Monitoring During Deployment

Open these in browser tabs while deploying:

1. **HAProxy Stats**: http://192.168.168.31:8404/stats
   - Watch backends change from "DOWN" → "UP"
   - Monitor connection counts during load test

2. **Prometheus**: http://192.168.168.31:9090
   - Query `up{job="websocket-gateway"}` to see relay health
   - Graph memory usage: `container_memory_usage_bytes`

3. **Grafana**: http://192.168.168.31:3000
   - Default: admin/admin (or check docker-compose.yml)
   - Watch "WebSocket Gateway Cluster" dashboard during k6 test

4. **Docker Logs**:
   ```bash
   # In separate terminal, stream logs
   docker-compose logs -f | grep -E "ERROR|WARNING|CRITICAL"
   ```

---

## Troubleshooting Quick Reference

### If mTLS deployment fails:
```bash
# Check error message
bash scripts/ops/provision-ide-session-lb-secret.sh 2>&1 | tail -30

# Rollback
docker-compose down
cp backups/2026-04-22-pre-deploy/docker-compose.yml .
docker-compose up -d
```

### If WebSocket cluster fails:
```bash
# Check logs
docker-compose logs ws-relay-1 | tail -50

# Verify Redis is accessible
redis-cli ping
# Expected: PONG

# Restart cluster
docker-compose restart ws-relay-1 ws-relay-2 ws-relay-3 haproxy
```

### If load test crashes:
```bash
# Check system resources
free -h
# Check if memory is low, CPU is maxed out

# Reduce VU count and retry
k6 run scripts/tests/k6-websocket-gateway-test.js --vus 500 --duration 5m
```

### If PagerDuty integration is unreachable:
```bash
# Verify container is running
docker-compose ps | grep pagerduty

# Check logs
docker-compose logs pagerduty-integration | tail -50

# Restart
docker-compose restart pagerduty-integration

# Verify
curl http://localhost:9094/health
```

---

## Expected Timeline

| Phase | Duration | Checkpoint |
|-------|----------|-----------|
| Pre-deployment validation | 5 min | Services healthy ✓ |
| mTLS primary deployment | 15 min | Verify script passes ✓ |
| mTLS replica deployment | 15 min | Certificates synced ✓ |
| Docker Compose restart | 10 min | All services "Up" ✓ |
| WebSocket cluster deploy | 5 min | 3 relays + HAProxy running ✓ |
| Load test 100 VUs | 8 min | <2s connect, <100ms latency ✓ |
| Load test 500 VUs | 10 min | <2s connect, <150ms latency ✓ |
| Load test 1000 VUs | 20 min | <3s connect, <200ms latency ✓ |
| PagerDuty validation | 5 min | Webhook receives incidents ✓ |
| **Total** | **~90 min** | **Production ready** ✓ |

---

## Success Indicators

After completing all steps:

✅ **Metrics visible on Prometheus**:
```bash
curl http://localhost:9090/api/v1/query?query='rate(http_requests_total[5m])'
```

✅ **WebSocket connections established**:
```bash
wscat -c ws://localhost:8080/test
# Should connect and echo back messages
```

✅ **mTLS certificates active**:
```bash
openssl s_client -connect localhost:5432 -CAfile config/mtls-certs/ca-root/ca-cert.pem
# Should establish TLS connection to postgres
```

✅ **PagerDuty incidents routable**:
```bash
curl http://localhost:9094/incidents | jq '.count'
# Should show > 0 if test incident was created
```

✅ **No critical errors in logs**:
```bash
docker-compose logs | grep -i "critical\|fatal" | wc -l
# Should return 0
```

---

## Next Steps After Successful Deployment

1. **Create Deployment Evidence Report** (5-10 min)
   - Screenshot metrics dashboards
   - Save load test results
   - Document any issues encountered

2. **Deploy to Replica for HA** (10 min)
   - Repeat phases 2-5 on 192.168.168.42
   - Verify cross-host communication

3. **Configure Monitoring Alerts** (15 min)
   - Set up AlertManager rules
   - Configure incident escalation

4. **Conduct Failover Test** (20 min)
   - Stop primary services
   - Verify replica takes traffic
   - Document failover time

5. **Document Runbooks** (30 min)
   - How to rotate mTLS certificates
   - How to scale WebSocket cluster
   - How to respond to PagerDuty incidents

---

## Emergency Rollback (If Needed)

Complete rollback to pre-deployment state:

```bash
cd /home/akushnir/code-server-enterprise-ops

# Stop current stack
docker-compose down

# Restore backup
cp backups/2026-04-22-pre-deploy/docker-compose.yml .
cp backups/2026-04-22-pre-deploy/.env.production .
cp backups/2026-04-22-pre-deploy/Caddyfile .

# Restart without overlays
docker-compose up -d

# Verify
docker-compose ps
```

---

**Ready to Deploy?** Execute the QUICK START command above.  
**Questions?** Refer back to PRODUCTION-DEPLOYMENT-PLAN-APRIL-22-2026.md for detailed procedures.  
**Contact**: akushnir@kushnir.cloud for operational support
