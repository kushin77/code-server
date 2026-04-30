# PHASE 2B PHASE 1 INCIDENT RESPONSE PLAYBOOK
## Rapid Response Procedures for Critical Issues (April 30 - May 4, 2026)

**Owner:** Operations Lead + Infrastructure Lead  
**Activation:** 24/7 during Phase 1 (April 30 - May 4)  
**Response Times:** CRITICAL <2min, HIGH <5min, MEDIUM <15min  
**Escalation:** Immediate to CTO for CRITICAL incidents  

---

## 🚨 INCIDENT SEVERITY MATRIX

### CRITICAL (Response <2 minutes, Escalate to CTO immediately)

```
INCIDENT: Container count drops below 85 on PRIMARY
└─ SEVERITY: CRITICAL - Deployment viability threatened

TRIGGER:
├─ Monitoring alert: Container count <85
├─ Alert rule: Activated automatically
└─ Notification: Slack + SMS + Phone

IMMEDIATE RESPONSE (First 30 seconds):
1. Monitoring Lead: PHONE CALL to Operations Lead
2. Operations Lead: Assess severity
3. Message Slack: "[CRITICAL] Container count LOW - investigating"
4. Infrastructure Lead: Be ready to respond

INVESTIGATION (Next 60 seconds):
1. Check: Which containers are down? (List them)
2. Check: Are they restarting or permanently down?
3. Check: Any errors in deployment?
4. Check: Network connectivity to those containers?
5. Decision: Can we restart them? Or is it a deployment issue?

REMEDIATION (Within 2 minutes):
Option A - If transient restart issue:
  └─ Execute: Manual container restart procedure
    ├─ SSH to PRIMARY node
    ├─ Identify stopped containers
    ├─ Restart: docker-compose up -d [container]
    └─ Verify: Container comes up and stays running

Option B - If deployment issue:
  └─ Execute: Deployment rollback or fix
    ├─ Escalate to CTO immediately
    ├─ Prepare rollback procedures
    ├─ Get approval from CTO for rollback
    └─ Execute rollback if approved

ESCALATION (Immediate):
├─ Phone: CTO immediately
├─ Message: "[CRITICAL] Containers down - [Investigating/Fixed/Escalating]"
├─ Status: Update every 30 seconds
└─ Escalate to Executive Sponsor if not resolved in 5 minutes

RESOLUTION CRITERIA:
├─ Container count restored to 87/87: ✓
├─ All services: Green status: ✓
├─ System: Stable for 1 minute: ✓
├─ CTO: Confirmed acceptable: ✓
└─ Log: Full incident record created: ✓

EVENT LOG ENTRY:
[HH:MM] CRITICAL_ALERT Container count dropped to XX
[HH:MM] INCIDENT_START Investigation began
[HH:MM] INCIDENT_CAUSE [Root cause identified]
[HH:MM] REMEDIATION [Action taken]
[HH:MM] INCIDENT_RESOLVED Container count restored to 87/87
```

### CRITICAL (Response <2 minutes): Database Replication Lag >10 seconds

```
INCIDENT: Database replication lag exceeds 10 seconds
└─ SEVERITY: CRITICAL - Data synchronization threatened

TRIGGER:
├─ Monitoring alert: Replication lag >10s
├─ Alert rule: Activated automatically
└─ Notification: Slack + Phone call

IMMEDIATE RESPONSE (First 30 seconds):
1. Monitoring Lead: PHONE CALL to Operations Lead
2. Operations Lead: Check database status
3. Message Slack: "[CRITICAL] DB replication lag HIGH - investigating"
4. Infrastructure Lead: Be ready

INVESTIGATION (Next 60 seconds):
1. Check database dashboard: Replication status
2. Check lag trend: Is it increasing or stable?
3. Check REPLICA node: Is it responsive?
4. Check network latency: PRIMARY ↔ REPLICA
5. Decision: Is it temporary network issue or database problem?

REMEDIATION:
Option A - If temporary network glitch:
  └─ Monitor lag decrease (should resume <5s)
    ├─ Time: 30-60 seconds to recover
    ├─ Decision: If not recovering, escalate
    └─ Continue: Normal operations if recovered

Option B - If persistent lag issue:
  └─ Escalate immediately
    ├─ Phone: Infrastructure Lead + CTO
    ├─ Decision: May need database intervention
    ├─ Possible actions: Restart replication, check disk I/O
    └─ Follow: Infrastructure Lead guidance

ESCALATION (Immediate if not recovered in 60 seconds):
├─ Phone: CTO immediately
├─ Message: "[CRITICAL] DB replication lag [current value] - escalating"
└─ Prepare: Database recovery procedures

RESOLUTION CRITERIA:
├─ Replication lag: <5 seconds: ✓
├─ System: Stable for 2 minutes: ✓
└─ CTO: Confirmed acceptable: ✓
```

### CRITICAL (Response <2 minutes): Virtual IP Unresponsive

