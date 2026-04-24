#!/usr/bin/env python3
# @file apps/paperclip/heartbeat.py
# @module paperclip/heartbeat
# @description Agent heartbeat tracking for the human control plane

from datetime import datetime, timedelta, timezone
from typing import Dict, List

from models import HeartbeatCreate, HeartbeatRecord


class HeartbeatMonitor:
    def __init__(self):
        self._heartbeats: Dict[str, HeartbeatRecord] = {}

    def record(self, heartbeat: HeartbeatCreate) -> HeartbeatRecord:
        record = HeartbeatRecord(
            agent_id=heartbeat.agent_id,
            task_id=heartbeat.task_id,
            last_action=heartbeat.last_action,
            status=heartbeat.status,
            eta_seconds=heartbeat.eta_seconds,
            last_seen_at=datetime.now(timezone.utc),
        )
        self._heartbeats[heartbeat.agent_id] = record
        return record

    def list_active(self, stale_after_seconds: int = 60) -> List[HeartbeatRecord]:
        cutoff = datetime.now(timezone.utc) - timedelta(seconds=stale_after_seconds)
        return [record for record in self._heartbeats.values() if record.last_seen_at >= cutoff]

    def list_unresponsive(self, stale_after_seconds: int = 60) -> List[HeartbeatRecord]:
        cutoff = datetime.now(timezone.utc) - timedelta(seconds=stale_after_seconds)
        return [record for record in self._heartbeats.values() if record.last_seen_at < cutoff]
