"""Shared SLO and SLI helpers for observability automation."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, List, Optional


class SLI(str, Enum):
    """Service level indicators used by the observability stack."""

    AVAILABILITY = "availability"
    LATENCY_P50 = "latency_p50"
    LATENCY_P99 = "latency_p99"
    ERROR_RATE = "error_rate"


@dataclass(frozen=True)
class SLOTarget:
    """Target value for a service level indicator."""

    sli: SLI
    target_value: float
    window: timedelta
    comparison: str = "gte"
    severity: str = "warning"
    description: str = ""

    def validate(self) -> None:
        if self.comparison not in {"gte", "lte"}:
            raise ValueError(f"Unsupported comparison: {self.comparison}")


@dataclass
class SLOResult:
    """Result of evaluating an SLO target."""

    sli: SLI
    target_value: float
    actual_value: float
    achieved: bool
    margin: float
    evaluated_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())


@dataclass
class SLOViolation:
    """Recorded SLO violation."""

    sli: SLI
    slo_target: float
    actual_value: float
    duration: timedelta
    severity: str
    observed_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())


class SLOTracker:
    """Evaluate service level objectives and track violations."""

    def __init__(self, service_name: str):
        self.service_name = service_name
        self._targets: Dict[SLI, SLOTarget] = {}
        self._violations: List[SLOViolation] = []

    def register_target(self, target: SLOTarget) -> None:
        """Register an SLO target for later evaluation."""

        target.validate()
        self._targets[target.sli] = target

    def evaluate(self, sli: SLI, actual_value: float) -> SLOResult:
        """Evaluate an SLI against its registered target."""

        target = self._targets.get(sli)
        if target is None:
            raise KeyError(f"No SLO target registered for {sli.value}")

        if target.comparison == "gte":
            achieved = actual_value >= target.target_value
            margin = actual_value - target.target_value
        else:
            achieved = actual_value <= target.target_value
            margin = target.target_value - actual_value

        result = SLOResult(
            sli=sli,
            target_value=target.target_value,
            actual_value=actual_value,
            achieved=achieved,
            margin=margin,
        )

        if not achieved:
            self._violations.append(
                SLOViolation(
                    sli=sli,
                    slo_target=target.target_value,
                    actual_value=actual_value,
                    duration=target.window,
                    severity=target.severity,
                )
            )

        return result

    def evaluate_availability(self, success_count: int, total_count: int) -> SLOResult:
        """Evaluate availability as success / total."""

        if total_count <= 0:
            raise ValueError("total_count must be greater than zero")

        return self.evaluate(SLI.AVAILABILITY, success_count / total_count)

    def evaluate_error_rate(self, error_count: int, total_count: int) -> SLOResult:
        """Evaluate error rate as error / total."""

        if total_count <= 0:
            raise ValueError("total_count must be greater than zero")

        return self.evaluate(SLI.ERROR_RATE, error_count / total_count)

    def evaluate_latency(self, latency_seconds: float, sli: SLI = SLI.LATENCY_P99) -> SLOResult:
        """Evaluate latency against a registered latency SLO."""

        if sli not in {SLI.LATENCY_P50, SLI.LATENCY_P99}:
            raise ValueError("latency SLI must be LATENCY_P50 or LATENCY_P99")

        return self.evaluate(sli, latency_seconds)

    def summarize(self) -> Dict[str, object]:
        """Return a compact summary of all known SLO targets and violations."""

        return {
            "service": self.service_name,
            "targets": [
                {
                    "sli": target.sli.value,
                    "target_value": target.target_value,
                    "comparison": target.comparison,
                    "window_seconds": int(target.window.total_seconds()),
                    "severity": target.severity,
                }
                for target in self._targets.values()
            ],
            "violations": [
                {
                    "sli": violation.sli.value,
                    "slo_target": violation.slo_target,
                    "actual_value": violation.actual_value,
                    "duration_seconds": int(violation.duration.total_seconds()),
                    "severity": violation.severity,
                    "observed_at": violation.observed_at,
                }
                for violation in self._violations
            ],
        }


__all__ = ["SLI", "SLOResult", "SLOTarget", "SLOTracker", "SLOViolation"]