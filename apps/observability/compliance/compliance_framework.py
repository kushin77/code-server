"""
Phase 25C: Compliance Framework

Compliance tracking and reporting for regulated environments:
- SOC 2 compliance tracking
- GDPR data retention policies
- HIPAA audit requirements automation
- Compliance reporting dashboards
- Automated evidence collection

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Set
from datetime import datetime, timedelta
from enum import Enum

logger = logging.getLogger(__name__)


class ComplianceFramework(Enum):
    """Supported compliance frameworks."""
    SOC2 = "soc2"
    GDPR = "gdpr"
    HIPAA = "hipaa"
    PCI_DSS = "pci_dss"
    ISO27001 = "iso27001"


class ComplianceStatus(Enum):
    """Compliance status."""
    COMPLIANT = "compliant"
    NON_COMPLIANT = "non_compliant"
    WARNING = "warning"
    UNKNOWN = "unknown"


@dataclass
class ComplianceControl:
    """Compliance control requirement."""
    control_id: str
    framework: ComplianceFramework
    name: str
    description: str
    category: str  # e.g., "Access Control", "Encryption", "Audit"
    requirement_text: str
    severity: str  # critical, high, medium, low
    implementation_status: str = "not_started"  # not_started, in_progress, implemented, verified
    automated_check: bool = False
    check_interval_hours: int = 24
    last_check: Optional[datetime] = None
    compliance_status: ComplianceStatus = ComplianceStatus.UNKNOWN
    evidence_files: List[str] = field(default_factory=list)
    notes: str = ""


@dataclass
class GDPRDataRetentionPolicy:
    """GDPR data retention policy."""
    policy_id: str
    data_type: str  # trace, metric, log, event, etc.
    retention_days: int
    deletion_method: str  # immediate, anonymize, archive
    archived_location: Optional[str] = None
    applicable_jurisdictions: Set[str] = field(default_factory=set)  # EU, US, etc.
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    last_purge: Optional[datetime] = None
    next_purge: Optional[datetime] = None
    purge_count: int = 0
    
    @property
    def is_due_for_purge(self) -> bool:
        """Check if data retention policy is due for purge."""
        if not self.last_purge:
            return True
        
        next_purge_time = self.last_purge + timedelta(days=1)
        return datetime.utcnow() >= next_purge_time


@dataclass
class HIPAAAuditEntry:
    """HIPAA audit requirement entry."""
    audit_id: str
    timestamp: datetime = field(default_factory=datetime.utcnow)
    event_type: str = ""  # access, modification, deletion, authentication, etc.
    user_id: str = ""
    resource_id: str = ""
    action: str = ""
    result: str = ""  # success, failed, denied
    ip_address: str = ""
    protected_health_info_accessed: bool = False
    details: Dict[str, Any] = field(default_factory=dict)
    retention_until: datetime = field(default_factory=lambda: datetime.utcnow() + timedelta(days=365*6))


@dataclass
class ComplianceReport:
    """Compliance assessment report."""
    report_id: str
    framework: ComplianceFramework
    generated_at: datetime = field(default_factory=datetime.utcnow)
    assessment_date: datetime = field(default_factory=datetime.utcnow)
    overall_status: ComplianceStatus = ComplianceStatus.UNKNOWN
    controls_total: int = 0
    controls_compliant: int = 0
    controls_non_compliant: int = 0
    controls_warning: int = 0
    findings: List[Dict[str, Any]] = field(default_factory=list)
    recommendations: List[str] = field(default_factory=list)
    remediation_required: List[str] = field(default_factory=list)
    prepared_by: str = ""
    reviewed_by: Optional[str] = None
    review_date: Optional[datetime] = None
    
    @property
    def compliance_percentage(self) -> float:
        """Calculate compliance percentage."""
        if self.controls_total == 0:
            return 0.0
        return (self.controls_compliant / self.controls_total) * 100


class ComplianceFrameworkManager:
    """Manages compliance frameworks and controls."""
    
    def __init__(self):
        """Initialize compliance manager."""
        self.controls: Dict[str, ComplianceControl] = {}
        self.reports: Dict[str, ComplianceReport] = {}
        self.gdpr_policies: Dict[str, GDPRDataRetentionPolicy] = {}
        self.hipaa_audit_log: List[HIPAAAuditEntry] = []
        self._init_default_controls()
    
    def _init_default_controls(self) -> None:
        """Initialize default compliance controls."""
        # SOC 2 controls
        soc2_controls = [
            ComplianceControl(
                control_id="soc2_cc1",
                framework=ComplianceFramework.SOC2,
                name="CC1: Governance & Accountability",
                description="Organization establishes governance structures",
                category="Governance",
                requirement_text="Establish governance framework and accountability",
                severity="critical",
            ),
            ComplianceControl(
                control_id="soc2_cc3",
                framework=ComplianceFramework.SOC2,
                name="CC3: Risk Assessment",
                description="Organization assesses risks to achieve objectives",
                category="Risk Management",
                requirement_text="Perform regular risk assessments",
                severity="critical",
            ),
            ComplianceControl(
                control_id="soc2_cc6",
                framework=ComplianceFramework.SOC2,
                name="CC6: Change Management",
                description="Systems are protected from unauthorized changes",
                category="Change Management",
                requirement_text="Control and approve all system changes",
                severity="high",
                automated_check=True,
            ),
            ComplianceControl(
                control_id="soc2_cc7",
                framework=ComplianceFramework.SOC2,
                name="CC7: System Monitoring",
                description="System and software are monitored for monitoring",
                category="Monitoring",
                requirement_text="Monitor systems and detect anomalies",
                severity="high",
                automated_check=True,
            ),
        ]
        
        for control in soc2_controls:
            self.controls[control.control_id] = control
        
        # GDPR controls
        gdpr_controls = [
            ComplianceControl(
                control_id="gdpr_5",
                framework=ComplianceFramework.GDPR,
                name="Article 5: Principles Relating to Processing",
                description="Personal data must be processed lawfully and fairly",
                category="Data Processing",
                requirement_text="Process personal data according to principles",
                severity="critical",
            ),
            ComplianceControl(
                control_id="gdpr_17",
                framework=ComplianceFramework.GDPR,
                name="Article 17: Right to Erasure",
                description="Data subject has right to erasure",
                category="Data Subject Rights",
                requirement_text="Implement right to erasure functionality",
                severity="critical",
                automated_check=True,
            ),
            ComplianceControl(
                control_id="gdpr_32",
                framework=ComplianceFramework.GDPR,
                name="Article 32: Security of Processing",
                description="Implement appropriate technical and organizational measures",
                category="Security",
                requirement_text="Protect personal data with encryption and controls",
                severity="critical",
                automated_check=True,
            ),
        ]
        
        for control in gdpr_controls:
            self.controls[control.control_id] = control
        
        # HIPAA controls
        hipaa_controls = [
            ComplianceControl(
                control_id="hipaa_164_312",
                framework=ComplianceFramework.HIPAA,
                name="§164.312: Technical Safeguards",
                description="Implementation specifications for technical safeguards",
                category="Technical Controls",
                requirement_text="Implement encryption, access controls, audit logs",
                severity="critical",
                automated_check=True,
            ),
            ComplianceControl(
                control_id="hipaa_164_308",
                framework=ComplianceFramework.HIPAA,
                name="§164.308: Administrative Safeguards",
                description="Administrative actions and policies required",
                category="Administrative Controls",
                requirement_text="Document policies and procedures",
                severity="high",
            ),
        ]
        
        for control in hipaa_controls:
            self.controls[control.control_id] = control
    
    def create_gdpr_policy(
        self,
        data_type: str,
        retention_days: int,
        deletion_method: str,
    ) -> GDPRDataRetentionPolicy:
        """Create GDPR data retention policy."""
        policy_id = f"gdpr_{data_type}_{int(retention_days)}"
        policy = GDPRDataRetentionPolicy(
            policy_id=policy_id,
            data_type=data_type,
            retention_days=retention_days,
            deletion_method=deletion_method,
            next_purge=datetime.utcnow() + timedelta(days=1),
        )
        self.gdpr_policies[policy_id] = policy
        
        logger.info(f"Created GDPR policy: {policy_id} ({data_type}, {retention_days} days)")
        
        return policy
    
    def add_hipaa_audit_entry(
        self,
        event_type: str,
        user_id: str,
        resource_id: str,
        action: str,
        result: str,
        protected_health_info_accessed: bool = False,
        details: Optional[Dict[str, Any]] = None,
    ) -> HIPAAAuditEntry:
        """Add HIPAA audit entry."""
        entry = HIPAAAuditEntry(
            audit_id=self._generate_id(),
            event_type=event_type,
            user_id=user_id,
            resource_id=resource_id,
            action=action,
            result=result,
            protected_health_info_accessed=protected_health_info_accessed,
            details=details or {},
        )
        self.hipaa_audit_log.append(entry)
        
        return entry
    
    def assess_framework(
        self,
        framework: ComplianceFramework,
        prepared_by: str,
    ) -> ComplianceReport:
        """Generate compliance assessment report."""
        report_id = self._generate_id()
        report = ComplianceReport(
            report_id=report_id,
            framework=framework,
            prepared_by=prepared_by,
        )
        
        # Get all controls for this framework
        framework_controls = [
            c for c in self.controls.values()
            if c.framework == framework
        ]
        
        report.controls_total = len(framework_controls)
        report.controls_compliant = sum(
            1 for c in framework_controls
            if c.compliance_status == ComplianceStatus.COMPLIANT
        )
        report.controls_non_compliant = sum(
            1 for c in framework_controls
            if c.compliance_status == ComplianceStatus.NON_COMPLIANT
        )
        report.controls_warning = sum(
            1 for c in framework_controls
            if c.compliance_status == ComplianceStatus.WARNING
        )
        
        # Determine overall status
        if report.controls_non_compliant > 0:
            report.overall_status = ComplianceStatus.NON_COMPLIANT
        elif report.controls_warning > 0:
            report.overall_status = ComplianceStatus.WARNING
        else:
            report.overall_status = ComplianceStatus.COMPLIANT
        
        # Generate findings
        for control in framework_controls:
            if control.compliance_status != ComplianceStatus.COMPLIANT:
                report.findings.append({
                    "control_id": control.control_id,
                    "name": control.name,
                    "status": control.compliance_status.value,
                    "notes": control.notes,
                })
                
                if control.compliance_status == ComplianceStatus.NON_COMPLIANT:
                    report.remediation_required.append(control.control_id)
        
        self.reports[report_id] = report
        
        return report
    
    def update_control_status(
        self,
        control_id: str,
        status: ComplianceStatus,
        notes: str = "",
    ) -> bool:
        """Update control compliance status."""
        if control_id not in self.controls:
            return False
        
        control = self.controls[control_id]
        control.compliance_status = status
        control.notes = notes
        control.last_check = datetime.utcnow()
        
        logger.info(f"Updated control {control_id} status to {status.value}")
        
        return True
    
    def get_compliance_summary(self) -> Dict[str, Any]:
        """Get overall compliance summary."""
        frameworks = {f: list(f) for f in ComplianceFramework}
        
        summary = {}
        for framework in ComplianceFramework:
            controls = [
                c for c in self.controls.values()
                if c.framework == framework
            ]
            
            if controls:
                compliant_count = sum(
                    1 for c in controls
                    if c.compliance_status == ComplianceStatus.COMPLIANT
                )
                
                summary[framework.value] = {
                    "total_controls": len(controls),
                    "compliant": compliant_count,
                    "compliance_percentage": (compliant_count / len(controls)) * 100,
                }
        
        return summary
    
    def _generate_id(self) -> str:
        """Generate unique ID."""
        import time
        import random
        import hashlib
        key = f"{time.time()}{random.random()}"
        return hashlib.md5(key.encode()).hexdigest()[:16]


__all__ = [
    "ComplianceFramework",
    "ComplianceStatus",
    "ComplianceControl",
    "GDPRDataRetentionPolicy",
    "HIPAAAuditEntry",
    "ComplianceReport",
    "ComplianceFrameworkManager",
]
