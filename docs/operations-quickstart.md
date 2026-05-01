# Code-Server Operations Handoff Package - Quick Start Guide

**Document**: Operations Team Quick Reference  
**Version**: Phase 10  
**Date**: April 30, 2026  
**Audience**: Operations Team, DevOps Engineers, SREs

---

## 🚀 Quick Start (5 Minutes to Operations Ready)

### 1. Access the Platform
```bash
# Primary host
ssh akushnir@192.168.168.31

# Replica host
ssh akushnir@192.168.168.42

# VRRP Virtual IP (active, high availability)
ssh akushnir@192.168.168.50
```

### 2. Check Infrastructure Status
```bash
# Quick health check (all containers, both hosts)
cd /home/akushnir/code-server
bash scripts/ci/validate-pre-apply.sh

# Expected output: All 14 checks PASS
```

### 3. View Live Dashboards
```
Grafana: http://localhost:3000/d/code-server-ops
Prometheus: http://localhost:9090
```

### 4. Enable Monitoring & Alerts
```bash
# Start monitoring metrics exporter
./scripts/ops/export-prometheus-metrics.sh start

# View alert history
tail -f /tmp/code-server-remediation.log
```

### 5. Set Up Auto-Remediation (Optional)
```bash
# Test in dry-run mode (no changes)
DRY_RUN=true ./scripts/ops/auto-remediation-engine.sh

# Enable in production (when ready)
sed -i 's/DRY_RUN=true/DRY_RUN=false/' .remediation/config.env
```

---

## 📚 Documentation Structure

### Core Operations Guides
| Document | Purpose | Time |
|----------|---------|------|
| [OPERATIONAL_RUNBOOK.md](docs/OPERATIONAL_RUNBOOK.md) | Daily operations, incident response (8 playbooks) | 30 min |
| [OPERATIONAL_HARDENING.md](docs/OPERATIONAL_HARDENING.md) | Pre-deployment validation, policy enforcement | 20 min |
| [ALERT_INTEGRATION_GUIDE.md](docs/ALERT_INTEGRATION_GUIDE.md) | Alert setup, Slack/email/syslog configuration | 15 min |
| [MONITORING_DASHBOARD_SETUP.md](docs/MONITORING_DASHBOARD_SETUP.md) | Prometheus/Grafana installation, dashboard config | 25 min |
| [AUTO_REMEDIATION_GUIDE.md](docs/AUTO_REMEDIATION_GUIDE.md) | Self-healing setup, safety policies, troubleshooting | 20 min |

### Completion Reports (Reference)
| Document | What | Status |
|----------|------|--------|
| [CONTINUATION_PHASE_8_MONITORING_DASHBOARDS.md](CONTINUATION_PHASE_8_MONITORING_DASHBOARDS.md) | Phase 8 summary | ✅ Complete |
| [CONTINUATION_PHASE_9_AUTO_REMEDIATION.md](CONTINUATION_PHASE_9_AUTO_REMEDIATION.md) | Phase 9 summary | ✅ Complete |

---

## 🎯 First Week Operations Plan

### Day 1: Setup & Familiarization (2 hours)
- [ ] Read this quickstart guide
- [ ] Access all 3 hosts via SSH
- [ ] Run health check validation
- [ ] Review OPERATIONAL_RUNBOOK.md
- [ ] Understand the 8 incident playbooks

### Day 2-3: Monitoring & Alerts (3 hours)
- [ ] Review ALERT_INTEGRATION_GUIDE.md
- [ ] Configure Slack webhook (if desired)
- [ ] Configure email alerts (if desired)
- [ ] Test alert routing: `./scripts/lib/alert-router.sh`
- [ ] Access Prometheus/Grafana dashboards
- [ ] Review existing metrics and alerts

### Day 4-5: Auto-Remediation (2 hours)
- [ ] Read AUTO_REMEDIATION_GUIDE.md
- [ ] Test dry-run: `DRY_RUN=true ./scripts/ops/auto-remediation-engine.sh`
- [ ] Review .remediation/config.env policies
- [ ] Understand protection mechanisms (SAFE_MODE, rate limits)
- [ ] Plan gradual enablement in production

### Week 2: Production Monitoring (Ongoing)
- [ ] Monitor logs: `tail -f /tmp/code-server-*.log`
- [ ] Review daily health reports
- [ ] Adjust thresholds based on your environment
- [ ] Train team on incident response
- [ ] Document any customizations

---

## 🔧 Daily Operations Checklist

