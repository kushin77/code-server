"""
Memory Engine Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.
"""

import os
from typing import Optional


# ── Server ────────────────────────────────────────────────────────────────────
PORT: int = int(os.getenv("MEMORY_ENGINE_PORT", "8001"))
HOST: str = os.getenv("MEMORY_ENGINE_HOST", "0.0.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
DEBUG: bool = ENVIRONMENT == "development"

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"  # Structured logging (SLOG)

# ── Vector Store (Qdrant) ─────────────────────────────────────────────────────
QDRANT_HOST: str = os.getenv("QDRANT_HOST", "qdrant")
QDRANT_PORT: int = int(os.getenv("QDRANT_PORT", "6333"))
QDRANT_COLLECTION: str = os.getenv("QDRANT_COLLECTION", "code-server-memory")

# ── Embedding Model ───────────────────────────────────────────────────────────
OLLAMA_HOST: str = os.getenv("OLLAMA_HOST", "http://ollama:11434")
EMBED_MODEL: str = os.getenv("EMBED_MODEL", "nomic-embed-text")

# ── GitHub Integration ────────────────────────────────────────────────────────
GITHUB_REPO: str = os.getenv("GITHUB_REPO", "kushin77/code-server")
GITHUB_TOKEN: Optional[str] = os.getenv("GITHUB_TOKEN")

# ── Health check configuration ────────────────────────────────────────────────
HEALTH_CHECK_TIMEOUT: int = int(os.getenv("HEALTH_CHECK_TIMEOUT", "5"))
