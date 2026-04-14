# April 17, 2026: Phase 26 Deployment Kickoff
## Immediate Action Items & Execution Plan

**Date**: April 14, 2026, 11:30 PM PT
**Status**: 🟢 **ALL SYSTEMS GO - READY FOR APRIL 17 EXECUTION**

---

## APRIL 17 ACTION ITEMS (3:00 AM PT - 5:00 PM PT)

### 1. RATE LIMITER DEPLOYMENT (2 hours, 3:00-5:00 AM PT)

**Task 1.1: GraphQL Middleware Integration (1.5 hours)**
```bash
# Deploy middleware to staging
kubectl rollout restart deployment/graphql-api -n staging
kubectl wait --for=condition=available deployment/graphql-api -n staging --timeout=300s

# Verify deployment
curl -s "http://graphql-api.staging:4000/graphql" \
  -H "X-API-Key: test-key" \
  -d '{"query":"{ __typename }"}'

# Check X-RateLimit headers in response
curl -v "http://graphql-api.staging:4000/graphql" \
  -H "X-API-Key: pro-test" \
  -d '{"query":"{ __typename }"}' | grep X-RateLimit
```

**Task 1.2: Functional Testing (30 minutes)**
- [ ] Test Free tier: 60 req/min limit
- [ ] Test Pro tier: 1000 req/min limit
- [ ] Test Enterprise tier: 10k req/min limit
- [ ] Verify concurrent limits: 5 (free), 50 (pro), 500 (enterprise)
- [ ] Check 429 Too Many Requests responses
- [ ] Verify X-RateLimit-* headers
- [ ] Check Prometheus metrics emission

**Success**: All tier limits enforced, headers accurate, no errors

---

### 2. FUNCTIONAL TESTING (3 hours, 5:00-8:00 AM PT)

**Task 2.1: Test Harness Execution**
```bash
# Run functional test suite
bash load-tests/phase-26-rate-limit.sh --mode=functional

# Expected output:
# ✓ Free tier forced to 60 req/min (tested with 100 reqs)
# ✓ Pro tier forced to 1000 req/min (tested with 2000 reqs)
# ✓ Enterprise allowed up to 10k req/min
# ✓ Concurrent limits: 5/50/500 enforced
# ✓ 429 responses have proper headers
# ✓ Prometheus metrics >99.9% accurate
```

**Task 2.2: Prometheus Metrics Validation**
```bash
# Query Prometheus for rate limiter metrics
curl -s "http://prometheus.phase-24:9090/api/v1/query?query=graphql_rate_limit_hits_total" | jq .

# Verify metrics:
# - graphql_rate_limit_hits_total > 0
# - graphql_rate_limit_violations_total < 0.1% of hits
# - graphql_rate_limit_latency_us < 50 (microseconds)
```

**Success**: All metrics correct, accuracy >99.9%, <50μs latency

---

### 3. LOAD TESTING (5 hours, 8:00 AM-1:00 PM PT)

**Task 3.1: k6 Load Test Execution**
```bash
# Run load test profile: 1000 req/sec sustained
k6 run load-tests/phase-26-rate-limit.js \
  --vus=1000 \
  --duration=5m \
  --out=json=results.json

# Expected results:
# - Requests: ~300,000 (5min × 1000 req/sec)
# - Success rate: >99.9%
# - Violations: 0-5 (normal edge cases)
# - p99 latency: <100ms
# - p95 latency: <80ms
# - p50 latency: <30ms
```

**Task 3.2: Load Test Analysis**
```bash
# Generate report
./load-tests/phase-26-rate-limit.sh --mode=analyze --input=results.json

# Verify:
# ✓ Latency baseline maintained
# ✓ Throughput ≥1000 req/sec
# ✓ Error rate <0.1%
# ✓ Violations <0.1% of successful requests
# ✓ No memory leaks (check k6 finalizers)
```

**Success**: 1000 req/sec sustained, p99<100ms, errors<0.1%

---

### 4. PRODUCTION STAGING DEPLOYMENT (2 hours, 1:00-3:00 PM PT)

**Task 4.1: Canary Deployment to Staging**
```bash
# Deploy to 10% of staging cluster
kubectl set image deployment/graphql-api \
  graphql-api=code-server/graphql-api:phase-26a-rate-limit \
  -n production

# Wait for rollout
kubectl rollout status deployment/graphql-api -n production --timeout=300s

# Verify health
kubectl get pods -n production -l app=graphql-api
```

**Task 4.2: Staging Validation**
```bash
# Quick sanity check
curl -s "https://api-staging.192.168.168.31/graphql" \
  -H "X-API-Key: test-key" \
  -d '{"query":"{ __typename }"}' | jq .

# Check X-RateLimit headers
curl -v "https://api-staging.192.168.168.31/graphql" \
  -H "X-API-Key: pro-test" \
  -d '{"query":"{ __typename }"}' 2>&1 | grep -i "x-ratelimit"
```

**Success**: Staging validated, headers present, no errors

---

### 5. APRIL 18-19: LOAD TEST & PRODUCTION DEPLOYMENT

**April 18 (9:00 AM PT)**
- Execute full 5-minute load test
- Analyze results
- If p99<100ms & errors <0.1%: Proceed to production

