#!/usr/bin/env python3
"""
@file threat_hunt_orchestration_engine.py
@description Phase 64 — Threat Hunt Orchestration Engine
@purpose Automated proactive threat hunting and threat intelligence correlation
@since 2026-05-01

Automates threat hunting:
- Hunt campaign management
- Threat pattern detection
- IOC correlation and matching
- Threat intelligence aggregation
- Hunt timeline and evidence tracking
"""

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, List, Optional, Set
from uuid import uuid4


class HuntStatus(Enum):
    """Threat hunt campaign status"""
    PLANNED = "planned"
    ACTIVE = "active"
    ANALYZING = "analyzing"
    CONCLUDED = "concluded"
    ARCHIVED = "archived"


class FindingType(Enum):
    """Hunt finding classification"""
    CONFIRMED_THREAT = "confirmed_threat"
    SUSPICIOUS_ACTIVITY = "suspicious_activity"
    BENIGN = "benign"
    FALSE_POSITIVE = "false_positive"
    REQUIRES_INVESTIGATION = "requires_investigation"


class IOCType(Enum):
    """Indicator of Compromise type"""
    IP_ADDRESS = "ip_address"
    DOMAIN_NAME = "domain_name"
    EMAIL_ADDRESS = "email_address"
    FILE_HASH = "file_hash"
    REGISTRY_KEY = "registry_key"
    PROCESS_NAME = "process_name"
    URL = "url"
    CERTIFICATE = "certificate"


@dataclass
class IOC:
    """Indicator of Compromise"""
    ioc_id: str
    ioc_type: IOCType
    value: str
    source: str
    confidence: float  # 0-100
    first_seen: datetime = field(default_factory=datetime.utcnow)
    last_seen: datetime = field(default_factory=datetime.utcnow)
    detection_count: int = 0
    threat_name: str = ""

    def to_dict(self) -> Dict:
        return {
            "ioc_id": self.ioc_id,
            "ioc_type": self.ioc_type.value,
            "value": self.value,
            "source": self.source,
            "confidence": self.confidence,
            "detection_count": self.detection_count,
            "age_days": (datetime.utcnow() - self.first_seen).days
        }


@dataclass
class HuntFinding:
    """Finding from threat hunt"""
    finding_id: str
    hunt_id: str
    finding_type: FindingType
    description: str
    severity: str  # critical, high, medium, low
    assets_affected: List[str] = field(default_factory=list)
    iocs_matched: List[str] = field(default_factory=list)
    found_at: datetime = field(default_factory=datetime.utcnow)
    evidence: Dict[str, str] = field(default_factory=dict)
    verified: bool = False

    def to_dict(self) -> Dict:
        return {
            "finding_id": self.finding_id,
            "finding_type": self.finding_type.value,
            "description": self.description,
            "severity": self.severity,
            "assets_affected": len(self.assets_affected),
            "iocs_matched": len(self.iocs_matched),
            "found_at": self.found_at.isoformat(),
            "verified": self.verified
        }


@dataclass
class ThreatCampaign:
    """Identified threat campaign"""
    campaign_id: str
    name: str
    attributed_actor: str = ""
    ttps: List[str] = field(default_factory=list)  # Tactics, Techniques, Procedures
    iocs: List[str] = field(default_factory=list)  # IOC IDs
    affected_assets: Set[str] = field(default_factory=set)
    first_observed: datetime = field(default_factory=datetime.utcnow)
    last_observed: Optional[datetime] = None
    severity: str = "medium"

    def to_dict(self) -> Dict:
        return {
            "campaign_id": self.campaign_id,
            "name": self.name,
            "attributed_actor": self.attributed_actor,
            "ttps": len(self.ttps),
            "iocs": len(self.iocs),
            "affected_assets": len(self.affected_assets),
            "severity": self.severity
        }


@dataclass
class HuntCampaign:
    """Threat hunt campaign"""
    hunt_id: str
    name: str
    hunt_type: str  # "ioc_search", "behavioral", "threat_actor", "vulnerability"
    status: HuntStatus = HuntStatus.PLANNED
    created_by: str = "hunt_engine"
    created_at: datetime = field(default_factory=datetime.utcnow)
    started_at: Optional[datetime] = None
    concluded_at: Optional[datetime] = None
    target_systems: List[str] = field(default_factory=list)
    findings: List[str] = field(default_factory=list)  # finding IDs
    threat_campaigns: List[str] = field(default_factory=list)  # campaign IDs
    tags: Dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> Dict:
        return {
            "hunt_id": self.hunt_id,
            "name": self.name,
            "hunt_type": self.hunt_type,
            "status": self.status.value,
            "findings": len(self.findings),
            "threat_campaigns": len(self.threat_campaigns),
            "duration_hours": self._duration_hours()
        }

    def _duration_hours(self) -> Optional[float]:
        if self.started_at and self.concluded_at:
            return (self.concluded_at - self.started_at).total_seconds() / 3600
        return None


