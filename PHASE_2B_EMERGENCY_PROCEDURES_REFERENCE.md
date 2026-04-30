# PHASE 2B EMERGENCY PROCEDURES QUICK REFERENCE
## Laminated War Room Reference Card

**Print & Laminate:** Post on war room wall for instant access  
**Update Before May 1:** Fill in all contact information & IP addresses  
**Laminate With:** Clear plastic sheets (both sides)  

---

## 🚨 CRITICAL CONTACTS (Keep Posted in War Room)

```
╔════════════════════════════════════════════════════════════════════╗
║              EMERGENCY ESCALATION CONTACTS - MAY 2026              ║
╚════════════════════════════════════════════════════════════════════╝

LEVEL 1 - IMMEDIATE RESPONSE (< 5 minutes)
┌────────────────────────────────────────────────────────────────────┐
│ Operations Lead                      │ [NAME]                      │
│ Phone: [XXX-XXX-XXXX]               │ Slack: @[name]              │
│ Location: War room physical seat [#] │ Backup: [BACKUP NAME]      │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ Infrastructure Lead                  │ [NAME]                      │
│ Phone: [XXX-XXX-XXXX]               │ Slack: @[name]              │
│ SSH Key: [Key type]                  │ Backup: [BACKUP NAME]      │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ On-Call Engineer                     │ [NAME]                      │
│ Phone: [XXX-XXX-XXXX]               │ Slack: @[on-call]           │
│ Pager: [NUMBER]                      │ SMS: [NUMBER]              │
└────────────────────────────────────────────────────────────────────┘

LEVEL 2 - URGENT ESCALATION (< 15 minutes)
┌────────────────────────────────────────────────────────────────────┐
│ CTO / Technical Lead                 │ [NAME]                      │
│ Phone: [XXX-XXX-XXXX]               │ Slack: @[cto]              │
│ Email: [EMAIL]                       │ Available: 24/7 during dep  │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ VP Operations                        │ [NAME]                      │
│ Phone: [XXX-XXX-XXXX]               │ Email: [EMAIL]              │
│ Availability: Business hours + on-call │ Backup: [BACKUP]        │
└────────────────────────────────────────────────────────────────────┘

LEVEL 3 - CRITICAL ESCALATION (< 30 minutes)
┌────────────────────────────────────────────────────────────────────┐
│ Executive Sponsor                    │ [NAME]                      │
│ Phone: [XXX-XXX-XXXX]               │ Email: [EMAIL]              │
│ Escalation Authorization Level: 5/5  │ Final GO/NO-GO Authority   │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ General Counsel (if data loss risk)  │ [NAME]                      │
│ Phone: [XXX-XXX-XXXX]               │ Email: [EMAIL]              │
│ Legal escalation threshold: Data loss detected │ Call immediately  │
└────────────────────────────────────────────────────────────────────┘

EXTERNAL VENDOR SUPPORT (24/7)
┌────────────────────────────────────────────────────────────────────┐
│ AWS Support                          │ Case Manager: [NAME]        │
│ Case Manager Phone: [NUMBER]        │ Portal: [URL]              │
│ SLA: Critical <1 hour                │ Account: [ACCOUNT ID]      │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ GitLab Support                       │ Priority: [Silver/Gold/Plat]│
│ Phone: [NUMBER]                      │ Portal: [URL]              │
│ Support Email: [EMAIL]               │ License: [NUMBER]          │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ Network Provider 24/7 Support        │ Account: [NUMBER]          │
│ Phone: [XXX-XXX-XXXX]               │ Portal: [URL]              │
│ SLA: Critical <30 min                │ BGP Contact: [NAME/PHONE]  │
└────────────────────────────────────────────────────────────────────┘
```

---

## 🔧 INFRASTRUCTURE QUICK ACCESS

```
╔════════════════════════════════════════════════════════════════════╗
║              INFRASTRUCTURE ACCESS REFERENCE                       ║
╚════════════════════════════════════════════════════════════════════╝

PRIMARY NODE (192.168.168.31)
├─ SSH: ssh ubuntu@192.168.168.31
├─ Docker: docker ps
├─ Logs: docker logs [container_name]
├─ Replication Status: docker exec gitlab_db psql -U postgres -c \
│  "SELECT slot_name FROM pg_replication_slots;"
└─ Disk Space: ssh ubuntu@192.168.168.31 "df -h /"

REPLICA NODE (192.168.168.42)
├─ SSH: ssh ubuntu@192.168.168.42
├─ Docker: docker ps
├─ Replication Lag: docker exec gitlab_db psql -U postgres -c \
│  "SELECT EXTRACT(EPOCH FROM (now() - \
│  pg_last_wal_receive_lsn_time()));"
└─ Disk Space: ssh ubuntu@192.168.168.42 "df -h /"

VIRTUAL IP (HA VIP - 192.168.168.50)
├─ Ping Test: ping -c 1 192.168.168.50
├─ Health Check: curl http://192.168.168.50:8080/health
├─ Active Node: Should respond from 192.168.168.31 (PRIMARY)
└─ Failover: If PRIMARY down, REPLICA takes VIP

MONITORING & DASHBOARDS
├─ Grafana: http://192.168.168.31:3000
├─ Prometheus: http://192.168.168.31:9090
├─ AlertManager: http://192.168.168.31:9093
└─ Cluster Health Dashboard: /d/cluster-health
```

