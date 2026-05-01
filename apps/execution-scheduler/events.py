"""
@file apps/execution-scheduler/events.py
@description Kafka event publisher for task scheduling, routing, and execution events
@governance GOV-002: Immutable, deterministic, audit-logged event publication
"""

import json
import logging
from datetime import datetime
from typing import Dict, Any, Optional
from kafka import KafkaProducer
from kafka.errors import KafkaError
import config as _svc_config



logger = logging.getLogger(__name__)


class SchedulerEventPublisher:
    """Publish scheduling and routing events to Kafka for audit trail and downstream processing."""

    def __init__(self, broker_url: str = "redpanda:9092"):
        self.broker_url = broker_url or _svc_config.KAFKA_BROKER
        self.producer: Optional[KafkaProducer] = None
        self._initialize_producer()

    def _initialize_producer(self) -> None:
        """Initialize Kafka producer with error handling."""
        try:
            self.producer = KafkaProducer(
                bootstrap_servers=self.broker_url,
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                acks='all',  # Wait for all replicas
                retries=3,
                max_in_flight_requests_per_connection=1,  # Preserve ordering
            )
            logger.info(f"Kafka producer initialized: {self.broker_url}")
        except Exception as e:
            logger.error(f"Failed to initialize Kafka producer: {e}")
            self.producer = None

    def _publish(self, topic: str, event: Dict[str, Any]) -> bool:
        """
        Publish event to Kafka topic with retry logic.
        
        Returns: True if published, False if failed
        """
        if not self.producer:
            logger.warning(f"Kafka producer not available, event dropped: {event}")
            return False

        try:
            event['timestamp'] = datetime.utcnow().isoformat() + 'Z'
            
            future = self.producer.send(topic, value=event)
            record_metadata = future.get(timeout=10)
            
            logger.debug(f"Event published to {topic}: partition={record_metadata.partition}, offset={record_metadata.offset}")
            return True

        except KafkaError as e:
            logger.error(f"Kafka error publishing to {topic}: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error publishing event: {e}")
            return False

    def publish_task_submitted(
        self,
        task_id: str,
        task_type: str,
        user_id: str,
        data_classification: str,
        request_metadata: Dict[str, Any],
    ) -> bool:
        """Publish when a task is submitted for routing."""
        event = {
            "event_type": "scheduler.task_submitted",
            "task_id": task_id,
            "task_type": task_type,
            "user_id": user_id,
            "data_classification": data_classification,
            "metadata": request_metadata,
        }
        return self._publish("scheduler.events", event)

    def publish_routing_decision(
        self,
        task_id: str,
        destination: str,
        routing_reason: str,
        cost_estimate: float,
        estimated_latency_ms: int,
    ) -> bool:
        """Publish when scheduler makes a routing decision."""
        event = {
            "event_type": "scheduler.routing_decision",
            "task_id": task_id,
            "destination": destination,
            "routing_reason": routing_reason,
            "cost_estimate": cost_estimate,
            "estimated_latency_ms": estimated_latency_ms,
        }
        return self._publish("scheduler.events", event)

    def publish_task_scheduled(
        self,
        task_id: str,
        destination: str,
        scheduled_at: str,
    ) -> bool:
        """Publish when task is successfully scheduled to destination."""
        event = {
            "event_type": "scheduler.task_scheduled",
            "task_id": task_id,
            "destination": destination,
            "scheduled_at": scheduled_at,
        }
        return self._publish("scheduler.events", event)

    def publish_routing_fallback(
        self,
        task_id: str,
        primary_destination: str,
        fallback_destination: str,
        reason: str,
    ) -> bool:
        """Publish when scheduler falls back to secondary destination."""
        event = {
            "event_type": "scheduler.routing_fallback",
            "task_id": task_id,
            "primary_destination": primary_destination,
            "fallback_destination": fallback_destination,
            "reason": reason,
        }
        return self._publish("scheduler.events", event)

    def publish_resource_constraint_hit(
        self,
        task_id: str,
        constraint_type: str,  # "cpu", "memory", "gpu", "disk"
        resource_name: str,
        current_usage: float,
        limit: float,
    ) -> bool:
        """Publish when a resource constraint limits routing options."""
        event = {
            "event_type": "scheduler.resource_constraint",
            "task_id": task_id,
            "constraint_type": constraint_type,
            "resource_name": resource_name,
            "current_usage": current_usage,
            "limit": limit,
            "usage_percentage": (current_usage / limit * 100) if limit > 0 else 0,
        }
        return self._publish("scheduler.events", event)

    def publish_cost_budget_alert(
        self,
        user_id: str,
        alert_level: str,  # "warning" (80%), "critical" (95%)
        monthly_budget: float,
        current_spend: float,
        percentage_used: float,
    ) -> bool:
        """Publish when user cost budget reaches threshold."""
        event = {
            "event_type": "scheduler.cost_budget_alert",
            "user_id": user_id,
            "alert_level": alert_level,
            "monthly_budget": monthly_budget,
            "current_spend": current_spend,
            "percentage_used": percentage_used,
        }
        return self._publish("scheduler.events", event)

    def publish_task_completed(
        self,
        task_id: str,
        destination: str,
        duration_seconds: float,
        cost_actual: float,
    ) -> bool:
        """Publish when task execution completes."""
        event = {
            "event_type": "scheduler.task_completed",
            "task_id": task_id,
            "destination": destination,
            "duration_seconds": duration_seconds,
            "cost_actual": cost_actual,
        }
        return self._publish("scheduler.events", event)

    def publish_task_failed(
        self,
        task_id: str,
        destination: str,
        error_message: str,
        retry_attempt: int,
    ) -> bool:
        """Publish when task execution fails."""
        event = {
            "event_type": "scheduler.task_failed",
            "task_id": task_id,
            "destination": destination,
            "error_message": error_message,
            "retry_attempt": retry_attempt,
        }
        return self._publish("scheduler.events", event)

    def publish_tier_based_priority(
        self,
        task_id: str,
        user_id: str,
        user_tier: str,
        priority_boost: int,
        reason: str,
    ) -> bool:
        """Publish when tier-based priority is applied to task."""
        event = {
            "event_type": "scheduler.tier_priority_applied",
            "task_id": task_id,
            "user_id": user_id,
            "user_tier": user_tier,
            "priority_boost": priority_boost,
            "reason": reason,
        }
        return self._publish("scheduler.events", event)

    def close(self) -> None:
        """Close Kafka producer connection."""
        if self.producer:
            self.producer.flush()
            self.producer.close()
            logger.info("Kafka producer closed")
