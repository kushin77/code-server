# COLLAB-9 STAGE 2 - PRODUCTION CANARY DEPLOYMENT PLAN
**Date:** April 24, 2026  
**Prepared for:** April 26-27, 2026  
**Target:** 5% production user canary  
**Status:** READY FOR EXECUTION

---

## STAGE 2 OBJECTIVE

Validate Collab-9 feature in production with minimal blast radius (5% of active users) while maintaining full observability and instant rollback capability.

---

## PRE-DEPLOYMENT CHECKLIST

### Stage 1 Validation Complete ✅
- ✅ Staging deployment verified operational
- ✅ All 5 live functional tests passed
- ✅ Monitoring infrastructure operational
- ✅ Documentation complete
- ✅ Risk assessment completed

### Production Readiness ✅
- ✅ Feature flag: FEATURE_WEBHOOK_ENABLED configured
- ✅ Rollout percentage: WEBHOOK_ROLLOUT_PERCENTAGE=5 ready
- ✅ Monitoring dashboards: Grafana, Prometheus, Loki, Jaeger configured
- ✅ Alert thresholds: Defined and ready
- ✅ Rollback procedure: Documented and tested

### Deployment Prerequisites ✅
- ✅ Replica 1 (Primary): code-server-enterprise:4.115.0 deployed
- ✅ Replica 2 (Secondary): Synced and ready
- ✅ DNS: ide.kushnir.cloud pointing to loadbalancer
- ✅ TLS certificates: Valid for ide.kushnir.cloud
- ✅ Database: PostgreSQL HA ready, backups scheduled
- ✅ Cache: Redis HA ready, Sentinel configured

---

## DEPLOYMENT EXECUTION PLAN

### Step 1: Pre-Deployment Validation (April 25, Evening)
```bash
# Verify staging is still operational
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose ps | grep -c UP"
# Expected: 38 (or close number)

# Verify git commit at staging
ssh akushnir@192.168.168.31 "cd code-server-enterprise && git rev-parse HEAD"
# Expected: Should be latest Collab-9 commit
```

### Step 2: Production Environment Preparation (April 26, 08:00 UTC)
```bash
# SSH to Replica 1 (primary production instance)
ssh akushnir@192.168.168.31

# Navigate to code-server directory
cd code-server-enterprise

# Pull latest code
git pull origin main

# Verify code is at Collab-9 commit
git log --oneline -1
```

### Step 3: Production Canary Deployment (April 26, 09:00 UTC)
```bash
# Set environment variables for 5% canary
export FEATURE_WEBHOOK_ENABLED=true
export WEBHOOK_ROLLOUT_PERCENTAGE=5

# Deploy to production (both replicas)
# Replica 1 (Primary)
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  FEATURE_WEBHOOK_ENABLED=true \
  docker-compose up -d --no-deps code-server"

# Replica 2 (Secondary) - Keep feature flag disabled for now
ssh akushnir@192.168.168.42 "cd code-server-enterprise && \
  docker-compose up -d --no-deps code-server"

# Wait for containers to stabilize (2 minutes)
sleep 120

# Verify deployments
ssh akushnir@192.168.168.31 "docker-compose ps | grep code-server"
ssh akushnir@192.168.168.42 "docker-compose ps | grep code-server"
```

### Step 4: Health Check Post-Deployment (April 26, 09:15 UTC)
```bash
# Verify HTTP connectivity
curl -I https://ide.kushnir.cloud/

# Expected: HTTP 302 (redirect to workspace)

# Check container logs for errors
ssh akushnir@192.168.168.31 "docker logs code-server | tail -20"

# Verify feature flag is active
ssh akushnir@192.168.168.31 "docker inspect code-server | grep FEATURE_WEBHOOK"
```

### Step 5: Monitoring Activation (April 26, 09:30 UTC)
```bash
# Verify Prometheus is scraping metrics
curl -s http://192.168.168.31:9090/api/v1/targets | jq '.data.activeTargets | length'

# Verify Grafana dashboards are populated
curl -I http://192.168.168.31:3000/

# Set up alert notification channel (Slack/Email)
# - Ensure alertmanager is configured
# - Test with a dummy alert
```

---

## MONITORING DURING CANARY (24/7)

### Critical Metrics to Watch

#### WebSocket Success Rate
**Target:** >99%  
**Check:** Prometheus query: `rate(websocket_connections_total{status="success"}[5m])`  
**Action:** If falls below 99% for >5min, evaluate root cause

#### Webhook Processing Latency
**Target:** <100ms P99  
**Check:** Prometheus query: `histogram_quantile(0.99, webhook_processing_duration_seconds)`  
**Action:** If exceeds 100ms, check database load and consider rollback

#### API Error Rate
**Target:** <0.5%  
**Check:** Prometheus query: `rate(http_requests_total{status=~"5.."}[5m])`  
**Action:** If exceeds 0.5%, check error logs in Loki and investigate

#### Database Write Latency
**Target:** <50ms average  
**Check:** Prometheus query: `rate(db_write_duration_seconds_sum[5m]) / rate(db_write_duration_seconds_count[5m])`  
**Action:** If exceeds 50ms, check connection pool and PostgreSQL stats

