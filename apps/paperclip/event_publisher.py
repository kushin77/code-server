#!/usr/bin/env python3
# @file apps/paperclip/event_publisher.py
# @module paperclip/events
# @description Lightweight event publisher for Paperclip control-plane events

from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import uuid


@dataclass
class PaperclipEvent:
    event_id: str
    event_type: str
    timestamp: str
    source: Dict[str, str]
    actor: Dict[str, Any]
    payload: Dict[str, Any]
    correlation_id: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        data = asdict(self)
        if data.get("correlation_id") is None:
            data.pop("correlation_id", None)
        return data


class PaperclipEventPublisher:
    def __init__(self, service_name: str = "paperclip", instance_id: str = "local"):
        self.service_name = service_name
        self.instance_id = instance_id
        self._published_events: List[PaperclipEvent] = []

    def publish(
        self,
        event_type: str,
        payload: Dict[str, Any],
        actor_id: str,
        actor_type: str = "system",
        correlation_id: Optional[str] = None,
    ) -> PaperclipEvent:
        event = PaperclipEvent(
            event_id=str(uuid.uuid4()),
            event_type=event_type,
            timestamp=datetime.now(timezone.utc).isoformat(),
            source={"service": self.service_name, "instance": self.instance_id},
            actor={"type": actor_type, "id": actor_id},
            payload=payload,
            correlation_id=correlation_id,
        )
        self._published_events.append(event)
        return event

    def publish_pending_approval(self, approval) -> PaperclipEvent:
        return self.publish(
            "agent.awaiting_approval",
            {
                "approval_id": approval.approval_id,
                "agent_id": approval.agent_id,
                "task_id": approval.task_id,
                "action_description": approval.action_description,
                "risk_score": approval.risk_score,
                "diff_preview": approval.diff_preview,
                "timeout_minutes": approval.timeout_minutes,
                "status": approval.status.value,
            },
            actor_id=approval.requested_by or approval.agent_id,
            actor_type="agent",
            correlation_id=approval.approval_id,
        )

    def publish_escalated_approval(self, approval) -> PaperclipEvent:
        return self.publish(
            "approval.escalated",
            {
                "approval_id": approval.approval_id,
                "agent_id": approval.agent_id,
                "task_id": approval.task_id,
                "status": approval.status.value,
                "escalation_level": approval.escalation_level,
                "timeout_minutes": approval.timeout_minutes,
            },
            actor_id=approval.requested_by or approval.agent_id,
            actor_type="system",
            correlation_id=approval.approval_id,
        )

    def publish_killswitch(self, triggered_by: str, reason: str, denied_count: int) -> PaperclipEvent:
        return self.publish(
            "agent.killswitch",
            {
                "triggered_by": triggered_by,
                "reason": reason,
                "denied_pending_approvals": denied_count,
            },
            actor_id=triggered_by,
            actor_type="human",
            correlation_id=str(uuid.uuid4()),
        )

    def list_events(self, event_type: Optional[str] = None) -> List[Dict[str, Any]]:
        events = self._published_events
        if event_type is not None:
            events = [event for event in events if event.event_type == event_type]
        return [event.to_dict() for event in events]

    def clear(self) -> None:
        self._published_events.clear()