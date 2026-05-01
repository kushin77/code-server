"""AI-assisted operations helpers for alert deduplication and response planning.

This module intentionally uses deterministic heuristics rather than external ML
dependencies so it can run in constrained environments and still provide useful
operator guidance.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List


@dataclass
class AlertDeduplicationResult:
    """Result of deduplicating a group of alerts."""

    unique_alerts: List[Any]
    duplicate_count: int
    fingerprints: Dict[str, int] = field(default_factory=dict)


@dataclass
class RunbookRecommendation:
    """Recommended runbook for a given alert."""

    alert_name: str
    component: str
    runbook: str
    confidence: float


@dataclass
class ScalingRecommendation:
    """Recommended scaling action for a given alert group."""

    component: str
    action: str
    reason: str
    confidence: float


@dataclass
class AIOperationsResult:
    """Combined AI operations output for an alert group."""

    deduplication: AlertDeduplicationResult
    runbooks: List[RunbookRecommendation]
    scaling: List[ScalingRecommendation]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "deduplication": {
                "unique_alerts": [alert.name for alert in self.deduplication.unique_alerts],
                "duplicate_count": self.deduplication.duplicate_count,
                "fingerprints": self.deduplication.fingerprints,
            },
            "runbooks": [
                {
                    "alert_name": item.alert_name,
                    "component": item.component,
                    "runbook": item.runbook,
                    "confidence": item.confidence,
                }
                for item in self.runbooks
            ],
            "scaling": [
                {
                    "component": item.component,
                    "action": item.action,
                    "reason": item.reason,
                    "confidence": item.confidence,
                }
                for item in self.scaling
            ],
        }


class AIOperationsAdvisor:
    """Deterministic advisory heuristics for AI-powered operations."""

    _RUNBOOK_MAP = {
        "database": "docs/operations/runbooks/database-recovery.md",
        "postgres": "docs/operations/runbooks/database-recovery.md",
        "redis": "docs/operations/runbooks/cache-recovery.md",
        "cache": "docs/operations/runbooks/cache-recovery.md",
        "cpu": "docs/operations/runbooks/cpu-saturation.md",
        "memory": "docs/operations/runbooks/memory-pressure.md",
        "latency": "docs/operations/runbooks/latency-investigation.md",
        "network": "docs/operations/runbooks/network-triage.md",
        "control-plane": "docs/operations/runbooks/control-plane-recovery.md",
        "agent-runtime": "docs/operations/runbooks/agent-runtime-recovery.md",
    }

    _SCALING_COMPONENTS = {"cpu", "memory", "api", "control-plane", "agent-runtime", "throughput"}

    def deduplicate_alerts(self, alert_group: Any) -> AlertDeduplicationResult:
        seen: Dict[str, Any] = {}
        fingerprints: Dict[str, int] = {}

        for alert in alert_group.alerts:
            fingerprint = self._fingerprint(alert)
            fingerprints[fingerprint] = fingerprints.get(fingerprint, 0) + 1
            seen.setdefault(fingerprint, alert)

        unique_alerts = list(seen.values())
        duplicate_count = max(0, len(alert_group.alerts) - len(unique_alerts))
        return AlertDeduplicationResult(
            unique_alerts=unique_alerts,
            duplicate_count=duplicate_count,
            fingerprints=fingerprints,
        )

    def recommend_runbooks(self, alert_group: Any) -> List[RunbookRecommendation]:
        recommendations: List[RunbookRecommendation] = []

        for alert in alert_group.alerts:
            runbook = alert.annotations.get("runbook") or self._fallback_runbook(alert)
            confidence = 0.95 if "runbook" in alert.annotations else 0.7
            recommendations.append(
                RunbookRecommendation(
                    alert_name=alert.name,
                    component=alert.component,
                    runbook=runbook,
                    confidence=confidence,
                )
            )

        return recommendations

    def recommend_scaling(self, alert_group: Any) -> List[ScalingRecommendation]:
        recommendations: List[ScalingRecommendation] = []

        for alert in alert_group.alerts:
            component = alert.component.lower()
            name = alert.name.lower()

            if component in self._SCALING_COMPONENTS or any(keyword in name for keyword in ("load", "latency", "throughput", "cpu", "memory")):
                severity = self._severity_value(alert)
                if severity == "critical":
                    action = "scale_up_immediately"
                    confidence = 0.95
                elif severity == "warning":
                    action = "scale_up_with_review"
                    confidence = 0.8
                else:
                    action = "monitor"
                    confidence = 0.5

                recommendations.append(
                    ScalingRecommendation(
                        component=alert.component,
                        action=action,
                        reason=f"{alert.name} indicates capacity pressure or performance degradation",
                        confidence=confidence,
                    )
                )

        return recommendations

    def analyze_alert_group(self, alert_group: Any) -> AIOperationsResult:
        return AIOperationsResult(
            deduplication=self.deduplicate_alerts(alert_group),
            runbooks=self.recommend_runbooks(alert_group),
            scaling=self.recommend_scaling(alert_group),
        )

    def execute_recommended_runbooks(self, alert_group: Any) -> List[Dict[str, Any]]:
        """Return a plan for automatic runbook execution.

        This is intentionally deterministic and side-effect free. A caller can
        interpret the plan and execute the listed runbooks if desired.
        """

        plan: List[Dict[str, Any]] = []
        for recommendation in self.recommend_runbooks(alert_group):
            plan.append(
                {
                    "alert_name": recommendation.alert_name,
                    "component": recommendation.component,
                    "runbook": recommendation.runbook,
                    "confidence": recommendation.confidence,
                    "action": "execute_runbook",
                }
            )
        return plan

    def _fingerprint(self, alert: Any) -> str:
        labels = getattr(alert, "labels", {})
        return "|".join(
            [
                labels.get("alertname", self._alert_name(alert)),
                labels.get("component", self._alert_component(alert)),
                labels.get("severity", self._severity_value(alert)),
            ]
        )

    def _fallback_runbook(self, alert: Any) -> str:
        component = self._alert_component(alert).lower()
        for key, runbook in self._RUNBOOK_MAP.items():
            if key in component or key in self._alert_name(alert).lower():
                return runbook
        return "docs/operations/runbooks/general-alert-triage.md"

    def _alert_name(self, alert: Any) -> str:
        return getattr(alert, "name", getattr(getattr(alert, "labels", {}), "get", lambda *_: "Unknown")("alertname", "Unknown"))

    def _alert_component(self, alert: Any) -> str:
        return getattr(alert, "component", getattr(getattr(alert, "labels", {}), "get", lambda *_: "unknown")("component", "unknown"))

    def _severity_value(self, alert: Any) -> str:
        severity = getattr(alert, "severity", None)
        if hasattr(severity, "value"):
            return str(severity.value)
        if isinstance(severity, str):
            return severity.lower()
        labels = getattr(alert, "labels", {})
        return str(labels.get("severity", "info")).lower()


__all__ = [
    "AIOperationsAdvisor",
    "AIOperationsResult",
    "AlertDeduplicationResult",
    "RunbookRecommendation",
    "ScalingRecommendation",
]