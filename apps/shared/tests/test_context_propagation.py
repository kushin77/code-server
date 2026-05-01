"""
Tests for distributed context propagation system.
"""

import importlib.util
import sys
import types
from datetime import datetime
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


CONTEXT_PROPAGATION = _load_module("apps.shared.context_propagation", "context_propagation.py")

ContextFormat = CONTEXT_PROPAGATION.ContextFormat
TraceIdentifiers = CONTEXT_PROPAGATION.TraceIdentifiers
BaggageItem = CONTEXT_PROPAGATION.BaggageItem
RequestBaggage = CONTEXT_PROPAGATION.RequestBaggage
DistributedContext = CONTEXT_PROPAGATION.DistributedContext
W3CTracePropagator = CONTEXT_PROPAGATION.W3CTracePropagator
JaegerPropagator = CONTEXT_PROPAGATION.JaegerPropagator
B3Propagator = CONTEXT_PROPAGATION.B3Propagator
ContextManager = CONTEXT_PROPAGATION.ContextManager
ContextPropagationMiddleware = CONTEXT_PROPAGATION.ContextPropagationMiddleware
require_context = CONTEXT_PROPAGATION.require_context
with_child_span = CONTEXT_PROPAGATION.with_child_span
set_baggage = CONTEXT_PROPAGATION.set_baggage


class TestTraceIdentifiers:
    """Test trace identifier generation and conversion."""
    
    def test_generate_identifiers(self):
        """Test generating new identifiers."""
        ids = TraceIdentifiers.generate()
        
        assert len(ids.trace_id) == 16
        assert len(ids.span_id) == 16
        assert ids.parent_span_id is None
        assert ids.trace_flags == 0x01
    
    def test_to_dict(self):
        """Test conversion to dictionary."""
        ids = TraceIdentifiers(
            trace_id="abc123",
            span_id="def456",
            parent_span_id="ghi789"
        )
        
        d = ids.to_dict()
        assert d["trace_id"] == "abc123"
        assert d["span_id"] == "def456"
        assert d["parent_span_id"] == "ghi789"
    
    def test_unique_generation(self):
        """Test that generated IDs are unique."""
        ids1 = TraceIdentifiers.generate()
        ids2 = TraceIdentifiers.generate()
        
        assert ids1.trace_id != ids2.trace_id
        assert ids1.span_id != ids2.span_id


class TestBaggage:
    """Test baggage item and collection."""
    
    def test_baggage_item_creation(self):
        """Test creating baggage items."""
        item = BaggageItem("user-id", "user123", {"sensitive": "false"})
        
        assert item.key == "user-id"
        assert item.value == "user123"
        assert item.properties["sensitive"] == "false"
    
    def test_baggage_to_header(self):
        """Test baggage header format."""
        item = BaggageItem("user-id", "user123", {"sensitive": "false"})
        header = item.to_header()
        
        assert "user-id=user123" in header
        assert "sensitive=false" in header
    
    def test_request_baggage_set_get(self):
        """Test setting and getting baggage items."""
        baggage = RequestBaggage()
        
        baggage.set("tenant", "acme")
        baggage.set("region", "us-west", {"replicated": "true"})
        
        assert baggage.get("tenant") == "acme"
        assert baggage.get("region") == "us-west"
        assert baggage.get("missing") is None
    
    def test_request_baggage_all(self):
        """Test getting all baggage."""
        baggage = RequestBaggage()
        baggage.set("key1", "value1")
        baggage.set("key2", "value2")
        
        all_items = baggage.all()
        assert all_items == {"key1": "value1", "key2": "value2"}
    
    def test_baggage_to_header_format(self):
        """Test converting baggage to header."""
        baggage = RequestBaggage()
        baggage.set("user", "alice")
        baggage.set("tenant", "corp")
        
        header = baggage.to_header()
        assert "user=alice" in header
        assert "tenant=corp" in header
        assert "," in header
    
    def test_baggage_from_header_parsing(self):
        """Test parsing baggage from header."""
        header = "user=alice,tenant=corp;region=us-west,trace=123"
        
        baggage = RequestBaggage()
        baggage.from_header(header)
        
        assert baggage.get("user") == "alice"
        assert baggage.get("tenant") == "corp"
        assert baggage.get("trace") == "123"
    
    def test_baggage_thread_safety(self):
        """Test baggage thread safety."""
        import threading
        
        baggage = RequestBaggage()
        results = []
        
        def set_items():
            for i in range(100):
                baggage.set(f"key{i}", f"value{i}")
        
        def get_items():
            for i in range(100):
                val = baggage.get(f"key{i}")
                if val:
                    results.append(val)
        
        threads = [threading.Thread(target=set_items) for _ in range(3)]
        threads.extend([threading.Thread(target=get_items) for _ in range(3)])
        
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        
        assert len(results) > 0


