# CRITICAL: Service Down - Immediate Action Required

## Symptoms
- Service endpoints return 5xx errors
- Health checks failing consistently
- P99 latency > 2 seconds
- Error rate > 10%

## Immediate Actions (First 5 minutes)

1. **Declare Incident**
   - Page on-call engineer immediately
   - Escalate to engineering lead
   - Start war room (Zoom/Slack)
   - Begin incident log

2. **Assess Impact**
   - Check Grafana SLO dashboards
   - Verify user impact via support channels
   - Check downstream service dependencies

3. **Triage**
   - Is database up? (psql -h localhost -U postgres -d code_server)
   - Are containers running? (docker ps)
   - Check recent deployments in git
   - Review logs: docker logs code-server-blue

## Recovery Steps

### Option A: Quick Rollback (2-3 min)
```bash
# Immediately switch to previous environment
systemctl reload nginx
docker stop code-server-blue
docker stop code-server-green
docker-compose -f deployment/production/docker-compose.yml up -d
```

### Option B: Database Recovery (5-10 min)
```bash
# Check database status
psql -h localhost -U postgres -d code_server -c "SELECT 1"

# If corrupted, restore from backup
docker stop code-server postgres
docker run -v postgres-backup:/backup postgres:15 \
  pg_restore -d code_server /backup/latest.dump
```

### Option C: Resource Exhaustion (10-30 min)
```bash
# Scale horizontally if using Kubernetes
kubectl scale deployment code-server --replicas=10

# Or restart with more resources
docker-compose -f deployment/production/docker-compose.yml down
docker-compose -f deployment/production/docker-compose.yml up -d
```

## Monitoring Recovery

1. Watch Prometheus dashboards
2. Confirm SLO metrics normalizing
3. Run smoke tests
4. Monitor error rates returning to baseline

## Post-Incident

- Document RCA (root cause analysis)
- Create follow-up issues for prevention
- Update runbooks based on learnings
- Schedule postmortem meeting

---

# HIGH: SLO Breach - Feature Freeze Triggered

## Symptoms
- Error budget > 75% consumed
- P99 latency consistently > target
- Error rate > SLO threshold

## Response

1. **Declare Feature Freeze**
   - No new deployments allowed
   - Engineering focus: stability only
   - Notify product and stakeholders

2. **Root Cause Analysis**
   - Recent deployments correlation
   - Database query performance
   - Infrastructure capacity
   - Third-party service issues

3. **Stabilization (24-48 hours)**
   - Rollback recent changes
   - Optimize slow queries
   - Scale resources
   - Fix resource leaks

4. **Verification**
   - Error budget below 50%
   - SLO metrics normalized
   - 24-hour baseline stability
   - Load test validation

5. **Resume Development**
   - Feature freeze lifted
   - Post-incident review complete
   - Prevention measures implemented

---

# MEDIUM: Performance Degradation

## Symptoms
- P99 latency increasing gradually
- CPU/memory utilization rising
- Database query time increasing

## Actions

1. Check recent code deployments
2. Analyze slow query logs
3. Review cache hit ratios
4. Check database connection pool exhaustion
5. Monitor third-party API latency

## Solutions

- Implement database indexes
- Clear Redis caches
- Scale database connections
- Optimize problematic queries
- Reduce logging verbosity

---

# WARNING: Approaching Error Budget Limit

## Threshold
- 50% of monthly budget consumed

## Response

1. High alert severity
2. Review all recent changes
3. Increase monitoring frequency
4. Plan for potential feature freeze
5. Prepare rollback procedures

## Monitoring

Watch:
- Burn rate trends
- Error rate patterns
- Latency distribution
- Resource utilization
