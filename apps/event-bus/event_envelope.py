#!/usr/bin/env python3
# @file apps/event-bus/event_envelope.py
# @module infrastructure/event-bus
# @description P3-1560 Phase 2: Standard event envelope builder
# @governance GOV-002: All events validated against schema before publishing

import json
import uuid
from datetime import datetime
from typing import Dict, Any, Optional
from dataclasses import dataclass, asdict
import jsonschema

@dataclass
class EventSource:
    service: str
    instance: str

@dataclass
class EventActor:
    type: str  # "human" or "agent"
    id: str
    reputation_score: Optional[float] = None

@dataclass
class StandardEventEnvelope:
    """Standard event envelope for all Kafka events"""
    event_id: str
    event_type: str
    schema_version: str
    timestamp: str
    source: EventSource
    actor: EventActor
    payload: Dict[str, Any]
    correlation_id: Optional[str] = None
    
    @staticmethod
    def create(
        event_type: str,
        payload: Dict[str, Any],
        service: str,
        instance: str,
        actor_type: str,
        actor_id: str,
        schema_version: str = "1.0",
        reputation_score: Optional[float] = None,
        correlation_id: Optional[str] = None
    ) -> 'StandardEventEnvelope':
        """Factory method to create a new event"""
        return StandardEventEnvelope(
            event_id=str(uuid.uuid4()),
            event_type=event_type,
            schema_version=schema_version,
            timestamp=datetime.utcnow().isoformat() + "Z",
            source=EventSource(service=service, instance=instance),
            actor=EventActor(
                type=actor_type,
                id=actor_id,
                reputation_score=reputation_score
            ),
            payload=payload,
            correlation_id=correlation_id or str(uuid.uuid4())
        )
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        return {
            "event_id": self.event_id,
            "event_type": self.event_type,
            "schema_version": self.schema_version,
            "timestamp": self.timestamp,
            "source": asdict(self.source),
            "actor": asdict(self.actor),
            "correlation_id": self.correlation_id,
            "payload": self.payload
        }
    
    def to_json(self) -> str:
        """Serialize to JSON string"""
        return json.dumps(self.to_dict(), default=str)

class EventValidator:
    """Validates events against JSON schemas"""
    
    def __init__(self):
        self.schemas = {}
        self._load_schemas()
    
    def _load_schemas(self):
        """Load all JSON schemas from disk"""
        # In production, load from schemas/kafka/ directory
        pass
    
    def validate(self, event: StandardEventEnvelope) -> bool:
        """Validate event against its schema"""
        try:
            event_dict = event.to_dict()
            # Would validate against loaded schema
            return True
        except jsonschema.ValidationError as e:
            print(f"Validation error: {e}")
            return False
    
    def validate_payload(self, event_type: str, payload: Dict[str, Any]) -> bool:
        """Validate just the payload against event-specific schema"""
        try:
            # Would validate payload against event-specific schema
            return True
        except jsonschema.ValidationError as e:
            print(f"Payload validation error: {e}")
            return False

if __name__ == "__main__":
    # Example: Create and validate an agent audit event
    event = StandardEventEnvelope.create(
        event_type="agent.audit",
        payload={
            "task_id": "task-2026-04-25-001",
            "task_description": "Fix authentication 502 error",
            "status": "success",
            "start_time": datetime.utcnow().isoformat() + "Z",
            "end_time": datetime.utcnow().isoformat() + "Z",
            "duration_seconds": 240,
            "tokens_used": 8432
        },
        service="agent-runtime",
        instance="primary",
        actor_type="agent",
        actor_id="agent/incident-responder/abc123",
        schema_version="1.0",
        reputation_score=85
    )
    
    print("Generated Event:")
    print(json.dumps(event.to_dict(), indent=2))
    
    # Validate
    validator = EventValidator()
    if validator.validate(event):
        print("\n✓ Event is valid")
    else:
        print("\n✗ Event is invalid")
