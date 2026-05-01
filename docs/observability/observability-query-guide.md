# Unified Observability Query Guide

**Issue:** #3151 - Unified Logging, Monitoring, Observability + SLOG Error Capture  
**Purpose:** Unified reference for querying logs, metrics, and traces  
**Status:** Active query reference

## Overview

The observability stack provides a single pane of glass across:
- **Logs** (Loki) - structured and unstructured log data
- **Metrics** (Prometheus) - time-series metrics
- **Traces** (Tempo) - distributed traces with causality

All are queryable through Grafana dashboards or directly via API.

## Logs (Loki / LogQL)

### Basic Log Query

Find errors from the API gateway in the last hour:

```logql
{job="api-gateway"} | level="ERROR" | __error__=""
```

### Filter by Service and Pattern

Find timeout errors in the database service:

```logql
{job="postgres"} | "timeout" or "deadline exceeded"
```

### Aggregate Error Counts

Count errors by service over 5-minute windows:

```logql
sum by (job) (
  count_over_time({level="ERROR"} [5m])
)
```

### Multi-Label Search

Find all CRITICAL logs from the primary replica:

```logql
{level="CRITICAL", host="primary"}
```

## Metrics (Prometheus / PromQL)

### Service Availability

Check the uptime of all services:

```promql
up{job=~"code-server-.*"}
```

### API Request Rate and Errors

Error rate of the API gateway (5-minute rolling average):

```promql
(
  sum(rate(http_requests_total{job="api-gateway", status=~"5.."}[5m]))
) / (
  sum(rate(http_requests_total{job="api-gateway"}[5m]))
) * 100
```

### Database Replication Lag

Monitor replication lag between primary and replica:

```promql
pg_stat_replication_lag_bytes / 1024  # Convert to KB
```

## Traces (Tempo / TraceQL)

### Find Slow Requests

Traces where the API gateway request took > 1 second:

```traceql
{ job="api-gateway" && duration > 1s }
```

### Trace Error Context

Get all traces that resulted in a 5xx error:

```traceql
{ http_status_code >= 500 }
```

## Correlated Queries: Alert → Trace → Logs → Change

### Step 1: Alert fires (Prometheus)

Trigger: `ErrorRateSLOViolation` alert indicates error rate > 1%

### Step 2: Find affected trace (Tempo)

```traceql
{ service="api-gateway" && duration > 500ms && http_status_code >= 500 }
```

### Step 3: Examine logs from trace (Loki)

Once you have a trace ID from Tempo, search Loki:

```logql
{trace_id="<trace_id_from_tempo>"}
```

### Step 4: Check recent changes (Git)

```bash
git log --oneline --since="1 hour ago" -- \
  apps/api-gateway/src/**/*.ts
```

## SLOG Taxonomy Queries

Use the [SLOG Taxonomy](./slog-taxonomy.md) to construct queries by error category:

### Find All Critical Infrastructure Events

```logql
{severity="CRITICAL"} | level="ERROR"
```

### Find Database Replication Issues

```logql
{job="postgres"} | "replication" | level=~"WARNING|ERROR"
```

### Find Service Degradation Events

```logql
{level="WARNING"} | "degradation" or "latency" or "exhaustion"
```

## Grafana Dashboard Links

Pre-built dashboards for common queries:

- **System Health**: <http://localhost:3000/d/system-health>
- **API Performance**: <http://localhost:3000/d/api-perf>
- **Database**: <http://localhost:3000/d/database>
- **Traces**: <http://localhost:3000/d/traces>

## Best Practices

1. **Always include time range**: Default is 1 hour; adjust as needed
2. **Use labels efficiently**: Narrow by job/service first, then pattern
3. **Aggregate appropriately**: Use `sum`, `avg`, `rate` to avoid cardinality explosion
4. **Correlate across signals**: Start with metrics alert → find trace → examine logs
5. **Check retention**: Logs older than 7 days may be pruned (see [Retention Policies](./retention-policies.md))

---

**Last Updated:** May 1, 2026  
**Owner:** Observability / Platform
