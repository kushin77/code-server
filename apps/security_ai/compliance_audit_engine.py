"""
compliance_audit_engine.py — Phase 46: Compliance Audit & Security Posture Verification
Aggregates signals from the full Phase 30-45 security stack into a unified compliance audit.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class AuditSeverity(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"


class FindingStatus(Enum):
    OPEN = "open"
    REMEDIATED = "remediated"
    ACCEPTED = "accepted"
    WONT_FIX = "wont_fix"


class ControlStatus(Enum):
    COMPLIANT = "compliant"
    NON_COMPLIANT = "non_compliant"
    PARTIAL = "partial"
    NOT_APPLICABLE = "not_applicable"


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class AuditFinding:
    finding_id: str
    title: str
    description: str
    severity: AuditSeverity
    phase_source: str
    control_id: str
    status: FindingStatus = FindingStatus.OPEN
    evidence: str = ""
    remediation: str = ""
    created_at: datetime = field(default_factory=datetime.utcnow)

    def resolve(self, resolution: FindingStatus, note: str = "") -> None:
        self.status = resolution
        if note:
            self.remediation = note

    def severity_weight(self) -> float:
        weights = {
            AuditSeverity.CRITICAL: 25.0,
            AuditSeverity.HIGH: 15.0,
            AuditSeverity.MEDIUM: 8.0,
            AuditSeverity.LOW: 3.0,
            AuditSeverity.INFO: 0.5,
        }
        return weights.get(self.severity, 5.0)


@dataclass
class ControlCheck:
    control_id: str
    control_name: str
    framework: str          # e.g. "SOC2", "ISO27001", "NIST"
    phase_source: str       # phase that provides the evidence
    threshold: float        # minimum score to be COMPLIANT (0-100)
    score: float = 0.0
    status: ControlStatus = ControlStatus.NOT_APPLICABLE
    last_checked: Optional[datetime] = None

    def evaluate(self, raw_score: float) -> ControlStatus:
        self.score = max(0.0, min(100.0, raw_score))
        self.last_checked = datetime.utcnow()
        if self.score >= self.threshold:
            self.status = ControlStatus.COMPLIANT
        elif self.score >= self.threshold * 0.75:
            self.status = ControlStatus.PARTIAL
        else:
            self.status = ControlStatus.NON_COMPLIANT
        return self.status


@dataclass
class AuditRecord:
    audit_id: str
    audit_name: str
    scope: str                      # system or service under audit
    controls: List[ControlCheck] = field(default_factory=list)
    findings: List[AuditFinding] = field(default_factory=list)
    phase_signals: Dict[str, float] = field(default_factory=dict)
    started_at: datetime = field(default_factory=datetime.utcnow)
    completed_at: Optional[datetime] = None

    # --- control helpers ---

    def control_summary(self) -> Dict[str, int]:
        summary: Dict[str, int] = {
            "compliant": 0, "partial": 0, "non_compliant": 0, "not_applicable": 0
        }
        for c in self.controls:
            summary[c.status.value] += 1
        return summary

    def is_fully_compliant(self) -> bool:
        return all(
            c.status in (ControlStatus.COMPLIANT, ControlStatus.NOT_APPLICABLE)
            for c in self.controls
        )

    # --- finding helpers ---

    def open_findings_by_severity(self) -> Dict[str, int]:
        counts: Dict[str, int] = {s.value: 0 for s in AuditSeverity}
        for f in self.findings:
            if f.status == FindingStatus.OPEN:
                counts[f.severity.value] += 1
        return counts

    def critical_open(self) -> int:
        return sum(
            1 for f in self.findings
            if f.status == FindingStatus.OPEN and f.severity == AuditSeverity.CRITICAL
        )

    # --- scoring ---

    def posture_score(self) -> float:
        """Compute 0-25 composite security posture score."""
        if not self.controls:
            return 0.0

        # 60% from control compliance average
        avg_control = sum(c.score for c in self.controls) / len(self.controls)
        control_component = (avg_control / 100.0) * 15.0

        # 40% from finding penalty
        penalty = sum(
            f.severity_weight()
            for f in self.findings
            if f.status == FindingStatus.OPEN
        )
        finding_component = max(0.0, 10.0 - penalty * 0.5)

        return round(min(25.0, control_component + finding_component), 2)


# ---------------------------------------------------------------------------
# Standard controls (Phase 30-45 coverage)
# ---------------------------------------------------------------------------


STANDARD_CONTROLS: List[ControlCheck] = [
    ControlCheck("ctrl-30", "Threat Detection Coverage",      "NIST-CSF",  "phase_30",  80.0),
    ControlCheck("ctrl-31", "Compliance Automation Rate",     "SOC2",      "phase_31",  85.0),
    ControlCheck("ctrl-34", "Forensic Evidence Integrity",    "ISO27001",  "phase_34",  80.0),
    ControlCheck("ctrl-35", "Advanced Compliance Score",      "SOC2",      "phase_35",  80.0),
    ControlCheck("ctrl-36", "Adaptive Response Efficiency",   "NIST-CSF",  "phase_36",  75.0),
    ControlCheck("ctrl-38", "Incident Response Time",         "ISO27001",  "phase_38",  75.0),
    ControlCheck("ctrl-40", "Predictive Threat Clearance",    "NIST-CSF",  "phase_40",  75.0),
    ControlCheck("ctrl-45", "Deployment Gate Compliance",     "SOC2",      "phase_45",  80.0),
]


# ---------------------------------------------------------------------------
# Audit Engine
# ---------------------------------------------------------------------------


class ComplianceAuditEngine:
    """
    Central engine for running compliance audits against the Phase 30-45 security stack.
    """

    def __init__(self) -> None:
        self.audits: Dict[str, AuditRecord] = {}
        self.history: List[AuditRecord] = []

    # --- lifecycle ---

    def create_audit(
        self,
        audit_name: str,
        scope: str,
        phase_signals: Optional[Dict[str, float]] = None,
    ) -> AuditRecord:
        audit_id = f"{scope.lower().replace(' ', '-')}-{datetime.utcnow().strftime('%Y%m%dT%H%M%S')}"
        import copy
        controls = [copy.deepcopy(c) for c in STANDARD_CONTROLS]
        record = AuditRecord(
            audit_id=audit_id,
            audit_name=audit_name,
            scope=scope,
            controls=controls,
            phase_signals=dict(phase_signals or {}),
        )
        self.audits[audit_id] = record
        return record

    def run_audit(
        self,
        record: AuditRecord,
        scores: Optional[Dict[str, float]] = None,
    ) -> bool:
        """
        Evaluate all controls.  Scores override phase_signals defaults.
        Returns True when all controls reach COMPLIANT or NOT_APPLICABLE.
        """
        resolved = self._resolve_scores(record.phase_signals, scores or {})
        for ctrl in record.controls:
            raw = resolved.get(ctrl.control_id, resolved.get(ctrl.phase_source, 85.0))
            ctrl.evaluate(raw)
        self._auto_generate_findings(record)
        return record.is_fully_compliant()

    def add_finding(
        self,
        record: AuditRecord,
        title: str,
        description: str,
        severity: AuditSeverity,
        phase_source: str,
        control_id: str,
        evidence: str = "",
    ) -> AuditFinding:
        finding = AuditFinding(
            finding_id=f"F-{uuid.uuid4().hex[:8].upper()}",
            title=title,
            description=description,
            severity=severity,
            phase_source=phase_source,
            control_id=control_id,
            evidence=evidence,
        )
        record.findings.append(finding)
        return finding

    def remediate_finding(
        self, record: AuditRecord, finding_id: str, note: str = ""
    ) -> bool:
        for f in record.findings:
            if f.finding_id == finding_id:
                f.resolve(FindingStatus.REMEDIATED, note)
                return True
        return False

    def finalize_audit(self, record: AuditRecord) -> None:
        record.completed_at = datetime.utcnow()
        self.history.append(record)
        self.audits.pop(record.audit_id, None)

    # --- reporting ---

    def generate_report(self, record: AuditRecord) -> Dict:
        ctrl_sum = record.control_summary()
        findings_sum = record.open_findings_by_severity()
        return {
            "audit_id": record.audit_id,
            "audit_name": record.audit_name,
            "scope": record.scope,
            "posture_score": record.posture_score(),
            "fully_compliant": record.is_fully_compliant(),
            "control_summary": ctrl_sum,
            "open_findings": findings_sum,
            "critical_open": record.critical_open(),
            "total_findings": len(record.findings),
            "completed_at": record.completed_at.isoformat() if record.completed_at else None,
        }

    def summary(self) -> Dict:
        all_records = list(self.audits.values()) + self.history
        if not all_records:
            return {
                "total_audits": 0,
                "fully_compliant": 0,
                "avg_posture_score": 0.0,
                "open_criticals": 0,
                "phase46_audit_score": 0.0,
            }
        scores = [r.posture_score() for r in all_records]
        avg = round(sum(scores) / len(scores), 2)
        return {
            "total_audits": len(all_records),
            "fully_compliant": sum(1 for r in all_records if r.is_fully_compliant()),
            "avg_posture_score": avg,
            "open_criticals": sum(r.critical_open() for r in all_records),
            "phase46_audit_score": avg,
        }

    # --- internals ---

    def _resolve_scores(
        self,
        phase_signals: Dict[str, float],
        overrides: Dict[str, float],
    ) -> Dict[str, float]:
        defaults = {
            "phase_30":  phase_signals.get("phase30_score", 88.0),
            "phase_31":  phase_signals.get("phase31_score", 90.0),
            "phase_34":  phase_signals.get("phase34_score", 85.0),
            "phase_35":  phase_signals.get("phase35_score", 87.0),
            "phase_36":  phase_signals.get("phase36_score", 90.0),
            "phase_38":  phase_signals.get("phase38_score", 83.0),
            "phase_40":  phase_signals.get("phase40_score", 86.0),
            "phase_45":  phase_signals.get("phase45_score", 88.0),
        }
        defaults.update(overrides)
        return defaults

    def _auto_generate_findings(self, record: AuditRecord) -> None:
        """Automatically raise findings for non-compliant controls."""
        for ctrl in record.controls:
            if ctrl.status == ControlStatus.NON_COMPLIANT:
                # Avoid duplicates
                existing = [f.control_id for f in record.findings]
                if ctrl.control_id not in existing:
                    self.add_finding(
                        record,
                        title=f"Control Non-Compliant: {ctrl.control_name}",
                        description=(
                            f"Control {ctrl.control_id} ({ctrl.framework}) scored {ctrl.score:.1f}%, "
                            f"below threshold {ctrl.threshold}%."
                        ),
                        severity=AuditSeverity.HIGH,
                        phase_source=ctrl.phase_source,
                        control_id=ctrl.control_id,
                        evidence=f"score={ctrl.score:.1f}, threshold={ctrl.threshold}",
                    )
            elif ctrl.status == ControlStatus.PARTIAL:
                existing = [f.control_id for f in record.findings]
                if ctrl.control_id not in existing:
                    self.add_finding(
                        record,
                        title=f"Control Partially Compliant: {ctrl.control_name}",
                        description=(
                            f"Control {ctrl.control_id} ({ctrl.framework}) scored {ctrl.score:.1f}%, "
                            f"partially meeting threshold {ctrl.threshold}%."
                        ),
                        severity=AuditSeverity.MEDIUM,
                        phase_source=ctrl.phase_source,
                        control_id=ctrl.control_id,
                        evidence=f"score={ctrl.score:.1f}, threshold={ctrl.threshold}",
                    )


# ---------------------------------------------------------------------------
# Top-level scorer (for test scoring integration)
# ---------------------------------------------------------------------------


def audit_score(engine: ComplianceAuditEngine) -> float:
    """Return the phase46_audit_score (0-25) from the engine summary."""
    return float(engine.summary().get("phase46_audit_score", 0.0))
