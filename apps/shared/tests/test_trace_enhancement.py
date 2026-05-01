"""Tests for the trace enhancement bridge."""

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
shared_pkg.advanced_tracing = ADVANCED_TRACING
TRACE_ENHANCEMENT = _load_module("apps.shared.trace_enhancement", "trace_enhancement.py")


def test_sampling_and_header_propagation_helpers() -> None:
    TRACE_ENHANCEMENT.initialize_trace_enhancement(
        TRACE_PATTERNS.TraceSamplingConfig(
            strategy=TRACE_PATTERNS.SamplingStrategy.ALWAYS,
            always_sample_paths=["/critical"],
        )
    )

    assert TRACE_ENHANCEMENT.setup_request_sampling("/critical/jobs", {"baggage": "userId=alice"}) is True
    headers = TRACE_ENHANCEMENT.get_outbound_trace_headers()

    assert headers["traceparent"].startswith("00-")
    assert headers["baggage"].startswith("userId=alice")

    TRACE_ENHANCEMENT.end_request_trace()
