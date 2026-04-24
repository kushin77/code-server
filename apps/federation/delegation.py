#!/usr/bin/env python3
# @file        apps/federation/delegation.py
# @module      federation/delegation
# @description Cross-org agent delegation with dual OPA policy enforcement

import logging
import uuid
from typing import Dict, List, Optional
from datetime import datetime
import os
import json

logger = logging.getLogger(__name__)


class DelegationEngine:
    """Manages cross-org agent delegation with dual policy enforcement."""

    def __init__(self, trust_manager):
        self.trust_manager = trust_manager
        self.delegations: Dict[str, Dict] = {}
        self.audit_log: List[Dict] = []

    def create_delegation(
        self,
        source_org: str,
        remote_org: str,
        agent_id: str,
        task: Dict,
        org_policies: Dict = None,
    ) -> Dict:
        """
        Create delegation for agent to execute in remote organization.
        
        Delegated agent has dual identity: source_org identity + remote_org execution context.
        Subject to BOTH orgs' OPA policies.
        """
        delegation_id = str(uuid.uuid4())
        remote_execution_id = str(uuid.uuid4())
        
        delegation = {
            "delegation_id": delegation_id,
            "remote_execution_id": remote_execution_id,
            "source_org": source_org,
            "remote_org": remote_org,
            "agent_id": agent_id,
            "task": task,
            "status": "active",
            "created_at": datetime.utcnow().isoformat(),
            "policies": {
                "source_org_policy": self._get_org_policy(source_org),
                "remote_org_policy": org_policies or self._get_org_policy(remote_org),
            },
        }
        
        # Verify dual policy compliance
        source_policy_ok = self._evaluate_policy(
            delegation["policies"]["source_org_policy"],
            agent_id,
            task,
        )
        
        remote_policy_ok = self._evaluate_policy(
            delegation["policies"]["remote_org_policy"],
            agent_id,
            task,
        )
        
        if not (source_policy_ok and remote_policy_ok):
            logger.error(f"Delegation {delegation_id} blocked by OPA policy")
            delegation["status"] = "blocked"
            return delegation
        
        self.delegations[delegation_id] = delegation
        
        # Log delegation
        self._log_audit_event(
            event_type="delegation_created",
            delegation_id=delegation_id,
            source_org=source_org,
            remote_org=remote_org,
            agent_id=agent_id,
            status="approved",
        )
        
        logger.info(f"✅ Delegation created: {delegation_id}")
        return delegation

    def get_delegated_agent_context(self, delegation_id: str) -> Optional[Dict]:
        """
        Get execution context for delegated agent.
        
        Returns agent identity combining source_org + remote_org context.
        """
        if delegation_id not in self.delegations:
            return None
        
        delegation = self.delegations[delegation_id]
        
        if delegation["status"] != "active":
            logger.warning(f"Delegation {delegation_id} is {delegation['status']}")
            return None
        
        return {
            "agent_id": delegation["agent_id"],
            "source_org": delegation["source_org"],
            "remote_org": delegation["remote_org"],
            "execution_id": delegation["remote_execution_id"],
            "policies": delegation["policies"],
        }

    def report_delegation_result(
        self,
        delegation_id: str,
        result: Dict,
        status: str = "completed",
    ) -> bool:
        """
        Report result from delegated agent execution.
        
        Logs to both source and remote org audit systems.
        """
        if delegation_id not in self.delegations:
            logger.warning(f"Delegation {delegation_id} not found")
            return False
        
        delegation = self.delegations[delegation_id]
        delegation["status"] = status
        delegation["result"] = result
        delegation["completed_at"] = datetime.utcnow().isoformat()
        
        # Log to both orgs
        self._log_audit_event(
            event_type="delegation_completed",
            delegation_id=delegation_id,
            source_org=delegation["source_org"],
            remote_org=delegation["remote_org"],
            agent_id=delegation["agent_id"],
            result=result,
            status=status,
        )
        
        logger.info(f"✅ Delegation {delegation_id} result reported: {status}")
        return True

    def cancel_delegations_for_org(self, remote_org: str) -> List[str]:
        """
        Cancel all delegations involving remote_org (e.g., on trust revocation).
        
        Returns list of cancelled delegation IDs.
        """
        cancelled = []
        
        for delegation_id, delegation in list(self.delegations.items()):
            if delegation["remote_org"] == remote_org and delegation["status"] == "active":
                delegation["status"] = "cancelled"
                delegation["cancelled_at"] = datetime.utcnow().isoformat()
                
                self._log_audit_event(
                    event_type="delegation_cancelled",
                    delegation_id=delegation_id,
                    source_org=delegation["source_org"],
                    remote_org=remote_org,
                    reason="trust_revocation",
                )
                
                cancelled.append(delegation_id)
        
        logger.info(f"✅ Cancelled {len(cancelled)} delegations for {remote_org}")
        return cancelled

    def get_active_delegations(self) -> List[Dict]:
        """Get all active delegations."""
        active = []
        for delegation_id, delegation in self.delegations.items():
            if delegation["status"] == "active":
                active.append({
                    "delegation_id": delegation_id,
                    "source_org": delegation["source_org"],
                    "remote_org": delegation["remote_org"],
                    "agent_id": delegation["agent_id"],
                    "created_at": delegation["created_at"],
                })
        return active

    def get_audit_log(self, remote_org: str = None) -> List[Dict]:
        """Get audit log entries (optionally filtered by org)."""
        if remote_org:
            return [e for e in self.audit_log if e.get("remote_org") == remote_org]
        return self.audit_log

    def _evaluate_policy(self, policy: Dict, agent_id: str, task: Dict) -> bool:
        """
        Evaluate OPA policy for delegation.
        
        Returns True if policy approves delegation.
        """
        # Placeholder: in production, call OPA /data/federation endpoint
        if not policy:
            return True  # No policy = allow
        
        # Simulate policy evaluation
        logger.debug(f"Evaluating policy for agent {agent_id}")
        return True

    def _get_org_policy(self, org_id: str) -> Optional[Dict]:
        """Get OPA policy for organization."""
        # Placeholder: fetch from policy store
        return {
            "org_id": org_id,
            "version": "1.0",
            "rules": [],
        }

    def _log_audit_event(
        self,
        event_type: str,
        delegation_id: str,
        source_org: str,
        remote_org: str,
        agent_id: str,
        **kwargs
    ):
        """Log delegation event to audit system."""
        event = {
            "event_type": event_type,
            "delegation_id": delegation_id,
            "source_org": source_org,
            "remote_org": remote_org,
            "agent_id": agent_id,
            "timestamp": datetime.utcnow().isoformat(),
            **kwargs,
        }
        
        self.audit_log.append(event)
        
        # In production: publish to federation.audit Kafka topic
        logger.info(f"Audit: {event_type} - {delegation_id}")
