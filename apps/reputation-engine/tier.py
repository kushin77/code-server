"""
@file apps/reputation-engine/tier.py
@description Tier determination and access control logic
@governance GOV-002
"""

import logging
from enum import Enum
from typing import Dict, Optional
from dataclasses import dataclass

logger = logging.getLogger(__name__)


class Tier(Enum):
    """Reputation tiers."""
    ELITE = "elite"
    SENIOR = "senior"
    STANDARD = "standard"
    RESTRICTED = "restricted"


@dataclass
class TierPrivileges:
    """Privileges for each tier."""
    tier: Tier
    min_score: float
    max_score: float
    model_access: str
    daily_token_budget: int
    requires_approval: str
    can_self_approve: str
    description: str


class TierManager:
    """Manage reputation tiers and access control."""

    TIER_DEFINITIONS = {
        Tier.ELITE: TierPrivileges(
            tier=Tier.ELITE,
            min_score=90,
            max_score=100,
            model_access="llama3:70b",
            daily_token_budget=500000,
            requires_approval="none",
            can_self_approve="low,medium",
            description="Elite engineers - full autonomy"
        ),
        Tier.SENIOR: TierPrivileges(
            tier=Tier.SENIOR,
            min_score=70,
            max_score=89,
            model_access="llama3:8b",
            daily_token_budget=300000,
            requires_approval="self",
            can_self_approve="low",
            description="Senior engineers - standard access"
        ),
        Tier.STANDARD: TierPrivileges(
            tier=Tier.STANDARD,
            min_score=50,
            max_score=69,
            model_access="mistral:7b",
            daily_token_budget=100000,
            requires_approval="human",
            can_self_approve="",
            description="Standard engineers - limited access"
        ),
        Tier.RESTRICTED: TierPrivileges(
            tier=Tier.RESTRICTED,
            min_score=0,
            max_score=49,
            model_access="none",
            daily_token_budget=10000,
            requires_approval="human,mentor",
            can_self_approve="",
            description="Restricted - read-only tasks only"
        ),
    }

    @staticmethod
    def get_tier_for_score(score: float) -> Tier:
        """Determine tier from score."""
        if score >= 90:
            return Tier.ELITE
        elif score >= 70:
            return Tier.SENIOR
        elif score >= 50:
            return Tier.STANDARD
        else:
            return Tier.RESTRICTED

    @staticmethod
    def get_privileges(tier: Tier) -> TierPrivileges:
        """Get privileges for tier."""
        return TierManager.TIER_DEFINITIONS.get(tier, TierManager.TIER_DEFINITIONS[Tier.STANDARD])

    @staticmethod
    def can_access_model(tier: Tier, requested_model: str) -> bool:
        """Check if tier can access requested model."""
        privileges = TierManager.get_privileges(tier)
        
        if privileges.model_access == "none":
            return False
        
        models_by_tier = {
            Tier.ELITE: ["llama3:70b", "llama3:8b", "mistral:7b"],
            Tier.SENIOR: ["llama3:8b", "mistral:7b"],
            Tier.STANDARD: ["mistral:7b"],
            Tier.RESTRICTED: [],
        }
        
        accessible = models_by_tier.get(tier, [])
        return requested_model in accessible

    @staticmethod
    def can_perform_action(
        tier: Tier,
        action: str,
        risk_level: str = "medium"
    ) -> Dict[str, any]:
        """Check if tier can perform action."""
        privileges = TierManager.get_privileges(tier)
        
        if tier == Tier.RESTRICTED and action != "read":
            return {
                "allowed": False,
                "requires_approval": False,
                "requires_mentor": True,
                "reason": "Restricted tier can only perform read actions"
            }
        
        requires_approval = privileges.requires_approval != "none"
        requires_mentor = "mentor" in privileges.requires_approval
        can_self_approve = risk_level in privileges.can_self_approve
        
        return {
            "allowed": True,
            "requires_approval": requires_approval,
            "requires_mentor": requires_mentor,
            "can_self_approve": can_self_approve and not requires_mentor,
            "reason": "OK"
        }

    @staticmethod
    def get_daily_token_budget(tier: Tier) -> int:
        """Get daily token budget for tier."""
        privileges = TierManager.get_privileges(tier)
        return privileges.daily_token_budget

    @staticmethod
    def get_tier_badge(tier: Tier) -> str:
        """Get visual badge for tier."""
        badges = {
            Tier.ELITE: "⭐ Elite",
            Tier.SENIOR: "🥇 Senior",
            Tier.STANDARD: "🥈 Standard",
            Tier.RESTRICTED: "🔒 Restricted",
        }
        return badges.get(tier, "Unknown")