class TestDistributedContext:
    """Test distributed context."""
    
    def test_context_creation(self):
        """Test creating context."""
        context = DistributedContext(
            trace_ids=TraceIdentifiers.generate(),
            user_id="user123",
            tenant_id="tenant456"
        )
        
        assert context.user_id == "user123"
        assert context.tenant_id == "tenant456"
        assert context.request_id is not None
        assert context.correlation_id is not None
    
    def test_context_to_dict(self):
        """Test context dict conversion."""
        context = DistributedContext(
            trace_ids=TraceIdentifiers.generate(),
            user_id="user123"
        )
        
        d = context.to_dict()
        assert "trace_id" in d
        assert "span_id" in d
        assert d["user_id"] == "user123"


class TestW3CTracePropagator:
    """Test W3C Trace Context propagation."""
    
    def test_inject_w3c_format(self):
        """Test injecting W3C headers."""
        propagator = W3CTracePropagator()
        context = DistributedContext(
            trace_ids=TraceIdentifiers(
                trace_id="0af7651916cd43dd",
                span_id="b9c7c989f97918e1",
                trace_flags=0x01
            )
        )
        
        carrier = {}
        propagator.inject(context, carrier)
        
        assert "traceparent" in carrier
        assert carrier["traceparent"].startswith("00-0af7651916cd43dd-")
    
    def test_extract_w3c_format(self):
        """Test extracting W3C headers."""
        propagator = W3CTracePropagator()
        carrier = {
            "traceparent": "00-0af7651916cd43dd-b9c7c989f97918e1-01"
        }
        
        context = propagator.extract(carrier)
        
        assert context is not None
        assert context.trace_ids.trace_id == "0af7651916cd43dd"
        assert context.trace_ids.parent_span_id == "b9c7c989f97918e1"
        assert context.trace_ids.trace_flags == 0x01
    
    def test_w3c_roundtrip_with_baggage(self):
        """Test W3C roundtrip with baggage."""
        propagator = W3CTracePropagator()
        
        original = DistributedContext(
            trace_ids=TraceIdentifiers.generate()
        )
        original.baggage.set("user", "alice")
        original.baggage.set("tenant", "corp")
        
        carrier = {}
        propagator.inject(original, carrier)
        
        extracted = propagator.extract(carrier)
        assert extracted is not None
        assert extracted.trace_ids.trace_id == original.trace_ids.trace_id


class TestJaegerPropagator:
    """Test Jaeger propagation."""
    
    def test_inject_jaeger_format(self):
        """Test injecting Jaeger headers."""
        propagator = JaegerPropagator()
        context = DistributedContext(
            trace_ids=TraceIdentifiers(
                trace_id="abc123",
                span_id="def456",
                trace_flags=1
            )
        )
        
        carrier = {}
        propagator.inject(context, carrier)
        
        assert "uber-trace-id" in carrier
        assert carrier["uber-trace-id"].startswith("abc123:")
    
    def test_extract_jaeger_format(self):
        """Test extracting Jaeger headers."""
        propagator = JaegerPropagator()
        carrier = {
            "uber-trace-id": "abc123:def456:0:1",
            "uberctx-user": "alice"
        }
        
        context = propagator.extract(carrier)
        
        assert context is not None
        assert context.trace_ids.trace_id == "abc123"
        assert context.trace_ids.span_id == "def456"
        assert context.baggage.get("user") == "alice"
    
    def test_jaeger_baggage_prefix(self):
        """Test Jaeger baggage with prefix."""
        propagator = JaegerPropagator()
        
        original = DistributedContext(
            trace_ids=TraceIdentifiers.generate()
        )
        original.baggage.set("tenant", "corp")
        original.format = ContextFormat.JAEGER
        
        carrier = {}
        propagator.inject(original, carrier)
        
        assert any(k.startswith("uberctx-") for k in carrier.keys())
        
        extracted = propagator.extract(carrier)
        assert extracted.baggage.get("tenant") == "corp"


