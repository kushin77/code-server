"""
security_posture_scoring.py — Phase 57: Security Posture Scoring & Risk Benchmarking
Aggregates gate scores from Phase 52-56 engines into a unified Security Posture
Index (SPI), maps scores against CIS/NIST benchmark thresholds, tracks posture
trend over time, and produces executive-level risk ratings.
"""
from __future__ import annotations

import statistics
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class PostureRating(Enum):
    EXEMPLARY   = "exemplary"    # SPI ≥ 90
    STRONG      = "strong"       # SPI ≥ 75
    ADEQUATE    = "adequate"     # SPI ≥ 60
    WEAK        = "weak"         # SPI ≥ 40
    CRITICAL    = "critical"     # SPI < 40


class BenchmarkFramework(Enum):
    CIS_L1   = "cis_level_1"
    CIS_L2   = "cis_level_2"
    NIST_CSF = "nist_csf"
    ISO27001 = "iso_27001"


class TrendDirection(Enum):
    IMPROVING  = "improving"
    STABLE     = "stable"
    DEGRADING  = "degrading"


class RiskDomain(Enum):
    THREAT_RESPONSE    = "threat_response"     # Phase 52
    ANOMALY_DETECTION  = "anomaly_detection"   # Phase 53
    THREAT_INTEL       = "threat_intel"        # Phase 54
    ZERO_TRUST         = "zero_trust"          # Phase 55
    SUPPLY_CHAIN       = "supply_chain"        # Phase 56


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class GateScore:
    """A single gate score contribution from one Phase engine."""
    phase: str           # e.g. "phase52"
    domain: RiskDomain
    score: float         # 0-25
    weight: float = 1.0
    recorded_at: datetime = field(default_factory=datetime.utcnow)
    metadata: Dict = field(default_factory=dict)

    @property
    def normalised(self) -> float:
        """Normalise 0-25 to 0-100."""
        return round((self.score / 25.0) * 100.0, 2)

    @property
    def weighted_score(self) -> float:
        return round(self.score * self.weight, 4)


@dataclass
class BenchmarkResult:
    """Comparison of SPI against a specific framework's threshold."""
    framework: BenchmarkFramework
    required_spi: float    # minimum SPI to pass
    actual_spi: float
    passed: bool
    gap: float             # actual - required (negative = below threshold)

    @property
    def compliance_pct(self) -> float:
        if self.required_spi == 0:
            return 100.0
        return min(round((self.actual_spi / self.required_spi) * 100.0, 2), 100.0)


@dataclass
class PostureSnapshot:
    """Point-in-time security posture assessment."""
    snapshot_id: str
    spi: float                          # Security Posture Index 0-100
    rating: PostureRating
    gate_scores: List[GateScore]
    benchmark_results: List[BenchmarkResult]
    phase57_score: float                # 0-25 gate contribution
    generated_at: datetime = field(default_factory=datetime.utcnow)

    @property
    def domain_scores(self) -> Dict[str, float]:
        result: Dict[str, float] = {}
        for gs in self.gate_scores:
            result[gs.domain.value] = round(gs.normalised, 2)
        return result

    @property
    def weakest_domain(self) -> Optional[str]:
        if not self.gate_scores:
            return None
        return min(self.gate_scores, key=lambda g: g.score).domain.value

    @property
    def frameworks_passed(self) -> int:
        return sum(1 for b in self.benchmark_results if b.passed)


# ---------------------------------------------------------------------------
# Benchmark thresholds (SPI 0-100)
# ---------------------------------------------------------------------------

_BENCHMARK_THRESHOLDS: Dict[BenchmarkFramework, float] = {
    BenchmarkFramework.CIS_L1:   60.0,
    BenchmarkFramework.CIS_L2:   75.0,
    BenchmarkFramework.NIST_CSF: 70.0,
    BenchmarkFramework.ISO27001: 65.0,
}


# ---------------------------------------------------------------------------
# Security Posture Scoring Engine
# ---------------------------------------------------------------------------


def _classify_rating(spi: float) -> PostureRating:
    if spi >= 90:
        return PostureRating.EXEMPLARY
    if spi >= 75:
        return PostureRating.STRONG
    if spi >= 60:
        return PostureRating.ADEQUATE
    if spi >= 40:
        return PostureRating.WEAK
    return PostureRating.CRITICAL


