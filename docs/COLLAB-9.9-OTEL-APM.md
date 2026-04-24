# OpenTelemetry APM Integration - Implementation Guide

## Overview

This document describes the implementation of the **OpenTelemetry APM Integration** (Collab-9.9), which exposes Jaeger traces and Prometheus metrics in a VS Code sidebar.

## Features

- ✅ **Service Discovery**: Lists instrumented services from Jaeger
- ✅ **Trace Browser**: Shows recent traces per service
- ✅ **Latency Summary**: Surface p95 latency and throughput
- ✅ **Error Visibility**: Track error traces quickly
- ✅ **Prometheus Querying**: Pull metrics from configured Prometheus endpoint
- ✅ **Open in Jaeger**: Jump from trace to Jaeger UI
- ✅ **Auto Refresh**: Keeps the panel current
- ✅ **Caching**: Limits repeated queries

## Setup

### Step 1: Confirm OTel Stack

This feature expects the existing observability stack:

- OpenTelemetry SDK in backend services
- OTel Collector listening on OTLP
- Jaeger UI at `http://localhost:16686`
- Prometheus at `http://localhost:9090`

### Step 2: Configure VS Code

Add settings for the sidebar:

```json
{
  "otelApm.jaegerBaseUrl": "http://localhost:16686",
  "otelApm.prometheusBaseUrl": "http://localhost:9090",
  "otelApm.refreshInterval": 30000
}
```

### Step 3: Ensure Instrumentation

Backend services should call the shared tracing initializer:

```typescript
import { initTracing } from './lib/tracing';

initTracing({
  serviceName: 'code-server',
  serviceVersion: '1.0.0',
});
```

## Usage

### Viewing the APM Panel

1. Open the **OpenTelemetry APM** sidebar
2. Review the service summary cards
3. Expand a service to view recent traces
4. Click a trace to open it in Jaeger

### Metrics Shown

- Services discovered
- Active recent traces
- Error rate
- p95 latency
- Throughput per minute

### Trace Entries

Each trace shows:
- Duration
- Operation name
- Trace ID
- Error indication
- Span count

## Data Sources

### Jaeger

Used for:
- Service discovery
- Recent trace lists
- Trace detail links

Endpoints:
- `/api/services`
- `/api/traces`
- `/api/traces/{traceId}`

### Prometheus

Used for:
- Latency queries
- Error rate queries
- Throughput queries

Query examples:
- `sum(rate(http_server_requests_total[5m]))`
- `sum(rate(http_server_requests_total{status=~"5.."}[5m]))`
- `histogram_quantile(0.95, ...)`

## Backend Integration

### Tracing Helpers

The panel is designed to work with the existing tracing helpers in [apps/backend/src/lib/tracing.ts](../apps/backend/src/lib/tracing.ts):

- `initTracing()` initializes the OTel SDK
- `withSpan()` wraps business operations
- `extractTraceHeaders()` propagates W3C context
- `currentTraceId()` and `currentSpanId()` support log correlation

### Collector Configuration

The collector config in [docs/configs/otel-config.yml](../docs/configs/otel-config.yml) already enables:

- OTLP gRPC/HTTP ingestion
- Jaeger export
- Prometheus export
- Tail sampling with error-first retention

## Troubleshooting

### No Services Found

Check:
1. Jaeger is reachable
2. Services are instrumented
3. Traces are being exported
4. Base URLs match your local environment

### Empty Traces

Check:
1. Service generated traffic recently
2. Lookback window is large enough
3. Sampling policy is not too aggressive
4. Collector queue is healthy

### Metrics Missing

Check:
1. Prometheus is scraping the collector
2. Metric names match the queries
3. The service emits HTTP duration and error metrics

## Performance Notes

- Service list and traces are cached for 60 seconds
- Panel refresh defaults to 30 seconds
- Only the first five services are expanded eagerly
- Queries are limited to recent data to avoid expensive full scans

## Related Files

- [apps/backend/src/lib/tracing.ts](../apps/backend/src/lib/tracing.ts)
- [docs/configs/otel-config.yml](../docs/configs/otel-config.yml)
- [config/grafana/dashboards/structured-logs-telemetry.json](../config/grafana/dashboards/structured-logs-telemetry.json)

---

**Implementation Status**: ✅ COMPLETE  
**Last Updated**: 2026-04-21  
**Issue**: #1174
