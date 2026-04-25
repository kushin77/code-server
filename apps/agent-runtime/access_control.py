"""
@governance: Capability-based access control — validate agent capabilities and risk levels
@Purpose: Enforce least-privilege access for agent actions with risk-level gating
@Author: Autonomous Infrastructure
@Date: 2026-04-25
@Related issues: #1534 (IaC Governance), #1557 (Agent Runtime)

Access control system for agent-based execution with capability validation
and risk-level enforcement.
"""

import logging
from enum import Enum
from typing import Dict, List, Optional, Set, Tuple
from dataclasses import dataclass

logger = logging.getLogger(__name__)


class CapabilityScope(str, Enum):
    """Scope of capability access"""
    GITHUB_REPO = "github:repo"
    GITHUB_ORG = "github:org"
    INTERNAL_API = "internal:api"
    FILE_SYSTEM = "file:system"
    NETWORK_EGRESS = "network:egress"
    SERVICE_RESTART = "service:restart"
    LOG_ACCESS = "log:access"
    METRICS_READ = "metrics:read"


class RiskLevel(str, Enum):
    """Risk levels for capability actions"""
    LOW = "low"              # Auto-approved, no approval needed
    MEDIUM = "medium"        # Requires approver
    HIGH = "high"            # Requires senior approver
    CRITICAL = "critical"    # Requires elite approver


class ApprovalRequired(str, Enum):
    """Approval requirement levels"""
    AUTO = "auto"              # Auto-approved
    APPROVER = "approver"      # Standard approver
    SENIOR = "senior"          # Senior level
    ELITE = "elite"            # Elite/on-call level


@dataclass
class Capability:
    """Single capability declaration"""
    scope: CapabilityScope
    action: str
    risk_level: RiskLevel
    approval_required: ApprovalRequired
    metadata: Optional[Dict] = None
    
    def __hash__(self):
        return hash((self.scope, self.action, self.risk_level))
    
    def __eq__(self, other):
        if not isinstance(other, Capability):
            return False
        return (self.scope == other.scope and 
                self.action == other.action and 
                self.risk_level == other.risk_level)


class CapabilityValidator:
    """Validates agent capability declarations and enforces access control"""
    
    # Risk level to approval mapping (immutable)
    readonly_RISK_TO_APPROVAL: Dict[RiskLevel, ApprovalRequired] = {
        RiskLevel.LOW: ApprovalRequired.AUTO,
        RiskLevel.MEDIUM: ApprovalRequired.APPROVER,
        RiskLevel.HIGH: ApprovalRequired.SENIOR,
        RiskLevel.CRITICAL: ApprovalRequired.ELITE,
    }
    
    def __init__(self, agent_type: str, declared_capabilities: Set[Capability]):
        self.agent_type = agent_type
        self.declared_capabilities = declared_capabilities
        self.capability_map = self._build_capability_map()
        self.validation_results: List[Dict] = []
    
    def _build_capability_map(self) -> Dict[Tuple[CapabilityScope, str], Capability]:
        """Build fast-lookup map of (scope, action) -> capability"""
        cap_map = {}
        for cap in self.declared_capabilities:
            key = (cap.scope, cap.action)
            if key in cap_map:
                logger.warning(
                    f"Duplicate capability for agent {self.agent_type}: "
                    f"{cap.scope.value}:{cap.action}"
                )
            cap_map[key] = cap
        return cap_map
    
    def validate_action(
        self,
        action_scope: CapabilityScope,
        action_name: str,
        risk_level_override: Optional[RiskLevel] = None
    ) -> Tuple[bool, str, ApprovalRequired]:
        """
        Validate if agent can perform requested action.
        
        Returns:
            Tuple of (is_allowed, reason, approval_required)
        """
        key = (action_scope, action_name)
        
        # Check if capability is declared
        if key not in self.capability_map:
            reason = (
                f"Agent {self.agent_type} does not have capability "
                f"{action_scope.value}:{action_name}"
            )
            logger.warning(reason)
            self.validation_results.append({
                "action": f"{action_scope.value}:{action_name}",
                "status": "denied",
                "reason": reason
            })
            return False, reason, ApprovalRequired.AUTO
        
        capability = self.capability_map[key]
        
        # Use override risk level if provided, otherwise use declared risk
        actual_risk = risk_level_override or capability.risk_level
        required_approval = self.readonly_RISK_TO_APPROVAL.get(
            actual_risk, 
            ApprovalRequired.APPROVER
        )
        
        # Check if capability's approval requirement matches risk level
        if capability.approval_required != required_approval:
            logger.warning(
                f"Risk level mismatch for {self.agent_type}/{action_scope.value}:"
                f"{action_name}: declared={capability.approval_required}, "
                f"risk={actual_risk}/{required_approval}"
            )
        
        reason = f"Action {action_scope.value}:{action_name} approved (risk: {actual_risk.value})"
        self.validation_results.append({
            "action": f"{action_scope.value}:{action_name}",
            "status": "allowed",
            "risk_level": actual_risk.value,
            "approval_required": required_approval.value,
            "reason": reason
        })
        
        logger.info(
            f"Action validation passed: agent={self.agent_type}, "
            f"action={action_scope.value}:{action_name}, "
            f"risk={actual_risk.value}, approval={required_approval.value}"
        )
        
        return True, reason, required_approval
    
    def validate_batch_actions(
        self,
        actions: List[Tuple[CapabilityScope, str]],
        fail_on_first_error: bool = True
    ) -> Tuple[bool, List[Dict]]:
        """
        Validate multiple actions.
        
        Returns:
            Tuple of (all_allowed, validation_results)
        """
        all_allowed = True
        results = []
        
        for action_scope, action_name in actions:
            is_allowed, reason, approval = self.validate_action(action_scope, action_name)
            
            result = {
                "action": f"{action_scope.value}:{action_name}",
                "allowed": is_allowed,
                "reason": reason,
                "approval_required": approval.value if is_allowed else None
            }
            results.append(result)
            
            if not is_allowed:
                all_allowed = False
                if fail_on_first_error:
                    logger.error(f"Batch validation failed at action: {action_scope.value}:{action_name}")
                    break
        
        return all_allowed, results
    
    def get_capabilities_summary(self) -> Dict:
        """Get summary of agent's capabilities"""
        by_scope = {}
        by_risk = {}
        
        for capability in self.declared_capabilities:
            # By scope
            scope_key = capability.scope.value
            if scope_key not in by_scope:
                by_scope[scope_key] = []
            by_scope[scope_key].append(capability.action)
            
            # By risk
            risk_key = capability.risk_level.value
            if risk_key not in by_risk:
                by_risk[risk_key] = []
            by_risk[risk_key].append(f"{capability.scope.value}:{capability.action}")
        
        return {
            "agent_type": self.agent_type,
            "total_capabilities": len(self.declared_capabilities),
            "by_scope": by_scope,
            "by_risk": by_risk,
            "by_approval": {
                approval.value: sum(
                    len(caps) for cap in self.declared_capabilities 
                    if cap.approval_required == approval
                )
                for approval in ApprovalRequired
            }
        }
    
    def get_validation_report(self) -> Dict:
        """Get validation report for audit logging"""
        return {
            "agent_type": self.agent_type,
            "validations_performed": len(self.validation_results),
            "successful": sum(1 for v in self.validation_results if v["status"] == "allowed"),
            "denied": sum(1 for v in self.validation_results if v["status"] == "denied"),
            "details": self.validation_results
        }
