#!/usr/bin/env python3
# @file apps/event-bus/src/consumer.py
# @module event-bus/consumers
# @description Base event consumer for subscribing to Kafka topics
# @governance GOV-003 - Event schema enforcement and audit trails

import json
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from log import get_logger
from typing import Any, Callable, Dict, List, Optional
from datetime import datetime, timezone
from abc import ABC, abstractmethod

try:
    from confluent_kafka import Consumer, KafkaError
except ImportError:
    Consumer = None
    KafkaError = None

logger = get_logger(__name__)


class EventConsumer(ABC):
    """Abstract base class for event consumers."""
    
    def __init__(
        self,
        broker: str = "localhost:9092",
        group_id: str = "unknown-group",
        topics: List[str] = None,
        auto_offset_reset: str = "earliest",
        enable_auto_commit: bool = True
    ):
        """Initialize event consumer.
        
        Args:
            broker: Kafka broker address
            group_id: Consumer group ID
            topics: Topics to subscribe to
            auto_offset_reset: What to do when there's no initial offset
            enable_auto_commit: Whether to auto-commit offsets
        """
        self.broker = broker
        self.group_id = group_id
        self.topics = topics or []
        self.consumer = None
        self._init_consumer(auto_offset_reset, enable_auto_commit)
    
    def _init_consumer(self, auto_offset_reset: str, enable_auto_commit: bool):
        """Initialize Kafka consumer."""
        if Consumer is None:
            raise ImportError("confluent-kafka not installed. Install with: pip install confluent-kafka")
        
        config = {
            'bootstrap.servers': self.broker,
            'group.id': self.group_id,
            'auto.offset.reset': auto_offset_reset,
            'enable.auto.commit': enable_auto_commit,
            'session.timeout.ms': 30000,
            'default.topic.config': {
                'auto.offset.reset': auto_offset_reset
            }
        }
        
        self.consumer = Consumer(config)
        logger.info(f"Initialized event consumer group={self.group_id} broker={self.broker}")
        
        if self.topics:
            self.subscribe(self.topics)
    
    def subscribe(self, topics: List[str]):
        """Subscribe to topics.
        
        Args:
            topics: List of topic names
        """
        if self.consumer is None:
            logger.error("Consumer not initialized")
            return
        
        try:
            self.consumer.subscribe(topics)
            logger.info(f"Subscribed to topics: {topics}")
        except Exception as e:
            logger.error(f"Failed to subscribe to topics: {e}")
    
    def poll(self, timeout_ms: int = 1000) -> Optional[Dict[str, Any]]:
        """Poll for messages.
        
        Args:
            timeout_ms: Poll timeout in milliseconds
        
        Returns:
            Parsed event dictionary or None
        """
        if self.consumer is None:
            return None
        
        try:
            msg = self.consumer.poll(timeout=timeout_ms / 1000.0)
            
            if msg is None:
                return None
            
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    logger.debug(f"Reached end of partition {msg.partition()}")
                else:
                    logger.error(f"Consumer error: {msg.error()}")
                return None
            
            # Parse the event
            try:
                event = json.loads(msg.value().decode('utf-8'))
                event['_kafka_topic'] = msg.topic()
                event['_kafka_partition'] = msg.partition()
                event['_kafka_offset'] = msg.offset()
                return event
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse message: {e}")
                return None
        
        except Exception as e:
            logger.error(f"Error polling consumer: {e}")
            return None
    
    def consume(self, timeout_ms: int = 1000, max_messages: Optional[int] = None) -> List[Dict[str, Any]]:
        """Consume multiple messages.
        
        Args:
            timeout_ms: Poll timeout per message
            max_messages: Maximum number of messages to consume
        
        Returns:
            List of parsed events
        """
        messages = []
        count = 0
        
        while True:
            if max_messages and count >= max_messages:
                break
            
            msg = self.poll(timeout_ms)
            if msg is None:
                break
            
            messages.append(msg)
            count += 1
        
        return messages
    
    def seek_beginning(self):
        """Seek to the beginning of all assigned partitions."""
        if self.consumer:
            self.consumer.seek_beginning()
            logger.info("Seeked to beginning of all partitions")
    
    def commit(self, offsets: Optional[Dict[str, Any]] = None, async_: bool = False):
        """Commit consumer offset.
        
        Args:
            offsets: Optional offsets to commit
            async_: Whether to commit asynchronously
        """
        if self.consumer:
            try:
                self.consumer.commit(offsets=offsets, asynchronous=async_)
            except Exception as e:
                logger.error(f"Failed to commit offsets: {e}")
    
    def close(self):
        """Close the consumer."""
        if self.consumer:
            self.consumer.close()
            self.consumer = None
            logger.info("Event consumer closed")
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()


