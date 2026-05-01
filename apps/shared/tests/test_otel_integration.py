"""Tests for OpenTelemetry integration."""

import importlib.util
import sys
import types
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

apps_pkg = types.ModuleType("apps")
apps_pkg.__path__ = [str(ROOT.parent)]
sys.modules.setdefault("apps", apps_pkg)

shared_pkg = types.ModuleType("apps.shared")
shared_pkg.__path__ = [str(ROOT)]
sys.modules["apps.shared"] = shared_pkg


def _load_module(module_name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(module_name, ROOT / file_name)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


OTEL = _load_module("apps.shared.otel_integration", "otel_integration.py")

TraceContextFormat = OTEL.TraceContextFormat
TraceContext = OTEL.TraceContext
JaegerTraceContext = OTEL.JaegerTraceContext
ContextPropagator = OTEL.ContextPropagator
ResourceBuilder = OTEL.ResourceBuilder
InstrumentationScope = OTEL.InstrumentationScope
SpanEventBuilder = OTEL.SpanEventBuilder
LinkBuilder = OTEL.LinkBuilder
OpenTelemetryBridge = OTEL.OpenTelemetryBridge


class TestTraceContext:
    """Test W3C trace context."""

    def test_context_creation(self):
        """Test creating trace context."""
        ctx = TraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
        )

        assert ctx.trace_id == "0af7651916cd43dd8448eb211c80319c"
        assert ctx.parent_id == "b7ad6b7169203331"

    def test_context_to_header(self):
        """Test converting context to header."""
        ctx = TraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
        )

        header = ctx.to_header()

        assert header.startswith("00-")
        assert "0af7651916cd43dd8448eb211c80319c" in header
        assert "b7ad6b7169203331" in header

    def test_context_from_header(self):
        """Test parsing context from header."""
        header = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"

        ctx = TraceContext.from_header(header)

        assert ctx is not None
        assert ctx.trace_id == "0af7651916cd43dd8448eb211c80319c"
        assert ctx.parent_id == "b7ad6b7169203331"
        assert ctx.trace_flags == "01"

    def test_context_from_invalid_header(self):
        """Test parsing invalid header."""
        header = "invalid-header"

        ctx = TraceContext.from_header(header)

        assert ctx is None


class TestJaegerTraceContext:
    """Test Jaeger trace context."""

    def test_jaeger_context_creation(self):
        """Test creating Jaeger context."""
        ctx = JaegerTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            span_id="b7ad6b7169203331",
        )

        assert ctx.trace_id == "0af7651916cd43dd8448eb211c80319c"
        assert ctx.span_id == "b7ad6b7169203331"

    def test_jaeger_to_header(self):
        """Test converting Jaeger context to header."""
        ctx = JaegerTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            span_id="b7ad6b7169203331",
            parent_id="c9ad6b7169203332",
            flags=1,
        )

        header = ctx.to_header()

        assert "0af7651916cd43dd8448eb211c80319c" in header
        assert "b7ad6b7169203331" in header
        assert "c9ad6b7169203332" in header

    def test_jaeger_from_header(self):
        """Test parsing Jaeger header."""
        header = "0af7651916cd43dd8448eb211c80319c:b7ad6b7169203331:c9ad6b7169203332:1"

        ctx = JaegerTraceContext.from_header(header)

        assert ctx is not None
        assert ctx.trace_id == "0af7651916cd43dd8448eb211c80319c"
        assert ctx.span_id == "b7ad6b7169203331"


