# PHASE 2B REAL-TIME DEPLOYMENT MONITORING SETUP

**Purpose:** Configure real-time dashboards for live visibility during May 1-21 deployment execution  
**Audience:** Monitoring Lead, Operations Lead
**Setup Time:** 30 minutes before go-live (May 1, 04:30 UTC)

---

## 🎯 MONITORING OBJECTIVES

**Primary Goal:** Real-time visibility of deployment progress and system health  
**Critical Metrics:** Container status, replication lag, resource utilization, error rates  
**Alert Thresholds:** All critical issues surface within 60 seconds  
**Dashboard Refresh:** Every 15 seconds during critical phases

---

## 📊 GRAFANA DASHBOARD SETUP

### Dashboard 1: Cluster Health Overview (PRIMARY VIEW)

**URL:** `http://192.168.168.31:3000/d/cluster-health`  
**Refresh Rate:** 15 seconds  
**Update Before Go-Live:** May 1, 04:30 UTC

**Required Panels:**

```
┌─────────────────────────────────────────────────────────┐
│ CLUSTER STATUS (Large Text Panel - Top)                │
├─────────────────────────────────────────────────────────┤
│ PRIMARY: [X/87] Containers Up                          │
│ REPLICA: [X/88] Containers Up                          │
│ Replication Lag: [X]s (target: <5s)                    │
│ VIP Status: [ ] RESPONDING                             │
│ Overall: [ ] HEALTHY                                   │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ PRIMARY NODE METRICS (4 sub-panels)                    │
├─────────────────────────────────────────────────────────┤
│ CPU Usage %     │  Memory %     │ Disk %    │ Network  │
│ [X]%            │  [X]%         │ [X]%      │ [X]Mbps  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ REPLICA NODE METRICS (4 sub-panels)                    │
├─────────────────────────────────────────────────────────┤
│ CPU Usage %     │  Memory %     │ Disk %    │ Network  │
│ [X]%            │  [X]%         │ [X]%      │ [X]Mbps  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ DEPLOYMENT PHASE TRACKING                              │
├─────────────────────────────────────────────────────────┤
│ Week 1 Phase: [X/8] - [Current Phase Name]            │
│ Progress: [████████░░░░░░░░░░░░] 40%                  │
│ Elapsed: [X] hours [X] minutes                         │
│ Estimated Completion: [Time] UTC                       │
└─────────────────────────────────────────────────────────┘
```

### Dashboard 2: Database Replication Detail

**URL:** `http://192.168.168.31:3000/d/db-replication`  
**Refresh Rate:** 15 seconds  
**Critical For:** Identifying replication issues immediately

**Required Panels:**

```
┌─────────────────────────────────────────────────────────┐
│ REPLICATION STATUS (Top)                               │
├─────────────────────────────────────────────────────────┤
│ Lag Time: [X] seconds [TREND ↑↓]                       │
│ Connected: [ ] YES                                     │
│ State: [ ] streaming / [ ] catchup / [ ] unknown       │
│ Sync State: [ ] sync / [ ] async / [ ] potential       │
│ XLog Distance: [X] MB                                  │
└─────────────────────────────────────────────────────────┘

┌──────────────────────────┬──────────────────────────────┐
│ PRIMARY METRICS          │ REPLICA METRICS              │
├──────────────────────────┼──────────────────────────────┤
│ QPS (Queries/sec): [X]   │ QPS (Queries/sec): [X]       │
│ Transactions: [X] tps    │ Transactions: [X] tps        │
│ Cache Hit %: [X]%        │ Cache Hit %: [X]%            │
│ Index Scans: [X]         │ Index Scans: [X]             │
│ Connections: [X]         │ Connections: [X]             │
└──────────────────────────┴──────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ LAG TREND (Graph - Last 24 hours)                      │
├─────────────────────────────────────────────────────────┤
│                    ▲                                     │
│  Lag (seconds)     │     ╱╲  ╱╲                         │
│                    │    ╱  ╲╱  ╲  (should be <5s)       │
│  5s ─────────────  │──  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─         │
│                    │ ╱╲                                 │
│  0s ─────────────  ╱──────────────────────────────────  │
│                   └─────────────────────────────────────│
└─────────────────────────────────────────────────────────┘
```

### Dashboard 3: Application Performance

**URL:** `http://192.168.168.31:3000/d/app-performance`  
**Refresh Rate:** 30 seconds

**Required Panels:**

