# PHASE 26-A: API Rate LIMITING - DEPLOYMENT PLAN

**Status**: 🟢 **READY FOR PRODUCTION**
**Timeline**: April 17-19, 2026 (3 days, ~12 hours effort)
**Owner**: API & Infrastructure Teams
**Target Deployment**: Staging Apr 17, Production Apr 20
**On-Prem Focus**: 192.168.168.31 (primary), 192.168.168.30 (standby)

---

## OVERVIEW

Implement intelligent, usage-based API rate limiting with:
- **3 Tier Model** (Free, Pro, Enterprise)
- **Dynamic Quota Calculation** (per-minute, per-day, concurrent)
- **Real-Time Header Signaling** (X-RateLimit-*)
- **Prometheus Integration** (metrics, alerts)
- **Sub-100ms Overhead** (calculated via middleware)

---

## DELIVERABLES

### 1. IaC (Terraform)
- **File**: `terraform/phase-26a-rate-limiting.tf` ✅ **CREATED**
- **Elements**:
  - Rate limit configuration (single source of truth via locals)
  - Prometheus metrics rules
  - Kubernetes ConfigMap (rate limit settings)
  - PostgreSQL schema updates (idempotent)

### 2. Application Integration
- **Service**: graphql-api (Node.js/Express)
- **Changes**:
  - Middleware: Rate limit enforcer
  - Headers: X-RateLimit-* (Remaining, Limit, Reset)
  - Responses: Include rate limit info in GraphQL extensions
  - Logging: Track enforcements for debugging

### 3. Load Testing
- **Tool**: k6 (JavaScript-based)
- **File**: `load-tests/phase-26-rate-limiting.js` ✅ **CREATED**
- **Scenarios**:
  - Simple queries (high volume, low cost)
  - Complex queries (medium volume, medium cost)
  - Mutations (low volume, high cost)
  - Rate limit header validation
  - Accuracy measurement (>99% target)

### 4. Monitoring
- **Prometheus Rules**: Rate limit alerts
  - Alert: User approaching 90% quota
  - Alert: Rate limit accuracy degraded (<99.9%)
- **Grafana Dashboards**:
  - Rate limit hits over time
  - Tier distribution (Free/Pro/Enterprise)
  - Accuracy histogram

### 5. Documentation
- **README**: API rate limiting guide
- **Runbook**: Emergency procedures
- **Troubleshooting**: Common issues & fixes

---

## TIER CONFIGURATION

### Free Tier

```
requests_per_minute:  60
requests_per_day:     10,000
concurrent_queries:   5
monthly_cost:         $0
```

**Use Case**: Personal dev testing, open-source projects
**Query Cost**: Simple = 1 credit, Complex = 5 credits

### Pro Tier

```
requests_per_minute:  1,000
requests_per_day:     500,000
concurrent_queries:   50
monthly_cost:         $50
```

**Use Case**: Small teams, startups
**Query Cost**: Simple = 1 credit, Complex = 5 credits

### Enterprise Tier

```
requests_per_minute:  10,000
requests_per_day:     100,000,000
concurrent_queries:   500
monthly_cost:         Custom
```

**Use Case**: Large deployments, multi-team orgs
**Query Cost**: Custom based on agreement

---

## IMPLEMENTATION SCHEDULE

### Day 1 (April 17): Code Review & Staging Setup

**Morning (2 hours)**:
- [ ] Code review: phase-26a-rate-limiting.tf
- [ ] Code review: graphql-api middleware changes
- [ ] Review Prometheus rules
- [ ] Approve load test scenarios

**Afternoon (3 hours)**:
- [ ] Deploy to staging (192.168.168.31)
- [ ] Verify rate limits enforced
- [ ] Check headers in responses
- [ ] Test tier boundaries

**Setup Commands**:
```bash
# SSH to staging
ssh akushnir@192.168.168.31

# Pull latest code
cd code-server-enterprise
git pull origin temp/deploy-phase-16-18

# Apply Terraform
terraform apply -auto-approve -target=null_resource.phase_26a_schema

# Restart GraphQL API
docker-compose -f docker-compose.yml up -d graphql-api

# Verify
curl -X POST http://localhost:4000/graphql \
  -H "Authorization: Bearer key_free_1" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ user(id: \"test\") { id } }"}'

# Check headers
curl -v -X POST http://localhost:4000/graphql \
  -H "Authorization: Bearer key_free_1" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ user(id: \"test\") { id } }"}' \
  | grep -i "X-RateLimit"
```

### Day 2 (April 18): Load Testing

**Morning (3 hours)**:
- [ ] Setup k6 environment
- [ ] Run baseline test (100 concurrent users, 5 min)
- [ ] Validate headers accurate
- [ ] Measure p99 latency

