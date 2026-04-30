# 🔍 POST-DEPLOYMENT OPERATIONAL MONITORING & SLA TRACKING
## Immediate Setup Guide (Execute After Go-Live)

**Date:** April 30, 2026  
**Phase:** Production Operations  
**Duration:** 24+ hours continuous monitoring

---

## 🚀 IMMEDIATE SETUP (First 15 Minutes After Go-Live)

### Step 1: Enable Real-Time Monitoring (5 min)

**Terminal 1: Service Status (Refresh every 30 seconds)**
```bash
ssh ubuntu@192.168.168.31
cd /home/akushnir/code-server

# Watch services continuously
watch -n 5 'docker-compose ps'
```

**Terminal 2: Resource Metrics (Refresh every 10 seconds)**
```bash
ssh ubuntu@192.168.168.31
cd /home/akushnir/code-server

# Watch CPU/Memory/Network
watch -n 10 'docker stats --no-stream'
```

**Terminal 3: Log Monitoring (Real-time)**
```bash
ssh ubuntu@192.168.168.31
cd /home/akushnir/code-server

# Watch for errors
docker-compose logs -f --tail=100
```

### Step 2: Verify Service Health (5 min)

```bash
# Run immediate health checks
echo "🔍 Checking API Health..."
curl -k https://kushnir.cloud/api/hermes/health -v

echo "🔍 Checking Appsmith..."
curl -k https://kushnir.cloud/ | head -c 200

echo "🔍 Checking Database..."
docker exec code-server-postgres \
  psql -U purebliss_user -d purebliss_db -c "SELECT NOW();"

echo "🔍 Checking Redis..."
docker exec code-server-redis redis-cli ping

echo "✅ All health checks complete"
```

### Step 3: Establish Baseline Metrics (5 min)

```bash
# Create baseline file
mkdir -p /home/akushnir/monitoring
cat > /home/akushnir/monitoring/baseline.txt << 'EOF'
=== PRODUCTION BASELINE - $(date) ===

Services Status:
$(docker-compose ps)

Resource Usage:
$(docker stats --no-stream --no-trunc)

Disk Usage:
$(df -h)

System Load:
$(uptime)

Network Connections:
$(netstat -tuln | grep LISTEN)

EOF

# Save baseline
timestamp=$(date +%s)
cp /home/akushnir/monitoring/baseline.txt \
   /home/akushnir/monitoring/baseline_${timestamp}.txt

echo "✅ Baseline metrics saved"
```

---

## 📊 CONTINUOUS MONITORING (Hours 0-24)

### Hour 1: Intensive Monitoring (5-min intervals)

**Every 5 minutes, check:**
1. Service status: `docker-compose ps`
2. Resource usage: `docker stats --no-stream`
3. Error logs: `docker-compose logs --since 5m --tail=20`
4. API response: `curl -w "%{time_total}\n" -o /dev/null -s -k https://kushnir.cloud/api/hermes/health`

**Expected Results:**
- All 5 services: UP
- Memory: <30%
- CPU: <40%
- Errors: NONE
- API Response: <100ms

**Alert Criteria:**
- ❌ Any service DOWN
- ❌ Memory >50%
- ❌ CPU >60%
- ❌ API Response >500ms
- ❌ Any ERROR in logs

### Hours 2-4: Alert Monitoring (15-min intervals)

**Every 15 minutes, check:**
1. Service status
2. Resource usage
3. Error logs
4. Database replication: `docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"`

**Expected Results:**
- All services UP
- Memory: <40%
- CPU: <50%
- DB Latency: <1ms
- No critical errors

### Hours 5-24: Standard Monitoring (Hourly intervals)

**Every hour, check:**
1. Service status
2. Resource usage
3. Error logs
4. Performance metrics
5. Database health

**Document Each Hour:**
```
=== HOUR [N] REPORT - $(date) ===

Services: [COUNT UP/DOWN]
Memory: [%]
CPU: [%]
Disk: [%]
API Response Time: [ms]
Errors: [COUNT]
Incidents: [DESCRIPTION or NONE]
Notes: [ANY ISSUES OR OBSERVATIONS]
```

---

## 🎯 SLA TRACKING MATRIX

### Real-Time SLA Monitoring