@dataclass
class HuntReport:
    """Threat hunt results report"""
    report_id: str
    generated_at: datetime
    total_hunts: int
    active_hunts: int
    total_findings: int
    confirmed_threats: int
    suspicious_activities: int
    unique_iocs: int
    threat_campaigns_identified: int
    avg_hunt_duration_hours: float
    threat_detection_rate: float

    def to_dict(self) -> Dict:
        return {
            "report_id": self.report_id,
            "generated_at": self.generated_at.isoformat(),
            "total_hunts": self.total_hunts,
            "active_hunts": self.active_hunts,
            "total_findings": self.total_findings,
            "confirmed_threats": self.confirmed_threats,
            "suspicious_activities": self.suspicious_activities,
            "unique_iocs": self.unique_iocs,
            "threat_campaigns": self.threat_campaigns_identified,
            "avg_hunt_duration": round(self.avg_hunt_duration_hours, 2),
            "threat_detection_rate": round(self.threat_detection_rate, 2),
            "phase64_score": self._calculate_phase64_score()
        }

    def _calculate_phase64_score(self) -> float:
        if self.total_hunts == 0:
            return 0.0
        threat_rate = (self.confirmed_threats / max(1, self.total_findings)) if self.total_findings > 0 else 0
        ioc_coverage = min(self.unique_iocs / 100, 1.0)  # 100 IOCs = 100% score
        detection_rate = self.threat_detection_rate / 100.0
        return 25 * (threat_rate * 0.3 + ioc_coverage * 0.4 + detection_rate * 0.3)


