#!/usr/bin/env python3
"""
@module advanced_threat_hunting
@description Phase 43: Advanced Threat Hunting & Autonomous Response Orchestration
@purpose Orchestrates advanced threat hunting with autonomous response capabilities
@since 2026-05-01

Consolidates threat intelligence (Phase 40), incident response (Phase 41), and
compliance automation (Phase 42) into comprehensive automated threat hunting.
"""

import json
import os
from pathlib import Path
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict, field
from enum import Enum
from typing import Dict, List, Optional, Set, Tuple
from statistics import mean


class HuntingStatus(Enum):
    """Threat hunting status"""
    ACTIVE = "active"
    PAUSED = "paused"
    COMPLETED = "completed"
    ESCALATED = "escalated"


class ThreatLevel(Enum):
    """Threat severity levels"""
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"


class HuntingStrategy(Enum):
    """Threat hunting strategies"""
    INDICATOR_BASED = "indicator_based"  # Hunt for known IOCs
    BEHAVIOR_BASED = "behavior_based"    # Hunt for suspicious behaviors
    ANOMALY_BASED = "anomaly_based"      # Hunt for deviations from baseline
    THREAT_ACTOR = "threat_actor"        # Hunt for specific threat actor patterns
    VULNERABILITY_BASED = "vulnerability_based"  # Hunt for exploit attempts


@dataclass
class ThreatIndicator:
    """Threat indicator (IOC)"""
    indicator_id: str
    indicator_type: str          # ip|domain|hash|email|url|file|registry|process
    indicator_value: str
    threat_level: str            # critical|high|medium|low
    source_phase: int
    source_reference: str
    confidence: float            # 0-1
    detected_at: float = field(default_factory=lambda: datetime.now().timestamp())
    enrichment_data: Dict = field(default_factory=dict)


@dataclass
class HuntingPlaybook:
    """Threat hunting playbook"""
    playbook_id: str
    name: str
    description: str
    strategy: str                # HuntingStrategy
    targets: List[str]           # What to hunt for
    detection_rules: List[str]   # Rules to detect indicators
    expected_impact: str         # Critical threat, high-value target, etc.
    success_criteria: str
    estimated_duration: int      # Seconds


@dataclass
class HuntingCampaign:
    """Active threat hunting campaign"""
    campaign_id: str
    playbook_id: str
    status: str                  # HuntingStatus
    started_at: float
    completed_at: Optional[float] = None
    indicators_found: int = 0
    threats_identified: int = 0
    responses_executed: int = 0
    hunt_success_rate: float = 0.0  # 0-1


@dataclass
class HuntingFinding:
    """Finding from threat hunt"""
    finding_id: str
    campaign_id: str
    finding_type: str           # indicator_match|behavior_anomaly|policy_violation|suspicious_activity
    description: str
    threat_indicators: List[str]  # Related IOCs
    evidence: Dict              # Forensic evidence
    severity: str               # critical|high|medium|low
    confidence: float           # 0-1
    found_at: float = field(default_factory=lambda: datetime.now().timestamp())
    response_status: str = "pending"  # pending|in_progress|resolved|escalated


