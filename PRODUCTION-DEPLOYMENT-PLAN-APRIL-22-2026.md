# Production Deployment & Validation Plan
**April 22, 2026** | Kushnir.cloud (KC) Infrastructure

---

## Overview

Comprehensive deployment and validation of recent P0/P1 infrastructure work:
- **P0 Security**: Zero-Trust mTLS with 3-node relay cluster, DLP, gVisor isolation
- **P1 Infrastructure**: WebSocket gateway cluster (HAProxy + 3-node relay)
- **P1 Collaboration**: PagerDuty incident integration for auto-file-open

**Deployment Targets:**
- Primary: 192.168.168.31 (Ubuntu, Docker Compose)
- Replica: 192.168.168.42 (HA failover, Redis Sentinel)

**Total Estimated Time**: 4-6 hours (including validation)

---

## Phase 1: Pre-Deployment Validation (30 minutes)

### 1.1 Verify Current Infrastructure Status
```bash
ssh akushnir@192.168.168.31 'cd /home/akushnir/code-server-enterprise-ops && docker-compose ps'
# Verify: All core services running (code-server, postgres, redis, caddy, etc.)

# Expected output:
# CONTAINER ID  IMAGE                  STATUS
# ...           code-server-enterprise:4.115.0   Up 2 days
# ...           postgres:15-alpine               Up 2 days
# ...           redis:7-alpine                   Up 2 days
# ...           caddy:2.7.6@sha256:...          Up 2 days
```

### 1.2 Verify Connectivity
```bash
# Test primary host SSH access
ssh akushnir@192.168.168.31 'echo "Primary OK"'

# Test replica host SSH access  
ssh akushnir@192.168.168.42 'echo "Replica OK"'

# Test NAS connectivity (192.168.168.56)
ssh akushnir@192.168.168.31 'ping -c 1 192.168.168.56'
```

### 1.3 Backup Current Configuration
```bash
# On primary host (192.168.168.31)
ssh akushnir@192.168.168.31 'cd /home/akushnir/code-server-enterprise-ops && \
  mkdir -p backups/2026-04-22-pre-deploy && \
  cp docker-compose.yml backups/2026-04-22-pre-deploy/ && \
  cp .env.production backups/2026-04-22-pre-deploy/ && \
  cp Caddyfile backups/2026-04-22-pre-deploy/ && \
  echo "Backup complete"'
```

### 1.4 Verify All Scripts Present
```bash
# Check deployment scripts exist
ssh akushnir@192.168.168.31 'cd /home/akushnir/code-server-enterprise-ops && \
  ls -la scripts/infrastructure/ | grep websocket && \
  ls -la scripts/security/ | grep mtls && \
  echo "Scripts verified"'
```

---

## Phase 2: P0 Security Stack Deployment (90 minutes)

### 2.1 Deploy mTLS Infrastructure (Primary Host)

**Estimated Time**: 30 minutes | **Risk**: LOW

```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Navigate to deployment directory
cd /home/akushnir/code-server-enterprise-ops

# Step 1: Run DRY-RUN (validation, no changes)
export DRY_RUN=1
bash scripts/ops/provision-ide-session-lb-secret.sh
# Expected output: "DRY_RUN mode - showing what would be done..."
# (Review changes before proceeding)

# Step 2: Execute real deployment
export DRY_RUN=0
bash scripts/ops/provision-ide-session-lb-secret.sh
# Takes ~10 minutes for certificate generation and rotation setup

# Step 3: Verify deployment
bash scripts/ops/verify-ide-session-lb-secret.sh
# Expected output: "✓ All 6 verification checks PASSED"
# (6 checks: Files, Permissions, Caddyfile, Systemd, Docker secrets, Certificates)
```

**Verification Checklist:**
- ✅ Root CA file exists: `config/mtls-certs/ca-root/ca-cert.pem`
- ✅ Intermediate CA exists: `config/mtls-certs/ca-intermediate/ca-intermediate-cert.pem`
- ✅ 13 service certificates generated
- ✅ Docker secrets created for all services
- ✅ Systemd timer scheduled for daily 02:00 UTC rotation
- ✅ Caddyfile updated with session secret
- ✅ Backup created with 7-day retention

### 2.2 Deploy mTLS to Replica Host (192.168.168.42)

**Estimated Time**: 30 minutes | **Risk**: LOW

