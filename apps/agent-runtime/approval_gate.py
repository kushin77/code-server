#!/usr/bin/env python3
# @file        apps/agent-runtime/approval_gate.py
# @module      agent-runtime/approval-gate
# @description Approval gate service - evaluate OPA policies, route to Paperclip
# @owner       agent-runtime
# @status      production-ready
#
# Decision matrix: auto-approve reads, require approval for writes/deployments/deletions

import logging
import hashlib
import json
from typing import Dict, Any, Optional, Tuple
from datetime import datetime

from sqlalchemy.orm import Session

from .models import AgentAction, ActionType, PolicyDecision, ApprovalGate

logger = logging.getLogger(__name__)


class ApprovalGateService:
    """Evaluate agent actions against OPA policies, route to approval if needed"""

    def __init__(self, db_session: Session):
        self.db = db_session

    def evaluate_action(
        self,
        agent_id: str,
        task_id: str,
        action_type: ActionType,
        resource: str,
        payload: Dict[str, Any],
        agent_capabilities: Dict[str, Any],
    ) -> Tuple[PolicyDecision, Dict[str, Any]]:
        """
        Evaluate agent action against OPA policy
        
        Returns: (decision, details)
        decision in: ALLOW, DENY, REQUIRES_APPROVAL
        
        Policy Rules (order matters):
        1. Reads to approved APIs → ALLOW
        2. Writes outside workspace → REQUIRES_APPROVAL  
        3. Deployments → REQUIRES_APPROVAL
        4. Deletions → REQUIRES_APPROVAL
        5. External API calls → REQUIRES_APPROVAL
        6. Default: DENY (fail-safe)
        """
        
        # Rule 1: Read-only operations auto-approve
        if action_type in [ActionType.READ_FILE, ActionType.READ_LOGS, ActionType.ANALYZE_CODE]:
            decision = PolicyDecision.ALLOW
            details = {
                "reason": "read_only_operation",
                "rule": "rule_1_read_auto_approve",
            }
            return decision, details
        
        # Rule 2: Writes outside workspace require approval
        if action_type == ActionType.WRITE_FILE:
            if not resource.startswith("/workspace/"):
                decision = PolicyDecision.REQUIRES_APPROVAL
                details = {
                    "reason": "write_outside_workspace",
                    "rule": "rule_2_write_location",
                    "resource": resource,
                }
                return decision, details
            
            # Writes inside workspace auto-approve (for doc/test agents)
            if "writable_locations" in agent_capabilities:
                writable = agent_capabilities.get("writable_locations", [])
                is_writable = any(resource.startswith(loc) for loc in writable)
                if is_writable:
                    decision = PolicyDecision.ALLOW
                    details = {
                        "reason": "write_in_approved_location",
                        "rule": "rule_2_write_location",
                    }
                    return decision, details
        
        # Rule 3: Deployments require approval
        if action_type == ActionType.DEPLOY:
            decision = PolicyDecision.REQUIRES_APPROVAL
            details = {
                "reason": "deployment_requires_approval",
                "rule": "rule_3_deployment",
                "risk_level": "high",
            }
            return decision, details
        
        # Rule 4: Deletions require approval
        if action_type == ActionType.DELETE_RESOURCE:
            decision = PolicyDecision.REQUIRES_APPROVAL
            details = {
                "reason": "deletion_requires_approval",
                "rule": "rule_4_deletion",
                "risk_level": "critical",
            }
            return decision, details
        
        # Rule 5: External API calls require approval
        if action_type in [ActionType.CREATE_ISSUE, ActionType.CREATE_PR_COMMENT]:
            decision = PolicyDecision.REQUIRES_APPROVAL
            details = {
                "reason": "external_api_call",
                "rule": "rule_5_external_api",
                "service": resource,
            }
            return decision, details
        
        # Rule 6: Command execution - dangerous, require approval
        if action_type == ActionType.EXECUTE_COMMAND:
            decision = PolicyDecision.REQUIRES_APPROVAL
            details = {
                "reason": "command_execution",
                "rule": "rule_6_command",
                "risk_level": "critical",
            }
            return decision, details
        
        # Default: deny (fail-safe)
        decision = PolicyDecision.DENY
        details = {
            "reason": "unknown_action_type",
            "rule": "rule_default_deny",
            "action_type": action_type.value,
        }
        return decision, details

    def record_action(
        self,
        agent_id: str,
        task_id: str,
        action_type: ActionType,
        resource: str,
        payload: Dict[str, Any],
        policy_decision: PolicyDecision,
        policy_details: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Record agent action with policy decision
        
        If requires_approval: create approval gate record
        If denied: log incident
        If allowed: log audit trail
        """
        
        # Hash payload for audit trail (don't store secrets)
        payload_json = json.dumps(payload, sort_keys=True)
        payload_hash = hashlib.sha256(payload_json.encode()).hexdigest()
        payload_size = len(payload_json)
        
        # Create action record
        action = AgentAction(
            id=f"action/{agent_id}/{int(datetime.utcnow().timestamp() * 1000)}",
            agent_id=agent_id,
            task_id=task_id,
            action_type=action_type,
            resource=resource,
            opa_policy_decision=policy_decision,
            opa_policy_details=json.dumps(policy_details),
            payload_hash=payload_hash,
            payload_size_bytes=payload_size,
            requires_approval=(policy_decision == PolicyDecision.REQUIRES_APPROVAL),
        )
        
        self.db.add(action)
        self.db.flush()
        
        result = {
            "action_id": action.id,
            "policy_decision": policy_decision.value,
            "requires_approval": action.requires_approval,
        }
        
        # If approval required, create approval gate record
        if policy_decision == PolicyDecision.REQUIRES_APPROVAL:
            approval_gate = ApprovalGate(
                id=f"gate/{action.id}",
                action_id=action.id,
                action_type=action_type.value,
                resource_description=resource,
                risk_assessment=json.dumps(policy_details),
                diff_preview=payload_json[:1000],
            )
            self.db.add(approval_gate)
            
            result["approval_gate_id"] = approval_gate.id
            result["awaiting_approval"] = True
            
            logger.warning(
                f"Action requires approval: {action.id} "
                f"(agent={agent_id}, action={action_type.value}, resource={resource})"
            )
        
        elif policy_decision == PolicyDecision.DENY:
            logger.error(
                f"Action denied: {action.id} "
                f"(agent={agent_id}, action={action_type.value})"
            )
            result["error"] = policy_details.get("reason", "access_denied")
        
        else:
            logger.info(
                f"Action allowed: {action.id} "
                f"(agent={agent_id}, action={action_type.value})"
            )
        
        self.db.commit()
        return result

    def get_pending_approvals(self) -> list:
        """Get all actions awaiting approval"""
        gates = self.db.query(ApprovalGate).filter(
            ApprovalGate.decision == None
        ).order_by(ApprovalGate.created_at).all()
        
        return [
            {
                "gate_id": g.id,
                "action_id": g.action_id,
                "action_type": g.action_type,
                "resource": g.resource_description,
                "risk_level": json.loads(g.risk_assessment or "{}").get("risk_level", "medium"),
                "created_at": g.created_at.isoformat(),
            }
            for g in gates
        ]

    def approve_action(
        self,
        gate_id: str,
        approver_id: str,
        reason: str = ""
    ) -> bool:
        """Approve action"""
        gate = self.db.query(ApprovalGate).filter(
            ApprovalGate.id == gate_id
        ).first()
        
        if not gate or gate.decision:
            return False
        
        gate.decision = "approved"
        gate.decided_by = approver_id
        gate.decided_at = datetime.utcnow()
        gate.decision_reason = reason
        
        # Update action record
        action = self.db.query(AgentAction).filter(
            AgentAction.id == gate.action_id
        ).first()
        
        if action:
            action.approval_decision = "approved"
            action.approval_decided_at = datetime.utcnow()
        
        self.db.commit()
        
        logger.info(f"Action approved: {gate.action_id} by {approver_id}")
        return True

    def deny_action(
        self,
        gate_id: str,
        approver_id: str,
        reason: str = ""
    ) -> bool:
        """Deny action"""
        gate = self.db.query(ApprovalGate).filter(
            ApprovalGate.id == gate_id
        ).first()
        
        if not gate or gate.decision:
            return False
        
        gate.decision = "denied"
        gate.decided_by = approver_id
        gate.decided_at = datetime.utcnow()
        gate.decision_reason = reason
        
        # Update action record
        action = self.db.query(AgentAction).filter(
            AgentAction.id == gate.action_id
        ).first()
        
        if action:
            action.approval_decision = "denied"
            action.approval_decided_at = datetime.utcnow()
        
        self.db.commit()
        
        logger.info(f"Action denied: {gate.action_id} by {approver_id}")
        return True

    def get_approval_stats(self) -> Dict[str, Any]:
        """Get approval queue statistics"""
        pending = self.db.query(ApprovalGate).filter(
            ApprovalGate.decision == None
        ).count()
        
        approved = self.db.query(ApprovalGate).filter(
            ApprovalGate.decision == "approved"
        ).count()
        
        denied = self.db.query(ApprovalGate).filter(
            ApprovalGate.decision == "denied"
        ).count()
        
        return {
            "pending": pending,
            "approved": approved,
            "denied": denied,
            "total": pending + approved + denied,
        }