```bash
#!/bin/bash
# Create SLA tracking script
cat > /home/akushnir/monitoring/track-slas.sh << 'SLAEOF'
#!/bin/bash
# SLA Tracking Script - Run every 5 minutes

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SLA_FILE="/home/akushnir/monitoring/sla-tracking.csv"

# Initialize CSV if new
if [ ! -f "$SLA_FILE" ]; then
  echo "timestamp,uptime_pct,api_response_ms,error_rate_pct,memory_pct,cpu_pct" > "$SLA_FILE"
fi

# Get metrics
SERVICES=$(docker-compose ps 2>/dev/null | grep -c "Up")
UPTIME=$((SERVICES * 100 / 5))

API_RESPONSE=$(curl -s -w "%{time_total}" -o /dev/null -k https://kushnir.cloud/api/hermes/health 2>/dev/null || echo "999")
API_MS=$(echo "$API_RESPONSE * 1000" | bc)

ERROR_COUNT=$(docker-compose logs --since 5m 2>/dev/null | grep -ci "error\|exception\|fail")
ERROR_RATE=$((ERROR_COUNT))

MEMORY=$(docker stats --no-stream --no-trunc 2>/dev/null | awk 'NR>1 {gsub(/%/,"",$11); sum+=$11} END {print int(sum/NR)}')

CPU=$(docker stats --no-stream --no-trunc 2>/dev/null | awk 'NR>1 {gsub(/%/,"",$3); sum+=$3} END {print int(sum/NR)}')

# Log metrics
echo "$TIMESTAMP,$UPTIME,$API_MS,$ERROR_RATE,$MEMORY,$CPU" >> "$SLA_FILE"

# Display status
echo "[$TIMESTAMP] Uptime: ${UPTIME}% | API: ${API_MS}ms | Errors: $ERROR_COUNT | Mem: ${MEMORY}% | CPU: ${CPU}%"

# Check SLA thresholds
[ "$UPTIME" -lt 99 ] && echo "⚠️  ALERT: Uptime below target (${UPTIME}%)"
[ "$API_MS" -gt 500 ] && echo "⚠️  ALERT: API response slow (${API_MS}ms)"
[ "$MEMORY" -gt 70 ] && echo "⚠️  ALERT: Memory high (${MEMORY}%)"
[ "$CPU" -gt 60 ] && echo "⚠️  ALERT: CPU high (${CPU}%)"

SLAEOF

chmod +x /home/akushnir/monitoring/track-slas.sh
echo "✅ SLA tracking script created"
```

**Run SLA Tracking:**
```bash
# Set up cron job for automatic SLA tracking
crontab -l > mycron 2>/dev/null
echo "*/5 * * * * /home/akushnir/monitoring/track-slas.sh" >> mycron
crontab mycron
rm mycron

echo "✅ SLA tracking enabled (every 5 minutes)"
```

---

## 🔔 ALERT HANDLING

### Alert Priority Levels

**CRITICAL (Immediate Response - <5 min):**
- Any service DOWN
- API Response >5 seconds
- Error rate >10%
- Database disconnected
- Memory >85%
- Disk full

**Response:**
```bash
# 1. Immediately notify team
echo "🚨 CRITICAL: [ISSUE DESCRIPTION]" | mail -s "CRITICAL ALERT" devops@kushnir.cloud

# 2. Collect diagnostics
docker-compose logs --tail=200 > /tmp/alert_${timestamp}.log
docker stats --no-stream > /tmp/stats_${timestamp}.txt

# 3. Attempt recovery
docker-compose restart [failed-service]

# 4. Monitor recovery
watch -n 5 'docker-compose ps'

# 5. Document incident
echo "[$(date)] INCIDENT: [DESCRIPTION]" >> /home/akushnir/monitoring/incidents.log
```

**WARNING (Monitor - <15 min):**
- Memory 70-85%
- CPU 60-80%
- API Response 500ms-5s
- Error rate 1-10%
- Disk 70-85%

**Response:**
```bash
# 1. Monitor closely
watch -n 10 'docker stats --no-stream'

# 2. Investigate root cause
docker-compose logs --tail=100

# 3. Document warning
echo "[$(date)] WARNING: [DESCRIPTION]" >> /home/akushnir/monitoring/warnings.log

# 4. Escalate if worsening
```

**INFO (Informational):**
- Normal SLA metrics
- Regular operations
- Expected variations

---

## 📋 OPERATION CHECKLIST (Every Hour)

