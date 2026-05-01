# Team Operations Handoff - Code-Server Platform
**Date:** May 1, 2026  
**Status:** Platform Ready for Operations Team Takeover  
**Audience:** Ops Team, DevOps Engineers, On-Call Engineers

---

## Document Purpose

This handoff package enables your team to independently operate the code-server platform. It includes:
- ✅ Architecture overview
- ✅ Daily operational procedures
- ✅ Incident response playbooks
- ✅ Troubleshooting guides
- ✅ Emergency procedures
- ✅ Escalation procedures

**Reference All Related Docs:**
- [Incident Response Playbook](docs/INCIDENT_RESPONSE_PLAYBOOK.md) - For incident procedures
- [Operations SOP Checklists](docs/OPERATIONS_SOP_CHECKLISTS.md) - Daily procedures
- [Operational Runbook](docs/OPERATIONAL_RUNBOOK.md) - Runbook procedures
- [Deployment Execution Runbook](DEPLOYMENT_EXECUTION_RUNBOOK.md) - Deployment procedures

---

## Part 1: Platform Overview

### Core Facts
- **Primary Host:** 192.168.168.31 (akushnir@192.168.168.31)
- **Replica Host:** 192.168.168.42 (akushnir@192.168.168.42)
- **Virtual IP:** 192.168.168.50 (edge access point)
- **Total Services:** 76 containers (38 per host)
- **Infrastructure:** Docker Compose + Terraform IaC
- **Repository:** /home/akushnir/code-server on each host
- **Repository Root:** /home/akushnir/code-server-enterprise

### Key Services You're Operating
**Stateless Services (Replicated):**
- Caddy (reverse proxy)
- Code-Server IDE  
- GitLab (source control)
- Appsmith (low-code platform)
- OAuth2 Proxy
- Edge Agent
- Execution Scheduler

**Stateful Services (Primary/Replica):**
- PostgreSQL (primary replication)
- Redis (sentinel failover)
- Redpanda (event streaming)
- Vault (secrets management)
- Minio (object storage)
- Qdrant (vector database)

**Observability Stack:**
- Prometheus (metrics)
- Grafana (dashboards) 
- Loki (logs)
- Tempo (traces)
- Alertmanager (alerts)

---

## Part 2: Quick Start for On-Call Engineers

### First 30 Seconds: Is Everything Down?

```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Check service status
cd /home/akushnir/code-server && docker compose ps

# If many services showing "Exited", go to CRITICAL INCIDENT section in INCIDENT_RESPONSE_PLAYBOOK.md
```

### Morning Health Check (5 minutes)

Use the **Daily Morning Checklist** in [Operations SOP Checklists](docs/OPERATIONS_SOP_CHECKLISTS.md):
```bash
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server
bash scripts/ci/validate-pre-apply.sh
# All checks should show PASS
```

### Typical Issues & Quick Fixes

| Issue | Command | Expected Result |
|-------|---------|-----------------|
| **High latency** | `docker compose logs api-gateway \| tail -50` | Look for "timeout", "connection refused" errors |
| **Disk full** | `df -h /home` | Should be <70% used |
| **Database slow** | `docker compose logs postgres \| grep -i "slow\|timeout"` | No slow query warnings |
| **Memory pressure** | `docker stats --no-stream \| sort -k 4 -h` | No service >500MB |
| **Network issues** | `ping -c 3 8.8.8.8` | Should get responses |

---

## Part 3: Daily Operations Rhythm

### Morning (Start of Shift)
1. Run Morning Checklist (docs/OPERATIONS_SOP_CHECKLISTS.md) - 10 min
2. Check Grafana dashboard for anomalies - 5 min
3. Review Alertmanager for any overnight alerts - 5 min
4. Communicate status to team - Slack

### Throughout Shift
1. Monitor Grafana (3 min every 30 min)
2. Watch Alertmanager (immediate if alert fires)
3. Check logs for errors (`docker compose logs -f --tail 100`)
4. Respond to any alerts per INCIDENT_RESPONSE_PLAYBOOK.md

### End of Shift
1. Document any issues in incident log
2. Handoff to next shift with status report
3. Update on-call status board