class TestB3Propagator:
    """Test B3 propagation."""
    
    def test_inject_b3_multi_header(self):
        """Test injecting B3 multi-header format."""
        propagator = B3Propagator()
        context = DistributedContext(
            trace_ids=TraceIdentifiers(
                trace_id="abc123",
                span_id="def456"
            )
        )
        
        carrier = {}
        propagator.inject(context, carrier)
        
        assert "x-b3-traceid" in carrier
        assert "x-b3-spanid" in carrier
        assert "x-b3-sampled" in carrier
    
    def test_extract_b3_single_header(self):
        """Test extracting B3 single header format."""
        propagator = B3Propagator()
        carrier = {
            "b3": "abc123-def456-1"
        }
        
        context = propagator.extract(carrier)
        
        assert context is not None
        assert context.trace_ids.trace_id == "abc123"
        assert context.trace_ids.span_id == "def456"
        assert context.trace_ids.trace_flags == 1
    
    def test_extract_b3_multi_header(self):
        """Test extracting B3 multi-header format."""
        propagator = B3Propagator()
        carrier = {
            "x-b3-traceid": "abc123",
            "x-b3-spanid": "def456",
            "x-b3-parentspanid": "ghi789",
            "x-b3-sampled": "1"
        }
        
        context = propagator.extract(carrier)
        
        assert context.trace_ids.trace_id == "abc123"
        assert context.trace_ids.parent_span_id == "ghi789"


class TestContextManager:
    """Test context manager."""
    
    def test_set_and_get_context(self):
        """Test setting and getting context."""
        context = DistributedContext(trace_ids=TraceIdentifiers.generate())
        ContextManager.set_context(context)
        
        retrieved = ContextManager.get_context()
        assert retrieved == context
    
    def test_get_or_create(self):
        """Test get or create context."""
        ContextManager.set_context(None)
        
        context = ContextManager.get_or_create("test-service")
        
        assert context is not None
        assert context.service_name == "test-service"
        assert context.trace_ids.trace_id is not None
    
    def test_extract_context_w3c(self):
        """Test extracting W3C context."""
        headers = {
            "traceparent": "00-abc123-def456-01"
        }
        
        context = ContextManager.extract_context(headers, [ContextFormat.W3C_TRACE_CONTEXT])
        
        assert context is not None
        assert context.format == ContextFormat.W3C_TRACE_CONTEXT
    
    def test_extract_context_jaeger(self):
        """Test extracting Jaeger context."""
        headers = {
            "uber-trace-id": "abc123:def456:0:1"
        }
        
        context = ContextManager.extract_context(headers, [ContextFormat.JAEGER])
        
        assert context is not None
        assert context.format == ContextFormat.JAEGER
    
    def test_inject_context(self):
        """Test injecting context."""
        context = DistributedContext(
            trace_ids=TraceIdentifiers.generate(),
            format=ContextFormat.W3C_TRACE_CONTEXT
        )
        
        headers = ContextManager.inject_context(context)
        
        assert "traceparent" in headers
    
    def test_with_context_scope(self):
        """Test context scope manager."""
        original = DistributedContext(trace_ids=TraceIdentifiers.generate())
        ContextManager.set_context(original)
        
        new = DistributedContext(trace_ids=TraceIdentifiers.generate())
        
        with ContextManager.with_context(new):
            current = ContextManager.get_context()
            assert current == new
        
        # After exiting scope, should restore original
        current = ContextManager.get_context()
        assert current == original
    
    def test_new_child_span(self):
        """Test creating child spans."""
        context = DistributedContext(trace_ids=TraceIdentifiers.generate())
        ContextManager.set_context(context)
        
        child = ContextManager.new_child_span()
        
        assert child.trace_id == context.trace_ids.trace_id
        assert child.span_id != context.trace_ids.span_id
        assert child.parent_span_id == context.trace_ids.span_id


