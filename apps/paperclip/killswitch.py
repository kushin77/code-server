#!/usr/bin/env python3
# @file apps/paperclip/killswitch.py
# @module paperclip/killswitch
# @description Emergency stop handler for the human control plane

from datetime import datetime, timezone
from typing import Dict, Any


class KillswitchManager:
    def __init__(self):
        self.active = False
        self.last_triggered_at = None
        self.last_triggered_by = None
        self.last_reason = None

    def trigger(self, triggered_by: str, reason: str, denied_count: int) -> Dict[str, Any]:
        self.active = True
        self.last_triggered_at = datetime.now(timezone.utc)
        self.last_triggered_by = triggered_by
        self.last_reason = reason

        return {
            "status": "triggered",
            "triggered_by": triggered_by,
            "reason": reason,
            "denied_pending_approvals": denied_count,
            "timestamp": self.last_triggered_at.isoformat(),
        }
