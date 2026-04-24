#!/usr/bin/env python3
# @file        scripts/kafka-producer/producer.py
# @description Kafka event producer utility for sending events to Redpanda event bus
# @module      kafka-producer

import asyncio
import json
import logging
import os
import sys
from datetime import datetime
from typing import Dict, Any, Optional
import uuid

from aiokafka import AIOKafkaProducer
import asyncpg

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class KafkaEventProducer:
    """Kafka event producer for Redpanda event bus"""

    def __init__(self, brokers: str = None):
        self.brokers = brokers or os.getenv("KAFKA_BROKERS", "redpanda:9092")
        self.producer: Optional[AIOKafkaProducer] = None

    async def __aenter__(self):
        await self.start()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.stop()

    async def start(self):
        """Start the Kafka producer"""
        self.producer = AIOKafkaProducer(
            bootstrap_servers=self.brokers,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            key_serializer=lambda k: k.encode('utf-8') if k else None,
            acks='all',
            retries=3,
            max_in_flight_requests_per_connection=1
        )
        await self.producer.start()
        logger.info(f"Kafka producer started with brokers: {self.brokers}")

    async def stop(self):
        """Stop the Kafka producer"""
        if self.producer:
            await self.producer.stop()
            logger.info("Kafka producer stopped")

    async def send_event(self, topic: str, event_data: Dict[str, Any], key: Optional[str] = None):
        """Send an event to a Kafka topic"""
        try:
            # Ensure event has required fields
            if 'event_id' not in event_data:
                event_data['event_id'] = str(uuid.uuid4())

            if 'timestamp' not in event_data:
                event_data['timestamp'] = int(datetime.now().timestamp() * 1000)

            await self.producer.send_and_wait(topic, event_data, key=key)
            logger.info(f"Event sent to topic '{topic}': {event_data['event_id']}")

        except Exception as e:
            logger.error(f"Failed to send event to topic '{topic}': {e}")
            raise

# Event creation helpers
def create_agent_audit_event(
    agent_id: str,
    agent_type: str,
    action: str,
    context: Dict[str, Any],
    parameters: Dict[str, Any],
    outcome: str,
    duration_ms: Optional[int] = None,
    error_message: Optional[str] = None,
    metadata: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """Create an agent audit event"""
    return {
        "event_id": str(uuid.uuid4()),
        "timestamp": int(datetime.now().timestamp() * 1000),
        "agent_id": agent_id,
        "agent_type": agent_type,
        "action": action,
        "context": context,
        "parameters": parameters,
        "outcome": outcome,
        "duration_ms": duration_ms,
        "error_message": error_message,
        "metadata": metadata or {}
    }

def create_deployment_event(
    deployment_id: str,
    action: str,
    environment: str,
    target: str,
    initiator: str,
    status: str,
    deployment_type: str = "docker_compose",
    duration_ms: Optional[int] = None,
    resources_changed: Optional[int] = None,
    error_message: Optional[str] = None,
    changes: Optional[list] = None,
    metadata: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """Create a deployment event"""
    return {
        "event_id": str(uuid.uuid4()),
        "timestamp": int(datetime.now().timestamp() * 1000),
        "deployment_id": deployment_id,
        "type": deployment_type,
        "action": action,
        "environment": environment,
        "target": target,
        "initiator": initiator,
        "status": status,
        "duration_ms": duration_ms,
        "resources_changed": resources_changed,
        "error_message": error_message,
        "changes": changes or [],
        "metadata": metadata or {}
    }

def create_ai_interaction_event(
    interaction_id: str,
    model: str,
    provider: str,
    user_id: str,
    request_type: str,
    prompt_length: int,
    response_length: Optional[int],
    tokens_used: Dict[str, int],
    duration_ms: int,
    status: str,
    context: Optional[Dict[str, Any]] = None,
    error_message: Optional[str] = None,
    metadata: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """Create an AI interaction event"""
    return {
        "event_id": str(uuid.uuid4()),
        "timestamp": int(datetime.now().timestamp() * 1000),
        "interaction_id": interaction_id,
        "model": model,
        "provider": provider,
        "user_id": user_id,
        "request_type": request_type,
        "prompt_length": prompt_length,
        "response_length": response_length,
        "tokens_used": tokens_used,
        "duration_ms": duration_ms,
        "status": status,
        "error_message": error_message,
        "context": context or {},
        "metadata": metadata or {}
    }

async def main():
    """CLI interface for sending test events"""
    if len(sys.argv) < 3:
        print("Usage: python producer.py <topic> <event_type> [event_data.json]")
        print("\nExample:")
        print("  python producer.py agent.audit agent_action")
        print("  python producer.py deploy.events deployment '{\"deployment_id\": \"test-123\", \"action\": \"apply\", \"environment\": \"development\", \"target\": \"web-service\", \"initiator\": \"test-user\", \"status\": \"completed\"}'")
        sys.exit(1)

    topic = sys.argv[1]
    event_type = sys.argv[2]
    event_data_json = sys.argv[3] if len(sys.argv) > 3 else "{}"

    try:
        event_data = json.loads(event_data_json)
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}")
        sys.exit(1)

    # Create appropriate event based on type
    if event_type == "agent_action":
        event = create_agent_audit_event(
            agent_id=event_data.get("agent_id", "test-agent"),
            agent_type=event_data.get("agent_type", "copilot"),
            action=event_data.get("action", "test_action"),
            context=event_data.get("context", {}),
            parameters=event_data.get("parameters", {}),
            outcome=event_data.get("outcome", "success")
        )
    elif event_type == "deployment":
        event = create_deployment_event(
            deployment_id=event_data.get("deployment_id", str(uuid.uuid4())),
            action=event_data.get("action", "apply"),
            environment=event_data.get("environment", "development"),
            target=event_data.get("target", "test-service"),
            initiator=event_data.get("initiator", "test-user"),
            status=event_data.get("status", "completed")
        )
    elif event_type == "ai_interaction":
        event = create_ai_interaction_event(
            interaction_id=str(uuid.uuid4()),
            model=event_data.get("model", "gpt-4"),
            provider=event_data.get("provider", "openai"),
            user_id=event_data.get("user_id", "test-user"),
            request_type=event_data.get("request_type", "completion"),
            prompt_length=event_data.get("prompt_length", 100),
            response_length=event_data.get("response_length", 200),
            tokens_used=event_data.get("tokens_used", {"total_tokens": 300}),
            duration_ms=event_data.get("duration_ms", 1500),
            status=event_data.get("status", "success")
        )
    else:
        # Generic event
        event = {
            "event_id": str(uuid.uuid4()),
            "timestamp": int(datetime.now().timestamp() * 1000),
            **event_data
        }

    async with KafkaEventProducer() as producer:
        await producer.send_event(topic, event)
        print(f"Event sent successfully: {event['event_id']}")

if __name__ == "__main__":
    asyncio.run(main())