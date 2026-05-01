"""Shared distributed tracing helpers for FastAPI services.

The module degrades gracefully when OpenTelemetry packages are not installed.
In that case it still propagates a stable trace id through request middleware
so logs and responses can be correlated consistently.
"""

from __future__ import annotations

import contextvars
import functools
import inspect
import uuid
from dataclasses import dataclass
from typing import Any, Callable, Optional

try:
    from opentelemetry import trace as otel_trace
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.trace import Status, StatusCode

    _OTEL_AVAILABLE = True
except Exception:  # pragma: no cover - optional dependency path
    otel_trace = None
    OTLPSpanExporter = None
    FastAPIInstrumentor = None
    Resource = None
    TracerProvider = None
    BatchSpanProcessor = None
    Status = None
    StatusCode = None
    _OTEL_AVAILABLE = False


_TRACE_ID_CONTEXT: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar("shared_trace_id", default=None)
_TRACING_INITIALIZED = False


@dataclass(frozen=True)
class TracingConfig:
    """Configuration for shared distributed tracing."""

    service_name: str
    app_version: str = "1.0"
    environment: str = "development"
    enabled: bool = True
    otlp_endpoint: str = ""
    use_insecure: bool = True


@dataclass
class TracingRuntime:
    """Runtime state for tracing instrumentation."""

    config: TracingConfig
    enabled: bool
    implementation: str
    tracer: Any = None
    instrumented: bool = False


def generate_trace_id() -> str:
    """Generate a stable 32-character trace id."""

    return uuid.uuid4().hex


def current_trace_id() -> Optional[str]:
    """Return the current trace id from context or the active OpenTelemetry span."""

    trace_id = _TRACE_ID_CONTEXT.get()
    if trace_id:
        return trace_id

    if _OTEL_AVAILABLE and otel_trace is not None:
        span = otel_trace.get_current_span()
        span_context = span.get_span_context()
        if span_context.is_valid:
            return f"{span_context.trace_id:032x}"

    return None


def _extract_incoming_trace_id(headers: dict[str, str]) -> Optional[str]:
    trace_id = headers.get("x-trace-id")
    if trace_id:
        trace_id = trace_id.strip()
        if trace_id:
            return trace_id[:32].lower()

    traceparent = headers.get("traceparent")
    if traceparent:
        parts = traceparent.strip().split("-")
        if len(parts) >= 4 and len(parts[1]) == 32:
            return parts[1].lower()

    return None


def setup_tracing(config: TracingConfig) -> TracingRuntime:
    """Initialize tracing infrastructure and return the runtime state."""

    global _TRACING_INITIALIZED

    if not config.enabled:
        runtime = TracingRuntime(config=config, enabled=False, implementation="disabled")
        return runtime

    if not _OTEL_AVAILABLE:
        runtime = TracingRuntime(config=config, enabled=False, implementation="fallback")
        _TRACE_ID_CONTEXT.set(generate_trace_id())
        return runtime

    if not _TRACING_INITIALIZED:
        resource = Resource.create(
            {
                "service.name": config.service_name,
                "service.version": config.app_version,
                "deployment.environment": config.environment,
            }
        )
        provider = TracerProvider(resource=resource)

        if config.otlp_endpoint:
            exporter = OTLPSpanExporter(endpoint=config.otlp_endpoint, insecure=config.use_insecure)
            provider.add_span_processor(BatchSpanProcessor(exporter))

        otel_trace.set_tracer_provider(provider)
        _TRACING_INITIALIZED = True

    tracer = otel_trace.get_tracer(config.service_name)
    runtime = TracingRuntime(config=config, enabled=True, implementation="opentelemetry", tracer=tracer)
    return runtime


def _with_trace_context(runtime: TracingRuntime, operation_name: str, func: Callable) -> Callable:
    def _start_trace_id() -> str:
        trace_id = current_trace_id()
        if trace_id:
            return trace_id
        return generate_trace_id()

    def _record_exception(span: Any, exc: BaseException) -> None:
        if span is None:
            return
        if Status is not None and StatusCode is not None:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, str(exc)))

    if inspect.iscoroutinefunction(func):

        @functools.wraps(func)
        async def async_wrapper(*args, **kwargs):
            trace_id = _start_trace_id()
            token = _TRACE_ID_CONTEXT.set(trace_id)
            span = None
            try:
                if runtime.enabled and runtime.tracer is not None:
                    with runtime.tracer.start_as_current_span(operation_name) as span_context:
                        span = span_context
                        if span is not None:
                            span.set_attribute("service.name", runtime.config.service_name)
                            span.set_attribute("trace.id", trace_id)
                            result = await func(*args, **kwargs)
                            return result
                result = await func(*args, **kwargs)
                return result
            except Exception as exc:
                _record_exception(span, exc)
                raise
            finally:
                _TRACE_ID_CONTEXT.reset(token)

        return async_wrapper

    @functools.wraps(func)
    def sync_wrapper(*args, **kwargs):
        trace_id = _start_trace_id()
        token = _TRACE_ID_CONTEXT.set(trace_id)
        span = None
        try:
            if runtime.enabled and runtime.tracer is not None:
                with runtime.tracer.start_as_current_span(operation_name) as span_context:
                    span = span_context
                    if span is not None:
                        span.set_attribute("service.name", runtime.config.service_name)
                        span.set_attribute("trace.id", trace_id)
                        return func(*args, **kwargs)
            return func(*args, **kwargs)
        except Exception as exc:
            _record_exception(span, exc)
            raise
        finally:
            _TRACE_ID_CONTEXT.reset(token)

    return sync_wrapper


def trace_operation(runtime: TracingRuntime, operation_name: str) -> Callable:
    """Decorator that tracks an operation within the current trace context."""

    def decorator(func: Callable) -> Callable:
        return _with_trace_context(runtime, operation_name, func)

    return decorator


def instrument_app(app: Any, runtime: TracingRuntime) -> None:
    """Instrument a FastAPI app and attach trace id propagation middleware."""

    if runtime.enabled and runtime.tracer is not None and _OTEL_AVAILABLE and FastAPIInstrumentor is not None:
        try:
            FastAPIInstrumentor.instrument_app(app)
        except Exception:
            pass

    @app.middleware("http")
    async def trace_middleware(request, call_next):  # type: ignore[override]
        incoming_trace_id = _extract_incoming_trace_id(
            {
                "x-trace-id": request.headers.get("x-trace-id", ""),
                "traceparent": request.headers.get("traceparent", ""),
            }
        )
        trace_id = incoming_trace_id or current_trace_id() or generate_trace_id()
        token = _TRACE_ID_CONTEXT.set(trace_id)
        try:
            response = await call_next(request)
            response.headers.setdefault("X-Trace-Id", trace_id)
            return response
        finally:
            _TRACE_ID_CONTEXT.reset(token)


__all__ = [
    "TracingConfig",
    "TracingRuntime",
    "current_trace_id",
    "generate_trace_id",
    "instrument_app",
    "setup_tracing",
    "trace_operation",
]