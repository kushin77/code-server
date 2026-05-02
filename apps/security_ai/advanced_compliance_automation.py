#!/usr/bin/env python3
"""
@module advanced_compliance_automation
@description Phase 42: Advanced Compliance Automation & Continuous Compliance
@purpose Automates compliance enforcement and continuous compliance monitoring
@since 2026-05-01

Combines data from all upstream phases to maintain compliance at scale.
"""

import json
import os
from pathlib import Path
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict, field
from enum import Enum
from typing import Dict, List, Optional, Set
from statistics import mean


class ComplianceFramework(Enum):
    """Compliance frameworks supported"""
    SOC2 = "soc2"
    PCI_DSS = "pci_dss"
    HIPAA = "hipaa"
    GDPR = "gdpr"
    ISO27001 = "iso27001"
    NIST = "nist"


class ComplianceDomain(Enum):
    """Compliance domains"""
    ACCESS_CONTROL = "access_control"
    DATA_PROTECTION = "data_protection"
    INCIDENT_RESPONSE = "incident_response"
    AUDIT_LOGGING = "audit_logging"
    VULNERABILITY_MANAGEMENT = "vulnerability_management"
    RISK_ASSESSMENT = "risk_assessment"


@dataclass
class ComplianceControl:
    """Single compliance control"""
    control_id: str
    framework: str                # ComplianceFramework
    domain: str                   # ComplianceDomain
    description: str
    is_implemented: bool = False
    is_effective: bool = False
    effectiveness_score: float = 0.0  # 0-100
    last_tested: Optional[float] = None
    next_test_due: Optional[float] = None


@dataclass
class ComplianceViolation:
    """Documented compliance violation"""
    violation_id: str
    control_id: str
    severity: str                 # critical|high|medium|low
    description: str
    detected_at: float = field(default_factory=lambda: datetime.now().timestamp())
    remediated_at: Optional[float] = None
    remediation_plan: Optional[str] = None


@dataclass
class ComplianceReport:
    """Compliance assessment report"""
    report_id: str
    framework: str
    assessment_date: float
    total_controls: int
    implemented_controls: int
    effective_controls: int
    compliance_score: float        # 0-100
    critical_violations: int
    high_violations: int
    medium_violations: int
    low_violations: int
    recommendations: List[str] = field(default_factory=list)
    phase_contributions: Dict[int, str] = field(default_factory=dict)


