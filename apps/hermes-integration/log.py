"""
Hermes Integration Structured Logging (SLOG)

Single factory for structured JSON logging across the entire application.
Import and use `get_logger(__name__)` in every module — never use `print()`.

All logs emit as JSON with standard fields (ts, level, svc, msg) for correlation
in Loki and OpenTelemetry collectors.
"""

import logging
import os
import sys
from typing import Any, Optional

try:
    from pythonjsonlogger import jsonlogger
    HAS_PYTHONJSONLOGGER = True
except ImportError:
    HAS_PYTHONJSONLOGGER = False

_LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
_LOG_FORMAT: str = "json"


def get_logger(name: str, extra_fields: Optional[dict[str, Any]] = None) -> logging.Logger:
    """Return a JSON-structured logger for the given module name."""
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger

    handler = logging.StreamHandler(sys.stdout)
    if HAS_PYTHONJSONLOGGER and _LOG_FORMAT == "json":
        formatter = jsonlogger.JsonFormatter(
            fmt="%(asctime)s %(name)s %(levelname)s %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S%z",
            rename_fields={"asctime": "ts", "name": "svc", "levelname": "level", "message": "msg"},
        )
    else:
        formatter = logging.Formatter(
            fmt="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S",
        )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.setLevel(_LOG_LEVEL)
    logger.propagate = False
    return logger


log = get_logger("hermes-integration")


def log_event(
    logger: logging.Logger,
    event: str,
    trace_id: Optional[str] = None,
    **kwargs: Any,
) -> None:
    """Emit a structured log record with a named event key."""
    extra = {"event": event}
    if trace_id:
        extra["trace_id"] = trace_id
    extra.update(kwargs)
    logger.info(event, extra=extra)