```bash
# SSH to replica host
ssh akushnir@192.168.168.42

# Copy certificates from primary
scp -r akushnir@192.168.168.31:/home/akushnir/code-server-enterprise-ops/config/mtls-certs* \
  /home/akushnir/code-server-enterprise-ops/config/

# Apply same deployment
cd /home/akushnir/code-server-enterprise-ops
bash scripts/ops/provision-ide-session-lb-secret.sh  # DRY_RUN=0
bash scripts/ops/verify-ide-session-lb-secret.sh
```

### 2.3 Activate mTLS in Docker Compose

**Estimated Time**: 15 minutes

```bash
# On primary host
cd /home/akushnir/code-server-enterprise-ops

# Load the mTLS overlay
docker-compose -f docker-compose.yml -f docker-compose.mtls.yml up -d

# Wait for all services to restart (~5-10 minutes)
sleep 30 && docker-compose ps

# Verify all services healthy
docker-compose ps | grep -c "Up" # Should match total service count
```

### 2.4 Verify mTLS Deployment

```bash
# Check that services are communicating via mTLS
ssh akushnir@192.168.168.31 'docker-compose logs code-server | tail -20 | grep -i "tls\|certificate"'

# Check systemd timer is active
ssh akushnir@192.168.168.31 'systemctl status rotate-ide-session-lb-secret.timer'
# Expected: "Active: active (waiting)" 

# Test certificate rotation (dry-run)
ssh akushnir@192.168.168.31 'DRY_RUN=1 bash scripts/security/rotate-mtls-certificates.sh'
```

**Expected Outcomes:**
- ✅ All 13 services running with mutual TLS
- ✅ Certificate rotation scheduled daily at 02:00 UTC
- ✅ Zero-downtime deployment (services restarted gracefully)
- ✅ Session security strengthened (secret rotated from hardcoded value)

---

## Phase 3: WebSocket Gateway Cluster Deployment (90 minutes)

### 3.1 Deploy Infrastructure

**Estimated Time**: 20 minutes | **Risk**: LOW

```bash
# On primary host
cd /home/akushnir/code-server-enterprise-ops

# Load the WebSocket gateway overlay
docker-compose -f docker-compose.yml -f docker-compose.websocket-gateway.yml up -d

# Verify cluster is running
docker-compose ps | grep ws-relay
# Expected: 3 relay nodes running (ws-relay-1, ws-relay-2, ws-relay-3)

docker-compose ps | grep haproxy
# Expected: HAProxy running

# Wait for services to stabilize (30 seconds)
sleep 30

# Check logs
docker-compose logs haproxy | tail -10  # Should show healthy backends
docker-compose logs ws-relay-1 | tail -5  # Should show ready to accept connections
```

### 3.2 Validate Cluster Health

**Estimated Time**: 10 minutes

```bash
# Check HAProxy stats page
curl http://localhost:8404/stats | grep -c "UP"
# Expected: 3 relay nodes should show "UP"

# Check individual relay health
for i in 1 2 3; do
  curl http://localhost:300$i/health
  # Expected: {"status":"healthy","connections":0,"messages":0}
done

# Test WebSocket connectivity to HAProxy
wscat -c ws://localhost:8080/test
# Expected: Should connect successfully
```

### 3.3 Deploy Cluster Monitoring

**Estimated Time**: 15 minutes

```bash
# Prometheus scrape targets are already configured
# Verify Prometheus is collecting metrics
curl http://localhost:9090/api/v1/targets | grep websocket
# Expected: All 3 relays and HAProxy in metrics

# Verify Grafana dashboard
# Manual step: Open http://192.168.168.31:3000
# - Username: admin (default)
# - Password: check docker-compose.yml for GRAFANA_ADMIN_PASSWORD
# - Verify "WebSocket Gateway Cluster" dashboard exists
```

### 3.4 Deploy to Replica (Optional HA)

**Estimated Time**: 20 minutes

```bash
# On replica host (192.168.168.42)
cd /home/akushnir/code-server-enterprise-ops

# Deploy same stack
docker-compose -f docker-compose.yml -f docker-compose.websocket-gateway.yml up -d

# Verify cluster
docker-compose ps | grep "ws-relay\|haproxy"
```

---

## Phase 4: WebSocket Load Testing (60 minutes)

