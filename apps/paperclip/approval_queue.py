#!/usr/bin/env python3
# @file apps/paperclip/approval_queue.py
# @module paperclip/queue
# @description In-memory approval queue for the human control plane

from copy import deepcopy
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, List, Optional
import uuid

import yaml

from models import ApprovalCreate, ApprovalDecision, ApprovalRecord, ApprovalStatus


DEFAULT_ESCALATION_POLICY: Dict[str, Dict[str, object]] = {
    "tier1": {"roles": ["developer"], "timeout_minutes": 5},
    "tier2": {"roles": ["tech_lead"], "timeout_minutes": 10},
    "fallback": "auto_deny",
}


class ApprovalQueue:
    def __init__(self, config_path: Optional[str] = None):
        self._approvals: Dict[str, ApprovalRecord] = {}
        self._escalation_policy = self._load_escalation_policy(config_path)

    def _default_config_path(self) -> Path:
        return Path(__file__).resolve().parents[2] / "config" / "paperclip.yaml"

    def _load_escalation_policy(self, config_path: Optional[str]) -> Dict[str, Dict[str, object]]:
        policy = deepcopy(DEFAULT_ESCALATION_POLICY)
        path = Path(config_path) if config_path else self._default_config_path()

        if not path.exists():
            return policy

        try:
            with open(path, encoding="utf-8") as file:
                config = yaml.safe_load(file) or {}
        except Exception:
            return policy

        escalation = config.get("escalation", {}) if isinstance(config, dict) else {}
        if not isinstance(escalation, dict):
            return policy

        for tier_name in ("tier1", "tier2"):
            tier_config = escalation.get(tier_name)
            if isinstance(tier_config, dict):
                for key in ("roles", "timeout_minutes"):
                    if key in tier_config:
                        policy[tier_name][key] = tier_config[key]

        fallback = escalation.get("fallback")
        if isinstance(fallback, str) and fallback:
            policy["fallback"] = fallback

        return policy

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

    def escalate_overdue(self, now: Optional[datetime] = None) -> Dict[str, int]:
        current_time = now or datetime.now(timezone.utc)
        result = {"escalated": 0, "auto_denied": 0}
        tier1_timeout = int(self._escalation_policy["tier1"]["timeout_minutes"])
        tier2_timeout = int(self._escalation_policy["tier2"]["timeout_minutes"])
        fallback = str(self._escalation_policy.get("fallback", "auto_deny"))

        for approval in self._approvals.values():
            if approval.status not in (ApprovalStatus.PENDING, ApprovalStatus.ESCALATED):
                continue

            elapsed_minutes = (current_time - approval.created_at).total_seconds() / 60.0
            if elapsed_minutes < tier1_timeout:
                continue

            if elapsed_minutes >= tier1_timeout + tier2_timeout:
                if fallback == "auto_deny" and approval.status != ApprovalStatus.DENIED:
                    approval.status = ApprovalStatus.DENIED
                    approval.approved_by = "paperclip-system"
                    approval.decision_reason = "Escalation timeout reached; auto-denied"
                    approval.escalation_level = max(approval.escalation_level, 2)
                    approval.updated_at = current_time
                    result["auto_denied"] += 1
                continue

            if approval.status != ApprovalStatus.ESCALATED or approval.escalation_level < 1:
                approval.status = ApprovalStatus.ESCALATED
                approval.escalation_level = max(approval.escalation_level, 1)
                approval.updated_at = current_time
                result["escalated"] += 1

        return result

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