class TestContextPropagationMiddleware:
    """Test middleware."""
    
    def test_extract_existing_context(self):
        """Test extracting existing context."""
        middleware = ContextPropagationMiddleware("test-service")
        headers = {
            "traceparent": "00-abc123-def456-01"
        }
        
        context = middleware.extract_from_headers(headers)
        
        assert context is not None
        assert context.service_name == "test-service"
    
    def test_create_new_context(self):
        """Test creating new context."""
        middleware = ContextPropagationMiddleware("test-service")
        
        context = middleware.extract_from_headers({})
        
        assert context is not None
        assert context.service_name == "test-service"
        assert context.trace_ids.trace_id is not None
    
    def test_inject_into_headers(self):
        """Test injecting into headers."""
        middleware = ContextPropagationMiddleware(
            "test-service",
            formats=[ContextFormat.W3C_TRACE_CONTEXT]
        )
        context = DistributedContext(trace_ids=TraceIdentifiers.generate())
        
        headers = middleware.inject_into_headers(context)
        
        assert "traceparent" in headers


class TestDecorators:
    """Test decorator functions."""
    
    def test_require_context_decorator(self):
        """Test require_context decorator."""
        ContextManager.set_context(None)
        
        @require_context
        def operation():
            return ContextManager.get_context()
        
        context = operation()
        assert context is not None
    
    def test_with_child_span_decorator(self):
        """Test with_child_span decorator."""
        parent = DistributedContext(trace_ids=TraceIdentifiers.generate())
        ContextManager.set_context(parent)
        
        @with_child_span("operation")
        def operation():
            return ContextManager.get_context()
        
        child_context = operation()
        assert child_context.trace_ids.trace_id == parent.trace_ids.trace_id
        assert child_context.trace_ids.parent_span_id == parent.trace_ids.span_id
    
    def test_set_baggage_decorator(self):
        """Test set_baggage decorator."""
        @set_baggage("user", "alice", {"role": "admin"})
        def operation():
            context = ContextManager.get_context()
            return context.baggage.get("user")
        
        result = operation()
        assert result == "alice"


class TestRoundTrips:
    """Test complete roundtrip scenarios."""
    
    def test_w3c_context_propagation(self):
        """Test complete W3C propagation flow."""
        # Service 1: Create context
        context1 = DistributedContext(
            trace_ids=TraceIdentifiers.generate(),
            service_name="service1"
        )
        context1.baggage.set("request-id", "req123")
        
        # Inject into headers
        headers = {}
        W3CTracePropagator().inject(context1, headers)
        
        # Service 2: Extract context
        context2 = W3CTracePropagator().extract(headers)
        context2.service_name = "service2"
        
        # Verify trace continuity
        assert context2.trace_ids.trace_id == context1.trace_ids.trace_id
        assert context2.baggage.get("request-id") == "req123"
    
    def test_multi_hop_propagation(self):
        """Test multi-hop context propagation."""
        trace_ids = TraceIdentifiers.generate()
        
        # Hop 1
        context1 = DistributedContext(trace_ids=trace_ids)
        headers1 = {}
        W3CTracePropagator().inject(context1, headers1)
        
        # Hop 2
        context2 = W3CTracePropagator().extract(headers1)
        headers2 = {}
        W3CTracePropagator().inject(context2, headers2)
        
        # Hop 3
        context3 = W3CTracePropagator().extract(headers2)
        
        # Verify trace continuity across hops
        assert context1.trace_ids.trace_id == context2.trace_ids.trace_id
        assert context2.trace_ids.trace_id == context3.trace_ids.trace_id
    
    def test_format_conversion(self):
        """Test converting between propagation formats."""
        # Create in W3C format
        context = DistributedContext(
            trace_ids=TraceIdentifiers.generate(),
            format=ContextFormat.W3C_TRACE_CONTEXT
        )
        context.baggage.set("tenant", "acme")
        
        # Extract as W3C
        w3c_headers = {}
        W3CTracePropagator().inject(context, w3c_headers)
        w3c_context = W3CTracePropagator().extract(w3c_headers)
        
        # Inject as Jaeger
        jaeger_headers = {}
        context.format = ContextFormat.JAEGER
        JaegerPropagator().inject(context, jaeger_headers)
        jaeger_context = JaegerPropagator().extract(jaeger_headers)
        
        # Same trace ID despite format change
        assert w3c_context.trace_ids.trace_id == jaeger_context.trace_ids.trace_id
