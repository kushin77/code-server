# 📱 MAY 1 QUICK REFERENCE CARD - PRINT THIS

**Date:** May 1, 2026 | **Status:** Production Go-Live Day

---

## ⏰ TIMELINE AT A GLANCE

```
06:00 UTC  │ Team Assembly & Morning Briefing
           │ Run: ./may-1-morning-startup.sh
           │
06:15 UTC  │ Pre-Deployment Verification (30 checks)
           │ Run: ./pre-deployment-verification-final.sh
           │ Time: ~20 minutes
           │
08:45 UTC  │ GO/NO-GO DECISION
           │ 5 sign-offs required
           │ Decision: GO or NO-GO?
           │
09:00 UTC  │ 🚀 PRODUCTION GO LIVE 🚀
           │ Deploy to production
           │ All teams on alert
           │
10:00 UTC  │ Post-Deployment Verification
           │ Run: ./post-deployment-verification.sh
           │ Verify all systems working
           │
17:00 UTC  │ Day 1 Status Report
```

---

## 🚨 EMERGENCY COMMANDS (Save to phone)

**Is the API working?**
```
curl -k https://kushnir.cloud/api/hermes/health
```

**Are all services running?**
```
docker-compose ps | grep -c "Up"  (should be 5)
```

**What's the CPU/Memory?**
```
docker stats --no-stream
```

**Database OK?**
```
docker exec code-server-postgres \
  psql -U purebliss_user -d purebliss_db -c "SELECT 1;"
```

**Redis OK?**
```
docker exec code-server-redis redis-cli ping  (should be PONG)
```

---

## 📞 ESCALATION CHAIN (Save to contacts)

| Level | Role | Phone | Slack |
|-------|------|-------|-------|
| 1 | Your Team Lead | _______ | @your-lead |
| 2 | DevOps On-Call | _______ | @devops-lead |
| 3 | Development Lead | _______ | @dev-lead |
| 4 | CTO | _______ | @cto |

**Response Times:**
- P1: 5 min
- P2: 15 min
- P3: 1 hour

---

## ✅ SUCCESS CHECKLIST (Print & tick off)

### 06:00 - Team Assembly
- [ ] All teams present
- [ ] No blockers identified
- [ ] Everyone has runbooks

### 06:15 - Pre-Deployment Verification
- [ ] Run verification script
- [ ] All 30+ checks passed
- [ ] Report generated

### 08:45 - Go/No-Go Decision
- [ ] All checks reviewed
- [ ] All teams ready
- [ ] 5 sign-offs obtained
- [ ] **DECISION: ☐ GO  ☐ NO-GO**

### 09:00 - Go Live
- [ ] Services deployed
- [ ] Monitoring active
- [ ] Teams on alert

### 10:00 - Post-Deployment
- [ ] Run verification
- [ ] All tests passed
- [ ] Systems healthy

---

## 🎯 CRITICAL DOCUMENTS (Bookmark These)

1. **Main Checklist:**
   `MAY_1_GOLIVE_EXECUTION_CHECKLIST.md`

2. **Your Role Guide:**
   - DevOps: `DEVOPS_TEAM_RUNBOOK.md`
   - Ops: `OPERATIONS_TEAM_RUNBOOK.md`
   - Dev: `DEVELOPMENT_TEAM_GUIDE.md`

3. **Quick Navigation:**
   `MASTER_DOCUMENTATION_INDEX.md`

4. **SLA Targets:**
   `FINAL_PRODUCTION_READINESS_CERTIFICATION.md`

---

## 🔴 IF SOMETHING GOES WRONG

**Step 1:** Identify the problem
```bash
./pre-deployment-verification-final.sh  # or
docker-compose ps  # or
docker logs hermes-integration | tail -50
```

**Step 2:** Document it
- Note time
- Note what failed
- Get error messages
- Screenshot if needed

**Step 3:** Escalate immediately
- Text/call your team lead
- Post in #incidents Slack
- Wait for guidance

**Step 4:** Don't panic
- We have rollback procedures
- Runbooks cover common issues
- Team knows what to do

---

## 💡 KEY REMINDERS

✅ **DO:**
- Follow procedures step-by-step
- Use the runbooks
- Ask questions before acting
- Communicate constantly
- Escalate when unsure

❌ **DON'T:**
- Skip verification steps
- Make decisions alone
- Deploy without approval
- Ignore warnings
- Restart services randomly

---

## 📊 WHAT TO MONITOR

**Real-time During Deployment:**
1. API responding? `curl -k https://kushnir.cloud/api/hermes/health`
2. Services up? `docker stats`
3. Database healthy? Connection test
4. Errors in logs? `docker logs --since 5m`

**Success Indicators:**
- ✅ API responds <500ms
- ✅ No error messages
- ✅ CPU <60%, Memory <70%
- ✅ All services "Up (healthy)"

---

## 📝 NOTES SECTION

Use this space for important numbers, notes, or decisions:

```
Team Lead Name:        _____________________
DevOps On-Call:        _____________________
Meeting Room:          _____________________
Deployment Start Time: _____________________
Pre-Check Result:      _____________________
Final Decision:        _____________________
```

---

## 🎉 SUCCESS LOOKS LIKE

When deployment is successful:
- ✅ All services running
- ✅ API responding
- ✅ Database healthy
- ✅ No critical errors
- ✅ Team confident
- ✅ Users can access platform
- ✅ All SLAs on target

**Celebration time!** 🚀

---

## 📋 ONE-PAGE SUMMARY

| Item | Status | Check |
|------|--------|-------|
| Runbooks Printed? | [ ] Yes | ☑️  |
| Phone Numbers Saved? | [ ] Yes | ☑️  |
| Scripts Verified? | [ ] Yes | ☑️  |
| VPN Working? | [ ] Yes | ☑️  |
| Access to Systems? | [ ] Yes | ☑️  |
| Time Zone Correct? | UTC | ☑️  |

---

**Keep this card with you on May 1, 2026**

**Questions? Check MASTER_DOCUMENTATION_INDEX.md**

**Emergency? Call Your Team Lead → DevOps On-Call → CTO**

🚀 **Ready for production deployment!** 🚀
