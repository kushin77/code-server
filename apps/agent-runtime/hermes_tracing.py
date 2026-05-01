"""
@file apps/agent-runtime/hermes_tracing.py
@description OpenTelemetry distributed tracing integration for Hermes + Agent Runtime.

Wires OTEL spans across:
  - HTTP requests received by agent-runtime (FastAPI middleware)
  - Outbound calls to Hermes, Paperclip, OPA, Reputation Engine
  - Agent execution lifecycle events (start, approval-wait, complete, fail)

Integrates with Grafana Tempo (already in the monitoring stack).

Usage:
    from hermes_tracing import setup_tracing, get_tracer, trace_agent_execution

    # Called once at app startup
    setup_tracing(service_name="agent-runtime")

    # In individual functions
    tracer = get_tracer()
    with tracer.start_as_current_span("my_operation") as span:
        span.set_attribute("agent.id", agent_id)
"""

import os
from contextlib import contextmanager
from typing import Any, Generator, Optional

from log import get_logger, log_event

logger = get_logger(__name__)

# ── Configuration ─────────────────────────────────────────────────────────────
OTEL_ENABLED: bool = os.getenv("OTEL_ENABLED", "true").lower() == "true"
OTEL_EXPORTER_OTLP_ENDPOINT: str = os.getenv(
    "OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317"
)
OTEL_SERVICE_NAME: str = os.getenv("OTEL_SERVICE_NAME", "agent-runtime")
OTEL_SERVICE_VERSION: str = os.getenv("AGENT_RUNTIME_VERSION", "1.0.0")

# ── Lazy import guard ─────────────────────────────────────────────────────────
# opentelemetry packages are optional; fall back gracefully if not installed.
_tracer: Optional[Any] = None
_otel_available: bool = False

try:
    from opentelemetry import trace
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

    _otel_available = True
except ImportError:
    _otel_available = False


def setup_tracing(service_name: str = OTEL_SERVICE_NAME) -> None:
    """
    Initialize OTEL tracing and set global tracer provider.

    Safe to call multiple times — subsequent calls are no-ops.
    When OTEL packages are absent or OTEL_ENABLED=false, tracing is silently
    disabled and all other calls in this module become no-ops.
    """
    global _tracer

    if not OTEL_ENABLED:
        log_event(logger, "otel_tracing_disabled", reason="OTEL_ENABLED=false")
        return

    if not _otel_available:
        log_event(
            logger,
            "otel_tracing_unavailable",
            reason="opentelemetry packages not installed — install extras: opentelemetry-sdk opentelemetry-exporter-otlp opentelemetry-instrumentation-fastapi opentelemetry-instrumentation-httpx",
        )
        return

    if _tracer is not None:
        return  # Already initialised

    resource = Resource.create(
        {
            SERVICE_NAME: service_name,
            SERVICE_VERSION: OTEL_SERVICE_VERSION,
        }
    )

    exporter = OTLPSpanExporter(endpoint=OTEL_EXPORTER_OTLP_ENDPOINT, insecure=True)
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    _tracer = trace.get_tracer(service_name)

    # Auto-instrument httpx (covers Hermes, Paperclip, OPA calls)
    HTTPXClientInstrumentor().instrument()

    log_event(
        logger,
        "otel_tracing_initialized",
        service_name=service_name,
        endpoint=OTEL_EXPORTER_OTLP_ENDPOINT,
    )


def instrument_app(app: Any) -> None:
    """
    Apply FastAPI auto-instrumentation to add trace context to every HTTP request.

    Call after setup_tracing() and after the FastAPI app is created.
    """
    if not (_otel_available and OTEL_ENABLED and _tracer is not None):
        return
    FastAPIInstrumentor.instrument_app(app)
    log_event(logger, "otel_fastapi_instrumented")


def get_tracer() -> Optional[Any]:
    """Return the global tracer, or None if tracing is not available."""
    return _tracer


@contextmanager
def trace_agent_execution(
    agent_id: str,
    agent_type: str,
    action: str,
    execution_id: str,
) -> Generator[Optional[Any], None, None]:
    """
    Context manager that wraps an agent execution in an OTEL span.

    When tracing is disabled, yields None and is a no-op.

    Usage:
        with trace_agent_execution(agent_id, agent_type, action, exec_id) as span:
            if span:
                span.set_attribute("custom.key", value)
            # ... execute ...
    """
    if _tracer is None:
        yield None
        return

    with _tracer.start_as_current_span(
        f"agent.execute.{action}",
        kind=trace.SpanKind.INTERNAL,
    ) as span:
        span.set_attribute("agent.id", agent_id)
        span.set_attribute("agent.type", agent_type)
        span.set_attribute("agent.action", action)
        span.set_attribute("execution.id", execution_id)
        yield span


@contextmanager
def trace_hermes_call(
    operation: str,
    agent_id: str,
) -> Generator[Optional[Any], None, None]:
    """
    Context manager for tracing outbound Hermes orchestrator calls.

    Usage:
        with trace_hermes_call("register", agent_id) as span:
            await hermes_client.register()
    """
    if _tracer is None:
        yield None
        return

    with _tracer.start_as_current_span(
        f"hermes.{operation}",
        kind=trace.SpanKind.CLIENT,
    ) as span:
        span.set_attribute("hermes.operation", operation)
        span.set_attribute("agent.id", agent_id)
        yield span
