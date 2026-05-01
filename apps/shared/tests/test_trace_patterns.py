"""Tests for advanced distributed tracing patterns."""

import asyncio
import importlib.util
import sys
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "trace_patterns.py"
SPEC = importlib.util.spec_from_file_location("shared_trace_patterns_test_module", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
TRACE_PATTERNS = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = TRACE_PATTERNS
SPEC.loader.exec_module(TRACE_PATTERNS)


def test_trace_sampler_honors_path_filters() -> None:
    sampler = TRACE_PATTERNS.TraceSampler(
        TRACE_PATTERNS.TraceSamplingConfig(
            strategy=TRACE_PATTERNS.SamplingStrategy.ALWAYS,
            exclude_paths=["/health"],
            always_sample_paths=["/admin"],
        )
    )

    assert sampler.should_sample(path="/admin/settings") is True
    assert sampler.should_sample(path="/health") is False
    assert sampler.should_sample(path="/api") is True


def test_trace_context_and_baggage_round_trip() -> None:
    headers = {
        "traceparent": "00-0123456789abcdef0123456789abcdef-1111111111111111-01",
        "baggage": "userId=alice,tenantId=acme,feature=beta",
    }

    context = TRACE_PATTERNS.W3CTraceContext.from_headers(headers)
    baggage = TRACE_PATTERNS.ContextBaggage.from_header(headers["baggage"])

    assert context is not None
    assert context.trace_id == "0123456789abcdef0123456789abcdef"
    assert context.parent_id == "1111111111111111"
    assert context.is_sampled() is True
    assert context.to_headers()["traceparent"].startswith("00-0123456789abcdef0123456789abcdef")

    assert baggage.user_id == "alice"
    assert baggage.tenant_id == "acme"
    assert baggage.custom_properties["feature"] == "beta"
    assert "userId=alice" in baggage.to_header()


def test_profile_span_records_duration_and_context() -> None:
    @TRACE_PATTERNS.profile_span("demo.sync")
    def sync_work() -> str:
        return "done"

    assert sync_work() == "done"
    profile = TRACE_PATTERNS.get_trace_context_manager().get_performance_profile()

    assert profile is not None
    assert profile.span_name == "demo.sync"
    assert profile.wall_time_ms >= 0


def test_profile_span_wraps_async_code() -> None:
    @TRACE_PATTERNS.profile_span("demo.async")
    async def async_work() -> str:
        await asyncio.sleep(0)
        return "done"

    assert asyncio.run(async_work()) == "done"
    profile = TRACE_PATTERNS.get_trace_context_manager().get_performance_profile()

    assert profile is not None
    assert profile.span_name == "demo.async"
"""Tests for advanced tracing patterns."""

import pytest
import time
from apps.shared.trace_patterns import (
    SamplingStrategy,
    TraceSamplingConfig,
    TraceSampler,
    W3CTraceContext,
    ContextBaggage,
    PerformanceProfile,
    TraceContextManager,
    get_trace_context_manager,
    profile_span,
)


class TestSamplingStrategy:
    """Test sampling strategies."""

    def test_always_sample(self):
        """Test ALWAYS sampling strategy."""
        config = TraceSamplingConfig(strategy=SamplingStrategy.ALWAYS)
        sampler = TraceSampler(config)

        # Should always sample
        for _ in range(100):
            assert sampler.should_sample() is True

    def test_never_sample(self):
        """Test NEVER sampling strategy."""
        config = TraceSamplingConfig(strategy=SamplingStrategy.NEVER)
        sampler = TraceSampler(config)

        # Should never sample
        for _ in range(100):
            assert sampler.should_sample() is False

    def test_uniform_sample(self):
        """Test UNIFORM sampling strategy."""
        config = TraceSamplingConfig(strategy=SamplingStrategy.UNIFORM, sample_rate=0.5)
        sampler = TraceSampler(config)

        # Should sample approximately 50%
        samples = sum(1 for _ in range(1000) if sampler.should_sample())
        assert 400 < samples < 600  # Roughly 50%

    def test_probability_sample(self):
        """Test PROBABILITY sampling strategy."""
        config = TraceSamplingConfig(strategy=SamplingStrategy.PROBABILITY, sample_rate=0.3)
        sampler = TraceSampler(config)

        samples = sum(1 for _ in range(1000) if sampler.should_sample())
        assert 200 < samples < 400  # Roughly 30%

    def test_rate_limited_sample(self):
        """Test RATE_LIMITED sampling strategy."""
        config = TraceSamplingConfig(
            strategy=SamplingStrategy.RATE_LIMITED,
            max_traces_per_minute=10,
        )
        sampler = TraceSampler(config)

        # Should sample up to limit
        samples = sum(1 for _ in range(20) if sampler.should_sample())
        assert samples == 10


class TestTraceSamplingConfig:
    """Test trace sampling configuration."""

    def test_config_creation(self):
        """Test configuration can be created."""
        config = TraceSamplingConfig(
            strategy=SamplingStrategy.UNIFORM,
            sample_rate=0.25,
        )

        assert config.strategy == SamplingStrategy.UNIFORM
        assert config.sample_rate == 0.25

    def test_config_validation(self):
        """Test configuration validation."""
        # Valid config
        config = TraceSamplingConfig(sample_rate=0.5)
        assert config.is_valid() is True

        # Invalid sample rate
        config.sample_rate = 1.5
        assert config.is_valid() is False

        config.sample_rate = -0.1
        assert config.is_valid() is False

    def test_exclude_paths(self):
        """Test path exclusion."""
        config = TraceSamplingConfig(
            strategy=SamplingStrategy.ALWAYS,
            exclude_paths=["/health", "/metrics"],
        )
        sampler = TraceSampler(config)

        assert sampler.should_sample(path="/health") is False
        assert sampler.should_sample(path="/api/users") is True

    def test_always_sample_paths(self):
        """Test always-sample paths."""
        config = TraceSamplingConfig(
            strategy=SamplingStrategy.NEVER,
            always_sample_paths=["/critical", "/payment"],
        )
        sampler = TraceSampler(config)

        assert sampler.should_sample(path="/critical") is True
        assert sampler.should_sample(path="/api/users") is False

    def test_debug_header(self):
        """Test debug header enables sampling."""
        config = TraceSamplingConfig(
            strategy=SamplingStrategy.NEVER,
            debug_mode=True,
        )
        sampler = TraceSampler(config)

        assert sampler.should_sample(debug_header="true") is True
        assert sampler.should_sample(debug_header=None) is False


class TestW3CTraceContext:
    """Test W3C Trace Context."""

    def test_trace_context_creation(self):
        """Test trace context can be created."""
        context = W3CTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
        )

        assert context.trace_id == "0af7651916cd43dd8448eb211c80319c"
        assert context.parent_id == "b7ad6b7169203331"

    def test_trace_context_from_headers(self):
        """Test parsing trace context from headers."""
        headers = {
            "traceparent": "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
        }

        context = W3CTraceContext.from_headers(headers)

        assert context is not None
        assert context.trace_id == "0af7651916cd43dd8448eb211c80319c"
        assert context.parent_id == "b7ad6b7169203331"

    def test_trace_context_to_headers(self):
        """Test converting trace context to headers."""
        context = W3CTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
            trace_flags="01",
        )

        headers = context.to_headers()

        assert "traceparent" in headers
        assert headers["traceparent"] == "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"

    def test_trace_context_is_sampled(self):
        """Test checking if trace is sampled."""
        context_sampled = W3CTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
            trace_flags="01",
        )
        assert context_sampled.is_sampled() is True

        context_not_sampled = W3CTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
            trace_flags="00",
        )
        assert context_not_sampled.is_sampled() is False

    def test_trace_context_invalid_header(self):
        """Test handling invalid header."""
        headers = {"traceparent": "invalid"}
        context = W3CTraceContext.from_headers(headers)
        assert context is None


