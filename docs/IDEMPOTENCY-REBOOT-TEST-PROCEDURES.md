# Kushnir.cloud Cluster Idempotency Reboot Test Procedures

**Version**: 1.0  
**Last Updated**: April 24, 2026  
**Scope**: Production cluster on-prem validation (192.168.168.31 and 192.168.168.42)  

---

## 1. OVERVIEW

This document outlines procedures for validating cluster idempotency through controlled reboot cycles. Idempotency validation proves that:

- Services auto-recover without manual intervention
- State is consistent and immutable across reboots
- Session continuity is maintained for users
- Data integrity is preserved
- Failover mechanisms work correctly

**Test Duration**: 30-45 minutes per replica  
**Risk Level**: Low (no production impact if failover works)  
**Best Time to Run**: During maintenance window or low-traffic period  

---

## 2. PREREQUISITES

Before running reboot tests:

- [ ] Both replicas healthy (20/20 services each)
- [ ] Cluster at stable commit (4bfcaa2a or verified production version)
- [ ] Grafana dashboard shows both replicas HEALTHY
- [ ] Health endpoints responding 200 OK or 403 redirect
- [ ] PostgreSQL replication lag < 1 second
- [ ] Redis Sentinel master link stable
- [ ] NAS mount accessible from both replicas
- [ ] Load balancer configured and routing traffic
- [ ] Team notified via Slack #infrastructure channel
- [ ] Monitoring active (Prometheus, Grafana, AlertManager)

**Quick Pre-Check**:

```bash
# Verify both replicas are healthy
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker ps -q | wc -l"  # Should be 20
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q | wc -l"  # Should be 20

# Verify health endpoints
curl -k https://192.168.168.31/health -I  # Should be 200 or 403
curl -k https://192.168.168.42/health -I  # Should be 200 or 403

# Verify Grafana dashboard
# Navigate to: https://grafana.kushnir.cloud/d/cluster-health-production
# Expected: Both replicas showing HEALTHY (green)
```

---

## 3. PRE-REBOOT VALIDATION

Before initiating the reboot, capture baseline metrics:

### Step 1: Document Current State (5 min)

```bash
# Capture replica 31 baseline
echo "=== REPLICA 31 PRE-REBOOT STATE ===" > /tmp/r31-preboot.txt
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 << 'EOF' >> /tmp/r31-preboot.txt
echo "Commit:" && git -C code-server-enterprise rev-parse --long HEAD
echo "Services:" && docker ps -q | wc -l
echo "Uptime:" && uptime
echo "Disk Usage:" && df -h /
echo "Memory:" && free -h
echo "PostgreSQL Replication:" && docker exec postgres psql -U postgres -c "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;" 2>/dev/null || echo "N/A"
echo "Redis Info:" && docker exec redis redis-cli INFO server | grep uptime_in_seconds || echo "N/A"
EOF

cat /tmp/r31-preboot.txt
```

### Step 2: Capture Health Baseline (3 min)

```bash
# Record health endpoint response
echo "=== HEALTH CHECK BASELINE ===" > /tmp/health-baseline.txt
for i in {1..5}; do
  echo "Request $i:" >> /tmp/health-baseline.txt
  curl -k https://192.168.168.31/health -w "\nHTTP %{http_code}\n" >> /tmp/health-baseline.txt 2>&1
  sleep 1
done

cat /tmp/health-baseline.txt
```

### Step 3: Count Active Sessions (2 min)

```bash
# Count active sessions in Redis
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 << 'EOF'
echo "=== ACTIVE SESSIONS PRE-REBOOT ==="
docker exec redis redis-cli DBSIZE
docker exec redis redis-cli KEYS "session:*" | wc -l
EOF
```

---

## 4. CONTROLLED REBOOT PROCEDURE

### Phase 1: Reboot Single Replica (Non-Disruptive)

For minimal impact, reboot **Replica 42** first (allows R31 to handle traffic):

