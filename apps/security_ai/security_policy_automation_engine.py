#!/usr/bin/env python3
"""
@file security_policy_automation_engine.py
@description Phase 62 — Security Policy Automation Engine
@purpose Automated security policy definition, deployment, monitoring, and enforcement
@since 2026-05-01

Automates security policy lifecycle:
- Policy definition and templating
- Automated policy deployment across infrastructure
- Policy compliance monitoring and violation detection
- Policy drift detection and remediation
- Policy versioning and rollback
"""

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, List, Optional, Tuple
from uuid import uuid4
import json


class PolicyType(Enum):
    """Security policy classification"""
    ACCESS_CONTROL = "access_control"
    DATA_PROTECTION = "data_protection"
    NETWORK_SECURITY = "network_security"
    INCIDENT_RESPONSE = "incident_response"
    CRYPTOGRAPHY = "cryptography"
    AUTHENTICATION = "authentication"
    AUDIT_LOGGING = "audit_logging"
    COMPLIANCE = "compliance"


class PolicyStatus(Enum):
    """Policy lifecycle status"""
    DRAFT = "draft"
    STAGED = "staged"
    DEPLOYED = "deployed"
    DEPRECATED = "deprecated"
    ARCHIVED = "archived"


class DeploymentStatus(Enum):
    """Deployment execution status"""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    SUCCESS = "success"
    PARTIAL = "partial"
    FAILED = "failed"
    ROLLED_BACK = "rolled_back"


class ViolationType(Enum):
    """Policy violation types"""
    UNAUTHORIZED_ACCESS = "unauthorized_access"
    DATA_EXPOSURE = "data_exposure"
    MISSING_ENCRYPTION = "missing_encryption"
    COMPLIANCE_BREACH = "compliance_breach"
    AUDIT_FAILURE = "audit_failure"
    CONFIG_DRIFT = "config_drift"
    AUTHENTICATION_FAILURE = "authentication_failure"


@dataclass
class PolicyRule:
    """Individual policy rule within a policy"""
    rule_id: str
    name: str
    description: str
    action: str  # e.g., "allow", "deny", "alert"
    conditions: Dict[str, str]
    priority: int = 100
    enabled: bool = True
    created_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> Dict:
        return {
            "rule_id": self.rule_id,
            "name": self.name,
            "description": self.description,
            "action": self.action,
            "conditions": self.conditions,
            "priority": self.priority,
            "enabled": self.enabled,
            "created_at": self.created_at.isoformat()
        }


@dataclass
class SecurityPolicy:
    """Security policy definition"""
    policy_id: str
    name: str
    policy_type: PolicyType
    version: str
    description: str
    rules: List[PolicyRule] = field(default_factory=list)
    status: PolicyStatus = PolicyStatus.DRAFT
    created_by: str = ""
    created_at: datetime = field(default_factory=datetime.utcnow)
    last_modified: datetime = field(default_factory=datetime.utcnow)
    deployments: List[str] = field(default_factory=list)
    tags: Dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> Dict:
        return {
            "policy_id": self.policy_id,
            "name": self.name,
            "policy_type": self.policy_type.value,
            "version": self.version,
            "description": self.description,
            "status": self.status.value,
            "rule_count": len(self.rules),
            "created_by": self.created_by,
            "created_at": self.created_at.isoformat(),
            "last_modified": self.last_modified.isoformat(),
            "deployment_count": len(self.deployments)
        }


@dataclass
class PolicyDeployment:
    """Policy deployment execution record"""
    deployment_id: str
    policy_id: str
    version: str
    target_scope: str  # e.g., "production", "staging", "*"
    status: DeploymentStatus = DeploymentStatus.PENDING
    deployed_at: Optional[datetime] = None
    deployed_by: str = ""
    affected_resources: int = 0
    successful_resources: int = 0
    failed_resources: int = 0
    rollback_available: bool = True
    previous_version: Optional[str] = None

    def to_dict(self) -> Dict:
        return {
            "deployment_id": self.deployment_id,
            "policy_id": self.policy_id,
            "version": self.version,
            "target_scope": self.target_scope,
            "status": self.status.value,
            "deployed_at": self.deployed_at.isoformat() if self.deployed_at else None,
            "deployed_by": self.deployed_by,
            "affected_resources": self.affected_resources,
            "successful_resources": self.successful_resources,
            "failed_resources": self.failed_resources,
            "success_rate": (self.successful_resources / self.affected_resources * 100) if self.affected_resources > 0 else 0
        }