class ActivityFeedConsumer(EventConsumer):
    """Consumer for activity feed aggregation."""
    
    def __init__(self, broker: str = "localhost:9092", **kwargs):
        """Initialize activity feed consumer."""
        super().__init__(
            broker=broker,
            group_id="activity-feed-service",
            topics=[
                "agent.audit",
                "agent.lifecycle",
                "deploy.events",
                "code.review",
                "incident.events",
                "ai.interactions",
                "reputation.update",
                "policy.violations"
            ],
            **kwargs
        )
    
    def get_next_activity(self, timeout_ms: int = 1000) -> Optional[Dict[str, Any]]:
        """Get next activity event."""
        return self.poll(timeout_ms)


class ReputationEngineConsumer(EventConsumer):
    """Consumer for reputation engine signal extraction."""
    
    def __init__(self, broker: str = "localhost:9092", **kwargs):
        """Initialize reputation engine consumer."""
        super().__init__(
            broker=broker,
            group_id="reputation-engine",
            topics=[
                "agent.audit",
                "agent.lifecycle",
                "deploy.events",
                "code.review",
                "policy.violations",
            ],
            enable_auto_commit=False,  # Manual commit for reliability
            **kwargs
        )
    
    def process_signals(self, handler: Callable[[Dict[str, Any]], bool]) -> int:
        """Process signals with a handler function.
        
        Args:
            handler: Async function to handle each event. Should return True on success.
        
        Returns:
            Number of events processed
        """
        count = 0
        try:
            while True:
                event = self.poll(timeout_ms=1000)
                if event is None:
                    break
                
                try:
                    if handler(event):
                        self.commit(async_=False)
                        count += 1
                    else:
                        logger.warning(f"Handler failed for event {event.get('event_id')}")
                
                except Exception as e:
                    logger.error(f"Error processing event: {e}")
        
        except KeyboardInterrupt:
            logger.info("Interrupted by user")
        
        finally:
            self.commit()
        
        return count


class AuditLogConsumer(EventConsumer):
    """Consumer for centralized audit logging."""
    
    def __init__(self, broker: str = "localhost:9092", **kwargs):
        """Initialize audit log consumer."""
        super().__init__(
            broker=broker,
            group_id="audit-logger",
            topics=[
                "agent.audit",
                "policy.violations",
                "deploy.events",
                "code.review",
                "audit.log"
            ],
            enable_auto_commit=False,  # Manual commit for reliability
            **kwargs
        )
    
    def write_audit_log(self, event: Dict[str, Any], storage_handler: Callable) -> bool:
        """Write event to audit log with custom storage handler.
        
        Args:
            event: Event to audit
            storage_handler: Function that persists the event (e.g., to PostgreSQL)
        
        Returns:
            True if successful
        """
        try:
            result = storage_handler(event)
            if result:
                self.commit(async_=False)
            return result
        except Exception as e:
            logger.error(f"Failed to write audit log: {e}")
            return False


class PaperclipConsumer(EventConsumer):
    """Consumer for Paperclip (human control plane) integration."""
    
    def __init__(self, broker: str = "localhost:9092", **kwargs):
        """Initialize Paperclip consumer."""
        super().__init__(
            broker=broker,
            group_id="paperclip-control-plane",
            topics=[
                "agent.awaiting_approval",
                "agent.killswitch"
            ],
            enable_auto_commit=False,  # Manual commit for reliability
            **kwargs
        )
    
    def get_pending_approvals(self, timeout_ms: int = 1000, max_count: int = 10) -> List[Dict[str, Any]]:
        """Get pending approvals from approval queue.
        
        Args:
            timeout_ms: Poll timeout
            max_count: Maximum approvals to return
        
        Returns:
            List of pending approval events
        """
        return self.consume(timeout_ms, max_count)
    
    def get_killswitch_events(self) -> Optional[Dict[str, Any]]:
        """Get emergency stop events (highest priority).
        
        Returns:
            Next killswitch event or None
        """
        event = self.poll(timeout_ms=100)
        if event and event.get('_kafka_topic') == 'agent.killswitch':
            return event
        return None
