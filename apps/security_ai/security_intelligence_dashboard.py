"""
security_intelligence_dashboard.py — Phase 48: Security Intelligence Dashboard & Metrics Aggregation
Aggregates all Phase 30-47 signals into a unified real-time security intelligence platform.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class MetricStatus(Enum):
    HEALTHY   = "healthy"
    WARNING   = "warning"
    CRITICAL  = "critical"
    UNKNOWN   = "unknown"


class AlertSeverity(Enum):
    CRITICAL  = "critical"
    HIGH      = "high"
    MEDIUM    = "medium"
    LOW       = "low"


class DashboardTier(Enum):
    EXECUTIVE  = "executive"   # C-suite: risk/compliance summary
    OPERATIONS = "operations"  # SOC: incident/threat view
    ENGINEERING = "engineering"  # Dev: deployment/gate view


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class PhaseMetric:
    """
    A single phase's contribution to the dashboard.
    score:   0-25 (the phase's standardised security posture contribution)
    weight:  relative importance in composite index (default 1.0)
    """
    phase_id: str
    phase_name: str
    score: float          # 0-25
    weight: float = 1.0
    status: MetricStatus = MetricStatus.UNKNOWN
    detail: str = ""
    recorded_at: datetime = field(default_factory=datetime.utcnow)

    def __post_init__(self) -> None:
        self.score = max(0.0, min(25.0, self.score))
        if self.status == MetricStatus.UNKNOWN:
            self.status = self._derive_status()

    def _derive_status(self) -> MetricStatus:
        if self.score >= 20.0:
            return MetricStatus.HEALTHY
        if self.score >= 12.0:
            return MetricStatus.WARNING
        return MetricStatus.CRITICAL

    def weighted_score(self) -> float:
        return round(self.score * self.weight, 4)


@dataclass
class DashboardAlert:
    alert_id: str
    title: str
    description: str
    severity: AlertSeverity
    phase_source: str
    triggered_at: datetime = field(default_factory=datetime.utcnow)
    acknowledged: bool = False

    def acknowledge(self) -> None:
        self.acknowledged = True


@dataclass
class DashboardSnapshot:
    """
    Point-in-time snapshot of the full security intelligence platform.
    """
    snapshot_id: str
    tier: DashboardTier
    metrics: List[PhaseMetric] = field(default_factory=list)
    alerts: List[DashboardAlert] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.utcnow)

    # --- aggregate metrics ---

    def composite_index(self) -> float:
        """
        Weighted composite security index 0-100.
        Each phase contributes up to 25 pts; we normalise to 0-100.
        """
        if not self.metrics:
            return 0.0
        total_weight = sum(m.weight for m in self.metrics)
        if total_weight == 0:
            return 0.0
        weighted_sum = sum(m.weighted_score() for m in self.metrics)
        # Max possible = 25 * total_weight → normalise to 100
        raw = (weighted_sum / (25.0 * total_weight)) * 100.0
        return round(min(100.0, raw), 2)

    def phase48_score(self) -> float:
        """0-25 contribution for cross-phase integration."""
        return round(self.composite_index() * 25.0 / 100.0, 2)

    def metric_summary(self) -> Dict[str, int]:
        counts: Dict[str, int] = {s.value: 0 for s in MetricStatus}
        for m in self.metrics:
            counts[m.status.value] += 1
        return counts

    def open_alerts_by_severity(self) -> Dict[str, int]:
        counts: Dict[str, int] = {s.value: 0 for s in AlertSeverity}
        for a in self.alerts:
            if not a.acknowledged:
                counts[a.severity.value] += 1
        return counts

    def critical_alert_count(self) -> int:
        return sum(
            1 for a in self.alerts
            if a.severity == AlertSeverity.CRITICAL and not a.acknowledged
        )

    def overall_status(self) -> MetricStatus:
        if any(m.status == MetricStatus.CRITICAL for m in self.metrics):
            return MetricStatus.CRITICAL
        if any(m.status == MetricStatus.WARNING for m in self.metrics):
            return MetricStatus.WARNING
        if self.metrics:
            return MetricStatus.HEALTHY
        return MetricStatus.UNKNOWN

    def top_risks(self, n: int = 3) -> List[PhaseMetric]:
        """Return the n lowest-scoring (highest-risk) metrics."""
        return sorted(self.metrics, key=lambda m: m.score)[:n]


# ---------------------------------------------------------------------------
# Dashboard Engine
# ---------------------------------------------------------------------------

_ALERT_COUNTER = 0


def _next_alert_id() -> str:
    global _ALERT_COUNTER
    _ALERT_COUNTER += 1
    return f"ALT-{_ALERT_COUNTER:04d}"


class SecurityIntelligenceDashboard:
    """
    Central security intelligence aggregation platform for Phases 30-47.
    """

    # Default phase registry: phase_id → (name, default_score, weight)
    PHASE_REGISTRY: Dict[str, Tuple[str, float, float]] = {
        "phase_30": ("Threat Detection",            22.0, 1.2),
        "phase_31": ("Compliance Automation",        21.0, 1.1),
        "phase_32": ("Policy Engine",                20.0, 1.0),
        "phase_33": ("Behavioral Analytics",         20.5, 1.0),
        "phase_34": ("Forensics Engine",             19.5, 1.0),
        "phase_35": ("Advanced Compliance",          20.0, 1.0),
        "phase_36": ("Adaptive Response",            21.5, 1.1),
        "phase_37": ("Cost Optimizer",               18.0, 0.8),
        "phase_38": ("Incident Response",            20.0, 1.2),
        "phase_39": ("Autonomous Optimizer",         19.0, 0.9),
        "phase_40": ("Predictive Threat Intel",      21.0, 1.2),
        "phase_41": ("Intelligent IR",               20.5, 1.0),
        "phase_42": ("Advanced Threat Hunting",      20.0, 1.0),
        "phase_43": ("Advanced Compliance Auto",     19.5, 1.0),
        "phase_44": ("Platform Orchestration",       21.0, 1.1),
        "phase_45": ("Deployment Orchestrator",      22.0, 1.2),
        "phase_46": ("Compliance Audit Engine",      22.0, 1.1),
        "phase_47": ("Risk Quantification",          21.5, 1.1),
    }

    def __init__(self) -> None:
        self.snapshots: List[DashboardSnapshot] = []
        self._phase_overrides: Dict[str, float] = {}

    # --- lifecycle ---

    def ingest_phase_scores(self, scores: Dict[str, float]) -> None:
        """Override default scores with live phase telemetry."""
        self._phase_overrides.update(scores)

    def create_snapshot(
        self,
        tier: DashboardTier = DashboardTier.OPERATIONS,
        phase_subset: Optional[List[str]] = None,
    ) -> DashboardSnapshot:
        snapshot_id = f"snap-{tier.value}-{datetime.utcnow().strftime('%Y%m%dT%H%M%S')}"
        snapshot = DashboardSnapshot(snapshot_id=snapshot_id, tier=tier)

        registry = self.PHASE_REGISTRY
        if phase_subset:
            registry = {k: v for k, v in registry.items() if k in phase_subset}

        for phase_id, (name, default_score, weight) in registry.items():
            score = self._phase_overrides.get(phase_id, default_score)
            metric = PhaseMetric(
                phase_id=phase_id,
                phase_name=name,
                score=score,
                weight=weight,
            )
            snapshot.metrics.append(metric)

        # Auto-raise alerts for critical metrics
        self._auto_alert(snapshot)
        self.snapshots.append(snapshot)
        return snapshot

    def add_alert(
        self,
        snapshot: DashboardSnapshot,
        title: str,
        description: str,
        severity: AlertSeverity,
        phase_source: str,
    ) -> DashboardAlert:
        alert = DashboardAlert(
            alert_id=_next_alert_id(),
            title=title,
            description=description,
            severity=severity,
            phase_source=phase_source,
        )
        snapshot.alerts.append(alert)
        return alert

    def acknowledge_alert(
        self, snapshot: DashboardSnapshot, alert_id: str
    ) -> bool:
        for a in snapshot.alerts:
            if a.alert_id == alert_id:
                a.acknowledge()
                return True
        return False

    def generate_report(
        self, snapshot: DashboardSnapshot
    ) -> Dict:
        return {
            "snapshot_id": snapshot.snapshot_id,
            "tier": snapshot.tier.value,
            "composite_index": snapshot.composite_index(),
            "phase48_score": snapshot.phase48_score(),
            "overall_status": snapshot.overall_status().value,
            "metric_summary": snapshot.metric_summary(),
            "open_alerts": snapshot.open_alerts_by_severity(),
            "critical_alerts": snapshot.critical_alert_count(),
            "top_risks": [
                {"phase": m.phase_id, "score": m.score, "status": m.status.value}
                for m in snapshot.top_risks(3)
            ],
            "total_phases": len(snapshot.metrics),
        }

    def summary(self) -> Dict:
        if not self.snapshots:
            return {
                "total_snapshots": 0,
                "avg_composite_index": 0.0,
                "healthy_snapshots": 0,
                "total_critical_alerts": 0,
                "phase48_dashboard_score": 0.0,
            }
        composites = [s.composite_index() for s in self.snapshots]
        avg = round(sum(composites) / len(composites), 2)
        return {
            "total_snapshots": len(self.snapshots),
            "avg_composite_index": avg,
            "healthy_snapshots": sum(
                1 for s in self.snapshots
                if s.overall_status() == MetricStatus.HEALTHY
            ),
            "total_critical_alerts": sum(
                s.critical_alert_count() for s in self.snapshots
            ),
            "phase48_dashboard_score": round(avg * 25.0 / 100.0, 2),
        }

    # --- internal ---

    def _auto_alert(self, snapshot: DashboardSnapshot) -> None:
        for m in snapshot.metrics:
            if m.status == MetricStatus.CRITICAL:
                self.add_alert(
                    snapshot,
                    title=f"Critical: {m.phase_name}",
                    description=f"{m.phase_id} scored {m.score:.1f}/25 — below critical threshold.",
                    severity=AlertSeverity.CRITICAL,
                    phase_source=m.phase_id,
                )
            elif m.status == MetricStatus.WARNING:
                self.add_alert(
                    snapshot,
                    title=f"Warning: {m.phase_name}",
                    description=f"{m.phase_id} scored {m.score:.1f}/25 — below healthy threshold.",
                    severity=AlertSeverity.MEDIUM,
                    phase_source=m.phase_id,
                )


# ---------------------------------------------------------------------------
# Top-level scorer
# ---------------------------------------------------------------------------


def dashboard_score(dash: SecurityIntelligenceDashboard) -> float:
    """Return the phase48_dashboard_score (0-25)."""
    return float(dash.summary().get("phase48_dashboard_score", 0.0))