### Morning (10 minutes)
```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Check container health
docker ps -a | grep -i unhealthy

# Check disk space
df -h /home

# Check logs for errors
tail -50 /tmp/code-server-*.log

# Check Grafana dashboard
# → http://localhost:3000/d/code-server-ops
# → Look for any red or yellow alerts
```

### After Any Deployment
```bash
# Validate pre-apply checks
cd /home/akushnir/code-server
bash scripts/ci/validate-pre-apply.sh

# Run health check
bash scripts/ci/check-docker-compose-idempotency.sh

# Review SLO metrics
./scripts/ops/track-slo-metrics.sh

# Check Grafana for new data
# → Verify all panels showing green
```

### Evening (5 minutes)
```bash
# Query alert history
grep "ERROR\|WARNING" /tmp/code-server-remediation.log | tail -20

# Check disk trends
df -h /home | tail -1

# Any unusual container restarts?
docker ps -a | head -20
```

---

## 🆘 Incident Quick Reference

### Issue: Container Not Healthy

**Quick Diagnosis**:
```bash
docker ps --filter "status=exited" -a
docker logs <container-name> | tail -20
```

**Quick Fix**:
```bash
docker restart <container-name>
docker ps | grep <container-name>  # verify it started
```

**Auto-Fix** (if enabled):
```
Auto-remediation will restart automatically (5-min cycle)
Check alert: tail -f /tmp/code-server-remediation.log
```

**Manual Review**:
- See playbook: [OPERATIONAL_RUNBOOK.md](docs/OPERATIONAL_RUNBOOK.md) → "Container Unhealthy"

---

### Issue: Disk Space High

**Quick Diagnosis**:
```bash
df -h /home
du -sh /home/* | sort -rh | head -10
```

**Quick Fix**:
```bash
docker system prune -af --volumes
docker image prune -af
df -h /home  # verify cleanup
```

**Auto-Fix** (if enabled):
```
Auto-remediation runs when >85% disk
Check alert: tail -f /tmp/code-server-remediation.log
```

---

### Issue: Terraform Drift Detected

**Quick Diagnosis**:
```bash
cd terraform/environments/private
terraform plan -json | jq -s 'map(select(.type == "resource_drift")) | length'
```

**Quick Fix**:
```bash
terraform plan  # review changes
terraform apply -auto-approve  # apply if safe
```

**Auto-Fix** (if enabled):
```
Auto-remediation BLOCKED by default (too risky)
Must manually review and apply Terraform
```

---

## 📊 Monitoring & Observability

### Access Points

**Prometheus** (Time-series metrics):
- URL: `http://localhost:9090`
- Use: Query historical data, set up rules
- Data: Last 15 days (default retention)

**Grafana** (Dashboards & visualization):
- URL: `http://localhost:3000`
- Dashboard: "Code-Server Operations" (code-server-ops)
- Panels: Drift, health, SLO, disk trends, container status

**Alert History** (Logs):
- File: `/tmp/code-server-remediation.log`
- View: `tail -f /tmp/code-server-remediation.log`
- Query: `grep "ERROR\|WARNING\|INFO" /tmp/code-server-remediation.log`

### Key Metrics to Watch

| Metric | Target | Alert If |
|--------|--------|----------|
| Terraform Drift | 0 resources | >5 resources drifted |
| Unhealthy Containers | 0 containers | >1 container unhealthy |
| Disk Usage | <70% | >85% usage |
| Availability SLO | ≥99% | <95% monthly |
| Deployment Success | 95%+ | <90% success rate |

---

## 🔐 Safety First

### Three-Level Safety
1. **Safe by Default**: Dangerous operations disabled
2. **Explicit Opt-In**: Require configuration changes to enable
3. **Multiple Guards**: Rate limits, protected resources, thresholds

### Protected Containers (Never Auto-Restart)
```
postgresql     - Stateful database, manual required
redis          - Cache with persistence, manual required
keepalived     - HA controller, manual required
```

### Protected Terraform Resources (Never Auto-Apply)
```
aws_rds_instance    - Stateful, database critical
aws_s3_bucket       - Contains data, loss is catastrophic
docker_container.postgresql  - Stateful
```

### When to Call for Backup
- Disk cleanup removes >20% space (investigate why)
- Same container restarted 5 times in 1 hour (root cause needed)
- Terraform drift >10 resources (manual review)
- Multiple containers unhealthy simultaneously (system issue)

---

## 📞 Getting Help

