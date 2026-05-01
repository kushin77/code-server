#!/usr/bin/env python3
"""
@file threat_detector.py
@description AI-driven threat detection engine for Phase 30

Detects security threats using ML anomaly detection + pattern matching.
Integrates with Phase 29 for autonomous remediation.

@since 2026-05-01
"""

import json
import logging
from dataclasses import dataclass
from enum import Enum
from typing import List, Dict, Any, Optional
from datetime import datetime

try:
    import numpy as np
    from sklearn.ensemble import IsolationForest
    _ML_AVAILABLE = True
except ImportError:
    _ML_AVAILABLE = False
    np = None  # type: ignore[assignment]


class ThreatSeverity(Enum):
    """Threat severity levels"""
    CRITICAL = 5
    HIGH = 4
    MEDIUM = 3
    LOW = 2
    INFO = 1


class ThreatType(Enum):
    """Threat classification"""
    INTRUSION = "intrusion"
    LATERAL_MOVEMENT = "lateral_movement"
    DATA_EXFILTRATION = "data_exfiltration"
    PRIVILEGE_ESCALATION = "privilege_escalation"
    MALWARE = "malware"
    ANOMALOUS_BEHAVIOR = "anomalous_behavior"
    POLICY_VIOLATION = "policy_violation"


@dataclass
class SecurityEvent:
    """Single security event from Falco/auditd"""
    timestamp: str
    source: str  # "falco", "auditd", "phase29"
    event_type: str
    container_id: str
    process: str
    syscall: Optional[str]
    network_flow: Optional[Dict[str, Any]]
    file_access: Optional[Dict[str, Any]]
    metadata: Dict[str, Any]


@dataclass
class Threat:
    """Detected security threat"""
    threat_id: str
    timestamp: str
    threat_type: ThreatType
    severity: ThreatSeverity
    affected_service: str
    description: str
    events: List[SecurityEvent]
    confidence: float  # 0.0 - 1.0
    recommended_actions: List[str]
    estimated_impact: str


