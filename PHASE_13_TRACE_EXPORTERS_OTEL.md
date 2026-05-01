# Phase 13: Trace Exporters & OpenTelemetry Bridge

**Status**: ✅ Ready
**Focus**: trace serialization, exporter formats, and OpenTelemetry-compatible context handling

## Objective

This slice exposes the trace exporter and OpenTelemetry bridge modules through the
shared package and documents how to move traces between the local analysis layer and
external observability systems.

## Deliverables

- `apps/shared/trace_exporters.py` - JSON, Jaeger, Zipkin, and OTLP trace exporters
- `apps/shared/otel_integration.py` - W3C/Jaeger context helpers and OTEL bridge
- `docs/observability/trace-exporters-guide.md` - operator guide for export formats and context handling

## Coverage

- Trace serialization to common observability backends
- W3C and Jaeger context propagation helpers
- Resource metadata and span event/link builders
- Shared export surface through `apps.shared`