**April 19 (9:00 AM PT)**
- Deploy to 10% production traffic (canary)
- Monitor for 1 hour
- If errors <0.1%: Proceed to 100%
- Full production rollout by 5:00 PM PT

---

## COMPLETE CHECKLIST

### Pre-Deployment ✅
- [x] Code reviewed and approved
- [x] Tests passing (unit + integration)
- [x] Load test framework ready
- [x] Kubernetes manifests prepared
- [x] Prometheus rules defined
- [x] Documentation complete
- [x] Rollback plan documented

### Deployment (Apr 17-19)
- [ ] Functional tests pass (Apr 17 AM)
- [ ] Load test passes (Apr 18)
- [ ] Staging deployment successful (Apr 17 PM)
- [ ] Production canary deploy (Apr 19 AM)
- [ ] Production 100% deploy (Apr 19 PM)

### Post-Deployment
- [ ] Monitor for 24 hours
- [ ] Verify metrics accuracy >99.9%
- [ ] Confirm rate limiting correct
- [ ] Update documentation with results
- [ ] Close GitHub issue #275

---

## GITHUB ISSUES CREATED

| Issue | Title | Status |
|-------|-------|--------|
| #275 | Phase 26-A: Stage 1 Deployment (Apr 17-19) | 🟢 READY |
| #276 | Phase 26-B: Analytics (Apr 20-24) | 🟡 READY FOR APR 20 |
| #277 | Phase 26-C/D: Orgs & Webhooks (Apr 25-May 1) | 🟡 READY FOR APR 25 |
| #278 | Phase 26: Testing & Launch (May 2-3) | 🟡 READY FOR MAY 2 |
| #279 | Phase 27: Mobile SDK (May 4-23) | 🟡 READY FOR MAY 4 |

---

## DEPLOYMENT SEQUENCE

```
April 17 (3:00 AM - 5:00 PM PT)
├─ 3:00 AM: Middleware integration + functional tests (2h)
├─ 5:00 AM: Functional testing (3h)
├─ 1:00 PM: Staging deployment (1h)
└─ 5:00 PM: Day 1 monitoring begins

April 18 (9:00 AM PT)
├─ Load testing (5min sustained 1000 req/sec)
├─ Results analysis
└─ Decision: Proceed to production?

April 19 (9:00 AM PT)
├─ Production canary: 10% traffic (1h monitoring)
├─ Production canary: 25% traffic (1h monitoring)
├─ Production canary: 50% traffic (overnight monitoring)
└─ May 4, 6:00 AM: 100% production rollout

May 4, 6:00 AM
├─ Stage 1 complete ✅
├─ Phase 26-B begins (analytics)
└─ Phase 27 unblocked (mobile SDK)
```

---

## TEAM CONTACTS

**Infrastructure**: [deployment-team]
**On-Call Pager**: [incident-response]
**Monitoring**: [observability-team]
**Database**: [postgres-team]
**Security**: [security-team]

---

## SUCCESS CRITERIA

✅ **Stage 1 Successful When**:
1. All tiers enforced correctly (Free 60/min, Pro 1000/min, Enterprise 10k/min)
2. Concurrent limits working (5/50/500)
3. Headers accurate (X-RateLimit-Limit, X-Remaining, X-Reset)
4. Load test passes (1000 req/sec sustained)
5. Prometheus metrics >99.9% accurate
6. Latency baseline maintained (<100ms p99)
7. Zero 4xx/5xx errors in production (except 429)

**Estimated Completion**: May 4, 6:00 AM PT

---

## ROLLBACK PLAN

If any stage fails:

```bash
# Immediate rollback from production
kubectl rollout undo deployment/graphql-api -n production

# Verify rollback
kubectl rollout status deployment/graphql-api -n production

# Check previous version is live
curl -s "https://api.192.168.168.31/graphql" -d '{"query":"{ __typename }"}'

# Expected: No X-RateLimit headers in old version
```

**Rollback Time**: <5 minutes
**Data Impact**: Zero (stateless middleware)
**User Impact**: Momentary service interruption during rollout

---

## MONITORING DURING DEPLOYMENT

**April 17-19 Dashboards**:
- Grafana: [Rate Limiting Status](http://grafana.phase-24:3000/d/phase-26-rate-limits)
- Prometheus: [Rate Limit Metrics](http://prometheus.phase-24:9090/graph?g0.expr=graphql_rate_limit_hits_total)
- Alerts: [AlertManager](http://alertmanager.phase-24:9093)

**Key Metrics to Watch**:
- `graphql_rate_limit_violations_total` (should stay <0.1%)
- `graphql_rate_limit_latency_us` (should stay <50μs)
- `graphql_requests_per_sec` (should match load)
- `http_request_duration_seconds p99` (should stay <100ms)

---

## NEXT PHASE KICKOFF

**April 20**: Phase 26-B (Analytics) begins
- ClickHouse deployment
- Aggregator service
- Grafana dashboards

**April 25**: Phase 26-C/D (Orgs & Webhooks) begins
- PostgreSQL migrations
- Organization API
- Webhook dispatcher

**May 2**: Phase 26-E (Testing & Launch) begins
- E2E test suite
- Security audit
- Canary deployment

---

**Document Created**: April 14, 2026, 11:30 PM PT
**Next Update**: April 17, 2026, 3:00 AM PT
**Status**: ✅ **READY FOR KICKOFF**
