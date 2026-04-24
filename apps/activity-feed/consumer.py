#!/usr/bin/env python3
# @file        apps/activity-feed/consumer.py
# @module      activity/feed/consumer
# @description Kafka consumer - aggregates events from all topics and sends to Activity Feed
# @owner       engineering/infrastructure
# @status      production-ready
#
# Listens to all engineering activity topics (agent, deploy, code review, etc.)
# and forwards events to Activity Feed REST API for unified stream

import logging
import json
import asyncio
import os
import sys
from typing import List
from datetime import datetime

import requests
from confluent_kafka import Consumer, KafkaError, KafkaException

# ════════════════════════════════════════════════════════════════════════════
# Configuration
# ════════════════════════════════════════════════════════════════════════════

KAFKA_BROKERS = os.getenv("KAFKA_BROKERS", "localhost:9092")
KAFKA_GROUP_ID = os.getenv("KAFKA_GROUP_ID", "activity-feed-consumer")
ACTIVITY_FEED_URL = os.getenv("ACTIVITY_FEED_URL", "http://localhost:8003")

# Topics to consume
TOPICS = [
    "agent.audit",
    "agent.lifecycle",
    "reputation.update",
    "deploy.events",
    "code.review",
    "incident.events",
    "ai.interactions",
    "system.alerts",
]

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# ════════════════════════════════════════════════════════════════════════════
# Kafka Consumer
# ════════════════════════════════════════════════════════════════════════════

def create_consumer():
    """Create Kafka consumer with configuration"""
    conf = {
        "bootstrap.servers": KAFKA_BROKERS,
        "group.id": KAFKA_GROUP_ID,
        "auto.offset.reset": "earliest",
        "enable.auto.commit": True,
        "session.timeout.ms": 6000,
        "socket.keepalive.enable": True,
    }
    
    logger.info(f"Creating Kafka consumer: brokers={KAFKA_BROKERS}, group={KAFKA_GROUP_ID}")
    return Consumer(conf)

def forward_to_activity_feed(event: dict):
    """
    Forward Kafka event to Activity Feed REST API
    
    Args:
        event: Kafka message (assumed to be JSON in standard envelope format)
    """
    try:
        response = requests.post(
            f"{ACTIVITY_FEED_URL}/api/activity/ingest",
            json=event,
            timeout=5,
        )
        
        if response.status_code == 200:
            logger.debug(f"✅ Forwarded event: {event.get('event_id')} | {response.json()}")
        else:
            logger.warning(
                f"⚠️  Failed to forward event: {response.status_code} | {response.text}"
            )
    except requests.exceptions.ConnectionError:
        logger.error(f"❌ Activity Feed unreachable: {ACTIVITY_FEED_URL}")
    except Exception as e:
        logger.error(f"❌ Error forwarding event: {e}")

def run_consumer():
    """Run the Kafka consumer"""
    consumer = create_consumer()
    
    try:
        logger.info(f"Subscribing to topics: {TOPICS}")
        consumer.subscribe(TOPICS)
        
        logger.info("✅ Consumer started - waiting for events...")
        
        while True:
            msg = consumer.poll(timeout=1.0)
            
            if msg is None:
                continue
            
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    continue
                else:
                    raise KafkaException(msg.error())
            
            # Parse message
            try:
                event = json.loads(msg.value().decode("utf-8"))
                topic = msg.topic()
                
                logger.info(
                    f"📨 Event received from {topic}: "
                    f"{event.get('event_type')} | Actor: {event.get('actor', {}).get('id', 'unknown')}"
                )
                
                # Forward to Activity Feed
                forward_to_activity_feed(event)
            
            except json.JSONDecodeError:
                logger.warning(f"Failed to parse JSON from {msg.topic()}")
            except Exception as e:
                logger.error(f"Error processing message: {e}")
    
    except KeyboardInterrupt:
        logger.info("Shutdown signal received...")
    
    finally:
        consumer.close()
        logger.info("Consumer closed")

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    try:
        run_consumer()
    except Exception as e:
        logger.fatal(f"Fatal error: {e}")
        sys.exit(1)