```bash
# Step 1: Verify R31 is handling all traffic
echo "=== CONFIRMING R31 IS HEALTHY ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker ps -q | wc -l"  # Should be 20
curl -k https://192.168.168.31/health -I  # Should be 200/403

# Step 2: Initiate graceful shutdown on R42
echo "=== GRACEFUL SHUTDOWN ON R42 ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 << 'EOF'
echo "Stopping docker-compose services..."
cd code-server-enterprise
docker-compose down  # Graceful stop with 10s timeout
sleep 5
echo "Services stopped."
EOF

# Step 3: Wait for load balancer to remove R42 from rotation
echo "=== WAITING FOR LOAD BALANCER UPDATE ==="
sleep 30
echo "Checking load balancer status..."
curl http://LOADBALANCER:8080/stats 2>/dev/null | grep -A2 "192.168.168.42"
# Expected: R42 marked NOLB or DOWN

# Step 4: Initiate reboot on R42
echo "=== INITIATING REBOOT ON R42 ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "sudo reboot" &
sleep 5
echo "Reboot initiated, waiting for 90 seconds..."
sleep 90  # Wait for reboot to complete

# Step 5: Verify R42 comes online
echo "=== WAITING FOR R42 TO COME ONLINE ==="
for i in {1..30}; do
  if ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "date" 2>/dev/null; then
    echo "R42 is online after $((i*10)) seconds"
    break
  fi
  echo "Waiting... $((i*10))s"
  sleep 10
done
```

### Phase 2: Auto-Recovery Validation (10 min)

After R42 comes online, validate it auto-recovers:

```bash
# Step 1: Verify services are starting
echo "=== MONITORING AUTO-RECOVERY ===" 
for i in {1..15}; do
  service_count=$(ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q 2>/dev/null | wc -l" || echo "0")
  echo "Minute $i: $service_count/20 services running"
  sleep 60
done
# Expected progression: 0 → 5 → 10 → 15 → 20 (5-10 minutes to full recovery)

# Step 2: Verify health endpoint once all services are up
echo "=== HEALTH CHECK POST-RECOVERY ==="
curl -k https://192.168.168.42/health -I  # Should be 200/403 when ready
curl -k https://192.168.168.42/health -v | head -20

# Step 3: Verify load balancer marks R42 HEALTHY
echo "=== CHECKING LOAD BALANCER STATUS ==="
curl http://LOADBALANCER:8080/stats | grep -A3 "192.168.168.42"
# Expected: R42 marked UP (green)

# Step 4: Verify git commit is correct
echo "=== VERIFYING GIT PARITY ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "git -C code-server-enterprise rev-parse --short HEAD"
# Expected: 4bfcaa2a (same as R31)
```

---

## 5. POST-REBOOT VERIFICATION

### Step 1: Validate State Consistency (5 min)

```bash
# Check git commit parity
echo "=== GIT COMMIT PARITY ==="
COMMIT_R31=$(ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "git -C code-server-enterprise rev-parse --short HEAD")
COMMIT_R42=$(ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "git -C code-server-enterprise rev-parse --short HEAD")
echo "R31 Commit: $COMMIT_R31"
echo "R42 Commit: $COMMIT_R42"
if [ "$COMMIT_R31" = "$COMMIT_R42" ]; then
  echo "✓ Git commits match"
else
  echo "✗ GIT COMMIT MISMATCH - ESCALATE IMMEDIATELY"
  exit 1
fi

# Check service count parity
echo "=== SERVICE COUNT PARITY ==="
SERVICES_R31=$(ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker ps -q | wc -l")
SERVICES_R42=$(ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q | wc -l")
echo "R31 Services: $SERVICES_R31/20"
echo "R42 Services: $SERVICES_R42/20"
if [ "$SERVICES_R31" -eq "20" ] && [ "$SERVICES_R42" -eq "20" ]; then
  echo "✓ Both replicas at 20/20 services"
else
  echo "✗ SERVICE COUNT MISMATCH - CHECK LOGS"
fi
```

