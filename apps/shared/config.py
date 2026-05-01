"""
Shared Monitoring Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.
"""

import os
from typing import Optional


# ── Monitoring ────────────────────────────────────────────────────────────────
MONITORING_ENABLED: bool = os.getenv("MONITORING_ENABLED", "true").lower() == "true"
METRICS_PORT: int = int(os.getenv("METRICS_PORT", "8000"))
METRICS_PATH: str = os.getenv("METRICS_PATH", "/metrics")

# ── Application Metadata ──────────────────────────────────────────────────────
APP_NAME: str = os.getenv("APP_NAME", "shared")
APP_VERSION: str = os.getenv("APP_VERSION", "1.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"  # Structured logging (SLOG)
