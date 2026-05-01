"""
Activity Feed Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.
"""

import os

# ── Server ────────────────────────────────────────────────────────────────────
PORT: int = int(os.getenv("ACTIVITY_FEED_PORT", "8000"))
HOST: str = os.getenv("ACTIVITY_FEED_HOST", "0.0.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
DEBUG: bool = ENVIRONMENT == "development"

# ── Kafka / Event Bus ─────────────────────────────────────────────────────────
KAFKA_BOOTSTRAP_SERVERS: str = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "redpanda:9092")
KAFKA_CONSUMER_GROUP: str = os.getenv("KAFKA_CONSUMER_GROUP", "activity-feed-consumer")

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"

# ── Health check ──────────────────────────────────────────────────────────────
HEALTH_CHECK_TIMEOUT: int = int(os.getenv("HEALTH_CHECK_TIMEOUT", "5"))


def validate_config() -> None:
    """Validate configuration on startup.

    Raises RuntimeError if production environment is missing critical variables.
    """
    if ENVIRONMENT == "production":
        missing = [
            # No critical secrets required for this service
        ]
        if missing:
            raise RuntimeError(
                f"Production deployment requires: {', '.join(missing)}. "
                "Set these environment variables before starting."
            )