```
┌────────────────┬────────────────┬────────────────┐
│ API Response   │ Web Response   │ Error Rate     │
│ (p50/p99/p100)│ (p50/p99)      │ (%)            │
├────────────────┼────────────────┼────────────────┤
│ [X]ms /        │ [X]ms /        │ [X]%           │
│ [X]ms /        │ [X]ms          │ [Alert if >1%] │
│ [X]ms          │                │                │
└────────────────┴────────────────┴────────────────┘

┌─────────────────────────────────────────────────────┐
│ REQUEST RATE (Requests/sec)                         │
├─────────────────────────────────────────────────────┤
│                                    ▄▄▄▄▄            │
│  Requests                    ▄▄▄▄▄▀           ▀▄▄   │
│  (per sec)  ▄▄▄▄▀▀▀▀▀▀▀▄▄▄▄▀                      │
│  Expected: [X] req/sec during load test              │
└─────────────────────────────────────────────────────┘

┌──────────────────────────┬──────────────────────────┐
│ STATUS CODE DISTRIBUTION │ ERROR TYPES (Last Hour)  │
├──────────────────────────┼──────────────────────────┤
│ 200 (Success): [X]%      │ 500 Errors: [X]          │
│ 301 (Redirect): [X]%     │ 404 Not Found: [X]       │
│ 400 (Client Error): [X]% │ Timeout: [X]             │
│ 500 (Server Error): [X]% │ Connection Refused: [X]  │
└──────────────────────────┴──────────────────────────┘
```

### Dashboard 4: Services Status

**URL:** `http://192.168.168.31:3000/d/services-status`  
**Refresh Rate:** 15 seconds

**Required Panels:**

```
CRITICAL SERVICES STATUS (Traffic Light Indicators):

PRIMARY NODE:
┌─────────────┬─────────────┬─────────────┬─────────────┐
│ GitLab      │ PostgreSQL  │ Redis       │ Nginx       │
│ Unicorn     │ (Primary)   │ (Master)    │ (Web)       │
├─────────────┼─────────────┼─────────────┼─────────────┤
│ ● UP        │ ● UP        │ ● UP        │ ● UP        │
│ 87 running  │ Accepting   │ PING OK     │ 443/80      │
│ Healthy     │ connections │ 6379 ready  │ Ready       │
└─────────────┴─────────────┴─────────────┴─────────────┘

REPLICA NODE:
┌─────────────┬─────────────┬─────────────┬─────────────┐
│ GitLab      │ PostgreSQL  │ Redis       │ Nginx       │
│ Unicorn     │ (Replica)   │ (Slave)     │ (Web)       │
├─────────────┼─────────────┼─────────────┼─────────────┤
│ ● UP        │ ● UP        │ ● UP        │ ● UP        │
│ 88 running  │ In recovery │ Synced      │ Ready       │
│ Healthy     │ Replicating │ 6379 OK     │ Ready       │
└─────────────┴─────────────┴─────────────┴─────────────┘

HA COMPONENTS:
┌──────────────┬──────────────┬──────────────┐
│ Keepalived   │ Virtual IP   │ Failover     │
│ PRIMARY      │ (192.168.168 │ Tested: ✓    │
├──────────────┼──────────────┼──────────────┤
│ ● MASTER     │ .50 ● UP     │ 8/8 passed   │
│ Running      │ Responding   │ Ready        │
└──────────────┴──────────────┴──────────────┘
```

---

## 🔔 PROMETHEUS ALERTS SETUP

### Alert 1: Primary Node Down

```yaml
alert: PRIMARY_NODE_DOWN
expr: up{job="primary-node"} == 0
for: 1m
labels:
  severity: CRITICAL
annotations:
  summary: "PRIMARY Node (192.168.168.31) is DOWN"
  description: "PRIMARY has been unreachable for >1 minute"
  action: "Immediate investigation required - escalate to Infrastructure Lead"
```

### Alert 2: Replication Lag Exceeded

```yaml
alert: REPLICATION_LAG_HIGH
expr: pg_replication_lag_seconds > 30
for: 2m
labels:
  severity: HIGH
annotations:
  summary: "PostgreSQL Replication Lag: {{ $value }}s (>30s)"
  description: "REPLICA is lagging behind PRIMARY by >30 seconds"
  action: "Check REPLICA CPU/disk, or check PRIMARY write load"
```

### Alert 3: Replication Connection Lost

```yaml
alert: REPLICATION_DISCONNECTED
expr: pg_stat_replication_count == 0
for: 1m
labels:
  severity: CRITICAL
annotations:
  summary: "PostgreSQL Replication Connection Lost"
  description: "PRIMARY has no connected replicas"
  action: "CRITICAL - Restart PostgreSQL on REPLICA immediately"
```