---

## Part 4: Critical Incident Response

**IMPORTANT: Follow [Incident Response Playbook](docs/INCIDENT_RESPONSE_PLAYBOOK.md) for detailed procedures**

### Severity Levels & Response Times
| Level | Response Time | Examples |
|-------|---------------|----------|
| **Critical** | 5 minutes | All APIs down, database unavailable |
| **High** | 15 minutes | Service degradation, 50% requests failing |
| **Medium** | 1 hour | Single service slow, limited feature impact |
| **Low** | 4 hours | UI glitch, non-critical feature broken |

### Critical Incident (5 min response)
1. **Declare incident:** Slack #critical-incidents channel
2. **Assess state:** SSH to host and run `docker compose ps` and `docker compose logs --tail 200`
3. **Determine cause:** Database? Network? Disk? Memory?
4. **Execute fix:** See specific procedures in INCIDENT_RESPONSE_PLAYBOOK.md
5. **Validate:** Rerun validation checks - all should pass

### If You Can't Fix It in 15 Minutes:
- **Document** what you've tried
- **Escalate** to Level 2 (ops-lead) with full context
- **Keep monitoring** and updating incident status

---

## Part 5: Replication & Failover

### Understanding Replication
- Primary (192.168.168.31) writes all data
- Replica (192.168.168.42) continuously syncs
- PostgreSQL uses streaming replication
- Redis uses sentinel for automatic failover
- If primary goes down, failover process begins automatically

### Checking Replication Status
```bash
# On primary host
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server
docker compose logs postgres | grep -i "replication\|wal\|subscriber"
```

### Manual Failover (Last Resort)
See "Manual Failover Procedure" in [Operational Runbook](docs/OPERATIONAL_RUNBOOK.md)
- Only do this if primary host is completely down
- Requires coordination with team lead
- Data loss risk: None (if replication is current)
- Recovery time: ~10 minutes

---

## Part 6: Common Troubleshooting

### "Connection Refused" Errors
```bash
# Check if service is running
docker compose ps | grep <service_name>

# If Exited, restart it
docker compose restart <service_name>

# Check logs for why it exited
docker compose logs <service_name> --tail 50
```

### "Out of Disk Space"
```bash
# See what's taking space
du -sh /home/* | sort -h

# Clean up old logs (usually /home/akushnir/code-server/logs/)
find /home/akushnir/code-server/logs -name "*.log" -mtime +30 -delete

# Restart services to refresh log handles
docker compose restart
```

### "High CPU Usage"
```bash
# See which containers are using CPU
docker stats --no-stream | sort -k 3 -h | tail -5

# Get detailed logs from high-CPU container
docker compose logs <service_name> --tail 100 | grep -i "error\|panic\|fatal"

# If stuck, gracefully restart it
docker compose restart <service_name>
```

### "Database Connectivity Issues"
```bash
# Check PostgreSQL is running
docker compose ps | grep postgres

# Test connection
docker compose exec postgres psql -U postgres -d code_server -c "SELECT 1;"

# Check replication status
docker compose logs postgres | grep -i "replication"
```

---

## Part 7: Deployment Procedures

### Running a Deployment
See [Deployment Execution Runbook](DEPLOYMENT_EXECUTION_RUNBOOK.md) for full procedures.

**Quick version:**
1. Ensure all morning checks pass
2. Create backup: `git add -A && git commit -m "backup: before deployment"`
3. Trigger via GitHub: Actions → phase-4-7-orchestration → Run workflow
4. Monitor in Actions tab
5. Post-deployment validation: Run validation checks again
6. Communicate completion to team

### Important Notes
- **Never deploy during business hours without coordination**
- **Always have rollback plan documented before deploying**
- **Test in staging first if possible**
- **Keep deployment window <30 minutes**

---

## Part 8: Escalation Procedures

### Level 1 (You - On-Call)
- Respond within 5 minutes (critical) or 15 minutes (high)
- Follow incident response procedures
- Attempt resolution for 15 minutes
- If unresolved, escalate to Level 2

