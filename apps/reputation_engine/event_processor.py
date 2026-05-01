#!/usr/bin/env python3
# @file apps/reputation-engine/event_processor.py
# @module reputation-engine/processing
# @description Process Kafka events for reputation scoring
# @governance GOV-004 - Event-driven reputation calculation

from typing import Dict, Any, Optional, List
from log import get_logger
import json
from datetime import datetime, timezone
from threading import Thread, Event

from sqlalchemy.orm import Session
from confluent_kafka import Consumer, KafkaError, KafkaException

from models import ActorType
from score_calculator import ScoreCalculator
from signal_extractor import SignalExtractor

logger = get_logger(__name__)


class ReputationEventProcessor:
    """Process Kafka events and update reputation scores."""
    
    # Topics to consume
    SIGNAL_TOPICS = [
        "agent.audit",
        "agent.lifecycle",
        "deploy.events",
        "code.review",
        "incident.events",
        "policy.violations",
    ]
    
    def __init__(
        self,
        db_session: Session,
        bootstrap_servers: str = "localhost:9092",
        group_id: str = "reputation-engine",
        auto_offset_reset: str = "latest",
    ):
        """Initialize event processor.
        
        Args:
            db_session: SQLAlchemy session
            bootstrap_servers: Kafka bootstrap servers
            group_id: Consumer group ID
            auto_offset_reset: Whether to start from latest or earliest
        """
        self.db = db_session
        self.bootstrap_servers = bootstrap_servers
        self.group_id = group_id
        self.auto_offset_reset = auto_offset_reset
        
        self.calculator = ScoreCalculator(db_session)
        self.consumer: Optional[Consumer] = None
        self.running = False
        self.stop_event = Event()
        
        logger.info(f"Initialized ReputationEventProcessor with bootstrap_servers={bootstrap_servers}")
    
    def connect(self):
        """Connect to Kafka."""
        conf = {
            "bootstrap.servers": self.bootstrap_servers,
            "group.id": self.group_id,
            "auto.offset.reset": self.auto_offset_reset,
            "enable.auto.commit": False,  # Manual commit for reliability
            "session.timeout.ms": 30000,
            "heartbeat.interval.ms": 10000,
        }
        
        self.consumer = Consumer(conf)
        logger.info(f"Connected to Kafka: {self.bootstrap_servers}")
    
    def subscribe(self):
        """Subscribe to signal topics."""
        if not self.consumer:
            raise RuntimeError("Consumer not connected")
        
        self.consumer.subscribe(self.SIGNAL_TOPICS)
        logger.info(f"Subscribed to topics: {', '.join(self.SIGNAL_TOPICS)}")
    
    def start(self):
        """Start event processing loop."""
        if self.running:
            logger.warning("Event processor already running")
            return
        
        self.connect()
        self.subscribe()
        self.running = True
        self.stop_event.clear()
        
        thread = Thread(target=self._process_loop, daemon=True)
        thread.start()
        logger.info("Started reputation event processor")
    
    def stop(self):
        """Stop event processing loop."""
        if not self.running:
            return
        
        self.stop_event.set()
        self.running = False
        
        if self.consumer:
            self.consumer.close()
        
        logger.info("Stopped reputation event processor")
    
    def _process_loop(self):
        """Main event processing loop."""
        try:
            while self.running and not self.stop_event.is_set():
                msg = self.consumer.poll(timeout=1.0)
                
                if msg is None:
                    continue
                
                if msg.error():
                    if msg.error().code() == KafkaError._PARTITION_EOF:
                        logger.debug("Reached end of partition")
                        continue
                    else:
                        raise KafkaException(msg.error())
                
                # Process message
                try:
                    self._process_message(msg)
                    self.consumer.commit(asynchronous=False)
                except Exception as e:
                    logger.error(f"Error processing message: {e}", exc_info=True)
        
        except Exception as e:
            logger.error(f"Event processing loop error: {e}", exc_info=True)
        finally:
            if self.consumer:
                self.consumer.close()
    
    def _process_message(self, msg):
        """Process a single Kafka message.
        
        Args:
            msg: Confluent Kafka message
        """
        try:
            # Parse event
            event_data = json.loads(msg.value().decode("utf-8"))
            topic = msg.topic()
            partition = msg.partition()
            offset = msg.offset()
            
            # Add Kafka metadata
            event_data["_kafka_topic"] = topic
            event_data["_kafka_partition"] = partition
            event_data["_kafka_offset"] = offset
            
            logger.debug(f"Processing event from {topic}:{partition}:{offset}")
            
            # Extract signals
            signals = SignalExtractor.extract_from_event(event_data)
            
            if not signals:
                logger.debug(f"No signals extracted from event: {event_data.get('event_type')}")
                return

            actor_type = self._infer_actor_type(topic)
            
            # Process each signal
            for signal_data in signals:
                actor_id = signal_data.get("actor_id")
                signal_type = signal_data.get("signal_type")
                signal_value = signal_data.get("signal_value", 1.0)
                event_id = signal_data.get("event_id")

                if not actor_id:
                    logger.warning(f"Signal missing actor_id: {signal_data}")
                    continue
                
                self.calculator.get_or_create_score(actor_id, actor_type)
                
                logger.info(f"Recording signal: actor={actor_id}, type={signal_type.value}, value={signal_value}")
                
                # Record signal
                self.calculator.add_signal(
                    actor_id=actor_id,
                    signal_type=signal_type,
                    signal_value=signal_value,
                    event_id=event_id,
                )
                
                # Recalculate score (may batch this for efficiency)
                new_score, new_tier, signals_used = self.calculator.recalculate_score(actor_id)
                
                logger.info(
                    f"Updated reputation: actor={actor_id}, score={new_score}, tier={new_tier.value}"
                )
                
                # Record audit
                self.calculator.record_audit(
                    action="score_updated",
                    actor_id=actor_id,
                    event_id=event_id,
                    details={
                        "signal_type": signal_type.value,
                        "signal_value": signal_value,
                        "new_score": new_score,
                        "new_tier": new_tier.value,
                        "contributing_signals": signals_used,
                    },
                    status="success",
                )
        
        except json.JSONDecodeError as e:
            logger.error(f"Failed to decode message: {e}")
        except Exception as e:
            logger.error(f"Error processing message: {e}", exc_info=True)

    def _infer_actor_type(self, topic: str) -> ActorType:
        """Infer the actor type from the Kafka topic."""
        if topic.startswith("agent."):
            return ActorType.AGENT

        return ActorType.ENGINEER
    
    def get_status(self) -> Dict[str, Any]:
        """Get processor status.
        
        Returns:
            Status dictionary
        """
        return {
            "running": self.running,
            "connected": self.consumer is not None,
            "topics": self.SIGNAL_TOPICS,
            "group_id": self.group_id,
            "bootstrap_servers": self.bootstrap_servers,
        }
