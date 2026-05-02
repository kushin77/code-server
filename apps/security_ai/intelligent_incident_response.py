#!/usr/bin/env python3
"""
@module intelligent_incident_response
@description Phase 41: Intelligent Incident Response & Auto-Remediation
@purpose Automatically responds to incidents detected by Phases 34-40 with orchestrated remediation
@since 2026-05-01

Combines forecasts, recommendations, and response automation for self-healing systems.
"""

import json
import os
from pathlib import Path
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict, field
from enum import Enum
from typing import Dict, List, Optional, Tuple
from statistics import mean, stdev
import uuid


class IncidentSeverity(Enum):
    """Incident severity levels"""
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"


class IncidentStatus(Enum):
    """Incident lifecycle status"""
    DETECTED = "detected"
    INVESTIGATING = "investigating"
    REMEDIATING = "remediating"
    RESOLVED = "resolved"
    ESCALATED = "escalated"


class RemediationStrategy(Enum):
    """Remediation tactics"""
    AUTO_SCALE = "auto_scale"
    CONNECTION_POOL_RESET = "connection_pool_reset"
    CACHE_FLUSH = "cache_flush"
    CIRCUIT_BREAK = "circuit_break"
    RATE_LIMIT = "rate_limit"
    QUERY_OPTIMIZATION = "query_optimization"
    POLICY_ENFORCEMENT = "policy_enforcement"
    THREAT_ISOLATION = "threat_isolation"
    DATA_RECOVERY = "data_recovery"
    FAILOVER = "failover"


@dataclass
class IncidentDetection:
    """Detected incident event"""
    incident_id: str
    source_phase: int                  # Phase that detected the incident
    severity: str                      # IncidentSeverity enum value
    incident_type: str
    description: str
    detection_timestamp: float = field(default_factory=lambda: datetime.now().timestamp())
    metrics_threshold: Dict[str, float] = field(default_factory=dict)


@dataclass
class RemediationAction:
    """Single remediation action to execute"""
    action_id: str
    strategy: str                      # RemediationStrategy enum value
    confidence: float                  # 0-1, likelihood of success
    estimated_duration_seconds: float
    resource_cost: float               # Estimated cost in basis points
    success_criteria: List[str] = field(default_factory=list)


@dataclass
class IncidentResponse:
    """Orchestrated incident response"""
    incident_id: str
    status: str                        # IncidentStatus enum value
    severity: str
    detected_at: float
    response_started_at: Optional[float] = None
    response_completed_at: Optional[float] = None
    mttd: Optional[float] = None       # Mean Time To Detect (seconds)
    mttr: Optional[float] = None       # Mean Time To Resolution (seconds)
    remediation_actions: List[RemediationAction] = field(default_factory=list)
    actions_executed: int = 0
    actions_succeeded: int = 0
    remediation_success_rate: float = 0.0
    phase_contributions: Dict[int, str] = field(default_factory=dict)
    timestamp: float = field(default_factory=lambda: datetime.now().timestamp())


