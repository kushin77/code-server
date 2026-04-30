# Operations Team Runbook - Hermes Agent Portal

**Date:** April 30, 2026 | **Audience:** Operations Team | **Status:** PRODUCTION

---

## Your Mission

Monitor, support, and maintain the Hermes Agent Portal in production. Your job is to:
1. Keep systems healthy and responsive
2. Respond to incidents quickly
3. Communicate with stakeholders
4. Execute procedures in the manual

---

## Daily Checklist

### Morning (09:00)
- [ ] Login to monitoring dashboard
- [ ] Check overnight logs for errors: `docker-compose logs --since 12h | grep -i error`
- [ ] Verify all 5 services running: `docker-compose ps` (should show 5/5 "Up")
- [ ] Check resource usage: `docker stats --no-stream` (CPU <60%, Memory <70%)
- [ ] Check disk space: `df -h /home` (should show >20GB free)
- [ ] Verify external access: `curl -k https://kushnir.cloud/`
- [ ] Review overnight incidents or alerts
- [ ] Update status page if needed

### Throughout Day (Every 2 hours)
- [ ] Run health monitor: `./monitor-health.sh 10 300`
- [ ] Check for error messages: `docker-compose logs --since 1h | grep -i error`
- [ ] Verify API responsiveness: `curl -k https://kushnir.cloud/api/hermes/health`
- [ ] Check resource trends

### Evening (17:00)
- [ ] Review day's logs and incidents
- [ ] Verify backup completed today
- [ ] Check tomorrow's maintenance schedule
- [ ] Prepare incident report if needed

---

## Incident Response

### Step 1: Detect Issue (Automatic or Manual)
- Alert received OR manual detection
- Verify the issue: Test the service, check logs
- Note the time and what you observe

### Step 2: Assess Severity

**P1 - CRITICAL:** Service completely down, no workaround
- Example: API not responding at all
- Action: Immediate escalation to DevOps

**P2 - HIGH:** Significant degradation, partial workaround
- Example: API slow (>2 seconds response time)
- Action: Escalate to DevOps within 15 minutes

**P3 - MEDIUM:** Minor issues, most features working
- Example: One dashboard page slow
- Action: Log and monitor, escalate if worsens

**P4 - LOW:** Cosmetic or insignificant issues
- Example: Log messages, UI minor issues
- Action: Document and review later

### Step 3: Execute Response

**For API Down (P1):**
1. Message Slack: "API SERVICE DOWN - investigating"
2. Contact DevOps Lead immediately
3. Provide: When detected, what you see, any recent changes

**For Slow Response (P2):**
1. Message Slack: "API responding slowly (>1s)"
2. Check: `docker stats --no-stream` (look for high CPU/memory)
3. If high: Contact DevOps
4. If normal: Monitor and report to DevOps after 15 min

**For Dashboard Issue (P3):**
1. Check: Can you access other pages?
2. Check: Is it a network issue or service issue?
3. Document: Screenshot, what you tried
4. Message Slack with details
5. Monitor for escalation

**For Minor Issues (P4):**
1. Document the issue
2. Create ticket if needed
3. Review during next maintenance window

### Step 4: Communicate

**External (If service is down):**
- Update status page: "Investigating service issue"
- Tweet/Slack: "We're experiencing issues. Working on a fix."
- Update every 15 minutes with status

**Internal (Every Issue):**
- Slack #incidents: Incident description and status
- Email on-call engineer if needed
- Create ticket in tracking system

### Step 5: Resolution & Follow-up

1. Confirm service is working again
2. Verify SLA targets are met
3. Document root cause (DevOps will investigate)
4. Update incident ticket with resolution
5. Send email summary to team

---

## Monitoring Tools

### Manual Monitoring
```bash
# Real-time health (updates every 10 seconds)
./monitor-health.sh 10 3600

# Full deployment validation
./validate-deployment.sh
```

### Log Monitoring
```bash
# Recent errors
docker-compose logs --since 1h | grep -i "error\|exception\|fatal"

# Recent warnings
docker-compose logs --since 1h | grep -i "warning"

# Specific service logs
docker logs -f hermes-integration
docker logs -f appsmith
docker logs -f code-server-postgres
```

### Resource Monitoring
```bash
# CPU and memory
docker stats --no-stream

# Disk space
df -h /home

# Network
ping 192.168.168.42 (secondary host latency)
```

---

## Common Issues & Resolution

### "API Not Responding"
1. Check if container is running: `docker ps | grep hermes-integration`
2. If not running: Contact DevOps immediately
3. If running: Check logs: `docker logs hermes-integration | tail -50`
4. Escalate to DevOps with logs

### "Dashboard Slow"
1. Check if it's just your network: Try different browser/device
2. Check API response: `curl -w "%{time_total}\n" https://kushnir.cloud/api/hermes/health`
3. If API slow: Contact DevOps
4. If API fast but dashboard slow: Try clearing browser cache

### "Can't Login to Dashboard"
1. Verify internet connection
2. Check: https://kushnir.cloud/ (not http)
3. If SSL warning: That's normal (until May 1 upgrade)
4. Try: Different browser or incognito mode
5. If still can't login: Contact DevOps

### "Database is Down"
1. Check status: `docker ps | grep postgres`
2. If not running: Contact DevOps immediately
3. If running but not responding: Contact DevOps with logs

### "Disk Running Out"
1. Alert DevOps: "Disk space low: only XGB free"
2. DevOps will clean up old logs
3. Do not delete files yourself

### "Memory High"
1. Alert DevOps: "Memory at 80%+: XGB used"
2. DevOps will investigate and optimize
3. Monitor for potential service crash

---

## SLA Targets (What We Commit To)

| SLA | Target | Warning | Critical |
|-----|--------|---------|----------|
| Uptime | 99.9% | 99.5% | 99.0% |
| Response Time | <500ms | 1000ms | 2000ms |
| Error Rate | <0.1% | 1% | 5% |
| All Services | Healthy | 95% | 85% |

**Your Role:** Monitor these metrics and alert DevOps if any approach warning level.

---

## Communication Channels

**For Urgent Issues:**
- Slack #incidents channel
- DevOps on-call: [Phone number]
- Status page: [URL]

**For Planning/Questions:**
- Slack #operations channel
- Weekly standup: Friday 14:00 UTC
- Email: ops-team@company.com

---

## Quick Reference

```bash
# Check everything is OK
docker-compose ps                    # 5/5 running?
docker stats --no-stream             # CPU <60%, Memory <70%?
df -h /home                          # >20GB free?
curl -k https://kushnir.cloud/       # Responds?

# Get help
./monitor-health.sh 10 300           # Real-time monitoring
docker-compose logs --since 1h       # Recent logs
./validate-deployment.sh              # Full validation

# On-call escalation
DevOps Lead: [contact]
Operations Lead: [contact]
CTO: [contact]
```

---

**Remember: You're the first line of defense. Quick detection and communication saves everyone time.**
