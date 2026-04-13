# SLA/SLO Definitions and Tracking

## Service Level Objectives (SLOs)

### Code-Server (IDE Service)

**Service Definition**: Time-sharing IDE for prompt engineering and code execution

**SLI #1: Availability (Uptime)**
```
Availability = (Total Requests - 5xx Errors) / Total Requests
Target: 99.95% over 30-day rolling window
```

Implementation:
```prometheus
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])
# Alert if > 0.1% (5xx rate)
```

**SLI #2: Latency**
```
P99 Response Time < 1 second
P95 Response Time < 500ms
Target: 99% of requests meet latency within each SLO window
```

Implementation:
```prometheus
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) < 1
```

**SLI #3: Correctness**
```
Successful auth flows / Total auth flows
Target: 99.9% - fail closed, not open
```

**Error Budget** (Monthly):
```
Total minutes available = 30 days × 24h × 60 = 43,200 minutes
Allowed downtime = 43,200 × (1 - 0.9995) = 21.6 minutes/month
```

If downtime exceeds 21.6 minutes, we've violated SLO and must conduct post-mortem.

---

### Agent API (Backend Service)

**Service Definition**: REST API for agent orchestration and model inference requests

**SLI #1: Availability**
```
Target: 99.9% (9 hours downtime allowed annually, 43.2 minutes/month)
Rate limiting counts as availability failure if breaching legitimate traffic
```

**SLI #2: Latency**
```
P50: < 100ms (median request)
P99: < 1 second (99th percentile)
Target: 99.5% of requests meet SLI
```

**SLI #3: Throughput**
```
Minimum sustainable throughput: 100 requests/second
During burst: 500 requests/second for up to 5 minutes
```

**Error Budget** (Monthly):
```
Allowed downtime = 43,200 × (1 - 0.999) = 43.2 minutes
Allowed errors (5xx) = 0.1% of 30M requests = 30,000 errors
```

---

### Embeddings Service (Batch Processing)

**Service Definition**: Vector embedding generation for semantic search

**SLI #1: Availability**
```
Service responding to health checks: 99%
(Batch jobs can queue, so availability is about scheduler health)
Target: 99% uptime
```

**SLI #2: Latency**
```
P99 embedding generation: < 2 seconds per request
Queue wait time: < 5 seconds (P95)
Target: 99% of requests meet combined latency
```

**SLI #3: Throughput**
```
Process at least 10,000 embeddings/hour
```

**Error Budget**:
```
Allowed downtime = 43,200 × (1 - 0.99) = 432 minutes
More lenient due to batch nature
```

---

## Burn Rate Tracking

To trigger automated responses to SLO violations:

```prometheus
# Calculate burn rate over 5-minute windows
# High burn rate = approaching SLO violation

burn_rate_5m = (1 - availability_5m) / (1 - slo_target)

if burn_rate_5m > 10 {
  # We're violating SLO at 10x the expected rate
  # Alert severity: SEV2
  # Action: Start investigation, consider traffic mitigation
}

if burn_rate_5m > 100 {
  # Complete failure mode
  # Alert severity: SEV1
  # Action: Immediate escalation, rollback consideration
}
```

**Alert Rules** (in Prometheus):
```yaml
groups:
  - name: slo_alerts
    rules:
      - alert: HighBurnRate
        expr: |
          (1 - http_requests_total{status!~"5.."} / http_requests_total) 
          / (1 - 0.9995) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "SLO burn rate {{ $value | humanize }}x above target"

      - alert: CriticalBurnRate
        expr: |
          (1 - http_requests_total{status!~"5.."} / http_requests_total) 
          / (1 - 0.9995) > 100
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "CRITICAL: SLO violation imminent"
```

---

## Service Level Agreement (SLA) - Customer Facing

**What we commit to customers:**

| Service | Uptime SLA | Monthly Credit |
|---------|-----------|-----------------|
| Standard Tier | 99.9% | 5% account credit |
| Premium Tier | 99.95% | 10% account credit |
| Enterprise Tier | 99.99% | 25% account credit + 1hr response |

**Calculation**:
```
If actual_uptime < SLA_target:
  credit_percent = (SLA_target - actual_uptime) / SLA_target × credit_factor
  customer_credit = monthly_bill × credit_percent
```

**Exclusions** (downtime not counted toward SLA):
- Planned maintenance (24-hour notice, limited to 4 hours/month)
- Customer misconfiguration
- Third-party services (e.g., Keycloak OOM)
- DDoS attack (unless due to us)
- Acts of God

