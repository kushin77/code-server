# Production Deployment Guide

## Pre-Deployment Checklist

- [ ] All tests passing (npm test, k6 load test)
- [ ] Code reviewed and approved
- [ ] Security scan passed (no vulnerabilities)
- [ ] Performance benchmarks acceptable
- [ ] Database migrations tested
- [ ] Backup created
- [ ] Runbooks reviewed with team
- [ ] On-call engineer available
- [ ] War room link prepared
- [ ] Stakeholders notified

## Deployment Phases

### Phase 1: Pre-Deployment (1-2 hours before)

1. Pull latest code from main
2. Run full test suite
3. Build production Docker image
4. Tag with version (v1.2.3)
5. Push to registry
6. Notify team of planned deployment

### Phase 2: Staging Validation (30 minutes)

```bash
# Deploy to staging environment
docker-compose -f deployment/staging/docker-compose.yml up -d

# Run smoke tests
bash deployment/tests/smoke-tests.sh

# Run load tests
k6 run performance/benchmarks/k6-load-test.js

# Manual validation
# - Check all dashboards
# - Verify SLO metrics
# - Test critical user workflows
```

### Phase 3: Production Deployment (Blue-Green, zero-downtime)

```bash
# Execute blue-green deployment
bash deployment/scripts/blue-green-deploy.sh

# Verify new environment
curl http://localhost:8080/health
curl http://localhost:3100/api/health
curl http://localhost:9090/-/healthy

# Run final smoke tests
bash deployment/tests/smoke-tests.sh
```

### Phase 4: Post-Deployment Monitoring (30 minutes)

1. Watch Grafana dashboards for 10 minutes
2. Monitor error rates and latency
3. Verify SLO metrics normalizing
4. Check application logs for errors
5. Confirm all services healthy

## Rollback Procedure

If critical issues detected:

```bash
# Immediate rollback (1 minute)
systemctl reload nginx
# Traffic switches to previous version

# Full rollback
docker-compose -f deployment/production/docker-compose.yml down
git checkout <previous-commit>
docker build -t code-server:prod .
docker-compose -f deployment/production/docker-compose.yml up -d
```

## Success Criteria

- All health checks passing
- Error rate < 0.1%
- P99 latency < 500ms
- Errors budget > 0%
- No deployment errors in logs
- All services responsive

## Communication

### During Deployment
- Post status updates to #deployments Slack channel
- Every 5 minutes: "Deployment in progress..."
- Upon completion: "Deployment successful"
- If rollback: "Rollback initiated - root cause TBD"

### Post-Deployment
- Send deployment summary to team
- Document any issues encountered
- Schedule postmortem if needed
- Create follow-up issues

## Monitoring Dashboard

After deployment, monitor:
- http://grafana:3100/d/slo-dashboard-main - SLO Tracking
- http://grafana:3100/d/agent-farm-overview - System Overview
- http://prometheus:9090/graph - Raw Prometheus metrics
- http://localhost:16686 - Jaeger Tracing

## Troubleshooting

### 500 Errors
1. Check application logs
2. Verify database connectivity
3. Check Redis connection
4. Review recent code changes

### High Latency
1. Check database query time
2. Verify cache hit ratio
3. Check CPU/memory usage
4. Monitor network latency

### Database Issues
1. Check PostgreSQL logs
2. Verify connection pool size
3. Check for long-running queries
4. Restore from recent backup if needed

## Incident Response

See: deployment/runbooks/CRITICAL-SERVICE-DOWN.md

## Automation

Deployments will eventually be automated via CI/CD:
```
main branch → Tests pass → Build image → Deploy to staging
→ Smoke tests pass → Manual approval → Deploy to production
```
