"""
@file apps/paperclip/opa_integration.py
@description OPA policy queries for approval governance and tier-based access control
@governance GOV-002
"""

import os
import requests
from typing import Dict, Any, Optional
import config as _svc_config
from log import get_logger

logger = get_logger(__name__)





class OPAPolicyManager:
    """Query OPA for approval policies and governance rules."""

    def __init__(self, opa_url: str = "http://opa:8181"):
        config = get_config()
        self.opa_url = opa_url or _svc_config.OPA_URL
        self.timeout = 10

    def check_approval_policy(
        self,
        user_id: str,
        approval_type: str,
        risk_level: str = "medium",
    ) -> Dict[str, Any]:
        """
        Check OPA policy for approval eligibility.
        
        Args:
            user_id: User requesting approval
            approval_type: Type of approval (deploy, config_change, etc.)
            risk_level: Risk level of action (low, medium, high, critical)
        
        Returns:
            {"allowed": bool, "reason": str, "requires_escalation": bool}
        """
        try:
            query = {
                "user_id": user_id,
                "approval_type": approval_type,
                "risk_level": risk_level,
            }

            response = requests.post(
                f"{self.opa_url}/v1/data/paperclip/can_approve",
                json=query,
                timeout=self.timeout,
            )

            if response.status_code != 200:
                logger.warning(f"OPA policy check failed: {response.status_code}")
                # Fail-safe: require escalation if OPA is unavailable
                return {
                    "allowed": False,
                    "reason": "Policy service unavailable",
                    "requires_escalation": True,
                }

            data = response.json()
            return data.get("result", {
                "allowed": False,
                "reason": "No policy result",
                "requires_escalation": True,
            })

        except requests.RequestException as e:
            logger.error(f"OPA connection error: {e}")
            return {
                "allowed": False,
                "reason": f"OPA unavailable: {str(e)}",
                "requires_escalation": True,
            }

    def get_approval_rules(self, approval_type: str) -> Dict[str, Any]:
        """
        Get approval rules for a specific approval type.
        
        Returns governance rules (timeout thresholds, escalation paths, etc.)
        """
        try:
            response = requests.get(
                f"{self.opa_url}/v1/data/paperclip/approval_rules/{approval_type}",
                timeout=self.timeout,
            )

            if response.status_code == 200:
                return response.json().get("result", {})
            else:
                logger.warning(f"Failed to fetch approval rules: {response.status_code}")
                return {}

        except requests.RequestException as e:
            logger.error(f"OPA connection error fetching rules: {e}")
            return {}

    def validate_escalation_path(
        self,
        approval_id: str,
        from_tier: str,
        to_tier: str,
    ) -> bool:
        """
        Validate that escalation from one tier to another is allowed.
        """
        try:
            query = {
                "approval_id": approval_id,
                "from_tier": from_tier,
                "to_tier": to_tier,
            }

            response = requests.post(
                f"{self.opa_url}/v1/data/paperclip/can_escalate",
                json=query,
                timeout=self.timeout,
            )

            if response.status_code == 200:
                result = response.json().get("result", False)
                return result
            else:
                logger.warning(f"Escalation validation failed: {response.status_code}")
                return False

        except requests.RequestException as e:
            logger.error(f"OPA escalation check failed: {e}")
            return False

    def health_check(self) -> bool:
        """Check if OPA is accessible and healthy."""
        try:
            response = requests.get(
                f"{self.opa_url}/health",
                timeout=self.timeout,
            )
            return response.status_code == 200
        except requests.RequestException:
            return False
