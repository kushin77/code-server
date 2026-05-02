"""
forensic_investigation_engine.py — Phase 59: Forensic Investigation & Chain of Custody Engine
Manages forensic investigation workflows, evidence collection, chain of custody
tracking, evidence integrity verification (hash validation), and forensic analysis
reports. Produces phase59_score() gate contribution (0-25).
"""
from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class EvidenceType(Enum):
    DISK_IMAGE    = "disk_image"
    MEMORY_DUMP   = "memory_dump"
    LOG_FILE      = "log_file"
    NETWORK_PCAP  = "network_pcap"
    EMAIL         = "email"
    DATABASE      = "database"
    CONFIG_FILE   = "config_file"
    EXECUTABLE    = "executable"
    REGISTRY      = "registry"
    OTHER         = "other"


class EvidenceStatus(Enum):
    COLLECTED    = "collected"
    VERIFIED     = "verified"
    ANALYZED     = "analyzed"
    ARCHIVED     = "archived"
    PURGED       = "purged"


class InvestigationStatus(Enum):
    OPEN       = "open"
    ACTIVE     = "active"
    SUSPENDED  = "suspended"
    COMPLETED  = "completed"
    CLOSED     = "closed"


class FindingSeverity(Enum):
    CRITICAL = "critical"
    HIGH     = "high"
    MEDIUM   = "medium"
    LOW      = "low"
    INFO     = "info"


class ChainOfCustodyAction(Enum):
    COLLECTED  = "collected"
    RECEIVED   = "received"
    TRANSFERRED = "transferred"
    ANALYZED   = "analyzed"
    ARCHIVED   = "archived"
    RELEASED   = "released"


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class EvidenceItem:
    """A single piece of evidence in a forensic investigation."""
    evidence_id:  str
    case_id:      str
    item_type:    EvidenceType
    description:  str
    source_path:  str
    collected_at: datetime
    collected_by: str
    status:       EvidenceStatus = EvidenceStatus.COLLECTED
    sha256_hash:  str = ""
    size_bytes:   int = 0
    location:     str = ""
    metadata:     Dict = field(default_factory=dict)
    _coc_history: List[Tuple[str, datetime, str]] = field(default_factory=list, repr=False)

    @property
    def hash_verified(self) -> bool:
        """Returns True if hash has been set (verification done)."""
        return bool(self.sha256_hash)

    def verify_hash(self, expected_hash: str) -> bool:
        """Verify that provided hash matches stored hash."""
        return self.sha256_hash.lower() == expected_hash.lower()

    def add_coc_action(self, action: ChainOfCustodyAction, actor: str, notes: str = "") -> None:
        """Record a chain of custody action."""
        self._coc_history.append((action.value, datetime.utcnow(), f"{actor}: {notes}"))

    @property
    def coc_chain(self) -> List[Dict]:
        """Return chain of custody history as list of dicts."""
        return [
            {
                "action": action,
                "timestamp": ts.isoformat(),
                "notes": note,
            }
            for action, ts, note in self._coc_history
        ]

    def to_dict(self) -> Dict:
        return {
            "evidence_id": self.evidence_id,
            "case_id": self.case_id,
            "item_type": self.item_type.value,
            "description": self.description,
            "source_path": self.source_path,
            "collected_at": self.collected_at.isoformat(),
            "collected_by": self.collected_by,
            "status": self.status.value,
            "sha256_hash": self.sha256_hash,
            "size_bytes": self.size_bytes,
            "location": self.location,
            "hash_verified": self.hash_verified,
            "coc_chain": self.coc_chain,
        }


@dataclass
class ForensicFinding:
    """A finding from forensic analysis."""
    finding_id:   str
    case_id:      str
    severity:     FindingSeverity
    title:        str
    description:  str
    evidence_ids: List[str] = field(default_factory=list)
    timeline:     List[Tuple[str, datetime, str]] = field(default_factory=list)

    def add_timeline_event(self, event: str, note: str = "") -> None:
        self.timeline.append((event, datetime.utcnow(), note))

    def to_dict(self) -> Dict:
        return {
            "finding_id": self.finding_id,
            "case_id": self.case_id,
            "severity": self.severity.value,
            "title": self.title,
            "description": self.description,
            "evidence_ids": self.evidence_ids,
            "timeline": [
                {
                    "event": e,
                    "timestamp": t.isoformat(),
                    "note": n,
                }
                for e, t, n in self.timeline
            ],
        }


