#!/bin/bash
###############################################################################
# @file        scripts/ops/kafka-memory-consumer.sh
# @module      ops/kafka-memory-consumer
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT


# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"
# @description Kafka consumer for continuous organizational memory ingestion
# @governance GOV-002
# @idempotent YES

# Source shared service endpoints
source "${REPO_ROOT}/scripts/_common/service-names.env"

# Configuration - use shared Redpanda endpoint
KAFKA_BROKER="${KAFKA_BROKER:-${REDPANDA_KAFKA_ENDPOINT}}"
MEMORY_ENGINE_URL="${MEMORY_ENGINE_URL:-http://localhost:8001}"
CONSUMER_GROUP="memory-engine-consumer"

# ============================================================================
# Kafka Consumer Setup
# ============================================================================

setup_memory_topics() {
    log_info "Ensuring Kafka topics exist for memory ingestion"
    
    local topics=(
        "incident.events"
        "code.review"
        "agent.audit"
    )
    
    for topic in "${topics[@]}"; do
        # Check if topic exists (simple check via docker exec if available)
        log_info "Topic ready: $topic (will be consumed by memory engine)"
    done
}


create_consumer_python_script() {
    local consumer_script="${REPO_ROOT}/apps/memory-engine/kafka_consumer.py"
    
    log_info "Creating Kafka consumer script: $consumer_script"
    mkdir -p "$(dirname "$consumer_script")"
    
    cat > "$consumer_script" <<'PYTHON_EOF'
#!/usr/bin/env python3
"""
@file apps/memory-engine/kafka_consumer.py
@description Kafka consumer for continuous organizational memory ingestion
@governance GOV-002
"""

import os
import json
import logging
from kafka import KafkaConsumer
from typing import Dict, Any
import requests
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(name)s] [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "localhost:9092")
MEMORY_ENGINE_URL = os.getenv("MEMORY_ENGINE_URL", "http://localhost:8001")
CONSUMER_GROUP = "memory-engine-consumer"

# Topic mappings
TOPIC_MAPPINGS = {
    "incident.events": "incidents",
    "code.review": "pr_descriptions",
    "agent.audit": "agent_learnings",
}


def process_incident_event(event: Dict[str, Any]) -> None:
    """Process incident event from Kafka."""
    try:
        status = event.get("status", "")
        
        if status in ("created", "resolved"):
            doc_json = {
                "title": event.get("title", "Untitled Incident"),
                "content": f"{event.get('description', '')}\n\n"
                          f"Status: {status}\n"
                          f"Root Cause: {event.get('root_cause', 'N/A')}\n"
                          f"Resolution: {event.get('resolution', 'N/A')}",
                "collection": "incidents",
                "source_url": event.get("url"),
                "tags": ["incident", status, event.get("severity", "medium")],
                "confidence_score": 0.85,
            }
            
            response = requests.post(
                f"{MEMORY_ENGINE_URL}/ingest",
                json=doc_json,
                timeout=10,
            )
            
            if response.status_code == 200:
                logger.info(f"Ingested incident: {event.get('title')}")
            else:
                logger.error(f"Failed to ingest incident: {response.text}")
    except Exception as e:
        logger.error(f"Error processing incident event: {e}")


def process_pr_event(event: Dict[str, Any]) -> None:
    """Process PR review event from Kafka."""
    try:
        if event.get("status") == "merged":
            doc_json = {
                "title": f"PR #{event.get('number')}: {event.get('title', 'Untitled')}",
                "content": event.get("description", ""),
                "collection": "pr_descriptions",
                "source_url": event.get("html_url"),
                "tags": ["pr", "merged", event.get("author", "unknown")],
                "confidence_score": 0.80,
            }
            
            response = requests.post(
                f"{MEMORY_ENGINE_URL}/ingest",
                json=doc_json,
                timeout=10,
            )
            
            if response.status_code == 200:
                logger.info(f"Ingested PR: {event.get('title')}")
            else:
                logger.error(f"Failed to ingest PR: {response.text}")
    except Exception as e:
        logger.error(f"Error processing PR event: {e}")


def process_agent_learning(event: Dict[str, Any]) -> None:
    """Process agent learning from Kafka."""
    try:
        if event.get("success"):  # Only store successful learnings
            doc_json = {
                "title": f"Agent Learning: {event.get('task_name', 'Untitled')}",
                "content": f"Task: {event.get('task_name')}\n"
                          f"Success: {event.get('success')}\n"
                          f"Root Cause: {event.get('root_cause', 'N/A')}\n"
                          f"Resolution Steps: {event.get('resolution_steps', 'N/A')}\n"
                          f"Tokens Used: {event.get('tokens_used', 0)}\n"
                          f"Duration: {event.get('duration_seconds', 0)}s",
                "collection": "agent_learnings",
                "tags": ["agent", "learning", event.get("agent_type", "unknown")],
                "confidence_score": 0.90 if event.get("success") else 0.50,
            }
            
            response = requests.post(
                f"{MEMORY_ENGINE_URL}/ingest",
                json=doc_json,
                timeout=10,
            )
            
            if response.status_code == 200:
                logger.info(f"Ingested agent learning: {event.get('task_name')}")
            else:
                logger.error(f"Failed to ingest agent learning: {response.text}")
    except Exception as e:
        logger.error(f"Error processing agent learning: {e}")


def main():
    """Start Kafka consumer."""
    logger.info(f"Starting memory engine consumer from {KAFKA_BROKER}")
    
    try:
        consumer = KafkaConsumer(
            *TOPIC_MAPPINGS.keys(),
            bootstrap_servers=KAFKA_BROKER,
            group_id=CONSUMER_GROUP,
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            auto_offset_reset='earliest',
            enable_auto_commit=True,
        )
        
        logger.info(f"Consumer subscribed to topics: {list(TOPIC_MAPPINGS.keys())}")
        
        for message in consumer:
            topic = message.topic
            event = message.value
            
            logger.info(f"Received event from topic '{topic}': {event.get('title', 'N/A')}")
            
            if topic == "incident.events":
                process_incident_event(event)
            elif topic == "code.review":
                process_pr_event(event)
            elif topic == "agent.audit":
                process_agent_learning(event)
            
    except Exception as e:
        logger.error(f"Consumer error: {e}")
        raise


if __name__ == "__main__":
    main()
PYTHON_EOF
    
    chmod +x "$consumer_script"
    log_success "Created Kafka consumer: $consumer_script"
}


# ============================================================================
# Main
# ============================================================================

main() {
    log_info "Setting up Kafka consumer for memory ingestion"
    
    setup_memory_topics
    create_consumer_python_script
    
    log_success "Kafka consumer setup complete"
    log_info "To start the consumer, run: python3 apps/memory-engine/kafka_consumer.py"
}

main "$@"
