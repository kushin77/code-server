"""
risk_quantification_engine.py — Phase 47: Risk Quantification & Threat Scoring
Synthesises signals from the full Phase 30-46 security stack into quantified
business risk metrics: probability, financial impact, composite risk score.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class RiskLevel(Enum):
    CRITICAL   = "critical"
    HIGH       = "high"
    MEDIUM     = "medium"
    LOW        = "low"
    NEGLIGIBLE = "negligible"


class ImpactCategory(Enum):
    FINANCIAL      = "financial"
    OPERATIONAL    = "operational"
    REPUTATIONAL   = "reputational"
    REGULATORY     = "regulatory"


class RiskTrend(Enum):
    INCREASING  = "increasing"
    STABLE      = "stable"
    DECREASING  = "decreasing"


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class RiskFactor:
    """
    An individual risk dimension sourced from a specific phase.
    probability: 0.0-1.0  (likelihood of materialisation)
    impact:      0.0-100.0 (potential harm magnitude)
    """
    factor_id: str
    name: str
    phase_source: str
    category: ImpactCategory
    probability: float   # 0-1
    impact: float        # 0-100
    description: str = ""

    def __post_init__(self) -> None:
        self.probability = max(0.0, min(1.0, self.probability))
        self.impact      = max(0.0, min(100.0, self.impact))

    def risk_score(self) -> float:
        """Expected loss proxy: probability * impact, 0-100."""
        return round(self.probability * self.impact, 2)

    def risk_level(self) -> RiskLevel:
        score = self.risk_score()
        if score >= 70:
            return RiskLevel.CRITICAL
        if score >= 50:
            return RiskLevel.HIGH
        if score >= 30:
            return RiskLevel.MEDIUM
        if score >= 10:
            return RiskLevel.LOW
        return RiskLevel.NEGLIGIBLE


@dataclass
class BusinessImpact:
    """
    Estimated business impact derived from threat materialisation.
    financial_loss_usd: estimated dollar exposure
    downtime_hours:     expected outage duration
    data_records_at_risk: number of records potentially compromised
    """
    financial_loss_usd: float    = 0.0
    downtime_hours: float        = 0.0
    data_records_at_risk: int    = 0
    regulatory_fine_usd: float   = 0.0

    def total_exposure_usd(self) -> float:
        """Aggregate financial exposure."""
        downtime_cost = self.downtime_hours * 15_000  # $15k/hr industry average
        return round(self.financial_loss_usd + downtime_cost + self.regulatory_fine_usd, 2)

    def severity_label(self) -> str:
        exposure = self.total_exposure_usd()
        if exposure >= 1_000_000:
            return "catastrophic"
        if exposure >= 100_000:
            return "severe"
        if exposure >= 10_000:
            return "moderate"
        if exposure > 0:
            return "minor"
        return "negligible"


@dataclass
class ThreatScoreRecord:
    """
    Aggregated risk assessment for a target (service, system, or platform).
    """
    record_id: str
    target: str
    phase_signals: Dict[str, float]
    factors: List[RiskFactor] = field(default_factory=list)
    impact: Optional[BusinessImpact] = None
    trend: RiskTrend = RiskTrend.STABLE
    assessed_at: datetime = field(default_factory=datetime.utcnow)

    # --- factor helpers ---

    def composite_score(self) -> float:
        """
        Composite risk score 0-100 using probability-weighted average of factor scores.
        """
        if not self.factors:
            return 0.0
        weighted = sum(f.risk_score() for f in self.factors)
        return round(min(100.0, weighted / len(self.factors)), 2)

    def overall_risk_level(self) -> RiskLevel:
        score = self.composite_score()
        if score >= 70:
            return RiskLevel.CRITICAL
        if score >= 50:
            return RiskLevel.HIGH
        if score >= 30:
            return RiskLevel.MEDIUM
        if score >= 10:
            return RiskLevel.LOW
        return RiskLevel.NEGLIGIBLE

    def factors_by_level(self) -> Dict[str, int]:
        counts: Dict[str, int] = {lvl.value: 0 for lvl in RiskLevel}
        for f in self.factors:
            counts[f.risk_level().value] += 1
        return counts

    def top_factors(self, n: int = 3) -> List[RiskFactor]:
        return sorted(self.factors, key=lambda f: f.risk_score(), reverse=True)[:n]

    def phase47_score(self) -> float:
        """
        0-25 contribution score for cross-phase integration.
        Inverted: lower risk → higher security posture score.
        """
        composite = self.composite_score()
        # 25 = perfect security (composite 0), 0 = maximum risk (composite 100)
        return round(max(0.0, 25.0 - (composite * 25.0 / 100.0)), 2)


# ---------------------------------------------------------------------------
# Standard risk factors (Phase 30-46 coverage)
# ---------------------------------------------------------------------------


def _default_factors(phase_signals: Dict[str, float]) -> List[RiskFactor]:
    """Derive standard risk factors from upstream phase telemetry."""

    def prob(signal_key: str, default: float, invert: bool = False) -> float:
        """
        Convert a 0-100 phase score to a 0-1 probability.
        invert=True  → high score means high probability (threat signal)
        invert=False → high score means low probability (security control signal)
        """
        raw = phase_signals.get(signal_key, default)
        raw = max(0.0, min(100.0, raw))
        return round((raw / 100.0) if invert else (1.0 - raw / 100.0), 4)

    return [
        RiskFactor(
            factor_id="rf-threat-detection",
            name="Undetected Threat Exposure",
            phase_source="phase_30",
            category=ImpactCategory.OPERATIONAL,
            probability=prob("phase30_score", 85.0),
            impact=75.0,
            description="Residual threat exposure not caught by detection models",
        ),
        RiskFactor(
            factor_id="rf-compliance-gap",
            name="Compliance Gap Risk",
            phase_source="phase_31",
            category=ImpactCategory.REGULATORY,
            probability=prob("phase31_score", 88.0),
            impact=60.0,
            description="Risk from unaddressed compliance obligations",
        ),
        RiskFactor(
            factor_id="rf-behavioral-anomaly",
            name="Behavioral Anomaly Risk",
            phase_source="phase_33",
            category=ImpactCategory.OPERATIONAL,
            probability=prob("phase33_score", 82.0),
            impact=55.0,
            description="Risk from unresolved behavioral anomalies",
        ),
        RiskFactor(
            factor_id="rf-forensic-evidence",
            name="Forensic Evidence Gap",
            phase_source="phase_34",
            category=ImpactCategory.REGULATORY,
            probability=prob("phase34_score", 84.0),
            impact=45.0,
            description="Risk from incomplete forensic evidence chains",
        ),
        RiskFactor(
            factor_id="rf-response-latency",
            name="Incident Response Latency",
            phase_source="phase_38",
            category=ImpactCategory.OPERATIONAL,
            probability=prob("phase38_score", 83.0),
            impact=65.0,
            description="Risk from slow incident response (MTTR)",
        ),
        RiskFactor(
            factor_id="rf-predictive-threat",
            name="Predictive Threat Materialisation",
            phase_source="phase_40",
            category=ImpactCategory.FINANCIAL,
            probability=prob("phase40_score", 86.0),
            impact=70.0,
            description="Probability that predicted threats materialise",
        ),
        RiskFactor(
            factor_id="rf-deployment-gate",
            name="Deployment Gate Failure Risk",
            phase_source="phase_45",
            category=ImpactCategory.OPERATIONAL,
            probability=prob("phase45_score", 88.0),
            impact=50.0,
            description="Risk from deployment bypassing security gates",
        ),
        RiskFactor(
            factor_id="rf-audit-posture",
            name="Audit Posture Risk",
            phase_source="phase_46",
            category=ImpactCategory.REPUTATIONAL,
            probability=prob("phase46_score", 90.0),
            impact=40.0,
            description="Risk from incomplete compliance audit coverage",
        ),
    ]


# ---------------------------------------------------------------------------
# Risk Quantification Engine
# ---------------------------------------------------------------------------


class RiskQuantificationEngine:
    """
    Central engine for computing quantified risk assessments across the
    Phase 30-46 security intelligence stack.
    """

    def __init__(self) -> None:
        self.assessments: Dict[str, ThreatScoreRecord] = {}
        self.history: List[ThreatScoreRecord] = []

    # --- lifecycle ---

    def create_assessment(
        self,
        target: str,
        phase_signals: Optional[Dict[str, float]] = None,
    ) -> ThreatScoreRecord:
        record_id = f"{target.lower().replace(' ', '-')}-{datetime.utcnow().strftime('%Y%m%dT%H%M%S')}"
        record = ThreatScoreRecord(
            record_id=record_id,
            target=target,
            phase_signals=dict(phase_signals or {}),
            factors=_default_factors(dict(phase_signals or {})),
        )
        self.assessments[record_id] = record
        return record

    def add_factor(
        self,
        record: ThreatScoreRecord,
        factor_id: str,
        name: str,
        phase_source: str,
        category: ImpactCategory,
        probability: float,
        impact: float,
        description: str = "",
    ) -> RiskFactor:
        factor = RiskFactor(
            factor_id=factor_id,
            name=name,
            phase_source=phase_source,
            category=category,
            probability=probability,
            impact=impact,
            description=description,
        )
        record.factors.append(factor)
        return factor

    def set_business_impact(
        self,
        record: ThreatScoreRecord,
        financial_loss_usd: float = 0.0,
        downtime_hours: float = 0.0,
        data_records_at_risk: int = 0,
        regulatory_fine_usd: float = 0.0,
    ) -> BusinessImpact:
        impact = BusinessImpact(
            financial_loss_usd=financial_loss_usd,
            downtime_hours=downtime_hours,
            data_records_at_risk=data_records_at_risk,
            regulatory_fine_usd=regulatory_fine_usd,
        )
        record.impact = impact
        return impact

    def compute_trend(
        self,
        record: ThreatScoreRecord,
        previous_score: Optional[float] = None,
    ) -> RiskTrend:
        if previous_score is None:
            record.trend = RiskTrend.STABLE
            return record.trend
        current = record.composite_score()
        delta = current - previous_score
        if delta > 5.0:
            record.trend = RiskTrend.INCREASING
        elif delta < -5.0:
            record.trend = RiskTrend.DECREASING
        else:
            record.trend = RiskTrend.STABLE
        return record.trend

    def finalize(self, record: ThreatScoreRecord) -> None:
        self.history.append(record)
        self.assessments.pop(record.record_id, None)

    # --- reporting ---

    def generate_report(self, record: ThreatScoreRecord) -> Dict:
        report: Dict = {
            "record_id": record.record_id,
            "target": record.target,
            "composite_score": record.composite_score(),
            "overall_risk_level": record.overall_risk_level().value,
            "phase47_score": record.phase47_score(),
            "trend": record.trend.value,
            "factors_by_level": record.factors_by_level(),
            "top_factors": [
                {"name": f.name, "score": f.risk_score(), "level": f.risk_level().value}
                for f in record.top_factors(3)
            ],
        }
        if record.impact:
            report["business_impact"] = {
                "total_exposure_usd": record.impact.total_exposure_usd(),
                "severity": record.impact.severity_label(),
                "downtime_hours": record.impact.downtime_hours,
                "data_records_at_risk": record.impact.data_records_at_risk,
            }
        return report

    def summary(self) -> Dict:
        all_records = list(self.assessments.values()) + self.history
        if not all_records:
            return {
                "total_assessments": 0,
                "avg_composite_score": 0.0,
                "critical_targets": 0,
                "avg_phase47_score": 0.0,
                "phase47_risk_score": 0.0,
            }
        composites = [r.composite_score() for r in all_records]
        p47_scores  = [r.phase47_score() for r in all_records]
        avg_composite = round(sum(composites) / len(composites), 2)
        avg_p47       = round(sum(p47_scores)  / len(p47_scores), 2)
        return {
            "total_assessments": len(all_records),
            "avg_composite_score": avg_composite,
            "critical_targets": sum(
                1 for r in all_records
                if r.overall_risk_level() == RiskLevel.CRITICAL
            ),
            "avg_phase47_score": avg_p47,
            "phase47_risk_score": avg_p47,
        }


# ---------------------------------------------------------------------------
# Top-level scorer
# ---------------------------------------------------------------------------


def quantify_risk(engine: RiskQuantificationEngine) -> float:
    """Return the phase47_risk_score (0-25) from the engine summary."""
    return float(engine.summary().get("phase47_risk_score", 0.0))
