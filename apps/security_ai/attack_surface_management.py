"""
attack_surface_management.py — Phase 63: Attack Surface Exposure Management
Inventorys attack surface assets, tracks exposure findings, prioritizes remediation,
and computes a gate score for risk-driven release controls.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional


class AssetType(Enum):
    API = "api"
    WEB_APP = "web_app"
    VM = "vm"
    CONTAINER = "container"
    DATABASE = "database"
    STORAGE = "storage"
    DNS = "dns"
    CDN = "cdn"


class ExposureSeverity(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class ExposureCategory(Enum):
    MISCONFIGURATION = "misconfiguration"
    WEAK_AUTH = "weak_auth"
    OUTDATED_COMPONENT = "outdated_component"
    OPEN_PORT = "open_port"
    EXPOSED_ADMIN_INTERFACE = "exposed_admin_interface"
    DATA_EXPOSURE = "data_exposure"
    MISSING_ENCRYPTION = "missing_encryption"


class ExposureStatus(Enum):
    OPEN = "open"
    ACCEPTED_RISK = "accepted_risk"
    IN_REMEDIATION = "in_remediation"
    RESOLVED = "resolved"


class RemediationStatus(Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    BLOCKED = "blocked"
    DONE = "done"


@dataclass
class AttackSurfaceAsset:
    asset_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    name: str = ""
    asset_type: AssetType = AssetType.API
    environment: str = "production"
    internet_facing: bool = True
    owner_team: str = "security"
    criticality: int = 3  # 1-5
    tags: List[str] = field(default_factory=list)
    discovered_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> dict:
        return {
            "asset_id": self.asset_id,
            "name": self.name,
            "asset_type": self.asset_type.value,
            "environment": self.environment,
            "internet_facing": self.internet_facing,
            "owner_team": self.owner_team,
            "criticality": self.criticality,
            "tags": self.tags,
            "discovered_at": self.discovered_at.isoformat(),
        }


@dataclass
class ExposureFinding:
    finding_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    asset_id: str = ""
    title: str = ""
    category: ExposureCategory = ExposureCategory.MISCONFIGURATION
    severity: ExposureSeverity = ExposureSeverity.MEDIUM
    status: ExposureStatus = ExposureStatus.OPEN
    evidence: Dict = field(default_factory=dict)
    detected_at: datetime = field(default_factory=datetime.utcnow)
    resolved_at: Optional[datetime] = None

    def resolve(self) -> None:
        self.status = ExposureStatus.RESOLVED
        self.resolved_at = datetime.utcnow()

    def accept_risk(self) -> None:
        self.status = ExposureStatus.ACCEPTED_RISK

    def start_remediation(self) -> None:
        self.status = ExposureStatus.IN_REMEDIATION

    def is_active(self) -> bool:
        return self.status in (ExposureStatus.OPEN, ExposureStatus.IN_REMEDIATION)

    def to_dict(self) -> dict:
        return {
            "finding_id": self.finding_id,
            "asset_id": self.asset_id,
            "title": self.title,
            "category": self.category.value,
            "severity": self.severity.value,
            "status": self.status.value,
            "evidence": self.evidence,
            "detected_at": self.detected_at.isoformat(),
            "resolved_at": self.resolved_at.isoformat() if self.resolved_at else None,
        }


@dataclass
class RemediationTask:
    task_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    finding_id: str = ""
    assignee: str = ""
    due_date: Optional[str] = None
    status: RemediationStatus = RemediationStatus.PENDING
    notes: str = ""

    def to_dict(self) -> dict:
        return {
            "task_id": self.task_id,
            "finding_id": self.finding_id,
            "assignee": self.assignee,
            "due_date": self.due_date,
            "status": self.status.value,
            "notes": self.notes,
        }


@dataclass
class ExposureReport:
    report_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    generated_at: datetime = field(default_factory=datetime.utcnow)
    total_assets: int = 0
    internet_facing_assets: int = 0
    total_findings: int = 0
    active_findings: int = 0
    critical_findings: int = 0
    high_findings: int = 0
    remediation_coverage_pct: float = 0.0

    def phase63_score(self) -> float:
        deductions = (
            min(self.critical_findings * 6, 18)
            + min(self.high_findings * 3, 9)
        )
        if self.remediation_coverage_pct < 85.0:
            deductions += 3
        if self.internet_facing_assets > 0 and self.active_findings > 0:
            deductions += 2
        return max(0.0, round(25.0 - deductions, 2))

    def to_dict(self) -> dict:
        return {
            "report_id": self.report_id,
            "generated_at": self.generated_at.isoformat(),
            "total_assets": self.total_assets,
            "internet_facing_assets": self.internet_facing_assets,
            "total_findings": self.total_findings,
            "active_findings": self.active_findings,
            "critical_findings": self.critical_findings,
            "high_findings": self.high_findings,
            "remediation_coverage_pct": round(self.remediation_coverage_pct, 2),
            "phase63_score": self.phase63_score(),
        }


class AttackSurfaceManagementEngine:
    def __init__(self) -> None:
        self._assets: Dict[str, AttackSurfaceAsset] = {}
        self._findings: Dict[str, ExposureFinding] = {}
        self._tasks: Dict[str, RemediationTask] = {}

    def register_asset(self, asset: AttackSurfaceAsset) -> AttackSurfaceAsset:
        self._assets[asset.asset_id] = asset
        return asset

    def get_asset(self, asset_id: str) -> Optional[AttackSurfaceAsset]:
        return self._assets.get(asset_id)

    def assets(self) -> List[AttackSurfaceAsset]:
        return list(self._assets.values())

    def internet_facing_assets(self) -> List[AttackSurfaceAsset]:
        return [a for a in self._assets.values() if a.internet_facing]

    def add_exposure(self, finding: ExposureFinding) -> ExposureFinding:
        if finding.asset_id not in self._assets:
            raise KeyError(f"Unknown asset_id: {finding.asset_id}")
        self._findings[finding.finding_id] = finding
        return finding

    def get_finding(self, finding_id: str) -> Optional[ExposureFinding]:
        return self._findings.get(finding_id)

    def findings(self) -> List[ExposureFinding]:
        return list(self._findings.values())

    def exposures_by_severity(self, severity: ExposureSeverity) -> List[ExposureFinding]:
        return [f for f in self._findings.values() if f.severity == severity]

    def unresolved_exposures(self) -> List[ExposureFinding]:
        return [f for f in self._findings.values() if f.is_active()]

    def critical_exposures(self) -> List[ExposureFinding]:
        return self.exposures_by_severity(ExposureSeverity.CRITICAL)

    def findings_for_asset(self, asset_id: str) -> List[ExposureFinding]:
        return [f for f in self._findings.values() if f.asset_id == asset_id]

    def start_remediation(self, finding_id: str) -> bool:
        finding = self._findings.get(finding_id)
        if not finding:
            return False
        finding.start_remediation()
        return True

    def resolve_exposure(self, finding_id: str) -> bool:
        finding = self._findings.get(finding_id)
        if not finding:
            return False
        finding.resolve()
        return True

    def accept_risk(self, finding_id: str) -> bool:
        finding = self._findings.get(finding_id)
        if not finding:
            return False
        finding.accept_risk()
        return True

    def assign_remediation(self, finding_id: str, assignee: str, due_date: Optional[str] = None) -> Optional[RemediationTask]:
        if finding_id not in self._findings:
            return None
        task = RemediationTask(finding_id=finding_id, assignee=assignee, due_date=due_date)
        self._tasks[task.task_id] = task
        self.start_remediation(finding_id)
        return task

    def update_task_status(self, task_id: str, status: RemediationStatus, notes: str = "") -> bool:
        task = self._tasks.get(task_id)
        if not task:
            return False
        task.status = status
        if notes:
            task.notes = notes
        if status == RemediationStatus.DONE:
            self.resolve_exposure(task.finding_id)
        return True

    def remediation_tasks(self) -> List[RemediationTask]:
        return list(self._tasks.values())

    def remediation_coverage_pct(self) -> float:
        active_findings = self.unresolved_exposures()
        if not active_findings:
            return 100.0
        active_ids = {f.finding_id for f in active_findings}
        tasked = {t.finding_id for t in self._tasks.values() if t.finding_id in active_ids}
        return round(len(tasked) / len(active_ids) * 100.0, 2)

    def generate_report(self) -> ExposureReport:
        return ExposureReport(
            total_assets=len(self._assets),
            internet_facing_assets=len(self.internet_facing_assets()),
            total_findings=len(self._findings),
            active_findings=len(self.unresolved_exposures()),
            critical_findings=len(self.exposures_by_severity(ExposureSeverity.CRITICAL)),
            high_findings=len(self.exposures_by_severity(ExposureSeverity.HIGH)),
            remediation_coverage_pct=self.remediation_coverage_pct(),
        )

    def phase63_score(self) -> float:
        return self.generate_report().phase63_score()

    def summary(self) -> dict:
        report = self.generate_report()
        return {
            "status": "ok" if report.phase63_score() >= 18 else "attention_required",
            "total_assets": report.total_assets,
            "internet_facing_assets": report.internet_facing_assets,
            "total_findings": report.total_findings,
            "active_findings": report.active_findings,
            "critical_findings": report.critical_findings,
            "high_findings": report.high_findings,
            "remediation_coverage_pct": report.remediation_coverage_pct,
            "phase63_score": report.phase63_score(),
        }

    def persist_state(self, output_path: str = "artifacts/phase63/attack-surface-report.json") -> str:
        import os

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        data = {
            "phase": 63,
            "engine": "AttackSurfaceManagementEngine",
            "exported_at": datetime.utcnow().isoformat(),
            "summary": self.summary(),
            "assets": [a.to_dict() for a in self._assets.values()],
            "findings": [f.to_dict() for f in self._findings.values()],
            "tasks": [t.to_dict() for t in self._tasks.values()],
        }
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        return output_path


def make_asset(
    name: str,
    asset_type: AssetType = AssetType.API,
    environment: str = "production",
    internet_facing: bool = True,
    owner_team: str = "security",
    criticality: int = 3,
) -> AttackSurfaceAsset:
    return AttackSurfaceAsset(
        name=name,
        asset_type=asset_type,
        environment=environment,
        internet_facing=internet_facing,
        owner_team=owner_team,
        criticality=criticality,
    )


def make_exposure(
    asset_id: str,
    title: str,
    category: ExposureCategory = ExposureCategory.MISCONFIGURATION,
    severity: ExposureSeverity = ExposureSeverity.MEDIUM,
    evidence: Optional[Dict] = None,
) -> ExposureFinding:
    return ExposureFinding(
        asset_id=asset_id,
        title=title,
        category=category,
        severity=severity,
        evidence=evidence or {},
    )