class AdvancedComplianceAutomation:
    """Advanced compliance automation and continuous compliance engine"""

    def __init__(self, state_dir: str = "artifacts/phase42"):
        """Initialize compliance automation engine"""
        self.state_dir = state_dir
        Path(self.state_dir).mkdir(parents=True, exist_ok=True)
        
        self.controls: Dict[str, ComplianceControl] = {}
        self.violations: Dict[str, ComplianceViolation] = {}
        self.reports: List[ComplianceReport] = []
        self.phase_data: Dict[int, Dict] = {}
        self.load_state()

    def register_control(
        self,
        control_id: str,
        framework: str,
        domain: str,
        description: str
    ) -> ComplianceControl:
        """Register a compliance control"""
        control = ComplianceControl(
            control_id=control_id,
            framework=framework,
            domain=domain,
            description=description,
            is_implemented=False,
            is_effective=False
        )
        self.controls[control_id] = control
        return control

    def ingest_phase_data(self, phase_id: int, phase_name: str, metrics: Dict) -> None:
        """Ingest compliance-relevant data from upstream phases"""
        self.phase_data[phase_id] = {
            "phase_name": phase_name,
            "metrics": metrics,
            "timestamp": datetime.now().timestamp()
        }

    def assess_control_implementation(self, control_id: str, is_implemented: bool) -> None:
        """Assess whether a control is implemented"""
        if control_id in self.controls:
            self.controls[control_id].is_implemented = is_implemented
            self.controls[control_id].last_tested = datetime.now().timestamp()

    def assess_control_effectiveness(self, control_id: str, effectiveness_score: float) -> None:
        """Assess control effectiveness (0-100 scale)"""
        if control_id in self.controls:
            self.controls[control_id].effectiveness_score = min(100, max(0, effectiveness_score))
            self.controls[control_id].is_effective = effectiveness_score >= 70.0

    def log_violation(
        self,
        control_id: str,
        severity: str,
        description: str,
        source_phase: Optional[int] = None
    ) -> ComplianceViolation:
        """Log a compliance violation"""
        violation_id = f"violation_{datetime.now().timestamp():.6f}".replace(".", "")
        violation = ComplianceViolation(
            violation_id=violation_id,
            control_id=control_id,
            severity=severity,
            description=description
        )
        self.violations[violation_id] = violation
        return violation

    def remediate_violation(
        self,
        violation_id: str,
        remediation_plan: str
    ) -> Optional[ComplianceViolation]:
        """Record violation remediation"""
        if violation_id not in self.violations:
            return None
        
        violation = self.violations[violation_id]
        violation.remediation_plan = remediation_plan
        violation.remediated_at = datetime.now().timestamp()
        return violation

    def calculate_framework_compliance(self, framework: str) -> float:
        """
        Calculate compliance score for a framework (0-100).
        Based on: (implemented + effective) controls / total controls
        """
        framework_controls = [
            c for c in self.controls.values()
            if c.framework == framework
        ]
        
        if not framework_controls:
            return 0.0
        
        implemented = sum(1 for c in framework_controls if c.is_implemented)
        effective = sum(1 for c in framework_controls if c.is_effective)
        
        # Score: 50% for implementation, 50% for effectiveness
        implementation_score = (implemented / len(framework_controls)) * 50
        effectiveness_score = (effective / len(framework_controls)) * 50
        
        return implementation_score + effectiveness_score

    def _identify_risk_areas(self) -> List[str]:
        """Identify areas of compliance risk"""
        risks = []
        
        # Find unimplemented controls
        unimplemented = [c for c in self.controls.values() if not c.is_implemented]
        if len(unimplemented) > 0:
            risks.append(f"{len(unimplemented)} controls not yet implemented")
        
        # Find ineffective controls
        ineffective = [c for c in self.controls.values() if c.is_implemented and not c.is_effective]
        if len(ineffective) > 0:
            risks.append(f"{len(ineffective)} implemented controls are not effective")
        
        # Find critical violations
        critical_violations = [v for v in self.violations.values() if v.severity == "critical" and v.remediated_at is None]
        if len(critical_violations) > 0:
            risks.append(f"{len(critical_violations)} critical violations unresolved")
        
        # Find overdue assessments
        now = datetime.now().timestamp()
        stale_controls = [c for c in self.controls.values() if c.last_tested and (now - c.last_tested) > 2592000]  # 30 days
        if len(stale_controls) > 0:
            risks.append(f"{len(stale_controls)} controls not tested in 30+ days")
        
        return risks

    def _generate_recommendations(self) -> List[str]:
        """Generate compliance improvement recommendations"""
        recommendations = []
        
        # Implementation recommendations
        unimplemented = [c for c in self.controls.values() if not c.is_implemented]
        if unimplemented:
            recommendations.append(f"Implement {len(unimplemented)} outstanding controls")
        
        # Effectiveness recommendations
        ineffective = [c for c in self.controls.values() if c.is_implemented and not c.is_effective]
        if ineffective:
            recommendations.append(f"Strengthen {len(ineffective)} ineffective controls")
        
        # Remediation recommendations
        open_violations = [v for v in self.violations.values() if v.remediated_at is None]
        if open_violations:
            recommendations.append(f"Remediate {len(open_violations)} open violations")
        
        # Phase integration recommendations
        if 37 in self.phase_data and self.phase_data[37].get("metrics", {}).get("response_time_avg", 0) > 1000:
            recommendations.append("Improve incident response time via Phase 37")
        
        if 38 in self.phase_data and self.phase_data[38].get("metrics", {}).get("anomalies_detected", 0) > 10:
            recommendations.append("Investigate behavioral anomalies from Phase 38")
        
        return recommendations

    def generate_compliance_report(self, framework: str) -> ComplianceReport:
        """Generate comprehensive compliance report"""
        framework_controls = [c for c in self.controls.values() if c.framework == framework]
        
        implemented = sum(1 for c in framework_controls if c.is_implemented)
        effective = sum(1 for c in framework_controls if c.is_effective)
        
        compliance_score = self.calculate_framework_compliance(framework)
        
        # Count violations by severity
        critical_vios = sum(1 for v in self.violations.values() if v.severity == "critical" and v.remediated_at is None)
        high_vios = sum(1 for v in self.violations.values() if v.severity == "high" and v.remediated_at is None)
        medium_vios = sum(1 for v in self.violations.values() if v.severity == "medium" and v.remediated_at is None)
        low_vios = sum(1 for v in self.violations.values() if v.severity == "low" and v.remediated_at is None)
        
        report = ComplianceReport(
            report_id=f"report_{datetime.now().timestamp():.0f}",
            framework=framework,
            assessment_date=datetime.now().timestamp(),
            total_controls=len(framework_controls),
            implemented_controls=implemented,
            effective_controls=effective,
            compliance_score=compliance_score,
            critical_violations=critical_vios,
            high_violations=high_vios,
            medium_violations=medium_vios,
            low_violations=low_vios,
            recommendations=self._generate_recommendations(),
            phase_contributions={
                30: "Threat detection baseline",
                31: "Compliance gate scoring",
                34: "Resilience controls",
                36: "Policy enforcement",
                41: "Remediation orchestration"
            }
        )
        
        self.reports.append(report)
        return report

    def compliance_score(self) -> float:
        """
        Calculate overall compliance score (0-25 pts for compliance gate).
        Based on average framework compliance across all registered frameworks.
        """
        framework_scores = []
        for framework in set(c.framework for c in self.controls.values()):
            score = self.calculate_framework_compliance(framework)
            framework_scores.append(score)
        
        if not framework_scores:
            return 0.0
        
        avg_compliance = mean(framework_scores)
        
        # Convert 0-100 scale to 0-25 pts
        return (avg_compliance / 100.0) * 25.0

    def summary(self) -> Dict:
        """Generate compliance automation summary"""
        total_controls = len(self.controls)
        implemented = sum(1 for c in self.controls.values() if c.is_implemented)
        effective = sum(1 for c in self.controls.values() if c.is_effective)
        
        open_violations = [v for v in self.violations.values() if v.remediated_at is None]
        remediated_violations = [v for v in self.violations.values() if v.remediated_at is not None]
        
        return {
            "timestamp": datetime.now().isoformat(),
            "total_controls": total_controls,
            "implemented_controls": implemented,
            "effective_controls": effective,
            "implementation_rate": (implemented / total_controls * 100) if total_controls > 0 else 0.0,
            "effectiveness_rate": (effective / total_controls * 100) if total_controls > 0 else 0.0,
            "frameworks_covered": list(set(c.framework for c in self.controls.values())),
            "domains_covered": list(set(c.domain for c in self.controls.values())),
            "total_violations": len(self.violations),
            "open_violations": len(open_violations),
            "remediated_violations": len(remediated_violations),
            "critical_violations": sum(1 for v in open_violations if v.severity == "critical"),
            "risk_areas": self._identify_risk_areas(),
            "compliance_score": self.compliance_score(),
            "recent_reports": len([r for r in self.reports if (datetime.now().timestamp() - r.assessment_date) < 86400])  # Last 24h
        }

    def persist_state(self) -> None:
        """Persist engine state to disk"""
        controls_file = os.path.join(self.state_dir, "controls.json")
        with open(controls_file, "w") as f:
            json.dump({k: asdict(v) for k, v in self.controls.items()}, f, indent=2)

        violations_file = os.path.join(self.state_dir, "violations.json")
        with open(violations_file, "w") as f:
            json.dump({k: asdict(v) for k, v in self.violations.items()}, f, indent=2)

        reports_file = os.path.join(self.state_dir, "reports.json")
        with open(reports_file, "w") as f:
            json.dump([asdict(r) for r in self.reports], f, indent=2)

    def load_state(self) -> None:
        """Load previous engine state"""
        controls_file = os.path.join(self.state_dir, "controls.json")
        if os.path.exists(controls_file):
            try:
                with open(controls_file) as f:
                    for item in json.load(f).values():
                        self.controls[item["control_id"]] = ComplianceControl(**item)
            except Exception:
                pass

        violations_file = os.path.join(self.state_dir, "violations.json")
        if os.path.exists(violations_file):
            try:
                with open(violations_file) as f:
                    for item in json.load(f).values():
                        self.violations[item["violation_id"]] = ComplianceViolation(**item)
            except Exception:
                pass

        reports_file = os.path.join(self.state_dir, "reports.json")
        if os.path.exists(reports_file):
            try:
                with open(reports_file) as f:
                    for item in json.load(f):
                        self.reports.append(ComplianceReport(**item))
            except Exception:
                pass