---

## 🎯 COMMON ISSUES & 5-MINUTE FIXES

```
╔════════════════════════════════════════════════════════════════════╗
║           RAPID TROUBLESHOOTING (5-MINUTE MAXIMUM)                ║
╚════════════════════════════════════════════════════════════════════╝

ISSUE #1: Container Exited Unexpectedly
┌────────────────────────────────────────────────────────────────────┐
│ SYMPTOM: docker ps shows container not in list
│
│ QUICK FIX (Select one):
│ 1. Restart: docker-compose restart [service_name]
│ 2. Check logs: docker logs [container_name]
│ 3. If corrupted: docker-compose up -d [service_name]
│
│ WITHIN 5 MIN?
│ ✓ YES → Confirm restoration, log event, continue operations
│ ✗ NO → Escalate to Infrastructure Lead
└────────────────────────────────────────────────────────────────────┘

ISSUE #2: Replication Lag >30 Seconds
┌────────────────────────────────────────────────────────────────────┐
│ SYMPTOM: Grafana shows replication_lag_seconds > 30
│
│ QUICK FIX:
│ 1. Check REPLICA CPU: docker stats (look for high CPU)
│ 2. Check REPLICA disk I/O: iostat (if available)
│ 3. Monitor for 2 minutes - should recover
│ 4. If persists: Check PRIMARY write load (might be normal load)
│
│ WITHIN 5 MIN?
│ ✓ Trending back down → Normal, monitor
│ ✗ Still >30s → Escalate to CTO + Infrastructure
└────────────────────────────────────────────────────────────────────┘

ISSUE #3: VIP (192.168.168.50) Not Responding
┌────────────────────────────────────────────────────────────────────┐
│ SYMPTOM: ping 192.168.168.50 returns "no response"
│
│ QUICK FIX:
│ 1. SSH PRIMARY: ssh ubuntu@192.168.168.31
│ 2. Restart keepalived: sudo systemctl restart keepalived
│ 3. Wait 10 seconds
│ 4. Test: ping -c 1 192.168.168.50 (should respond from PRIMARY)
│
│ WITHIN 5 MIN?
│ ✓ YES → Confirm working, log event, continue
│ ✗ NO → Check PRIMARY keepalived: sudo systemctl status keepalived
│         Escalate to CTO
└────────────────────────────────────────────────────────────────────┘

ISSUE #4: High CPU Usage (>80%)
┌────────────────────────────────────────────────────────────────────┐
│ SYMPTOM: Grafana shows CPU >80% on PRIMARY or REPLICA
│
│ QUICK FIX:
│ 1. Identify hot container: docker stats (look for highest CPU)
│ 2. If postgresql: Normal during indexing/backup - monitor
│ 3. If redis: Check for large operations - monitor
│ 4. If other: Check docker logs for errors
│ 5. Monitor for 2 minutes - should return to normal
│
│ WITHIN 5 MIN?
│ ✓ Returns to normal → Log as normal operation spike, continue
│ ✗ Sustained >80% → Escalate to Infrastructure Lead
└────────────────────────────────────────────────────────────────────┘

ISSUE #5: High Memory Usage (>85%)
┌────────────────────────────────────────────────────────────────────┐
│ SYMPTOM: Grafana shows memory >85%
│
│ QUICK FIX:
│ 1. Check container memory: free -h (from node)
│ 2. If postgresql using >30GB: May be normal (cache)
│ 3. Monitor for memory pressure (swap usage)
│ 4. If swap usage >10%: Escalate immediately
│
│ WITHIN 5 MIN?
│ ✓ Swap usage <5% → Normal caching, no action needed
│ ✗ Swap usage >10% → CRITICAL, escalate immediately to CTO
└────────────────────────────────────────────────────────────────────┘

ISSUE #6: Error Rate Spiked (>1%)
┌────────────────────────────────────────────────────────────────────┐
│ SYMPTOM: Grafana shows error_rate > 1%
│
│ QUICK FIX:
│ 1. Check app logs: docker logs gitlab_web (last 20 lines)
│ 2. Look for pattern: All same error? OR Multiple different?
│ 3. If timeout errors: Network/response time issue
│ 4. If 500 errors: Application issue
│ 5. If connection refused: Service down
│
│ Root cause identified?
│ ✓ YES → Fix specific issue (container restart, etc)
│ ✗ NO → Escalate to QA Lead for investigation
└────────────────────────────────────────────────────────────────────┘

ISSUE #7: No Response from Web Interface
┌────────────────────────────────────────────────────────────────────┐
│ SYMPTOM: curl http://192.168.168.31 → Connection refused or timeout
│
│ QUICK FIX:
│ 1. Check nginx: docker ps | grep nginx (should show UP)
│ 2. If not UP: docker-compose restart nginx
│ 3. Test again: curl -v http://192.168.168.31
│ 4. If still fails: Check web app container: docker ps | grep web
│ 5. Restart web: docker-compose restart gitlab_web
│
│ WITHIN 5 MIN?
│ ✓ YES → Confirmed working, log event
│ ✗ NO → Multiple services down, escalate to Infrastructure Lead
└────────────────────────────────────────────────────────────────────┘

ANY OTHER ISSUE NOT LISTED:
1. Document in incident log immediately
2. Assess severity (see severity table below)
3. Attempt 1 fix (if safe)
4. If resolved: Continue with monitoring
5. If not resolved: Escalate to appropriate lead
```

