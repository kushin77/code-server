#!/usr/bin/env python3
# @file        apps/agent-registry/billing.py
# @module      agent-registry/billing
# @description Usage tracking and billing system for agent marketplace
# @owner       Phase 4 — Ecosystem & Autonomy
# @status      active

"""
Agent Billing System

Responsibilities:
1. Track token usage per agent per org
2. Calculate charges based on pricing tier
3. Stripe integration for payments
4. Revenue split (70% author, 30% platform)
5. Usage reporting and dashboards
"""

import logging
from typing import Dict, List
from datetime import datetime, timezone
from enum import Enum

logger = logging.getLogger(__name__)


class PricingTier(str, Enum):
    """Agent pricing tiers"""
    FREE = "free"              # Unlimited usage, open source
    USAGE = "usage"            # Per 1000 tokens consumed
    SUBSCRIPTION = "subscription"  # Monthly flat rate


class UsageEvent:
    """Represents a usage event for billing"""
    
    def __init__(self, agent_id: str, org_id: str, tokens: int, timestamp: str = None):
        self.agent_id = agent_id
        self.org_id = org_id
        self.tokens = tokens
        self.timestamp = timestamp or datetime.now(timezone.utc).isoformat(timespec="seconds")


class BillingEngine:
    """Handles billing and usage tracking"""
    
    # Pricing constants
    PRICE_PER_1K_TOKENS = 0.01  # $0.01 per 1000 tokens for usage tier
    PRICE_MONTHLY_SUBSCRIPTION = 9.99  # $9.99/month for subscription tier
    
    # Revenue split
    AUTHOR_SHARE = 0.70  # 70% to author
    PLATFORM_SHARE = 0.30  # 30% to platform
    
    def __init__(self):
        """Initialize billing engine"""
        self.usage_events = []  # In-memory log (TODO: use PostgreSQL)
        self.stripe_client = None  # TODO: Initialize with API key from GSM
        logger.info("BillingEngine initialized")
    
    def track_usage(self, event: UsageEvent) -> bool:
        """
        Record a usage event for billing
        
        Args:
            event: UsageEvent with agent_id, org_id, tokens
            
        Returns:
            True if recorded successfully
        """
        try:
            self.usage_events.append(event)
            logger.info(f"Tracked usage: {event.agent_id} by {event.org_id}: {event.tokens} tokens")
            return True
        except Exception as e:
            logger.error(f"Error tracking usage: {e}")
            return False
    
    def get_usage_summary(
        self,
        agent_id: str,
        org_id: str,
        period: str = "2026-04",  # YYYY-MM format
    ) -> Dict:
        """
        Get usage summary for billing period
        
        Args:
            agent_id: Agent identifier
            org_id: Organization identifier
            period: Billing period (YYYY-MM)
            
        Returns:
            Usage summary with token count and estimated charge
        """
        try:
            # Filter events for this agent, org, and period
            period_events = [
                e for e in self.usage_events
                if e.agent_id == agent_id and
                   e.org_id == org_id and
                   e.timestamp.startswith(period)
            ]
            
            total_tokens = sum(e.tokens for e in period_events)
            
            return {
                "agent_id": agent_id,
                "org_id": org_id,
                "period": period,
                "tokens_consumed": total_tokens,
                "event_count": len(period_events),
                "estimated_charge": self._calculate_charge(total_tokens, "usage"),
            }
            
        except Exception as e:
            logger.error(f"Error getting usage summary: {e}")
            raise
    
    def _calculate_charge(self, tokens: int, pricing_tier: str) -> float:
        """
        Calculate charge based on tokens and pricing tier
        
        Args:
            tokens: Number of tokens consumed
            pricing_tier: free | usage | subscription
            
        Returns:
            Dollar amount to charge
        """
        try:
            tier = PricingTier(pricing_tier)
            
            if tier == PricingTier.FREE:
                return 0.0
            elif tier == PricingTier.USAGE:
                # $0.01 per 1000 tokens
                return round((tokens / 1000) * self.PRICE_PER_1K_TOKENS, 2)
            elif tier == PricingTier.SUBSCRIPTION:
                # Fixed monthly rate
                return self.PRICE_MONTHLY_SUBSCRIPTION
            
        except Exception as e:
            logger.error(f"Error calculating charge: {e}")
            raise
    
    def calculate_revenue_split(self, total_revenue: float) -> Dict[str, float]:
        """
        Calculate revenue split between author and platform
        
        Args:
            total_revenue: Total revenue from this agent
            
        Returns:
            Dict with author_share and platform_share
        """
        try:
            author_share = round(total_revenue * self.AUTHOR_SHARE, 2)
            platform_share = round(total_revenue * self.PLATFORM_SHARE, 2)
            
            return {
                "total_revenue": total_revenue,
                "author_share": author_share,
                "author_percentage": int(self.AUTHOR_SHARE * 100),
                "platform_share": platform_share,
                "platform_percentage": int(self.PLATFORM_SHARE * 100),
            }
            
        except Exception as e:
            logger.error(f"Error calculating revenue split: {e}")
            raise
    
    def process_payment(
        self,
        org_id: str,
        amount: float,
        stripe_token: str,
    ) -> Dict:
        """
        Process payment via Stripe
        
        Args:
            org_id: Organization to charge
            amount: Amount in dollars
            stripe_token: Stripe payment token
            
        Returns:
            Payment result with transaction ID
        """
        try:
            # TODO: Implement Stripe integration
            # 1. Create Stripe charge
            # 2. Record transaction
            # 3. Update org billing status
            # 4. Send receipt
            
            logger.warning("Stripe payment processing not yet implemented")
            return {
                "status": "pending",
                "org_id": org_id,
                "amount": amount,
                "transaction_id": "stripe_xxx_pending",
            }
            
        except Exception as e:
            logger.error(f"Error processing payment: {e}")
            raise
    
    def get_author_earnings(self, author: str, period: str = None) -> Dict:
        """
        Get earnings for an agent author
        
        Args:
            author: Author identifier
            period: Optional period filter (YYYY-MM)
            
        Returns:
            Author earnings summary
        """
        try:
            # TODO: Implement author earnings query
            # 1. Find all agents by author
            # 2. Sum usage across all their agents
            # 3. Calculate 70% share
            # 4. Apply any fees or adjustments
            
            return {
                "author": author,
                "period": period or "all-time",
                "total_earnings": 0.0,
                "pending_payout": 0.0,
                "last_payout_date": None,
            }
            
        except Exception as e:
            logger.error(f"Error getting author earnings: {e}")
            raise


# Singleton instance
_engine = BillingEngine()


def get_engine() -> BillingEngine:
    """Get billing engine singleton"""
    return _engine