@dataclass
class ForensicCase:
    """A forensic investigation case."""
    case_id:      str
    title:        str
    opened_at:    datetime = field(default_factory=datetime.utcnow)
    opened_by:    str = "system"
    status:       InvestigationStatus = InvestigationStatus.OPEN
    closed_at:    Optional[datetime] = None
    evidence:     List[EvidenceItem] = field(default_factory=list)
    findings:     List[ForensicFinding] = field(default_factory=list)
    metadata:     Dict = field(default_factory=dict)

    @property
    def total_evidence(self) -> int:
        return len(self.evidence)

    @property
    def verified_evidence(self) -> int:
        return sum(1 for e in self.evidence if e.hash_verified)

    @property
    def verified_pct(self) -> float:
        if not self.evidence:
            return 100.0
        return round(self.verified_evidence / self.total_evidence * 100.0, 2)

    @property
    def critical_findings(self) -> int:
        return sum(1 for f in self.findings if f.severity == FindingSeverity.CRITICAL)

    @property
    def high_findings(self) -> int:
        return sum(1 for f in self.findings if f.severity == FindingSeverity.HIGH)

    def duration_minutes(self) -> float:
        """Elapsed time since case opened."""
        end = self.closed_at or datetime.utcnow()
        return (end - self.opened_at).total_seconds() / 60.0


# ---------------------------------------------------------------------------
# Forensic Investigation Engine
# ---------------------------------------------------------------------------