### Documentation Reference
1. **General Operations**: OPERATIONAL_RUNBOOK.md (8 incident playbooks)
2. **Setup Issues**: MONITORING_DASHBOARD_SETUP.md (troubleshooting section)
3. **Alert Problems**: ALERT_INTEGRATION_GUIDE.md (alert troubleshooting)
4. **Auto-Remediation**: AUTO_REMEDIATION_GUIDE.md (safety model explained)

### Common Troubleshooting Steps
```bash
# Check SSH connectivity to hosts
for host in 192.168.168.31 192.168.168.42; do
  ssh -o ConnectTimeout=5 akushnir@$host "echo OK" || echo "Failed: $host"
done

# Verify Docker is running
docker ps | head -1

# Check Terraform
cd terraform/environments/private && terraform plan -json | head -50

# Verify alert router
./scripts/lib/alert-router.sh init_alerts

# Check metrics exporter
curl http://localhost:9091/metrics | head -20
```

### Emergency Contact Procedures
1. **Critical Outage**: Contact platform team
2. **Alert System Down**: Check syslog via `logger` command
3. **All Hosts Down**: Network/infrastructure issue - escalate
4. **Lost Data**: Check state backups in `.git` history

---

## 📈 Weekly Operations Review

**Every Friday (30 minutes)**:
```bash
# Review weekly metrics
./scripts/ops/track-slo-metrics.sh

# Check remediation frequency
grep "SUCCESS" /tmp/code-server-remediation.log | \
  awk -F'[' '{print $1}' | uniq -c | sort -rn

# Any patterns in container restarts?
grep "RESTART_CONTAINER" /tmp/code-server-remediation.log | tail -20

# Disk space trending up/down?
df -h /home | tail -1

# Review Grafana for trends
# → Check 1-week view
# → Look for upward trends in errors/restarts
# → Adjust thresholds if needed
```

---

## 🎓 Team Training Topics

### For New Team Members
1. **Day 1**: Quickstart + daily checklist
2. **Day 2**: OPERATIONAL_RUNBOOK.md + playbooks
3. **Day 3**: Monitoring dashboard walkthrough
4. **Day 4**: Hands-on: Run health check, review logs
5. **Day 5**: Shadow ops, respond to test alerts

### For Advanced Team Members
1. **Terraform drift remediation** (when to enable)
2. **Advanced Prometheus queries** (custom monitoring)
3. **Alert rule creation** (custom alerts)
4. **State backup/recovery** (disaster scenarios)

---

## ✅ Operations Readiness Checklist

Before going live:

- [ ] All team members have SSH access to 3 hosts
- [ ] Health check validation runs successfully
- [ ] Monitoring dashboards accessible and displaying data
- [ ] Alert routing tested (Slack/email/syslog)
- [ ] Auto-remediation tested in dry-run mode
- [ ] Daily operations checklist documented and trained
- [ ] Incident playbooks reviewed with team
- [ ] Emergency procedures defined
- [ ] On-call rotation established
- [ ] Weekly review schedule set

---

## 📋 Critical Files Reference

### Configuration
- `.remediation/config.env` - Auto-remediation policies
- `.alerts/config.env` - Alert routing configuration
- `monitoring/prometheus.yml` - Prometheus scrape config
- `monitoring/grafana-dashboard.json` - Dashboard definition

### Scripts
- `scripts/ci/validate-pre-apply.sh` - Pre-deployment validation (14 checks)
- `scripts/ops/drift-monitoring-watchdog.sh` - 5-minute drift check
- `scripts/ops/auto-remediation-engine.sh` - Self-healing engine
- `scripts/ops/export-prometheus-metrics.sh` - Metrics exporter
- `scripts/ops/track-slo-metrics.sh` - SLO tracking

### Documentation
- `docs/OPERATIONAL_RUNBOOK.md` - 850 lines, 8 playbooks
- `docs/OPERATIONAL_HARDENING.md` - Pre-apply validation guide
- `docs/ALERT_INTEGRATION_GUIDE.md` - Alert setup & configuration
- `docs/MONITORING_DASHBOARD_SETUP.md` - Prometheus & Grafana setup
- `docs/AUTO_REMEDIATION_GUIDE.md` - Self-healing setup & safety

---

## 🎬 Next Steps

1. **Now**: Read this quickstart guide (you are here ✓)
2. **Today**: Access the platform and run health check
3. **This Week**: Follow the "First Week Operations Plan" above
4. **Ongoing**: Use daily checklist and reference guides
5. **Monthly**: Review trends and adjust thresholds
6. **Quarterly**: Test disaster recovery procedures

---

**Status**: ✅ **OPERATIONS READY**

All documentation, tools, and automation are ready for operations team deployment. Welcome to the team!

