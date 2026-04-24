# POST-DEPLOYMENT OPERATIONAL MONITORING GUIDE

**Date:** April 24, 2026  
**Prepared For:** Production Operations Team  
**Status:** Ready for Implementation  

---

## Executive Summary

Comprehensive guide for operating and monitoring the production deployment. All infrastructure is deployed, automated, and ready for monitoring and optimization.

---

## Immediate Monitoring Procedures (0-15 minutes post-deployment)

### Step 1: Verify GitHub Actions Deployment Workflow

**URL:** https://github.com/kushin77/code-server/actions?query=branch%3Amain

**What to Look For:**
- Workflow name: gitops-cd.yml (Continuous Deployment)
- Status: Should show "in progress" or "completed"
- Latest run should match commit 119b1ff8 or later
- All steps should show green checkmarks

**Expected Workflow Sequence:**
```
✅ Checkout code
✅ Set up environment
✅ SSH to production hosts
✅ Pull latest Docker images
✅ Execute docker-compose up -d
✅ Run health checks
✅ Verify OPA policies
✅ Generate deployment report
```

### Step 2: Access Grafana Dashboards

**URL:** https://grafana.code-server.local (or configured IP:3000)

**Default Credentials:**
- Username: admin
- Password: See infrastructure secrets management

**Navigation Steps:**
1. Login to Grafana
2. Click "Dashboards" in sidebar
3. Verify 5 dashboards are listed:
   - OPA Policy Monitoring
   - Memory Engine Monitoring
   - Kafka Event Bus & Activity Feed
   - Execution Scheduler Monitoring
   - System Observability

**Initial Observations:**
- Dashboards may show "no data" for first 2-5 minutes (services starting)
- Metrics will begin appearing as services initialize
- After 10 minutes, all panels should display data

### Step 3: Monitor Service Startup

**SSH to Production Host:**
```bash
ssh akushnir@192.168.168.31

# Check service status
docker-compose ps

# Expected output:
# NAME             STATUS              PORTS
# code-server      Up 1 minute         0.0.0.0:8080->8080/tcp
# opa-server       Up 1 minute         0.0.0.0:8181->8181/tcp
# kafka            Up 1 minute         0.0.0.0:9092->9092/tcp
# postgres         Up 1 minute         0.0.0.0:5432->5432/tcp
# prometheus       Up 1 minute         0.0.0.0:9090->9090/tcp
# grafana          Up 1 minute         0.0.0.0:3000->3000/tcp
# loki             Up 1 minute         0.0.0.0:3100->3100/tcp
# jaeger           Up 1 minute         0.0.0.0:16686->16686/tcp
```

### Step 4: Verify Health Endpoints

**Test each service endpoint:**

```bash
# OPA Policy Engine
curl http://localhost:8181/health

# Prometheus
curl http://localhost:9090/api/v1/status

# Grafana
curl http://localhost:3000/api/health

# Loki
curl http://localhost:3100/ready

# Kafka (via docker-compose)
docker-compose exec kafka kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# PostgreSQL
docker-compose exec postgres psql -U postgres -d paperclip -c "SELECT version();"
```

**Expected Response:** All endpoints should return 200 OK or similar success status

---

## Short-Term Monitoring (15 minutes - 2 hours post-deployment)

### Phase 1: Verify Metrics Collection (15-30 minutes)

**In Grafana, check each dashboard:**

1. **OPA Policy Monitoring**
   - [ ] Policy Allow/Deny Rate showing traffic
   - [ ] Decision Evaluation Latency visible
   - [ ] Bundle Load Duration graph active
   - Target: Should see baseline metrics

2. **Memory Engine Monitoring**
   - [ ] Semantic Search Queries showing activity
   - [ ] Search Latency p95 populated
   - [ ] Agent Task Success Rate > 95%
   - Target: Should see baseline performance

3. **Kafka Event Bus & Activity Feed**
   - [ ] Event Throughput showing messages/sec
   - [ ] Consumer Lag metrics visible
   - [ ] Broker Availability at 100%
   - Target: Should see event flow

4. **Execution Scheduler Monitoring**
   - [ ] Tasks by Destination chart active
   - [ ] Cost Trend line showing data
   - [ ] Resource Utilization gauge populated
   - Target: Should see task routing

5. **System Observability**
   - [ ] Node exporter metrics present
   - [ ] Container metrics visible
   - [ ] Network metrics shown
   - Target: Should see infrastructure health

### Phase 2: Validate OPA Policy Enforcement (30-45 minutes)

**Test OPA Policy Engine:**

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Test a sample policy decision
curl -X POST http://localhost:8181/v1/data/system/policy \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "user_id": "user123",
      "action": "deploy",
      "resource": "production"
    }
  }'