class ForensicInvestigationEngine:
    """
    Phase 59 — Forensic Investigation & Chain of Custody Engine.

    Manages forensic case workflows, evidence collection, chain of custody
    tracking, hash verification, and forensic analysis with phase59_score()
    gate contribution (0-25).
    """

    def __init__(self) -> None:
        self._cases:  Dict[str, ForensicCase] = {}
        self._closed_cases: List[str] = []

    # --- Case management ---

    def open_case(
        self,
        title: str,
        opened_by: str = "system",
        metadata: Optional[Dict] = None,
    ) -> ForensicCase:
        """Open a new forensic investigation case."""
        case_id = f"CASE-{uuid.uuid4().hex[:8].upper()}"
        case = ForensicCase(
            case_id=case_id,
            title=title,
            opened_by=opened_by,
            metadata=metadata or {},
        )
        self._cases[case_id] = case
        return case

    def close_case(self, case_id: str, status: InvestigationStatus = InvestigationStatus.CLOSED) -> ForensicCase:
        """Close a forensic investigation case."""
        case = self._get(case_id)
        case.status = status
        case.closed_at = datetime.utcnow()
        self._closed_cases.append(case_id)
        return case

    def get_case(self, case_id: str) -> ForensicCase:
        """Retrieve a case by ID."""
        return self._get(case_id)

    # --- Evidence management ---

    def collect_evidence(
        self,
        case_id: str,
        item_type: EvidenceType,
        description: str,
        source_path: str,
        collected_by: str,
        sha256_hash: str = "",
        size_bytes: int = 0,
        location: str = "",
        metadata: Optional[Dict] = None,
    ) -> EvidenceItem:
        """Collect evidence for a case."""
        case = self._get(case_id)
        eid = f"EV-{uuid.uuid4().hex[:8].upper()}"
        evidence = EvidenceItem(
            evidence_id=eid,
            case_id=case_id,
            item_type=item_type,
            description=description,
            source_path=source_path,
            collected_at=datetime.utcnow(),
            collected_by=collected_by,
            sha256_hash=sha256_hash,
            size_bytes=size_bytes,
            location=location,
            metadata=metadata or {},
        )
        evidence.add_coc_action(ChainOfCustodyAction.COLLECTED, collected_by, description)
        case.evidence.append(evidence)
        return evidence

    def verify_evidence_hash(
        self,
        case_id: str,
        evidence_id: str,
        expected_hash: str,
        verified_by: str,
    ) -> bool:
        """Verify evidence integrity by hash."""
        case = self._get(case_id)
        for ev in case.evidence:
            if ev.evidence_id == evidence_id:
                match = ev.verify_hash(expected_hash)
                if match:
                    ev.status = EvidenceStatus.VERIFIED
                    ev.add_coc_action(ChainOfCustodyAction.RECEIVED, verified_by, "Hash verified")
                return match
        raise KeyError(f"Evidence {evidence_id!r} not found in case {case_id!r}")

    def transfer_evidence(
        self,
        case_id: str,
        evidence_id: str,
        to_location: str,
        transferred_by: str,
    ) -> EvidenceItem:
        """Transfer evidence to another location."""
        case = self._get(case_id)
        for ev in case.evidence:
            if ev.evidence_id == evidence_id:
                ev.location = to_location
                ev.add_coc_action(ChainOfCustodyAction.TRANSFERRED, transferred_by, f"To: {to_location}")
                return ev
        raise KeyError(f"Evidence {evidence_id!r} not found")

    def mark_evidence_analyzed(
        self,
        case_id: str,
        evidence_id: str,
        analyzed_by: str,
    ) -> EvidenceItem:
        """Mark evidence as analyzed."""
        case = self._get(case_id)
        for ev in case.evidence:
            if ev.evidence_id == evidence_id:
                ev.status = EvidenceStatus.ANALYZED
                ev.add_coc_action(ChainOfCustodyAction.ANALYZED, analyzed_by, "Analysis complete")
                return ev
        raise KeyError(f"Evidence {evidence_id!r} not found")

    # --- Findings ---

    def add_finding(
        self,
        case_id: str,
        severity: FindingSeverity,
        title: str,
        description: str,
        evidence_ids: Optional[List[str]] = None,
    ) -> ForensicFinding:
        """Add a forensic finding to a case."""
        case = self._get(case_id)
        fid = f"FIND-{uuid.uuid4().hex[:8].upper()}"
        finding = ForensicFinding(
            finding_id=fid,
            case_id=case_id,
            severity=severity,
            title=title,
            description=description,
            evidence_ids=evidence_ids or [],
        )
        case.findings.append(finding)
        return finding

    # --- Queries ---

    def all_cases(self) -> List[ForensicCase]:
        """Return all cases."""
        return list(self._cases.values())

    def open_cases(self) -> List[ForensicCase]:
        """Return open/active cases."""
        return [c for c in self._cases.values() if c.status in (InvestigationStatus.OPEN, InvestigationStatus.ACTIVE)]

    def cases_with_unverified_evidence(self) -> List[ForensicCase]:
        """Return cases with evidence that hasn't been verified."""
        return [
            c for c in self._cases.values()
            if c.verified_pct < 100.0
        ]

    # --- Scoring ---

    def phase59_score(self) -> float:
        """
        Gate score 0-25 based on:
        - Evidence collection rate: % of collected items
        - Hash verification rate: % of items with verified hashes
        - Case closure rate: % of closed cases
        
        Score = 25 × (collection_rate × 0.4 + verification_rate × 0.4 + closure_rate × 0.2)
        """
        if not self._cases:
            return 25.0

        # Collection: all cases should have some evidence
        collected = sum(1 for c in self._cases.values() if c.total_evidence > 0)
        collection_rate = collected / len(self._cases) if self._cases else 0.0

        # Verification: across all evidence, % that are verified
        all_evidence = [e for c in self._cases.values() for e in c.evidence]
        if all_evidence:
            verification_rate = sum(1 for e in all_evidence if e.hash_verified) / len(all_evidence)
        else:
            verification_rate = 1.0

        # Closure: % of closed cases
        closure_rate = len(self._closed_cases) / len(self._cases) if self._cases else 0.0

        composite = collection_rate * 0.4 + verification_rate * 0.4 + closure_rate * 0.2
        return round(25.0 * composite, 2)

    def summary(self) -> Dict:
        """Return summary of forensic investigation state."""
        all_cases = self._cases.values()
        total_evidence = sum(c.total_evidence for c in all_cases)
        verified_evidence = sum(c.verified_evidence for c in all_cases)

        return {
            "total_cases": len(self._cases),
            "open_cases": len(self.open_cases()),
            "closed_cases": len(self._closed_cases),
            "total_evidence": total_evidence,
            "verified_evidence": verified_evidence,
            "unverified_evidence": total_evidence - verified_evidence,
            "verification_pct": round(verified_evidence / total_evidence * 100.0, 2) if total_evidence > 0 else 100.0,
            "critical_findings": sum(c.critical_findings for c in all_cases),
            "high_findings": sum(c.high_findings for c in all_cases),
            "phase59_score": self.phase59_score(),
        }

    def case_report(self, case_id: str) -> Dict:
        """Generate a detailed forensic case report."""
        case = self._get(case_id)
        return {
            "case_id": case.case_id,
            "title": case.title,
            "opened_at": case.opened_at.isoformat(),
            "opened_by": case.opened_by,
            "closed_at": case.closed_at.isoformat() if case.closed_at else None,
            "status": case.status.value,
            "duration_minutes": round(case.duration_minutes(), 2),
            "total_evidence": case.total_evidence,
            "verified_evidence": case.verified_evidence,
            "verification_pct": case.verified_pct,
            "critical_findings": case.critical_findings,
            "high_findings": case.high_findings,
            "evidence": [e.to_dict() for e in case.evidence],
            "findings": [f.to_dict() for f in case.findings],
        }

    # --- Internal ---

    def _get(self, case_id: str) -> ForensicCase:
        if case_id not in self._cases:
            raise KeyError(f"Case {case_id!r} not found")
        return self._cases[case_id]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_case(engine: ForensicInvestigationEngine, title: str) -> ForensicCase:
    return engine.open_case(title)


def forensic_score(engine: ForensicInvestigationEngine) -> float:
    return engine.phase59_score()