```
INCIDENT: Virtual IP (192.168.168.50) not responding to health checks
└─ SEVERITY: CRITICAL - Failover capability threatened

TRIGGER:
├─ Monitoring alert: VIP health check failed
├─ Alert rule: Activated automatically
└─ Notification: Slack + Phone call

IMMEDIATE RESPONSE (First 30 seconds):
1. Monitoring Lead: PHONE CALL to Operations Lead
2. Operations Lead: Verify VIP status
3. Message Slack: "[CRITICAL] VIP unresponsive - investigating"
4. Test: Manual VIP connectivity test

INVESTIGATION (Next 60 seconds):
1. Test: Can we ping VIP? (192.168.168.50)
2. Test: Can we reach web interface through VIP?
3. Check: Keepalived status on PRIMARY
4. Check: DNS resolution (does it resolve correctly?)
5. Decision: Is Keepalived down? Is PRIMARY unreachable?

REMEDIATION:
Option A - If Keepalived process crashed:
  └─ SSH to PRIMARY node
    ├─ Check: systemctl status keepalived
    ├─ Restart: systemctl restart keepalived
    ├─ Wait: 10 seconds for VIP to respond
    ├─ Test: Ping VIP - should respond
    └─ Verify: VIP responding to health checks

Option B - If PRIMARY node unreachable:
  └─ Escalate immediately
    ├─ Phone: Infrastructure Lead + CTO
    ├─ Decision: May need PRIMARY node recovery or failover
    ├─ Prepare: HA failover procedures
    └─ Follow: Infrastructure Lead guidance

ESCALATION (Immediate):
├─ Phone: CTO immediately
├─ Message: "[CRITICAL] VIP unresponsive - [Investigating/Fixed/Escalating]"
└─ Status: Update every 30 seconds

RESOLUTION CRITERIA:
├─ VIP: Responding to ping: ✓
├─ Web interface: Accessible through VIP: ✓
├─ Health checks: Passing: ✓
└─ CTO: Confirmed acceptable: ✓
```

---

## 🔴 HIGH SEVERITY INCIDENTS (Response <5 minutes)

```
HIGH SEVERITY TRIGGERS:
├─ CPU utilization: Exceeds 95%
├─ Memory utilization: Exceeds 95%
├─ Disk space: Drops below 5GB
├─ Non-critical service: RED status
├─ Performance degradation: >25%
└─ Response time: API >500ms

RESPONSE PROCEDURE:
1. Monitoring Lead: Notifies Operations Lead (5 min SLA)
2. Operations Lead: Assess severity
3. Message Slack: "[HIGH] [Issue description]"
4. Monitor: Is it trending worse?
5. Decision: Can we remediate? Or escalate?
6. If escalating: Phone Infrastructure Lead
7. If resolving: Execute remediation
8. Log: Full incident record
```

---

## 🟡 MEDIUM SEVERITY INCIDENTS (Response <15 minutes)

```
MEDIUM SEVERITY TRIGGERS:
├─ Transient errors in logs
├─ Temporary latency spike
├─ Non-critical service alert
├─ Minor performance deviation (<15%)
└─ Single failed request (not sustained)

RESPONSE PROCEDURE:
1. Monitoring Lead: Logs alert
2. Operations Lead: Reviews in next hourly report
3. Monitor: Is issue persisting?
4. If YES after 15 minutes: Escalate to HIGH
5. If NO: Document and continue
6. Log: Track all medium alerts for pattern analysis
```

---

## 📋 INCIDENT LOG TEMPLATE

**Use this for every incident, regardless of severity:**

```
════════════════════════════════════════════════════════════════
INCIDENT LOG ENTRY - PHASE 1
════════════════════════════════════════════════════════════════

INCIDENT ID: P1-[DATE]-[SEQUENCE] (e.g., P1-0430-001)
REPORTED TIME: [HH:MM UTC] _________________
SEVERITY: [CRITICAL / HIGH / MEDIUM / LOW] _________________

INCIDENT DESCRIPTION:
[What happened?] _______________________________________________

DISCOVERY METHOD:
├─ Automated alert: [YES / NO]
├─ Alert type: [Monitoring dashboard / Email alert / Phone]
└─ Discovered by: [Team member name] _____________________

INITIAL ASSESSMENT (First 2 minutes):
├─ Impact scope: [Single container / Multiple / System-wide]
├─ Service affected: [Which services] _____________________
├─ User impact: [Describe] ________________________________
├─ Severity confirmed: [CRITICAL / HIGH / MEDIUM / LOW] _____
└─ Escalation required: [YES / NO] _____________________

ROOT CAUSE ANALYSIS:
├─ Initial hypothesis: [Theory] ____________________________
├─ Investigation findings: [Details] _____________________
├─ Root cause: [Identified cause] _______________________
└─ Contributing factors: [Any] ____________________________

REMEDIATION:
├─ Action 1: [Action taken] _______________________________
├─ Result: [Outcome] ____________________________________
├─ Action 2 (if needed): [Action] ________________________
├─ Result: [Outcome] ____________________________________
└─ Status: [RESOLVED / ESCALATED / UNRESOLVED] ___________

ESCALATION (if applicable):
├─ Escalated to: [CTO / Executive Sponsor / Security]
├─ Time escalated: [HH:MM UTC] _____________________
├─ Escalation reason: [Why escalated] _______________
└─ Escalation result: [Outcome] _____________________

IMPACT METRICS:
├─ Downtime: [XX minutes] ______________
├─ Services affected: [Count] ______________
├─ User impact: [Description] ____________________
├─ Data loss: [YES / NO] ______________
└─ Recovery time: [XX minutes] ______________

RESOLUTION:
├─ Time to resolution: [XX minutes] ______________
├─ Final status: [All systems GREEN / Degraded / Escalated]
├─ Confirmation: [By whom] _____________________
└─ CTO sign-off: [Time] _____________________

PREVENTIVE MEASURES:
├─ Immediate action: [To prevent recurrence] _____
├─ Configuration change: [If needed] ____________
├─ Monitoring enhancement: [If needed] __________
└─ Procedure update: [If needed] _______________

INCIDENT NOTES:
[Additional observations, lessons learned, team feedback]
______________________________________________________________

INCIDENT OWNER: __________________ DATE: ______________
```