### Level 2 (Ops Lead)
- Page: [ops-lead-phone] or Slack @ops-lead
- Provide: What happened, what you tried, current status
- Decision: Rollback, manual failover, or escalate to Level 3

### Level 3 (Engineering Lead)
- For: Data loss concerns, multi-service failures, architecture issues
- Page: [eng-lead-phone] or Slack @eng-lead
- Trigger: Post-mortem after resolution

---

## Part 9: Knowledge Base

### Critical Documents
1. [Incident Response Playbook](docs/INCIDENT_RESPONSE_PLAYBOOK.md) - Your primary reference for incidents
2. [Operations SOP Checklists](docs/OPERATIONS_SOP_CHECKLISTS.md) - Daily procedures
3. [Operational Runbook](docs/OPERATIONAL_RUNBOOK.md) - Operational procedures
4. [Deployment Execution Runbook](DEPLOYMENT_EXECUTION_RUNBOOK.md) - Deployment guide

### Monitoring & Dashboards
- **Grafana:** http://192.168.168.250:3000 (or your external endpoint)
  - Username: admin
  - Password: [in Vault or team password manager]
- **Prometheus:** http://192.168.168.250:9090
- **Alertmanager:** http://192.168.168.250:9093

### Key Contacts
- **On-Call Rotation:** [Link to rotation schedule]
- **Ops Lead:** [Name & phone]
- **Eng Lead:** [Name & phone]
- **Team Slack:** #code-server-ops

---

## Part 10: Training Checklist

Before taking on on-call responsibility, ensure you've:

- [ ] Read this entire handoff document
- [ ] Read Incident Response Playbook
- [ ] Run morning checklist successfully
- [ ] Accessed all three hosts (primary, replica, virtual IP)
- [ ] Viewed Grafana dashboards
- [ ] Checked Alertmanager setup
- [ ] Reviewed one past incident (if available)
- [ ] Done a practice failover in non-production
- [ ] Signed off with ops lead

---

## Part 11: Health Metrics & SLOs

### Service Level Objectives (SLOs)

| SLO | Target | Alert If Below |
|-----|--------|-----------------|
| **Availability** | 99.5% uptime | <99% (4h/month down) |
| **Response Time** | <200ms p99 | >300ms sustained |
| **Error Rate** | <0.1% | >0.5% sustained |
| **Database Health** | Replication lag <1s | >5s replication lag |

### Checking Against SLOs
```bash
# Dashboard: Grafana → Code-Server Monitoring → SLO Dashboard
# Or command-line
scripts/ops/track-slo-metrics.sh
```

---

## Part 12: Emergency Contacts & Escalation

### During Business Hours
- **Slack:** #code-server-ops (fastest)
- **Ops Lead:** [Contact info]
- **Response Target:** 5-15 min

### After Hours (Weekend/Night)
- **On-Call Pager:** [Pager service]
- **Emergency Phone Tree:** [Phone numbers]
- **Response Target:** 15-30 min

---

## Success Criteria for Operations Handoff

✅ Team can run morning checks successfully  
✅ Team can respond to incidents per playbook  
✅ Team can execute deployments  
✅ Team understands failover procedures  
✅ Team knows how to escalate  
✅ Team has access to all monitoring tools  
✅ Team has completed training checklist  

---

## Final Handoff Confirmation

**Prepared By:** GitHub Copilot Agent  
**Date:** May 1, 2026  
**Repository:** /home/akushnir/code-server  
**Total Commits:** 3,105  

**Handoff Completion:**
- [ ] All operational documentation reviewed with team
- [ ] All team members completed training checklist
- [ ] Practice incident response completed
- [ ] Access verified for all team members
- [ ] Monitoring/alerting confirmed operational
- [ ] Escalation procedures tested
- [ ] On-call rotation activated

---

**Questions? References:**
- Architecture: DEPLOYMENT_COMPLETION_REPORT.md
- Incidents: docs/INCIDENT_RESPONSE_PLAYBOOK.md
- Daily Ops: docs/OPERATIONS_SOP_CHECKLISTS.md
- Deployments: DEPLOYMENT_EXECUTION_RUNBOOK.md