### Step 2: Validate Data Consistency (5 min)

```bash
# Check PostgreSQL replication
echo "=== DATABASE REPLICATION STATUS ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 << 'EOF'
docker exec postgres psql -U postgres -c "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"
EOF

# Check replication lag
echo "=== REPLICATION LAG ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 << 'EOF'
docker exec postgres psql -U postgres -c "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"
EOF

# Verify session data integrity
echo "=== SESSION DATA INTEGRITY ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker exec redis redis-cli DBSIZE"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker exec redis redis-cli DBSIZE"
# Expected: Both should show same or slightly higher key count (from R31)
```

### Step 3: Validate User Session Continuity (3 min)

```bash
# Test IDE accessibility from both replicas
echo "=== USER CONNECTIVITY TEST ==="
for i in {1..5}; do
  echo "Request $i via load balancer:"
  curl -k https://ide.kushnir.cloud/health -s -w "HTTP %{http_code}\n" | head -1
  sleep 1
done

# Test direct replica connectivity
echo "=== DIRECT REPLICA TESTS ==="
curl -k https://192.168.168.31/health -s -w "R31: HTTP %{http_code}\n"
curl -k https://192.168.168.42/health -s -w "R42: HTTP %{http_code}\n"
```

### Step 4: Check Health Alerts (2 min)

```bash
# Verify no critical alerts fired
echo "=== CHECKING ALERTMANAGER ==="
curl http://ALERTMANAGER:9093/api/v1/alerts | jq '.data[] | {alertname, state}' 2>/dev/null

# Check Grafana for alerts
# Navigate to: https://grafana.kushnir.cloud/d/cluster-health-production
# Expected: Both replicas showing HEALTHY, no red alerts
```

---

## 6. VALIDATION CHECKLIST

After reboot test completes, verify all items:

| Item | Expected | Pass/Fail |
|------|----------|-----------|
| **Recovery Time** | < 10 minutes to 20/20 services | ☐ |
| **Git Commit Parity** | Both at 4bfcaa2a | ☐ |
| **Service Count** | Both 20/20 running | ☐ |
| **Health Endpoints** | 200 OK or 403 redirect | ☐ |
| **DB Replication** | Lag < 1 second | ☐ |
| **Redis Data** | Session keys intact | ☐ |
| **Load Balancer** | Both marked UP (green) | ☐ |
| **Grafana Dashboard** | Both replicas HEALTHY | ☐ |
| **Active Alerts** | None critical/warning | ☐ |
| **User Connectivity** | IDE loads successfully | ☐ |
| **No Data Loss** | All sessions still present | ☐ |

---

## 7. REBOOT TEST COMPLETE - PHASE 2 (Optional)

If Phase 1 successful, optionally reboot **Replica 31** to validate complete redundancy:

```bash
# Repeat entire procedure for R31:
# 1. Verify R42 is handling traffic
# 2. Gracefully shutdown R31
# 3. Wait for load balancer update
# 4. Reboot R31
# 5. Monitor auto-recovery (5-10 minutes)
# 6. Validate parity and health
# 7. Verify both replicas back online

# Expected: Identical results to Phase 1
```

---

## 8. FAILURE SCENARIOS & RECOVERY

### Scenario A: Services Don't Auto-Start After Reboot

**Symptoms**: Replica stays at 0-5 services after 10 minutes

**Recovery**:

```bash
# SSH to the replica
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42

# Check docker daemon status
sudo systemctl status docker

# If docker isn't running, start it
sudo systemctl start docker

# Check code-server-enterprise directory
cd code-server-enterprise && ls -la

# Manually start services
docker-compose up -d

# Monitor recovery
watch -n 5 'docker ps -q | wc -l'  # Wait until 20
```

### Scenario B: Git Commit Diverges After Reboot

