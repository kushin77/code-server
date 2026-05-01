"""
Paperclip Human Control Plane Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.

Startup validation ensures production deployments have required secrets.
"""

import os
from typing import Optional


# ── Server ────────────────────────────────────────────────────────────────────
PORT: int = int(os.getenv("PAPERCLIP_PORT", "8010"))
HOST: str = os.getenv("PAPERCLIP_HOST", "0.0.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
DEBUG: bool = ENVIRONMENT == "development"

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"  # Structured logging (SLOG)

# ── External services ─────────────────────────────────────────────────────────
OPA_URL: str = os.getenv("OPA_URL", "http://opa:8181")
REPUTATION_ENGINE_URL: str = os.getenv("REPUTATION_ENGINE_URL", "http://reputation-engine:8000")

# ── Kafka / Event Bus ─────────────────────────────────────────────────────────
KAFKA_BROKER: str = os.getenv("KAFKA_BROKER", "redpanda:9092")

# ── Approval Tunables ─────────────────────────────────────────────────────────
APPROVAL_TIMEOUT_ESCALATE_SECONDS: int = int(os.getenv("APPROVAL_TIMEOUT_ESCALATE", "300"))
APPROVAL_TIMEOUT_DENY_SECONDS: int = int(os.getenv("APPROVAL_TIMEOUT_DENY", "900"))
KILLSWITCH_BROADCAST_TIMEOUT_SECONDS: int = int(os.getenv("KILLSWITCH_BROADCAST_TIMEOUT", "10"))

# ── Auth / Security ───────────────────────────────────────────────────────────
SECRET_KEY: str = os.getenv("SECRET_KEY", "")

# ── Health check configuration ────────────────────────────────────────────────
HEALTH_CHECK_TIMEOUT: int = int(os.getenv("HEALTH_CHECK_TIMEOUT", "5"))


def validate_config() -> None:
    """
    Validate configuration on startup.

    Raises RuntimeError if production environment is missing critical secrets.
    """
    if ENVIRONMENT == "production":
        missing: list[str] = []

        if not SECRET_KEY:
            missing.append("SECRET_KEY")

        if missing:
            raise RuntimeError(
                f"Production deployment requires: {', '.join(missing)}. "
                "Set these in your secrets manager / deployment manifest."
            )