class AdvancedThreatHunting:
    """Advanced threat hunting orchestration engine"""

    def __init__(self, state_dir: Optional[str] = None):
        """Initialize threat hunting engine"""
        if state_dir is None:
            state_dir = Path(__file__).parent.parent.parent / "artifacts" / "phase43"
        self.state_dir = str(state_dir)
        Path(self.state_dir).mkdir(parents=True, exist_ok=True)

        self.indicators: Dict[str, ThreatIndicator] = {}
        self.playbooks: Dict[str, HuntingPlaybook] = {}
        self.campaigns: Dict[str, HuntingCampaign] = {}
        self.findings: Dict[str, HuntingFinding] = {}
        self.phase_data: Dict[int, Dict] = {}
        self.load_state()

    def register_indicator(
        self,
        indicator_type: str,
        indicator_value: str,
        threat_level: str,
        source_phase: int,
        source_reference: str,
        confidence: float
    ) -> ThreatIndicator:
        """Register threat indicator (IOC)"""
        indicator_id = f"indicator_{datetime.now().timestamp():.6f}".replace(".", "")
        indicator = ThreatIndicator(
            indicator_id=indicator_id,
            indicator_type=indicator_type,
            indicator_value=indicator_value,
            threat_level=threat_level,
            source_phase=source_phase,
            source_reference=source_reference,
            confidence=confidence
        )
        self.indicators[indicator_id] = indicator
        return indicator

    def ingest_phase_data(self, phase_id: int, phase_name: str, metrics: Dict) -> None:
        """Ingest threat hunting data from upstream phases"""
        self.phase_data[phase_id] = {
            "phase_name": phase_name,
            "metrics": metrics,
            "ingested_at": datetime.now().timestamp()
        }

    def create_hunting_playbook(
        self,
        name: str,
        description: str,
        strategy: str,
        targets: List[str],
        detection_rules: List[str],
        expected_impact: str,
        success_criteria: str,
        estimated_duration: int = 3600
    ) -> HuntingPlaybook:
        """Create threat hunting playbook"""
        playbook_id = f"playbook_{datetime.now().timestamp():.6f}".replace(".", "")
        playbook = HuntingPlaybook(
            playbook_id=playbook_id,
            name=name,
            description=description,
            strategy=strategy,
            targets=targets,
            detection_rules=detection_rules,
            expected_impact=expected_impact,
            success_criteria=success_criteria,
            estimated_duration=estimated_duration
        )
        self.playbooks[playbook_id] = playbook
        return playbook

    def start_hunting_campaign(
        self,
        playbook_id: str,
        initial_threat_level: Optional[str] = None
    ) -> Optional[HuntingCampaign]:
        """Start new threat hunting campaign"""
        if playbook_id not in self.playbooks:
            return None

        campaign_id = f"campaign_{datetime.now().timestamp():.6f}".replace(".", "")
        campaign = HuntingCampaign(
            campaign_id=campaign_id,
            playbook_id=playbook_id,
            status=HuntingStatus.ACTIVE.value,
            started_at=datetime.now().timestamp()
        )
        self.campaigns[campaign_id] = campaign
        return campaign

    def complete_campaign(self, campaign_id: str) -> Optional[HuntingCampaign]:
        """Complete hunting campaign"""
        if campaign_id not in self.campaigns:
            return None

        campaign = self.campaigns[campaign_id]
        campaign.completed_at = datetime.now().timestamp()
        campaign.status = HuntingStatus.COMPLETED.value
        return campaign

    def log_finding(
        self,
        campaign_id: str,
        finding_type: str,
        description: str,
        threat_indicators: List[str],
        evidence: Dict,
        severity: str,
        confidence: float
    ) -> HuntingFinding:
        """Log hunting finding"""
        finding_id = f"finding_{datetime.now().timestamp():.6f}".replace(".", "")
        finding = HuntingFinding(
            finding_id=finding_id,
            campaign_id=campaign_id,
            finding_type=finding_type,
            description=description,
            threat_indicators=threat_indicators,
            evidence=evidence,
            severity=severity,
            confidence=confidence
        )
        self.findings[finding_id] = finding

        # Update campaign counters
        if campaign_id in self.campaigns:
            campaign = self.campaigns[campaign_id]
            campaign.indicators_found += 1
            if severity in ["critical", "high"]:
                campaign.threats_identified += 1

        return finding

    def execute_response(
        self,
        finding_id: str,
        response_action: str,
        dry_run: bool = False
    ) -> bool:
        """Execute response action for finding"""
        if finding_id not in self.findings:
            return False

        finding = self.findings[finding_id]
        finding.response_status = "in_progress" if not dry_run else "pending"

        # Link to campaign
        if finding.campaign_id in self.campaigns:
            campaign = self.campaigns[finding.campaign_id]
            if not dry_run:
                campaign.responses_executed += 1

        return True

    def calculate_hunting_success_rate(self) -> float:
        """Calculate overall hunting success rate"""
        if not self.campaigns:
            return 0.0

        success_rates = []
        for campaign in self.campaigns.values():
            if campaign.status == HuntingStatus.COMPLETED.value and campaign.threats_identified > 0:
                # Success = threats identified / total indicators searched
                if self.indicators:
                    rate = min(1.0, campaign.threats_identified / len(self.indicators))
                    success_rates.append(rate)

        if success_rates:
            return mean(success_rates)
        return 0.0

    def hunting_score(self) -> float:
        """Calculate threat hunting score for Phase 31 (0-25 pts)"""
        success_rate = self.calculate_hunting_success_rate()
        campaign_count = len([c for c in self.campaigns.values() if c.status == HuntingStatus.COMPLETED.value])
        critical_threats = len([f for f in self.findings.values() if f.severity == "critical"])

        # Scoring: success rate (40%) + campaigns completed (40%) + critical threats found (20%)
        score = (success_rate * 10) + (min(10, campaign_count * 2)) + (min(5, critical_threats * 0.5))
        return min(25.0, score)

    def identify_risk_areas(self) -> List[str]:
        """Identify high-risk areas from findings"""
        risk_areas = []
        
        critical_findings = [f for f in self.findings.values() if f.severity == "critical"]
        if critical_findings:
            risk_areas.append(f"{len(critical_findings)} critical findings require immediate attention")

        unresolved = [f for f in self.findings.values() if f.response_status == "pending"]
        if unresolved:
            risk_areas.append(f"{len(unresolved)} findings awaiting response")

        return risk_areas

    def generate_hunting_report(self) -> Dict:
        """Generate comprehensive threat hunting report"""
        completed_campaigns = [c for c in self.campaigns.values() if c.status == HuntingStatus.COMPLETED.value]
        total_findings = len(self.findings)
        critical_findings = len([f for f in self.findings.values() if f.severity == "critical"])
        high_findings = len([f for f in self.findings.values() if f.severity == "high"])

        return {
            "report_id": f"report_{datetime.now().timestamp():.0f}",
            "timestamp": datetime.now().timestamp(),
            "total_campaigns": len(self.campaigns),
            "completed_campaigns": len(completed_campaigns),
            "total_indicators": len(self.indicators),
            "total_findings": total_findings,
            "critical_findings": critical_findings,
            "high_findings": high_findings,
            "hunting_success_rate": self.calculate_hunting_success_rate(),
            "threat_hunting_score": self.hunting_score(),
            "risk_areas": self.identify_risk_areas(),
            "recommendations": self._generate_recommendations()
        }

    def _generate_recommendations(self) -> List[str]:
        """Generate recommendations based on findings"""
        recommendations = []

        if not self.campaigns:
            recommendations.append("Initiate first threat hunting campaign")

        critical_count = len([f for f in self.findings.values() if f.severity == "critical"])
        if critical_count > 0:
            recommendations.append(f"Immediately investigate and respond to {critical_count} critical findings")

        unresolved_count = len([f for f in self.findings.values() if f.response_status == "pending"])
        if unresolved_count > 0:
            recommendations.append(f"Execute response actions for {unresolved_count} pending findings")

        if len(self.indicators) < 10:
            recommendations.append("Expand threat indicator database")

        return recommendations

    def summary(self) -> Dict:
        """Generate executive summary"""
        return {
            "total_indicators": len(self.indicators),
            "total_campaigns": len(self.campaigns),
            "total_findings": len(self.findings),
            "hunting_success_rate": f"{self.calculate_hunting_success_rate() * 100:.1f}%",
            "threat_hunting_score": f"{self.hunting_score():.1f}/25.0",
            "risk_areas": self.identify_risk_areas(),
            "phase_integrations": list(self.phase_data.keys())
        }

    def persist_state(self) -> None:
        """Persist state to disk"""
        Path(self.state_dir).mkdir(parents=True, exist_ok=True)

        with open(f"{self.state_dir}/indicators.json", "w") as f:
            json.dump({k: asdict(v) for k, v in self.indicators.items()}, f, indent=2)

        with open(f"{self.state_dir}/campaigns.json", "w") as f:
            json.dump({k: asdict(v) for k, v in self.campaigns.items()}, f, indent=2)

        with open(f"{self.state_dir}/findings.json", "w") as f:
            json.dump({k: asdict(v) for k, v in self.findings.items()}, f, indent=2)

    def load_state(self) -> None:
        """Load state from disk"""
        try:
            with open(f"{self.state_dir}/indicators.json") as f:
                data = json.load(f)
                for iid, idata in data.items():
                    indicator = ThreatIndicator(**idata)
                    self.indicators[iid] = indicator
        except FileNotFoundError:
            pass

        try:
            with open(f"{self.state_dir}/campaigns.json") as f:
                data = json.load(f)
                for cid, cdata in data.items():
                    campaign = HuntingCampaign(**cdata)
                    self.campaigns[cid] = campaign
        except FileNotFoundError:
            pass

        try:
            with open(f"{self.state_dir}/findings.json") as f:
                data = json.load(f)
                for fid, fdata in data.items():
                    finding = HuntingFinding(**fdata)
                    self.findings[fid] = finding
        except FileNotFoundError:
            pass