class TestContextPropagator:
    """Test context propagation."""

    def test_extract_w3c_context(self):
        """Test extracting W3C context from headers."""
        headers = {
            "traceparent": "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
        }

        context = ContextPropagator.extract(headers, TraceContextFormat.W3C)

        assert context is not None
        assert context["trace_id"] == "0af7651916cd43dd8448eb211c80319c"
        assert context["parent_id"] == "b7ad6b7169203331"

    def test_extract_jaeger_context(self):
        """Test extracting Jaeger context from headers."""
        headers = {
            "uber-trace-id": "0af7651916cd43dd8448eb211c80319c:b7ad6b7169203331:c9ad6b7169203332:1",
        }

        context = ContextPropagator.extract(headers, TraceContextFormat.JAEGER)

        assert context is not None
        assert context["trace_id"] == "0af7651916cd43dd8448eb211c80319c"
        assert context["span_id"] == "b7ad6b7169203331"

    def test_extract_missing_context(self):
        """Test extracting from headers without context."""
        headers = {}

        context = ContextPropagator.extract(headers, TraceContextFormat.W3C)

        assert context is None

    def test_inject_w3c_context(self):
        """Test injecting W3C context into headers."""
        context = {
            "trace_id": "0af7651916cd43dd8448eb211c80319c",
            "parent_id": "b7ad6b7169203331",
        }

        headers = ContextPropagator.inject(context, TraceContextFormat.W3C)

        assert "traceparent" in headers
        assert "0af7651916cd43dd8448eb211c80319c" in headers["traceparent"]

    def test_inject_jaeger_context(self):
        """Test injecting Jaeger context into headers."""
        context = {
            "trace_id": "0af7651916cd43dd8448eb211c80319c",
            "span_id": "b7ad6b7169203331",
        }

        headers = ContextPropagator.inject(context, TraceContextFormat.JAEGER)

        assert "uber-trace-id" in headers
        assert "0af7651916cd43dd8448eb211c80319c" in headers["uber-trace-id"]


class TestResourceBuilder:
    """Test resource builder."""

    def test_build_resource_with_service(self):
        """Test building resource with service."""
        builder = ResourceBuilder()
        builder.set_service("my-service", "1.0.0")

        resource = builder.build()

        assert resource["service.name"] == "my-service"
        assert resource["service.version"] == "1.0.0"

    def test_build_resource_with_environment(self):
        """Test building resource with environment."""
        builder = ResourceBuilder()
        builder.set_service("my-service")
        builder.set_environment("production", region="us-east-1", zone="us-east-1a")

        resource = builder.build()

        assert resource["deployment.environment"] == "production"
        assert resource["cloud.region"] == "us-east-1"
        assert resource["cloud.availability_zone"] == "us-east-1a"

    def test_build_resource_with_host(self):
        """Test building resource with host."""
        builder = ResourceBuilder()
        builder.set_host("hostname-1", host_id="host-123", container_id="container-456")

        resource = builder.build()

        assert resource["host.name"] == "hostname-1"
        assert resource["host.id"] == "host-123"
        assert resource["container.id"] == "container-456"

    def test_build_resource_with_process(self):
        """Test building resource with process."""
        builder = ResourceBuilder()
        builder.set_process(1234, "python")

        resource = builder.build()

        assert resource["process.pid"] == 1234
        assert resource["process.executable.name"] == "python"

    def test_build_resource_with_custom_attribute(self):
        """Test building resource with custom attributes."""
        builder = ResourceBuilder()
        builder.add_attribute("custom.key", "custom_value")
        builder.add_attribute("custom.number", 42)

        resource = builder.build()

        assert resource["custom.key"] == "custom_value"
        assert resource["custom.number"] == 42

    def test_builder_chaining(self):
        """Test builder method chaining."""
        resource = (
            ResourceBuilder()
            .set_service("api-service", "2.0.0")
            .set_environment("staging", region="eu-west-1")
            .set_host("api-1")
            .add_attribute("team", "platform")
            .build()
        )

        assert resource["service.name"] == "api-service"
        assert resource["deployment.environment"] == "staging"
        assert resource["host.name"] == "api-1"
        assert resource["team"] == "platform"


class TestInstrumentationScope:
    """Test instrumentation scope."""

    def test_scope_creation(self):
        """Test creating instrumentation scope."""
        scope = InstrumentationScope("my-library", "1.0.0")

        assert scope.name == "my-library"
        assert scope.version == "1.0.0"

    def test_scope_to_dict(self):
        """Test converting scope to dict."""
        scope = InstrumentationScope(
            "my-library",
            "1.5.0",
            "https://opentelemetry.io/schemas/1.20.0",
        )

        scope_dict = scope.to_dict()

        assert scope_dict["name"] == "my-library"
        assert scope_dict["version"] == "1.5.0"
        assert "schemaUrl" in scope_dict


