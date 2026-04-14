# PHASE 13 DAY 2 - QUICK REFERENCE CARD
**Keep this open during the 24-hour test**

---

## 🚀 LAUNCH COMMANDS (April 14, 09:00 UTC)

```bash
# TERMINAL 1: Pre-flight (08:00 UTC) then launch (09:00 UTC)
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31
bash ~/code-server-phase13/scripts/phase-13-day2-preflight-final.sh  # 08:00 UTC
bash ~/code-server-phase13/scripts/phase-13-day2-orchestrator.sh    # 09:00 UTC

# TERMINAL 2: Real-time monitoring (during all 24 hours)
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31
tail -f /tmp/phase-13-monitoring.log

# TERMINAL 3: Health checks (run every 30 min)
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Size}}"
```

---

## 🎯 SLO TARGETS (Alarm If Exceeded)

| Metric | Target | Alarm | Normal |
|--------|--------|-------|--------|
| **p99 Latency** | <100ms | 🔴 if >100ms | 🟢 42-89ms |
| **Error Rate** | <0.1% | 🔴 if >0.1% | 🟢 0.0% |
| **Throughput** | >100 req/s | 🔴 if <100/s | 🟢 150+/s |
| **Availability** | >99.9% | 🔴 if <99.9% | 🟢 99.98% |

---

## 🚨 EMERGENCY RESPONSES

### Container Failure
```bash
ssh akushnir@192.168.168.31
docker restart <container-name>
docker ps  # Verify restart
```

### SLO Breach
1. Note time and metric
2. Check logs: `ssh akushnir@192.168.168.31 'docker logs code-server | tail -50'`
3. If recoverable in <30min, attempt fix
4. If unresolved after 30min: FAIL decision

### Disk Space Critical (<10GB)
```bash
ssh akushnir@192.168.168.31
docker system prune -a --volumes -f
df -h /
```

### Network Issues
```bash
ssh akushnir@192.168.168.31
ping -c 3 8.8.8.8
docker network inspect phase13-net
```

### Stop Test (Last Resort)
```bash
ssh akushnir@192.168.168.31
pkill -f "phase-13-day2-load-test"
docker-compose restart
```

---

## 📊 CHECKPOINT TIMES

| Time | Action | Expected |
|------|--------|----------|
| **09:00 UTC** | Load test starts | Metrics begin |
| **12:00 UTC** | 3h checkpoint | SLOs normal |
| **18:00 UTC** | 9h checkpoint | SLOs normal |
| **00:00 UTC (Apr 15)** | 15h checkpoint | SLOs normal |
| **06:00 UTC (Apr 15)** | 21h checkpoint | SLOs normal |
| **09:00 UTC (Apr 15)** | Test completes | Collect final data |
| **12:00 UTC (Apr 15)** | Decision | 🟢 PASS or 🔴 FAIL |

---

## 🔗 COMMUNICATION

- **Issue Detected**: Slack #code-server-production immediately
- **SLO Breach**: Mention @DevOps @Platform-Manager
- **Critical Issue**: Escalate to @VP-Engineering
- **Status Update**: Comment on GitHub issue #210 every 6h

---

## 📂 KEY FILES & LOCATIONS

**Documentation**:
- PHASE-13-DAY2-EXECUTION-READY.md
- PHASE-13-EMERGENCY-PROCEDURES.sh
- PHASE-13-DAY2-FINAL-CHECKLIST.md

**Scripts** (remote host):
- ~/code-server-phase13/scripts/phase-13-day2-preflight-final.sh
- ~/code-server-phase13/scripts/phase-13-day2-orchestrator.sh
- ~/code-server-phase13/scripts/phase-13-day2-monitoring.sh

**Logs** (remote host):
- /tmp/phase-13-monitoring.log (real-time SLOs)
- /tmp/phase-13-load-test.log (load generation)
- /tmp/phase-13-execution-*.log (execution tracking)

---

## ✅ PASS CRITERIA (All Must Be Met)

✅ p99 Latency <100ms throughout 24h
✅ Error Rate <0.1% throughout 24h
✅ Throughput >100 req/s throughout 24h
✅ Availability >99.9% throughout 24h
✅ Zero uncharacterized container restarts
✅ All monitoring data successfully collected

**If all ✅**: 🟢 **PASS** → Phase 14 proceeds
**If any ❌**: 🔴 **FAIL** → Schedule retry

---

## 🎯 DECISION AT 12:00 UTC (April 15)

```
🟢 PASS → Immediate Phase 14 deployment
   └─ Stage 1: 10% canary traffic
   └─ Stage 2: 50% canary traffic
   └─ Stage 3: 100% full production

🔴 FAIL → Root cause analysis needed
   └─ Schedule post-mortem
   └─ Plan fix
   └─ Retry in 2-5 days
```

---

## 📏 TIME REMAINING COUNTER

Use during the 24-hour test:

```
09:00 → 09:30 (00:30 elapsed, 23:30 remaining)
09:00 → 12:00 (03:00 elapsed, 21:00 remaining)
09:00 → 18:00 (09:00 elapsed, 15:00 remaining)
09:00 → 00:00 (15:00 elapsed, 09:00 remaining)
09:00 → 06:00 (21:00 elapsed, 03:00 remaining)
09:00 → 09:00 (24:00 elapsed, DONE!)
```

---

## 🆘 NEED HELP?

1. **Technical issue** → Check PHASE-13-EMERGENCY-PROCEDURES.sh
2. **Need quick command** → Reference this card
3. **Can't resolve** → Escalate to Platform Manager
4. **Still stuck** → Escalate to VP Engineering

---

**REMEMBER**: You've trained for this. Follow the procedure. Communicate early. Escalate when needed.

**Let's get this test PASSED! 🚀**
