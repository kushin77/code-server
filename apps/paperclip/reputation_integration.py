"""
@file apps/paperclip/reputation_integration.py
@description Reputation-Engine queries for tier-based approval authority
@governance GOV-002
"""

import os
import requests
import logging
from typing import Dict, Any, Optional
import config as _svc_config



logger = logging.getLogger(__name__)


class ReputationTierManager:
    """Query Reputation Engine for user tier and approval authority."""

    def __init__(self, reputation_url: Optional[str] = None):
        config = get_config()
        self.reputation_url = reputation_url or _svc_config.REPUTATION_ENGINE_URL
        self.timeout = 10

    def get_user_tier(self, user_id: str) -> Optional[str]:
        """
        Get user's reputation tier.
        
        Returns: "elite", "senior", "standard", "restricted", or None if not found
        """
        try:
            response = requests.get(
                f"{self.reputation_url}/reputation/users/{user_id}",
                timeout=self.timeout,
            )

            if response.status_code == 200:
                data = response.json()
                return data.get("tier")
            else:
                logger.warning(f"Failed to fetch user tier for {user_id}: {response.status_code}")
                return None

        except requests.RequestException as e:
            logger.error(f"Reputation service connection error: {e}")
            return None

    def can_approve_high_risk(self, user_id: str) -> bool:
        """
        Check if user's tier permits approval of high-risk actions.
        
        Elite: Can approve all risk levels
        Senior: Can approve medium/high risk
        Standard: Can only approve low/medium risk
        Restricted: Cannot approve anything
        """
        tier = self.get_user_tier(user_id)

        if tier in ("elite", "senior"):
            return True
        elif tier == "standard":
            return False  # Standard users need escalation for high-risk
        else:  # restricted or unknown
            return False

    def can_approve_critical(self, user_id: str) -> bool:
        """Check if user can approve critical-risk actions (elite only)."""
        tier = self.get_user_tier(user_id)
        return tier == "elite"

    def get_approval_authority_level(self, user_id: str) -> Dict[str, Any]:
        """
        Get detailed approval authority based on reputation tier.
        
        Returns authority constraints for different risk levels.
        """
        tier = self.get_user_tier(user_id)

        authority_matrix = {
            "elite": {
                "tier": "elite",
                "can_approve_low": True,
                "can_approve_medium": True,
                "can_approve_high": True,
                "can_approve_critical": True,
                "requires_escalation": False,
                "daily_approval_limit": None,  # Unlimited
            },
            "senior": {
                "tier": "senior",
                "can_approve_low": True,
                "can_approve_medium": True,
                "can_approve_high": True,
                "can_approve_critical": False,
                "requires_escalation_for": ["critical"],
                "daily_approval_limit": 50,
            },
            "standard": {
                "tier": "standard",
                "can_approve_low": True,
                "can_approve_medium": True,
                "can_approve_high": False,
                "can_approve_critical": False,
                "requires_escalation_for": ["high", "critical"],
                "daily_approval_limit": 10,
            },
            "restricted": {
                "tier": "restricted",
                "can_approve_low": False,
                "can_approve_medium": False,
                "can_approve_high": False,
                "can_approve_critical": False,
                "cannot_approve": True,
                "daily_approval_limit": 0,
            },
        }

        return authority_matrix.get(
            tier,
            {
                "tier": "unknown",
                "error": f"Unknown tier: {tier}",
                "cannot_approve": True,
                "daily_approval_limit": 0,
            },
        )

    def health_check(self) -> bool:
        """Check if Reputation Engine is accessible."""
        try:
            response = requests.get(
                f"{self.reputation_url}/health",
                timeout=self.timeout,
            )
            return response.status_code == 200
        except requests.RequestException:
            return False
