"""
behavioral_anomaly_detection.py — Phase 53: Behavioral Anomaly Detection Engine
Monitors rolling phase-score trends across the Phase 30-52 stack, detects
statistical drift, outlier events, and classifies anomaly severity for
downstream alerting and response orchestration.
"""
from __future__ import annotations

import math
import statistics
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class AnomalySeverity(Enum):
    CRITICAL = "critical"   # z-score ≥ 3.0
    HIGH     = "high"       # z-score ≥ 2.0
    MEDIUM   = "medium"     # z-score ≥ 1.5
    LOW      = "low"        # z-score < 1.5 (flagged as mild drift)


class DriftDirection(Enum):
    DEGRADING  = "degrading"   # score trending down
    IMPROVING  = "improving"   # score trending up
    STABLE     = "stable"      # no meaningful trend


class DetectionMode(Enum):
    ZSCORE     = "zscore"      # statistical z-score outlier
    THRESHOLD  = "threshold"   # score crosses hard limit
    TREND      = "trend"       # sustained directional drift
    COMPOSITE  = "composite"   # combined signal


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class ScoreObservation:
    """Single timestamped phase score sample."""
    obs_id: str
    phase_source: str
    score: float           # 0-25 scale
    observed_at: datetime = field(default_factory=datetime.utcnow)
    metadata: Dict = field(default_factory=dict)


@dataclass
class AnomalyEvent:
    """Detected anomaly with evidence."""
    event_id: str
    phase_source: str
    score: float
    baseline_mean: float
    baseline_std: float
    z_score: float
    severity: AnomalySeverity
    direction: DriftDirection
    mode: DetectionMode
    description: str = ""
    detected_at: datetime = field(default_factory=datetime.utcnow)

    @property
    def phase53_contribution(self) -> float:
        """Per-event anomaly score contribution (higher = more anomalous, 0-25)."""
        return min(round(abs(self.z_score) * 8.33, 2), 25.0)


@dataclass
class PhaseBaseline:
    """Running baseline statistics for a single phase signal."""
    phase_source: str
    observations: List[float] = field(default_factory=list)
    window_size: int = 20   # rolling window length

    def add(self, score: float) -> None:
        self.observations.append(score)
        if len(self.observations) > self.window_size:
            self.observations = self.observations[-self.window_size:]

    @property
    def mean(self) -> float:
        if not self.observations:
            return 0.0
        return statistics.mean(self.observations)

    @property
    def std(self) -> float:
        if len(self.observations) < 2:
            return 0.0
        return statistics.stdev(self.observations)

    def z_score(self, value: float) -> float:
        if self.std == 0:
            return 0.0
        return (value - self.mean) / self.std

    @property
    def trend(self) -> DriftDirection:
        """Simple linear trend over last 5 observations."""
        obs = self.observations[-5:]
        if len(obs) < 2:
            return DriftDirection.STABLE
        deltas = [obs[i] - obs[i - 1] for i in range(1, len(obs))]
        avg_delta = sum(deltas) / len(deltas)
        if avg_delta <= -0.5:
            return DriftDirection.DEGRADING
        if avg_delta >= 0.5:
            return DriftDirection.IMPROVING
        return DriftDirection.STABLE

    def is_ready(self) -> bool:
        """Baseline is reliable when it has at least 3 observations."""
        return len(self.observations) >= 3


# ---------------------------------------------------------------------------
# Anomaly Detector
# ---------------------------------------------------------------------------


def _classify_severity(z: float) -> AnomalySeverity:
    az = abs(z)
    if az >= 3.0:
        return AnomalySeverity.CRITICAL
    if az >= 2.0:
        return AnomalySeverity.HIGH
    if az >= 1.5:
        return AnomalySeverity.MEDIUM
    return AnomalySeverity.LOW