class TestSpanEventBuilder:
    """Test span event builder."""

    def test_event_creation(self):
        """Test creating span event."""
        event = SpanEventBuilder("user_action").build()

        assert event["name"] == "user_action"
        assert "timestamp" in event

    def test_event_with_attributes(self):
        """Test creating event with attributes."""
        event = (
            SpanEventBuilder("db_query")
            .add_attribute("query", "SELECT * FROM users")
            .add_attribute("duration_ms", 45)
            .build()
        )

        assert event["name"] == "db_query"
        assert event["attributes"]["query"] == "SELECT * FROM users"
        assert event["attributes"]["duration_ms"] == 45

    def test_event_with_timestamp(self):
        """Test creating event with custom timestamp."""
        timestamp = 1234567890000000000

        event = SpanEventBuilder("event").set_timestamp(timestamp).build()

        assert event["timestamp"] == timestamp


class TestLinkBuilder:
    """Test link builder."""

    def test_link_creation(self):
        """Test creating link."""
        link = LinkBuilder(
            "trace_1",
            "span_1",
        ).build()

        assert link["traceId"] == "trace_1"
        assert link["spanId"] == "span_1"

    def test_link_with_attributes(self):
        """Test creating link with attributes."""
        link = (
            LinkBuilder("trace_1", "span_1")
            .add_attribute("link.type", "async_call")
            .add_attribute("caller_id", "service_a")
            .build()
        )

        assert link["traceId"] == "trace_1"
        assert link["attributes"]["link.type"] == "async_call"
        assert link["attributes"]["caller_id"] == "service_a"


class TestOpenTelemetryBridge:
    """Test OpenTelemetry bridge."""

    def test_create_resource(self):
        """Test creating resource."""
        resource = OpenTelemetryBridge.create_resource(
            "api-service",
            "1.0.0",
            "production",
        )

        assert resource["service.name"] == "api-service"
        assert resource["service.version"] == "1.0.0"
        assert resource["deployment.environment"] == "production"

    def test_create_instrumentation_scope(self):
        """Test creating instrumentation scope."""
        scope = OpenTelemetryBridge.create_instrumentation_scope(
            "my-library",
            "2.0.0",
        )

        assert scope.name == "my-library"
        assert scope.version == "2.0.0"

    def test_span_kind_to_string(self):
        """Test converting span kind to string."""
        assert OpenTelemetryBridge.span_kind_to_string(0) == "UNSPECIFIED"
        assert OpenTelemetryBridge.span_kind_to_string(1) == "INTERNAL"
        assert OpenTelemetryBridge.span_kind_to_string(2) == "SERVER"
        assert OpenTelemetryBridge.span_kind_to_string(3) == "CLIENT"

    def test_status_code_to_string(self):
        """Test converting status code to string."""
        assert OpenTelemetryBridge.status_code_to_string(0) == "UNSET"
        assert OpenTelemetryBridge.status_code_to_string(1) == "OK"
        assert OpenTelemetryBridge.status_code_to_string(2) == "ERROR"


class TestOTELIntegration:
    """Integration tests for OpenTelemetry."""

    def test_context_propagation_flow(self):
        """Test full context propagation flow."""
        # Create initial context
        initial_context = {
            "trace_id": "0af7651916cd43dd8448eb211c80319c",
            "parent_id": "b7ad6b7169203331",
        }

        # Inject into headers (as if sending to another service)
        headers = ContextPropagator.inject(initial_context, TraceContextFormat.W3C)

        # Extract on the receiving end
        received_context = ContextPropagator.extract(headers, TraceContextFormat.W3C)

        # Should match
        assert received_context["trace_id"] == initial_context["trace_id"]
        assert received_context["parent_id"] == initial_context["parent_id"]

    def test_resource_and_scope_building(self):
        """Test building resource and scope together."""
        resource = OpenTelemetryBridge.create_resource("api", "1.0.0", "prod")
        scope = OpenTelemetryBridge.create_instrumentation_scope("my-lib")

        assert resource["service.name"] == "api"
        assert scope.name == "my-lib"

    def test_cross_format_context_propagation(self):
        """Test propagating context between formats."""
        w3c_context = {
            "trace_id": "0af7651916cd43dd8448eb211c80319c",
            "parent_id": "b7ad6b7169203331",
        }

        # Inject W3C
        w3c_headers = ContextPropagator.inject(w3c_context, TraceContextFormat.W3C)
        w3c_extracted = ContextPropagator.extract(w3c_headers, TraceContextFormat.W3C)

        # Verify extraction
        assert w3c_extracted["trace_id"] == w3c_context["trace_id"]