**Load Test Command**:
```bash
# Install k6 (on local machine or staging)
curl https://dl.k6.io/install-ubuntu.sh | sudo bash

# Run baseline test
k6 run load-tests/phase-26-rate-limiting.js \
  --vus 100 \
  --duration 5m \
  --env API_URL=http://192.168.168.31:4000/graphql \
  --env MAX_VUS=100 \
  --out json=results-baseline.json

# Check results
# - Rate limit accuracy should be >99%
# - p99 latency should be <200ms
# - Error rate should be <1%
```

**Afternoon (2 hours)**:
- [ ] Run peak load test (1000 concurrent users, 3 min)
- [ ] Validate under stress
- [ ] Verify no memory leaks
- [ ] Document results

**Peak Load Command**:
```bash
k6 run load-tests/phase-26-rate-limiting.js \
  --vus 1000 \
  --duration 3m \
  --env API_URL=http://192.168.168.31:4000/graphql \
  --env MAX_VUS=1000 \
  --out json=results-peak.json
```

### Day 3 (April 19): Production Canary Deployment

**Morning (2 hours)**:
- [ ] Test failover scenarios (primary → standby)
- [ ] Verify standby has rate limit data synced
- [ ] Check PostgreSQL replication
- [ ] Validate metrics in Prometheus

**Afternoon (3 hours)**:
- [ ] Deploy to production (primary: 192.168.168.31)
- [ ] Monitor for 2 hours
- [ ] Validate X-RateLimit headers in production
- [ ] Confirm Prometheus metrics collected

**Canary Command**:
```bash
# Only deploy after staging validation ✅

# Staging health check first
curl http://192.168.168.31:4000/graphql \
  -X POST \
  -H "Authorization: Bearer key_free_1" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ __typename }"}'

# Production deployment
ssh akushnir@192.168.168.31
cd code-server-enterprise
git pull origin temp/deploy-phase-16-18
terraform apply -auto-approve -target=null_resource.phase_26a_schema
docker-compose -f docker-compose.yml up -d graphql-api

# Monitor production
watch -n 5 'curl http://localhost:4000/graphql -X POST \
  -H "Authorization: Bearer key_free_1" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"{ __typename }\"}" | jq .'

# Check Grafana
# http://192.168.168.31:3000/d/phase-26-rate-limiting
```

---

## SUCCESS CRITERIA

### Performance
✅ **API Response Time**: <50ms p99 (Phase 21 baseline maintained)
✅ **Rate Limit Overhead**: <1ms added per request
✅ **Concurrent Queries**: Supported per tier (5 free, 50 pro, 500 enterprise)

### Accuracy
✅ **Rate Limit Accuracy**: >99.9%
✅ **Header Correctness**: 100% (X-RateLimit-* headers accurate)
✅ **Tier Enforcement**: 100% (correct tier applied to all requests)

### Reliability
✅ **Uptime**: 99.95% (SLA maintained from Phase 21)
✅ **Error Rate**: <0.1% (during staging load tests)
✅ **Failover Time**: <30 seconds (primary → standby switchover)

### Load Testing
✅ **Baseline Load**: 100 concurrent users, <1% error rate
✅ **Peak Load**: 1000 concurrent users, <5% error rate
✅ **Burst Load**: 10000 queries/second, graceful degradation

---

## ROLLBACK PLAN

If issues arise during deployment:

### Stage 1: Immediate Disable (1 minute)

```bash
# SSH to affected host
ssh akushnir@192.168.168.31

# Disable rate limiting middleware
docker-compose -f docker-compose.yml \
  exec graphql-api \
  npm run config -- --disable-rate-limiting=true

# Restart service
docker-compose -f docker-compose.yml \
  restart graphql-api

# Verify
curl http://localhost:4000/graphql \
  -X POST \
  -d '{"query": "{ __typename }"}'
```

### Stage 2:  Revert Code (5 minutes)

```bash
# Rollback to previous commit
git revert --no-commit HEAD
git commit -m "Revert: Phase 26-A rate limiting (emergency)"
git push origin temp/deploy-phase-16-18

# Redeploy without rate limiting
docker-compose -f docker-compose.yml \
  up -d --force-recreate graphql-api
```

### Stage 3: Investigation (post-incident)

1. Pull logs from failed deployment:
   ```bash
   docker logs graphql-api > /tmp/api-logs.txt
   ```

2. Check Prometheus for errors:
   ```
   http://192.168.168.31:9090
   Query: api_rate_limit_errors
   ```

3. Review rate limit calculations in PostgreSQL:
   ```sql
   SELECT user_id, tier, requests_used, requests_limit
   FROM rate_limit_usage
   WHERE timestamp > NOW() - INTERVAL '10 minutes';
   ```