### Alert 4: Containers Exited Unexpectedly

```yaml
alert: CONTAINERS_EXITED
expr: increase(container_exit_count[5m]) > 0
for: 1m
labels:
  severity: HIGH
annotations:
  summary: "Container exited: {{ $labels.container_name }}"
  description: "{{ $value }} containers exited in last 5 minutes"
  action: "Check container logs and restart if needed"
```

### Alert 5: High CPU Usage

```yaml
alert: HIGH_CPU_USAGE
expr: rate(container_cpu_usage_seconds_total[5m]) * 100 > 80
for: 5m
labels:
  severity: MEDIUM
annotations:
  summary: "High CPU on {{ $labels.host }}: {{ $value }}%"
  description: "CPU usage has exceeded 80% for >5 minutes"
  action: "Monitor for process causing high CPU, optimize if needed"
```

### Alert 6: High Memory Usage

```yaml
alert: HIGH_MEMORY_USAGE
expr: (container_memory_usage_bytes / 1024 / 1024 / 1024) / (node_memory_MemTotal_bytes / 1024 / 1024 / 1024) * 100 > 85
for: 5m
labels:
  severity: MEDIUM
annotations:
  summary: "High Memory on {{ $labels.host }}: {{ $value }}%"
  description: "Memory usage has exceeded 85% for >5 minutes"
  action: "Check for memory leaks, increase allocations or reduce workload"
```

---

## 📋 MANUAL MONITORING CHECKLIST

**Execute Every Hour During Active Deployment (May 1-12, May 15-21)**

### Hourly Health Check (5 minutes)

```bash
# Copy this into terminal and run hourly
#!/bin/bash
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S UTC")
echo "=== HEALTH CHECK $TIMESTAMP ==="

# Container counts
PRIMARY_COUNT=$(ssh ubuntu@192.168.168.31 "docker ps | wc -l" 2>/dev/null)
REPLICA_COUNT=$(ssh ubuntu@192.168.168.42 "docker ps | wc -l" 2>/dev/null)
echo "Containers: PRIMARY=$PRIMARY_COUNT (expect 87+), REPLICA=$REPLICA_COUNT (expect 88)"

# Replication lag
LAG=$(ssh ubuntu@192.168.168.31 "docker exec gitlab_db psql -U postgres -c 'SELECT EXTRACT(EPOCH FROM (now() - pg_last_wal_receive_lsn_time())) as lag_sec;' 2>/dev/null" | head -1)
echo "Replication Lag: ${LAG}s (expect <5s)"

# VIP ping
VIP_STATUS=$(ping -c 1 192.168.168.50 2>&1 | grep -c "1 received")
if [ "$VIP_STATUS" -eq 1 ]; then
  echo "VIP (192.168.168.50): RESPONDING ✓"
else
  echo "VIP (192.168.168.50): NOT RESPONDING ✗"
fi

# Prometheus targets
TARGETS=$(curl -s http://192.168.168.31:9090/api/v1/targets | jq '.data.activeTargets | length' 2>/dev/null)
echo "Prometheus Targets: $TARGETS active (expect 8+)"

echo "=== END CHECK ==="
```

**Run Hourly Output Log:**

```
=== HEALTH CHECK 2026-05-01 05:00:00 UTC ===
Containers: PRIMARY=87 (expect 87+), REPLICA=88 (expect 88) ✓
Replication Lag: 2s (expect <5s) ✓
VIP (192.168.168.50): RESPONDING ✓
Prometheus Targets: 8 active (expect 8+) ✓
=== END CHECK ===
```

---

## 📱 ALERT ROUTING SETUP

### AlertManager Notification Channels

**Configure Before May 1, 04:00 UTC:**

```yaml
# Slack Channel: #phase2b-deployment
- channel: "#phase2b-deployment"
  receivers:
    - operations-alerts
  matchers:
    - severity: CRITICAL
    - severity: HIGH
  repeat_interval: 5m

# PagerDuty (if available)
- service_key: "[SERVICE_KEY]"
  receivers:
    - pagerduty-alerts
  matchers:
    - severity: CRITICAL
  repeat_interval: 1m

# Email: on-call@operations.com
- to: "operations-lead@company.com,cto@company.com"
  receivers:
    - email-alerts
  matchers:
    - severity: CRITICAL
  repeat_interval: 15m
```

---

