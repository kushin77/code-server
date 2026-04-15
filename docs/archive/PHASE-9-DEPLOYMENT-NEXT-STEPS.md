# Phase 9 Production Deployment - Next Steps
## Prepared for Immediate Execution
### April 17, 2026

---

## Status: ✅ ALL INFRASTRUCTURE-AS-CODE COMPLETE & COMMITTED

All three phases (9-A, 9-B, 9-C) are **production-ready** and awaiting deployment to primary/replica hosts.

---

## Deployment Sequence (Recommended Order)

### Phase 9-A: HAProxy Load Balancing & High Availability
**Duration**: 30-45 minutes  
**Status**: ✅ IaC Complete (Commit: ff12e1e5)  
**Files**: `terraform/phase-9a-*.tf`, `scripts/deploy-phase-9a.sh`

#### Deploy Steps
```bash
# 1. SSH to primary host
ssh akushnir@192.168.168.31

# 2. Deploy HAProxy
cd /code-server-enterprise
bash scripts/deploy-phase-9a.sh

# 3. Verify HAProxy is running
docker ps | grep haproxy
curl http://192.168.168.31:8404/stats  # HAProxy stats

# 4. Deploy Keepalived on primary
docker-compose up -d keepalived

# 5. Verify VIP is active on primary
ip addr show | grep 192.168.168.100

# 6. Deploy Keepalived on replica (192.168.168.42)
ssh akushnir@192.168.168.42
cd /code-server-enterprise
docker-compose up -d keepalived

# 7. Test failover
bash scripts/test-failover.sh
```

**Validation**:
- HAProxy listening on port 80/443
- Keepalived VRRP communication active
- VIP 192.168.168.100 responds to ping
- All 7 backends healthy in HAProxy stats

---

### Phase 9-B: Observability Stack (Jaeger, Loki, Prometheus SLOs)
**Duration**: 60-90 minutes  
**Status**: ✅ IaC Complete (Commit: db9a3bf8)  
**Files**: `terraform/phase-9b-*.tf`, `scripts/deploy-phase-9b.sh`

#### Deploy Steps
```bash
# 1. Deploy Jaeger tracing
ssh akushnir@192.168.168.31
cd /code-server-enterprise
docker-compose up -d jaeger

# 2. Deploy Loki + Promtail
docker-compose up -d loki promtail

# 3. Update Prometheus to include SLO recording rules
bash scripts/deploy-phase-9b.sh

# 4. Verify services are running
curl http://192.168.168.31:16686/api/services  # Jaeger
curl http://192.168.168.31:3100/api/v1/status/buildinfo  # Loki
curl http://192.168.168.31:9090/api/v1/query?query=up  # Prometheus

# 5. Verify Grafana dashboards are available
curl http://192.168.168.31:3000/api/dashboards/db/slos  # SLO dashboard
```

**Validation**:
- Jaeger UI accessible on port 16686
- Loki query endpoint responsive
- Prometheus SLO metrics being collected
- Grafana SLO dashboard populated
- Logs flowing from Promtail to Loki
- Traces being captured from instrumented services

---

### Phase 9-C: Kong API Gateway
**Duration**: 60-90 minutes  
**Status**: ✅ IaC Complete (Commit: 3f968de2)  
**Files**: `terraform/phase-9c-*.tf`, `scripts/deploy-phase-9c.sh`

#### Deploy Steps
```bash
# 1. Deploy Kong PostgreSQL database (if not already running)
ssh akushnir@192.168.168.31
cd /code-server-enterprise
docker-compose up -d postgres  # (if not already running)

# 2. Deploy Kong migrations container
docker-compose run kong kong migrations bootstrap

# 3. Deploy Kong gateway
docker-compose up -d kong

# 4. Deploy Konga admin UI (optional)
docker-compose up -d konga

# 5. Verify Kong is running
curl http://192.168.168.31:8001/  # Kong Admin API

# 6. Configure routes via Admin API
bash scripts/deploy-phase-9c.sh

# 7. Test proxy endpoints
curl http://192.168.168.31:8000/health  # Proxy health
curl http://192.168.168.31:8001/services  # List services
curl http://192.168.168.31:8001/routes  # List routes
```

