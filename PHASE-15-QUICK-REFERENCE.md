# Phase 15: Advanced Load Testing - Quick Reference

**Status**: 🟢 READY  
**Duration**: 30 min (quick) or 24+ hours (extended)  
**Scripts**: 3 main executables ready  

---

## One-Line Execution

```bash
# Quick 30-minute validation
bash scripts/phase-15-advanced-observability.sh && bash scripts/phase-15-extended-load-test.sh --quick

# Extended 24-hour testing
bash scripts/phase-15-extended-load-test.sh --extended
```

---

## Script Reference

| Script | Purpose | Duration | Command |
|--------|---------|----------|---------|
| phase-15-advanced-observability.sh | Deploy custom monitoring | 10 min | `bash scripts/phase-15-advanced-observability.sh` |
| phase-15-extended-load-test.sh | Execute load tests | 30 min - 24h | `bash scripts/phase-15-extended-load-test.sh [opts]` |
| phase-15-deployment.sh | Full deployment orchestrator | 15 min | `bash scripts/phase-15-deployment.sh` |

---

## Key Metrics

| Metric | Target | Quick Test | Extended Test |
|--------|--------|-----------|---------------|
| p99 Latency | <100ms | ✅ Monitor | ✅ Validate |
| Error Rate | <0.1% | ✅ Check | ✅ Sustained |
| Throughput | >100 req/s | ✅ Baseline | ✅ Sustained |
| CPU @ 1000u | <80% | ⏳ Test | ✅ Monitor |
| Memory @ 1000u | <4GB | ⏳ Test | ✅ Monitor |

---

## Quick Test (30 min)

```bash
# 1. Pre-flight (1 min)
docker-compose ps

# 2. Deploy (15 min)
bash scripts/phase-15-advanced-observability.sh

# 3. Test (10 min)
bash scripts/phase-15-extended-load-test.sh --quick

# 4. Review (5 min)
# Navigate to: http://localhost:3000/d/phase-15-performance
```

---

## Extended Test (24+ hours)

```bash
# Start monitoring first
bash scripts/phase-15-extended-load-test.sh --monitor-start

# Run 24-hour test
bash scripts/phase-15-extended-load-test.sh --extended &

# Monitor progress
watch -n 10 'tail /tmp/phase-15-metrics.log'

# After 24 hours: analyze
bash scripts/phase-15-extended-load-test.sh --analyze
```

---

## Go/No-Go Criteria

**🟢 GO** (Proceed to Phase 16):
- ✅ p99 latency <100ms at 1000 concurrent users
- ✅ Error rate <0.1% sustained
- ✅ Zero container restarts
- ✅ Memory stable

**🔴 NO-GO** (Halt and investigate):
- ❌ p99 latency >150ms sustained
- ❌ Error rate >0.5%
- ❌ Container crash or OOM
- ❌ Memory leak detected

---

## Dashboards

- **Performance**: http://localhost:3000/d/phase-15-performance
- **SLOs**: http://localhost:3000/d/phase-15-slo
- **System**: http://localhost:3000/d/system-metrics

---

## Common Commands

```bash
# Check Redis cache
docker exec phase15_redis_cache redis-cli INFO memory

# View load test progress
tail -f /tmp/phase-15-metrics.log

# Check alert status
curl -s http://localhost:9093/api/v1/alerts | jq '.[].labels.alertname'

# Manual SLO check
curl -k -w '\nLatency: %{time_total}\n' https://localhost/health
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Redis won't start | Check disk space, verify docker daemon |
| Latency high | Check CPU, memory, network utilization |
| Tests not collecting metrics | Verify Prometheus targets are UP |
| Dashboards not updating | Restart Grafana service |

---

## Team Contacts

- **Infrastructure**: Monitoring and deployment
- **Performance**: Load test interpretation
- **On-Call**: Incident response during test

---

*For full details, see PHASE-15-EXECUTION-PLAN.md*
