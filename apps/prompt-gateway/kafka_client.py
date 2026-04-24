import json
import logging
import os
from typing import Dict, Any, Optional
from datetime import datetime

# @file        apps/prompt-gateway/kafka_client.py
# @module      ai/security
# @description Kafka producer for Prompt Gateway interactions

try:
    from confluent_kafka import Producer
    HAS_KAFKA = True
except ImportError:
    HAS_KAFKA = False

logger = logging.getLogger(__name__)

class KafkaProducer:
    def __init__(self):
        self.enabled = os.environ.get("ENABLE_KAFKA", "false").lower() == "true"
        self.bootstrap_servers = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
        self.topic = os.environ.get("KAFKA_TOPIC_AI_INTERACTIONS", "ai.interactions")
        
        self.producer = None
        if self.enabled and HAS_KAFKA:
            try:
                self.producer = Producer({
                    'bootstrap.servers': self.bootstrap_servers,
                    'client.id': 'prompt-gateway',
                    'acks': 'all'
                })
                logger.info(f"Kafka producer initialized for {self.bootstrap_servers}")
            except Exception as e:
                logger.error(f"Failed to initialize Kafka producer: {e}")
                self.enabled = False

    def publish_interaction(self, event: Dict[str, Any]):
        """Publish an AI interaction event to Kafka"""
        if not self.enabled or not self.producer:
            # Fallback to local logging if Kafka is disabled/failed
            logger.info(f"KAFKA_MOCK_PUBLISH: {json.dumps(event)}")
            return

        try:
            self.producer.produce(
                self.topic,
                key=event.get("user_id", "anonymous"),
                value=json.dumps(event).encode('utf-8'),
                callback=self._delivery_report
            )
            # Poll for delivery reports
            self.producer.poll(0)
        except Exception as e:
            logger.error(f"Failed to produce Kafka message: {e}")

    def _delivery_report(self, err, msg):
        """Called once for each message produced to indicate delivery result"""
        if err is not None:
            logger.error(f"Message delivery failed: {err}")
        else:
            logger.debug(f"Message delivered to {msg.topic()} [{msg.partition()}]")

    def flush(self, timeout=10):
        if self.producer:
            self.producer.flush(timeout)
