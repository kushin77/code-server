"""
access_governance_engine.py — Phase 61: Identity Access Governance & Privilege Drift
Tracks identities, role assignments, effective permissions, drift from least privilege,
access reviews, and remediation scoring for pipeline gates.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Set


class IdentityType(Enum):
    HUMAN = "human"
    SERVICE = "service"
    MACHINE = "machine"


class IdentityStatus(Enum):
    ACTIVE = "active"
    SUSPENDED = "suspended"
    DEPROVISIONED = "deprovisioned"


class PermissionRisk(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    NONE = "none"


class ReviewStatus(Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REVOKED = "revoked"


class DriftSeverity(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


@dataclass(frozen=True)
class Permission:
    resource: str
    action: str

    def key(self) -> str:
        return f"{self.resource}:{self.action}"


@dataclass
class Role:
    role_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    name: str = ""
    permissions: List[Permission] = field(default_factory=list)
    is_privileged: bool = False

    def permission_keys(self) -> Set[str]:
        return {p.key() for p in self.permissions}

    def to_dict(self) -> dict:
        return {
            "role_id": self.role_id,
            "name": self.name,
            "permissions": [{"resource": p.resource, "action": p.action} for p in self.permissions],
            "is_privileged": self.is_privileged,
        }


@dataclass
class Identity:
    identity_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    name: str = ""
    identity_type: IdentityType = IdentityType.HUMAN
    status: IdentityStatus = IdentityStatus.ACTIVE
    assigned_roles: List[str] = field(default_factory=list)
    direct_permissions: List[Permission] = field(default_factory=list)
    owner: str = ""
    created_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> dict:
        return {
            "identity_id": self.identity_id,
            "name": self.name,
            "identity_type": self.identity_type.value,
            "status": self.status.value,
            "assigned_roles": self.assigned_roles,
            "direct_permissions": [{"resource": p.resource, "action": p.action} for p in self.direct_permissions],
            "owner": self.owner,
            "created_at": self.created_at.isoformat(),
        }


@dataclass
class AccessReview:
    review_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    identity_id: str = ""
    reviewer: str = ""
    status: ReviewStatus = ReviewStatus.PENDING
    findings: List[str] = field(default_factory=list)
    reviewed_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> dict:
        return {
            "review_id": self.review_id,
            "identity_id": self.identity_id,
            "reviewer": self.reviewer,
            "status": self.status.value,
            "findings": self.findings,
            "reviewed_at": self.reviewed_at.isoformat(),
        }


@dataclass
class DriftFinding:
    finding_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    identity_id: str = ""
    severity: DriftSeverity = DriftSeverity.LOW
    reason: str = ""
    excessive_permissions: List[str] = field(default_factory=list)
    privileged_role_count: int = 0
    created_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> dict:
        return {
            "finding_id": self.finding_id,
            "identity_id": self.identity_id,
            "severity": self.severity.value,
            "reason": self.reason,
            "excessive_permissions": self.excessive_permissions,
            "privileged_role_count": self.privileged_role_count,
            "created_at": self.created_at.isoformat(),
        }


@dataclass
class AccessGovernanceReport:
    report_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    generated_at: datetime = field(default_factory=datetime.utcnow)
    total_identities: int = 0
    active_identities: int = 0
    privileged_identities: int = 0
    drift_findings: int = 0
    critical_findings: int = 0
    high_findings: int = 0
    pending_reviews: int = 0
    review_coverage_pct: float = 0.0

    def phase61_score(self) -> float:
        deductions = (
            min(self.critical_findings * 6, 18)
            + min(self.high_findings * 3, 9)
            + min(self.pending_reviews, 6)
        )
        if self.review_coverage_pct < 80:
            deductions += 3
        return max(0.0, round(25.0 - deductions, 2))

    def to_dict(self) -> dict:
        return {
            "report_id": self.report_id,
            "generated_at": self.generated_at.isoformat(),
            "total_identities": self.total_identities,
            "active_identities": self.active_identities,
            "privileged_identities": self.privileged_identities,
            "drift_findings": self.drift_findings,
            "critical_findings": self.critical_findings,
            "high_findings": self.high_findings,
            "pending_reviews": self.pending_reviews,
            "review_coverage_pct": round(self.review_coverage_pct, 2),
            "phase61_score": self.phase61_score(),
        }


class AccessGovernanceEngine:
    def __init__(self) -> None:
        self._roles: Dict[str, Role] = {}
        self._identities: Dict[str, Identity] = {}
        self._least_privilege_baseline: Dict[str, Set[str]] = {}
        self._reviews: List[AccessReview] = []
        self._findings: List[DriftFinding] = []

    def register_role(self, role: Role) -> Role:
        self._roles[role.role_id] = role
        return role

    def register_identity(self, identity: Identity) -> Identity:
        self._identities[identity.identity_id] = identity
        return identity

    def set_least_privilege_baseline(self, identity_id: str, permission_keys: List[str]) -> None:
        self._least_privilege_baseline[identity_id] = set(permission_keys)

    def assign_role(self, identity_id: str, role_id: str) -> bool:
        identity = self._identities.get(identity_id)
        role = self._roles.get(role_id)
        if not identity or not role or identity.status != IdentityStatus.ACTIVE:
            return False
        if role_id not in identity.assigned_roles:
            identity.assigned_roles.append(role_id)
        return True

    def revoke_role(self, identity_id: str, role_id: str) -> bool:
        identity = self._identities.get(identity_id)
        if not identity:
            return False
        if role_id in identity.assigned_roles:
            identity.assigned_roles.remove(role_id)
            return True
        return False

    def add_direct_permission(self, identity_id: str, permission: Permission) -> bool:
        identity = self._identities.get(identity_id)
        if not identity or identity.status != IdentityStatus.ACTIVE:
            return False
        identity.direct_permissions.append(permission)
        return True

    def effective_permissions(self, identity_id: str) -> Set[str]:
        identity = self._identities.get(identity_id)
        if not identity:
            return set()
        keys = {p.key() for p in identity.direct_permissions}
        for role_id in identity.assigned_roles:
            role = self._roles.get(role_id)
            if role:
                keys.update(role.permission_keys())
        return keys

    def privileged_role_count(self, identity_id: str) -> int:
        identity = self._identities.get(identity_id)
        if not identity:
            return 0
        return sum(1 for rid in identity.assigned_roles if self._roles.get(rid) and self._roles[rid].is_privileged)

    def classify_permission_risk(self, permission_key: str) -> PermissionRisk:
        k = permission_key.lower()
        if any(x in k for x in ["*", "admin", "root", "iam:passrole", "kms:decrypt"]):
            return PermissionRisk.CRITICAL
        if any(x in k for x in ["delete", "write", "modify", "create"]):
            return PermissionRisk.HIGH
        if any(x in k for x in ["update", "execute"]):
            return PermissionRisk.MEDIUM
        if any(x in k for x in ["read", "list", "get"]):
            return PermissionRisk.LOW
        return PermissionRisk.NONE

    def detect_privilege_drift(self, identity_id: str) -> Optional[DriftFinding]:
        identity = self._identities.get(identity_id)
        if not identity:
            return None

        effective = self.effective_permissions(identity_id)
        baseline = self._least_privilege_baseline.get(identity_id, set())
        excessive = sorted(list(effective - baseline))
        priv_count = self.privileged_role_count(identity_id)

        severity = None
        reason = ""

        critical_excess = [p for p in excessive if self.classify_permission_risk(p) == PermissionRisk.CRITICAL]
        high_excess = [p for p in excessive if self.classify_permission_risk(p) == PermissionRisk.HIGH]

        if identity.status != IdentityStatus.ACTIVE:
            severity = DriftSeverity.HIGH
            reason = f"Non-active identity '{identity.name}' retains access"
        elif priv_count >= 2 or critical_excess:
            severity = DriftSeverity.CRITICAL
            reason = "Critical privilege drift detected"
        elif priv_count >= 1 or len(high_excess) >= 2:
            severity = DriftSeverity.HIGH
            reason = "High privilege drift detected"
        elif excessive:
            severity = DriftSeverity.MEDIUM
            reason = "Permissions exceed least-privilege baseline"

        if severity is None:
            return None

        finding = DriftFinding(
            identity_id=identity_id,
            severity=severity,
            reason=reason,
            excessive_permissions=excessive,
            privileged_role_count=priv_count,
        )
        self._findings.append(finding)
        return finding

    def scan_all_drift(self) -> List[DriftFinding]:
        results: List[DriftFinding] = []
        for identity_id in self._identities:
            finding = self.detect_privilege_drift(identity_id)
            if finding:
                results.append(finding)
        return results

    def create_review(self, identity_id: str, reviewer: str, findings: Optional[List[str]] = None) -> Optional[AccessReview]:
        if identity_id not in self._identities:
            return None
        review = AccessReview(identity_id=identity_id, reviewer=reviewer, findings=findings or [])
        self._reviews.append(review)
        return review

    def set_review_status(self, review_id: str, status: ReviewStatus) -> bool:
        for r in self._reviews:
            if r.review_id == review_id:
                r.status = status
                r.reviewed_at = datetime.utcnow()
                return True
        return False

    def reviews(self) -> List[AccessReview]:
        return list(self._reviews)

    def findings(self) -> List[DriftFinding]:
        return list(self._findings)

    def findings_by_severity(self) -> Dict[str, List[DriftFinding]]:
        out = {s.value: [] for s in DriftSeverity}
        for f in self._findings:
            out[f.severity.value].append(f)
        return out

    def privileged_identities(self) -> List[Identity]:
        items: List[Identity] = []
        for i in self._identities.values():
            if self.privileged_role_count(i.identity_id) > 0:
                items.append(i)
        return items

    def pending_reviews(self) -> List[AccessReview]:
        return [r for r in self._reviews if r.status == ReviewStatus.PENDING]

    def generate_report(self) -> AccessGovernanceReport:
        by_sev = self.findings_by_severity()
        total = len(self._identities)
        reviewed_ids = {r.identity_id for r in self._reviews}
        coverage = (len(reviewed_ids) / total * 100.0) if total else 100.0
        return AccessGovernanceReport(
            total_identities=total,
            active_identities=sum(1 for i in self._identities.values() if i.status == IdentityStatus.ACTIVE),
            privileged_identities=len(self.privileged_identities()),
            drift_findings=len(self._findings),
            critical_findings=len(by_sev[DriftSeverity.CRITICAL.value]),
            high_findings=len(by_sev[DriftSeverity.HIGH.value]),
            pending_reviews=len(self.pending_reviews()),
            review_coverage_pct=coverage,
        )

    def phase61_score(self) -> float:
        return self.generate_report().phase61_score()

    def summary(self) -> dict:
        report = self.generate_report()
        return {
            "status": "ok" if report.phase61_score() >= 18 else "attention_required",
            "total_identities": report.total_identities,
            "active_identities": report.active_identities,
            "privileged_identities": report.privileged_identities,
            "drift_findings": report.drift_findings,
            "critical_findings": report.critical_findings,
            "high_findings": report.high_findings,
            "pending_reviews": report.pending_reviews,
            "review_coverage_pct": report.review_coverage_pct,
            "phase61_score": report.phase61_score(),
        }

    def persist_state(self, output_path: str = "artifacts/phase61/access-governance.json") -> str:
        import os

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        state = {
            "phase": 61,
            "engine": "AccessGovernanceEngine",
            "exported_at": datetime.utcnow().isoformat(),
            "summary": self.summary(),
            "roles": [r.to_dict() for r in self._roles.values()],
            "identities": [i.to_dict() for i in self._identities.values()],
            "reviews": [r.to_dict() for r in self._reviews],
            "findings": [f.to_dict() for f in self._findings],
        }
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)
        return output_path


def make_permission(resource: str, action: str) -> Permission:
    return Permission(resource=resource, action=action)


def make_role(name: str, permissions: List[Permission], is_privileged: bool = False) -> Role:
    return Role(name=name, permissions=permissions, is_privileged=is_privileged)


def make_identity(name: str, identity_type: IdentityType = IdentityType.HUMAN, owner: str = "") -> Identity:
    return Identity(name=name, identity_type=identity_type, owner=owner)
