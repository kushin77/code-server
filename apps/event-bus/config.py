"""
Event Bus Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.
"""

import os

# ── Kafka Broker ──────────────────────────────────────────────────────────────
KAFKA_BOOTSTRAP_SERVERS: str = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "redpanda:9092")
KAFKA_DEFAULT_GROUP_ID: str = os.getenv("KAFKA_DEFAULT_GROUP_ID", "code-server-event-bus")
KAFKA_PRODUCER_ACKS: str = os.getenv("KAFKA_PRODUCER_ACKS", "all")
KAFKA_CONSUMER_AUTO_OFFSET_RESET: str = os.getenv("KAFKA_CONSUMER_AUTO_OFFSET_RESET", "earliest")

# ── Schema Validation ─────────────────────────────────────────────────────────
SCHEMA_VALIDATION_ENABLED: bool = os.getenv("SCHEMA_VALIDATION_ENABLED", "true").lower() == "true"
SCHEMA_REGISTRY_URL: str = os.getenv("SCHEMA_REGISTRY_URL", "")

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
