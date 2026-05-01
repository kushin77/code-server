import asyncio
import importlib.util
import sys
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "tracing.py"
SPEC = importlib.util.spec_from_file_location("shared_tracing_test_module", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
TRACING = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = TRACING
SPEC.loader.exec_module(TRACING)


def test_generate_trace_id_and_setup_tracing_disabled() -> None:
    trace_id = TRACING.generate_trace_id()

    runtime = TRACING.setup_tracing(
        TRACING.TracingConfig(
            service_name="demo",
            enabled=False,
        )
    )

    assert len(trace_id) == 32
    assert int(trace_id, 16) >= 0
    assert runtime.enabled is False
    assert runtime.implementation == "disabled"
    assert TRACING.current_trace_id() is None or isinstance(TRACING.current_trace_id(), str)


def test_trace_operation_wraps_sync_and_async_code() -> None:
    runtime = TRACING.TracingRuntime(
        config=TRACING.TracingConfig(service_name="demo", enabled=False),
        enabled=False,
        implementation="fallback",
    )

    @TRACING.trace_operation(runtime, "demo.sync")
    def sync_function() -> str:
        trace_id = TRACING.current_trace_id()
        assert trace_id is not None
        return trace_id

    assert len(sync_function()) == 32

    async_runtime = TRACING.TracingRuntime(
        config=TRACING.TracingConfig(service_name="demo", enabled=False),
        enabled=False,
        implementation="fallback",
    )

    @TRACING.trace_operation(async_runtime, "demo.async")
    async def async_function() -> str:
        trace_id = TRACING.current_trace_id()
        assert trace_id is not None
        return trace_id

    result = asyncio.run(async_function())
    assert len(result) == 32