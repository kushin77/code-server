# Shared Tracing Guide

The platform now has a shared tracing helper in `apps/shared/tracing.py` that
supports two modes:

- OpenTelemetry instrumentation when the OTEL packages are installed.
- Lightweight trace-id propagation when OTEL is unavailable.

## Configuration

Set these environment variables when tracing is enabled:

- `OTEL_ENABLED=true|false`
- `OTEL_EXPORTER_OTLP_ENDPOINT` for the collector endpoint
- `OTEL_SERVICE_NAME` for the emitting service name
- `ENVIRONMENT` for deployment metadata

## Integration Pattern

```python
from apps.shared.tracing import TracingConfig, instrument_app, setup_tracing, trace_operation

tracing = setup_tracing(
    TracingConfig(
        service_name="control-plane",
        app_version="1.0",
        environment="production",
        enabled=True,
    )
)

instrument_app(app, tracing)

@app.get("/health")
@trace_operation(tracing, "control-plane.health_check")
async def health_check():
    ...
```

## Behavior

- Incoming `traceparent` and `X-Trace-Id` headers are propagated when present.
- Outgoing responses receive `X-Trace-Id` so logs and traces can be correlated.
- If OTEL is installed, the module instruments FastAPI automatically and emits
  spans to the configured exporter.

## External Service Tracing

External service calls use `apps/shared/external_tracing.py` to record span metadata
for GitHub API, GCP, and other third-party integrations. The helper records:

- Service and endpoint identifiers
- Request and response sizes
- Status code and error state
- Latency for the full external call

Use the helper when a service needs to track boundary-crossing work, especially for
calls that should be visible in logs, alerts, or downstream analysis.

The GitHub integration wrapper in `apps/shared/github_integration.py` uses the helper
for repository lookups, pull-request actions, and issue comments. The agent-runtime
service exposes those flows as a reference external-service tracing path.

The GCP integration wrapper in `apps/shared/gcp_integration.py` uses the same helper
for Cloud Storage, BigQuery, Pub/Sub, and Cloud Functions operations. The control-plane
service shows how those traces can be surfaced alongside application telemetry.

## Reference Service

The control-plane service now uses the shared tracing helpers as the Phase 10c
reference implementation. Use it as the template for other FastAPI services.