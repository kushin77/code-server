# Production Alerting Guide

## Overview

This document describes the comprehensive alerting rules for production infrastructure monitoring and SLA compliance.

## Alert Severity Levels

- **Critical**: Immediate action required, service impairment or failure
- **High**: Urgent attention needed, degraded performance
- **Warning**: Preventive action recommended, capacity approaching limits

## Alert Categories

### 1. Application Health
- API health checks
- Error rate monitoring
- Response time tracking

### 2. Infrastructure Health
- Database connectivity and replication
- Container health and resource usage
- System resource utilization

### 3. Deployment Health
- Kubernetes deployment status
- Pod lifecycle events
- Resource exhaustion events

### 4. Capacity Monitoring
- Disk space availability
- Network performance
- Memory utilization

### 5. Security Alerts
- Authentication failures
- Policy violations
- Suspicious activity patterns

### 6. Business Metrics
- SLA compliance tracking
- Latency thresholds
- Availability percentages

## Runbook Integration

Each alert includes a runbook reference for quick remediation:

```
docs/RUNBOOK-<ALERT-CATEGORY>.md
```

Follow the runbook for step-by-step recovery procedures.

## Configuration

### Prometheus
- Configuration: `${PROMETHEUS_RULES}`
- Reload: `curl -X POST http://prometheus:9090/-/reload`

### Grafana
- Configuration: `${GRAFANA_ALERTS}`
- Import via: Grafana UI → Alerts → Import

## Testing Alerts

1. **Dry Run**: Test alert rules without firing
   ```bash
   promtool check rules prometheus-rules.yaml
   ```

2. **Query Validation**: Test individual alert expressions
   ```
   http://prometheus:9090/api/v1/query?query=<EXPRESSION>
   ```

3. **Alert Testing**: Simulate alert conditions in staging
   ```bash
   scripts/ops/test-alerts-staging.sh
   ```

## SLA Commitments

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Availability | 99.9% | < 99% |
| Response Time (p95) | 1s | > 1s for 10m |
| Error Rate | < 0.1% | > 0.5% for 5m |
| Database Replication Lag | < 1s | > 300s for 5m |

## Escalation Policy

1. **Tier 1**: Automated remediation (if available)
2. **Tier 2**: On-call engineer (within 15 min for critical)
3. **Tier 3**: Engineering manager (for SLA breach)
4. **Tier 4**: Director/VP (for business impact)

## Maintenance

- Review alert rules monthly
- Update thresholds based on metrics trends
- Test runbook procedures quarterly
- Archive resolved issues for analysis

---

**Last Updated**: 2026-04-25
**Version**: 1.0
**Governance**: GOV-002 - All alerts documented with runbooks