class TestContextBaggage:
    """Test context baggage."""

    def test_baggage_creation(self):
        """Test baggage can be created."""
        baggage = ContextBaggage(
            user_id="user123",
            tenant_id="tenant456",
            correlation_id="corr789",
        )

        assert baggage.user_id == "user123"
        assert baggage.tenant_id == "tenant456"

    def test_baggage_from_header(self):
        """Test parsing baggage from header."""
        header = "userId=user123,tenantId=tenant456,correlationId=corr789"
        baggage = ContextBaggage.from_header(header)

        assert baggage.user_id == "user123"
        assert baggage.tenant_id == "tenant456"
        assert baggage.correlation_id == "corr789"

    def test_baggage_to_header(self):
        """Test converting baggage to header."""
        baggage = ContextBaggage(
            user_id="user123",
            tenant_id="tenant456",
        )

        header = baggage.to_header()

        assert "userId=user123" in header
        assert "tenantId=tenant456" in header

    def test_baggage_custom_properties(self):
        """Test baggage with custom properties."""
        baggage = ContextBaggage(
            user_id="user123",
            custom_properties={"region": "us-west", "environment": "production"},
        )

        header = baggage.to_header()

        assert "userId=user123" in header
        assert "region=us-west" in header or "environment=production" in header


class TestPerformanceProfile:
    """Test performance profiling."""

    def test_profile_creation(self):
        """Test profile can be created."""
        profile = PerformanceProfile(
            span_name="test_span",
            start_time=time.time(),
        )

        assert profile.span_name == "test_span"
        assert profile.end_time == 0.0

    def test_profile_finalize(self):
        """Test profile finalization."""
        start = time.time()
        profile = PerformanceProfile(
            span_name="test_span",
            start_time=start,
        )

        time.sleep(0.1)
        profile.finalize()

        assert profile.end_time > start
        assert profile.wall_time_ms >= 100

    def test_profile_to_dict(self):
        """Test profile conversion to dictionary."""
        profile = PerformanceProfile(
            span_name="test_span",
            start_time=time.time(),
            wall_time_ms=150.5,
            cpu_time_ms=100.2,
            memory_mb=256.8,
        )

        profile_dict = profile.to_dict()

        assert profile_dict["span_name"] == "test_span"
        assert profile_dict["wall_time_ms"] == 150.5
        assert profile_dict["cpu_time_ms"] == 100.2
        assert profile_dict["memory_mb"] == 256.8


