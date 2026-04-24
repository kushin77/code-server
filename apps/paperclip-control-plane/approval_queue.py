#!/usr/bin/env python3
# @file        apps/paperclip-control-plane/approval_queue.py
# @module      paperclip/control-plane
# @description Approval queue service - consumer, persistence, fast API access
# @owner       paperclip/control-plane
# @status      production-ready
#
# Kafka consumer for agent.awaiting_approval → persistent queue → IDE display

import asyncio
import json
import logging
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta
from dataclasses import dataclass

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from .models import ApprovalQueue, ApprovalStatus, EscalationTier

logger = logging.getLogger(__name__)

@dataclass
class ApprovalAction:
    """Represents an action awaiting approval"""
    agent_id: str
    task_id: str
    action_type: str
    action_description: str
    estimated_cost_tokens: float = 0.0


class ApprovalQueueService:
    """Manage approval queue persistence and retrieval"""

    def __init__(self, db_session: Session):
        self.db = db_session

    def submit_action(
        self,
        action: ApprovalAction,
        config: Dict[str, Any]
    ) -> int:
        """
        Submit an action for approval
        
        Returns: approval_id (for tracking)
        """
        now = datetime.utcnow()
        tier1_timeout_mins = config.get("escalation", {}).get("tier1", {}).get("timeout_minutes", 5)
        
        approval = ApprovalQueue(
            agent_id=action.agent_id,
            task_id=action.task_id,
            action_type=action.action_type,
            action_description=action.action_description,
            estimated_cost_tokens=action.estimated_cost_tokens,
            status=ApprovalStatus.PENDING,
            current_tier=EscalationTier.TIER_1,
            tier1_expires_at=now + timedelta(minutes=tier1_timeout_mins),
            final_deadline=now + timedelta(minutes=tier1_timeout_mins + 15),  # Hard stop
        )
        
        self.db.add(approval)
        self.db.commit()
        
        logger.info(f"Approval submitted: {approval.id} for agent={action.agent_id}, task={action.task_id}")
        return approval.id

    def get_pending_approvals(self, limit: int = 50) -> List[ApprovalQueue]:
        """Get all pending approvals (for display in IDE)"""
        return self.db.query(ApprovalQueue).filter(
            ApprovalQueue.status.in_([
                ApprovalStatus.PENDING,
                ApprovalStatus.ESCALATED,
            ])
        ).order_by(ApprovalQueue.submitted_at).limit(limit).all()

    def get_approval_by_id(self, approval_id: int) -> Optional[ApprovalQueue]:
        """Fetch specific approval"""
        return self.db.query(ApprovalQueue).filter(
            ApprovalQueue.id == approval_id
        ).first()

    def approve_action(
        self,
        approval_id: int,
        approver_id: str,
        reason: str = ""
    ) -> bool:
        """
        Approve an action
        
        Returns: success
        """
        approval = self.get_approval_by_id(approval_id)
        if not approval:
            logger.warning(f"Approval not found: {approval_id}")
            return False

        if approval.status != ApprovalStatus.PENDING:
            logger.warning(f"Approval {approval_id} not pending: {approval.status}")
            return False

        approval.status = ApprovalStatus.APPROVED
        approval.approver_id = approver_id
        approval.approval_reason = reason
        approval.approval_decision_at = datetime.utcnow()
        
        self.db.commit()
        logger.info(f"Approval {approval_id} approved by {approver_id}")
        return True

    def deny_action(
        self,
        approval_id: int,
        approver_id: str,
        reason: str = ""
    ) -> bool:
        """
        Deny an action
        
        Returns: success
        """
        approval = self.get_approval_by_id(approval_id)
        if not approval:
            logger.warning(f"Approval not found: {approval_id}")
            return False

        if approval.status not in [ApprovalStatus.PENDING, ApprovalStatus.ESCALATED]:
            logger.warning(f"Approval {approval_id} cannot be denied: {approval.status}")
            return False

        approval.status = ApprovalStatus.DENIED
        approval.approver_id = approver_id
        approval.approval_reason = reason
        approval.approval_decision_at = datetime.utcnow()
        
        self.db.commit()
        logger.info(f"Approval {approval_id} denied by {approver_id}: {reason}")
        return True

    def check_expiry(self) -> int:
        """
        Check for expired approvals and auto-deny
        
        Returns: count of expired items
        """
        now = datetime.utcnow()
        expired = self.db.query(ApprovalQueue).filter(
            and_(
                ApprovalQueue.status.in_([
                    ApprovalStatus.PENDING,
                    ApprovalStatus.ESCALATED,
                ]),
                ApprovalQueue.final_deadline <= now
            )
        ).all()

        count = 0
        for approval in expired:
            approval.status = ApprovalStatus.EXPIRED
            approval.approver_id = "system"
            approval.approval_reason = "Auto-denied: deadline exceeded"
            approval.approval_decision_at = now
            count += 1

        if count > 0:
            self.db.commit()
            logger.info(f"Auto-denied {count} expired approvals")

        return count

    def get_approval_stats(self) -> Dict[str, Any]:
        """Get approval queue statistics"""
        pending = self.db.query(ApprovalQueue).filter(
            ApprovalQueue.status == ApprovalStatus.PENDING
        ).count()
        
        escalated = self.db.query(ApprovalQueue).filter(
            ApprovalQueue.status == ApprovalStatus.ESCALATED
        ).count()
        
        approved_today = self.db.query(ApprovalQueue).filter(
            and_(
                ApprovalQueue.status == ApprovalStatus.APPROVED,
                ApprovalQueue.approval_decision_at >= datetime.utcnow() - timedelta(days=1)
            )
        ).count()
        
        denied_today = self.db.query(ApprovalQueue).filter(
            and_(
                ApprovalQueue.status == ApprovalStatus.DENIED,
                ApprovalQueue.approval_decision_at >= datetime.utcnow() - timedelta(days=1)
            )
        ).count()
        
        return {
            "pending": pending,
            "escalated": escalated,
            "approved_today": approved_today,
            "denied_today": denied_today,
            "queued_tokens_estimated": self.db.query(ApprovalQueue).filter(
                ApprovalQueue.status.in_([
                    ApprovalStatus.PENDING,
                    ApprovalStatus.ESCALATED,
                ])
            ).with_entities(lambda x: x.estimated_cost_tokens).scalar() or 0.0,
        }


