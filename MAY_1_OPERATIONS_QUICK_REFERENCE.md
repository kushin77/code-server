# May 1 Go-Live - Operations Quick Reference Card

**Print and post on your desk!**

---

## 🚀 GO-LIVE TIMELINE (May 1, 2026 UTC)

| Time | Phase | Owner | Status |
|------|-------|-------|--------|
| **06:00-06:15** | Team Assembly & Briefing | Project Manager | 📋 |
| **06:15-06:45** | Pre-Deployment Verification | DevOps Lead | ✅ |
| **06:45-08:00** | Infrastructure Health Check | DevOps Lead | 🔍 |
| **08:00-08:30** | PostgreSQL Replication Fix | DevOps Engineer | 🔧 |
| **08:30-08:45** | Final Go/No-Go Decision | DevOps Lead + Manager | 📊 |
| **09:00-09:30** | Production Deployment | DevOps Lead | 🚀 |
| **09:30-10:00** | Health Verification | QA Team | ✅ |
| **10:00+** | Monitoring Window (24h) | On-Call Team | 👀 |

---

## 🎯 5 CRITICAL ALERTS TO KNOW

### 1. 🔴 PostgreSQL Replication Not Active
**What to do:** Run `bash orchestrate-postgresql-replication-fix.sh` on replica (192.168.168.42)  
**Expected:** ~20 minutes to fix  
**Command:** `ssh ubuntu@192.168.168.42 && cd /home/ubuntu/code-server && bash orchestrate-postgresql-replication-fix.sh`

### 2. 🔴 PostgreSQL Down
**What to do:** Restart with `docker-compose up -d postgres`  
**Expected:** ~30 seconds startup  
**Escalate if:** Still down after restart

### 3. 🔴 API Server Down
**What to do:** Restart with `docker-compose up -d api-server`  
**Expected:** ~10 seconds startup  
**Check:** `curl http://localhost:8000/health`

### 4. 🔴 API Error Rate > 1%
**What to do:** Check logs `docker logs api-server --tail=50`  
**Common cause:** Database slow or memory issue  
**Quick fix:** Restart service or investigate database

### 5. 🟠 Host CPU/Memory High
**What to do:** Identify with `docker stats --no-stream`  
**Common cause:** Memory leak or spike in traffic  
**Quick fix:** Restart container or monitor

---

## 🔧 ESSENTIAL COMMANDS

### Service Status
```bash
# All services
docker-compose ps

# Specific service
docker-compose ps postgres
docker-compose ps redis
docker-compose ps api-server
```

### Health Checks
```bash
# PostgreSQL
docker exec code-server-postgres psql -U postgres -c "SELECT 1;"

# Redis
docker-compose exec redis redis-cli PING

# API
curl http://localhost:8000/health

# Replication
docker exec code-server-postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Result: t = in replication, f = not in replication
```

### Restart
```bash
# One service
docker-compose restart postgres

# All services
docker-compose restart

# Force restart
docker-compose down && docker-compose up -d
```

### Logs
```bash
# Last 50 lines
docker logs <container> --tail=50

# Follow in real-time
docker logs <container> -f

# Last 10 minutes
docker logs <container> --since 10m
```

---

## 📊 DASHBOARD LINKS

| Dashboard | URL | What to Watch |
|-----------|-----|---------------|
| Infrastructure | http://192.168.168.31:3000 | CPU, memory, disk |
| PostgreSQL | http://192.168.168.31:3000/d/postgresql | Replication lag, queries |
| API | http://192.168.168.31:3000/d/api-performance | Response time, error rate |
| Prometheus Alerts | http://192.168.168.31:9090/alerts | Active alerts |
| Alert Manager | http://192.168.168.31:9093 | Alert routing status |

---

## 📞 ESCALATION CHAIN

**Level 1 (YOU):**
- Acknowledge alert
- Run quick diagnosis
- Try restart if appropriate
- Escalate if stuck > 15 min

**Level 2 (Senior DevOps):**
- More complex troubleshooting
- Can make infrastructure changes
- Phone: [CONTACT]
- Slack: @on-call-l2

**Level 3 (Manager):**
- Major incident coordination
- Customer communication
- Phone: [CONTACT]
- Slack: @devops-manager