@dataclass
class PolicyViolation:
    """Policy violation detection record"""
    violation_id: str
    policy_id: str
    violation_type: ViolationType
    severity: str  # "critical", "high", "medium", "low"
    resource: str
    details: str
    detected_at: datetime = field(default_factory=datetime.utcnow)
    resolved: bool = False
    resolved_at: Optional[datetime] = None
    remediation: str = ""

    def to_dict(self) -> Dict:
        return {
            "violation_id": self.violation_id,
            "policy_id": self.policy_id,
            "violation_type": self.violation_type.value,
            "severity": self.severity,
            "resource": self.resource,
            "detected_at": self.detected_at.isoformat(),
            "resolved": self.resolved,
            "age_hours": (datetime.utcnow() - self.detected_at).total_seconds() / 3600
        }


@dataclass
class PolicyDriftEvent:
    """Configuration drift from deployed policy"""
    drift_id: str
    policy_id: str
    resource: str
    expected_state: Dict
    actual_state: Dict
    detected_at: datetime = field(default_factory=datetime.utcnow)
    remediated: bool = False
    remediated_at: Optional[datetime] = None

    def to_dict(self) -> Dict:
        return {
            "drift_id": self.drift_id,
            "policy_id": self.policy_id,
            "resource": self.resource,
            "detected_at": self.detected_at.isoformat(),
            "remediated": self.remediated,
            "drift_duration_hours": (datetime.utcnow() - self.detected_at).total_seconds() / 3600 if not self.remediated else 0
        }


@dataclass
class PolicyReport:
    """Policy status and compliance report"""
    report_id: str
    generated_at: datetime
    total_policies: int
    deployed_policies: int
    violations_count: int
    critical_violations: int
    drift_events_count: int
    deployment_success_rate: float
    avg_deployment_time_minutes: float
    compliance_score: float  # 0-100

    def to_dict(self) -> Dict:
        return {
            "report_id": self.report_id,
            "generated_at": self.generated_at.isoformat(),
            "total_policies": self.total_policies,
            "deployed_policies": self.deployed_policies,
            "violations": self.violations_count,
            "critical_violations": self.critical_violations,
            "drift_events": self.drift_events_count,
            "deployment_success_rate": round(self.deployment_success_rate, 2),
            "avg_deployment_time": round(self.avg_deployment_time_minutes, 2),
            "compliance_score": round(self.compliance_score, 2),
            "phase62_score": self._calculate_phase62_score()
        }

    def _calculate_phase62_score(self) -> float:
        if self.total_policies == 0:
            return 0.0
        deployment_rate = (self.deployed_policies / self.total_policies) if self.total_policies > 0 else 0
        violation_impact = max(0, 1 - (self.critical_violations / max(1, self.violations_count)))
        drift_factor = max(0, 1 - (self.drift_events_count / max(1, self.total_policies)))
        return 25 * (deployment_rate * 0.5 + violation_impact * 0.3 + drift_factor * 0.2)


