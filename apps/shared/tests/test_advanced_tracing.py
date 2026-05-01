"""Tests for the advanced tracing façade."""

import asyncio
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


TRACE_PATTERNS = _load_module("apps.shared.trace_patterns", "trace_patterns.py")
shared_pkg.trace_patterns = TRACE_PATTERNS
ADVANCED_TRACING = _load_module("apps.shared.advanced_tracing", "advanced_tracing.py")


def test_advanced_tracer_sampling_and_headers() -> None:
    tracer = ADVANCED_TRACING.AdvancedTracer(
        ADVANCED_TRACING.AdvancedTracingConfig(
            sampling_config=TRACE_PATTERNS.TraceSamplingConfig(
                strategy=TRACE_PATTERNS.SamplingStrategy.ALWAYS,
                always_sample_paths=["/critical"],
                exclude_paths=["/health"],
            )
        )
    )

    assert tracer.should_sample(path="/critical/jobs") is True
    assert tracer.should_sample(path="/health") is False

    context = tracer.create_trace_context("0123456789abcdef0123456789abcdef", "1111111111111111")
    baggage = TRACE_PATTERNS.ContextBaggage(user_id="alice", tenant_id="acme")
    headers = tracer.get_propagation_headers(context, baggage)

    assert headers["traceparent"].startswith("00-0123456789abcdef0123456789abcdef")
    assert headers["baggage"].startswith("userId=alice")


def test_advanced_tracer_trace_request_profiles_sync_and_async() -> None:
    tracer = ADVANCED_TRACING.AdvancedTracer(
        ADVANCED_TRACING.AdvancedTracingConfig(
            sampling_config=TRACE_PATTERNS.TraceSamplingConfig(
                strategy=TRACE_PATTERNS.SamplingStrategy.ALWAYS,
                exclude_paths=["/health"],
            )
        )
    )

    @tracer.trace_request(path="/critical/jobs")
    def sync_handler(**kwargs):
        assert kwargs["headers"]["traceparent"]
        return "sync"

    assert (
        sync_handler(headers={"traceparent": "00-0123456789abcdef0123456789abcdef-1111111111111111-01"})
        == "sync"
    )
    assert tracer.get_current_profile() is not None
    assert tracer.get_current_profile().span_name == "sync_handler"

    @tracer.trace_request(path="/critical/jobs")
    async def async_handler(**kwargs):
        assert kwargs["headers"]["traceparent"]
        await asyncio.sleep(0)
        return "async"

    assert (
        asyncio.run(
            async_handler(headers={"traceparent": "00-0123456789abcdef0123456789abcdef-1111111111111111-01"})
        )
        == "async"
    )
    assert tracer.get_current_profile() is not None
    assert tracer.get_current_profile().span_name == "async_handler"