---

## ✅ PRE-GO-LIVE CHECKLIST (Run Morning of May 1)

- [ ] PostgreSQL replication ACTIVE (test: `SELECT pg_is_in_recovery();` = t)
- [ ] All 87 containers running (`docker-compose ps | grep -c Up`)
- [ ] Dashboards loading and showing metrics
- [ ] Slack alerts working (sent test message)
- [ ] PagerDuty configured and responding
- [ ] SSH access to both hosts verified
- [ ] On-call team assembled and standing by
- [ ] Incident communication channel ready (#critical-incidents)
- [ ] Team knows escalation procedures
- [ ] Runbooks printed and available

---

## 🚨 IF SOMETHING GOES WRONG

### I don't know what to do:
1. **DON'T PANIC** - Take a breath
2. **Acknowledge the alert** - Click buttons in PagerDuty/Slack
3. **Read the runbook** - Check PRODUCTION_ON_CALL_RUNBOOK.md
4. **Post in Slack** - "@on-call-l2 I need help with: [DESCRIPTION]"
5. **Get Level 2 help** - Phone or Slack

### Service completely down:
1. Check `docker-compose ps` - verify containers exist
2. Try `docker-compose restart` - usually fixes transient issues
3. Check logs for error messages - `docker logs <container>`
4. If still down: **ESCALATE IMMEDIATELY**

### Can't SSH to host:
1. Verify IP address is correct (192.168.168.31 or 192.168.168.42)
2. Try: `ping 192.168.168.31`
3. Try from different machine if possible
4. Escalate to infrastructure team

### Database is corrupted:
1. **DON'T WRITE TO DATABASE**
2. Check logs: `docker logs code-server-postgres`
3. Stop all writes to database
4. **ESCALATE TO LEVEL 2 IMMEDIATELY**
5. May need to restore from backup

---

## 🎯 SUCCESS INDICATORS (After Go-Live)

Look for these in your first 24 hours:

✅ API responding to requests  
✅ All services showing green in dashboards  
✅ No CRITICAL alerts firing  
✅ No HIGH alerts persisting > 1 hour  
✅ PostgreSQL replication lag < 100ms  
✅ Error rate < 0.1%  
✅ Response time P95 < 1 second  

---

## 📋 MONITORING WINDOWS

**First Hour (09:00-10:00):** Watch dashboards closely  
**First 4 Hours (09:00-13:00):** Stay alert, check every 15 min  
**First 24 Hours (09:00 May 1 to 09:00 May 2):** Normal on-call duty  
**First Week:** Daily check-ins on health metrics

---

## 📝 INCIDENT LOGGING

When incident occurs, document:
- [ ] **What happened:** Brief description
- [ ] **When:** Start time and resolution time
- [ ] **Who:** Which service/component failed
- [ ] **Why:** Root cause (if known)
- [ ] **How fixed:** Steps taken to resolve
- [ ] **Prevention:** What to do next time

**Template:**
```
INCIDENT: [NAME]
Time: [HH:MM-HH:MM UTC]
Duration: [X minutes]
Service: [COMPONENT]
Root Cause: [CAUSE]
Resolution: [STEPS TAKEN]
Escalation: [YES/NO] → Level 2/3
Prevention: [FUTURE ACTION]
```

---

## 🎓 TRAINING RESOURCES

**Read before May 1:**
- PRODUCTION_ON_CALL_RUNBOOK.md - Step-by-step procedures
- POSTGRESQL_REPLICATION_OPERATIONS_GUIDE.md - Replication fix
- MAY_1_FINAL_DEPLOYMENT_READINESS_CHECKLIST.md - Go-live plan

**Keep Handy:**
- PRODUCTION_MONITORING_SETUP_GUIDE.md - Alert details
- This quick reference card - Print and post!

---

## ⏱️ YOU'RE ON-CALL FROM: ________ TO ________

**Your contact info:**
- Phone: ________________
- Slack: @______________
- Email: ________________

**Your backup (Level 2):**
- Name: _________________
- Phone: _________________
- Slack: @________________

---

**REMEMBER: You've got this! The platform is solid, the team is trained, and you have all the procedures you need. ✅**

