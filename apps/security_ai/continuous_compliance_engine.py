"""
continuous_compliance_engine.py — Phase 60: Continuous Compliance & Evidence Collection Engine
Automated continuous compliance monitoring, evidence collection, audit trail
management, and compliance scoring against regulatory frameworks (SOC2, HIPAA,
PCI-DSS, GDPR) with phase60_score() gate contribution (0-25).
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, List, Optional, Set, Tuple


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class ComplianceFramework(Enum):
    SOC2       = "soc2"
    HIPAA      = "hipaa"
    PCI_DSS    = "pci_dss"
    GDPR       = "gdpr"
    ISO27001   = "iso_27001"
    NIST       = "nist"


class ControlStatus(Enum):
    COMPLIANT      = "compliant"
    NON_COMPLIANT  = "non_compliant"
    PARTIAL        = "partial"
    NOT_APPLICABLE = "not_applicable"
    EVIDENCE_PENDING = "evidence_pending"


class EvidenceType(Enum):
    CONFIGURATION = "configuration"
    LOG_ENTRY      = "log_entry"
    POLICY        = "policy"
    AUDIT_REPORT  = "audit_report"
    ASSESSMENT    = "assessment"
    ATTESTATION   = "attestation"
    PROCEDURE     = "procedure"
    OTHER         = "other"


class AuditAction(Enum):
    ACCESS_GRANTED   = "access_granted"
    ACCESS_DENIED    = "access_denied"
    OBJECT_CREATED   = "object_created"
    OBJECT_MODIFIED  = "object_modified"
    OBJECT_DELETED   = "object_deleted"
    PERMISSION_CHANGED = "permission_changed"
    CONFIGURATION_CHANGED = "configuration_changed"
    OTHER            = "other"


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class ComplianceControl:
    """A single compliance control requirement."""
    control_id:    str
    framework:     ComplianceFramework
    title:         str
    description:   str
    status:        ControlStatus     = ControlStatus.EVIDENCE_PENDING
    required:      bool              = True
    last_verified: Optional[datetime] = None
    evidence_ids:  List[str]         = field(default_factory=list)
    notes:         str               = ""

    def to_dict(self) -> Dict:
        return {
            "control_id": self.control_id,
            "framework": self.framework.value,
            "title": self.title,
            "description": self.description,
            "status": self.status.value,
            "required": self.required,
            "last_verified": self.last_verified.isoformat() if self.last_verified else None,
            "evidence_count": len(self.evidence_ids),
            "notes": self.notes,
        }


@dataclass
class ComplianceEvidence:
    """Evidence supporting compliance with a control."""
    evidence_id:   str
    control_id:    str
    evidence_type: EvidenceType
    description:   str
    collected_at:  datetime
    collected_by:  str
    content_hash:  str           # SHA256
    location:      str           # URL or file path
    metadata:      Dict          = field(default_factory=dict)
    expires_at:    Optional[datetime] = None

    @property
    def is_expired(self) -> bool:
        if self.expires_at is None:
            return False
        return datetime.utcnow() > self.expires_at

    @property
    def days_until_expiry(self) -> Optional[float]:
        if self.expires_at is None:
            return None
        return (self.expires_at - datetime.utcnow()).total_seconds() / 86400.0

    def to_dict(self) -> Dict:
        return {
            "evidence_id": self.evidence_id,
            "control_id": self.control_id,
            "evidence_type": self.evidence_type.value,
            "description": self.description,
            "collected_at": self.collected_at.isoformat(),
            "collected_by": self.collected_by,
            "location": self.location,
            "is_expired": self.is_expired,
            "days_until_expiry": self.days_until_expiry,
        }


@dataclass
class AuditEntry:
    """An audit log entry for compliance tracking."""
    audit_id:      str
    action:        AuditAction
    actor:         str
    resource:      str
    timestamp:     datetime
    result:        str           # "success", "failure", etc.
    details:       str           = ""
    framework:     Optional[ComplianceFramework] = None

    def to_dict(self) -> Dict:
        return {
            "audit_id": self.audit_id,
            "action": self.action.value,
            "actor": self.actor,
            "resource": self.resource,
            "timestamp": self.timestamp.isoformat(),
            "result": self.result,
            "details": self.details,
            "framework": self.framework.value if self.framework else None,
        }


@dataclass
class ComplianceAssessment:
    """A compliance assessment result."""
    assessment_id:   str
    framework:       ComplianceFramework
    assessed_at:     datetime
    compliant_count: int
    partial_count:   int
    non_compliant_count: int
    total_required:  int
    score:           float             # 0-100
    notes:           str = ""

    @property
    def compliance_pct(self) -> float:
        """Percentage of compliant + partial controls."""
        if self.total_required == 0:
            return 100.0
        return round((self.compliant_count + self.partial_count * 0.5) / self.total_required * 100.0, 2)

    def to_dict(self) -> Dict:
        return {
            "assessment_id": self.assessment_id,
            "framework": self.framework.value,
            "assessed_at": self.assessed_at.isoformat(),
            "compliant": self.compliant_count,
            "partial": self.partial_count,
            "non_compliant": self.non_compliant_count,
            "total_required": self.total_required,
            "compliance_pct": self.compliance_pct,
            "score": self.score,
        }


# ---------------------------------------------------------------------------
# Continuous Compliance Engine
# ---------------------------------------------------------------------------


class ContinuousComplianceEngine:
    """
    Phase 60 — Continuous Compliance & Evidence Collection Engine.

    Manages compliance controls, evidence collection, audit trails, and
    produces phase60_score() gate contribution (0-25).
    """

    def __init__(self) -> None:
        self._controls:      Dict[str, ComplianceControl] = {}
        self._evidence:      Dict[str, ComplianceEvidence] = {}
        self._audit_log:     List[AuditEntry] = []
        self._assessments:   List[ComplianceAssessment] = []
        self._control_evidence: Dict[str, List[str]] = {}  # control_id -> [evidence_ids]

    # --- Control management ---

    def register_control(
        self,
        framework: ComplianceFramework,
        control_id: str,
        title: str,
        description: str,
        required: bool = True,
    ) -> ComplianceControl:
        """Register a compliance control."""
        if control_id in self._controls:
            raise ValueError(f"Control {control_id!r} already exists")
        control = ComplianceControl(
            control_id=control_id,
            framework=framework,
            title=title,
            description=description,
            required=required,
        )
        self._controls[control_id] = control
        self._control_evidence[control_id] = []
        return control

    def update_control_status(
        self,
        control_id: str,
        status: ControlStatus,
        notes: str = "",
    ) -> ComplianceControl:
        """Update control compliance status."""
        if control_id not in self._controls:
            raise KeyError(f"Control {control_id!r} not found")
        control = self._controls[control_id]
        control.status = status
        control.last_verified = datetime.utcnow()
        control.notes = notes
        return control

    def get_control(self, control_id: str) -> ComplianceControl:
        if control_id not in self._controls:
            raise KeyError(f"Control {control_id!r} not found")
        return self._controls[control_id]

    # --- Evidence management ---

    def collect_evidence(
        self,
        control_id: str,
        evidence_type: EvidenceType,
        description: str,
        location: str,
        collected_by: str,
        content_hash: str = "",
        expires_in_days: Optional[int] = None,
        metadata: Optional[Dict] = None,
    ) -> ComplianceEvidence:
        """Collect evidence for a control."""
        if control_id not in self._controls:
            raise KeyError(f"Control {control_id!r} not found")
        eid = f"EV-{uuid.uuid4().hex[:8].upper()}"
        expires_at = None
        if expires_in_days:
            expires_at = datetime.utcnow() + timedelta(days=expires_in_days)
        evidence = ComplianceEvidence(
            evidence_id=eid,
            control_id=control_id,
            evidence_type=evidence_type,
            description=description,
            collected_at=datetime.utcnow(),
            collected_by=collected_by,
            content_hash=content_hash,
            location=location,
            metadata=metadata or {},
            expires_at=expires_at,
        )
        self._evidence[eid] = evidence
        self._control_evidence[control_id].append(eid)
        return evidence

    def get_evidence(self, evidence_id: str) -> ComplianceEvidence:
        if evidence_id not in self._evidence:
            raise KeyError(f"Evidence {evidence_id!r} not found")
        return self._evidence[evidence_id]

    def evidence_for_control(self, control_id: str) -> List[ComplianceEvidence]:
        """Get all evidence for a control."""
        return [
            self._evidence[eid]
            for eid in self._control_evidence.get(control_id, [])
        ]

    # --- Audit log ---

    def log_audit_event(
        self,
        action: AuditAction,
        actor: str,
        resource: str,
        result: str,
        details: str = "",
        framework: Optional[ComplianceFramework] = None,
    ) -> AuditEntry:
        """Record an audit event."""
        aid = f"AUD-{uuid.uuid4().hex[:8].upper()}"
        entry = AuditEntry(
            audit_id=aid,
            action=action,
            actor=actor,
            resource=resource,
            timestamp=datetime.utcnow(),
            result=result,
            details=details,
            framework=framework,
        )
        self._audit_log.append(entry)
        return entry

    # --- Assessment ---

    def assess_framework(self, framework: ComplianceFramework) -> ComplianceAssessment:
        """Assess compliance with a framework."""
        controls_for_fw = [c for c in self._controls.values() if c.framework == framework and c.required]
        if not controls_for_fw:
            return ComplianceAssessment(
                assessment_id=f"ASS-{uuid.uuid4().hex[:8].upper()}",
                framework=framework,
                assessed_at=datetime.utcnow(),
                compliant_count=0,
                partial_count=0,
                non_compliant_count=0,
                total_required=0,
                score=100.0,
            )

        compliant = sum(1 for c in controls_for_fw if c.status == ControlStatus.COMPLIANT)
        partial = sum(1 for c in controls_for_fw if c.status == ControlStatus.PARTIAL)
        non_compliant = sum(1 for c in controls_for_fw if c.status == ControlStatus.NON_COMPLIANT)

        total = len(controls_for_fw)
        score = round((compliant * 100.0 + partial * 50.0) / total, 2) if total > 0 else 100.0

        assessment = ComplianceAssessment(
            assessment_id=f"ASS-{uuid.uuid4().hex[:8].upper()}",
            framework=framework,
            assessed_at=datetime.utcnow(),
            compliant_count=compliant,
            partial_count=partial,
            non_compliant_count=non_compliant,
            total_required=total,
            score=score,
        )
        self._assessments.append(assessment)
        return assessment

    # --- Queries ---

    def controls_by_framework(self, framework: ComplianceFramework) -> List[ComplianceControl]:
        """Get all controls for a framework."""
        return [c for c in self._controls.values() if c.framework == framework]

    def controls_by_status(self, status: ControlStatus) -> List[ComplianceControl]:
        """Get all controls with a given status."""
        return [c for c in self._controls.values() if c.status == status]

    def expired_evidence(self) -> List[ComplianceEvidence]:
        """Get all expired evidence."""
        return [e for e in self._evidence.values() if e.is_expired]

    def evidence_expiring_soon(self, days: int = 30) -> List[ComplianceEvidence]:
        """Get evidence expiring within N days."""
        cutoff = datetime.utcnow() + timedelta(days=days)
        return [
            e for e in self._evidence.values()
            if e.expires_at is not None and e.expires_at <= cutoff and not e.is_expired
        ]

    def recent_audit_entries(self, hours: int = 24) -> List[AuditEntry]:
        """Get audit entries from the last N hours."""
        cutoff = datetime.utcnow() - timedelta(hours=hours)
        return [e for e in self._audit_log if e.timestamp >= cutoff]

    # --- Scoring ---

    def phase60_score(self) -> float:
        """
        Gate score 0-25 based on:
        - Control compliance rate: % of required controls compliant or partial
        - Evidence recency: % of controls with recent evidence
        - Audit coverage: % of resources with audit entries
        
        Score = 25 × (compliance_rate×0.5 + evidence_rate×0.3 + audit_rate×0.2)
        """
        # Compliance rate
        required_controls = [c for c in self._controls.values() if c.required]
        if required_controls:
            compliant_or_partial = sum(
                1 for c in required_controls
                if c.status in (ControlStatus.COMPLIANT, ControlStatus.PARTIAL)
            )
            compliance_rate = compliant_or_partial / len(required_controls)
        else:
            compliance_rate = 1.0

        # Evidence recency (controls with evidence from last 30 days)
        recent_cutoff = datetime.utcnow() - timedelta(days=30)
        if required_controls:
            with_recent_evidence = sum(
                1 for c in required_controls
                if any(self._evidence[eid].collected_at >= recent_cutoff 
                      for eid in self._control_evidence.get(c.control_id, []))
            )
            evidence_rate = with_recent_evidence / len(required_controls)
        else:
            evidence_rate = 1.0

        # Audit coverage (resources with audit entries)
        if self._audit_log:
            unique_resources = set(e.resource for e in self._audit_log)
            audit_rate = min(len(unique_resources) / 10.0, 1.0)  # 10 unique = 100%
        else:
            audit_rate = 0.0

        composite = compliance_rate * 0.5 + evidence_rate * 0.3 + audit_rate * 0.2
        return round(25.0 * composite, 2)

    def summary(self) -> Dict:
        required = [c for c in self._controls.values() if c.required]
        compliant = sum(1 for c in required if c.status == ControlStatus.COMPLIANT)
        partial = sum(1 for c in required if c.status == ControlStatus.PARTIAL)
        non_compliant = sum(1 for c in required if c.status == ControlStatus.NON_COMPLIANT)

        return {
            "total_controls": len(self._controls),
            "required_controls": len(required),
            "compliant": compliant,
            "partial": partial,
            "non_compliant": non_compliant,
            "total_evidence": len(self._evidence),
            "expired_evidence": len(self.expired_evidence()),
            "expiring_soon_30d": len(self.evidence_expiring_soon(30)),
            "total_audit_entries": len(self._audit_log),
            "frameworks": len(set(c.framework for c in self._controls.values())),
            "phase60_score": self.phase60_score(),
        }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_control(
    engine: ContinuousComplianceEngine,
    framework: ComplianceFramework,
    control_id: str,
    title: str,
) -> ComplianceControl:
    return engine.register_control(framework, control_id, title, "")


def compliance_score(engine: ContinuousComplianceEngine) -> float:
    return engine.phase60_score()