class TierTransitionManager:
    """Manage tier transitions and recovery."""

    RECOVERY_POINTS_REQUIRED = 100
    RECOVERY_MULTIPLIER = 2.0

    @staticmethod
    def should_promote(current_score: float, new_score: float) -> bool:
        """Check if score change should trigger tier promotion."""
        current_tier = TierManager.get_tier_for_score(current_score)
        new_tier = TierManager.get_tier_for_score(new_score)
        
        return new_tier.value != current_tier.value and new_tier.value > current_tier.value

    @staticmethod
    def should_demote(current_score: float, new_score: float) -> bool:
        """Check if score change should trigger tier demotion."""
        current_tier = TierManager.get_tier_for_score(current_score)
        new_tier = TierManager.get_tier_for_score(new_score)
        
        return new_tier.value != current_tier.value and new_tier.value < current_tier.value

    @staticmethod
    def check_recovery_eligibility(history_events: list) -> Dict[str, any]:
        """Check if restricted entity is eligible for recovery."""
        if not history_events:
            return {
                "eligible": False,
                "points_earned": 0,
                "points_needed": TierTransitionManager.RECOVERY_POINTS_REQUIRED,
                "reason": "No history"
            }
        
        recent = history_events[-5:]
        if len(recent) >= 5:
            all_success = all(
                event.get("signals", {}).get("success", False) 
                for event in recent
            )
            all_no_override = all(
                not event.get("signals", {}).get("human_override", False)
                for event in recent
            )
            
            if all_success and all_no_override:
                return {
                    "eligible": True,
                    "points_earned": 50,
                    "points_needed": 50,
                    "recovery_method": "task_completion",
                    "reason": "5 consecutive successful tasks with no overrides"
                }
        
        mentor_vouches = sum(
            1 for event in history_events[-10:]
            if event.get("event_type") == "mentor_vouch"
        )
        
        if mentor_vouches > 0:
            return {
                "eligible": True,
                "points_earned": mentor_vouches * 10,
                "points_needed": TierTransitionManager.RECOVERY_POINTS_REQUIRED - (mentor_vouches * 10),
                "recovery_method": "mentor_vouch",
                "reason": f"{mentor_vouches} mentor vouch(es)"
            }
        
        return {
            "eligible": False,
            "points_earned": 0,
            "points_needed": TierTransitionManager.RECOVERY_POINTS_REQUIRED,
            "reason": "Not eligible for recovery yet"
        }

    @staticmethod
    def get_mentor_vouch_boost() -> float:
        """Get score boost from mentor vouch."""
        return 10.0

    @staticmethod
    def get_recovery_point_value(base_points: float) -> float:
        """Get value of points during recovery period."""
        return base_points * TierTransitionManager.RECOVERY_MULTIPLIER


class AccessPolicyBuilder:
    """Build OPA policies for tier-based access."""

    @staticmethod
    def generate_opa_policy() -> str:
        """Generate OPA policy for tier-based access."""
        return '''
package reputation

# Elite tier - full autonomy
allow_deploy {
    data.reputation.engineers[input.user].tier == "elite"
}

allow_model_access["llama3:70b"] {
    data.reputation.engineers[input.user].tier == "elite"
}

allow_self_approve {
    data.reputation.engineers[input.user].tier == "elite"
    input.risk_level in ["low", "medium"]
}

# Senior tier - standard access
allow_deploy {
    data.reputation.engineers[input.user].tier == "senior"
    input.requires_mentor == false
}

allow_model_access["llama3:8b"] {
    data.reputation.engineers[input.user].tier in ["elite", "senior"]
}

allow_self_approve {
    data.reputation.engineers[input.user].tier == "senior"
    input.risk_level == "low"
}

# Standard tier - limited access
allow_deploy {
    data.reputation.engineers[input.user].tier == "standard"
    input.requires_approval == true
}

allow_model_access["mistral:7b"] {
    data.reputation.engineers[input.user].tier in ["elite", "senior", "standard"]
}

# Restricted tier - read-only
deny_all_writes {
    data.reputation.engineers[input.user].tier == "restricted"
    input.action in ["write", "delete", "deploy"]
}

# Agent access policies
allow_agent_task {
    score := data.reputation.agents[input.agent_id].score
    score >= 70
}

deny_agent_high_risk {
    score := data.reputation.agents[input.agent_id].score
    score < 50
    input.risk_level == "high"
}
'''
