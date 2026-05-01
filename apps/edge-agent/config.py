"""
Edge Agent Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.
"""

import os

# ── Agent Identity ────────────────────────────────────────────────────────────
EDGE_AGENT_REGION: str = os.getenv("EDGE_AGENT_REGION", "us-west")
EDGE_AGENT_ID: str = os.getenv("EDGE_AGENT_ID", "")

# ── Replication ───────────────────────────────────────────────────────────────
REPLICATION_TARGET_REGIONS: str = os.getenv("REPLICATION_TARGET_REGIONS", "eu-central,asia-pacific")
REPLICATION_STALE_TTL_SECONDS: int = int(os.getenv("REPLICATION_STALE_TTL_SECONDS", "300"))

# ── Routing ───────────────────────────────────────────────────────────────────
ROUTING_OVERLOAD_THRESHOLD: float = float(os.getenv("ROUTING_OVERLOAD_THRESHOLD", "80.0"))
ROUTING_MIN_CAPACITY: int = int(os.getenv("ROUTING_MIN_CAPACITY", "1"))

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")


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
