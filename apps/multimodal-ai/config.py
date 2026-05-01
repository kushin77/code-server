"""
Multimodal AI Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.
"""

import os

# ── Server ────────────────────────────────────────────────────────────────────
PORT: int = int(os.getenv("MULTIMODAL_AI_PORT", "8000"))
HOST: str = os.getenv("MULTIMODAL_AI_HOST", "0.0.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
DEBUG: bool = ENVIRONMENT == "development"

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"

# ── Ollama (local LLM) ────────────────────────────────────────────────────────
OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434")
OLLAMA_MODEL: str = os.getenv("OLLAMA_MODEL", "llama3:8b")
OLLAMA_VISION_MODEL: str = os.getenv("OLLAMA_VISION_MODEL", "llava:13b")

# ── OpenAI (fallback) ─────────────────────────────────────────────────────────
OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL: str = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_VISION_MODEL: str = os.getenv("OPENAI_VISION_MODEL", "gpt-4-vision-preview")

# ── Diagram LLM ───────────────────────────────────────────────────────────────
DIAGRAM_LLM_BACKEND: str = os.getenv("DIAGRAM_LLM_BACKEND", "ollama")  # ollama | openai
LLM_TIMEOUT_SEC: int = int(os.getenv("LLM_TIMEOUT_SEC", "45"))

# ── Vision ────────────────────────────────────────────────────────────────────
VISION_BACKEND: str = os.getenv("VISION_BACKEND", "ollama")  # ollama | openai
VISION_TIMEOUT_SEC: int = int(os.getenv("VISION_TIMEOUT_SEC", "60"))

# ── Whisper (speech-to-text) ──────────────────────────────────────────────────
WHISPER_MODEL: str = os.getenv("WHISPER_MODEL", "base")
TTS_BACKEND: str = os.getenv("TTS_BACKEND", "gtts")  # gtts | azure
AZURE_TTS_KEY: str = os.getenv("AZURE_TTS_KEY", "")
AZURE_TTS_REGION: str = os.getenv("AZURE_TTS_REGION", "eastus")
AZURE_TTS_VOICE: str = os.getenv("AZURE_TTS_VOICE", "en-US-JennyNeural")

# ── Health check ──────────────────────────────────────────────────────────────
HEALTH_CHECK_TIMEOUT: int = int(os.getenv("HEALTH_CHECK_TIMEOUT", "5"))


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
