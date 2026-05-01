#!/usr/bin/env python3
# @file apps/activity-feed/consumer.py
# @module infrastructure/activity-feed
# @description P3-1560 Phase 3: Kafka consumer aggregating all topics into activity feed
# @governance GOV-002: All engineering events persisted and auditable

import json
import asyncio
from datetime import datetime
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
import logging

from apps._shared.python.logging import get_logger

logger = get_logger(__name__)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class ActivityEvent:
    """Unified activity event from any Kafka topic"""
    event_id: str
    event_type: str
    timestamp: datetime
    actor_id: str
    actor_type: str
    service: str
    title: str
    description: str
    status: str
    severity: str = "info"  # info, warning, error
    tags: List[str] = None
    metadata: Dict[str, Any] = None
    
    def __post_init__(self):
        if self.tags is None:
            self.tags = []
        if self.metadata is None:
            self.metadata = {}

class ActivityFeedConsumer:
    """Consumes all Kafka topics and aggregates into activity feed"""
    
    def __init__(self, kafka_brokers: str = "localhost:9092"):
        self.kafka_brokers = kafka_brokers
        self.topics = [
            "agent.audit",
            "agent.lifecycle",
            "deploy.events",
            "code.review",
            "incident.events",
            "ai.interactions",
            "reputation.update",
            "system.alerts"
        ]
        self.activity_buffer: List[ActivityEvent] = []
    
    async def consume_all_topics(self):
        """Start consuming from all topics"""
        logger.info(f"Starting activity feed consumer for {len(self.topics)} topics")
        
        # Would use kafka consumer library to connect and consume
        # For now, log the setup
        logger.info(f"Connected to Kafka brokers: {self.kafka_brokers}")
    
    def _parse_agent_audit_event(self, raw_event: Dict[str, Any]) -> ActivityEvent:
        """Parse agent.audit topic event"""
        payload = raw_event.get("payload", {})
        actor = raw_event.get("actor", {})
        
        status_to_severity = {
            "success": "info",
            "failure": "error",
            "timeout": "warning",
            "cancelled": "warning"
        }
        
        return ActivityEvent(
            event_id=raw_event["event_id"],
            event_type="agent.audit",
            timestamp=datetime.fromisoformat(raw_event["timestamp"].replace("Z", "+00:00")),
            actor_id=actor.get("id", "unknown"),
            actor_type="agent",
            service=raw_event.get("source", {}).get("service", "agent-runtime"),
            title=f"Agent: {payload.get('task_description', 'Unknown task')}",
            description=f"Status: {payload.get('status')} | Duration: {payload.get('duration_seconds')}s",
            status=payload.get("status", "unknown"),
            severity=status_to_severity.get(payload.get("status"), "info"),
            tags=["agent", payload.get("status", "")],
            metadata={
                "task_id": payload.get("task_id"),
                "tokens_used": payload.get("tokens_used"),
                "error": payload.get("error_message")
            }
        )
    
    def _parse_deploy_event(self, raw_event: Dict[str, Any]) -> ActivityEvent:
        """Parse deploy.events topic event"""
        payload = raw_event.get("payload", {})
        actor = raw_event.get("actor", {})
        
        status_to_severity = {
            "started": "info",
            "completed": "info",
            "failed": "error",
            "rolled_back": "warning"
        }
        
        services = ", ".join(payload.get("services", []))
        
        return ActivityEvent(
            event_id=raw_event["event_id"],
            event_type="deploy.events",
            timestamp=datetime.fromisoformat(raw_event["timestamp"].replace("Z", "+00:00")),
            actor_id=actor.get("id", "system"),
            actor_type=actor.get("type", "human"),
            service="deploy-orchestrator",
            title=f"Deployment: {payload.get('status').upper()}",
            description=f"Services: {services} | Environment: {payload.get('environment')}",
            status=payload.get("status", "unknown"),
            severity=status_to_severity.get(payload.get("status"), "info"),
            tags=["deployment", payload.get("environment", ""), payload.get("status", "")],
            metadata={
                "deploy_id": payload.get("deploy_id"),
                "git_commit": payload.get("git_commit"),
                "duration_seconds": payload.get("duration_seconds")
            }
        )
    
    def _parse_incident_event(self, raw_event: Dict[str, Any]) -> ActivityEvent:
        """Parse incident.events topic event"""
        payload = raw_event.get("payload", {})
        actor = raw_event.get("actor", {})
        
        severity_map = {
            "critical": "error",
            "high": "error",
            "medium": "warning",
            "low": "info"
        }
        
        return ActivityEvent(
            event_id=raw_event["event_id"],
            event_type="incident.events",
            timestamp=datetime.fromisoformat(raw_event["timestamp"].replace("Z", "+00:00")),
            actor_id=actor.get("id", "system"),
            actor_type=actor.get("type", "human"),
            service="incident-management",
            title=f"Incident: {payload.get('title', 'Unknown')}",
            description=payload.get("description", ""),
            status=payload.get("status", "created"),
            severity=severity_map.get(payload.get("severity", "medium"), "info"),
            tags=["incident", payload.get("status", ""), payload.get("severity", "")],
            metadata={
                "incident_id": payload.get("incident_id"),
                "severity": payload.get("severity")
            }
        )
    
    def parse_event(self, raw_event: Dict[str, Any]) -> Optional[ActivityEvent]:
        """Parse raw Kafka event into unified ActivityEvent"""
        event_type = raw_event.get("event_type", "")
        
        try:
            if event_type == "agent.audit":
                return self._parse_agent_audit_event(raw_event)
            elif event_type == "deploy.events":
                return self._parse_deploy_event(raw_event)
            elif event_type == "incident.events":
                return self._parse_incident_event(raw_event)
            # Add handlers for other event types
            else:
                logger.warning(f"Unknown event type: {event_type}")
                return None
        except Exception as e:
            logger.error(f"Error parsing event {event_type}: {e}")
            return None
    
    def add_activity(self, event: ActivityEvent):
        """Add parsed activity to feed"""
        self.activity_buffer.append(event)
        logger.info(f"Activity added: {event.title}")
    
    def get_recent_activity(self, limit: int = 50) -> List[ActivityEvent]:
        """Get recent activities (latest first)"""
        return sorted(
            self.activity_buffer,
            key=lambda e: e.timestamp,
            reverse=True
        )[:limit]
    
    def filter_by_actor(self, actor_id: str) -> List[ActivityEvent]:
        """Filter activities by actor"""
        return [e for e in self.activity_buffer if e.actor_id == actor_id]
    
    def filter_by_severity(self, severity: str) -> List[ActivityEvent]:
        """Filter activities by severity"""
        return [e for e in self.activity_buffer if e.severity == severity]
    
    def filter_by_service(self, service: str) -> List[ActivityEvent]:
        """Filter activities by service"""
        return [e for e in self.activity_buffer if e.service == service]

if __name__ == "__main__":
    consumer = ActivityFeedConsumer()
    
    # Example: Parse an agent audit event
    raw_event = {
        "event_id": "550e8400-e29b-41d4-a716-446655440000",
        "event_type": "agent.audit",
        "schema_version": "1.0",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "source": {"service": "agent-runtime", "instance": "primary"},
        "actor": {"type": "agent", "id": "agent/incident-responder/abc123", "reputation_score": 85},
        "payload": {
            "task_id": "task-001",
            "task_description": "Fix 502 authentication error",
            "status": "success",
            "duration_seconds": 240,
            "tokens_used": 8432
        }
    }
    
    activity = consumer.parse_event(raw_event)
    if activity:
        consumer.add_activity(activity)
        logger.info(f"\nParsed activity: {activity.title}")
        logger.info(f"Severity: {activity.severity}")
        logger.info(f"Tags: {', '.join(activity.tags)}")
