# Runbook: SLO Violation

## Alert
`SLOViolation` - Triggered when 30-day HTTP availability drops below 99.9% SLO target.

## Severity
🔴 CRITICAL

## Impact
- Service level agreement (SLO) breach
- Error budget depleted
- Customer-facing availability commitment violated
- May trigger customer rebates or compensation

## SLO Definition
- **Target**: 99.9% availability (30-day rolling window)
- **Error Budget**: 43.2 minutes downtime per month
- **Burn Rate**: 0.144% per day

## Diagnostics

### 1. Current Availability Metrics
```bash
# SSH to Prometheus
ssh akushnir@192.168.168.31

# Query current availability
curl 'http://192.168.168.31:9090/api/v1/query?query=slo:http_availability:30d'
curl 'http://192.168.168.31:9090/api/v1/query?query=slo:error_budget:remaining'
```

### 2. Error Budget Remaining
Go to Grafana: http://192.168.168.31:3000/d/slo-error-budget
- Check "Error Budget Remaining" gauge
- If < 10%, critical state

### 3. Root Cause Analysis
```bash
# Check request failure rate
curl 'http://192.168.168.31:9090/api/v1/query?query=sum(rate(http_requests_total{status=~"5.."}[5m]))'

# Check 4xx errors (user-caused, don't count against SLO)
curl 'http://192.168.168.31:9090/api/v1/query?query=sum(rate(http_requests_total{status=~"4.."}[5m]))'

# Check which endpoints failing
curl 'http://192.168.168.31:9090/api/v1/query?query=sum(rate(http_requests_total{status="500"}[5m])) by (handler,path)'
```

### 4. Timeline of Events
```bash
# Check Loki logs for errors in past 24h
# Go to Grafana Explore → Loki
# Query: {severity="error"} | json status="500"
```

## Resolution

### Phase 1: Stabilize (Immediate)
1. **Identify failing service**
   ```bash
   docker-compose ps
   docker-compose logs <failing-service> | tail -50
   ```

2. **Restart affected services**
   ```bash
   docker-compose restart <service>
   ```

3. **Check database connectivity**
   ```bash
   docker-compose exec postgresql psql -U postgres -c "SELECT 1;"
   docker-compose exec redis redis-cli PING
   ```

4. **Check disk space**
   ```bash
   df -h
   du -sh /var/log/*
   ```

### Phase 2: Analyze (Next 30 min)
1. **Review recent deployments**
   ```bash
   git log --oneline -10
   git show <commit> --stat
   ```

2. **Check resource usage**
   ```bash
   docker stats
   free -h
   ```

3. **Review configuration changes**
   ```bash
   git diff HEAD~5 HEAD -- config/
   ```

### Phase 3: Prevent Recurrence
1. **Increase monitoring fidelity**
   - Add more granular health checks
   - Lower probe interval (e.g., 10s instead of 30s)

2. **Capacity planning**
   - Review load test results (Issue #422)
   - Scale resources if at capacity

3. **Auto-remediation**
   - Enable automated restarts for failed services
   - Implement circuit breakers

4. **Error budget review**
   - At 10% remaining: schedule maintenance window
   - At 5% remaining: pause new deployments
   - Document root causes for post-mortems

## Prevention

### Short-term (This Week)
1. Deploy HA failover (Issue #422)
2. Enable blackbox synthetic monitoring (Issue #429)
3. Configure PagerDuty escalation (Issue #429)

### Medium-term (This Month)
1. Implement circuit breakers in nginx/Kong
2. Set up automated incident response playbooks
3. Enable distributed tracing (Jaeger) for better diagnostics
4. Implement database connection pooling (PgBouncer)

### Long-term (This Quarter)
1. Migrate to Kubernetes for better resilience
2. Implement canary deployments
3. Multi-region failover (beyond .31/.42)

## Escalation

- **Alert triggers** - Page on-call engineer immediately
- **10 min** - Join incident war room
- **20 min** - If not resolved, escalate to senior engineer
- **30 min** - Escalate to management/customer
- **60 min** - Post-mortem initiated

## Key Contacts

- **On-Call**: Check PagerDuty
- **Platform Lead**: kushin77@github.com
- **Customer Success**: ops-team@example.com

---
**Last Updated**: April 15, 2026  
**RTO Target**: <5 minutes  
**Documentation**: See [SLO Dashboard](http://192.168.168.31:3000/d/slo-error-budget)  
**Related**: Issue #429 (Observability), Issue #422 (HA)