```bash
#!/bin/bash
# Hourly Operations Checklist

HOUR=$(date +%H)
echo "=== HOURLY OPERATIONS CHECKLIST - Hour $HOUR ==="

# 1. Services
SERVICES_UP=$(docker-compose ps 2>/dev/null | grep -c "Up")
echo "✓ Services Up: $SERVICES_UP/5"
[ "$SERVICES_UP" -eq 5 ] && echo "  ✅ All services running" || echo "  ❌ ALERT: Services down!"

# 2. API Health
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -k https://kushnir.cloud/api/hermes/health)
echo "✓ API Status: $API_STATUS"
[ "$API_STATUS" = "200" ] && echo "  ✅ API responsive" || echo "  ❌ ALERT: API not responding!"

# 3. Database
DB_STATUS=$(docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT 1;" 2>&1)
if echo "$DB_STATUS" | grep -q "1"; then
  echo "✓ Database: Connected"
  echo "  ✅ Database healthy"
else
  echo "✓ Database: Disconnected"
  echo "  ❌ ALERT: Database connection failed!"
fi

# 4. Memory
MEMORY=$(docker stats --no-stream --no-trunc 2>/dev/null | awk 'NR>1 {gsub(/%/,"",$11); sum+=$11} END {print int(sum/NR)}')
echo "✓ Memory Usage: ${MEMORY}%"
[ "$MEMORY" -lt 70 ] && echo "  ✅ Memory normal" || echo "  ⚠️  WARN: Memory high"

# 5. CPU
CPU=$(docker stats --no-stream --no-trunc 2>/dev/null | awk 'NR>1 {gsub(/%/,"",$3); sum+=$3} END {print int(sum/NR)}')
echo "✓ CPU Usage: ${CPU}%"
[ "$CPU" -lt 60 ] && echo "  ✅ CPU normal" || echo "  ⚠️  WARN: CPU high"

# 6. Errors
ERRORS=$(docker-compose logs --since 1h 2>/dev/null | grep -ci "error\|exception\|fail" || echo 0)
echo "✓ Errors (Last Hour): $ERRORS"
[ "$ERRORS" -eq 0 ] && echo "  ✅ No errors" || echo "  ⚠️  WARN: $ERRORS errors detected"

# 7. Disk
DISK=$(df -h /home | awk 'NR==2 {print $5}' | sed 's/%//')
echo "✓ Disk Usage: ${DISK}%"
[ "$DISK" -lt 70 ] && echo "  ✅ Disk normal" || echo "  ⚠️  WARN: Disk usage high"

echo ""
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=== END CHECKLIST ===" 
```

**Run Checklist:**
```bash
chmod +x /home/akushnir/monitoring/hourly-checklist.sh
/home/akushnir/monitoring/hourly-checklist.sh
```

---

## 📈 METRICS COLLECTION

### Create Metrics Dashboard

```bash
#!/bin/bash
# Create metrics collection script

cat > /home/akushnir/monitoring/collect-metrics.sh << 'METRICSEOF'
#!/bin/bash

METRICS_DIR="/home/akushnir/monitoring/metrics"
mkdir -p "$METRICS_DIR"

TIMESTAMP=$(date +%s)
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Collect all metrics
{
  echo "=== PRODUCTION METRICS - $DATE ==="
  echo ""
  echo "SERVICES:"
  docker-compose ps
  echo ""
  echo "RESOURCE USAGE:"
  docker stats --no-stream --no-trunc
  echo ""
  echo "DISK:"
  df -h
  echo ""
  echo "PROCESSES:"
  top -b -n 1 | head -20
  echo ""
  echo "NETWORK:"
  netstat -tuln | grep LISTEN
} > "$METRICS_DIR/metrics_${TIMESTAMP}.txt"

echo "✅ Metrics collected: $METRICS_DIR/metrics_${TIMESTAMP}.txt"
METRICSEOF

chmod +x /home/akushnir/monitoring/collect-metrics.sh
```

---

## 🎯 INCIDENT RESPONSE PROCEDURES

### When Issues Occur

1. **NOTICE:** Issue detected (5 min)
   - Alert received
   - Acknowledge alert
   - Start incident timer

2. **ASSESS:** Determine severity (5 min)
   - Collect logs
   - Check metrics
   - Identify scope
   - Classify as P1/P2/P3

3. **COMMUNICATE:** Notify team (2 min)
   - Send alert message
   - Include issue details
   - Request assistance
   - Update status

4. **INVESTIGATE:** Root cause (15 min)
   - Review logs
   - Check recent changes
   - Test connectivity
   - Identify root cause

5. **RESOLVE:** Fix issue (15 min)
   - Execute fix
   - Restart services if needed
   - Verify recovery
   - Confirm SLAs restored

6. **DOCUMENT:** Record incident (10 min)
   - Log incident details
   - Document timeline
   - Note resolution
   - Create post-mortem

---

## ✅ 24-HOUR MONITORING SIGN-OFF

**After 24 hours of successful monitoring:**

- [ ] Zero critical incidents
- [ ] All SLAs met or exceeded
- [ ] No service downtime
- [ ] All logs reviewed and clear
- [ ] Metrics baseline established
- [ ] Team confident in operations
- [ ] Escalation procedures tested
- [ ] Ready for operational handoff

**Sign-Off:**
```
Operations Lead: _________________ Date: _______
Status: ✅ PRODUCTION OPERATIONS VERIFIED
```

---

**Status: ✅ MONITORING SETUP COMPLETE**

All monitoring systems ready. SLA tracking established. Incident procedures documented.
Ready for 24/7 production operations monitoring.

🔍 **HERMES AGENT PORTAL - OPERATIONAL MONITORING ACTIVE** 🔍