---

## Monthly SLO Review

Every 30 days, review:

1. **Availability Metrics**
   - Did we meet 99.95% uptime for code-server?
   - Any incidents that contributed to downtime?
   - Trends in downtime sources

2. **Latency Metrics**
   - P99 response times trending up/down?
   - Any spikes that indicate performance issues?
   - Database query performance

3. **Error Budget Status**
   - How much error budget remains this month?
   - On track to meet annual SLO?
   - Spend rate vs projected

4. **Incident Analysis**
   - Which incidents consumed the most error budget?
   - Could they have been prevented?
   - Process improvements needed?

**Template**:
```markdown
# SLO Review - April 2026

## Metrics
- Code-Server Availability: 99.96% ✅ (Target: 99.95%)
- Code-Server P99 Latency: 847ms ✅ (Target: 1000ms)
- Agent API Availability: 99.87% ❌ (Target: 99.9%)
- Agent API P99 Latency: 1.2s ❌ (Target: 1000ms)

## Incidents Impacting SLO
- Apr 5: Database upgrade (45 min downtime) - Agent API
- Apr 12: Memory leak in embeddings (20 min degradation, not full outage)

## Error Budget Status
- Code-Server: 12.5 min allowed, 3 min used = 75% budget remaining ✅
- Agent API: 43.2 min allowed, 52 min used = OVER BUDGET ❌
- Embeddings: 432 min allowed, 20 min used = 95% budget remaining ✅

## Action Items
- [ ] Root cause database upgrade issues
- [ ] Implement automated database upgrade testing
- [ ] Add memory regression tests for embeddings
```

---

## Quarterly SLO Goals

Set aspirational targets:

| Q | Code-Server | Agent API | Embeddings | Notes |
|---|-------------|-----------|------------|-------|
| Q1 2026 | 99.90% | 99.85% | 98.5% | Baseline establishment |
| Q2 2026 | 99.93% | 99.88% | 99.0% | Improve via new infra |
| Q3 2026 | 99.95% | 99.90% | 99.2% | Approach production targets |
| Q4 2026 | 99.95% | 99.95% | 99.5% | Full production maturity |

---

## Communicating SLO Changes

When changing SLO target:

1. **Announce**: 30-day notice to customers
2. **Explain**: Why we're changing (raising is good, lowering requires justification)
3. **Stagger**: Implement new SLO at start of calendar month
4. **Monitor**: Watch closely for first 48 hours

Example:
```
Subject: Uptime SLA Improvement - Code-Server Premium Tier

Effective May 1, 2026, we're improving our uptime commitment from 99.9% to 99.95%
for Premium tier customers.

This reflects our new Kubernetes infrastructure and improved monitoring. We're
confident in this commitment based on Q1 performance.

Current premium customers: No action needed. Your SLA automatically upgrades.
```

---

## SLO Target Rationale

**Why 99.95% for Code-Server?**
- Allows 21.6 minutes downtime/month
- Can tolerate 1 planned maintenance (4 hours/year with notice)
- Competitive with Heroku ($50 platform), better than competitors
- Achievable with 2-region deployment + automated failover

**Why 99.9% for Agent API?**
- More tolerant (43.2 min allowed)
- Can handle database maintenance without violating SLO
- Acceptable for enterprise use cases
- Aligns with industry standards for async APIs

**Why 99% for Embeddings?**
- Batch processing - single failures less critical
- Inherent variability in LLM inference
- Queueing absorbs short outages
- Relaxed to allow for model updates

---

## Customer Communication

When SLO is violated and customer is eligible for credit:

```markdown
# SLO Violation Notice - April 2026

Dear Customer,

We experienced a service outage on April 5, 2026, affecting our Code-Server
Premium tier for 45 minutes (14:00-14:45 UTC).

Our commitment: 99.95% uptime (21.6 min allowed/month)
Actual uptime: 99.89% (62.6 min downtime)
Shortfall: 40.8 minutes

We're issuing you a 10% account credit ($XXX) as per our SLA.

**What happened**: Database upgrade failed to coordinate with Kubernetes rollout.

**What we fixed**: 
- Automated database upgrade validation before deployment
- Coordination workflow with infrastructure team
- Better health checks for critical dependencies

**What we're monitoring**: Error budgets and burn rate in real-time dashboard.

Thank you for your patience. We're committed to improving reliability.

Best regards,
Operations Team
```