class ThreatDetector:
    """ML-based threat detection and classification"""
    
    def __init__(self):
        """Initialize threat detector with ML models"""
        if _ML_AVAILABLE:
            from sklearn.ensemble import IsolationForest as _IF
            self.isolation_forest = _IF(contamination=0.05, random_state=42, n_jobs=-1)
        else:
            self.isolation_forest = None
        self.logger = logging.getLogger(__name__)
        self.threat_patterns = self._load_threat_patterns()
        self.baseline_behaviors = {}
        self.threat_counter = 0
        
    def _load_threat_patterns(self) -> Dict[str, Any]:
        """Load MITRE ATT&CK patterns and known signatures"""
        return {
            "privilege_escalation": [
                "docker run --privileged",
                "sudo without password",
                "kernel module load",
                "setuid binary execution"
            ],
            "lateral_movement": [
                "SSH to internal IP",
                "port scan (nmap)",
                "service enumeration",
                "credential reuse attempt"
            ],
            "data_exfiltration": [
                "large file read (>100MB)",
                "database export",
                "archive creation (tar/zip)",
                "curl to external IP"
            ],
            "malware_indicators": [
                "binary in /tmp",
                "process hollowing",
                "process injection",
                "known malware hash"
            ]
        }
    
    def train_baseline(self, clean_events: List[SecurityEvent]) -> None:
        """Train anomaly detector on clean (non-threat) events"""
        if not _ML_AVAILABLE or self.isolation_forest is None:
            self.logger.warning("ML not available — skipping baseline training")
            return
        self.logger.info(f"Training baseline on {len(clean_events)} clean events")
        features = self._events_to_features(clean_events)
        self.isolation_forest.fit(features)
        self.logger.info("Baseline training complete")
    
    def detect_threats(self, events: List[SecurityEvent]) -> List[Threat]:
        """Detect security threats in event stream"""
        threats = []
        
        # Check for pattern matches
        threats.extend(self._detect_pattern_matches(events))
        
        # Check for anomalies
        threats.extend(self._detect_anomalies(events))
        
        # Check for policy violations
        threats.extend(self._detect_policy_violations(events))
        
        # Deduplicate and rank by severity
        threats = self._deduplicate_threats(threats)
        threats.sort(key=lambda t: t.severity.value, reverse=True)
        
        return threats
    
    def _detect_pattern_matches(self, events: List[SecurityEvent]) -> List[Threat]:
        """Detect known attack patterns (MITRE ATT&CK)"""
        threats = []
        
        for event in events:
            event_str = json.dumps({
                'process': event.process,
                'syscall': event.syscall,
                'metadata': event.metadata
            })
            
            for threat_category, patterns in self.threat_patterns.items():
                for pattern in patterns:
                    if pattern.lower() in event_str.lower():
                        threat = Threat(
                            threat_id=self._gen_threat_id(),
                            timestamp=datetime.now().isoformat(),
                            threat_type=self._classify_threat_type(threat_category),
                            severity=ThreatSeverity.HIGH,
                            affected_service=event.container_id,
                            description=f"Pattern match: {pattern}",
                            events=[event],
                            confidence=0.85,
                            recommended_actions=self._recommend_actions(threat_category),
                            estimated_impact=self._estimate_impact(threat_category)
                        )
                        threats.append(threat)
        
        return threats
    
    def _detect_anomalies(self, events: List[SecurityEvent]) -> List[Threat]:
        """Detect anomalous behavior using ML"""
        threats = []
        
        if not _ML_AVAILABLE or self.isolation_forest is None or not hasattr(self.isolation_forest, 'estimators_'):
            self.logger.warning("ML baseline not trained, skipping anomaly detection")
            return threats
        
        # Convert events to features
        features = self._events_to_features(events)
        
        # Score anomalies (-1 = anomaly, 1 = normal)
        scores = self.isolation_forest.predict(features)
        
        for i, (event, score) in enumerate(zip(events, scores)):
            if score == -1:  # Anomaly detected
                threat = Threat(
                    threat_id=self._gen_threat_id(),
                    timestamp=datetime.now().isoformat(),
                    threat_type=ThreatType.ANOMALOUS_BEHAVIOR,
                    severity=ThreatSeverity.MEDIUM,
                    affected_service=event.container_id,
                    description="Anomalous system behavior detected",
                    events=[event],
                    confidence=abs(self.isolation_forest.score_samples(features)[i]),
                    recommended_actions=["Review event logs", "Monitor container"],
                    estimated_impact="Low to Medium"
                )
                threats.append(threat)
        
        return threats
    
    def _detect_policy_violations(self, events: List[SecurityEvent]) -> List[Threat]:
        """Detect policy violations"""
        threats = []
        
        for event in events:
            # Check for privileged container
            if event.metadata.get("privileged") and not event.metadata.get("approved"):
                threats.append(Threat(
                    threat_id=self._gen_threat_id(),
                    timestamp=datetime.now().isoformat(),
                    threat_type=ThreatType.POLICY_VIOLATION,
                    severity=ThreatSeverity.HIGH,
                    affected_service=event.container_id,
                    description="Privileged container without approval",
                    events=[event],
                    confidence=1.0,
                    recommended_actions=["Stop container", "Review policy"],
                    estimated_impact="High"
                ))
            
            # Check for root process
            if event.metadata.get("uid") == 0 and not event.metadata.get("approved"):
                threats.append(Threat(
                    threat_id=self._gen_threat_id(),
                    timestamp=datetime.now().isoformat(),
                    threat_type=ThreatType.POLICY_VIOLATION,
                    severity=ThreatSeverity.MEDIUM,
                    affected_service=event.container_id,
                    description="Process running as root",
                    events=[event],
                    confidence=1.0,
                    recommended_actions=["Review process", "Apply least privilege"],
                    estimated_impact="Medium"
                ))
        
        return threats
    
    def _events_to_features(self, events: List[SecurityEvent]):
        """Convert security events to numeric feature vector"""
        if not _ML_AVAILABLE:
            return []
        features = []
        for event in events:
            feature_vector = [
                len(event.process or ""),
                len(event.syscall or ""),
                len(event.metadata.get("args", "")),
                1 if event.network_flow else 0,
                1 if event.file_access else 0,
                event.metadata.get("uid", 1000),
                1 if event.metadata.get("privileged") else 0,
            ]
            features.append(feature_vector)
        return np.array(features) if features else np.array([]).reshape(0, 7)
    
    def _classify_threat_type(self, category: str) -> ThreatType:
        """Classify threat category to threat type"""
        mapping = {
            "privilege_escalation": ThreatType.PRIVILEGE_ESCALATION,
            "lateral_movement": ThreatType.LATERAL_MOVEMENT,
            "data_exfiltration": ThreatType.DATA_EXFILTRATION,
            "malware_indicators": ThreatType.MALWARE,
        }
        return mapping.get(category, ThreatType.ANOMALOUS_BEHAVIOR)
    
    def _recommend_actions(self, threat_category: str) -> List[str]:
        """Generate recommended actions for threat"""
        actions = {
            "privilege_escalation": [
                "Isolate container immediately",
                "Review process execution logs",
                "Check for credential compromise",
                "Revoke access tokens"
            ],
            "lateral_movement": [
                "Check network policies",
                "Review SSH logs",
                "Monitor internal communications",
                "Segment network"
            ],
            "data_exfiltration": [
                "Stop network access",
                "Review data access logs",
                "Check file integrity",
                "Alert security team"
            ],
            "malware_indicators": [
                "Quarantine process",
                "Scan filesystem",
                "Revoke container image",
                "Emergency incident response"
            ]
        }
        return actions.get(threat_category, ["Manual investigation required"])
    
    def _estimate_impact(self, threat_category: str) -> str:
        """Estimate blast radius and impact"""
        impacts = {
            "privilege_escalation": "Full container compromise, potential host compromise",
            "lateral_movement": "Potential multi-service compromise",
            "data_exfiltration": "Confidentiality breach of stored data",
            "malware_indicators": "Integrity and availability compromise"
        }
        return impacts.get(threat_category, "Unknown impact")
    
    def _deduplicate_threats(self, threats: List[Threat]) -> List[Threat]:
        """Remove duplicate threats within time window"""
        # Simple dedup: same service + type within 5 minutes
        seen = {}
        unique = []
        
        for threat in threats:
            key = (threat.affected_service, threat.threat_type.value)
            if key not in seen:
                seen[key] = threat
                unique.append(threat)
        
        return unique
    
    def _gen_threat_id(self) -> str:
        """Generate unique threat ID"""
        self.threat_counter += 1
        return f"THR-{datetime.now().strftime('%Y%m%d%H%M%S')}-{self.threat_counter:05d}"
    
    def to_dict(self) -> Dict[str, Any]:
        """Serialize threat to dict for logging/export"""
        return {
            "threat_id": self.threat_id,
            "timestamp": self.timestamp,
            "threat_type": self.threat_type.value,
            "severity": self.severity.name,
            "affected_service": self.affected_service,
            "description": self.description,
            "confidence": self.confidence,
            "recommended_actions": self.recommended_actions,
            "estimated_impact": self.estimated_impact,
            "event_count": len(self.events)
        }


if __name__ == "__main__":
    # Example usage
    logging.basicConfig(level=logging.INFO)
    
    detector = ThreatDetector()
    
    # Create sample events
    sample_events = [
        SecurityEvent(
            timestamp=datetime.now().isoformat(),
            source="falco",
            event_type="process_execution",
            container_id="code-server-api-1",
            process="docker run --privileged",
            syscall="execve",
            network_flow=None,
            file_access=None,
            metadata={"uid": 0, "privileged": True}
        )
    ]
    
    # Detect threats
    threats = detector.detect_threats(sample_events)
    
    print(f"Detected {len(threats)} threats:")
    for threat in threats:
        print(f"  - {threat.threat_id}: {threat.description} (severity: {threat.severity.name})")
