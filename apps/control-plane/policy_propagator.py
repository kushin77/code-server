#!/usr/bin/env python3
# @file        apps/control-plane/policy_propagator.py
# @module      control-plane/policy
# @description Global policy propagation to federated organizations

import logging
import uuid
from typing import Dict, List, Optional
from datetime import datetime, timedelta
import asyncio

logger = logging.getLogger(__name__)


class PolicyPropagator:
    """Manages policy propagation across federated organizations."""

    def __init__(self):
        self.propagations: Dict[str, Dict] = {}
        self.policy_history: List[Dict] = []
        self.ack_timeout = 300  # 5 minutes

    async def propagate(
        self,
        policy_id: str,
        policy_content: str,
        target_orgs: List[str] = None,
    ) -> Dict:
        """
        Propagate OPA policy to all federated organizations.
        
        Returns: propagation_id and acknowledgment status
        """
        propagation_id = str(uuid.uuid4())
        
        propagation = {
            "propagation_id": propagation_id,
            "policy_id": policy_id,
            "policy_content": policy_content,
            "target_orgs": target_orgs or [],
            "acknowledged": [],
            "failed": [],
            "pending": target_orgs or [],
            "created_at": datetime.utcnow().isoformat(),
            "status": "propagating",
        }
        
        self.propagations[propagation_id] = propagation
        
        # Log policy change
        self.policy_history.append({
            "propagation_id": propagation_id,
            "policy_id": policy_id,
            "action": "propagated",
            "timestamp": datetime.utcnow().isoformat(),
            "previous_version": self._get_previous_policy(policy_id),
        })
        
        logger.info(f"Policy {policy_id} propagated: {propagation_id}")
        
        # Simulate waiting for acknowledgments (in production: async Kafka listener)
        await asyncio.sleep(0.1)
        
        return {
            "propagation_id": propagation_id,
            "target_orgs": propagation["target_orgs"],
            "acknowledged": propagation["acknowledged"],
            "failed": propagation["failed"],
        }

    def acknowledge_policy(self, propagation_id: str, org_id: str) -> bool:
        """Mark organization as acknowledged policy receipt."""
        if propagation_id not in self.propagations:
            return False
        
        propagation = self.propagations[propagation_id]
        
        if org_id in propagation["pending"]:
            propagation["pending"].remove(org_id)
            propagation["acknowledged"].append(org_id)
            
            logger.info(f"Policy {propagation_id} acknowledged by {org_id}")
            
            # Check if all orgs acknowledged
            if not propagation["pending"]:
                propagation["status"] = "acknowledged"
            
            return True
        
        return False

    def timeout_policy(self, propagation_id: str) -> List[str]:
        """
        Mark unanswered orgs as failed (5-minute timeout).
        
        Returns: list of orgs that failed to acknowledge
        """
        if propagation_id not in self.propagations:
            return []
        
        propagation = self.propagations[propagation_id]
        
        # Move pending to failed
        propagation["failed"] = propagation.get("pending", [])
        propagation["pending"] = []
        propagation["status"] = "timeout"
        
        if propagation["failed"]:
            logger.warning(
                f"Policy {propagation_id} timeout: {len(propagation['failed'])} orgs failed"
            )
        
        return propagation["failed"]

    def get_propagation_status(self, propagation_id: str) -> Optional[Dict]:
        """Get status of policy propagation."""
        if propagation_id not in self.propagations:
            return None
        
        propagation = self.propagations[propagation_id]
        
        # Check timeout
        created = datetime.fromisoformat(propagation["created_at"])
        if (datetime.utcnow() - created).total_seconds() > self.ack_timeout:
            if propagation["status"] == "propagating":
                self.timeout_policy(propagation_id)
        
        return {
            "propagation_id": propagation_id,
            "status": propagation["status"],
            "acknowledged": len(propagation["acknowledged"]),
            "failed": len(propagation["failed"]),
            "pending": len(propagation["pending"]),
            "target_orgs": propagation["target_orgs"],
        }

    def get_policy_audit(self, policy_id: str) -> List[Dict]:
        """Get audit trail for policy (who changed it, when, what was previous)."""
        return [
            h for h in self.policy_history
            if h["policy_id"] == policy_id
        ]

    def _get_previous_policy(self, policy_id: str) -> Optional[str]:
        """Get previous version of policy."""
        # Placeholder: fetch from policy store
        return None

    def get_all_propagations(self) -> List[Dict]:
        """Get all policy propagations."""
        return list(self.propagations.values())
