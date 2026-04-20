# Operations Checklist - Daily/Weekly/Monthly
## kushin77/code-server Deployment #950

---

## 🔵 DAILY HEALTH CHECK (5 minutes)
Run this check each morning before opening to users.

### SSH Access
- [ ] Can SSH to 192.168.168.31: `ssh akushnir@192.168.168.31`
- [ ] Can SSH to 192.168.168.42: `ssh akushnir@192.168.168.42`

### Container Status
```bash
cd /home/akushnir/code-server-enterprise
docker compose ps
```
- [ ] code-server: HEALTHY
- [ ] caddy: UP
- [ ] oauth2_proxy: HEALTHY
- [ ] postgres_prod: HEALTHY
- [ ] redis_prod: UP
- [ ] prometheus_prod: UP
- [ ] grafana_prod: UP
- [ ] alertmanager_prod: UP
- [ ] jaeger_prod: UP

### Network Accessibility
```bash
curl -s http://192.168.168.31:8080 > /dev/null && echo "✓ code-server" || echo "✗ code-server"
curl -s http://192.168.168.31:9090 > /dev/null && echo "✓ Prometheus" || echo "✗ Prometheus"
curl -s http://192.168.168.31:3000 > /dev/null && echo "✓ Grafana" || echo "✗ Grafana"
curl -s http://192.168.168.31:4180/health > /dev/null && echo "✓ OAuth" || echo "✗ OAuth"
```
- [ ] All endpoints responding (4/4 ✓)

### Authentication Test
- [ ] OAuth2-proxy health endpoint: `curl http://192.168.168.31:4180/health` → 200 OK
- [ ] Browser can reach code-server: http://code-server.kushnir.cloud:8080
- [ ] OAuth login flow completes without redirect loops

### Database Check
```bash
docker exec postgres_prod psql -U postgres -c "SELECT count(*) FROM code_server_sessions;" 2>/dev/null
```
- [ ] PostgreSQL responding
- [ ] Redis responding: `docker exec redis_prod redis-cli ping` → PONG

### Alert Status
- [ ] Visit http://192.168.168.31:9093
- [ ] No firing alerts (or only expected ones)
- [ ] If alerts firing, investigate and document

### Resource Usage (Check if any service over threshold)
```bash
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```
- [ ] CPU usage < 70% for all containers
- [ ] Memory usage < 80% for all containers
- [ ] Disk usage: `df -h /` → < 90% used

### Sign-Off
- [ ] Date: ____________
- [ ] Time: ____________
- [ ] Operator: ____________
- [ ] Status: ☐ PASS ☐ ISSUES FOUND (Document below)

**Issues Found (if any)**:
```
[Space for notes]
```

---

## 🟠 WEEKLY HEALTH CHECK (30 minutes)
Run this check every Monday morning.

### Review Past Week's Alerts
```bash
# Check AlertManager for past 7 days
curl -s 'http://localhost:9093/api/v1/alerts?filter=state:resolved' | jq . | head -50
```
- [ ] Review all resolved alerts from past week
- [ ] Document any recurring issues
- [ ] Check if any alerts indicate system problems

### Backup Validation
```bash
ls -lh /home/akushnir/code-server-enterprise/backups/ | head -10
```
- [ ] Latest backup from past 24 hours exists
- [ ] Backup size reasonable (> 40 MB, < 100 MB)
- [ ] Backup timestamp recent

### Database Replication Check
```bash
# SSH to primary (31)
ssh akushnir@192.168.168.31
docker exec postgres_prod psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```
- [ ] Replication lag < 100ms
- [ ] Replica (192.168.168.42) showing in output
- [ ] All LSN positions progressing

### Disk Space Trend
```bash
df -h /
# Compare with last week's note
```
- [ ] Disk usage is not growing rapidly
- [ ] Current usage: ____ % of total
- [ ] If trend is bad, investigate and clean up

### SSL/TLS Certificate Check
```bash
# Caddy auto-renews, but verify manually
curl -I https://code-server.kushnir.cloud 2>&1 | grep -i "certificate\|expire"
```
- [ ] TLS certificate is valid
- [ ] Certificate expiration is > 30 days away
- [ ] No certificate warnings

### Security Scan (Optional)
```bash
# Run vulnerability scan on running containers
docker scan code_server_prod
docker scan postgres_prod
docker scan redis_prod
```
- [ ] No critical CVEs found
- [ ] Document any high-severity issues
- [ ] Plan remediation if needed

### Performance Baselines (Compare with last week)
- [ ] Code-server response time: _______ ms (baseline: ~150ms)
- [ ] OAuth login time: _______ seconds (baseline: 2-4s)
- [ ] Database query time: _______ ms (baseline: <50ms)