### 4.1 Install k6 (if needed)

```bash
# Check if k6 is installed
k6 version
# If not found, install:
sudo apt-get install k6
```

### 4.2 Run Baseline Load Test (100 VUs)

**Estimated Time**: 8 minutes

```bash
# Navigate to test directory
cd /home/akushnir/code-server-enterprise-ops

# Run 100 concurrent pairs for 5 minutes
k6 run scripts/tests/k6-websocket-gateway-test.js \
  --vus 100 \
  --duration 5m \
  --env GATEWAY_HOST=localhost:8080

# Expected Results:
# - Connection time p95: < 2s
# - Message latency p95: < 100ms  
# - Error rate: < 1%
# - Throughput: 1000+ messages/second
```

### 4.3 Run Target Load Test (500 VUs)

**Estimated Time**: 12 minutes

```bash
# 500 concurrent pairs for 5 minutes
k6 run scripts/tests/k6-websocket-gateway-test.js \
  --vus 500 \
  --duration 5m \
  --env GATEWAY_HOST=localhost:8080

# Expected Results:
# - Connection time p95: < 2s
# - Message latency p95: < 150ms (slight increase under load)
# - Error rate: < 1%
# - Throughput: 5000+ messages/second
```

### 4.4 Run Peak Load Test (1000 VUs)

**Estimated Time**: 20 minutes

```bash
# 1000 concurrent pairs for 15 minutes
# (Ramp-up 5m → Hold 5m → Ramp-down 5m)
k6 run scripts/tests/k6-websocket-gateway-test.js \
  --vus 1000 \
  --duration 15m \
  --env GATEWAY_HOST=localhost:8080 \
  --summary-export=/tmp/k6-results-1000vus.json

# Expected Results:
# - Connection time p95: < 3s (under peak load)
# - Message latency p95: < 200ms (acceptable under 1000 VUs)
# - Error rate: < 1%
# - Throughput: 10,000+ messages/second
# - No memory leaks (check HAProxy/relay memory usage)
```

### 4.5 Verify Results

```bash
# Convert JSON results to summary
k6-to-grafana import /tmp/k6-results-1000vus.json \
  --url http://localhost:9090 \
  --job websocket-1k-load-test

# Expected outcome:
# ✅ All thresholds passed
# ✅ No service crashes during test
# ✅ Clean shutdown after test
# ✅ Cluster ready for traffic ramp
```

---

## Phase 5: PagerDuty Integration Validation (30 minutes)

### 5.1 Verify Service Running

```bash
# Check if PagerDuty service is running
curl http://localhost:9094/health
# Expected: {"status":"ready","uptime":"..."}

# Get current incidents (should be empty initially)
curl http://localhost:9094/incidents
# Expected: {"incidents":[],"count":0}
```

### 5.2 Send Test Incident

```bash
# Simulate PagerDuty incident
curl -X POST http://localhost:9094/test/incident \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Redis connection timeout in cache-service",
    "service": "Cache",
    "severity": "high"
  }'

# Response should include incident details and workspace context
```

### 5.3 Verify Workspace Context

```bash
# Get incident details
INCIDENT_ID=$(curl -s http://localhost:9094/incidents | jq -r '.incidents[0].id')

# Get workspace context (files to open)
curl http://localhost:9094/incidents/$INCIDENT_ID/workspace-context | jq .

# Expected response:
# {
#   "incident": {...},
#   "files": {
#     "pinned": ["src/services/cache/..."],
#     "recent": ["docker-compose.yml", "CHANGELOG.md"],
#     "stackTrace": [],
#     "config": ["config/redis.yaml"]
#   },
#   "onCall": {...},
#   "searchContext": {...}
# }
```

### 5.4 Verify Notifications

```bash
# Check logs for notification events
docker-compose logs pagerduty-integration | tail -20
# Should show: "incident.triggered", "workspace.context.generated", "notification.sent"
```

### 5.5 Test End-to-End (Manual)

**This requires actual PagerDuty account configuration:**

1. Log into PagerDuty console
2. Navigate to **Services** → Select your service
3. Go to **Integrations** → **Add Integration**
4. Select "Generic Webhook" (or custom)
5. Configure webhook URL: `http://192.168.168.31:9094/webhooks/pagerduty`
6. Enable events: All incident events
7. Test with a manual incident trigger
8. Verify workspace opens appropriate files