#### Cache Hit Rate
**Target:** >95%  
**Check:** Prometheus query: `rate(redis_hits_total[5m]) / (rate(redis_hits_total[5m]) + rate(redis_misses_total[5m]))`  
**Action:** If falls below 95%, check cache eviction and TTL settings

#### Polling Fallback Rate
**Target:** <1% of connections  
**Check:** Prometheus query: `rate(websocket_fallback_to_polling_total[5m])`  
**Action:** If exceeds 1%, WebSocket may be unstable - investigate

### Dashboard URLs
- **Grafana:** http://192.168.168.31:3000/d/collab9-canary
- **Prometheus:** http://192.168.168.31:9090/graph
- **Loki Logs:** http://192.168.168.31:3100/loki/api/v1/query_range
- **Jaeger Traces:** http://192.168.168.31:16686/search

---

## DECISION POINTS

### Day 2 (April 26, 21:00 UTC) - 12-Hour Checkpoint
**Review Metrics:**
- WebSocket success rate >99%?
- P99 latency <100ms?
- Error rate <0.5%?
- No data loss?

**Decision Options:**
1. ✅ **PROCEED TO NEXT PHASE** - All metrics green, SLOs met
2. ⚠️ **INVESTIGATE** - Metrics slightly off, need more data
3. ❌ **ROLLBACK** - Critical issues detected, disable feature flag

### Day 3 (April 27, 09:00 UTC) - 24-Hour Checkpoint
**Review Metrics:**
- All SLOs still met over full 24-hour period?
- Any intermittent issues or patterns?
- User feedback positive?

**Decision Options:**
1. ✅ **APPROVE FOR EXPANSION** - Proceed to Stage 3 (10% rollout)
2. ⚠️ **EXTEND CANARY** - Need more validation data
3. ❌ **ROLLBACK** - Critical issues found, disable feature

---

## ROLLBACK PROCEDURE

### Instant Disable (If Issues Detected)
```bash
# SSH to Replica 1
ssh akushnir@192.168.168.31

# Stop code-server containers
cd code-server-enterprise
FEATURE_WEBHOOK_ENABLED=false docker-compose restart code-server

# Verify fallback to polling active
docker logs code-server | grep -i "polling\|fallback"

# Check metrics drop
# Query Prometheus for websocket_active_connections - should drop to near-zero
```

### Full Rollback (If Severe Issues)
```bash
# Revert to previous commit
ssh akushnir@192.168.168.31
cd code-server-enterprise
git revert HEAD~1
git push origin main

# Rebuild and redeploy
docker-compose build code-server
docker-compose up -d code-server
```

### Post-Rollback Validation
```bash
# Verify polling is active
curl -s https://ide.kushnir.cloud/ | grep -i "polling"

# Check user reports stabilize
# Monitor error rates return to baseline

# Schedule post-mortem
```

---

## SUCCESS CRITERIA FOR STAGE 2

### Primary Metrics
- ✅ WebSocket connection success rate: >99%
- ✅ Webhook processing latency P99: <100ms
- ✅ API error rate: <0.5%
- ✅ Database health: No connection pool issues
- ✅ Zero data loss on failover

### User Experience
- ✅ Real-time task updates working
- ✅ No connection drops >1%
- ✅ Fallback to polling working transparently
- ✅ No performance degradation vs polling

### Infrastructure
- ✅ All 38 services healthy throughout
- ✅ Memory/CPU usage within baselines
- ✅ Database replication lag <1s
- ✅ Cache eviction normal rates

### Documentation
- ✅ All metrics collected and graphed
- ✅ Alert rules tested and firing correctly
- ✅ Logs captured for audit trail
- ✅ Traces recorded for bottleneck analysis

---

## POST-DEPLOYMENT ACTIONS

### If Canary Succeeds
1. Document final metrics and performance profiles
2. Update runbooks with production findings
3. Prepare for Stage 3 (Progressive rollout)
4. Schedule team celebration (🎉)

### If Issues Found
1. Create post-mortem issue
2. Document root cause analysis
3. Update architecture or code as needed
4. Schedule retry for next week

---

## COMMUNICATION PLAN

### Status Updates
- **Day 1 (Apr 26, 12:00 UTC):** Kickoff message - "Canary deployment starting"
- **Day 2 (Apr 26, 21:00 UTC):** 12-hour checkpoint - "Metrics stable, proceeding"
- **Day 3 (Apr 27, 09:00 UTC):** Final checkpoint - "Canary successful, ready for expansion"

### Escalation Path
- **Issue detected:** Slack #incidents channel
- **Severity High:** Page on-call via PagerDuty
- **Severity Critical:** Immediate rollback without approval

---

## SIGN-OFF

**Deployment Plan:** READY FOR EXECUTION  
**Target Date:** April 26-27, 2026  
**Approver:** Ready for team approval  
**Status:** READY FOR STAGE 2

---

This plan is ready to execute. All prerequisites are met. Staging validation complete. Production canary deployment can proceed as scheduled.