class SecurityPostureScoringEngine:
    """
    Phase 57 — Security Posture Scoring & Risk Benchmarking.

    Collects GateScores from Phase 52-56 engines, computes a weighted
    Security Posture Index (SPI 0-100), benchmarks against CIS/NIST,
    and tracks posture trend over time.
    Produces phase57_score() gate contribution (0-25).
    """

    # Default domain weights — THREAT_RESPONSE and ZERO_TRUST weighted higher
    _DEFAULT_WEIGHTS: Dict[RiskDomain, float] = {
        RiskDomain.THREAT_RESPONSE:   1.3,
        RiskDomain.ANOMALY_DETECTION: 1.1,
        RiskDomain.THREAT_INTEL:      1.0,
        RiskDomain.ZERO_TRUST:        1.2,
        RiskDomain.SUPPLY_CHAIN:      1.0,
    }

    def __init__(
        self,
        frameworks: Optional[List[BenchmarkFramework]] = None,
        custom_weights: Optional[Dict[RiskDomain, float]] = None,
    ) -> None:
        self.frameworks = frameworks or list(BenchmarkFramework)
        self.weights = custom_weights or dict(self._DEFAULT_WEIGHTS)
        self._gate_scores: List[GateScore] = []
        self._history: List[PostureSnapshot] = []

    # --- Gate score ingestion ---

    def record_score(self, gate: GateScore) -> None:
        """Record a single gate score."""
        self._gate_scores.append(gate)

    def record_scores(self, gates: List[GateScore]) -> None:
        """Record multiple gate scores at once."""
        for g in gates:
            self._gate_scores.append(g)

    def clear_scores(self) -> None:
        """Clear current gate scores (start fresh cycle)."""
        self._gate_scores.clear()

    # --- SPI computation ---

    def compute_spi(self, gate_scores: Optional[List[GateScore]] = None) -> float:
        """
        Weighted average of gate scores, normalised to 0-100.
        Returns 0.0 if no scores are present.
        """
        scores = gate_scores if gate_scores is not None else self._gate_scores
        if not scores:
            return 0.0
        total_weight = sum(self.weights.get(g.domain, 1.0) for g in scores)
        weighted_sum = sum(
            g.score * self.weights.get(g.domain, 1.0) for g in scores
        )
        raw = weighted_sum / total_weight   # 0-25 range
        return round((raw / 25.0) * 100.0, 2)

    # --- Benchmarking ---

    def benchmark(self, spi: float) -> List[BenchmarkResult]:
        results: List[BenchmarkResult] = []
        for fw in self.frameworks:
            threshold = _BENCHMARK_THRESHOLDS[fw]
            results.append(BenchmarkResult(
                framework=fw,
                required_spi=threshold,
                actual_spi=spi,
                passed=spi >= threshold,
                gap=round(spi - threshold, 2),
            ))
        return results

    # --- Snapshot ---

    def snapshot(self) -> PostureSnapshot:
        """Compute SPI, benchmark, produce and store a snapshot."""
        scores = list(self._gate_scores)
        spi = self.compute_spi(scores)
        rating = _classify_rating(spi)
        benchmarks = self.benchmark(spi)
        p57 = self.phase57_score(spi)
        snap = PostureSnapshot(
            snapshot_id=f"snap-{uuid.uuid4().hex[:8]}",
            spi=spi,
            rating=rating,
            gate_scores=scores,
            benchmark_results=benchmarks,
            phase57_score=p57,
        )
        self._history.append(snap)
        return snap

    # --- Trend analysis ---

    def trend(self, window: int = 5) -> TrendDirection:
        """
        Compute trend over the last `window` snapshots.
        Returns STABLE if fewer than 2 snapshots or no meaningful delta.
        """
        recent = [s.spi for s in self._history[-window:]]
        if len(recent) < 2:
            return TrendDirection.STABLE
        deltas = [recent[i] - recent[i - 1] for i in range(1, len(recent))]
        avg = sum(deltas) / len(deltas)
        if avg >= 1.0:
            return TrendDirection.IMPROVING
        if avg <= -1.0:
            return TrendDirection.DEGRADING
        return TrendDirection.STABLE

    # --- Scoring ---

    def phase57_score(self, spi: Optional[float] = None) -> float:
        """
        Gate score 0-25 = SPI / 4  (SPI 100 → 25, SPI 0 → 0).
        If spi is None, recomputes from current gate scores.
        """
        if spi is None:
            spi = self.compute_spi()
        return round(spi / 4.0, 2)

    # --- Summary and report ---

    def summary(self) -> Dict:
        spi = self.compute_spi()
        rating = _classify_rating(spi)
        benchmarks = self.benchmark(spi)
        return {
            "spi": spi,
            "rating": rating.value,
            "phase57_score": self.phase57_score(spi),
            "gate_count": len(self._gate_scores),
            "snapshot_count": len(self._history),
            "trend": self.trend().value,
            "frameworks_passed": sum(1 for b in benchmarks if b.passed),
            "total_frameworks": len(benchmarks),
        }

    def generate_report(self, snap: PostureSnapshot) -> Dict:
        return {
            "snapshot_id": snap.snapshot_id,
            "spi": snap.spi,
            "rating": snap.rating.value,
            "phase57_score": snap.phase57_score,
            "weakest_domain": snap.weakest_domain,
            "domain_scores": snap.domain_scores,
            "frameworks_passed": snap.frameworks_passed,
            "total_frameworks": len(snap.benchmark_results),
            "benchmark_results": [
                {
                    "framework": b.framework.value,
                    "required_spi": b.required_spi,
                    "actual_spi": b.actual_spi,
                    "passed": b.passed,
                    "gap": b.gap,
                }
                for b in snap.benchmark_results
            ],
        }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_gate(
    phase: str,
    domain: RiskDomain,
    score: float,
    weight: float = 1.0,
) -> GateScore:
    return GateScore(phase=phase, domain=domain, score=score, weight=weight)


def posture_score(engine: SecurityPostureScoringEngine) -> float:
    """Return phase57_score (0-25)."""
    return engine.phase57_score()