**Rollback SLA**: <5 minutes to full functionality

---

## MONITORING & ALERTS

### Prometheus Alerts (auto-firing)

**Alert 1: Rate Limit Accuracy Degraded**
```
Threshold: accuracy < 99%
Action: Page on-call engineer
```

**Alert 2: High 429 Error Rate**
```
Threshold: 429s > 1% of requests for 5 min
Action: Investigate rate limit logic
```

**Alert 3: Rate Limit Processing Lag**
```
Threshold: rate_limit_computation_seconds > 0.01
Action: Optimize calculation logic
```

### Grafana Dashboards

**Dashboard 1: Rate Limit Overview**
- Requests per minute (by tier)
- 429 error rate
- p95/p99 latency
- Header accuracy

**Dashboard 2: Tier Distribution**
- Free tier requests
- Pro tier requests
- Enterprise tier requests
- Monthly usage trend

**Dashboard 3: Production Health**
- API uptime
- Rate limit component health
- Database query performance
- Cache hit ratio

---

## DOCUMENTATION

### README: API Rate Limiting Guide

```markdown
# API Rate Limiting (Phase 26-A)

## Rate Limits

### Free Tier
- 60 requests/minute
- 10,000 requests/day
- 5 concurrent queries

### Pro Tier
- 1,000 requests/minute
- 500,000 requests/day
- 50 concurrent queries

### Enterprise Tier
- Contact sales

## Response Headers

All API responses include:
- `X-RateLimit-Limit`: Total requests allowed
- `X-RateLimit-Remaining`: Requests remaining
- `X-RateLimit-Reset`: Unix timestamp when limit resets

## Rate Limited Response (429)

When you exceed the limit:
```json
{
  "errors": [{
    "message": "Rate limit exceeded",
    "extensions": {
      "code": "RATE_LIMITED",
      "retryAfter": 60
    }
  }]
}
```

## Increasing Your Limit

1. **Upgrade to Pro**: $50/month (1000 req/min)
2. **Contact Sales**: Enterprise tier (custom limits)
```

### Runbook: Emergency Procedures

1. **User Reports Rate Limiting When Not Expected**
   - Check tier: `SELECT tier FROM users WHERE id = ?`
   - Check usage: `SELECT requests_used, requests_limit FROM rate_limit_usage`
   - Reset if bug: `UPDATE rate_limit_usage SET requests_used = 0`

2. **Rate Limiter Service Down**
   - Fallback: Allow all requests (no limiting)
   - Alert: Page on-call engineer
   - Investigate: Check database connectivity

3. **Header Values Incorrect**
   - Validate calculation: Check GraphQL resolver
   - Check database: Verify usage table values
   - Test: Run `load-tests/phase-26-rate-limiting.js` again

---

## GO/NO-GO CRITERIA

### Day 1 (April 17)
- [ ] Code review approved
- [ ] Staging deployment successful
- [ ] Headers present in responses
- [ ] Tiers enforced correctly
- **Decision**: GO/NO-GO

### Day 2 (April 18)
- [ ] Baseline load test passed (100 VUs, >99% accuracy)
- [ ] Peak load test passed (1000 VUs, <5% error)
- [ ] No memory leaks detected
- [ ] Latency baseline maintained (<50ms p99)
- **Decision**: GO/NO-GO

### Day 3 (April 19)
- [ ] Failover tested (primary ↔ standby)
- [ ] Production health metrics green
- [ ] Alert system validated
- [ ] Documentation complete
- **Decision**: GO/NO-GO → Phase 26-B (SDKs)

---

## NEXT PHASE

After Phase 26-A completes (April 20):

**Phase 26-B: Multi-Language SDKs** (April 21-25)
- Python SDK
- Go SDK
- JavaScript/TypeScript SDK
- Java SDK
- Rust SDK
- All integrated with rate limiting

---

## PHASE 26-A COMPLETION CHECKLIST

- [ ] IaC created and committed
- [ ] Load test script ready
- [ ] Staging deployment complete (Apr 17)
- [ ] Load tests validated (Apr 18)
- [ ] Production deployment complete (Apr 19)
- [ ] Grafana dashboards configured
- [ ] Prometheus alerts active
- [ ] Runbooks documented
- [ ] Team trained on troubleshooting
- [ ] Metrics baseline established

**Target Completion**: April 20, 2026 (12:00 UTC)
**Phase 26 Unblock**: April 21 (Phase 26-B kickoff)

---

**Owner**: API Infrastructure Team
**Last Updated**: April 14, 2026
**Status**: Ready for April 17 Staging Deployment
