#!/usr/bin/env python3
"""
@file behavioral_analytics.py
@description ML-driven behavioral analytics engine for Phase 38

Detects anomalous user and system behavior patterns using unsupervised learning.
Integrates with Phase 30 threat detection, Phase 32 incidents, and Phase 35 forensics.

@since 2026-05-01
@phase 38
"""

import json
import logging
from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import List, Dict, Any, Optional, Tuple, Set
from datetime import datetime, timedelta
from collections import defaultdict
import hashlib

try:
    import numpy as np
    from sklearn.ensemble import IsolationForest
    from sklearn.preprocessing import StandardScaler
    _ML_AVAILABLE = True
except ImportError:
    _ML_AVAILABLE = False
    np = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)


class BehaviorAnomaloType(Enum):
    """Behavioral anomaly classifications"""
    PRIVILEGE_ESCALATION = "privilege_escalation"
    LATERAL_MOVEMENT = "lateral_movement"
    DATA_EXFILTRATION = "data_exfiltration"
    RESOURCE_ABUSE = "resource_abuse"
    CONFIGURATION_TAMPERING = "configuration_tampering"
    CREDENTIAL_MISUSE = "credential_misuse"
    TIMING_ANOMALY = "timing_anomaly"
    PATTERN_DEVIATION = "pattern_deviation"


class AnomalySource(Enum):
    """Sources of anomaly detection"""
    ML_ISOLATION_FOREST = "ml_isolation_forest"
    STATISTICAL_DEVIATION = "statistical_deviation"
    BEHAVIORAL_BASELINE = "behavioral_baseline"
    PHASE30_THREAT_SCORE = "phase30_threat_score"
    PHASE32_INCIDENT = "phase32_incident"


@dataclass
class BehaviorMetric:
    """Single user/service behavior metric"""
    timestamp: str
    entity_id: str  # user, service, container
    entity_type: str  # "user", "service", "container"
    metric_type: str  # "api_calls", "file_access", "network_connections", etc.
    metric_value: float
    context: Dict[str, Any] = field(default_factory=dict)


@dataclass
class BaselineProfile:
    """Behavioral baseline for entity"""
    entity_id: str
    entity_type: str
    metric_type: str
    mean: float
    stddev: float
    p95: float
    p99: float
    sample_count: int
    last_updated: str


@dataclass
class BehavioralAnomaly:
    """Detected behavioral anomaly"""
    anomaly_id: str
    timestamp: str
    entity_id: str
    entity_type: str
    anomaly_type: BehaviorAnomaloType
    severity: int  # 1-5 (LOW to CRITICAL)
    confidence: float  # 0.0-1.0
    deviation_score: float  # How many stddevs away from baseline
    contributing_metrics: List[str]
    supporting_events: List[Dict[str, Any]]
    description: str
    phase30_correlation: Optional[str] = None  # threat_id from Phase 30
    phase32_correlation: Optional[str] = None  # incident_id from Phase 32
    recommended_actions: List[str] = field(default_factory=list)


@dataclass
class BehavioralProfile:
    """Comprehensive behavioral profile for entity"""
    entity_id: str
    entity_type: str
    baselines: Dict[str, BaselineProfile] = field(default_factory=dict)
    anomalies: List[BehavioralAnomaly] = field(default_factory=list)
    risk_score: float = 0.0
    last_analyzed: str = ""