**Validation**:
- Kong proxy listening on port 8000/8443
- Kong Admin API responsive on port 8001
- Routes properly configured (13 routes)
- Services connected to upstreams (6 services)
- Rate limiting policies enforced
- Authentication working (OAuth2, API Key)
- Prometheus metrics being collected

---

## Parallel Deployment Option

All three phases can be deployed in parallel since they have no direct dependencies:

```bash
# Terminal 1: Deploy Phase 9-A
ssh akushnir@192.168.168.31
bash scripts/deploy-phase-9a.sh
bash scripts/test-failover.sh

# Terminal 2: Deploy Phase 9-B
ssh akushnir@192.168.168.31
bash scripts/deploy-phase-9b.sh
curl http://192.168.168.31:16686/api/services

# Terminal 3: Deploy Phase 9-C
ssh akushnir@192.168.168.31
bash scripts/deploy-phase-9c.sh
curl http://192.168.168.31:8000/health
```

**Total Time**: ~90 minutes (parallel) vs 180 minutes (sequential)

---

## Post-Deployment Verification

### Health Checks
```bash
# Check all services are running
docker ps | grep -E "haproxy|keepalived|jaeger|loki|kong|prometheus|grafana"

# Verify virtual IP
ip addr show | grep 192.168.168.100

# Test load balancing
for i in {1..10}; do curl http://192.168.168.100:80/health; done

# Check rate limiting
for i in {1..150}; do curl http://192.168.168.31:8000/ & done
# Should see 429 status codes after rate limit exceeded

# Verify tracing is working
curl http://192.168.168.31:16686/api/traces?service=code-server | jq '.traces | length'

# Verify logs are being aggregated
curl 'http://192.168.168.31:3100/api/v1/query?query={job="docker"}'

# Verify SLO metrics
curl 'http://192.168.168.31:9090/api/v1/query?query=slo_availability' | jq '.data.result'
```

### Integration Tests
```bash
# Test end-to-end request flow
curl -v http://192.168.168.31:8000/
# Should trace through Kong → HAProxy → Code-server

# Test authentication
curl -H "Authorization: Bearer invalid-token" http://192.168.168.31:8000/
# Should get 401 Unauthorized

# Test rate limiting
ab -n 200 -c 10 http://192.168.168.31:8000/
# Should show 429 responses after threshold

# Test failover
# In one terminal:
watch -n 1 'ip addr show | grep 192.168.168.100'

# In another:
sudo systemctl stop keepalived  # on primary

# VIP should move to replica within 15-30 seconds
```

---

## Troubleshooting Guide

### HAProxy Issues
```bash
# Check HAProxy logs
docker logs haproxy | tail -50

# Verify backend health
curl http://192.168.168.31:8404/stats

# Test direct backend
curl http://192.168.168.31:80/health
```

### Keepalived Issues
```bash
# Check Keepalived logs
docker logs keepalived | tail -50

# Verify VRRP state
docker exec keepalived ip addr show

# Check priority
docker exec keepalived cat /etc/keepalived/keepalived.conf | grep priority
```

### Jaeger Issues
```bash
# Check Jaeger logs
docker logs jaeger | tail -50

# Verify OTLP endpoints
curl http://192.168.168.31:14250  # gRPC endpoint
curl http://192.168.168.31:4318   # HTTP endpoint

# Query traces
curl http://192.168.168.31:16686/api/traces?service=code-server
```

### Loki Issues
```bash
# Check Loki logs
docker logs loki | tail -50

# Verify ingestion
curl http://192.168.168.31:3100/api/v1/query?query='{job="docker"}'

# Check Promtail
docker logs promtail | tail -50
```

### Kong Issues
```bash
# Check Kong logs
docker logs kong | tail -50

# Verify database connectivity
docker logs kong | grep postgres

# Run Kong migrations again
docker-compose run kong kong migrations bootstrap

# Reload plugins
curl -X POST http://192.168.168.31:8001/config
```

---

## Rollback Procedure (If Needed)

