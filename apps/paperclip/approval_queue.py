#!/usr/bin/env python3
# @file apps/paperclip/approval_queue.py
# @module paperclip/queue
# @description In-memory approval queue for the human control plane

from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional
import uuid

from models import ApprovalCreate, ApprovalDecision, ApprovalRecord, ApprovalStatus


class ApprovalQueue:
    def __init__(self):
        self._approvals: Dict[str, ApprovalRecord] = {}

    def submit(self, request: ApprovalCreate) -> ApprovalRecord:
        approval = ApprovalRecord(
            approval_id=f"approval-{uuid.uuid4().hex[:12]}",
            agent_id=request.agent_id,
            task_id=request.task_id,
            action_description=request.action_description,
            risk_score=request.risk_score,
            diff_preview=request.diff_preview,
            timeout_minutes=request.timeout_minutes,
            requested_by=request.requested_by,
        )
        self._approvals[approval.approval_id] = approval
        return approval

    def list_pending(self) -> List[ApprovalRecord]:
        return [approval for approval in self._approvals.values() if approval.status == ApprovalStatus.PENDING]

    def list_escalated(self) -> List[ApprovalRecord]:
        return [approval for approval in self._approvals.values() if approval.status == ApprovalStatus.ESCALATED]

    def get(self, approval_id: str) -> Optional[ApprovalRecord]:
        return self._approvals.get(approval_id)

    def approve(self, approval_id: str, decision: ApprovalDecision) -> ApprovalRecord:
        return self._apply_decision(approval_id, ApprovalStatus.APPROVED, decision)

    def deny(self, approval_id: str, decision: ApprovalDecision) -> ApprovalRecord:
        return self._apply_decision(approval_id, ApprovalStatus.DENIED, decision)

    def delegate(self, approval_id: str, decision: ApprovalDecision) -> ApprovalRecord:
        return self._apply_decision(approval_id, ApprovalStatus.DELEGATED, decision)

    def deny_all_pending(self, reason: str, triggered_by: str) -> int:
        denied = 0
        for approval in list(self._approvals.values()):
            if approval.status in (ApprovalStatus.PENDING, ApprovalStatus.ESCALATED):
                approval.status = ApprovalStatus.DENIED
                approval.approved_by = triggered_by
                approval.decision_reason = reason
                approval.updated_at = datetime.now(timezone.utc)
                denied += 1
        return denied

    def escalate_overdue(self, now: Optional[datetime] = None) -> int:
        current_time = now or datetime.now(timezone.utc)
        escalated = 0

        for approval in self._approvals.values():
            if approval.status != ApprovalStatus.PENDING:
                continue

            deadline = approval.created_at + timedelta(minutes=approval.timeout_minutes)
            if current_time >= deadline:
                approval.status = ApprovalStatus.ESCALATED
                approval.escalation_level += 1
                approval.updated_at = current_time
                escalated += 1

        return escalated

    def _apply_decision(
        self,
        approval_id: str,
        status: ApprovalStatus,
        decision: ApprovalDecision,
    ) -> ApprovalRecord:
        approval = self._approvals.get(approval_id)
        if approval is None:
            raise KeyError(f"Approval not found: {approval_id}")

        approval.status = status
        approval.approved_by = decision.approver
        approval.decision_reason = decision.reason
        approval.delegated_to = decision.delegate_to
        approval.updated_at = datetime.now(timezone.utc)
        return approval
