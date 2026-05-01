# Code-Server Operations Handbook - Team Training Guide

**Document**: Comprehensive Team Training Manual  
**Version**: Phase 10  
**Date**: April 30, 2026  
**Audience**: All Operations & DevOps Team Members

---

## Module 1: Infrastructure Overview (30 minutes)

### Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────┐
│                    Virtual Router (VRRP)                    │
│                   192.168.168.50 (Virtual)                  │
└────────┬────────────────────────────────────────────────────┘
         │
    ┌────┴─────┐
    │           │
┌───▼──────┐  ┌──▼───────┐
│ Primary  │  │  Replica  │
│ 192.168.168.31  │ 192.168.168.42  │
│ (Priority 100)  │ (Priority 90)   │
│ MASTER (Active) │ BACKUP (Standby)│
└──────────┘  └───────────┘
    │ 50        │ 50
    │ containers│ containers
    ▼           ▼
 [Docker]    [Docker]
```

**Key Points**:
- **Primary**: 192.168.168.31 (active, handles traffic)
- **Replica**: 192.168.168.42 (standby, ready to take over)
- **Virtual IP**: 192.168.168.50 (VRRP managed, always points to active)
- **Containers**: 50 per host (100 total, managed via Terraform)
- **HA Mechanism**: Keepalived monitors health, auto-failover on failure

### Three Layers of Management

**Layer 1: Infrastructure Code (Terraform)**
```
Terraform v1.14.9
├─ 50 Docker container definitions
├─ Terraform variables for both hosts
├─ SSH-based remote execution
└─ State file versioning
```

**Layer 2: Container Orchestration (Docker)**
```
Docker Engine (both hosts)
├─ 50 containers per host
├─ Health checks configured
├─ Resource limits set
└─ Network/volume management
```

**Layer 3: Operations Automation (Scripts)**
```
Bash Automation Scripts
├─ Validation (pre-apply checks)
├─ Monitoring (drift watchdog, SLO tracking)
├─ Remediation (auto-restart, disk cleanup)
└─ Observability (Prometheus exporter)
```

---

## Module 2: Daily Operations (45 minutes)

### The Daily Checklist

**Morning Standup (10 minutes)**:
```bash
# Step 1: Overall Health
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server
bash scripts/ci/validate-pre-apply.sh

# Expected: All 14 checks PASS ✓
```

**Checks Performed** (by validate-pre-apply.sh):
1. Terraform syntax validation
2. SSH connectivity to both hosts
3. Docker availability
4. PostgreSQL health
5. Redis availability
6. Disk space (>10% free)
7. Network connectivity
8. System resources (CPU, memory)
9. Terraform variables loading
10. Keepalived status
11. Keepalived VRRP state
12. Active container count
13. Health check status
14. System load average

```bash
# Step 2: Quick Dashboard Check
# Open browser to: http://localhost:3000/d/code-server-ops
# Look for:
#   ✓ Drift gauge: GREEN (0 resources)
#   ✓ Health gauge: GREEN (0 unhealthy)
#   ✓ Disk trend: Below 70% line
#   ✓ SLO table: All metrics ≥95%

# Step 3: Recent Alerts
tail -20 /tmp/code-server-remediation.log
# Look for: Any ERROR lines? Any repeated WARNINGs?

# Result: If all green → Good morning! ✓
```

**After Deployment (15 minutes)**:
```bash
# Step 1: Validate pre-apply checks (same as morning)
bash scripts/ci/validate-pre-apply.sh

# Step 2: Verify deployment idempotency
bash scripts/ci/check-docker-compose-idempotency.sh

# Step 3: Check SLO metrics
./scripts/ops/track-slo-metrics.sh

# Expected output:
# Availability: 99% (target ≥99%)
# Deployment Success: 95% (target ≥95%)
# Drift-Free: 100% (target ≥100%)
# Health Check: 98% (target ≥98%)
```

**Evening Review (5 minutes)**:
```bash
# Check for any issues during the day
grep "ERROR\|WARNING" /tmp/code-server-remediation.log | tail -10

# Disk space trend
df -h /home

# Container restart count (if auto-remediation enabled)
grep "RESTART_CONTAINER.*SUCCESS" /tmp/code-server-remediation.log | wc -l
```

---

## Module 3: Incident Response (60 minutes)

### The 8 Incident Playbooks

**Playbook 1: Container Unhealthy**

*Symptoms*: One or more containers showing as "unhealthy" in `docker ps`

*Steps*:
```bash
# 1. Identify unhealthy containers
docker ps | grep "unhealthy\|exited"