class KafkaApprovalConsumer:
    """Consume agent.awaiting_approval events from Kafka"""

    def __init__(self, queue_service: ApprovalQueueService, config: Dict[str, Any]):
        self.queue_service = queue_service
        self.config = config
        self.running = False

    async def start(self, kafka_brokers: List[str]):
        """Start consuming approval events"""
        # Kafka consumer would be initialized here
        # For Phase 1, we focus on queue persistence and API interface
        # Kafka integration happens in Phase 2
        logger.info("Approval consumer ready (Kafka integration in Phase 2)")

    def consume_event(self, event: Dict[str, Any]) -> Optional[int]:
        """
        Process incoming approval event from Kafka
        
        Expected event format:
        {
            "agent_id": "engineer-001",
            "task_id": "task-123",
            "action_type": "deploy",
            "action_description": "Deploy v2.1.0 to production",
            "estimated_cost_tokens": 15000.0
        }
        """
        try:
            action = ApprovalAction(
                agent_id=event["agent_id"],
                task_id=event["task_id"],
                action_type=event["action_type"],
                action_description=event["action_description"],
                estimated_cost_tokens=event.get("estimated_cost_tokens", 0.0),
            )
            approval_id = self.queue_service.submit_action(action, self.config)
            return approval_id
        except KeyError as e:
            logger.error(f"Invalid approval event: missing {e}")
            return None
