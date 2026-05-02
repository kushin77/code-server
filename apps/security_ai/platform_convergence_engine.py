"""
platform_convergence_engine.py — Phase 51: Unified Security Orchestration & Platform Convergence
Milestone phase: aggregates all Phase 30-50 engines into a single unified control plane,
producing a master platform health index, cross-phase correlation, and executive-ready
convergence reports.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Tuple
import json
import uuid


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class ConvergenceHealth(Enum):
    OPTIMAL   = "optimal"     # composite ≥ 90
    HEALTHY   = "healthy"     # composite ≥ 75
    DEGRADED  = "degraded"    # composite ≥ 50
    CRITICAL  = "critical"    # composite < 50


class CorrelationStrength(Enum):
    STRONG   = "strong"    # |r| ≥ 0.75
    MODERATE = "moderate"  # |r| ≥ 0.40
    WEAK     = "weak"      # |r| < 0.40


class PlatformDomain(Enum):
    SECURITY     = "security"      # Phases 30, 36, 37, 39, 40, 43
    COMPLIANCE   = "compliance"    # Phases 31, 42, 46, 49
    RESILIENCE   = "resilience"    # Phases 34, 41, 44
    INTELLIGENCE = "intelligence"  # Phases 38, 39, 40, 47, 48
    ENGINEERING  = "engineering"   # Phases 32, 33, 35, 45
    GOVERNANCE   = "governance"    # Phases 49, 31


# ---------------------------------------------------------------------------
# Domain configuration: which phases belong to which domain
# ---------------------------------------------------------------------------

DOMAIN_PHASES: Dict[str, List[str]] = {
    PlatformDomain.SECURITY.value:     ["phase30", "phase36", "phase37", "phase40", "phase43"],
    PlatformDomain.COMPLIANCE.value:   ["phase31", "phase42", "phase46", "phase49"],
    PlatformDomain.RESILIENCE.value:   ["phase34", "phase41", "phase44"],
    PlatformDomain.INTELLIGENCE.value: ["phase38", "phase39", "phase47", "phase48"],
    PlatformDomain.ENGINEERING.value:  ["phase32", "phase33", "phase35", "phase45"],
    PlatformDomain.GOVERNANCE.value:   ["phase31", "phase46", "phase49"],
}


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class PhaseSignal:
    """
    Normalised signal from an upstream phase engine.
    score:   0-25 (standardised phase contribution)
    domain:  primary PlatformDomain this phase belongs to
    weight:  relative importance in composite index (default 1.0)
    """
    phase_id: str
    score: float              # 0-25
    domain: PlatformDomain
    label: str = ""
    weight: float = 1.0
    metadata: Dict = field(default_factory=dict)
    ingested_at: datetime = field(default_factory=datetime.utcnow)

    @property
    def normalised(self) -> float:
        """Score normalised to 0-100."""
        return round((self.score / 25.0) * 100.0, 2)

    @property
    def health(self) -> ConvergenceHealth:
        n = self.normalised
        if n >= 90:
            return ConvergenceHealth.OPTIMAL
        if n >= 75:
            return ConvergenceHealth.HEALTHY
        if n >= 50:
            return ConvergenceHealth.DEGRADED
        return ConvergenceHealth.CRITICAL


@dataclass
class CrossPhaseCorrelation:
    """Pearson-like correlation between two phase scores over time."""
    phase_a: str
    phase_b: str
    coefficient: float   # -1.0 to 1.0
    sample_count: int = 1

    @property
    def strength(self) -> CorrelationStrength:
        abs_r = abs(self.coefficient)
        if abs_r >= 0.75:
            return CorrelationStrength.STRONG
        if abs_r >= 0.40:
            return CorrelationStrength.MODERATE
        return CorrelationStrength.WEAK

    def to_dict(self) -> dict:
        return {
            "phase_a": self.phase_a,
            "phase_b": self.phase_b,
            "coefficient": round(self.coefficient, 4),
            "strength": self.strength.value,
            "sample_count": self.sample_count,
        }


@dataclass
class DomainAggregate:
    """Aggregated score and health for a platform domain."""
    domain: PlatformDomain
    phase_signals: List[PhaseSignal]
    weight: float = 1.0

    def avg_score(self) -> float:
        if not self.phase_signals:
            return 0.0
        return round(sum(s.score for s in self.phase_signals) / len(self.phase_signals), 2)

    def avg_normalised(self) -> float:
        return round((self.avg_score() / 25.0) * 100.0, 2)

    def health(self) -> ConvergenceHealth:
        n = self.avg_normalised()
        if n >= 90:
            return ConvergenceHealth.OPTIMAL
        if n >= 75:
            return ConvergenceHealth.HEALTHY
        if n >= 50:
            return ConvergenceHealth.DEGRADED
        return ConvergenceHealth.CRITICAL

    def weakest_phase(self) -> Optional[PhaseSignal]:
        return min(self.phase_signals, key=lambda s: s.score) if self.phase_signals else None

    def to_dict(self) -> dict:
        return {
            "domain": self.domain.value,
            "phase_count": len(self.phase_signals),
            "avg_score": self.avg_score(),
            "avg_normalised": self.avg_normalised(),
            "health": self.health().value,
            "weakest_phase": self.weakest_phase().phase_id if self.weakest_phase() else None,
        }


@dataclass
class ConvergenceSnapshot:
    """
    Full platform convergence snapshot produced by one convergence cycle.
    """
    snapshot_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    created_at: datetime = field(default_factory=datetime.utcnow)
    signals: Dict[str, PhaseSignal] = field(default_factory=dict)
    domain_aggregates: Dict[str, DomainAggregate] = field(default_factory=dict)
    correlations: List[CrossPhaseCorrelation] = field(default_factory=list)

    # ---- Composite index --------------------------------------------------

    def composite_index(self) -> float:
        """
        Weighted composite platform health index (0-100).
        Each domain contributes proportionally to its weight.
        """
        if not self.domain_aggregates:
            return 0.0
        total_weight = sum(da.weight for da in self.domain_aggregates.values())
        if total_weight == 0:
            return 0.0
        weighted_sum = sum(
            da.avg_normalised() * da.weight
            for da in self.domain_aggregates.values()
        )
        return round(weighted_sum / total_weight, 2)

    def phase50_score(self) -> int:
        """Contribution to Phase 31 gate (0-25). Linear: 100→25, 0→0."""
        return round((self.composite_index() / 100.0) * 25)

    def overall_health(self) -> ConvergenceHealth:
        ci = self.composite_index()
        if ci >= 90:
            return ConvergenceHealth.OPTIMAL
        if ci >= 75:
            return ConvergenceHealth.HEALTHY
        if ci >= 50:
            return ConvergenceHealth.DEGRADED
        return ConvergenceHealth.CRITICAL

    def top_risks(self, n: int = 5) -> List[PhaseSignal]:
        """Return the n lowest-scoring phase signals."""
        return sorted(self.signals.values(), key=lambda s: s.score)[:n]

    def strong_correlations(self) -> List[CrossPhaseCorrelation]:
        return [c for c in self.correlations if c.strength == CorrelationStrength.STRONG]

    def domain_health_map(self) -> Dict[str, str]:
        return {k: da.health().value for k, da in self.domain_aggregates.items()}

    def summary(self) -> dict:
        return {
            "snapshot_id": self.snapshot_id,
            "created_at": self.created_at.isoformat(),
            "phases_ingested": len(self.signals),
            "composite_index": self.composite_index(),
            "overall_health": self.overall_health().value,
            "phase50_score": self.phase50_score(),
            "domain_health": self.domain_health_map(),
            "top_risks": [s.phase_id for s in self.top_risks(3)],
            "strong_correlations": len(self.strong_correlations()),
        }

    def to_dict(self) -> dict:
        return {
            **self.summary(),
            "domains": {k: da.to_dict() for k, da in self.domain_aggregates.items()},
            "correlations": [c.to_dict() for c in self.correlations],
            "signals": {
                pid: {
                    "score": s.score,
                    "normalised": s.normalised,
                    "health": s.health.value,
                    "domain": s.domain.value,
                    "weight": s.weight,
                }
                for pid, s in self.signals.items()
            },
        }


# ---------------------------------------------------------------------------
# Phase domain mapping (used internally by the engine)
# ---------------------------------------------------------------------------

_PHASE_DOMAIN_MAP: Dict[str, PlatformDomain] = {
    "phase30": PlatformDomain.SECURITY,
    "phase31": PlatformDomain.COMPLIANCE,
    "phase32": PlatformDomain.ENGINEERING,
    "phase33": PlatformDomain.ENGINEERING,
    "phase34": PlatformDomain.RESILIENCE,
    "phase35": PlatformDomain.ENGINEERING,
    "phase36": PlatformDomain.SECURITY,
    "phase37": PlatformDomain.SECURITY,
    "phase38": PlatformDomain.INTELLIGENCE,
    "phase39": PlatformDomain.INTELLIGENCE,
    "phase40": PlatformDomain.SECURITY,
    "phase41": PlatformDomain.RESILIENCE,
    "phase42": PlatformDomain.COMPLIANCE,
    "phase43": PlatformDomain.SECURITY,
    "phase44": PlatformDomain.RESILIENCE,
    "phase45": PlatformDomain.ENGINEERING,
    "phase46": PlatformDomain.COMPLIANCE,
    "phase47": PlatformDomain.INTELLIGENCE,
    "phase48": PlatformDomain.INTELLIGENCE,
    "phase49": PlatformDomain.GOVERNANCE,
}

_PHASE_LABELS: Dict[str, str] = {
    "phase30": "Security Enforcement",
    "phase31": "GitOps Compliance Gate",
    "phase32": "Adaptive Security Controls",
    "phase33": "Cost Optimization Guardrails",
    "phase34": "Resilience & Chaos Testing",
    "phase35": "Forensic Readiness",
    "phase36": "Zero-Trust Policy Enforcement",
    "phase37": "Response Automation",
    "phase38": "Behavioral Analytics",
    "phase39": "Autonomous Optimizer",
    "phase40": "Predictive Threat Intelligence",
    "phase41": "Intelligent Incident Response",
    "phase42": "Advanced Compliance Automation",
    "phase43": "Advanced Threat Hunting",
    "phase44": "Platform Orchestration",
    "phase45": "Continuous Deployment Engine",
    "phase46": "Compliance Audit & Posture",
    "phase47": "Risk Quantification & Scoring",
    "phase48": "Security Intelligence Dashboard",
    "phase49": "Policy Enforcement & Governance",
}


# ---------------------------------------------------------------------------
# Core engine
# ---------------------------------------------------------------------------


class PlatformConvergenceEngine:
    """
    Phase 50 — Unified Security Orchestration & Platform Convergence.

    Milestone phase: ties together all Phase 30-49 signals into a single
    unified control plane with:
      - Weighted composite platform health index (0-100)
      - Per-domain aggregation across 6 PlatformDomains
      - Cross-phase correlation analysis
      - Top-risk identification
      - Tier-filtered convergence reports
      - Gate contribution: phase50_score() → 0-25 pts

    Workflow:
      1. ingest_phase_scores() — supply per-phase 0-25 telemetry
      2. converge()            — run convergence cycle → ConvergenceSnapshot
      3. latest_snapshot()     — retrieve last snapshot
      4. generate_report()     — executive / domain / full report
      5. persist_state()       — save artefact to artifacts/phase50/
    """

    # Domain weights for composite index
    DOMAIN_WEIGHTS: Dict[str, float] = {
        PlatformDomain.SECURITY.value:     1.5,
        PlatformDomain.COMPLIANCE.value:   1.3,
        PlatformDomain.GOVERNANCE.value:   1.2,
        PlatformDomain.RESILIENCE.value:   1.1,
        PlatformDomain.INTELLIGENCE.value: 1.0,
        PlatformDomain.ENGINEERING.value:  0.9,
    }

    def __init__(self) -> None:
        self._phase_scores: Dict[str, float] = {}
        self._snapshots: List[ConvergenceSnapshot] = []

    # ---- Telemetry ingestion -----------------------------------------------

    def ingest_phase_scores(self, scores: Dict[str, float]) -> None:
        """Accept per-phase 0-25 scores from upstream phase engines."""
        for phase, score in scores.items():
            self._phase_scores[phase] = max(0.0, min(25.0, float(score)))

    def set_phase_score(self, phase_id: str, score: float) -> None:
        self._phase_scores[phase_id] = max(0.0, min(25.0, float(score)))

    def phase_scores(self) -> Dict[str, float]:
        return dict(self._phase_scores)

    def phases_ingested(self) -> int:
        return len(self._phase_scores)

    # ---- Convergence cycle ------------------------------------------------

    def converge(self) -> ConvergenceSnapshot:
        """
        Run a convergence cycle:
          1. Build PhaseSignal objects for all ingested phases
          2. Group into DomainAggregates
          3. Compute cross-phase correlations
          4. Return ConvergenceSnapshot
        """
        # Build signals
        signals: Dict[str, PhaseSignal] = {}
        for phase_id, score in self._phase_scores.items():
            domain = _PHASE_DOMAIN_MAP.get(phase_id, PlatformDomain.ENGINEERING)
            label  = _PHASE_LABELS.get(phase_id, phase_id)
            signals[phase_id] = PhaseSignal(
                phase_id=phase_id,
                score=score,
                domain=domain,
                label=label,
            )

        # Group into domain aggregates
        domain_buckets: Dict[str, List[PhaseSignal]] = {d.value: [] for d in PlatformDomain}
        for sig in signals.values():
            domain_buckets[sig.domain.value].append(sig)

        domain_aggregates: Dict[str, DomainAggregate] = {}
        for domain_val, phase_sigs in domain_buckets.items():
            if phase_sigs:
                domain_aggregates[domain_val] = DomainAggregate(
                    domain=PlatformDomain(domain_val),
                    phase_signals=phase_sigs,
                    weight=self.DOMAIN_WEIGHTS.get(domain_val, 1.0),
                )

        # Compute pairwise correlations (simplified: sign-based coefficient)
        correlations = self._compute_correlations(signals)

        snapshot = ConvergenceSnapshot(
            signals=signals,
            domain_aggregates=domain_aggregates,
            correlations=correlations,
        )
        self._snapshots.append(snapshot)
        return snapshot

    def _compute_correlations(
        self, signals: Dict[str, PhaseSignal]
    ) -> List[CrossPhaseCorrelation]:
        """
        Compute pairwise cross-phase correlations.
        Uses a lightweight score-proximity coefficient:
          coefficient = 1 - |score_a - score_b| / 25.0
        Ranges from 0.0 (max divergence) to 1.0 (identical scores).
        Only pairs within the same domain are correlated.
        """
        correlations: List[CrossPhaseCorrelation] = []
        domain_groups: Dict[str, List[str]] = {}
        for pid, sig in signals.items():
            d = sig.domain.value
            domain_groups.setdefault(d, []).append(pid)

        for domain_phases in domain_groups.values():
            if len(domain_phases) < 2:
                continue
            sorted_phases = sorted(domain_phases)
            for i, pa in enumerate(sorted_phases):
                for pb in sorted_phases[i + 1:]:
                    score_a = signals[pa].score
                    score_b = signals[pb].score
                    coeff = round(1.0 - abs(score_a - score_b) / 25.0, 4)
                    correlations.append(CrossPhaseCorrelation(
                        phase_a=pa, phase_b=pb, coefficient=coeff
                    ))
        return correlations

    # ---- Query API --------------------------------------------------------

    def latest_snapshot(self) -> Optional[ConvergenceSnapshot]:
        return self._snapshots[-1] if self._snapshots else None

    def convergence_cycles(self) -> int:
        return len(self._snapshots)

    def composite_index(self) -> float:
        snap = self.latest_snapshot()
        return snap.composite_index() if snap else 0.0

    def phase50_score(self) -> int:
        snap = self.latest_snapshot()
        return snap.phase50_score() if snap else 0

    def overall_health(self) -> Optional[ConvergenceHealth]:
        snap = self.latest_snapshot()
        return snap.overall_health() if snap else None

    def top_risks(self, n: int = 5) -> List[PhaseSignal]:
        snap = self.latest_snapshot()
        return snap.top_risks(n) if snap else []

    # ---- Reporting --------------------------------------------------------

    def generate_report(self, view: str = "full") -> dict:
        """
        Generate convergence report.
        view options: 'executive' | 'domain' | 'full'
        """
        snap = self.latest_snapshot()
        if not snap:
            return {"error": "No convergence cycle has been run yet."}

        if view == "executive":
            return {
                "view": "executive",
                "snapshot_id": snap.snapshot_id,
                "generated_at": snap.created_at.isoformat(),
                "composite_index": snap.composite_index(),
                "overall_health": snap.overall_health().value,
                "phase50_score": snap.phase50_score(),
                "top_risks": [{"phase_id": s.phase_id, "label": s.label, "score": s.score}
                              for s in snap.top_risks(5)],
                "domain_health": snap.domain_health_map(),
            }
        if view == "domain":
            return {
                "view": "domain",
                "snapshot_id": snap.snapshot_id,
                "generated_at": snap.created_at.isoformat(),
                "composite_index": snap.composite_index(),
                "domains": {k: da.to_dict() for k, da in snap.domain_aggregates.items()},
            }
        # full
        return {
            "view": "full",
            **snap.to_dict(),
            "convergence_cycles": self.convergence_cycles(),
        }

    def summary(self) -> dict:
        snap = self.latest_snapshot()
        if not snap:
            return {
                "status": "no_convergence_cycle",
                "phases_ingested": self.phases_ingested(),
                "phase50_score": 0,
            }
        return {
            "status": "ok",
            "convergence_cycles": self.convergence_cycles(),
            "phases_ingested": self.phases_ingested(),
            "composite_index": snap.composite_index(),
            "overall_health": snap.overall_health().value,
            "phase50_score": snap.phase50_score(),
            "domains_active": len(snap.domain_aggregates),
            "top_risks": [s.phase_id for s in snap.top_risks(3)],
            "strong_correlations": len(snap.strong_correlations()),
            "domain_health": snap.domain_health_map(),
        }

    def persist_state(
        self, output_path: str = "artifacts/phase50/convergence-state.json"
    ) -> str:
        import os
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        state = {
            "phase": 50,
            "engine": "PlatformConvergenceEngine",
            "exported_at": datetime.utcnow().isoformat(),
            "summary": self.summary(),
            "snapshots": [s.to_dict() for s in self._snapshots],
        }
        with open(output_path, "w") as f:
            json.dump(state, f, indent=2)
        return output_path