---

## 📊 SEVERITY LEVELS & ESCALATION TRIGGERS

```
╔════════════════════════════════════════════════════════════════════╗
║              ISSUE SEVERITY & WHEN TO ESCALATE                     ║
╚════════════════════════════════════════════════════════════════════╝

🔴 CRITICAL SEVERITY (IMMEDIATE ESCALATION TO CTO)
├─ PRIMARY node unreachable (no SSH, ping fails)
├─ Both PRIMARY and REPLICA affected
├─ Replication completely broken (lag >5 minutes)
├─ Multiple critical services DOWN (DB + Web + Redis)
├─ Data loss risk detected
├─ Memory >90% or Swap >25%
├─ VIP failover triggered unexpectedly
└─ ANY firewall/network connectivity complete loss
    → Escalation: Call CTO immediately
    → Action: Hold deployment OR activate contingency

🟠 HIGH SEVERITY (ESCALATE WITHIN 15 MINUTES)
├─ Single critical service DOWN (fixable in <5 min)
├─ Replication lag 30-60 seconds
├─ CPU >85% sustained for 2+ minutes
├─ Memory >85% with swap usage
├─ API response time >1000ms
├─ Error rate 1-5%
├─ One node partially degraded (some containers down)
└─ Non-critical service exited
    → Escalation: Notify Infrastructure Lead
    → Action: Investigate, fix, or accept risk

🟡 MEDIUM SEVERITY (MONITOR & INVESTIGATE)
├─ Single non-critical service error
├─ Replication lag 10-30 seconds
├─ CPU 70-85% (temporary spike)
├─ Memory 70-85% (acceptable cache pressure)
├─ Error rate <1%
├─ API response time 200-1000ms
├─ Dashboard not updating (monitoring-only issue)
└─ Minor alert firing
    → Escalation: Log event, monitor
    → Action: Continue operations, investigate when possible

🟢 LOW SEVERITY (LOG & CONTINUE)
├─ Metric threshold alert (non-critical)
├─ Dashboard flicker/refresh issue
├─ Non-critical log error
├─ Warning messages in logs
└─ Information event
    → Escalation: Log only
    → Action: Continue operations normally
```

---

## ☎️ PHONE TREE - WHO TO CALL WHEN