### Sign-Off
- [ ] Date: ____________
- [ ] Time: ____________
- [ ] Operator: ____________
- [ ] Status: ☐ PASS ☐ ISSUES FOUND ☐ REQUIRES ATTENTION

**Notes**:
```
[Space for observations and recommendations]
```

---

## 🔴 MONTHLY MAINTENANCE (2 hours)
Run this check on the 1st of each month.

### Critical Update Check
```bash
# Check for Docker image updates
docker pull code-server:latest
docker pull postgres:15
docker pull redis:7
```
- [ ] Check if newer versions available
- [ ] Document version changes
- [ ] Plan update schedule if necessary

### Old Backup Cleanup
```bash
# Delete backups older than 30 days
find /home/akushnir/code-server-enterprise/backups -name "*.tgz" -mtime +30 -ls
# Manual verification before delete:
find /home/akushnir/code-server-enterprise/backups -name "*.tgz" -mtime +30 -delete
```
- [ ] Old backups deleted (kept most recent 30)
- [ ] Storage space verified

### Log Rotation
```bash
# Check if logs are growing excessively
du -sh /var/lib/docker/containers/*/logs/
```
- [ ] Log files not excessively large
- [ ] Consider rotating/archiving old logs

### Database Optimization
```bash
# Run VACUUM and ANALYZE on PostgreSQL
ssh akushnir@192.168.168.31
docker exec postgres_prod psql -U postgres -c "VACUUM ANALYZE code_server;"
```
- [ ] Database optimization completed
- [ ] Query performance validated post-optimization

### Failover Readiness Drill (Non-Disruptive)
```bash
# Verify failover is ready (don't trigger actual failover)
ssh akushnir@192.168.168.31
bash scripts/ops/failover-status.sh
```
- [ ] Failover status: READY
- [ ] Replication lag acceptable
- [ ] Both hosts online and responsive

### Credentials Rotation (If Required)
```bash
# Rotate OAuth client secret in Google Console
# Update .env with new credentials
# Restart oauth2-proxy
docker restart oauth2_proxy_prod
```
- [ ] Credentials validated and working
- [ ] Old credentials revoked
- [ ] No service interruption during rotation

### Disaster Recovery Document Review
- [ ] Review disaster recovery runbook
- [ ] Verify all links in documentation are valid
- [ ] Test one backup restoration (dry-run if possible):
  ```bash
  # On a test system (not production):
  tar xzf backup.tgz -C /tmp/test/
  # Verify contents
  ls -la /tmp/test/
  ```
- [ ] Document any findings

### Performance Report
```bash
# Generate monthly performance summary
echo "=== Monthly Performance Report ==="
echo "Uptime (past 30 days):"
docker inspect code_server_prod | grep StartedAt

echo "Service restarts this month:"
docker logs code_server_prod --timestamps 2>&1 | grep "container start" | wc -l

echo "Total requests (from Prometheus):"
curl -s 'http://localhost:9090/api/v1/query?query=increase(http_requests_total[30d])' | jq
```
- [ ] Performance report generated
- [ ] Any concerning trends documented
- [ ] Recommendations for optimization noted

### Security Review
- [ ] Review access logs: `docker logs caddy_prod | tail -100`
- [ ] Check for suspicious activity
- [ ] Verify no unauthorized access attempts
- [ ] Review and update firewall rules if needed

### Documentation Updates
- [ ] Update this checklist if procedures changed
- [ ] Update runbooks if any process improved
- [ ] Document any issues found and resolutions applied

### Sign-Off
- [ ] Date: ____________
- [ ] Time: ____________
- [ ] Operator: ____________
- [ ] Manager Review: ☐ YES ☐ NO

**Key Findings & Recommendations**:
```
[Space for detailed monthly report]
```

---

## ⚠️ INCIDENT RESPONSE CHECKLIST

### IF SERVICE IS DOWN (Act immediately)

1. **Verify the problem**
   - [ ] Try accessing from different network/device
   - [ ] Check if problem is local or system-wide
   - [ ] Timestamp of first detection: ____________

2. **Assess scope**
   - [ ] Which service is down? ____________
   - [ ] Is it a cascading failure? (YES/NO)
   - [ ] Estimated impact: _____ users/services affected

3. **Begin triage**
   ```bash
   ssh akushnir@192.168.168.31
   docker compose logs --tail=100 <failed-service>
   docker inspect <failed-container>
   docker stats
   free -h && df -h
   ```
   - [ ] Collect logs from all services
   - [ ] Check resource usage (CPU/Memory/Disk)
   - [ ] Document error messages