class ThreatHuntOrchestrationEngine:
    """Orchestrates proactive threat hunting operations"""

    def __init__(self):
        self.hunts: Dict[str, HuntCampaign] = {}
        self.iocs: Dict[str, IOC] = {}
        self.findings: Dict[str, HuntFinding] = {}
        self.campaigns: Dict[str, ThreatCampaign] = {}

    def create_hunt(
        self,
        name: str,
        hunt_type: str,
        target_systems: List[str] = None
    ) -> HuntCampaign:
        """Create a new threat hunt campaign"""
        hunt_id = f"HNT-{str(uuid4())[:8].upper()}"
        hunt = HuntCampaign(
            hunt_id=hunt_id,
            name=name,
            hunt_type=hunt_type,
            target_systems=target_systems or []
        )
        self.hunts[hunt_id] = hunt
        return hunt

    def start_hunt(self, hunt_id: str) -> HuntCampaign:
        """Start a hunt campaign"""
        if hunt_id not in self.hunts:
            raise KeyError(f"Hunt {hunt_id} not found")
        hunt = self.hunts[hunt_id]
        hunt.status = HuntStatus.ACTIVE
        hunt.started_at = datetime.utcnow()
        return hunt

    def conclude_hunt(self, hunt_id: str) -> HuntCampaign:
        """Conclude a hunt campaign"""
        if hunt_id not in self.hunts:
            raise KeyError(f"Hunt {hunt_id} not found")
        hunt = self.hunts[hunt_id]
        hunt.status = HuntStatus.CONCLUDED
        hunt.concluded_at = datetime.utcnow()
        return hunt

    def register_ioc(
        self,
        ioc_type: IOCType,
        value: str,
        source: str,
        confidence: float = 80.0,
        threat_name: str = ""
    ) -> IOC:
        """Register an Indicator of Compromise"""
        ioc_id = f"IOC-{str(uuid4())[:8].upper()}"
        ioc = IOC(
            ioc_id=ioc_id,
            ioc_type=ioc_type,
            value=value,
            source=source,
            confidence=confidence,
            threat_name=threat_name
        )
        self.iocs[ioc_id] = ioc
        return ioc

    def record_ioc_detection(self, ioc_id: str, asset: str = "") -> IOC:
        """Record detection of an IOC"""
        if ioc_id not in self.iocs:
            raise KeyError(f"IOC {ioc_id} not found")
        ioc = self.iocs[ioc_id]
        ioc.detection_count += 1
        ioc.last_seen = datetime.utcnow()
        return ioc

    def add_finding(
        self,
        hunt_id: str,
        finding_type: FindingType,
        description: str,
        severity: str,
        assets_affected: List[str] = None
    ) -> HuntFinding:
        """Add finding to hunt"""
        if hunt_id not in self.hunts:
            raise KeyError(f"Hunt {hunt_id} not found")
        
        finding_id = f"FND-{str(uuid4())[:8].upper()}"
        finding = HuntFinding(
            finding_id=finding_id,
            hunt_id=hunt_id,
            finding_type=finding_type,
            description=description,
            severity=severity,
            assets_affected=assets_affected or []
        )
        self.findings[finding_id] = finding
        self.hunts[hunt_id].findings.append(finding_id)
        return finding

    def link_ioc_to_finding(self, finding_id: str, ioc_id: str) -> HuntFinding:
        """Link IOC to a finding"""
        if finding_id not in self.findings:
            raise KeyError(f"Finding {finding_id} not found")
        if ioc_id not in self.iocs:
            raise KeyError(f"IOC {ioc_id} not found")
        
        finding = self.findings[finding_id]
        finding.iocs_matched.append(ioc_id)
        return finding

    def identify_campaign(
        self,
        name: str,
        attributed_actor: str = "",
        severity: str = "medium"
    ) -> ThreatCampaign:
        """Identify a threat campaign"""
        campaign_id = f"CAM-{str(uuid4())[:8].upper()}"
        campaign = ThreatCampaign(
            campaign_id=campaign_id,
            name=name,
            attributed_actor=attributed_actor,
            severity=severity
        )
        self.campaigns[campaign_id] = campaign
        return campaign

    def link_campaign_to_hunt(self, hunt_id: str, campaign_id: str) -> HuntCampaign:
        """Link threat campaign to hunt"""
        if hunt_id not in self.hunts:
            raise KeyError(f"Hunt {hunt_id} not found")
        if campaign_id not in self.campaigns:
            raise KeyError(f"Campaign {campaign_id} not found")
        
        hunt = self.hunts[hunt_id]
        hunt.threat_campaigns.append(campaign_id)
        return hunt

    def get_hunt(self, hunt_id: str) -> HuntCampaign:
        """Retrieve hunt by ID"""
        if hunt_id not in self.hunts:
            raise KeyError(f"Hunt {hunt_id} not found")
        return self.hunts[hunt_id]

    def hunts_by_status(self, status: HuntStatus) -> List[HuntCampaign]:
        """Get hunts by status"""
        return [h for h in self.hunts.values() if h.status == status]

    def findings_by_type(self, finding_type: FindingType) -> List[HuntFinding]:
        """Get findings by type"""
        return [f for f in self.findings.values() if f.finding_type == finding_type]

    def iocs_by_type(self, ioc_type: IOCType) -> List[IOC]:
        """Get IOCs by type"""
        return [ioc for ioc in self.iocs.values() if ioc.ioc_type == ioc_type]

    def high_confidence_iocs(self, min_confidence: float = 85.0) -> List[IOC]:
        """Get high confidence IOCs"""
        return [ioc for ioc in self.iocs.values() if ioc.confidence >= min_confidence]

    def generate_report(self) -> HuntReport:
        """Generate threat hunt report"""
        hunts = list(self.hunts.values())
        active = [h for h in hunts if h.status == HuntStatus.ACTIVE]
        findings_list = list(self.findings.values())
        confirmed = [f for f in findings_list if f.finding_type == FindingType.CONFIRMED_THREAT]
        suspicious = [f for f in findings_list if f.finding_type == FindingType.SUSPICIOUS_ACTIVITY]
        
        durations = [h._duration_hours() for h in hunts if h._duration_hours()]
        avg_duration = sum(durations) / len(durations) if durations else 0
        
        detection_rate = 0.0
        if hunts:
            detected = len([h for h in hunts if h.findings])
            detection_rate = (detected / len(hunts)) * 100
        
        report = HuntReport(
            report_id=f"HTR-{str(uuid4())[:8].upper()}",
            generated_at=datetime.utcnow(),
            total_hunts=len(hunts),
            active_hunts=len(active),
            total_findings=len(findings_list),
            confirmed_threats=len(confirmed),
            suspicious_activities=len(suspicious),
            unique_iocs=len(self.iocs),
            threat_campaigns_identified=len(self.campaigns),
            avg_hunt_duration_hours=avg_duration,
            threat_detection_rate=detection_rate
        )
        return report

    def summary(self) -> Dict:
        """Get engine summary"""
        return {
            "total_hunts": len(self.hunts),
            "active_hunts": len(self.hunts_by_status(HuntStatus.ACTIVE)),
            "concluded_hunts": len(self.hunts_by_status(HuntStatus.CONCLUDED)),
            "total_findings": len(self.findings),
            "confirmed_threats": len(self.findings_by_type(FindingType.CONFIRMED_THREAT)),
            "suspicious_activities": len(self.findings_by_type(FindingType.SUSPICIOUS_ACTIVITY)),
            "total_iocs": len(self.iocs),
            "high_confidence_iocs": len(self.high_confidence_iocs()),
            "threat_campaigns": len(self.campaigns),
            "phase64_score": self.phase64_score()
        }

    def phase64_score(self) -> float:
        """Calculate Phase 64 gate contribution (0-25)"""
        report = self.generate_report()
        return report._calculate_phase64_score()


def make_hunt(
    name: str = "Test Hunt",
    hunt_type: str = "ioc_search"
) -> HuntCampaign:
    """Helper to create test hunt"""
    return HuntCampaign(
        hunt_id=f"HNT-{str(uuid4())[:8].upper()}",
        name=name,
        hunt_type=hunt_type
    )


def hunt_orchestration_score(engine: ThreatHuntOrchestrationEngine) -> float:
    """Helper to get phase64_score"""
    return engine.phase64_score()