---

## Phase 6: Post-Deployment Validation (30 minutes)

### 6.1 Health Checks

```bash
# Core services
docker-compose ps | grep -E "code-server|postgres|redis|caddy" | grep "Up"
# Expected: All running

# Security services
docker-compose ps | grep -E "ws-relay|haproxy" | grep "Up"
# Expected: All running

# Collaboration services  
curl http://localhost:9094/health
# Expected: {"status":"ready"}
```

### 6.2 Performance Baselines

```bash
# Verify no performance regressions
curl http://localhost:9095/metrics | grep "http_request_duration_seconds"
# Compare to pre-deployment baseline

# Check memory usage
docker stats --no-stream | awk 'NR>1 {print $1 ":" $6}'
# Expected: No significant increase from deployment
```

### 6.3 Security Verification

```bash
# Verify mTLS is enforced
docker-compose exec code-server openssl s_client -connect postgres:5432 -CAfile /mnt/certs/ca-cert.pem
# Expected: TLS connection successful

# Verify certificate rotation scheduled
systemctl status rotate-ide-session-lb-secret.timer
# Expected: "Active: active (waiting)"
```

### 6.4 Monitoring Integration

```bash
# Verify Prometheus is collecting all metrics
curl http://localhost:9090/api/v1/query?query='count(up)'
# Expected: Should match number of services being monitored

# Verify Grafana dashboards are available
curl -s http://localhost:3000/api/dashboards | jq '.[].title'
# Expected: WebSocket Gateway Cluster, mTLS Security, PagerDuty Incidents
```

---

## Rollback Procedures

### If mTLS Deployment Fails

```bash
# Restore from backup
cd /home/akushnir/code-server-enterprise-ops
cp backups/2026-04-22-pre-deploy/docker-compose.yml .
cp backups/2026-04-22-pre-deploy/.env.production .
cp backups/2026-04-22-pre-deploy/Caddyfile .

# Restart without mTLS overlay
docker-compose down
docker-compose up -d

# Verify services
docker-compose ps
```

### If WebSocket Cluster Fails

```bash
# Remove overlay
docker-compose -f docker-compose.yml down -f docker-compose.websocket-gateway.yml

# Restart core services
docker-compose up -d

# Verify
docker-compose ps | grep -E "code-server|postgres|redis"
```

### If PagerDuty Integration Fails

```bash
# Logs will show error
docker-compose logs pagerduty-integration | tail -50

# Fix and restart
docker-compose restart pagerduty-integration

# Verify
curl http://localhost:9094/health
```

---

## Success Criteria

✅ **All 13 microservices** running with mTLS enabled  
✅ **WebSocket gateway cluster** handling 1000 concurrent pairs  
✅ **Load test results** meet performance thresholds  
✅ **PagerDuty integration** successfully routes incident context  
✅ **Monitoring dashboards** display real-time metrics  
✅ **Zero data loss** during deployment  
✅ **Graceful failover** tested on replica  
✅ **Rollback procedures** validated  

---

## Post-Deployment Reporting

Create evidence documents:
1. **Deployment Evidence** - Screenshots, logs, metrics
2. **Load Test Results** - k6 summary, performance graphs
3. **Security Verification** - mTLS certificates, rotation status
4. **Integration Testing** - PagerDuty webhook logs
5. **Monitoring Dashboard** - Grafana screenshots
6. **Operational Runbook** - On-call procedures

---

## Timeline Summary

| Phase | Component | Duration | Status |
|-------|-----------|----------|--------|
| 1 | Pre-Deployment Validation | 30 min | Scheduled |
| 2 | P0 Security Stack (mTLS) | 90 min | Scheduled |
| 3 | WebSocket Gateway Cluster | 90 min | Scheduled |
| 4 | Load Testing (k6) | 60 min | Scheduled |
| 5 | PagerDuty Integration | 30 min | Scheduled |
| 6 | Post-Deployment Validation | 30 min | Scheduled |
| **Total** | **End-to-End** | **~5.5 hours** | **Ready** |

---

**Deployment Authorization**: Ready (all prerequisites met)  
**Risk Level**: LOW (tested components, rollback available)  
**Estimated Completion**: April 22, 2026, 11 PM UTC  
**Next Review**: April 23, 2026, 9 AM UTC
