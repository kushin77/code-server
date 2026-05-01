"""
Environment Provisioner Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.
"""

import os
from typing import Optional


# ── Server ────────────────────────────────────────────────────────────────────
PORT: int = int(os.getenv("PROVISIONER_PORT", "8000"))
HOST: str = os.getenv("PROVISIONER_HOST", "0.0.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
DEBUG: bool = ENVIRONMENT == "development"

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"  # Structured logging (SLOG)

# ── Provisioner Settings ──────────────────────────────────────────────────────
ENV_YAML_PATH: str = os.getenv("ENV_YAML_PATH", "env.yaml")
SCHEMA_PATH: str = os.getenv("SCHEMA_PATH", "schemas/env-yaml.v1.json")
ARTIFACTS_DIR: str = os.getenv("ARTIFACTS_DIR", "artifacts")

# ── External services ─────────────────────────────────────────────────────────
VAULT_URL: Optional[str] = os.getenv("VAULT_URL")  # Optional: secrets injection
KUBERNETES_NAMESPACE: str = os.getenv("KUBERNETES_NAMESPACE", "default")

# ── Health check configuration ────────────────────────────────────────────────
HEALTH_CHECK_TIMEOUT: int = int(os.getenv("HEALTH_CHECK_TIMEOUT", "5"))