4. **Attempt recovery** (non-disruptive first)
   - [ ] Restart single service: `docker restart <service>`
   - [ ] Wait 2 minutes for recovery
   - [ ] If still failing, try full restart: `docker compose restart`
   - [ ] If still failing, escalate to fallback host

5. **Activate fallback host (if needed)**
   - [ ] SSH to 192.168.168.42 (replica)
   - [ ] Verify services running on replica
   - [ ] If promoting to primary:
     ```bash
     docker exec postgres_replica psql -U postgres -c "SELECT pg_promote();"
     # Update DNS to point to 192.168.168.42
     ```
   - [ ] Verify failover successful

6. **Post-incident**
   - [ ] Root cause identified: ____________
   - [ ] Time to recovery: _______ minutes
   - [ ] Permanent fix applied? (YES/NO)
   - [ ] If YES, describe: ____________
   - [ ] Create GitHub issue if bug found
   - [ ] Update runbook with learnings

---

## 📋 SIGN-OFF SHEETS (Print & Archive)

### Daily Checklist Archive
```
Date       | Operator    | Status   | Issues?
-----------|-------------|----------|----------
2026-04-23 | John Doe    | PASS     | None
2026-04-24 | Jane Smith  | PASS     | OAuth lag
...
```

### Weekly Checklist Archive
```
Week Of    | Operator    | Pass/Fail | Action Items
-----------|-------------|-----------|------------------
2026-04-22 | Team       | PASS      | None
2026-04-29 | Team       | PASS      | Update docs
...
```

### Monthly Checklist Archive
```
Month      | Operator    | Pass/Fail | Major Findings
-----------|-------------|-----------|------------------
Apr 2026   | Lead SRE    | PASS      | Backup successful, all OK
May 2026   | Lead SRE    | PASS      | Performance stable
...
```

---

## 🎯 ESCALATION PATH

### If you cannot resolve an issue:

**Tier 1 Escalation** (Contact SRE Team Lead)
- [ ] Document the problem
- [ ] Provide logs and error messages
- [ ] Describe recovery attempts
- [ ] Expected timeframe for response: 15 minutes

**Tier 2 Escalation** (Contact Platform Engineering)
- [ ] If Tier 1 cannot resolve within 1 hour
- [ ] Provide full incident summary
- [ ] Include dashboard screenshots
- [ ] Expected timeframe: 30 minutes

**Tier 3 Escalation** (Contact System Owner)
- [ ] If Tier 2 cannot resolve within 2 hours
- [ ] Production emergency
- [ ] Expected timeframe: immediate

**GitHub Issue** (Document for next sprint)
- [ ] Open issue for known problems
- [ ] Use template: `ops/issue-template.md`
- [ ] Label with `severity:high` if blocking users
- [ ] Assign to relevant team

---

## 📞 QUICK CONTACTS

| Role | Name | Email | Phone |
|------|------|-------|-------|
| SRE Team Lead | TBD | sre-lead@company.com | 555-0101 |
| Platform Engineering | TBD | platform-eng@company.com | 555-0102 |
| System Owner (akushnir) | Alex Kushnir | alex@company.com | 555-0100 |

---

## 📅 SCHEDULE TEMPLATE

### Week of April 22, 2026
```
Monday:
  [ ] Daily health check (john.doe)
  [ ] Weekly review (sre-team)

Tuesday-Friday:
  [ ] Daily health check (rotation: jane.smith, bob.jones, ...)

Next Monday (April 29):
  [ ] Weekly review
  [ ] Database optimization
  [ ] Backup validation
```

### Assign operators to each day to ensure coverage

---

## 📖 REFERENCE DOCUMENTATION

- **Deployment Summary**: [DEPLOYMENT-EPIC-950-SUMMARY-APRIL-2026.md](./DEPLOYMENT-EPIC-950-SUMMARY-APRIL-2026.md)
- **Validation Runbook**: [POST-DEPLOYMENT-VALIDATION-APRIL-2026.md](./POST-DEPLOYMENT-VALIDATION-APRIL-2026.md)
- **Quick Reference**: [QUICK-REFERENCE-OPERATIONS-GUIDE.md](./QUICK-REFERENCE-OPERATIONS-GUIDE.md)
- **GitHub Issues**: https://github.com/kushin77/code-server/issues
- **Runbooks**: `/docs/runbooks/`

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | Apr 22, 2026 | Initial creation | Copilot |
| | | | |

---

**Status**: ✅ READY FOR USE

Print and post on office wall or share with operations team.
Keep digital copy updated as procedures change.