# Expected: Policy decision (allow/deny) based on rules
```

**Check Policy Decision Logs:**
```bash
# View OPA decision log in Grafana Loki
# Query: {job="opa"} | pattern `.*allow.*` or `.*deny.*`

# Or via CLI:
docker-compose logs opa | grep -i "decision"
```

### Phase 3: Test Event Processing (45-60 minutes)

**Verify Kafka Event Bus:**

```bash
# Check topic creation
docker-compose exec kafka kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --list

# Expected topics:
# - events
# - activity-feed
# - policy-decisions
# - agent-tasks
# - reputation-scores

# Check consumer groups
docker-compose exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --list
```

**Test Message Publishing:**
```bash
# In one terminal, consume messages
docker-compose exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic events \
  --from-beginning

# In another terminal, produce test message
docker-compose exec kafka kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic events <<< '{"test": "message", "timestamp": "'$(date -u +'%Y-%m-%dT%H:%M:%SZ')'"}'

# Verify message appears in consumer
```

### Phase 4: Baseline Performance Collection (1-2 hours)

**Collect Initial Metrics:**

1. Record current metrics from Grafana dashboards
2. Document latency p95 values
3. Note error rates for each service
4. Record throughput for event bus
5. Capture resource utilization

**Save Baseline Report:**
```bash
# Via Grafana API
curl -H "Authorization: Bearer $GRAFANA_TOKEN" \
  http://localhost:3000/api/dashboards/uid/opa-policies | jq . > baseline-opa.json

# Repeat for other dashboards
```

---

## Ongoing Monitoring (Hourly)

### Hourly Checks

**Every hour, verify:**

1. **Service Health**
   ```bash
   docker-compose ps | grep -c "Up"
   # Should equal 8 (all services)
   ```

2. **Disk Space**
   ```bash
   df -h / | awk 'NR==2 {print $5}'
   # Should be < 80%
   ```

3. **Memory Usage**
   ```bash
   docker stats --no-stream --format "table {{.Name}}\t{{.MemPerc}}"
   # All services < 10% individually
   ```

4. **Error Rate**
   ```bash
   # In Grafana, check "Error Rate %" on each dashboard
   # Should be < 1%
   ```

5. **Alert Status**
   ```bash
   curl http://localhost:9090/api/v1/alerts | jq .data.alerts
   # Should have no firing alerts
   ```

### Daily Checks

**Once per day, review:**

1. **Grafana Dashboard Trends**
   - 24-hour view of all metrics
   - Check for anomalies or spikes
   - Verify trend direction (healthy/degrading)

2. **Deployment History**
   - Check GitHub Actions workflow runs
   - Verify all deployments succeeded
   - Review drift detection reports

3. **Alert Logs**
   - Review any alerts that fired
   - Verify false positives vs. real issues
   - Tune thresholds if needed

4. **Resource Trending**
   - CPU usage trend
   - Memory usage trend
   - Disk usage trend
   - Network bandwidth trend

5. **Performance Metrics**
   - Request latency trends
   - Throughput trends
   - Error rate trends
   - Policy decision rates

---

## Alert Response Procedures

### When Alerts Fire

**Standard Response Process:**

1. **Immediate (< 5 minutes)**
   - Check Grafana dashboard for context
   - Verify alert isn't a transient spike
   - Check service logs (docker-compose logs <service>)

2. **Assessment (< 15 minutes)**
   - Determine root cause (service issue vs. dependency)
   - Check recent deployments
   - Review configuration changes

3. **Action (< 30 minutes)**
   - Attempt remediation if known issue
   - Or escalate to on-call engineer
   - Or trigger automated rollback if critical

4. **Documentation (< 60 minutes)**
   - Create GitHub issue if unexpected
   - Document root cause
   - Update runbooks if procedure needed

### Common Alerts & Response

**High Error Rate (> 5%):**
```bash
# Check service logs
docker-compose logs <service> --tail 100

# Check health endpoint
curl http://localhost:<port>/health

# If unrecoverable, trigger rollback
bash scripts/_common/rollback-manager.sh --revert-to previous
```

**High Latency (p95 > 1000ms):**
```bash
# Check service metrics
docker stats

# Check database query performance
docker-compose exec postgres psql -U postgres \
  -c "SELECT * FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

# If persistent, scale up resources or optimize queries
```

**Service Down:**
```bash
# Restart service
docker-compose restart <service>

# Wait 30 seconds and verify health
sleep 30 && curl http://localhost:<port>/health

