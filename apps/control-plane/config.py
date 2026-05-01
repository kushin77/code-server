"""
Control Plane Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.
"""

import os
from typing import Optional


# ── Server ────────────────────────────────────────────────────────────────────
PORT: int = int(os.getenv("CONTROL_PLANE_PORT", "8082"))
HOST: str = os.getenv("CONTROL_PLANE_HOST", "0.0.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
DEBUG: bool = ENVIRONMENT == "development"

# ── Cluster Identity ──────────────────────────────────────────────────────────
DEPLOYMENT_ID: str = os.getenv("DEPLOYMENT_ID", "primary")

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"  # Structured logging (SLOG)

# ── External services ─────────────────────────────────────────────────────────
OPA_URL: str = os.getenv("OPA_URL", "http://opa:8181")
PAPERCLIP_URL: str = os.getenv("PAPERCLIP_URL", "http://paperclip:8010")
HERMES_URL: str = os.getenv("HERMES_URL", "")  # empty = disabled

# ── Health check configuration ────────────────────────────────────────────────
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
