# Observability Platform Documentation Index

**Issue:** #3151 - Unified Logging, Monitoring, Observability + SLOG Error Capture  
**Purpose:** Central hub for observability documentation  
**Status:** Production Ready  
**Last Updated:** May 1, 2026

## Documentation Structure

### 1. Operational Runbooks

| Document | Purpose | Audience |
|----------|---------|----------|
| [incident-response-playbook.md](../incident-response-playbook.md) | Procedures for responding to production incidents | On-call engineers, incident commanders |
| [OBSERVABILITY-GUIDE.md](../OBSERVABILITY-GUIDE.md) | Complete observability stack overview | Platform engineers, ops team |
| [OPERATIONS_QUICK_REFERENCE.md](../OPERATIONS_QUICK_REFERENCE.md) | Quick reference for common ops tasks | All engineers |

### 2. Error Handling & Taxonomy

| Document | Purpose | Audience |
|----------|---------|----------|
| [slog-taxonomy.md](./slog-taxonomy.md) | Error categories, severity classification, logging levels | All engineers |
| [retention-policies.md](./retention-policies.md) | Data retention windows and enforcement | Ops, platform team |

### 3. Query Reference

| Document | Purpose | Audience |
|----------|---------|----------|
| [observability-query-guide.md](./observability-query-guide.md) | How to query logs, metrics, and traces | All engineers, SREs |

## Getting Started

### For On-Call Engineers

1. **Incident starts** → Read [incident-response-playbook.md](../incident-response-playbook.md)
2. **Need diagnostics** → Use [observability-query-guide.md](./observability-query-guide.md)
3. **Classify severity** → Reference [slog-taxonomy.md](./slog-taxonomy.md)
4. **Quick checklist** → See [OPERATIONS_QUICK_REFERENCE.md](../OPERATIONS_QUICK_REFERENCE.md)

### For Development Teams

1. **Understand our observability** → Read [OBSERVABILITY-GUIDE.md](../OBSERVABILITY-GUIDE.md)
2. **How to log properly** → See [slog-taxonomy.md](./slog-taxonomy.md) logging levels
3. **Write a dashboard** → Use [observability-query-guide.md](./observability-query-guide.md) examples

### For Platform Engineers

1. **Retention and storage** → See [retention-policies.md](./retention-policies.md)
2. **Scaling observability** → Read [OBSERVABILITY-GUIDE.md](../OBSERVABILITY-GUIDE.md) scaling section
3. **Error categorization** → Review [slog-taxonomy.md](./slog-taxonomy.md)

## Signal Types

### Logs (Loki)

Structured and unstructured logs from all containers.

- **Retention**: 7-90 days (per [retention-policies.md](./retention-policies.md))
- **Query**: [LogQL in observability-query-guide.md](./observability-query-guide.md#logs-loki--logql)
- **Sources**: Containerized services via Promtail

### Metrics (Prometheus)

Time-series metrics for system and application health.

- **Retention**: 15 days (per [retention-policies.md](./retention-policies.md))
- **Query**: [PromQL in observability-query-guide.md](./observability-query-guide.md#metrics-prometheus--promql)
- **Scrape interval**: 15 seconds

### Traces (Tempo)

Distributed traces showing request causality across services.

- **Retention**: 24 hours (per [retention-policies.md](./retention-policies.md))
- **Query**: [TraceQL in observability-query-guide.md](./observability-query-guide.md#traces-tempo--traceql)
- **Sampling**: 100% (all traces collected)

## Severity Classification

Reference [slog-taxonomy.md](./slog-taxonomy.md#severity-classifications):

| Level | Response Time | Routing | Retention |
|-------|---------------|---------|-----------|
| CRITICAL | 5 min | PagerDuty + Slack | 90 days |
| WARNING | 15 min | Slack | 30 days |
| INFO | 1 hour | Logs only | 14 days |
| DEBUG | 4 hours | Logs only | 7 days |

## Common Queries

All examples: [observability-query-guide.md](./observability-query-guide.md)

### Find Errors

**Logs:**
```logql
{level="ERROR"} | __error__=""
```

**Metrics:**
```promql
rate(http_errors_total[5m])
```

### Find Slow Requests

**Traces:**
```traceql
{ duration > 1s }
```

**Metrics:**
```promql
histogram_quantile(0.95, http_request_duration_seconds_bucket)
```

### Find Database Issues

**Logs:**
```logql
{job="postgres"} | "replication" or "lag" or "timeout"
```

**Metrics:**
```promql
pg_stat_replication_lag_bytes
```

## Alert Channels

- **Critical alerts**: PagerDuty + #critical-alerts (Slack)
- **Warnings**: #warnings (Slack)
- **API team**: #api-team (Slack)
- **Database team**: #database-team (Slack)

See [incident-response-playbook.md](../incident-response-playbook.md#critical-incidents-service-outage) for full routing.

## Compliance & Standards

- **SLOG taxonomy**: [slog-taxonomy.md](./slog-taxonomy.md)
- **Auth log retention**: 90 days (SOC2/HIPAA per [slog-taxonomy.md](./slog-taxonomy.md#compliance--retention))
- **Data retention**: [retention-policies.md](./retention-policies.md)
- **Incident response**: [incident-response-playbook.md](../incident-response-playbook.md)

## Key Contacts

- **Observability Lead**: Specified in .instructions.md
- **On-Call Rotation**: See incident-response-playbook.md
- **Escalation Path**: Page incident commander for CRITICAL incidents

## Issue Resolution Process

For #3151 evidence/improvement requests:

1. Check current state → [OBSERVABILITY-GUIDE.md](../OBSERVABILITY-GUIDE.md)
2. Reference taxonomy → [slog-taxonomy.md](./slog-taxonomy.md)
3. Query data → [observability-query-guide.md](./observability-query-guide.md)
4. Add retention rules → [retention-policies.md](./retention-policies.md)
5. Document runbook → [incident-response-playbook.md](../incident-response-playbook.md)

---

**Architecture:** Loki (logs) + Prometheus (metrics) + Tempo (traces) + Grafana (visualization)  
**Deployment:** Docker Compose in primary + replica (HA)  
**Scope:** All code-server services, containers, and infrastructure
