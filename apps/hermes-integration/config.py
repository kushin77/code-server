"""
Hermes Integration Configuration (SSOT)

All runtime tunables are read from environment variables with sane defaults.
Never hard-code secrets or environment-specific values.
"""

import os

# ── Server ────────────────────────────────────────────────────────────────────
PORT: int = int(os.getenv("HERMES_PORT", "8000"))
HOST: str = os.getenv("HERMES_HOST", "0.0.0.0")
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
DEBUG: bool = ENVIRONMENT == "development"

# ── Hermes Repo ───────────────────────────────────────────────────────────────
HERMES_REPO_PATH: str = os.getenv("HERMES_REPO_PATH", "/home/akushnir/hermes-agent")

# ── Agent Endpoints ───────────────────────────────────────────────────────────
AGENT_CODE_REVIEWER_HOST: str = os.getenv("AGENT_CODE_REVIEWER_HOST", "code-server-agent-code-reviewer")
AGENT_CODE_REVIEWER_PORT: int = int(os.getenv("AGENT_CODE_REVIEWER_PORT", "9000"))
AGENT_INCIDENT_RESPONDER_HOST: str = os.getenv("AGENT_INCIDENT_RESPONDER_HOST", "code-server-agent-incident-responder")
AGENT_INCIDENT_RESPONDER_PORT: int = int(os.getenv("AGENT_INCIDENT_RESPONDER_PORT", "9000"))
AGENT_DOC_WRITER_HOST: str = os.getenv("AGENT_DOC_WRITER_HOST", "code-server-agent-doc-writer")
AGENT_DOC_WRITER_PORT: int = int(os.getenv("AGENT_DOC_WRITER_PORT", "9000"))
AGENT_TEST_GENERATOR_HOST: str = os.getenv("AGENT_TEST_GENERATOR_HOST", "code-server-agent-test-generator")
AGENT_TEST_GENERATOR_PORT: int = int(os.getenv("AGENT_TEST_GENERATOR_PORT", "9000"))

# ── External Services ─────────────────────────────────────────────────────────
OPA_URL: str = os.getenv("OPA_URL", "http://opa:8181")
KAFKA_BROKER: str = os.getenv("KAFKA_BROKER", "redpanda:9092")
OTEL_ENDPOINT: str = os.getenv("OTEL_ENDPOINT", "")

# ── Orchestration Tunables ────────────────────────────────────────────────────
HEALTH_SWEEP_INTERVAL_SECONDS: int = int(os.getenv("HEALTH_SWEEP_INTERVAL_SECONDS", "30"))
AGENT_STALE_THRESHOLD_SECONDS: int = int(os.getenv("AGENT_STALE_THRESHOLD_SECONDS", "60"))

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
LOG_FORMAT: str = "json"

# ── Health check ──────────────────────────────────────────────────────────────
HEALTH_CHECK_TIMEOUT: int = int(os.getenv("HEALTH_CHECK_TIMEOUT", "5"))