**Symptoms**: R42 commit differs from R31 after reboot

**Recovery**:

```bash
# Force sync to correct commit
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 << 'EOF'
cd code-server-enterprise
git fetch origin main
git reset --hard origin/main  # Force reset to latest
git rev-parse --short HEAD  # Verify correct commit
EOF

# Restart services
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose up -d'

# Verify recovery
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q | wc -l"  # Wait until 20
```

### Scenario C: Database Replication Lag > 10 Seconds

**Symptoms**: PostgreSQL replication not catching up

**Recovery**:

```bash
# Check replication status on primary
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 << 'EOF'
docker exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"
EOF

# If replica slot is stuck, manually refresh
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 << 'EOF'
docker exec postgres psql -U postgres -c "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) FROM pg_replication_slots WHERE slot_type='physical';"
# Monitor until lag approaches zero
EOF
```

---

## 9. METRICS COLLECTION

During reboot test, collect these metrics for SLA baseline:

```bash
# Create metrics file
cat > /tmp/reboot-metrics.txt << 'EOF'
REBOOT TEST METRICS
====================

Test Date: $(date)
Replica Tested: 42
Initial Service Count: 20/20
Initial Commit: $(ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "git -C code-server-enterprise rev-parse --short HEAD")

Reboot Initiated: $(date +%s)
Replica Online: $(date +%s)
Services Started: $(date +%s)  [Target: < 300s]
Health Endpoint Responding: $(date +%s)  [Target: < 400s]
Grafana Dashboard Green: $(date +%s)  [Target: < 600s]
Git Commit Match: $(date +%s)  [Target: immediate]
Data Integrity Verified: $(date +%s)  [Target: < 60s]

Recovery Duration: ___ seconds [Target: 300-600s]
Session Data Loss: ___ keys lost [Target: 0]
User Connectivity Impact: ___ seconds [Target: < 10s]

Pass/Fail: ☐ PASS  ☐ FAIL
Notes: _________________________________
EOF

cat /tmp/reboot-metrics.txt
```

---

## 10. SUCCESS CRITERIA

Reboot test is **SUCCESSFUL** if:

- ✅ Replica reboots cleanly without manual intervention
- ✅ Services auto-start after 2-3 minutes
- ✅ All 20 services running within 5-10 minutes
- ✅ Git commit matches peer replica
- ✅ Health endpoint responds (200/403)
- ✅ Load balancer marks replica UP within 10 minutes
- ✅ PostgreSQL replication lag < 1 second
- ✅ Redis session data preserved
- ✅ No critical alerts fire
- ✅ User connectivity maintained throughout
- ✅ Zero data loss

If **ALL** criteria met, idempotency is **VERIFIED**.

---

## 11. POST-TEST DOCUMENTATION

After reboot test completes successfully, document:

```bash
# Create test report
cat > /tmp/reboot-test-report.md << 'EOF'
# Cluster Idempotency Reboot Test Report

**Date**: April 24, 2026
**Replica Tested**: 42
**Tester**: [Name]

## Pre-Test State
- Both replicas: 20/20 services
- Commit: 4bfcaa2a
- Health: HEALTHY

## Reboot Sequence
- Reboot initiated: [time]
- Replica online: [time]
- Services started: [time]
- Health endpoint: [time]

## Recovery Metrics
- Total recovery time: [X minutes]
- Service startup time: [X seconds]
- Full cluster recovery: [X minutes]

## Validation Results
- ✅ All 20 services running
- ✅ Git commits match
- ✅ No data loss
- ✅ Health endpoints respond
- ✅ Grafana shows HEALTHY

## Conclusion
Idempotency test: **PASSED**
Cluster is ready for production automatic failover.
EOF

cat /tmp/reboot-test-report.md
```

---

**Document Version**: 1.0  
**Last Updated**: April 24, 2026  
**Next Review**: May 24, 2026
