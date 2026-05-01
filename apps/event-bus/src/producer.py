#!/usr/bin/env python3
# @file apps/event-bus/src/producer.py
# @module event-bus/producers
# @description Base event producer for publishing to Kafka topics
# @governance GOV-003 - Event schema enforcement and audit trails

import json
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, Optional
from dataclasses import dataclass, asdict
from abc import ABC, abstractmethod
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from log import get_logger

try:
    from confluent_kafka import Producer
except ImportError:
    Producer = None

logger = get_logger(__name__)


@dataclass
class EventEnvelope:
    """Standard event envelope for all Kafka events."""
    
    event_id: str
    event_type: str
    schema_version: str
    timestamp: str
    source: Dict[str, str]
    actor: Dict[str, Any]
    payload: Dict[str, Any]
    correlation_id: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary, excluding None values."""
        data = asdict(self)
        return {k: v for k, v in data.items() if v is not None}
    
    def to_json(self) -> str:
        """Convert to JSON string."""
        return json.dumps(self.to_dict(), default=str)


class EventProducer(ABC):
    """Abstract base class for event producers."""
    
    def __init__(
        self,
        broker: str = "localhost:9092",
        service_name: str = "unknown-service",
        service_version: str = "1.0.0"
    ):
        """Initialize event producer.
        
        Args:
            broker: Kafka broker address
            service_name: Name of the service publishing events
            service_version: Version of the service
        """
        self.broker = broker
        self.service_name = service_name
        self.service_version = service_version
        self.producer = None
        self._init_producer()
    
    def _init_producer(self):
        """Initialize Kafka producer."""
        if Producer is None:
            raise ImportError("confluent-kafka not installed. Install with: pip install confluent-kafka")
        
        config = {
            'bootstrap.servers': self.broker,
            'client.id': f'{self.service_name}-producer',
            'acks': 'all',  # Wait for all replicas to ack
            'compression.type': 'snappy',
            'linger.ms': 100,  # Batch messages for 100ms
            'batch.size': 16384,
        }
        
        self.producer = Producer(config)
        logger.info(f"Initialized event producer for service={self.service_name} broker={self.broker}")
    
    def create_envelope(
        self,
        event_type: str,
        payload: Dict[str, Any],
        actor_id: str,
        actor_type: str = "system",
        reputation_score: int = 0,
        correlation_id: Optional[str] = None,
        schema_version: str = "1.0",
        metadata: Optional[Dict[str, Any]] = None
    ) -> EventEnvelope:
        """Create a standard event envelope.
        
        Args:
            event_type: Event type (e.g., agent.audit, deploy.completed)
            payload: Event-specific payload
            actor_id: ID of the actor (agent, engineer, or system)
            actor_type: Type of actor (agent, human, system)
            reputation_score: Current reputation score of the actor
            correlation_id: Optional correlation ID linking related events
            schema_version: Schema version
            metadata: Optional additional metadata
        
        Returns:
            EventEnvelope instance
        """
        return EventEnvelope(
            event_id=str(uuid.uuid4()),
            event_type=event_type,
            schema_version=schema_version,
            timestamp=datetime.now(timezone.utc).isoformat(),
            source={
                "service": self.service_name,
                "instance": self._get_instance_id(),
                "version": self.service_version,
            },
            actor={
                "type": actor_type,
                "id": actor_id,
                "reputation_score": reputation_score,
            },
            payload=payload,
            correlation_id=correlation_id,
            metadata=metadata or {},
        )
    
    def publish(
        self,
        topic: str,
        envelope: EventEnvelope,
        key: Optional[str] = None
    ) -> bool:
        """Publish an event to Kafka.
        
        Args:
            topic: Kafka topic name
            envelope: EventEnvelope to publish
            key: Optional partition key
        
        Returns:
            True if successful, False otherwise
        """
        if self.producer is None:
            logger.error("Producer not initialized")
            return False
        
        try:
            # Use correlation_id or event_id as key for partitioning
            partition_key = key or envelope.correlation_id or envelope.event_id
            
            self.producer.produce(
                topic=topic,
                key=partition_key.encode('utf-8'),
                value=envelope.to_json().encode('utf-8'),
                callback=self._delivery_report
            )
            
            logger.debug(f"Published event {envelope.event_id} to topic {topic}")
            return True
        
        except Exception as e:
            logger.error(f"Failed to publish event to {topic}: {e}")
            return False
    
    def flush(self, timeout: float = 30):
        """Flush pending messages to broker.
        
        Args:
            timeout: Timeout in seconds
        """
        if self.producer:
            remaining = self.producer.flush(timeout)
            if remaining > 0:
                logger.warning(f"Failed to deliver {remaining} messages within timeout")
    
    def close(self):
        """Close the producer."""
        if self.producer:
            self.flush()
            self.producer = None
            logger.info("Event producer closed")
    
    def _delivery_report(self, err, msg):
        """Kafka delivery report callback."""
        if err is not None:
            logger.error(f'Message delivery failed: {err}')
        else:
            logger.debug(f'Message delivered to {msg.topic()} [{msg.partition()}]')
    
    @staticmethod
    def _get_instance_id() -> str:
        """Get instance ID (hostname or pod name)."""
        import socket
        try:
            return socket.gethostname()
        except OSError:
            return "unknown-instance"
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()


class DeployEventProducer(EventProducer):
    """Producer for deployment events."""
    
    def publish_deploy_started(
        self,
        deploy_id: str,
        environment: str,
        actor_id: str,
        services: list = None,
        correlation_id: Optional[str] = None
    ) -> bool:
        """Publish a deployment start event."""
        envelope = self.create_envelope(
            event_type="deploy.events",
            payload={
                "action": "started",
                "deploy_id": deploy_id,
                "environment": environment,
                "services": services or [],
            },
            actor_id=actor_id,
            correlation_id=correlation_id,
        )
        return self.publish("deploy.events", envelope, key=deploy_id)
    
    def publish_deploy_completed(
        self,
        deploy_id: str,
        environment: str,
        success: bool,
        actor_id: str,
        duration_ms: int = 0,
        error: Optional[str] = None,
        correlation_id: Optional[str] = None
    ) -> bool:
        """Publish a deployment completion event."""
        envelope = self.create_envelope(
            event_type="deploy.events",
            payload={
                "action": "completed",
                "deploy_id": deploy_id,
                "environment": environment,
                "success": success,
                "duration_ms": duration_ms,
                "error": error,
            },
            actor_id=actor_id,
            correlation_id=correlation_id,
        )
        return self.publish("deploy.events", envelope, key=deploy_id)


class AgentEventProducer(EventProducer):
    """Producer for agent lifecycle and audit events."""
    
    def publish_agent_spawned(
        self,
        agent_id: str,
        agent_type: str,
        parent_task_id: str,
        actor_id: str,
        correlation_id: Optional[str] = None
    ) -> bool:
        """Publish an agent spawn event."""
        envelope = self.create_envelope(
            event_type="agent.lifecycle",
            payload={
                "action": "spawn",
                "agent_id": agent_id,
                "agent_type": agent_type,
                "parent_task_id": parent_task_id,
                "start_time": datetime.now(timezone.utc).isoformat(),
            },
            actor_id=actor_id,
            correlation_id=correlation_id,
        )
        return self.publish("agent.lifecycle", envelope, key=agent_id)
    
    def publish_agent_completed(
        self,
        agent_id: str,
        success: bool,
        duration_ms: int,
        tokens_used: int = 0,
        output: Optional[Dict[str, Any]] = None,
        error: Optional[str] = None,
        actor_id: str = "system",
        correlation_id: Optional[str] = None
    ) -> bool:
        """Publish an agent completion event."""
        envelope = self.create_envelope(
            event_type="agent.lifecycle",
            payload={
                "action": "complete" if success else "fail",
                "agent_id": agent_id,
                "success": success,
                "duration_ms": duration_ms,
                "tokens_used": tokens_used,
                "output": output,
                "error": error,
            },
            actor_id=actor_id,
            correlation_id=correlation_id,
        )
        return self.publish("agent.lifecycle", envelope, key=agent_id)
    
    def publish_agent_audit(
        self,
        agent_id: str,
        action: str,
        resource: str,
        actor_id: str,
        success: bool = True,
        details: Optional[Dict[str, Any]] = None,
        correlation_id: Optional[str] = None
    ) -> bool:
        """Publish an agent audit event."""
        envelope = self.create_envelope(
            event_type="agent.audit",
            payload={
                "agent_id": agent_id,
                "action": action,
                "resource": resource,
                "success": success,
                "details": details or {},
            },
            actor_id=actor_id,
            correlation_id=correlation_id,
        )
        return self.publish("agent.audit", envelope, key=agent_id)


class AIEventProducer(EventProducer):
    """Producer for AI interaction events."""
    
    def publish_ai_interaction(
        self,
        model_name: str,
        provider: str,
        prompt_hash: str,
        prompt_tokens: int,
        response_tokens: int,
        latency_ms: int,
        actor_id: str,
        success: bool = True,
        error: Optional[str] = None,
        cost_credits: float = 0,
        temperature: float = 0.7,
        correlation_id: Optional[str] = None
    ) -> bool:
        """Publish an AI interaction event."""
        envelope = self.create_envelope(
            event_type="ai.interactions",
            payload={
                "model_name": model_name,
                "provider": provider,
                "prompt_hash": prompt_hash,
                "prompt_tokens": prompt_tokens,
                "response_tokens": response_tokens,
                "total_tokens": prompt_tokens + response_tokens,
                "latency_ms": latency_ms,
                "temperature": temperature,
                "success": success,
                "error": error,
                "cost_credits": cost_credits,
            },
            actor_id=actor_id,
            correlation_id=correlation_id,
        )
        return self.publish("ai.interactions", envelope, key=model_name)
