"""
Reputation Engine Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.

Startup validation ensures production deployments have required secrets.
"""

import os
from typing import Optional


# ── Server ────────────────────────────────────────────────────────────────────
PORT: int = int(os.getenv("REPUTATION_ENGINE_PORT", "8000"))
HOST: str = os.getenv("REPUTATION_ENGINE_HOST", "0.0.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
DEBUG: bool = ENVIRONMENT == "development"

# ── Database ──────────────────────────────────────────────────────────────────
DATABASE_URL: Optional[str] = os.getenv("DATABASE_URL")  # Required in production

# ── Kafka / Event Bus ─────────────────────────────────────────────────────────
KAFKA_BOOTSTRAP_SERVERS: str = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")

# ── External services ─────────────────────────────────────────────────────────
OPA_URL: str = os.getenv("OPA_URL", "http://localhost:8181")

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"  # Structured logging (SLOG)

# ── Reputation Tunables ───────────────────────────────────────────────────────
REPUTATION_STALE_THRESHOLD_DAYS: int = int(os.getenv("REPUTATION_STALE_THRESHOLD_DAYS", "30"))
REPUTATION_SYNC_INTERVAL_SECONDS: int = int(os.getenv("REPUTATION_SYNC_INTERVAL_SECONDS", "60"))
OPA_SYNC_INTERVAL_SECONDS: int = int(os.getenv("OPA_SYNC_INTERVAL_SECONDS", "300"))

# ── Health check configuration ────────────────────────────────────────────────
HEALTH_CHECK_TIMEOUT: int = int(os.getenv("HEALTH_CHECK_TIMEOUT", "5"))


def validate_config() -> None:
    """
    Validate configuration on startup.

    Raises RuntimeError if production environment is missing critical secrets.
    """
    if ENVIRONMENT == "production":
        missing: list[str] = []

        if not DATABASE_URL:
            missing.append("DATABASE_URL")

        if missing:
            raise RuntimeError(
                f"Production deployment requires: {', '.join(missing)}. "
                "Set these in your secrets manager / deployment manifest."
            )
