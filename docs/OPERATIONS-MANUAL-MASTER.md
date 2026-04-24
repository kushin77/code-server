# Master Operations Manual for KC Production Cluster

**Purpose**: Unified operations reference for kushin77/code-server production infrastructure  
**Audience**: Operations Engineers, SRE, DevOps, On-Call Team  
**Version**: 1.0  
**Date**: April 24, 2026  
**Status**: Production-Ready

---

## Quick Navigation

This manual consolidates all operational procedures. Use sections below for specific tasks.

### 📋 Core Operations

| Task | Time | Reference |
|------|------|-----------|
| Daily Health Check | 5 min | [Section 1](#1-daily-operations) |
| Deploy to Production | 8-13 min | [DEPLOYMENT-RUNBOOK-OPERATIONS.md](DEPLOYMENT-RUNBOOK-OPERATIONS.md) |
| Incident Response | 5-30 min | [INCIDENT-COMMUNICATION-GUIDE.md](INCIDENT-COMMUNICATION-GUIDE.md) |
| Failover Procedure | 5-10 min | [FAILOVER-RUNBOOK-SIMPLIFIED.md](FAILOVER-RUNBOOK-SIMPLIFIED.md) |
| Troubleshooting | 10-60 min | [ADVANCED-TROUBLESHOOTING-GUIDE.md](ADVANCED-TROUBLESHOOTING-GUIDE.md) |

### 🔐 Security & Compliance

| Task | Reference |
|------|-----------|
| Air-Gapped Deployment | [AIR-GAPPED-DEPLOYMENT-COMPLETE.md](AIR-GAPPED-DEPLOYMENT-COMPLETE.md) |
| Security Audit | [SECURITY-HARDENING-GUIDE.md](SECURITY-HARDENING-GUIDE.md) |
| TLS Certificate Management | [Section 3](#3-certificate-management) |
| Access Control | [Section 4](#4-access-control) |

### 📊 Monitoring & SLA

| Task | Reference |
|------|-----------|
| Dashboard Setup | [GRAFANA-DASHBOARD-SETUP.md](GRAFANA-DASHBOARD-SETUP.md) |
| SLA Metrics | [PRODUCTION-SLA-METRICS.md](PRODUCTION-SLA-METRICS.md) |
| Monitoring Health Checks | [Section 5](#5-monitoring-and-alerting) |

---

## 1. Daily Operations

### 1.1 Start of Shift Checklist (5 minutes)

**Every shift begins with:**

```bash
#!/bin/bash
# scripts/ops/shift-start-checklist.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

log_info "🌅 Starting shift checklist..."

# 1. Cluster Health
log_info "[1/5] Checking cluster health..."
for replica in 192.168.168.31 192.168.168.42; do
  if ssh -o ConnectTimeout=3 akushnir@$replica 'echo OK' &>/dev/null; then
    log_info "  ✅ $replica reachable"
  else
    log_error "  ❌ $replica UNREACHABLE - ESCALATE IMMEDIATELY"
    exit 1
  fi
done

# 2. Service Status
log_info "[2/5] Checking service status..."
for replica in 192.168.168.31 192.168.168.42; do
  services=$(ssh akushnir@$replica 'docker compose ps -q | wc -l')
  log_info "  ✅ $replica: $services services running"
done

# 3. Database Replication
log_info "[3/5] Checking database replication..."
lag=$(ssh akushnir@192.168.168.31 'docker compose exec -T postgres-primary psql -U postgres -c "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), slot_restart_lsn) FROM pg_replication_slots;" 2>/dev/null' | tail -1 | tr -d ' ')
if [ "$lag" -lt 1000000 ]; then
  log_info "  ✅ Replication lag < 1 MB: $lag bytes"
else
  log_warn "  ⚠️  Replication lag high: $lag bytes"
fi

# 4. Disk Space
log_info "[4/5] Checking disk space..."
for replica in 192.168.168.31 192.168.168.42; do
  usage=$(ssh akushnir@$replica 'df -h / | tail -1 | awk "{print \$5}"' | tr -d '%')
  if [ "$usage" -lt 80 ]; then
    log_info "  ✅ $replica disk: ${usage}% used"
  else
    log_error "  ⚠️  $replica disk: ${usage}% used (CRITICAL)"
  fi
done

# 5. Certificate Expiration
log_info "[5/5] Checking certificate expiration..."
cert_days=$(openssl s_client -connect kushnir.cloud:443 -servername kushnir.cloud </dev/null 2>/dev/null | \
  openssl x509 -noout -dates | grep notAfter | cut -d'=' -f2 | \
  xargs -I {} date -d {} +%s && echo | awk '{days=($1-now)/86400; if(days>30) print days}')

if [ -n "$cert_days" ] && [ "$cert_days" -gt 30 ]; then
  log_info "  ✅ Certificate valid: ~${cert_days} days remaining"
else
  log_warn "  ⚠️  Certificate expiring soon (<30 days)"
fi

log_info "✅ Shift start checklist complete"
```

**Run this at shift start:**
```bash
bash scripts/ops/shift-start-checklist.sh
```

### 1.2 End of Shift Checklist

```bash
log_info "🌆 End of shift verification..."

# 1. No open incidents
incidents=$(gh issue list --repo kushin77/code-server --state open --label incident --json number | jq length)
log_info "  Open incidents: $incidents"

# 2. All services green
for replica in 192.168.168.31 192.168.168.42; do
  healthy=$(ssh akushnir@$replica 'curl -s http://localhost:8080/health | grep -q UP && echo 1 || echo 0')
  [ "$healthy" = "1" ] && log_info "  ✅ $replica healthy" || log_warn "  ⚠️  $replica status unknown"
done

log_info "✅ End of shift verification complete"
```

---

## 2. Deployment Operations

### 2.1 Pre-Deployment

**Checklist** (done automatically by `verify-production-readiness.sh`):

```
☑ Both replicas SSH reachable
☑ Load balancer health checks passing
☑ Database replication < 1 second lag
☑ Redis Sentinel failover ready
☑ All services running
☑ No P0/P1 incidents blocking deployment
☑ Git commit on main branch (no uncommitted changes)
```

### 2.2 Deployment Command

```bash
# Standard parallel deployment to both replicas
bash scripts/ops/redeploy.sh

# Expected output:
# 🚀 Executing standard redeploy on 192.168.168.31...
# 🚀 Executing standard redeploy on 192.168.168.42...
# ✅ Node 192.168.168.31 is up-to-date
# ✅ Node 192.168.168.42 is up-to-date
```

**Time**: 8-13 minutes (parallel)  
**Downtime**: < 1 second (LB switch)

### 2.3 Post-Deployment Verification

```bash
# 1. Verify both replicas deployed
git log --oneline -1
# Output should show latest commit on both replicas

# 2. Check health
bash scripts/ops/verify-deployment-state.sh

# 3. Validate parity
bash scripts/ops/validate-cluster-parity.sh
```

**Full reference**: [DEPLOYMENT-RUNBOOK-OPERATIONS.md](DEPLOYMENT-RUNBOOK-OPERATIONS.md)

---

## 3. Certificate Management

### 3.1 Certificate Status

```bash
# Check certificate expiration
openssl s_client -connect kushnir.cloud:443 -servername kushnir.cloud </dev/null 2>/dev/null | \
  openssl x509 -noout -dates
```

**Output example**:
```
notBefore=Apr 24 00:00:00 2026 GMT
notAfter=Apr 25 23:59:59 2027 GMT
```

### 3.2 Certificate Renewal (Automatic)

Let's Encrypt auto-renews 30 days before expiry via Caddy.

**Rate Limit Issue** (#1694):
- Rate limit reset: April 25, 2026 11:29:47 UTC
- If urgent, use self-signed cert recovery: `bash scripts/ops/p1-1694-tls-recovery.sh`

### 3.3 Manual Renewal

```bash
# Force renewal (if needed)
ssh akushnir@192.168.168.31 'docker compose restart caddy'

# Verify renewal
sleep 30
openssl s_client -connect kushnir.cloud:443 </dev/null 2>/dev/null | \
  openssl x509 -noout -dates
```

---

## 4. Access Control

### 4.1 SSH Key Management

**Add new team member**:

```bash
# 1. Add SSH public key to authorized_keys on both replicas
for replica in 192.168.168.31 192.168.168.42; do
  ssh-copy-id -i ~/.ssh/kushnir-prod.pub akushnir@$replica
done

# 2. Verify access
ssh -i ~/.ssh/kushnir-prod akushnir@192.168.168.31 'echo Access OK'
ssh -i ~/.ssh/kushnir-prod akushnir@192.168.168.42 'echo Access OK'
```

**Revoke team member**:

```bash
# Remove SSH key from authorized_keys
for replica in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$replica "sed -i '/old-key/d' ~/.ssh/authorized_keys"
done
```

### 4.2 Secret Rotation

**GSM Secrets** (used by replicas):

```bash
# Fetch secrets from Google Secret Manager
bash scripts/fetch-gsm-secrets.sh

# Verify secrets loaded
env | grep OIDC_ISSUER_URL  # Should show value
```

---

## 5. Monitoring and Alerting

### 5.1 Grafana Dashboard

**Access**: http://192.168.168.31:3000

**Default Dashboards**:
- Cluster Health (11 panels, < 10 second health determination)
- Node Exporter (CPU, memory, disk)
- Prometheus (scrape targets, up/down status)

**Setup** (if not configured):
```bash
bash scripts/ops/deploy-grafana-dashboards.sh
```

### 5.2 Alert Rules

**SLA-Based Alerts**:
- Deployment success rate < 99.9%
- Failover time > 30 seconds
- Health check latency > 500ms
- Database replication lag > 10 MB

**Deploy alert rules**:
```bash
bash scripts/ops/deploy-sla-metrics.sh
```

### 5.3 Alert Notifications

| Severity | Channel | Escalation |
|----------|---------|-----------|
| **CRITICAL** | PagerDuty | Immediate page |
| **HIGH** | Slack #ops-critical | 5-min escalation |
| **MEDIUM** | Email | 15-min escalation |
| **LOW** | Slack #infrastructure | No escalation |

---

## 6. Incident Response

### 6.1 Incident Severity Classification

**P0 (Critical)** - Immediate action
- Complete outage (both replicas down)
- Data loss detected
- Security breach

**P1 (High)** - Urgent
- One replica down (LB handling)
- Major feature broken
- Certificate expiring < 7 days

**P2 (Medium)** - Prompt
- Performance degradation
- Non-critical service issues
- Elevated error rates

**P3 (Low)** - Routine
- Minor issues
- Documentation gaps
- Tech debt

### 6.2 P0 Incident Activation

```bash
# 1. Post to #ops-critical
# 2. Create GitHub issue: gh issue create --title "P0: ..." --label P0,incident
# 3. Activate war room
# 4. Assign IC (Incident Commander)
# 5. Begin diagnosis (30 min SLA)
```

**Full procedure**: [INCIDENT-COMMUNICATION-GUIDE.md](INCIDENT-COMMUNICATION-GUIDE.md)

### 6.3 Failover Procedure

```bash
# Detect failover need
curl http://192.168.168.31:8080/health  # FAIL
curl http://192.168.168.42:8080/health  # OK → LB already redirected

# Manual failover (if needed)
bash docs/FAILOVER-RUNBOOK-SIMPLIFIED.md
```

---

## 7. Backup & Recovery

### 7.1 Database Backup

**Daily automated backup** (runs at 02:00 UTC):

```bash
# Manual backup
ssh akushnir@192.168.168.31 'docker compose exec postgres-primary \
  pg_dump -U postgres mydb | gzip' > backup-$(date +%Y%m%d).sql.gz

# Verify backup
gunzip -c backup-*.sql.gz | head -20  # Should show SQL DDL
```

**Backup location**: `/mnt/nas/backups/postgres/`

### 7.2 Point-in-Time Recovery (PITR)

```bash
# List backup files
ls -la /mnt/nas/backups/postgres/ | tail -5

# Restore from backup
psql -U postgres < backup-YYYYMMDD.sql

# Verify restore
psql -U postgres -c "SELECT COUNT(*) FROM users;"
```

---

## 8. Scaling & Capacity

### 8.1 Resource Usage Monitoring

```bash
# CPU & Memory
for replica in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$replica 'docker stats --no-stream | tail -1'
done

# Disk Space
for replica in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$replica 'df -h /'
done

# Network
ssh akushnir@192.168.168.31 'iftop -i eth0'  # If available
```

### 8.2 When to Scale

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU | > 80% | Increase container limits or reduce load |
| Memory | > 90% | Restart services or scale up |
| Disk | > 85% | Prune old data, increase storage |
| Network | > 1 Gbps sustained | Upgrade network or optimize queries |

---

## 9. Maintenance Windows

### 9.1 Scheduled Maintenance

**Every month** (2nd Thursday, 02:00-03:00 UTC):

```
- Database maintenance (VACUUM, ANALYZE)
- Disk cleanup (docker system prune)
- Certificate renewal check
- Backup restoration test
```

### 9.2 Maintenance Checklist

```bash
# 1. Announce maintenance window
# 2. Disable non-critical alerts
# 3. Perform maintenance tasks
# 4. Verify all services online
# 5. Re-enable alerts
# 6. Post completion summary
```

---

## 10. Runbooks Quick Reference

### Emergency Response

| Scenario | Runbook | Time |
|----------|---------|------|
| All services down | [Failover](FAILOVER-RUNBOOK-SIMPLIFIED.md) | 5-10 min |
| One replica offline | [Troubleshooting](ADVANCED-TROUBLESHOOTING-GUIDE.md) | 5-30 min |
| Data loss suspected | [Recovery](DEPLOYMENT-RUNBOOK-OPERATIONS.md#rollback-procedures) | 30-60 min |
| Certificate expired | [TLS Recovery](#3-certificate-management) | 5-10 min |
| Network unreachable | [Network Diagnostics](ADVANCED-TROUBLESHOOTING-GUIDE.md#network--load-balancing) | 10-30 min |

### Regular Operations

| Task | When | Time | Runbook |
|------|------|------|---------|
| Deploy update | Every push to main | 8-13 min | [Deployment](DEPLOYMENT-RUNBOOK-OPERATIONS.md) |
| Health check | Start of shift | 5 min | Section 1.1 |
| Certificate renewal | Auto, or if <7 days | 5 min | Section 3 |
| Backup restore test | Monthly | 30 min | Section 7.2 |
| Incident review | Within 24 hours of P0/P1 | 1 hour | [Incident Guide](INCIDENT-COMMUNICATION-GUIDE.md) |

---

## 11. Contact & Escalation

### On-Call Rotation

- **Primary**: akushnir
- **Secondary**: [Team Lead]
- **Manager**: [Director]

**Escalation Criteria**:
- No response in 5 minutes → escalate
- Not resolved in 30 minutes (P0) → escalate to Level 2
- Not resolved in 2 hours (P1) → escalate to management

### External Contacts

| Issue | Team | Response |
|-------|------|----------|
| Network down | Network Ops | 30 min |
| Hardware failure | Infrastructure | 1 hour |
| Security incident | Security Team | 15 min |
| Vendor issue | [Vendor] | Per SLA |

---

## 12. Tools & Commands

### Most Used Commands

```bash
# Quick health check
curl -I http://192.168.168.31:8080/health

# Check service status
ssh akushnir@192.168.168.31 'docker compose ps'

# View recent logs
ssh akushnir@192.168.168.31 'docker compose logs --tail 50'

# Restart a service
ssh akushnir@192.168.168.31 'docker compose restart <service-name>'

# Get into container
ssh akushnir@192.168.168.31 'docker compose exec <service-name> bash'
```

### Emergency Commands

```bash
# Force failover (if LB stuck)
ssh akushnir@192.168.168.42 'docker compose restart'

# Kill hung process
ssh akushnir@192.168.168.31 'docker kill <container-id>'

# Emergency rollback
git revert HEAD && git push origin main
```

---

## Document Maintenance

**Last Updated**: April 24, 2026  
**Next Review**: May 24, 2026  
**Owner**: Operations Team  
**Contributing Runbooks**:
- [DEPLOYMENT-RUNBOOK-OPERATIONS.md](DEPLOYMENT-RUNBOOK-OPERATIONS.md)
- [FAILOVER-RUNBOOK-SIMPLIFIED.md](FAILOVER-RUNBOOK-SIMPLIFIED.md)
- [ADVANCED-TROUBLESHOOTING-GUIDE.md](ADVANCED-TROUBLESHOOTING-GUIDE.md)
- [INCIDENT-COMMUNICATION-GUIDE.md](INCIDENT-COMMUNICATION-GUIDE.md)
- [PRODUCTION-SLA-METRICS.md](PRODUCTION-SLA-METRICS.md)
- [GRAFANA-DASHBOARD-SETUP.md](GRAFANA-DASHBOARD-SETUP.md)
- [AIR-GAPPED-DEPLOYMENT-COMPLETE.md](AIR-GAPPED-DEPLOYMENT-COMPLETE.md)

---

✅ **Status**: Production-Ready  
📞 **Support**: See Section 11 for contacts  
🔄 **Reviews**: Monthly on 2nd Thursday
