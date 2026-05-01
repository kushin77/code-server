"""
apps.security_ai — Phase 30 AI-driven security and compliance automation.

Modules:
    threat_detector    — ML-based threat detection (Isolation Forest + MITRE ATT&CK)
    compliance_checker — Automated compliance validation (SOC2/NIST/ISO 27001)
"""

from .threat_detector import ThreatDetector, ThreatSeverity, ThreatType, SecurityEvent, Threat
from .compliance_checker import (
    ComplianceChecker,
    ComplianceFramework,
    ComplianceStatus,
    ComplianceControl,
    ComplianceReport,
)

__all__ = [
    "ThreatDetector",
    "ThreatSeverity",
    "ThreatType",
    "SecurityEvent",
    "Threat",
    "ComplianceChecker",
    "ComplianceFramework",
    "ComplianceStatus",
    "ComplianceControl",
    "ComplianceReport",
]

__version__ = "30.0.0"