# 2. Check container logs
docker logs <container-name> --tail=50

# 3. Manual restart
docker restart <container-name>

# 4. Verify recovery
docker ps | grep <container-name>

# 5. If still failing
docker inspect <container-name> | grep -A5 '"Health"'
docker stats <container-name>  # Check resource usage
```

*Resolution Time*: 5-15 minutes  
*Prevention*: Auto-remediation (if enabled) restarts in 5-minute cycle

---

**Playbook 2: Terraform Drift**

*Symptoms*: Drift detected in monitoring logs or dashboard

*Steps*:
```bash
# 1. Identify drifted resources
cd terraform/environments/private
terraform plan -json | jq -s 'map(select(.type == "resource_drift"))'

# 2. Review changes carefully
terraform plan

# 3. If safe, apply changes
terraform apply -auto-approve

# 4. Verify with health check
bash scripts/ci/validate-pre-apply.sh
```

*Resolution Time*: 10-30 minutes  
*Prevention*: Drift watchdog alerts; auto-remediation (if enabled)

---

**Playbook 3: High Disk Space**

*Symptoms*: Dashboard shows >85% disk usage

*Steps*:
```bash
# 1. Check usage
df -h /home
du -sh /home/* | sort -rh

# 2. Find largest consumers
docker images --format "{{.Size}}\t{{.Repository}}"
docker ps -s  # Container sizes

# 3. Clean up Docker artifacts
docker system prune -af --volumes

# 4. Verify cleanup
df -h /home

# 5. If still high, clean logs
find /home/akushnir/code-server -name "*.log" -mtime +7 -delete
```

*Resolution Time*: 2-5 minutes  
*Prevention*: Auto-remediation (if enabled) at >85%

---

**Playbook 4: Container Parity Mismatch**

*Symptoms*: Primary and replica have different container counts

*Steps*:
```bash
# 1. Check both hosts
ssh akushnir@192.168.168.31 'docker ps | wc -l'
ssh akushnir@192.168.168.42 'docker ps | wc -l'

# 2. List containers on each
ssh akushnir@192.168.168.31 'docker ps --format "{{.Names}}"' > primary.txt
ssh akushnir@192.168.168.42 'docker ps --format "{{.Names}}"' > replica.txt

# 3. Find differences
diff primary.txt replica.txt

# 4. Reapply Terraform to sync
cd terraform/environments/private
terraform apply -auto-approve

# 5. Verify parity
./scripts/ops/export-prometheus-metrics.sh metrics | grep "parity"
```

*Resolution Time*: 15-30 minutes  
*Cause*: Usually stale Terraform state or manual container changes

---

**Playbook 5: Keepalived Down**

*Symptoms*: VRRP failover occurred or keepalived service stopped

*Steps*:
```bash
# 1. Check Keepalived status on primary
ssh akushnir@192.168.168.31 'systemctl status keepalived'

# 2. Check VRRP status
ssh akushnir@192.168.168.31 'ip addr show | grep 192.168.168.50'
# Should show: MASTER on primary, BACKUP on replica

# 3. If keepalived crashed
ssh akushnir@192.168.168.31 'systemctl restart keepalived'

# 4. Verify failover didn't occur
ssh akushnir@192.168.168.31 'systemctl status keepalived'

# 5. Check replica is still standby
ssh akushnir@192.168.168.42 'ip addr show | grep 192.168.168.50'
# Should NOT have the IP (replica is backup)
```

*Resolution Time*: 5-10 minutes  
*Critical*: Without Keepalived, no automatic failover to replica

---

**Playbook 6: SSH Connection Failed**

*Symptoms*: Cannot SSH to one of the hosts

*Steps*:
```bash
# 1. Check network connectivity
ping 192.168.168.31
ping 192.168.168.42

# 2. Check SSH service
ssh -vvv akushnir@192.168.168.31 'echo test'
# Look for: "Connection refused" vs "Connection timeout"

# 3. If refused (service down)
# → Physical access required (out of scope)

# 4. If timeout (network issue)
# → Check firewall/routing (infrastructure team)

# 5. Fallback to replica
ssh akushnir@192.168.168.42
# Can still manage from replica if primary SSH down
```

*Resolution Time*: 5-30 minutes (depends on infrastructure)

---

**Playbook 7: Terraform Plan Timeout**

*Symptoms*: `terraform plan` hangs or times out (>5 minutes)

*Steps*:
```bash
# 1. Kill the hanging process
Ctrl+C

# 2. Check Terraform state
cd terraform/environments/private
terraform validate

# 3. Try again with timeout
timeout 60 terraform plan -json | head -100

# 4. If still hanging, check remote hosts
ssh akushnir@192.168.168.31 'docker ps' | head -5
ssh akushnir@192.168.168.42 'docker ps' | head -5

# 5. If hosts unreachable
# → May need infrastructure team support
```

*Resolution Time*: 10-20 minutes  
*Prevention*: Terraform plan is fast normally; hangs indicate network issues

---

**Playbook 8: Database Connection Failed**

*Symptoms*: PostgreSQL or Redis connection fails, alerts trigger

*Steps*:
```bash
# 1. Check container health
docker ps | grep postgres
docker ps | grep redis

# 2. Check container logs
docker logs postgresql | tail -20
docker logs redis | tail -20

# 3. Verify listening ports
docker port postgresql
docker port redis

# 4. Test connection
docker exec postgresql psql -U postgres -c "SELECT 1"
docker exec redis redis-cli ping

# 5. If connection works but container unhealthy
docker restart postgresql
docker restart redis
```

*Resolution Time*: 5-15 minutes  
*Critical*: Database failures affect all applications

---

### How to Use the Playbooks

1. **Identify Issue**: Match symptoms to one of the 8 playbooks
2. **Follow Steps**: Execute commands in order
3. **Verify Resolution**: Run the "Verify" section
4. **Document**: Log what happened and when (for post-mortems)
5. **Escalate if Needed**: Follow emergency procedures

---

## Module 4: Monitoring & Observability (45 minutes)

### Three Monitoring Layers

**Layer 1: Logs (Real-time Events)**

```bash
# Remediation actions (auto-restarts, disk cleanup)
tail -f /tmp/code-server-remediation.log

# Drift detection (every 5 minutes)
tail -f /tmp/code-server-watchdog/*.log

# SLO tracking (daily)
tail -f /tmp/code-server-slo-*.log
```

**Layer 2: Metrics (Historical Data)**

Access Prometheus: `http://localhost:9090`

*Key queries*:
```
# Drift trend
code_server_terraform_drift_resources

# Container health over time
sum(code_server_unhealthy_containers)

# Disk usage trend
code_server_disk_usage_percent{host="primary"}

# SLO compliance
code_server_slo_availability_percent
```

**Layer 3: Dashboards (Visual Summary)**

Access Grafana: `http://localhost:3000/d/code-server-ops`

*Panels*:
- Terraform Drift Gauge (should be 0-1)
- Unhealthy Containers Gauge (should be 0)
- Availability SLO Gauge (should be ≥99%)
- Disk Usage Trend (should be <70%)
- Container Health Pie Chart (should be mostly green)
- SLO Compliance Table (all ≥95%)

---

### Alert Types & Responses

**INFO Alerts** (Green):
```
- Container restarted successfully
- Disk space cleaned up
- Terraform applied successfully
```
*Response*: Monitor, no action needed

**WARNING Alerts** (Orange):
```
- Container restarted 5 times/hour
- Disk cleanup removing large amounts
- Drift approaching threshold
```
*Response*: Investigate root cause, may need manual fix

**ERROR Alerts** (Red):
```
- Container restart failed
- Disk cleanup insufficient
- Terraform apply failed
- Database connection lost
```
*Response*: URGENT - Follow incident playbook immediately

---

## Module 5: Automation & Self-Healing (30 minutes)

### Auto-Remediation Strategies

**Strategy 1: Container Restart** ✅ ENABLED BY DEFAULT

*How it works*:
```
Every 5 minutes:
1. Check both hosts for unhealthy containers
2. Restart any found (max 5 per container per hour)
3. Skip critical containers (PostgreSQL, Redis, Keepalived)
4. Send alert on each action
5. Log to /tmp/code-server-remediation.log
```

*When it activates*: Container exits with error  
*Time to recovery*: 5-10 minutes  
*Risk level*: LOW (rate-limited, protected resources)

**Strategy 2: Disk Cleanup** ✅ ENABLED BY DEFAULT

*How it works*:
```
Every 5 minutes:
1. Check disk usage on both hosts
2. If >85%, run docker system prune
3. Measure before/after
4. Send alert with cleanup results
5. Log to /tmp/code-server-remediation.log
```

*When it activates*: Disk usage exceeds 85%  
*Time to recovery*: 10-30 minutes  
*Risk level*: LOW (only removes unused artifacts)

**Strategy 3: Terraform Drift** ❌ DISABLED BY DEFAULT

*How it works* (if enabled):
```
Every 5 minutes:
1. Check for terraform resource_drift
2. If drift <10 resources, apply terraform
3. If drift >10, block (too risky)
4. Send alert with results
5. Log to /tmp/code-server-remediation.log
```

*When to enable*: After 30+ days of monitoring  
*Risk level*: HIGH (causes infrastructure changes)  
*Requires*: SAFE_MODE=false, manual opt-in

---

### Safety Mechanisms

**Mechanism 1: Rate Limiting**
```
No container restarted >5 times per hour
Prevents infinite restart loops
Hourly counter resets
```

**Mechanism 2: Protected Resources**
```
DO_NOT_AUTO_RESTART = postgresql, redis, keepalived
These require manual review before restart
```

**Mechanism 3: Dry-Run Mode**
```
DRY_RUN=true: See what would happen without changes
Perfect for testing before production
```

**Mechanism 4: Safe Mode**
```
SAFE_MODE=true: Blocks dangerous operations (drift)
Default setting for safety
```

---

## Module 6: Deployment Procedures (45 minutes)

### Pre-Deployment Checklist

**Before ANY deployment**:

```bash
# 1. Run pre-apply validation
bash scripts/ci/validate-pre-apply.sh
# Expected: All 14 checks PASS

# 2. Review Terraform changes
cd terraform/environments/private
terraform plan -json | jq '.[] | select(.type == "resource_drift")'
# Expected: Empty (no drift) or acceptable changes

# 3. Check current health
docker ps | wc -l
df -h /home

# 4. Backup current state
git status
git add -A
git commit -m "backup before deployment"
```

### Deployment Steps

**Step 1: Dry-Run Deployment**
```bash
cd /home/akushnir/code-server
timeout 60 bash scripts/ops/full-deployment-test.sh --dry-run
```

**Step 2: Review Plan Output**
```
Expected: 6 test phases PASS/PASS/PASS/PASS/PASS/PASS
If any FAIL: Stop! Investigate before proceeding
```

**Step 3: Apply Changes**
```bash
cd terraform/environments/private
terraform apply

# Or deploy specific containers:
docker-compose -f ../../docker-compose.enterprise.yml up -d <service-name>
```

**Step 4: Verify Deployment**
```bash
bash scripts/ci/validate-pre-apply.sh
./scripts/ops/track-slo-metrics.sh
docker ps | wc -l  # verify count
```

**Step 5: Monitor for Issues**
```bash
tail -f /tmp/code-server-remediation.log
# Watch for any errors for next 15 minutes
```

---

## Module 7: Disaster Recovery (30 minutes)

### Backup Strategy

**Automatic Backups**:
- Git history (all changes versioned)
- Terraform state (in repository)
- Container configs (in docker-compose files)
- Metrics (15 days in Prometheus)

**Manual Backups** (recommended):
```bash
# Backup database
docker exec postgresql pg_dump -U postgres | gzip > backup-$(date +%Y%m%d).sql.gz

# Backup Redis
docker exec redis redis-cli BGSAVE
docker cp redis:/data/dump.rdb ./backup-redis-$(date +%Y%m%d).rdb

# Backup Terraform state
cp terraform/environments/private/terraform.tfstate \
   backup-tfstate-$(date +%Y%m%d).json
```

### Recovery Procedures

**Scenario: Container Data Lost**
```bash
# 1. Restore from database backup
docker exec postgresql psql -U postgres < backup-YYYYMMDD.sql.gz

# 2. Restore Redis
docker cp backup-redis-YYYYMMDD.rdb redis:/data/dump.rdb
docker exec redis redis-cli MODULE LOAD
```

**Scenario: Terraform State Corrupted**
```bash
# 1. Restore from backup
cp backup-tfstate-YYYYMMDD.json terraform/environments/private/terraform.tfstate

# 2. Refresh state
terraform refresh

# 3. Apply to sync
terraform apply
```

**Scenario: Complete Host Failure**
```bash
# 1. If primary (192.168.168.31) fails
# → Replica (192.168.168.42) takes over via Keepalived
# → VRRP automatically switches to replica
# → Service continues on replica

# 2. Restore primary
# → Redeploy via Terraform
# → Rejoin cluster
# → Keepalived brings back to primary
```

---

## Module 8: Troubleshooting Reference (60 minutes)

### Common Issues & Solutions

**Issue 1: Prometheus not scraping metrics**

*Symptoms*: Grafana shows "No data"

*Fix*:
```bash
# 1. Check Prometheus config
cat monitoring/prometheus.yml | grep -A5 "scrape_configs"

# 2. Verify metrics exporter running
curl http://localhost:9091/metrics | head -10

# 3. Check Prometheus targets
curl http://localhost:9090/api/v1/targets
# Look for "state: 'down'"

# 4. Restart Prometheus
docker restart prometheus
```

---

**Issue 2: Alerts not being sent**

*Symptoms*: Alert event but no Slack/email received

*Fix*:
```bash
# 1. Check alert config
cat .alerts/config.env | grep "ALERT_.*_ENABLED"

# 2. Verify webhook/email
cat .alerts/config.env | grep "SLACK_WEBHOOK_URL\|EMAIL_TO"

# 3. Test alert routing
./scripts/lib/alert-router.sh send_alert ERROR test "Test message" "{}"

# 4. Check alert history
grep "test" /tmp/code-server-remediation.log
```

---

**Issue 3: Container keeps restarting**

*Symptoms*: Container restarts every minute

*Fix*:
```bash
# 1. Check container logs
docker logs <container> --tail=50

# 2. Look for:
# - "Out of memory" → Increase memory limit
# - "Permission denied" → Check file permissions
# - "Connection refused" → Dependency not starting

# 3. Add to protected list (temporary)
# Edit .remediation/config.env
# Add container to DO_NOT_AUTO_RESTART

# 4. Fix underlying issue
# - Config issue? Fix config
# - Resource issue? Increase limits
# - Dependency? Ensure it starts first

# 5. Remove from protected list after fix
```

---

## Module 9: Team Roles & Responsibilities (15 minutes)

### Role 1: On-Call Operator
- Monitor dashboards hourly
- Respond to alerts within 5 minutes
- Follow incident playbooks
- Document issues

### Role 2: Senior SRE
- Train new operators
- Review incident logs weekly
- Adjust thresholds based on patterns
- Mentor on-call team

### Role 3: Platform Engineer
- Develop new automation features
- Optimize scripts for performance
- Review and approve changes
- Lead disaster recovery drills

### Role 4: Escalation Contact
- Available for critical issues
- Has infrastructure access
- Can approve major changes
- Coordinates with external teams

---

## Module 10: Knowledge Check Quiz (15 minutes)

**Question 1**: What are the 3 auto-remediation strategies?
- Container restart, disk cleanup, terraform drift ✓

**Question 2**: How often does auto-remediation run?
- Every 5 minutes ✓

**Question 3**: What is the max container restarts per hour?
- 5 restarts per container ✓

**Question 4**: Which containers are protected from auto-restart?
- PostgreSQL, Redis, Keepalived ✓

**Question 5**: What does SAFE_MODE do?
- Blocks dangerous operations (like terraform drift) ✓

**Question 6**: How to test auto-remediation without making changes?
- Set DRY_RUN=true ✓

**Question 7**: What's the virtual IP for VRRP?
- 192.168.168.50 ✓

**Question 8**: Which host is MASTER by default?
- Primary (192.168.168.31) ✓

**Question 9**: What are the 8 incident playbooks about?
- Container health, drift, disk space, parity, keepalived, SSH, terraform, database ✓

**Question 10**: What SLO target for availability?
- ≥99% ✓

---

## Appendix: Quick Command Reference

```bash
# Health check
bash scripts/ci/validate-pre-apply.sh

# View dashboards
# Grafana: http://localhost:3000/d/code-server-ops
# Prometheus: http://localhost:9090

# Check alerts
tail -f /tmp/code-server-remediation.log

# View SLO metrics
./scripts/ops/track-slo-metrics.sh

# List containers (both hosts)
docker ps

# SSH to hosts
ssh akushnir@192.168.168.31  # Primary
ssh akushnir@192.168.168.42  # Replica
ssh akushnir@192.168.168.50  # Virtual (VRRP)

# Check Terraform
cd terraform/environments/private
terraform plan
terraform apply

# View logs
docker logs <container-name>

# Restart container
docker restart <container-name>

# Clean disk
docker system prune -af --volumes

# Test auto-remediation (dry-run)
DRY_RUN=true ./scripts/ops/auto-remediation-engine.sh
```

---

**Status**: ✅ **TRAINING COMPLETE**

All team members should complete all 10 modules before going live.

Estimated time: 6 hours (can be spread across multiple days)