class IntelligentIncidentResponse:
    """Orchestrates intelligent incident response with auto-remediation"""

    def __init__(self, state_dir: str = "artifacts/phase41"):
        """Initialize intelligent incident response engine"""
        self.state_dir = state_dir
        Path(self.state_dir).mkdir(parents=True, exist_ok=True)
        
        self.incidents: Dict[str, IncidentDetection] = {}
        self.responses: Dict[str, IncidentResponse] = {}
        self.response_history: List[IncidentResponse] = []
        self.load_state()

    def detect_incident(
        self,
        source_phase: int,
        incident_type: str,
        description: str,
        severity: str,
        metrics: Dict[str, float]
    ) -> IncidentDetection:
        """Detect and register an incident from upstream phase"""
        incident_id = f"incident_{str(uuid.uuid4())[:8]}"
        detection = IncidentDetection(
            incident_id=incident_id,
            source_phase=source_phase,
            severity=severity,
            incident_type=incident_type,
            description=description,
            metrics_threshold=metrics
        )
        self.incidents[incident_id] = detection
        return detection

    def _map_threat_to_severity(self, threat_type: str) -> str:
        """Map threat types to severity levels"""
        threat_severity_map = {
            "security_breach": IncidentSeverity.CRITICAL.value,
            "incident_spike": IncidentSeverity.HIGH.value,
            "resource_exhaustion": IncidentSeverity.HIGH.value,
            "performance_degradation": IncidentSeverity.MEDIUM.value,
            "policy_violation": IncidentSeverity.MEDIUM.value,
            "behavioral_anomaly": IncidentSeverity.LOW.value,
        }
        return threat_severity_map.get(threat_type, IncidentSeverity.MEDIUM.value)

    def _generate_remediation_playbook(self, incident: IncidentDetection) -> List[RemediationAction]:
        """Generate remediation playbook for incident type"""
        actions = []
        
        # Map incident type to remediation strategies
        incident_lower = incident.incident_type.lower()
        
        if "security" in incident_lower or "breach" in incident_lower:
            actions.extend([
                RemediationAction(
                    action_id=f"action_{str(uuid.uuid4())[:8]}",
                    strategy=RemediationStrategy.THREAT_ISOLATION.value,
                    confidence=0.95,
                    estimated_duration_seconds=30,
                    resource_cost=50,
                    success_criteria=["Threat isolated", "Blast radius contained"]
                ),
                RemediationAction(
                    action_id=f"action_{str(uuid.uuid4())[:8]}",
                    strategy=RemediationStrategy.POLICY_ENFORCEMENT.value,
                    confidence=0.90,
                    estimated_duration_seconds=60,
                    resource_cost=20,
                    success_criteria=["Policies re-enforced", "Access controls verified"]
                )
            ])
        
        elif "resource" in incident_lower or "exhaustion" in incident_lower:
            actions.extend([
                RemediationAction(
                    action_id=f"action_{str(uuid.uuid4())[:8]}",
                    strategy=RemediationStrategy.AUTO_SCALE.value,
                    confidence=0.88,
                    estimated_duration_seconds=120,
                    resource_cost=200,
                    success_criteria=["Capacity increased", "Load balanced"]
                ),
                RemediationAction(
                    action_id=f"action_{str(uuid.uuid4())[:8]}",
                    strategy=RemediationStrategy.CACHE_FLUSH.value,
                    confidence=0.85,
                    estimated_duration_seconds=45,
                    resource_cost=10,
                    success_criteria=["Cache cleared", "Memory freed"]
                )
            ])
        
        elif "performance" in incident_lower or "latency" in incident_lower:
            actions.extend([
                RemediationAction(
                    action_id=f"action_{str(uuid.uuid4())[:8]}",
                    strategy=RemediationStrategy.QUERY_OPTIMIZATION.value,
                    confidence=0.80,
                    estimated_duration_seconds=90,
                    resource_cost=15,
                    success_criteria=["Query optimized", "Response time reduced"]
                ),
                RemediationAction(
                    action_id=f"action_{str(uuid.uuid4())[:8]}",
                    strategy=RemediationStrategy.CONNECTION_POOL_RESET.value,
                    confidence=0.92,
                    estimated_duration_seconds=30,
                    resource_cost=5,
                    success_criteria=["Pool reset", "Connections recycled"]
                )
            ])
        
        elif "policy" in incident_lower or "violation" in incident_lower:
            actions.append(
                RemediationAction(
                    action_id=f"action_{str(uuid.uuid4())[:8]}",
                    strategy=RemediationStrategy.POLICY_ENFORCEMENT.value,
                    confidence=0.93,
                    estimated_duration_seconds=60,
                    resource_cost=5,
                    success_criteria=["Policy enforced", "Compliance restored"]
                )
            )
        
        else:
            actions.append(
                RemediationAction(
                    action_id=f"action_{str(uuid.uuid4())[:8]}",
                    strategy=RemediationStrategy.CIRCUIT_BREAK.value,
                    confidence=0.85,
                    estimated_duration_seconds=45,
                    resource_cost=25,
                    success_criteria=["Circuit breaker engaged", "System protected"]
                )
            )
        
        return actions

    def initiate_response(self, incident_id: str, auto_execute: bool = False) -> IncidentResponse:
        """Initiate response orchestration for an incident"""
        if incident_id not in self.incidents:
            raise ValueError(f"Incident {incident_id} not found")
        
        incident = self.incidents[incident_id]
        
        # Create response record
        response = IncidentResponse(
            incident_id=incident_id,
            status=IncidentStatus.INVESTIGATING.value,
            severity=incident.severity,
            detected_at=incident.detection_timestamp,
            response_started_at=datetime.now().timestamp(),
            remediation_actions=self._generate_remediation_playbook(incident),
            phase_contributions={incident.source_phase: f"Detection ({incident.incident_type})"}
        )
        
        # Execute actions if auto-enabled
        if auto_execute:
            self.execute_remediation(incident_id, response)
        
        self.responses[incident_id] = response
        return response

    def execute_remediation(self, incident_id: str, response: IncidentResponse, dry_run: bool = True) -> IncidentResponse:
        """Execute remediation actions for incident"""
        if incident_id not in self.responses:
            response = self.responses[incident_id]
        
        executed = 0
        succeeded = 0
        
        for action in response.remediation_actions:
            executed += 1
            
            # Simulate success based on confidence
            success = (0.95 - (1.0 - action.confidence) * 0.5) > 0.5  # Weighted by confidence
            if success:
                succeeded += 1
        
        response.actions_executed = executed
        response.actions_succeeded = succeeded
        response.remediation_success_rate = (succeeded / executed) if executed > 0 else 0.0
        response.status = IncidentStatus.RESOLVED.value if response.remediation_success_rate > 0.7 else IncidentStatus.ESCALATED.value
        response.response_completed_at = datetime.now().timestamp()
        
        # Calculate MTTD and MTTR
        response.mttd = response.response_started_at - response.detected_at
        response.mttr = response.response_completed_at - response.response_started_at
        
        return response

    def remediation_success_score(self) -> float:
        """
        Calculate remediation success score (0-25 pts for compliance gate).
        Based on average remediation success rate across all responses.
        """
        resolved_responses = [r for r in self.response_history if r.status == IncidentStatus.RESOLVED.value]
        
        if not resolved_responses:
            return 0.0
        
        avg_success_rate = mean([r.remediation_success_rate for r in resolved_responses])
        
        # Score: >80% success = 25pts, 60-80% = 20pts, 40-60% = 15pts, <40% = 5pts
        if avg_success_rate > 0.80:
            return 25.0
        elif avg_success_rate > 0.60:
            return 20.0
        elif avg_success_rate > 0.40:
            return 15.0
        else:
            return 5.0

    def get_incident_metrics(self) -> Dict:
        """Get incident response metrics"""
        total_incidents = len(self.response_history)
        
        if total_incidents == 0:
            return {
                "total_incidents": 0,
                "resolved_incidents": 0,
                "escalated_incidents": 0,
                "avg_mttd": None,
                "avg_mttr": None,
                "avg_success_rate": 0.0,
                "success_score": 0.0
            }
        
        resolved = [r for r in self.response_history if r.status == IncidentSeverity.RESOLVED.value]
        escalated = [r for r in self.response_history if r.status == IncidentStatus.ESCALATED.value]
        
        mttds = [r.mttd for r in self.response_history if r.mttd is not None]
        mttrs = [r.mttr for r in self.response_history if r.mttr is not None]
        
        return {
            "total_incidents": total_incidents,
            "resolved_incidents": len(resolved),
            "escalated_incidents": len(escalated),
            "avg_mttd": mean(mttds) if mttds else None,
            "avg_mttr": mean(mttrs) if mttrs else None,
            "avg_success_rate": mean([r.remediation_success_rate for r in self.response_history]),
            "success_score": self.remediation_success_score()
        }

    def summary(self) -> Dict:
        """Generate incident response summary"""
        metrics = self.get_incident_metrics()
        
        return {
            "timestamp": datetime.now().isoformat(),
            "active_incidents": len(self.incidents),
            "total_incidents_detected": len(self.incidents),
            "incident_responses": len(self.response_history),
            "incidents_resolved": metrics["resolved_incidents"],
            "incidents_escalated": metrics["escalated_incidents"],
            "avg_detection_time_s": metrics["avg_mttd"],
            "avg_resolution_time_s": metrics["avg_mttr"],
            "avg_remediation_success_rate": metrics["avg_success_rate"],
            "remediation_success_score": metrics["success_score"],
            "severity_distribution": {
                "critical": len([i for i in self.incidents.values() if i.severity == IncidentSeverity.CRITICAL.value]),
                "high": len([i for i in self.incidents.values() if i.severity == IncidentSeverity.HIGH.value]),
                "medium": len([i for i in self.incidents.values() if i.severity == IncidentSeverity.MEDIUM.value]),
                "low": len([i for i in self.incidents.values() if i.severity == IncidentSeverity.LOW.value]),
            }
        }

    def persist_state(self) -> None:
        """Persist engine state to disk"""
        incidents_file = os.path.join(self.state_dir, "incidents.json")
        with open(incidents_file, "w") as f:
            json.dump({k: asdict(v) for k, v in self.incidents.items()}, f, indent=2)

        responses_file = os.path.join(self.state_dir, "responses.json")
        with open(responses_file, "w") as f:
            json.dump([asdict(r) for r in self.response_history], f, indent=2)

    def load_state(self) -> None:
        """Load previous engine state"""
        incidents_file = os.path.join(self.state_dir, "incidents.json")
        if os.path.exists(incidents_file):
            try:
                with open(incidents_file) as f:
                    for item in json.load(f).values():
                        self.incidents[item["incident_id"]] = IncidentDetection(**item)
            except Exception:
                pass

        responses_file = os.path.join(self.state_dir, "responses.json")
        if os.path.exists(responses_file):
            try:
                with open(responses_file) as f:
                    for item in json.load(f):
                        # Convert back to RemediationAction objects
                        item["remediation_actions"] = [RemediationAction(**a) for a in item.get("remediation_actions", [])]
                        self.response_history.append(IncidentResponse(**item))
            except Exception:
                pass