class SecurityPolicyAutomationEngine:
    """Automated security policy management engine"""

    def __init__(self):
        self.policies: Dict[str, SecurityPolicy] = {}
        self.deployments: Dict[str, PolicyDeployment] = {}
        self.violations: Dict[str, PolicyViolation] = {}
        self.drift_events: Dict[str, PolicyDriftEvent] = {}
        self.deployment_history: List[Tuple[str, datetime, float]] = []

    def create_policy(
        self,
        name: str,
        policy_type: PolicyType,
        description: str,
        created_by: str = "system"
    ) -> SecurityPolicy:
        """Create a new security policy"""
        policy_id = f"POL-{str(uuid4())[:8].upper()}"
        policy = SecurityPolicy(
            policy_id=policy_id,
            name=name,
            policy_type=policy_type,
            version="1.0.0",
            description=description,
            created_by=created_by
        )
        self.policies[policy_id] = policy
        return policy

    def add_rule_to_policy(
        self,
        policy_id: str,
        rule_name: str,
        action: str,
        conditions: Dict[str, str],
        description: str = ""
    ) -> PolicyRule:
        """Add rule to existing policy"""
        if policy_id not in self.policies:
            raise KeyError(f"Policy {policy_id} not found")
        
        rule_id = f"RULE-{str(uuid4())[:8].upper()}"
        rule = PolicyRule(
            rule_id=rule_id,
            name=rule_name,
            description=description,
            action=action,
            conditions=conditions,
            priority=len(self.policies[policy_id].rules) * 10
        )
        self.policies[policy_id].rules.append(rule)
        return rule

    def deploy_policy(
        self,
        policy_id: str,
        target_scope: str = "*",
        deployed_by: str = "system"
    ) -> PolicyDeployment:
        """Deploy policy to target scope"""
        if policy_id not in self.policies:
            raise KeyError(f"Policy {policy_id} not found")
        
        policy = self.policies[policy_id]
        deployment_id = f"DEP-{str(uuid4())[:8].upper()}"
        deployment = PolicyDeployment(
            deployment_id=deployment_id,
            policy_id=policy_id,
            version=policy.version,
            target_scope=target_scope,
            deployed_by=deployed_by,
            status=DeploymentStatus.IN_PROGRESS
        )
        self.deployments[deployment_id] = deployment
        return deployment

    def complete_deployment(
        self,
        deployment_id: str,
        affected_resources: int = 0,
        successful_resources: int = 0
    ) -> PolicyDeployment:
        """Mark deployment as complete"""
        if deployment_id not in self.deployments:
            raise KeyError(f"Deployment {deployment_id} not found")
        
        deployment = self.deployments[deployment_id]
        deployment.affected_resources = affected_resources
        deployment.successful_resources = successful_resources
        deployment.failed_resources = max(0, affected_resources - successful_resources)
        deployment.deployed_at = datetime.utcnow()
        
        if successful_resources == affected_resources:
            deployment.status = DeploymentStatus.SUCCESS
        elif successful_resources > 0:
            deployment.status = DeploymentStatus.PARTIAL
        else:
            deployment.status = DeploymentStatus.FAILED
        
        policy = self.policies[deployment.policy_id]
        policy.status = PolicyStatus.DEPLOYED
        policy.deployments.append(deployment_id)
        
        deploy_time = (datetime.utcnow() - deployment.deployed_at).total_seconds() / 60
        self.deployment_history.append((deployment_id, datetime.utcnow(), deploy_time))
        
        return deployment

    def record_violation(
        self,
        policy_id: str,
        violation_type: ViolationType,
        severity: str,
        resource: str,
        details: str
    ) -> PolicyViolation:
        """Record a policy violation"""
        if policy_id not in self.policies:
            raise KeyError(f"Policy {policy_id} not found")
        
        violation_id = f"VIO-{str(uuid4())[:8].upper()}"
        violation = PolicyViolation(
            violation_id=violation_id,
            policy_id=policy_id,
            violation_type=violation_type,
            severity=severity,
            resource=resource,
            details=details
        )
        self.violations[violation_id] = violation
        return violation

    def resolve_violation(self, violation_id: str, remediation: str = "") -> PolicyViolation:
        """Resolve a policy violation"""
        if violation_id not in self.violations:
            raise KeyError(f"Violation {violation_id} not found")
        
        violation = self.violations[violation_id]
        violation.resolved = True
        violation.resolved_at = datetime.utcnow()
        violation.remediation = remediation
        return violation

    def detect_drift(
        self,
        policy_id: str,
        resource: str,
        expected_state: Dict,
        actual_state: Dict
    ) -> PolicyDriftEvent:
        """Detect configuration drift from deployed policy"""
        if policy_id not in self.policies:
            raise KeyError(f"Policy {policy_id} not found")
        
        drift_id = f"DFT-{str(uuid4())[:8].upper()}"
        drift = PolicyDriftEvent(
            drift_id=drift_id,
            policy_id=policy_id,
            resource=resource,
            expected_state=expected_state,
            actual_state=actual_state
        )
        self.drift_events[drift_id] = drift
        return drift

    def remediate_drift(self, drift_id: str) -> PolicyDriftEvent:
        """Remediate configuration drift"""
        if drift_id not in self.drift_events:
            raise KeyError(f"Drift {drift_id} not found")
        
        drift = self.drift_events[drift_id]
        drift.remediated = True
        drift.remediated_at = datetime.utcnow()
        return drift

    def get_policy(self, policy_id: str) -> SecurityPolicy:
        """Retrieve policy by ID"""
        if policy_id not in self.policies:
            raise KeyError(f"Policy {policy_id} not found")
        return self.policies[policy_id]

    def policies_by_type(self, policy_type: PolicyType) -> List[SecurityPolicy]:
        """Get all policies of specified type"""
        return [p for p in self.policies.values() if p.policy_type == policy_type]

    def policies_by_status(self, status: PolicyStatus) -> List[SecurityPolicy]:
        """Get all policies with specified status"""
        return [p for p in self.policies.values() if p.status == status]

    def violations_by_severity(self, severity: str) -> List[PolicyViolation]:
        """Get violations by severity level"""
        return [v for v in self.violations.values() if v.severity == severity and not v.resolved]

    def unresolved_violations(self) -> List[PolicyViolation]:
        """Get all unresolved violations"""
        return [v for v in self.violations.values() if not v.resolved]

    def active_drift_events(self) -> List[PolicyDriftEvent]:
        """Get all unresolved drift events"""
        return [d for d in self.drift_events.values() if not d.remediated]

    def generate_report(self) -> PolicyReport:
        """Generate policy compliance and status report"""
        deployed = len([p for p in self.policies.values() if p.status == PolicyStatus.DEPLOYED])
        unresolved_violations = self.unresolved_violations()
        critical_violations = len([v for v in unresolved_violations if v.severity == "critical"])
        active_drifts = self.active_drift_events()
        
        deployment_success_rate = 0.0
        if self.deployment_history:
            successful = len([d for d in self.deployments.values() if d.status == DeploymentStatus.SUCCESS])
            deployment_success_rate = (successful / len(self.deployments)) * 100 if self.deployments else 0
        
        avg_deployment_time = 0.0
        if self.deployment_history:
            avg_deployment_time = sum(t[2] for t in self.deployment_history) / len(self.deployment_history)
        
        total_policies = len(self.policies)
        compliance_score = (deployed / total_policies * 100) if total_policies > 0 else 0
        
        report = PolicyReport(
            report_id=f"RPT-{str(uuid4())[:8].upper()}",
            generated_at=datetime.utcnow(),
            total_policies=total_policies,
            deployed_policies=deployed,
            violations_count=len(unresolved_violations),
            critical_violations=critical_violations,
            drift_events_count=len(active_drifts),
            deployment_success_rate=deployment_success_rate,
            avg_deployment_time_minutes=avg_deployment_time,
            compliance_score=compliance_score
        )
        return report

    def summary(self) -> Dict:
        """Get engine summary"""
        return {
            "total_policies": len(self.policies),
            "policy_types": {pt.value: len(self.policies_by_type(pt)) for pt in PolicyType},
            "policy_statuses": {ps.value: len(self.policies_by_status(ps)) for ps in PolicyStatus},
            "total_deployments": len(self.deployments),
            "successful_deployments": len([d for d in self.deployments.values() if d.status == DeploymentStatus.SUCCESS]),
            "unresolved_violations": len(self.unresolved_violations()),
            "critical_violations": len([v for v in self.unresolved_violations() if v.severity == "critical"]),
            "active_drift_events": len(self.active_drift_events()),
            "avg_deployment_time_minutes": sum(t[2] for t in self.deployment_history) / len(self.deployment_history) if self.deployment_history else 0,
            "phase62_score": self.phase62_score()
        }

    def phase62_score(self) -> float:
        """Calculate Phase 62 gate contribution (0-25)"""
        report = self.generate_report()
        return report._calculate_phase62_score()


def make_policy(
    name: str = "Test Policy",
    policy_type: PolicyType = PolicyType.ACCESS_CONTROL,
    description: str = "Test policy"
) -> SecurityPolicy:
    """Helper to create test policy"""
    return SecurityPolicy(
        policy_id=f"POL-{str(uuid4())[:8].upper()}",
        name=name,
        policy_type=policy_type,
        version="1.0.0",
        description=description
    )


def policy_compliance_score(engine: SecurityPolicyAutomationEngine) -> float:
    """Helper to get phase62_score"""
    return engine.phase62_score()
