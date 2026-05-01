"""
Prompt Gateway Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.
"""

import os

# ── Service ────────────────────────────────────────────────────────────────────
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")

# ── Memory Engine Integration ─────────────────────────────────────────────────
MEMORY_ENGINE_URL: str = os.getenv("MEMORY_ENGINE_URL", "http://memory-engine:8001")
MEMORY_ENGINE_TIMEOUT_SEC: int = int(os.getenv("MEMORY_ENGINE_TIMEOUT_SEC", "10"))

# ── LLM Routing ───────────────────────────────────────────────────────────────
DEFAULT_LLM_BACKEND: str = os.getenv("DEFAULT_LLM_BACKEND", "ollama")  # ollama | openai
OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")
OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")

# ── Context Enrichment ────────────────────────────────────────────────────────
CONTEXT_MAX_TOKENS: int = int(os.getenv("CONTEXT_MAX_TOKENS", "2048"))
CONTEXT_CACHE_TTL_SECONDS: int = int(os.getenv("CONTEXT_CACHE_TTL_SECONDS", "300"))

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"


def validate_config() -> None:
    """Validate configuration on startup.

    Raises RuntimeError if production environment is missing critical variables.
    """
    if ENVIRONMENT == "production":
        missing = [
            *[v for v, val in {"OPENAI_API_KEY": OPENAI_API_KEY}.items() if not val],
        ]
        if missing:
            raise RuntimeError(
                f"Production deployment requires: {', '.join(missing)}. "
                "Set these environment variables before starting."
            )
