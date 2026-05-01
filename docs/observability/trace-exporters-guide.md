# Trace Exporters and OpenTelemetry Bridge Guide

**Phase**: 13 - Trace Analysis & Insights  
**Audience**: SREs, platform engineers, and observability maintainers  
**Scope**: export formats, trace serialization, and OpenTelemetry-compatible context handling

The trace exporter modules convert the shared trace data into common observability
formats so it can move between the in-app analysis layer and external systems.

## Modules

### `apps/shared/trace_exporters.py`
Exports trace data to standard formats:

- `JSONExporter` for readable trace payloads
- `JaegerExporter` for Jaeger-compatible trace batches
- `ZipkinExporter` for Zipkin B3 format
- `OTLPExporter` for OpenTelemetry Protocol output

### `apps/shared/otel_integration.py`
Provides the bridge to OpenTelemetry conventions:

- W3C and Jaeger trace context parsing and injection
- Resource and instrumentation-scope helpers
- Span event and link builders
- An OpenTelemetry bridge for resource metadata and kind/status conversion

## Typical Workflow

1. Analyze a trace with `trace_analysis.py` and `trace_insights.py`.
2. Convert the result into an exported trace with `trace_exporters.py`.
3. Use `otel_integration.py` when a service needs W3C/Jaeger header interop or OTEL-shaped metadata.
4. Feed the exported payload to the target observability backend.

## When To Use Which Exporter

- JSON when you want quick debugging or human review.
- Jaeger when you need direct compatibility with the tracing UI.
- Zipkin when you are bridging into B3-compatible tooling.
- OTLP when the destination expects an OpenTelemetry payload.

## Operational Notes

- The exporters are deterministic and safe to run locally.
- OTLP protobuf output is represented as a base64 transport string in this codebase.
- Use the OpenTelemetry bridge helpers when you need consistent resource metadata across services.