# If still down, check logs and escalate
docker-compose logs <service> --tail 200
```

**Disk Space Critical (> 90%):**
```bash
# Find large files
du -sh /* | sort -rh | head -10

# Rotate logs
docker-compose exec <service> bash -c 'find /var/log -name "*.log" -mtime +7 -delete'

# Or scale up disk volume
```

---

## Disaster Recovery Testing

### Weekly Rollback Test

**Every week, verify rollback capability:**

```bash
# 1. Get current commit
CURRENT=$(git rev-parse HEAD)

# 2. Get previous commit
PREVIOUS=$(git rev-parse HEAD~1)

# 3. Test rollback (dry-run)
bash scripts/_common/rollback-manager.sh --revert-to $PREVIOUS --dry-run

# 4. If tests pass, rollback real
bash scripts/_common/rollback-manager.sh --revert-to $PREVIOUS

# 5. Verify health
bash scripts/ci/health-check-post-deploy.sh

# 6. Restore to current
git checkout $CURRENT
docker-compose restart
```

### Monthly Disaster Recovery Drill

**Once per month, execute full recovery:**

1. Simulate service failure
2. Trigger drift detection alert
3. Execute automated rollback
4. Verify service recovery
5. Document any issues
6. Brief team on findings

---

## Performance Optimization

### When Performance Degrades

**Investigation Steps:**

1. **Identify bottleneck** (from Grafana dashboards)
2. **Profile service** (cpu, memory, I/O)
3. **Analyze logs** (errors, warnings, slowness)
4. **Check dependencies** (database, cache, external services)
5. **Optimize** (config tuning, code changes, resource allocation)
6. **Test changes** (in staging first, then production)
7. **Monitor results** (compare before/after metrics)

### Scaling Considerations

**CPU-bound services (OPA, Memory Engine):**
- Increase replicas in docker-compose
- Enable container limits optimization
- Consider reserved resources

**I/O-bound services (PostgreSQL, Kafka):**
- Add disk space
- Optimize query patterns
- Tune cache settings

**Memory-intensive services (Kafka, Grafana):**
- Increase heap size
- Add memory to host
- Tune garbage collection

---

## Maintenance Windows

### Scheduled Maintenance

**Monthly Maintenance Window:**
- Tuesday 02:00 UTC
- Duration: 1-2 hours
- Activities: Database optimization, log rotation, security patching

**Maintenance Procedure:**
```bash
# 1. Announce maintenance
slack-notify "#incidents" "Scheduled maintenance window starting"

# 2. Disable alerts (optional)
# curl -X POST http://localhost:9090/api/v1/alerts/pause

# 3. Perform maintenance
# - Run database vacuum
# - Rotate logs
# - Apply security patches
# - Update monitoring config

# 4. Re-enable alerts
# curl -X POST http://localhost:9090/api/v1/alerts/pause

# 5. Run health checks
bash scripts/ci/health-check-post-deploy.sh

# 6. Announce completion
slack-notify "#incidents" "Scheduled maintenance completed successfully"
```

---

## Monitoring Best Practices

### Dashboard Usage

1. **Always check Grafana first** for baseline context
2. **Use time-range selector** to focus on relevant period
3. **Correlate metrics** across dashboards
4. **Create custom panels** for specific concerns
5. **Set appropriate refresh rates** (30s-5min typical)

### Alert Tuning

1. **Avoid alert fatigue** with reasonable thresholds
2. **Add context to alerts** (dashboard links, runbook links)
3. **Group related alerts** to reduce noise
4. **Test alert routing** (Slack, email, PagerDuty)
5. **Document alert purpose** and response procedure

### Log Analysis

1. **Use Loki for log queries** instead of grepping manually
2. **Create saved queries** for common investigations
3. **Set retention policies** to manage storage
4. **Archive logs** for long-term analysis
5. **Search by labels** (service, environment, severity)

---

## Escalation Procedures

### Level 1: Automated Response (< 5 minutes)
- Grafana alerts
- Prometheus alerting rules
- GitOps drift detection
- Automated health checks

### Level 2: Manual Investigation (5-30 minutes)
- On-call engineer reviews
- Dashboard analysis
- Service troubleshooting
- Documentation checks

### Level 3: Escalation (> 30 minutes)
- Team lead notification
- Architecture team consultation
- Vendor support contact
- Incident postmortem scheduled

### Level 4: Emergency (Ongoing)
- Full team mobilization
- Executive notification
- Customer communication
- Continuous status updates

---

## Contact & Resources

**On-Call Engineer:** See GitHub teams/assignments  
**Incident Channel:** #incidents on Slack  
**Escalation:** @architecture-team on Slack  
**Runbooks:** docs/operations/  
**Dashboards:** https://grafana.code-server.local/dashboards  
**GitHub Actions:** https://github.com/kushin77/code-server/actions  

---

## Acknowledgments

This guide provides comprehensive operational procedures for production monitoring and maintenance. All infrastructure is designed for automation and self-healing, minimizing manual intervention requirements.

**Last Updated:** April 24, 2026 @ 21:58 UTC  
**Version:** 1.0 (Production Ready)  
**Status:** 🟢 ACTIVE
