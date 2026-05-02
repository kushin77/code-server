"""
Phase 66 — Data Loss Prevention & Exfiltration Detection Engine
================================================================
Monitors data transfers across channels, enforces DLP policies,
detects exfiltration attempts, and produces actionable violation reports.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional


# ---------------------------------------------------------------------------
# Enumerations
# ---------------------------------------------------------------------------


class DataClassification(str, Enum):
    PUBLIC = "PUBLIC"
    INTERNAL = "INTERNAL"
    CONFIDENTIAL = "CONFIDENTIAL"
    RESTRICTED = "RESTRICTED"
    TOP_SECRET = "TOP_SECRET"


class ChannelType(str, Enum):
    EMAIL = "EMAIL"
    HTTP_UPLOAD = "HTTP_UPLOAD"
    FTP = "FTP"
    USB = "USB"
    CLOUD_SYNC = "CLOUD_SYNC"
    PRINT = "PRINT"
    CLIPBOARD = "CLIPBOARD"
    API = "API"


class ViolationSeverity(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


class ViolationStatus(str, Enum):
    DETECTED = "DETECTED"
    INVESTIGATING = "INVESTIGATING"
    CONFIRMED = "CONFIRMED"
    FALSE_POSITIVE = "FALSE_POSITIVE"
    REMEDIATED = "REMEDIATED"


class PolicyAction(str, Enum):
    ALLOW = "ALLOW"
    MONITOR = "MONITOR"
    BLOCK = "BLOCK"
    QUARANTINE = "QUARANTINE"
    ALERT = "ALERT"


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------


@dataclass
class DataAsset:
    asset_id: str
    name: str
    classification: DataClassification
    owner: str
    tags: List[str] = field(default_factory=list)
    size_bytes: int = 0

    def to_dict(self) -> dict:
        return {
            "asset_id": self.asset_id,
            "name": self.name,
            "classification": self.classification.value,
            "owner": self.owner,
            "tags": self.tags,
            "size_bytes": self.size_bytes,
        }


@dataclass
class DLPPolicy:
    policy_id: str
    name: str
    classifications: List[DataClassification]
    blocked_channels: List[ChannelType]
    monitored_channels: List[ChannelType]
    action: PolicyAction
    enabled: bool = True
    description: str = ""

    def applies_to(self, classification: DataClassification, channel: ChannelType) -> bool:
        return self.enabled and classification in self.classifications

    def action_for_channel(self, channel: ChannelType) -> PolicyAction:
        if channel in self.blocked_channels:
            return PolicyAction.BLOCK
        if channel in self.monitored_channels:
            return PolicyAction.MONITOR
        return PolicyAction.ALLOW

    def to_dict(self) -> dict:
        return {
            "policy_id": self.policy_id,
            "name": self.name,
            "classifications": [c.value for c in self.classifications],
            "blocked_channels": [c.value for c in self.blocked_channels],
            "monitored_channels": [c.value for c in self.monitored_channels],
            "action": self.action.value,
            "enabled": self.enabled,
            "description": self.description,
        }


@dataclass
class DataTransferEvent:
    event_id: str
    actor: str
    asset_id: str
    classification: DataClassification
    channel: ChannelType
    destination: str
    size_bytes: int
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    metadata: Dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "event_id": self.event_id,
            "actor": self.actor,
            "asset_id": self.asset_id,
            "classification": self.classification.value,
            "channel": self.channel.value,
            "destination": self.destination,
            "size_bytes": self.size_bytes,
            "timestamp": self.timestamp,
            "metadata": self.metadata,
        }


@dataclass
class DLPViolation:
    violation_id: str
    event_id: str
    actor: str
    asset_id: str
    classification: DataClassification
    channel: ChannelType
    policy_id: str
    policy_name: str
    action_taken: PolicyAction
    severity: ViolationSeverity
    status: ViolationStatus
    destination: str
    size_bytes: int
    detected_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    notes: str = ""

    def to_dict(self) -> dict:
        return {
            "violation_id": self.violation_id,
            "event_id": self.event_id,
            "actor": self.actor,
            "asset_id": self.asset_id,
            "classification": self.classification.value,
            "channel": self.channel.value,
            "policy_id": self.policy_id,
            "policy_name": self.policy_name,
            "action_taken": self.action_taken.value,
            "severity": self.severity.value,
            "status": self.status.value,
            "destination": self.destination,
            "size_bytes": self.size_bytes,
            "detected_at": self.detected_at,
            "notes": self.notes,
        }


@dataclass
class DLPReport:
    report_id: str
    generated_at: str
    total_events_analyzed: int
    total_violations: int
    violations_by_severity: Dict[str, int]
    violations_by_channel: Dict[str, int]
    violations_by_classification: Dict[str, int]
    top_actors: List[Dict[str, object]]
    active_violations: int
    blocked_transfers: int
    monitored_transfers: int
    score: float
    violations: List[DLPViolation] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "report_id": self.report_id,
            "generated_at": self.generated_at,
            "total_events_analyzed": self.total_events_analyzed,
            "total_violations": self.total_violations,
            "violations_by_severity": self.violations_by_severity,
            "violations_by_channel": self.violations_by_channel,
            "violations_by_classification": self.violations_by_classification,
            "top_actors": self.top_actors,
            "active_violations": self.active_violations,
            "blocked_transfers": self.blocked_transfers,
            "monitored_transfers": self.monitored_transfers,
            "score": self.score,
            "violations": [v.to_dict() for v in self.violations],
        }


# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------

_SEVERITY_MAP: Dict[DataClassification, ViolationSeverity] = {
    DataClassification.TOP_SECRET: ViolationSeverity.CRITICAL,
    DataClassification.RESTRICTED: ViolationSeverity.HIGH,
    DataClassification.CONFIDENTIAL: ViolationSeverity.MEDIUM,
    DataClassification.INTERNAL: ViolationSeverity.LOW,
    DataClassification.PUBLIC: ViolationSeverity.LOW,
}

_SEVERITY_DEDUCTIONS: Dict[ViolationSeverity, float] = {
    ViolationSeverity.CRITICAL: 5.0,
    ViolationSeverity.HIGH: 3.0,
    ViolationSeverity.MEDIUM: 1.5,
    ViolationSeverity.LOW: 0.5,
}


class DataLossPreventionEngine:
    """Evaluate data transfer events against DLP policies and track violations."""

    def __init__(self) -> None:
        self._assets: Dict[str, DataAsset] = {}
        self._policies: Dict[str, DLPPolicy] = {}
        self._violations: Dict[str, DLPViolation] = {}
        self._events_analyzed: int = 0
        self._blocked_count: int = 0
        self._monitored_count: int = 0

    # ------------------------------------------------------------------
    # Registration
    # ------------------------------------------------------------------

    def register_asset(self, asset: DataAsset) -> None:
        self._assets[asset.asset_id] = asset

    def register_policy(self, policy: DLPPolicy) -> None:
        self._policies[policy.policy_id] = policy

    def get_asset(self, asset_id: str) -> Optional[DataAsset]:
        return self._assets.get(asset_id)

    def get_policy(self, policy_id: str) -> Optional[DLPPolicy]:
        return self._policies.get(policy_id)

    def list_policies(self) -> List[DLPPolicy]:
        return list(self._policies.values())

    # ------------------------------------------------------------------
    # Transfer analysis
    # ------------------------------------------------------------------

    def analyze_transfer(self, event: DataTransferEvent) -> Optional[DLPViolation]:
        """Evaluate a data transfer event.  Returns a violation if a policy triggers."""
        self._events_analyzed += 1

        triggered_policy: Optional[DLPPolicy] = None
        for policy in self._policies.values():
            if policy.applies_to(event.classification, event.channel):
                channel_action = policy.action_for_channel(event.channel)
                if channel_action in (PolicyAction.BLOCK, PolicyAction.QUARANTINE, PolicyAction.ALERT, PolicyAction.MONITOR):
                    triggered_policy = policy
                    break

        if triggered_policy is None:
            return None

        action_taken = triggered_policy.action_for_channel(event.channel)

        if action_taken == PolicyAction.BLOCK:
            self._blocked_count += 1
        elif action_taken == PolicyAction.MONITOR:
            self._monitored_count += 1

        severity = _SEVERITY_MAP.get(event.classification, ViolationSeverity.LOW)

        violation = DLPViolation(
            violation_id=str(uuid.uuid4()),
            event_id=event.event_id,
            actor=event.actor,
            asset_id=event.asset_id,
            classification=event.classification,
            channel=event.channel,
            policy_id=triggered_policy.policy_id,
            policy_name=triggered_policy.name,
            action_taken=action_taken,
            severity=severity,
            status=ViolationStatus.DETECTED,
            destination=event.destination,
            size_bytes=event.size_bytes,
        )

        self._violations[violation.violation_id] = violation
        return violation

    # ------------------------------------------------------------------
    # Violation management
    # ------------------------------------------------------------------

    def get_violations(self, status: Optional[ViolationStatus] = None) -> List[DLPViolation]:
        if status is None:
            return list(self._violations.values())
        return [v for v in self._violations.values() if v.status == status]

    def get_active_violations(self) -> List[DLPViolation]:
        inactive = {ViolationStatus.FALSE_POSITIVE, ViolationStatus.REMEDIATED}
        return [v for v in self._violations.values() if v.status not in inactive]

    def update_violation_status(
        self,
        violation_id: str,
        new_status: ViolationStatus,
        notes: str = "",
    ) -> bool:
        violation = self._violations.get(violation_id)
        if violation is None:
            return False
        violation.status = new_status
        if notes:
            violation.notes = notes
        return True

    def get_violation(self, violation_id: str) -> Optional[DLPViolation]:
        return self._violations.get(violation_id)

    # ------------------------------------------------------------------
    # Reporting & scoring
    # ------------------------------------------------------------------

    def generate_report(self) -> DLPReport:
        violations = list(self._violations.values())

        by_severity: Dict[str, int] = {s.value: 0 for s in ViolationSeverity}
        by_channel: Dict[str, int] = {}
        by_classification: Dict[str, int] = {}
        actor_counts: Dict[str, int] = {}

        for v in violations:
            by_severity[v.severity.value] += 1
            by_channel[v.channel.value] = by_channel.get(v.channel.value, 0) + 1
            by_classification[v.classification.value] = (
                by_classification.get(v.classification.value, 0) + 1
            )
            actor_counts[v.actor] = actor_counts.get(v.actor, 0) + 1

        top_actors = sorted(
            [{"actor": a, "violations": c} for a, c in actor_counts.items()],
            key=lambda x: x["violations"],
            reverse=True,
        )[:5]

        return DLPReport(
            report_id=str(uuid.uuid4()),
            generated_at=datetime.now(timezone.utc).isoformat(),
            total_events_analyzed=self._events_analyzed,
            total_violations=len(violations),
            violations_by_severity=by_severity,
            violations_by_channel=by_channel,
            violations_by_classification=by_classification,
            top_actors=top_actors,
            active_violations=len(self.get_active_violations()),
            blocked_transfers=self._blocked_count,
            monitored_transfers=self._monitored_count,
            score=self.phase66_score(),
            violations=violations,
        )

    def phase66_score(self) -> float:
        """Return a 0–25 health score. Deduct per active violation severity."""
        score = 25.0
        for v in self.get_active_violations():
            score -= _SEVERITY_DEDUCTIONS.get(v.severity, 0.5)
        return max(0.0, score)

    def summary(self) -> dict:
        active = self.get_active_violations()
        return {
            "phase": 66,
            "engine": "DataLossPreventionEngine",
            "assets_registered": len(self._assets),
            "policies_registered": len(self._policies),
            "events_analyzed": self._events_analyzed,
            "total_violations": len(self._violations),
            "active_violations": len(active),
            "blocked_transfers": self._blocked_count,
            "monitored_transfers": self._monitored_count,
            "score": self.phase66_score(),
        }

    def persist_state(self, path: str = "/tmp/phase66_dlp_state.json") -> str:
        state = {
            "assets": {k: v.to_dict() for k, v in self._assets.items()},
            "policies": {k: v.to_dict() for k, v in self._policies.items()},
            "violations": {k: v.to_dict() for k, v in self._violations.items()},
            "events_analyzed": self._events_analyzed,
            "blocked_count": self._blocked_count,
            "monitored_count": self._monitored_count,
        }
        Path(path).write_text(json.dumps(state, indent=2))
        return path


# ---------------------------------------------------------------------------
# Convenience helpers
# ---------------------------------------------------------------------------


def make_asset(
    classification: DataClassification = DataClassification.CONFIDENTIAL,
    owner: str = "alice",
    size_bytes: int = 1024,
) -> DataAsset:
    return DataAsset(
        asset_id=str(uuid.uuid4()),
        name=f"asset-{classification.value.lower()}",
        classification=classification,
        owner=owner,
        size_bytes=size_bytes,
    )


def make_event(
    actor: str = "bob",
    asset: Optional[DataAsset] = None,
    channel: ChannelType = ChannelType.USB,
    destination: str = "external-device",
    size_bytes: int = 512,
) -> DataTransferEvent:
    if asset is None:
        asset = make_asset()
    return DataTransferEvent(
        event_id=str(uuid.uuid4()),
        actor=actor,
        asset_id=asset.asset_id,
        classification=asset.classification,
        channel=channel,
        destination=destination,
        size_bytes=size_bytes,
    )


def make_policy(
    name: str = "Default DLP Policy",
    classifications: Optional[List[DataClassification]] = None,
    blocked_channels: Optional[List[ChannelType]] = None,
    monitored_channels: Optional[List[ChannelType]] = None,
    action: PolicyAction = PolicyAction.BLOCK,
) -> DLPPolicy:
    return DLPPolicy(
        policy_id=str(uuid.uuid4()),
        name=name,
        classifications=classifications or [DataClassification.CONFIDENTIAL, DataClassification.RESTRICTED],
        blocked_channels=blocked_channels or [ChannelType.USB, ChannelType.FTP],
        monitored_channels=monitored_channels or [ChannelType.EMAIL, ChannelType.HTTP_UPLOAD],
        action=action,
    )