class TestTraceContextManager:
    """Test trace context manager."""

    def test_get_set_trace_context(self):
        """Test getting and setting trace context."""
        manager = TraceContextManager()
        context = W3CTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
        )

        manager.set_trace_context(context)
        retrieved = manager.get_trace_context()

        assert retrieved is context

    def test_get_set_baggage(self):
        """Test getting and setting baggage."""
        manager = TraceContextManager()
        baggage = ContextBaggage(user_id="user123")

        manager.set_baggage(baggage)
        retrieved = manager.get_baggage()

        assert retrieved.user_id == "user123"

    def test_trace_scope(self):
        """Test trace scope context manager."""
        manager = TraceContextManager()
        context = W3CTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
        )
        baggage = ContextBaggage(user_id="user123")

        with manager.trace_scope(context, baggage):
            assert manager.get_trace_context() is context
            assert manager.get_baggage().user_id == "user123"

        # Should be reset after scope
        assert manager.get_trace_context() is None

    def test_global_context_manager(self):
        """Test global context manager."""
        manager = get_trace_context_manager()

        context = W3CTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
        )

        manager.set_trace_context(context)
        retrieved = manager.get_trace_context()

        assert retrieved is context


class TestProfileSpanDecorator:
    """Test profile_span decorator."""

    @pytest.mark.asyncio
    async def test_profile_async_span(self):
        """Test profiling async span."""

        @profile_span("async_test")
        async def async_function():
            await pytest.sleep(0.05)
            return "result"

        result = await async_function()

        assert result == "result"

        manager = get_trace_context_manager()
        profile = manager.get_performance_profile()

        assert profile is not None
        assert profile.span_name == "async_test"

    def test_profile_sync_span(self):
        """Test profiling sync span."""

        @profile_span("sync_test")
        def sync_function():
            time.sleep(0.05)
            return "result"

        result = sync_function()

        assert result == "result"

        manager = get_trace_context_manager()
        profile = manager.get_performance_profile()

        assert profile is not None
        assert profile.span_name == "sync_test"
        assert profile.wall_time_ms >= 50

    @pytest.mark.asyncio
    async def test_profile_exception_handling(self):
        """Test profiling with exception."""

        @profile_span("error_test")
        async def failing_function():
            raise ValueError("Test error")

        with pytest.raises(ValueError):
            await failing_function()

        manager = get_trace_context_manager()
        profile = manager.get_performance_profile()

        assert profile is not None
        assert profile.span_name == "error_test"


class TestTracePatternsIntegration:
    """Integration tests for trace patterns."""

    def test_sampling_with_baggage(self):
        """Test sampling with baggage propagation."""
        config = TraceSamplingConfig(strategy=SamplingStrategy.ALWAYS)
        sampler = TraceSampler(config)

        # Should sample
        assert sampler.should_sample() is True

        # Create context with baggage
        context = W3CTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
        )
        baggage = ContextBaggage(user_id="user123", tenant_id="tenant456")

        manager = TraceContextManager()
        manager.set_trace_context(context)
        manager.set_baggage(baggage)

        # Verify both are set
        assert manager.get_trace_context().trace_id == context.trace_id
        assert manager.get_baggage().user_id == "user123"

    def test_performance_profile_with_context(self):
        """Test performance profile with trace context."""
        context = W3CTraceContext(
            trace_id="0af7651916cd43dd8448eb211c80319c",
            parent_id="b7ad6b7169203331",
        )
        baggage = ContextBaggage(user_id="user123")

        manager = TraceContextManager()

        with manager.trace_scope(context, baggage):
            # Create and record profile
            profile = PerformanceProfile(
                span_name="integration_test",
                start_time=time.time(),
            )
            time.sleep(0.05)
            profile.finalize()

            manager.set_performance_profile(profile)

            # Verify profile and context
            assert manager.get_trace_context() is context
            assert manager.get_performance_profile().span_name == "integration_test"
