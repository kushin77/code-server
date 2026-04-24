#!/usr/bin/env python3
# @file        apps/paperclip-control-plane/escalation.py
# @module      paperclip/control-plane
# @description Escalation logic - timer-driven chain for approval routing
# @owner       paperclip/control-plane
# @status      production-ready
#
# Escalation chain: Tier 1 (5m) → Tier 2 (10m) → auto-deny

import asyncio
import logging
from typing import Dict, Any, List
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from sqlalchemy import and_

from .models import ApprovalQueue, ApprovalStatus, EscalationTier, EscalationEvent

logger = logging.getLogger(__name__)


class EscalationEngine:
    """Drive escalations through approval chain"""

    def __init__(self, db_session: Session, config: Dict[str, Any]):
        self.db = db_session
        self.config = config
        self.escalation_config = config.get("escalation", {})

    def check_tier1_timeout(self) -> int:
        """
        Check for Tier 1 approvals that exceeded SLA
        Escalate to Tier 2
        
        Returns: count of escalations
        """
        now = datetime.utcnow()
        tier1_expired = self.db.query(ApprovalQueue).filter(
            and_(
                ApprovalQueue.status == ApprovalStatus.PENDING,
                ApprovalQueue.current_tier == EscalationTier.TIER_1,
                ApprovalQueue.tier1_expires_at <= now
            )
        ).all()

        count = 0
        tier2_timeout_mins = self.escalation_config.get("tier2", {}).get("timeout_minutes", 10)
        
        for approval in tier1_expired:
            # Create escalation event (audit trail)
            escalation = EscalationEvent(
                approval_id=approval.id,
                from_tier=EscalationTier.TIER_1,
                to_tier=EscalationTier.TIER_2,
                reason="tier_1_timeout",
                notified_roles=self.escalation_config.get("tier2", {}).get("roles", ["tech_lead"]),
                notification_count=0,
            )
            
            # Update approval
            approval.status = ApprovalStatus.ESCALATED
            approval.current_tier = EscalationTier.TIER_2
            approval.tier2_expires_at = now + timedelta(minutes=tier2_timeout_mins)
            escalation.new_deadline = approval.tier2_expires_at
            
            self.db.add(escalation)
            count += 1
            
            logger.info(
                f"Escalated approval {approval.id} to Tier 2 "
                f"(agent={approval.agent_id}, task={approval.task_id})"
            )

        if count > 0:
            self.db.commit()
            logger.info(f"Escalated {count} approvals from Tier 1 → Tier 2")

        return count

    def check_tier2_timeout(self) -> int:
        """
        Check for Tier 2 approvals that exceeded SLA
        Either escalate to Tier 3 or auto-deny based on config
        
        Returns: count of escalations
        """
        now = datetime.utcnow()
        tier2_expired = self.db.query(ApprovalQueue).filter(
            and_(
                ApprovalQueue.status == ApprovalStatus.ESCALATED,
                ApprovalQueue.current_tier == EscalationTier.TIER_2,
                ApprovalQueue.tier2_expires_at.isnot(None),
                ApprovalQueue.tier2_expires_at <= now
            )
        ).all()

        count = 0
        fallback_action = self.escalation_config.get("fallback", "auto_deny")
        
        for approval in tier2_expired:
            if fallback_action == "auto_deny":
                # Auto-deny with reputation penalty for agent
                escalation = EscalationEvent(
                    approval_id=approval.id,
                    from_tier=EscalationTier.TIER_2,
                    to_tier=EscalationTier.AUTO_DENY,
                    reason="tier_2_timeout_auto_deny",
                    notified_roles=["system"],
                    notification_count=0,
                )
                
                approval.status = ApprovalStatus.DENIED
                approval.approver_id = "system"
                approval.approval_reason = "Auto-denied: Tier 2 SLA exceeded"
                approval.approval_decision_at = now
                approval.current_tier = EscalationTier.AUTO_DENY
                
                self.db.add(escalation)
                count += 1
                
                logger.warning(
                    f"Auto-denied approval {approval.id} after Tier 2 timeout "
                    f"(agent={approval.agent_id}, task={approval.task_id}) - "
                    f"reputation penalty pending"
                )
            else:
                # Future: Tier 3 escalation (CTO level)
                logger.info(f"Tier 3 escalation not yet implemented for approval {approval.id}")

        if count > 0:
            self.db.commit()
            logger.info(f"Auto-denied {count} approvals after Tier 2 timeout")

        return count

    async def run_escalation_loop(self, check_interval_seconds: int = 30):
        """
        Background task: periodically check for escalations
        
        Run as: asyncio.create_task(escalation_engine.run_escalation_loop())
        """
        logger.info("Starting escalation loop")
        
        while True:
            try:
                # Check Tier 1 timeouts
                tier1_count = self.check_tier1_timeout()
                
                # Check Tier 2 timeouts
                tier2_count = self.check_tier2_timeout()
                
                if tier1_count + tier2_count > 0:
                    logger.info(
                        f"Escalation cycle: T1→T2={tier1_count}, T2→deny={tier2_count}"
                    )
                
                await asyncio.sleep(check_interval_seconds)
                
            except Exception as e:
                logger.error(f"Error in escalation loop: {e}", exc_info=True)
                await asyncio.sleep(check_interval_seconds)

    def get_escalation_chain(self, approval_id: int) -> List[Dict[str, Any]]:
        """Get escalation history for a specific approval (audit trail)"""
        events = self.db.query(EscalationEvent).filter(
            EscalationEvent.approval_id == approval_id
        ).order_by(EscalationEvent.escalated_at).all()
        
        return [
            {
                "from_tier": str(e.from_tier.value),
                "to_tier": str(e.to_tier.value),
                "reason": e.reason,
                "escalated_at": e.escalated_at.isoformat(),
                "new_deadline": e.new_deadline.isoformat(),
                "notified_roles": e.notified_roles,
            }
            for e in events
        ]

    def get_escalation_stats(self) -> Dict[str, Any]:
        """Get escalation queue statistics"""
        tier1_backlog = self.db.query(ApprovalQueue).filter(
            and_(
                ApprovalQueue.status == ApprovalStatus.PENDING,
                ApprovalQueue.current_tier == EscalationTier.TIER_1,
            )
        ).count()
        
        tier2_backlog = self.db.query(ApprovalQueue).filter(
            and_(
                ApprovalQueue.status == ApprovalStatus.ESCALATED,
                ApprovalQueue.current_tier == EscalationTier.TIER_2,
            )
        ).count()
        
        return {
            "tier_1_pending": tier1_backlog,
            "tier_2_escalated": tier2_backlog,
            "total_in_chain": tier1_backlog + tier2_backlog,
        }