```
╔════════════════════════════════════════════════════════════════════╗
║                   PHONE ESCALATION TREE                            ║
╚════════════════════════════════════════════════════════════════════╝

STEP 1: What's the issue?
│
├─ Infrastructure/System down?
│  └─ CALL: Infrastructure Lead [XXX-XXX-XXXX]
│     └─ If no answer in 2 min: CALL: On-Call Engineer [XXX-XXX-XXXX]
│        └─ If no answer: CALL: CTO [XXX-XXX-XXXX]
│
├─ Application/Web not responding?
│  └─ CALL: Operations Lead [XXX-XXX-XXXX]
│     └─ If no answer in 2 min: CALL: On-Call Engineer
│        └─ If no answer: CALL: CTO
│
├─ Database/Replication issue?
│  └─ CALL: Infrastructure Lead [XXX-XXX-XXXX]
│     └─ If no answer: CALL: CTO
│
├─ Monitoring/Alerting issue?
│  └─ CALL: Operations Lead [XXX-XXX-XXXX]
│     └─ If no answer: CALL: Infrastructure Lead
│
├─ Multiple systems down / Complete outage?
│  └─ CALL: CTO immediately [XXX-XXX-XXXX]
│     └─ ALSO: Notify VP Operations [XXX-XXX-XXXX]
│     └─ ALSO: Notify Executive Sponsor [XXX-XXX-XXXX]
│
└─ Data loss detected?
   └─ CALL: CTO immediately [XXX-XXX-XXXX]
   └─ CALL: General Counsel [XXX-XXX-XXXX]
   └─ DO NOT: Make any restoration attempts
      └─ Wait for legal guidance
```

---

## ⏱️ CRITICAL TIME WINDOWS

```
╔════════════════════════════════════════════════════════════════════╗
║              DECISION WINDOWS & TIMING GATES                       ║
╚════════════════════════════════════════════════════════════════════╝

DEPLOYMENT TIMELINE (DO NOT MISS THESE TIMES):

04:00 UTC - Pre-Flight Begins
  └─ If FAIL by 04:50 UTC → Cannot make 05:00 go-live
  └─ Escalate to CTO for delay decision

05:00 UTC - GO-LIVE DECISION POINT (FINAL)
  └─ All systems must be GREEN by 05:00 UTC
  └─ CTO makes final GO/NO-GO decision at 05:00 UTC
  └─ No changes after 05:05 UTC (execution begins)

05:15 UTC - QA Begins Testing
  └─ If QA cannot start → escalate immediately
  └─ No delays acceptable at this point

06:00 UTC - End of Critical Window
  └─ All systems must be operational
  └─ If issues persist → activate contingency

HOLD DECISION:
If not ready by 05:00 UTC:
  → CTO decides: Fix and delay OR Proceed with contingencies
  → If delay: New go-live time announced immediately
  → All teams notified via Slack + Phone
```

---

## 🆘 IMMEDIATE ACTION CHECKLIST

**PRINT & HAVE READY ON DESK:**

```
SOMETHING IS DOWN / BROKEN - WHAT DO I DO RIGHT NOW?

□ Step 1: STAY CALM (deep breath)
□ Step 2: Identify issue (what broke?)
□ Step 3: Assess severity (use severity table above)
□ Step 4: Open incident log: PHASE_2B_DEPLOYMENT_INCIDENT_EVENT_LOG.md
□ Step 5: Record issue with exact time
□ Step 6: Consult "Common Issues & 5-Minute Fixes" above
□ Step 7: Attempt fix if safe (do NOT make it worse)
□ Step 8: Fixed in <5 min? 
    ✓ YES → Continue operations, log resolution
    ✗ NO → Escalate immediately (call appropriate lead)
□ Step 9: Call appropriate person from PHONE TREE above
□ Step 10: Provide: Issue description + severity + attempted fixes
□ Step 11: LISTEN to escalation guidance
□ Step 12: Execute escalation instructions
□ Step 13: Document outcome in incident log

REMEMBER:
- Time is critical (every minute counts)
- Escalate early if uncertain
- Don't waste time on unfixable issues
- CTO has final authority on go-live decisions
- Communicate status to war room every 5 minutes
```

---

## 🚀 DEPLOYMENT DAY MORNING CHECKLIST

**CHECK BEFORE 04:00 UTC - DO NOT FORGET:**

```
FINAL PRE-GO-LIVE CHECKLIST (Print & Bring to War Room):

□ This laminated card in your pocket
□ Phone fully charged (100%)
□ Laptop fully charged (100%)
□ Coffee/water (hydration for 8-hour shift)
□ Notebook + pen (for notes)
□ SSH key / credentials ready
□ Contact list from team (all numbers saved in phone)
□ Quick reference cards (one per team member)
□ Incident log printed (first few pages)
□ All 4 Grafana dashboards bookmarked
□ War room access verified (key card, building access)
□ Video conferencing tested (camera + mic work)
□ Slack mobile app installed & notifications ON
□ Email checked (any last-minute messages)
□ Sleep well (7+ hours) - CRITICAL
□ Arrive early (by 03:45 UTC) - MANDATORY
```

---

**LAMINATE THIS CARD**  
**POST ON WAR ROOM WALL**  
**KEEP COPY ON EACH TEAM MEMBER'S DESK**

**This is your lifeline during deployment.**  
**Refer to this card first before escalating.**

