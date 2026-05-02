"""
insider_threat_detection_engine.py — Phase 65: Insider Threat Detection & Behavior Risk
Detects anomalous user/service access behavior and computes a phase gate score.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional


class ActorType(Enum):
    HUMAN = "human"
    SERVICE = "service"
    CONTRACTOR = "contractor"


class EventType(Enum):
    LOGIN = "login"
    DATA_EXPORT = "data_export"
    PRIVILEGE_CHANGE = "privilege_change"
    FILE_ACCESS = "file_access"
    TOKEN_USAGE = "token_usage"


class RiskLevel(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    NONE = "none"


class AlertStatus(Enum):
    OPEN = "open"
    INVESTIGATING = "investigating"
    RESOLVED = "resolved"
    SUPPRESSED = "suppressed"


@dataclass
class BehaviorEvent:
    event_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    actor_id: str = ""
    actor_type: ActorType = ActorType.HUMAN
    event_type: EventType = EventType.LOGIN
    resource: str = ""
    timestamp: datetime = field(default_factory=datetime.utcnow)
    metadata: Dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "event_id": self.event_id,
            "actor_id": self.actor_id,
            "actor_type": self.actor_type.value,
            "event_type": self.event_type.value,
            "resource": self.resource,
            "timestamp": self.timestamp.isoformat(),
            "metadata": self.metadata,
        }


@dataclass
class BaselineProfile:
    actor_id: str
    expected_regions: List[str] = field(default_factory=list)
    allowed_resources: List[str] = field(default_factory=list)
    max_daily_exports_gb: float = 1.0
    max_privilege_changes_per_day: int = 1

    def to_dict(self) -> dict:
        return {
            "actor_id": self.actor_id,
            "expected_regions": self.expected_regions,
            "allowed_resources": self.allowed_resources,
            "max_daily_exports_gb": self.max_daily_exports_gb,
            "max_privilege_changes_per_day": self.max_privilege_changes_per_day,
        }


@dataclass
class InsiderAlert:
    alert_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    actor_id: str = ""
    risk: RiskLevel = RiskLevel.LOW
    reason: str = ""
    status: AlertStatus = AlertStatus.OPEN
    created_at: datetime = field(default_factory=datetime.utcnow)

    def is_active(self) -> bool:
        return self.status in (AlertStatus.OPEN, AlertStatus.INVESTIGATING)

    def to_dict(self) -> dict:
        return {
            "alert_id": self.alert_id,
            "actor_id": self.actor_id,
            "risk": self.risk.value,
            "reason": self.reason,
            "status": self.status.value,
            "created_at": self.created_at.isoformat(),
        }


@dataclass
class InsiderThreatReport:
    report_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    generated_at: datetime = field(default_factory=datetime.utcnow)
    total_events: int = 0
    total_alerts: int = 0
    active_alerts: int = 0
    critical_alerts: int = 0
    high_alerts: int = 0

    def phase65_score(self) -> float:
        deductions = min(self.critical_alerts * 6, 18) + min(self.high_alerts * 3, 9)
        if self.active_alerts > 0:
            deductions += 2
        return max(0.0, round(25.0 - deductions, 2))

    def to_dict(self) -> dict:
        return {
            "report_id": self.report_id,
            "generated_at": self.generated_at.isoformat(),
            "total_events": self.total_events,
            "total_alerts": self.total_alerts,
            "active_alerts": self.active_alerts,
            "critical_alerts": self.critical_alerts,
            "high_alerts": self.high_alerts,
            "phase65_score": self.phase65_score(),
        }


class InsiderThreatDetectionEngine:
    def __init__(self) -> None:
        self._events: List[BehaviorEvent] = []
        self._baselines: Dict[str, BaselineProfile] = {}
        self._alerts: Dict[str, InsiderAlert] = {}

    def set_baseline(self, profile: BaselineProfile) -> None:
        self._baselines[profile.actor_id] = profile

    def get_baseline(self, actor_id: str) -> Optional[BaselineProfile]:
        return self._baselines.get(actor_id)

    def ingest_event(self, event: BehaviorEvent) -> Optional[InsiderAlert]:
        self._events.append(event)
        baseline = self._baselines.get(event.actor_id)
        if not baseline:
            return self._create_alert(event.actor_id, RiskLevel.MEDIUM, "No baseline profile configured")

        if event.event_type == EventType.DATA_EXPORT:
            gb = float(event.metadata.get("export_gb", 0.0))
            if gb > baseline.max_daily_exports_gb:
                return self._create_alert(event.actor_id, RiskLevel.CRITICAL, f"Large data export: {gb}GB")

        if event.event_type == EventType.PRIVILEGE_CHANGE:
            recent = len([e for e in self._events if e.actor_id == event.actor_id and e.event_type == EventType.PRIVILEGE_CHANGE])
            if recent > baseline.max_privilege_changes_per_day:
                return self._create_alert(event.actor_id, RiskLevel.HIGH, "Excessive privilege changes")

        if baseline.allowed_resources and event.resource and event.resource not in baseline.allowed_resources:
            return self._create_alert(event.actor_id, RiskLevel.HIGH, f"Access to unexpected resource: {event.resource}")

        region = str(event.metadata.get("region", ""))
        if baseline.expected_regions and region and region not in baseline.expected_regions:
            return self._create_alert(event.actor_id, RiskLevel.MEDIUM, f"Unexpected region: {region}")

        return None

    def _create_alert(self, actor_id: str, risk: RiskLevel, reason: str) -> InsiderAlert:
        alert = InsiderAlert(actor_id=actor_id, risk=risk, reason=reason)
        self._alerts[alert.alert_id] = alert
        return alert

    def alerts(self) -> List[InsiderAlert]:
        return list(self._alerts.values())

    def active_alerts(self) -> List[InsiderAlert]:
        return [a for a in self._alerts.values() if a.is_active()]

    def alerts_by_risk(self, risk: RiskLevel) -> List[InsiderAlert]:
        return [a for a in self._alerts.values() if a.risk == risk]

    def resolve_alert(self, alert_id: str) -> bool:
        alert = self._alerts.get(alert_id)
        if not alert:
            return False
        alert.status = AlertStatus.RESOLVED
        return True

    def suppress_alert(self, alert_id: str) -> bool:
        alert = self._alerts.get(alert_id)
        if not alert:
            return False
        alert.status = AlertStatus.SUPPRESSED
        return True

    def events(self) -> List[BehaviorEvent]:
        return list(self._events)

    def generate_report(self) -> InsiderThreatReport:
        return InsiderThreatReport(
            total_events=len(self._events),
            total_alerts=len(self._alerts),
            active_alerts=len(self.active_alerts()),
            critical_alerts=len(self.alerts_by_risk(RiskLevel.CRITICAL)),
            high_alerts=len(self.alerts_by_risk(RiskLevel.HIGH)),
        )

    def phase65_score(self) -> float:
        return self.generate_report().phase65_score()

    def summary(self) -> dict:
        report = self.generate_report()
        return {
            "status": "ok" if report.phase65_score() >= 18 else "attention_required",
            "total_events": report.total_events,
            "total_alerts": report.total_alerts,
            "active_alerts": report.active_alerts,
            "critical_alerts": report.critical_alerts,
            "high_alerts": report.high_alerts,
            "phase65_score": report.phase65_score(),
        }

    def persist_state(self, output_path: str = "artifacts/phase65/insider-threat-report.json") -> str:
        import os

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        state = {
            "phase": 65,
            "engine": "InsiderThreatDetectionEngine",
            "exported_at": datetime.utcnow().isoformat(),
            "summary": self.summary(),
            "baselines": [b.to_dict() for b in self._baselines.values()],
            "events": [e.to_dict() for e in self._events],
            "alerts": [a.to_dict() for a in self._alerts.values()],
        }
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)
        return output_path


def make_event(actor_id: str, event_type: EventType, resource: str = "", actor_type: ActorType = ActorType.HUMAN, metadata: Optional[Dict] = None) -> BehaviorEvent:
    return BehaviorEvent(actor_id=actor_id, actor_type=actor_type, event_type=event_type, resource=resource, metadata=metadata or {})


def make_baseline(actor_id: str, expected_regions: Optional[List[str]] = None, allowed_resources: Optional[List[str]] = None, max_daily_exports_gb: float = 1.0, max_privilege_changes_per_day: int = 1) -> BaselineProfile:
    return BaselineProfile(
        actor_id=actor_id,
        expected_regions=expected_regions or [],
        allowed_resources=allowed_resources or [],
        max_daily_exports_gb=max_daily_exports_gb,
        max_privilege_changes_per_day=max_privilege_changes_per_day,
    )
