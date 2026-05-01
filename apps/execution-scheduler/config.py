"""
Execution Scheduler Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.

Startup validation ensures production deployments have required secrets.
"""

import os
from typing import Optional


# ── Server ────────────────────────────────────────────────────────────────────
PORT: int = int(os.getenv("SCHEDULER_PORT", "8030"))
HOST: str = os.getenv("SCHEDULER_HOST", "0.0.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
DEBUG: bool = ENVIRONMENT == "development"

# ── Database ──────────────────────────────────────────────────────────────────
DATABASE_URL: Optional[str] = os.getenv("DATABASE_URL")  # Optional for stateless/test mode

# ── Auth / Security ───────────────────────────────────────────────────────────
SCHEDULER_API_KEY: str = os.getenv("SCHEDULER_API_KEY", "")
OAUTH2_INTROSPECT_URL: str = os.getenv("OAUTH2_INTROSPECT_URL", "")
OAUTH2_CLIENT_ID: str = os.getenv("OAUTH2_CLIENT_ID", "")
OAUTH2_CLIENT_SECRET: str = os.getenv("OAUTH2_CLIENT_SECRET", "")

# ── Kafka / Event Bus ─────────────────────────────────────────────────────────
KAFKA_BROKER: str = os.getenv("KAFKA_BROKER", "redpanda:9092")

# ── External services ─────────────────────────────────────────────────────────
OPA_URL: str = os.getenv("OPA_URL", "http://opa:8181")
HERMES_URL: str = os.getenv("HERMES_URL", "")  # empty = disabled

# ── Scheduler Tunables ────────────────────────────────────────────────────────
MAX_CONCURRENT_TASKS: int = int(os.getenv("MAX_CONCURRENT_TASKS", "50"))
TASK_TIMEOUT_SECONDS: int = int(os.getenv("TASK_TIMEOUT_SECONDS", "300"))
RETRY_DELAY_SECONDS: int = int(os.getenv("RETRY_DELAY_SECONDS", "5"))
MAX_TASK_RETRIES: int = int(os.getenv("MAX_TASK_RETRIES", "3"))

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"  # Structured logging (SLOG)

# ── Health check configuration ────────────────────────────────────────────────
HEALTH_CHECK_TIMEOUT: int = int(os.getenv("HEALTH_CHECK_TIMEOUT", "5"))


def validate_config() -> None:
    """
    Validate configuration on startup.

    Raises RuntimeError if production environment is missing critical secrets.
    """
    if ENVIRONMENT == "production":
        missing: list[str] = []

        if not SCHEDULER_API_KEY:
            missing.append("SCHEDULER_API_KEY")

        if not DATABASE_URL:
            missing.append("DATABASE_URL")

        if missing:
            raise RuntimeError(
                f"Production deployment requires: {', '.join(missing)}. "
                "Set these in your secrets manager / deployment manifest."
            )