class BehavioralAnalyticsEngine:
    """ML-driven behavioral analytics for anomaly detection"""

    def __init__(self, state_dir: str = "artifacts/phase38"):
        """Initialize behavioral analytics engine"""
        self.state_dir = state_dir
        self.profiles: Dict[str, BehavioralProfile] = {}
        self.baselines: Dict[str, Dict[str, BaselineProfile]] = defaultdict(dict)
        self.ml_models: Dict[str, Any] = {}
        self._ensure_state_dir()

    def _ensure_state_dir(self) -> None:
        """Ensure state directory exists"""
        import os
        os.makedirs(self.state_dir, exist_ok=True)

    def ingest_metrics(self, metrics: List[BehaviorMetric]) -> None:
        """Ingest behavior metrics for analysis"""
        for metric in metrics:
            entity_key = f"{metric.entity_type}:{metric.entity_id}"
            if entity_key not in self.profiles:
                self.profiles[entity_key] = BehavioralProfile(
                    entity_id=metric.entity_id,
                    entity_type=metric.entity_type
                )

    def build_baseline(
        self,
        entity_id: str,
        entity_type: str,
        metric_type: str,
        values: List[float],
        window_hours: int = 7 * 24
    ) -> BaselineProfile:
        """Build behavioral baseline from historical values"""
        if not values or len(values) < 10:
            # Insufficient data for reliable baseline
            return BaselineProfile(
                entity_id=entity_id,
                entity_type=entity_type,
                metric_type=metric_type,
                mean=0.0,
                stddev=0.0,
                p95=0.0,
                p99=0.0,
                sample_count=len(values),
                last_updated=datetime.utcnow().isoformat()
            )

        if not _ML_AVAILABLE or np is None:
            # Fallback: simple statistical calculations
            sorted_values = sorted(values)
            mean = sum(values) / len(values)
            variance = sum((v - mean) ** 2 for v in values) / len(values)
            stddev = variance ** 0.5
            p95_idx = int(len(sorted_values) * 0.95)
            p99_idx = int(len(sorted_values) * 0.99)
            
            return BaselineProfile(
                entity_id=entity_id,
                entity_type=entity_type,
                metric_type=metric_type,
                mean=float(mean),
                stddev=float(stddev),
                p95=float(sorted_values[min(p95_idx, len(sorted_values)-1)]),
                p99=float(sorted_values[min(p99_idx, len(sorted_values)-1)]),
                sample_count=len(values),
                last_updated=datetime.utcnow().isoformat()
            )

        # Use numpy for calculations
        arr = np.array(values)
        baseline = BaselineProfile(
            entity_id=entity_id,
            entity_type=entity_type,
            metric_type=metric_type,
            mean=float(arr.mean()),
            stddev=float(arr.std()),
            p95=float(np.percentile(arr, 95)),
            p99=float(np.percentile(arr, 99)),
            sample_count=len(values),
            last_updated=datetime.utcnow().isoformat()
        )
        
        return baseline

    def detect_anomalies_ml(
        self,
        entity_id: str,
        entity_type: str,
        metrics_data: List[Tuple[str, float]]
    ) -> List[BehavioralAnomaly]:
        """Detect anomalies using ML (Isolation Forest)"""
        anomalies = []

        if not _ML_AVAILABLE or np is None:
            # Fallback to statistical detection
            return self._detect_anomalies_statistical(
                entity_id, entity_type, metrics_data
            )

        try:
            # Prepare feature matrix for ML model
            features = np.array([v[1] for v in metrics_data]).reshape(-1, 1)
            
            if len(features) < 5:
                return anomalies

            # Apply Isolation Forest
            iso_forest = IsolationForest(
                contamination=0.1,
                random_state=42,
                n_estimators=100
            )
            predictions = iso_forest.fit_predict(features)
            anomaly_scores = iso_forest.score_samples(features)

            # Process anomalies
            for idx, (metric_name, value) in enumerate(metrics_data):
                if predictions[idx] == -1:  # Anomaly detected
                    confidence = min(1.0, abs(anomaly_scores[idx]) / 2.0)
                    
                    anomaly = BehavioralAnomaly(
                        anomaly_id=self._generate_anomaly_id(
                            entity_id, metric_name
                        ),
                        timestamp=datetime.utcnow().isoformat(),
                        entity_id=entity_id,
                        entity_type=entity_type,
                        anomaly_type=self._classify_anomaly_type(metric_name),
                        severity=self._calculate_severity(confidence),
                        confidence=confidence,
                        deviation_score=abs(anomaly_scores[idx]),
                        contributing_metrics=[metric_name],
                        supporting_events=[],
                        description=f"ML anomaly detected in {metric_name} "
                                  f"for {entity_type}:{entity_id} "
                                  f"(value={value:.2f})",
                        recommended_actions=self._recommend_actions(
                            metric_name, entity_type
                        )
                    )
                    anomalies.append(anomaly)

        except Exception as e:
            logger.error(f"ML anomaly detection failed: {e}")

        return anomalies

    def _detect_anomalies_statistical(
        self,
        entity_id: str,
        entity_type: str,
        metrics_data: List[Tuple[str, float]]
    ) -> List[BehavioralAnomaly]:
        """Fallback statistical anomaly detection"""
        anomalies = []
        entity_key = f"{entity_type}:{entity_id}"

        for metric_name, value in metrics_data:
            # Check if baseline exists for this metric
            if entity_key not in self.baselines:
                continue
            if metric_name not in self.baselines[entity_key]:
                continue

            baseline = self.baselines[entity_key][metric_name]
            if baseline.stddev == 0:
                continue

            # Calculate deviation in terms of standard deviations
            deviation = abs((value - baseline.mean) / baseline.stddev)

            if deviation > 3.0:  # 3-sigma rule
                confidence = min(1.0, (deviation - 3.0) / 3.0)
                
                anomaly = BehavioralAnomaly(
                    anomaly_id=self._generate_anomaly_id(
                        entity_id, metric_name
                    ),
                    timestamp=datetime.utcnow().isoformat(),
                    entity_id=entity_id,
                    entity_type=entity_type,
                    anomaly_type=self._classify_anomaly_type(metric_name),
                    severity=self._calculate_severity(confidence),
                    confidence=confidence,
                    deviation_score=deviation,
                    contributing_metrics=[metric_name],
                    supporting_events=[],
                    description=f"Statistical anomaly in {metric_name}: "
                              f"{value:.2f} (baseline: {baseline.mean:.2f}±"
                              f"{baseline.stddev:.2f})",
                    recommended_actions=self._recommend_actions(
                        metric_name, entity_type
                    )
                )
                anomalies.append(anomaly)

        return anomalies

    def _classify_anomaly_type(self, metric_name: str) -> BehaviorAnomaloType:
        """Classify anomaly type based on metric"""
        metric_lower = metric_name.lower()
        
        if "privilege" in metric_lower or "sudo" in metric_lower:
            return BehaviorAnomaloType.PRIVILEGE_ESCALATION
        elif "lateral" in metric_lower or "ssh" in metric_lower:
            return BehaviorAnomaloType.LATERAL_MOVEMENT
        elif "exfil" in metric_lower or "download" in metric_lower:
            return BehaviorAnomaloType.DATA_EXFILTRATION
        elif "cpu" in metric_lower or "memory" in metric_lower:
            return BehaviorAnomaloType.RESOURCE_ABUSE
        elif "config" in metric_lower or "syscall" in metric_lower:
            return BehaviorAnomaloType.CONFIGURATION_TAMPERING
        elif "credential" in metric_lower or "password" in metric_lower:
            return BehaviorAnomaloType.CREDENTIAL_MISUSE
        elif "timing" in metric_lower:
            return BehaviorAnomaloType.TIMING_ANOMALY
        else:
            return BehaviorAnomaloType.PATTERN_DEVIATION

    def _calculate_severity(self, confidence: float) -> int:
        """Convert confidence to severity (1-5)"""
        if confidence >= 0.9:
            return 5  # CRITICAL
        elif confidence >= 0.7:
            return 4  # HIGH
        elif confidence >= 0.5:
            return 3  # MEDIUM
        elif confidence >= 0.3:
            return 2  # LOW
        else:
            return 1  # INFO

    def _recommend_actions(
        self,
        metric_name: str,
        entity_type: str
    ) -> List[str]:
        """Generate recommended actions"""
        actions = []
        metric_lower = metric_name.lower()

        if entity_type == "user":
            if "privilege" in metric_lower:
                actions.append("AUDIT_SUDO_LOGS")
                actions.append("REVIEW_USER_PERMISSIONS")
            elif "credential" in metric_lower:
                actions.append("FORCE_PASSWORD_RESET")
                actions.append("REVOKE_TOKENS")
        elif entity_type == "service":
            if "resource_abuse" in metric_lower:
                actions.append("SCALE_SERVICE_UP")
                actions.append("REVIEW_WORKLOAD")
            elif "lateral" in metric_lower:
                actions.append("ISOLATE_SERVICE")
                actions.append("REVIEW_NETWORK_POLICIES")

        if not actions:
            actions.append("INVESTIGATE")
            actions.append("ALERT_SECURITY_TEAM")

        return actions

    def _generate_anomaly_id(self, entity_id: str, metric_name: str) -> str:
        """Generate unique anomaly ID"""
        content = f"{entity_id}:{metric_name}:{datetime.utcnow().isoformat()}"
        return f"anomaly_{hashlib.sha256(content.encode()).hexdigest()[:16]}"

    def behavioral_score(
        self,
        entity_id: str,
        entity_type: str
    ) -> float:
        """Calculate behavioral risk score (0-25 pts to compliance gate)"""
        entity_key = f"{entity_type}:{entity_id}"
        if entity_key not in self.profiles:
            return 0.0

        profile = self.profiles[entity_key]
        if not profile.anomalies:
            return 25.0  # Excellent: no anomalies detected

        # Penalize based on anomaly severity and count
        total_penalty = 0.0
        for anomaly in profile.anomalies[-10:]:  # Last 10 anomalies
            severity_weight = anomaly.severity / 5.0  # Normalize 1-5 to 0-1
            confidence_weight = anomaly.confidence
            total_penalty += severity_weight * confidence_weight

        # Cap penalty at 25 points
        score = max(0.0, 25.0 - total_penalty)
        return score

    def persist_state(self) -> None:
        """Persist profiles and baselines to storage"""
        import json
        import os

        profiles_file = os.path.join(self.state_dir, "profiles.json")
        baselines_file = os.path.join(self.state_dir, "baselines.json")

        try:
            # Serialize profiles
            profiles_data = {}
            for key, profile in self.profiles.items():
                profiles_data[key] = {
                    "entity_id": profile.entity_id,
                    "entity_type": profile.entity_type,
                    "anomalies": [asdict(a) for a in profile.anomalies],
                    "risk_score": profile.risk_score,
                    "last_analyzed": profile.last_analyzed
                }

            with open(profiles_file, "w") as f:
                json.dump(profiles_data, f, indent=2, default=str)

            # Serialize baselines
            baselines_data = {}
            for entity_key, metrics in self.baselines.items():
                baselines_data[entity_key] = {}
                for metric_key, baseline in metrics.items():
                    baselines_data[entity_key][metric_key] = asdict(baseline)

            with open(baselines_file, "w") as f:
                json.dump(baselines_data, f, indent=2, default=str)

        except Exception as e:
            logger.error(f"Failed to persist state: {e}")

    def load_state(self) -> None:
        """Load profiles and baselines from storage"""
        import json
        import os

        profiles_file = os.path.join(self.state_dir, "profiles.json")
        baselines_file = os.path.join(self.state_dir, "baselines.json")

        try:
            if os.path.exists(profiles_file):
                with open(profiles_file) as f:
                    data = json.load(f)
                    # Note: simplified loading; full deserialization would need
                    # to reconstruct dataclasses

        except Exception as e:
            logger.error(f"Failed to load state: {e}")

    def summary(self) -> Dict[str, Any]:
        """Generate analytics summary"""
        total_entities = len(self.profiles)
        total_anomalies = sum(
            len(p.anomalies) for p in self.profiles.values()
        )
        avg_confidence = 0.0

        if total_anomalies > 0:
            avg_confidence = sum(
                a.confidence
                for p in self.profiles.values()
                for a in p.anomalies
            ) / total_anomalies

        critical_count = sum(
            1 for p in self.profiles.values()
            for a in p.anomalies
            if a.severity == 5
        )

        return {
            "timestamp": datetime.utcnow().isoformat(),
            "total_entities_monitored": total_entities,
            "total_anomalies_detected": total_anomalies,
            "critical_anomalies": critical_count,
            "average_confidence": round(avg_confidence, 3),
            "behavioral_coverage": min(1.0, total_entities / 100.0),
            "phase38_behavioral_score": round(
                sum(
                    self.behavioral_score(p.entity_id, p.entity_type)
                    for p in self.profiles.values()
                ) / max(1, total_entities),
                1
            )
        }
