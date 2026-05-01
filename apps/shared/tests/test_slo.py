from datetime import timedelta

import pytest

from apps.shared.slo import SLI, SLOTarget, SLOTracker


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

    with pytest.raises(ValueError):
        tracker.register_target(SLOTarget(SLI.AVAILABILITY, 0.99, timedelta(minutes=5), comparison="invalid"))

    with pytest.raises(KeyError):
        tracker.evaluate(SLI.AVAILABILITY, 0.99)