## 📊 LIVE MONITORING STATION SETUP (War Room)

### Monitor 1: Main Dashboard (60-inch screen)
**Display:** PHASE_2B_REAL_TIME_STATUS (custom dashboard)
- Cluster Health (large)
- Database Replication (large)
- Service Status (large)
- Deployment Phase Progress

### Monitor 2: Application Performance
**Display:** Application Performance Dashboard
- API Response Times
- Error Rates
- Request Rates
- Status Code Distribution

### Monitor 3: System Resources
**Display:** Node Metrics
- PRIMARY CPU/Memory/Disk
- REPLICA CPU/Memory/Disk
- Network throughput
- Alert status

### Monitor 4: Real-Time Log Aggregation
**Display:** Log Analysis
- Recent errors (last 50 lines)
- Warnings (last 50 lines)
- Critical events (highlighted)
- Live tail of /var/log/deployment.log

---

## 🎬 DEPLOYMENT PHASE TRACKING DISPLAY

**Update in Real-Time on Grafana Dashboard**

```
WEEK 1 DEPLOYMENT PROGRESS (May 1-12)

PHASE 1: Infrastructure Preparation ✅ COMPLETE (May 1, 00:00-04:00)
├─ Docker health checks: ✓
├─ Database preparation: ✓
└─ VIP verification: ✓

PHASE 2: GitHub PR Process 🔄 IN PROGRESS (May 1, 04:00 - May 4, 23:59)
├─ Branch creation: [████░░░░░░░░░░░░] 20% (May 1)
├─ PR creation: [░░░░░░░░░░░░░░░░░░] 0% (May 2)
├─ Approvals: [░░░░░░░░░░░░░░░░░░] 0% (May 3)
└─ Merge: [░░░░░░░░░░░░░░░░░░] 0% (May 4)

PHASE 3: Docker Build ⏳ PENDING (May 5, 00:00 - May 5, 12:00)
├─ Build trigger: [░░░░░░░░░░░░░░░░░░] 0%
├─ Build execution: [░░░░░░░░░░░░░░░░░░] 0%
└─ Push to registry: [░░░░░░░░░░░░░░░░░░] 0%

... (continue for all 8 phases)

MILESTONE CHECKPOINTS:
[ ] May 1, 05:05 UTC: Pre-flight verification PASSED
[ ] May 12, 23:59 UTC: Week 1 all phases COMPLETE
[ ] May 14, 23:59 UTC: Production sign-offs obtained
[ ] May 21, 72h later: Deployment SUCCESSFUL
```

---

## 🚨 ANOMALY DETECTION RULES

**Monitoring Lead: Watch for these patterns and escalate if observed:**

| Metric | Normal Range | Warning | Critical | Action |
|--------|---|---|---|---|
| Replication Lag | <5s | 10-30s | >30s | Check REPLICA, escalate if >60s |
| CPU PRIMARY | <40% | 60-80% | >80% | Monitor, optimize if sustained |
| CPU REPLICA | <40% | 60-80% | >80% | Monitor, reduce workload if needed |
| Memory PRIMARY | <70% | 80-90% | >90% | Escalate immediately |
| Memory REPLICA | <70% | 80-90% | >90% | Escalate immediately |
| Disk Usage | <60% | 75-80% | >85% | Escalate to Infrastructure |
| Error Rate | <0.1% | 0.5-1% | >1% | Investigate root cause |
| API Response (p99) | <200ms | 500-1000ms | >1000ms | Investigate and optimize |
| Exited Containers | 0 | 1-2 | >2 | Restart containers, investigate |
| VIP Responsiveness | 100% | 95-99% | <95% | Check Keepalived, escalate |

---

## ✅ PRE-GO-LIVE MONITORING CHECKLIST (May 1, 04:30 UTC)

- [ ] All Grafana dashboards loaded and visible
- [ ] Prometheus targets all reporting (8+)
- [ ] AlertManager channels tested (Slack/Email/PagerDuty)
- [ ] All alert rules configured and active
- [ ] War room monitors powered on and displaying dashboards
- [ ] Log aggregation system running
- [ ] Hourly health check script ready to run
- [ ] Communication templates ready to send
- [ ] Incident escalation contacts confirmed by phone
- [ ] All team leads can access all monitoring systems
- [ ] Dashboard refresh rates set correctly (15-30s)
- [ ] Baseline metrics recorded for comparison

**Monitoring Lead Sign-Off:** ________________________ **Time:** ________

All systems ready for live monitoring. Deployment may proceed.