---

## 🔧 COMMON REMEDIATION PROCEDURES

### Container Restart Procedure

```
WHEN TO USE: Container crashed but is still in system
EXPECTED TIME: <1 minute

STEPS:
1. SSH to PRIMARY node (192.168.168.31)
2. List containers: docker ps -a
3. Identify container: [container-name]
4. Restart: docker restart [container-name]
5. Verify: docker ps | grep [container-name]
6. Check: Is container running? (STATUS = "Up X seconds")
7. Confirm: Container logs look healthy? docker logs [container-name]
8. Resolution: Container healthy and responding
```

### Database Replication Recovery Procedure

```
WHEN TO USE: Replication lag stuck >10 seconds
EXPECTED TIME: 2-5 minutes

STEPS:
1. Check lag: SELECT now() - pg_last_wal_receive_lsn() AS replication_lag;
2. If lag persistent: Check disk I/O on REPLICA
3. Check: Is REPLICA network connectivity good?
4. Option A - Restart replication:
   └─ On REPLICA: pg_ctl restart
5. Option B - Full resync:
   └─ Contact Infrastructure Lead (escalate)
6. Monitor: Replication lag should drop to <5s within 60 seconds
7. Confirm: Lag <5 seconds for 2 minutes
8. Resolution: Replication synchronized
```

### Virtual IP (Keepalived) Recovery Procedure

```
WHEN TO USE: VIP not responding to health checks
EXPECTED TIME: <1 minute

STEPS:
1. SSH to PRIMARY node (192.168.168.31)
2. Check status: systemctl status keepalived
3. If not running: systemctl start keepalived
4. If running but not responding:
   └─ Restart: systemctl restart keepalived
5. Wait: 10 seconds for VIP to stabilize
6. Test: ping 192.168.168.50
7. Verify: Should respond with <5ms latency
8. Confirm: Health check passing
9. Resolution: VIP responding normally
```

---

## 📞 ESCALATION DECISION TREE

```
INCIDENT OCCURS
      ↓
  Assess severity
      ↓
  ┌─→ CRITICAL (<2 min response)
  │   ├─ Phone CTO immediately
  │   ├─ Attempt remediation while escalating
  │   ├─ Update status every 30 seconds
  │   └─ If not resolved in 5 min: Call Executive Sponsor
  │
  ├─→ HIGH (<5 min response)
  │   ├─ Notify Operations Lead
  │   ├─ Assess: Can we fix? Or escalate?
  │   ├─ If fixable: Execute remediation
  │   └─ If not: Call Infrastructure Lead
  │
  └─→ MEDIUM (<15 min response)
      ├─ Log in hourly report
      ├─ Monitor: Is it getting worse?
      ├─ If YES: Escalate to HIGH
      └─ If NO: Document and continue
```

---

## ✅ INCIDENT RESPONSE READINESS

```
EVERY TEAM MEMBER SHOULD KNOW:

[ ] Location of this playbook: [File path]
[ ] My role in incident response: [My responsibility]
[ ] CTO emergency contact: [Phone number]
[ ] Executive Sponsor contact: [Phone number]
[ ] Escalation decision criteria: [Understood]
[ ] How to log incidents: [Procedure understood]
[ ] Response time expectations: [CRITICAL <2min, HIGH <5min, MEDIUM <15min]
[ ] Communication protocol: [Slack + Phone for CRITICAL]
```

---

**PHASE 1 INCIDENT RESPONSE PLAYBOOK READY**

*Every incident can be resolved with these procedures.*

*Response times: CRITICAL <2 min, HIGH <5 min, MEDIUM <15 min*

*Escalation: Immediate to CTO for all CRITICAL incidents.*

✅ **READY FOR PHASE 1 DEPLOYMENT**