### Rollback Individual Phases
```bash
# Rollback Phase 9-C (Kong)
docker-compose down kong konga

# Rollback Phase 9-B (Observability)
docker-compose down jaeger loki promtail

# Rollback Phase 9-A (HAProxy/HA)
docker-compose down haproxy keepalived
```

### Complete Rollback
```bash
# Remove all Phase 9 containers
docker-compose down

# Git rollback to prior commit
git revert 3f968de2  # Phase 9-C
git revert db9a3bf8  # Phase 9-B
git revert ff12e1e5  # Phase 9-A

# Redeploy Phase 8 or earlier
git checkout phase-7-deployment
bash scripts/deploy-phase-8.sh
```

**Rollback Time**: < 5 minutes

---

## Monitoring During & After Deployment

### Real-time Metrics Dashboard
```bash
# Open Grafana
open http://192.168.168.31:3000
# Login: admin / admin123
# Dashboard: "Phase 9 Infrastructure"
```

### Real-time Logs
```bash
# Monitor HAProxy traffic
docker logs -f haproxy | grep -E "GET|POST|HTTP"

# Monitor request flow
docker logs -f code-server | grep -E "request|error"

# Monitor Kong
docker logs -f kong | grep -E "error|rate.*limit"
```

### Prometheus Queries
```
# Proxy latency
histogram_quantile(0.99, kong_http_request_duration_ms)

# Error rate
rate(kong_http_requests_total{status=~"5.."}[5m])

# Upstream health
kong_upstream_target_health

# Cache hits
rate(kong_cache_hit_total[5m]) / rate(kong_http_requests_total[5m])
```

---

## SLO Validation Post-Deployment

After all phases are deployed, validate these SLO targets:

| Target | Metric | Expected |
|--------|--------|----------|
| HAProxy Availability | uptime | 99.99% |
| Kong Gateway Availability | proxy health | 99.95% |
| Trace Capture Rate | jaeger_traces_captured | 99.9% |
| Log Ingestion | loki_ingestion_rate | 99.9% |
| Latency P99 | request duration | < 500ms |
| Error Rate | 5xx responses | < 0.1% |
| RTO | failover time | < 120s |
| RPO | replication lag | < 30s |

---

## Known Issues & Workarounds

### Issue: Kong Admin API Returns 500
**Workaround**: Run migrations again
```bash
docker-compose down kong
docker-compose run kong kong migrations bootstrap
docker-compose up -d kong
```

### Issue: Keepalived Not Electing Master
**Workaround**: Restart Keepalived with increased verbosity
```bash
docker-compose logs -f keepalived
# Check priority and state in logs
```

### Issue: Loki Query Returns No Results
**Workaround**: Check Promtail is feeding logs
```bash
docker logs promtail | grep -E "sent|error"
docker exec loki loki-logcli query '{job="docker"}'
```

### Issue: Jaeger Shows No Traces
**Workaround**: Verify instrumentation is sending traces
```bash
docker logs code-server | grep -E "OTLP|trace"
curl -s http://192.168.168.31:16686/api/services | jq .
```

---

## Session Handoff

**Status**: ✅ All IaC complete, committed, ready for production deployment  
**Git Branch**: phase-7-deployment (all commits here)  
**Production Target**: 192.168.168.31 (primary), 192.168.168.42 (replica)  
**Estimated Deployment Time**: 90-180 minutes (parallel/sequential)  
**Next Phase**: Phase 9-D (Backup & Disaster Recovery)

---

## Files to Reference

- **PHASES-8-9-COMPLETION-REPORT.md** - Comprehensive status
- **PHASE-9A-HAPROXY-COMPLETION.md** - HAProxy details
- **PHASE-9B-OBSERVABILITY-COMPLETION.md** - Observability details
- **PHASE-9C-KONG-COMPLETION.md** - Kong details
- **INCIDENT-RUNBOOKS.md** - Production runbooks
- **FAILOVER-RUNBOOK.md** - Failover procedures

---

**Ready for Production Deployment** ✅  
**No Blockers** ✅  
**All Standards Met** ✅  
