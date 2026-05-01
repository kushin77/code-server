import importlib.util
import sys
import types
from datetime import timedelta
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


SLO = _load_module("apps.shared.slo", "slo.py")

SLI = SLO.SLI
SLOTarget = SLO.SLOTarget
SLOTracker = SLO.SLOTracker


def test_slo_tracker_evaluates_availability_and_error_rate() -> None:
    tracker = SLOTracker("control-plane")
    tracker.register_target(SLOTarget(SLI.AVAILABILITY, 0.999, timedelta(minutes=5), comparison="gte"))
    tracker.register_target(SLOTarget(SLI.ERROR_RATE, 0.001, timedelta(minutes=5), comparison="lte"))

    availability = tracker.evaluate_availability(999, 1000)
    error_rate = tracker.evaluate_error_rate(2, 1000)

    assert availability.achieved is True
    assert availability.margin >= 0
    assert error_rate.achieved is False
    assert error_rate.margin < 0


def test_slo_tracker_evaluates_latency_and_summarizes_violations() -> None:
    tracker = SLOTracker("control-plane")
    tracker.register_target(SLOTarget(SLI.LATENCY_P99, 0.5, timedelta(minutes=5), comparison="lte"))

    result = tracker.evaluate_latency(0.42)
    violation = tracker.evaluate_latency(0.75)

    summary = tracker.summarize()

    assert result.achieved is True
    assert violation.achieved is False
    assert summary["service"] == "control-plane"
    assert len(summary["targets"]) == 1
    assert len(summary["violations"]) == 1


def test_slo_tracker_rejects_invalid_configuration() -> None:
    tracker = SLOTracker("demo")

    caught_value_error = False
    try:
        tracker.register_target(SLOTarget(SLI.AVAILABILITY, 0.99, timedelta(minutes=5), comparison="invalid"))
    except ValueError:
        caught_value_error = True

    caught_key_error = False
    try:
        tracker.evaluate(SLI.AVAILABILITY, 0.99)
    except KeyError:
        caught_key_error = True

    assert caught_value_error
    assert caught_key_error