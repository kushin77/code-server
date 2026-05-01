"""
Agent Runtime Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.

Startup validation ensures production deployments have required secrets.
"""

import os
from typing import Optional


# ── Server ────────────────────────────────────────────────────────────────────
PORT: int = int(os.getenv("AGENT_RUNTIME_PORT", "8020"))
HOST: str = os.getenv("AGENT_RUNTIME_HOST", "0.0.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
DEBUG: bool = ENVIRONMENT == "development"

# ── Database ──────────────────────────────────────────────────────────────────
DATABASE_URL: Optional[str] = os.getenv("DATABASE_URL")  # Optional for agent-only mode

# ── Cache ─────────────────────────────────────────────────────────────────────
REDIS_URL: Optional[str] = os.getenv("REDIS_URL")  # Optional for local dev

# ── Auth / Security ───────────────────────────────────────────────────────────
SECRET_KEY: str = os.getenv("SECRET_KEY", "")
OIDC_CLIENT_ID: str = os.getenv("OIDC_CLIENT_ID", "agent-runtime")
OIDC_ISSUER: Optional[str] = os.getenv("OIDC_ISSUER")  # Optional for dev

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"  # Structured logging (SLOG)

# ── External services ─────────────────────────────────────────────────────────
OPA_URL: str = os.getenv("OPA_URL", "http://opa:8181")
REPUTATION_ENGINE_URL: str = os.getenv("REPUTATION_ENGINE_URL", "http://reputation-engine:8080")
PAPERCLIP_URL: str = os.getenv("PAPERCLIP_URL", "http://paperclip:8010")
SCHEDULER_URL: str = os.getenv("SCHEDULER_URL", "http://execution-scheduler:8030")

# ── Hermes Orchestrator ───────────────────────────────────────────────────────
HERMES_URL: str = os.getenv("HERMES_URL", "")                   # empty = disabled
HERMES_HEARTBEAT_INTERVAL: int = int(os.getenv("HERMES_HEARTBEAT_INTERVAL", "30"))
HERMES_REGISTRATION_RETRIES: int = int(os.getenv("HERMES_REGISTRATION_RETRIES", "3"))

# ── Timeouts ──────────────────────────────────────────────────────────────────
REQUEST_TIMEOUT_SECONDS: int = int(os.getenv("REQUEST_TIMEOUT_SECONDS", "30"))
APPROVAL_TIMEOUT_ESCALATE_SECONDS: int = int(os.getenv("APPROVAL_TIMEOUT_ESCALATE", "300"))
APPROVAL_TIMEOUT_DENY_SECONDS: int = int(os.getenv("APPROVAL_TIMEOUT_DENY", "900"))

# ── Health check configuration ────────────────────────────────────────────────
HEALTH_CHECK_TIMEOUT: int = int(os.getenv("HEALTH_CHECK_TIMEOUT", "5"))
READINESS_CHECK_TIMEOUT: int = int(os.getenv("READINESS_CHECK_TIMEOUT", "10"))


def validate_config() -> None:
    """
    Validate configuration on startup.
    
    Raises RuntimeError if production environment has missing critical secrets.
    """
    if ENVIRONMENT == "production":
        missing = []
        
        if not SECRET_KEY:
            missing.append("SECRET_KEY")
        
        if not DATABASE_URL:
            missing.append("DATABASE_URL")
        
        if not REDIS_URL:
            missing.append("REDIS_URL")
        
        if missing:
            raise RuntimeError(
                f"Production deployment requires the following environment variables: {', '.join(missing)}. "
                f"Generate SECRET_KEY with: python -c \"import secrets; print(secrets.token_hex(32))\""
            )
