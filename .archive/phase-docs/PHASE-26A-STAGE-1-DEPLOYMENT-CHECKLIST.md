# Phase 26-A: Stage 1 Deployment Checklist
## API Rate Limiting Enhancement (12 hours, Apr 17-19)

## Pre-Deployment (Apr 16-17)

### Infrastructure Review
- [ ] Terraform module validated (`phase-26a-rate-limiting.tf`)
- [ ] Kubernetes manifests reviewed (Prometheus rules, ConfigMaps)
- [ ] Redis instance available for rate limiter state
- [ ] PostgreSQL connection tested for user tier lookups
- [ ] Kubernetes secret `rate-limit-config` created

### Code Review
- [ ] GraphQL middleware integration approved
- [ ] Rate limit configuration single-sourced (locals.tf, ConfigMaps)
- [ ] Error handling for Redis failures (fail-open strategy)
- [ ] Metrics instrumentation complete
- [ ] No hardcoded values in middleware (all from ConfigMaps)

### Testing Setup
- [ ] Load test script ready (`phase-26-rate-limit.js`)
- [ ] k6 CLI installed on test harness
- [ ] Prometheus scrape targets configured
- [ ] Grafana dashboard prepared (rate limit metrics)
- [ ] Alert rules synced to Prometheus

### Documentation
- [ ] Implementation guide published
- [ ] Rate limit tier documentation prepared
- [ ] API response header documentation updated
- [ ] Runbook for rate limit troubleshooting

## Day 1: Apr 17 - GraphQL Middleware Integration

### Morning: Code Deployment
- [ ] Deploy GraphQL middleware to staging
  - [ ] `src/middleware/graphql-rate-limit.js` integrated
  - [ ] API keys configured for test users
  - [ ] Tier assignments verified
- [ ] Enable rate limit logging
- [ ] Start baseline metrics collection (30 min)

### Afternoon: Functional Testing
- [ ] Manual API tests with different tiers
  - [ ] Free tier: 60 requests/min enforced
  - [ ] Pro tier: 1000 requests/min enforced
  - [ ] Enterprise tier: 10000 requests/min enforced
- [ ] Test rate limit headers in responses
  - [ ] X-RateLimit-Limit present
  - [ ] X-RateLimit-Remaining accurate
  - [ ] X-RateLimit-Reset correct
- [ ] Test 429 Too Many Requests response
- [ ] Test burst handling (grace period)
- [ ] Verify no impact on baseline latency (<100ms p99)

### Validation
- [ ] Prometheus metrics collecting
- [ ] Error rate <0.1%
- [ ] False positive rate <0.1%
- [ ] Latency increase <1ms (target: <10μs overhead)
- [ ] Update status: **Functional Testing PASSED**

## Day 2: Apr 18 - Load Testing

### Load Test Execution
- [ ] Start k6 load test: 1000 req/sec peak
  - [ ] Ramp-up phase (100 → 500 → 1000 users)
  - [ ] Sustained load (1000 users, 3 min)
  - [ ] Ramp-down phase
  - [ ] Cool-down phase
- [ ] Monitor Grafana dashboards in real-time
- [ ] Watch Prometheus for any anomalies
- [ ] Log all errors to analysis queue

### Load Test Results Analysis
- [ ] Response time p99: <100ms ✓
- [ ] Rate limit accuracy: ≥99.9% ✓
- [ ] False positive rate: <0.1% ✓
- [ ] Success rate: >99.9% ✓
- [ ] No memory leaks observed ✓
- [ ] No connection exhaustion ✓
- [ ] Update status: **Load Testing PASSED**

### Metrics Review
- [ ] Export load test results
- [ ] Generate graphs for report
- [ ] Compare against baseline
- [ ] Document any optimization opportunities

## Day 3: Apr 19 - Production Deployment & Validation

### Pre-Production Deployment
- [ ] Deploy rate limiter to production
  - [ ] Kubernetes rollout (1 replica, wait)
  - [ ] Health checks passing
  - [ ] Metrics flowing to Prometheus
  - [ ] No error spikes
- [ ] Production smoke test
  - [ ] Test with real API keys
  - [ ] Verify rate limit enforcement
  - [ ] Check response headers
- [ ] Enable production monitoring alerts

### Production Monitoring (2 hours)
- [ ] Watch error rate (target: <0.1%)
- [ ] Monitor latency (target: <100ms p99)
- [ ] Track rate limit accuracy (target: >99.9%)
- [ ] Review alert logs
- [ ] Verify tier enforcement
- [ ] Update status: **Production Deployment PASSED**

### Documentation & Sign-Off
- [ ] Update deployment runbook
- [ ] Document discovered issues and resolutions
- [ ] Create troubleshooting guide
- [ ] Stage 1 completion report
- [ ] **STAGE 1 COMPLETE - Apr 19, 5:00 PM**

## Success Criteria (All Required)

✅ **Functional**
- Rate limiting enforced per tier
- Proper HTTP headers in responses (X-RateLimit-*)
- 429 Too Many Requests returned when limit exceeded
- Concurrent query limiting works

✅ **Performance**
- API latency baseline maintained (<100ms p99)
- Rate limit header calculation <1ms
- No memory leaks observed
- No connection exhaustion

✅ **Reliability**
- Prometheus metrics accurate (99.9%+)
- False positive rate <0.1%
- Fail-open on Redis errors
- Zero data loss

✅ **Monitoring**
- All metrics collecting to Prometheus
- Grafana dashboard showing real-time data
- Alerts configured and tested
- Audit logs recording all rate limit events

## Rollback Plan

If any success criterion fails:

1. **Immediate**: Disable rate limiting middleware in GraphQL
2. **Monitor**: Wait 5 minutes for baseline recovery
3. **Investigate**: Review logs and metrics
4. **Fix**: Apply code fix or configuration change
5. **Re-test**: Run load test again
6. **Retry**: Attempt deployment again

Rollback is single-click in Kubernetes:
```bash
kubectl rollout undo deployment/graphql-api -n default
```

## Escalation

**Critical Issues** (>0.1% error rate, latency >100ms p99):
- Contact: PureBlissAK (primary), BestGaaS220 (backup)
- Slack: #infrastructure-incident
- Response time: <15 minutes

**Non-Critical Issues** (minor bugs, documentation):
- Assign to team, add to sprint backlog
- Fix in Phase 26-B or later

## Sign-Off

- [ ] Infrastructure Team Lead: _________________
- [ ] DevOps Engineer: _________________
- [ ] Performance Engineer: _________________
- [ ] Date: _________________

---

## Notes & Learnings

(To be filled during deployment)

---

**Timeline**: Apr 17-19 (3 days, 12 hours effort)  
**Status**: Ready to begin April 17  
**Owner**: Infrastructure Team
