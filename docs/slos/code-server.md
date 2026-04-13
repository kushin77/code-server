# Code-Server SLOs

## Overview

Code-server is the **developer IDE platform** for enterprise development. It impacts developer productivity and must be highly available and performant.

---

## SLIs & SLOs

### SLI-1: Successful Requests
**What we measure**: Percentage of HTTP requests returning 2xx/3xx (excluding client errors)

**Definition**:

successful_requests = COUNT(http_status =~ "^[23]")
failed_requests = COUNT(http_status =~ "^[45]")
success_rate = (successful_requests / (successful_requests + failed_requests)) × 100


**SLO**: **99.5%** successful requests
**Alert threshold**: < 99.3% for 5 minutes
**Impact if breached**: Users unable to access code-server, blocked on all developmen

---

### SLI-2: API Latency (P99)
**What we measure**: 99th percentile of request response time

**Definition**:

P99_latency = PERCENTILE(request_duration_ms, 99)


**SLO**: **< 800ms** P99 latency
**Alert threshold**: > 1000ms for 5 minutes
**Impact if breached**: Poor user experience, context switching, developer frustration

---

### SLI-3: Service Availability
**What we measure**: Availability of code-server service (heartbeat)

**Definition**:

available_seconds = COUNT(health_check_pass)
total_seconds = total_measured_seconds
availability = (available_seconds / total_seconds) × 100


**SLO**: **99.5%** availability
**Alert threshold**: < 99.3% for 10 minutes
**Impact if breached**: Code-server down, all developers blocked

---

## Error Budge

### Calendar Month (30 days)
- **Total possible uptime**: 43,200 minutes
- **SLO**: 99.5%
- **Error budget**: 0.5% × 43,200 = **216 minutes**

### Actions if < 50% error budget remaining
- 🚨 **No new feature deployments** (only critical hotfixes)
- 🚨 **Reliability-only focus** (performance, scalability, incident prevention)
- 🚨 **Daily reliability standup** (until error budget recovers)
- 🚨 **Enhanced monitoring** (increased alerting sensitivity)

---

## Incident Response SLA

When alert triggers:
| Phase | Target | Status |
|-------|--------|--------|
| Page on-call | < 1 minute | ✅ Configured |
| Incident investigation begins | < 3 minutes | ✅ Target: 2 min |
| Mitigation action (rollback/scale/fix) | < 15 minutes | ✅ Target: 5 min |
| Root cause identified | < 1 hour | ✅ Post-mortum review |
| Service restored | < 30 minutes | ✅ Target: 10 min |

---

## Monitoring & Alerting

### Alert Rules

```yaml
alert_code_server_high_error_rate:
  condition: error_rate > 0.5%
  duration: 5 minutes
  severity: critical
  action: page on-call

alert_code_server_latency_high:
  condition: latency_p99 > 1000ms
  duration: 5 minutes
  severity: warning
  action: alert Slack

alert_code_server_down:
  condition: availability < 99%
  duration: 2 minutes
  severity: critical
  action: page on-call immediately


---

## Capacity Planning

### Current Metrics (Baseline)
| Metric | Value | Status |
|--------|-------|--------|
| Peak QPS | 500 req/sec | ✅ Normal |
| P99 Latency | 450ms | ✅ Healthy |
| Error Rate | 0.3% | ✅ Acceptable |
| CPU Usage (peak) | 35% | ✅ Headroom |
| Memory Usage (peak) | 2.1 GB / 4 GB | ✅ Headroom |

### Growth Trajectory
- Engineering team growing: +10 developers/quarter
- Expected QPS growth: +120 req/sec/quarter
- Current headroom: 3-4 quarters before scaling needed

### Scaling Trigger
**When**: Peak QPS > 70% of current capacity (350 req/sec)
**Then**: Provision additional code-server instance + load balancer
**Timeline**: < 1 week provisioning via Terraform

---

## Architecture Decisions Impacting SLO

- **ADR-001**: Containerized deployment supports horizontal scaling
- **ADR-002**: OAuth2 Proxy authentication adds ~50ms latency (acceptable)
- **ADR-003**: Terraform infrastructure reproducible for quick scaling

---

## Review Schedule

### Monthly Review (Last Friday of month)
- [ ] Error budget consumption vs. forecas
- [ ] Incident analysis and trends
- [ ] Deployment freeze status

### Quarterly Review (End of Q)
- [ ] SLO still achievable?
- [ ] Should we tighten SLO?
- [ ] Should we increase error budget (accept lower availability)?
- [ ] Capacity planning update

### Annually (Q1)
- [ ] Full SLO strategy review
- [ ] Alignment with business priorities
- [ ] On-call staffing adequacy
- [ ] New SLOs for new services

---

## Owner & Contacts

- **Primary Owner**: @kushin77
- **Slack Channel**: #code-server-incidents