class BehavioralAnomalyDetector:
    """
    Phase 53 — Behavioral Anomaly Detection Engine.

    Maintains per-phase baselines (rolling window statistics) and detects
    score anomalies using z-score, hard threshold, and trend analysis.
    Produces a phase53_score() gate contribution (0-25).
    """

    def __init__(
        self,
        window_size: int = 20,
        zscore_threshold: float = 1.5,
        hard_threshold_low: float = 5.0,
        hard_threshold_high: float = 23.0,
    ) -> None:
        self.window_size = window_size
        self.zscore_threshold = zscore_threshold
        self.hard_threshold_low = hard_threshold_low
        self.hard_threshold_high = hard_threshold_high
        self.baselines: Dict[str, PhaseBaseline] = {}
        self.anomaly_log: List[AnomalyEvent] = []
        self.observation_count: int = 0

    # --- Observation ingestion ---

    def observe(self, phase_source: str, score: float) -> Optional[AnomalyEvent]:
        """
        Ingest a score observation. Updates baseline and returns an AnomalyEvent
        if an anomaly is detected, else None.
        """
        self.observation_count += 1
        if phase_source not in self.baselines:
            self.baselines[phase_source] = PhaseBaseline(
                phase_source=phase_source,
                window_size=self.window_size,
            )
        baseline = self.baselines[phase_source]

        # Detect against current baseline BEFORE updating it (preserves baseline integrity)
        result: Optional[AnomalyEvent] = None
        if baseline.is_ready():
            result = self._detect(baseline, score)

        baseline.add(score)
        return result

    def observe_batch(
        self, observations: List[Tuple[str, float]]
    ) -> List[AnomalyEvent]:
        """Ingest multiple (phase_source, score) pairs; return detected anomalies."""
        events: List[AnomalyEvent] = []
        for phase_source, score in observations:
            evt = self.observe(phase_source, score)
            if evt is not None:
                events.append(evt)
        return events

    # --- Detection logic ---

    def _detect(self, baseline: PhaseBaseline, score: float) -> Optional[AnomalyEvent]:
        """Run all detectors; return highest-severity event or None."""
        candidates: List[AnomalyEvent] = []

        # 1. Z-score
        z = baseline.z_score(score)
        if abs(z) >= self.zscore_threshold:
            evt = self._make_event(
                baseline, score, z, DetectionMode.ZSCORE,
                f"Z-score {z:.2f} exceeds threshold {self.zscore_threshold}",
            )
            candidates.append(evt)

        # 2. Hard threshold
        if score <= self.hard_threshold_low or score >= self.hard_threshold_high:
            z2 = baseline.z_score(score)
            evt = self._make_event(
                baseline, score, z2, DetectionMode.THRESHOLD,
                f"Score {score:.2f} outside safe band [{self.hard_threshold_low}, "
                f"{self.hard_threshold_high}]",
            )
            candidates.append(evt)

        # 3. Trend (only on DEGRADING)
        if baseline.trend == DriftDirection.DEGRADING:
            z3 = baseline.z_score(score)
            evt = self._make_event(
                baseline, score, z3, DetectionMode.TREND,
                "Sustained degrading trend detected over last 5 observations",
            )
            candidates.append(evt)

        if not candidates:
            return None

        # Pick most severe
        severity_order = list(AnomalySeverity)
        best = min(candidates, key=lambda e: severity_order.index(e.severity))
        # If multiple same severity, prefer COMPOSITE
        if len(candidates) > 1:
            best.mode = DetectionMode.COMPOSITE
        self.anomaly_log.append(best)
        return best

    def _make_event(
        self,
        baseline: PhaseBaseline,
        score: float,
        z: float,
        mode: DetectionMode,
        description: str,
    ) -> AnomalyEvent:
        direction = DriftDirection.DEGRADING if score < baseline.mean else DriftDirection.IMPROVING
        if abs(score - baseline.mean) < 0.1:
            direction = DriftDirection.STABLE
        return AnomalyEvent(
            event_id=f"anom-{uuid.uuid4().hex[:8]}",
            phase_source=baseline.phase_source,
            score=score,
            baseline_mean=round(baseline.mean, 4),
            baseline_std=round(baseline.std, 4),
            z_score=round(z, 4),
            severity=_classify_severity(z),
            direction=direction,
            mode=mode,
            description=description,
        )

    # --- Scoring and reporting ---

    def phase53_score(self) -> float:
        """
        Gate score (0-25). Score = 25 × (1 - anomaly_rate), where anomaly_rate
        is the fraction of anomalies that are CRITICAL or HIGH severity.
        With no anomalies → 25.0; fully critical stream → 0.0.
        """
        if self.observation_count == 0:
            return 0.0
        critical_high = sum(
            1 for e in self.anomaly_log
            if e.severity in (AnomalySeverity.CRITICAL, AnomalySeverity.HIGH)
        )
        anomaly_rate = critical_high / self.observation_count
        return round((1.0 - anomaly_rate) * 25.0, 2)

    def summary(self) -> Dict:
        sev_counts: Dict[str, int] = {s.value: 0 for s in AnomalySeverity}
        for evt in self.anomaly_log:
            sev_counts[evt.severity.value] += 1
        return {
            "total_observations": self.observation_count,
            "active_baselines": len(self.baselines),
            "total_anomalies": len(self.anomaly_log),
            "severity_breakdown": sev_counts,
            "phase53_score": self.phase53_score(),
        }

    def generate_report(self, phase_source: Optional[str] = None) -> Dict:
        events = (
            [e for e in self.anomaly_log if e.phase_source == phase_source]
            if phase_source
            else self.anomaly_log
        )
        baseline = self.baselines.get(phase_source) if phase_source else None
        return {
            "phase_source": phase_source or "all",
            "anomaly_count": len(events),
            "baseline_mean": round(baseline.mean, 4) if baseline else None,
            "baseline_std": round(baseline.std, 4) if baseline else None,
            "events": [
                {
                    "event_id": e.event_id,
                    "score": e.score,
                    "z_score": e.z_score,
                    "severity": e.severity.value,
                    "direction": e.direction.value,
                    "mode": e.mode.value,
                    "description": e.description,
                }
                for e in events
            ],
        }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_observation(phase_source: str, score: float) -> Tuple[str, float]:
    return (phase_source, score)


def anomaly_score(detector: BehavioralAnomalyDetector) -> float:
    """Return phase53_score (0-25)."""
    return detector.phase53_score()
