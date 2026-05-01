"""
Agent Runtime Structured Logging (SLOG)

Single factory for structured JSON logging across the entire application.
Import and use `get_logger(__name__)` in every module — never use `print()`.

All logs emit as JSON with standard fields (ts, level, svc, msg, execution_id, trace_id, etc.)
for correlation in Loki and OpenTelemetry collectors.
"""

import logging
import sys
from typing import Any, Optional

try:
    from pythonjsonlogger import jsonlogger
    HAS_PYTHONJSONLOGGER = True
except ImportError:
    HAS_PYTHONJSONLOGGER = False

from config import LOG_LEVEL, LOG_FORMAT


def get_logger(name: str, extra_fields: Optional[dict[str, Any]] = None) -> logging.Logger:
    """
    Return a JSON-structured logger for the given module name.
    
    Args:
        name: Module name (typically `__name__`)
        extra_fields: Optional dict of extra fields to include in all records from this logger
    
    Returns:
        Configured logger with SLOG output
    """
    logger = logging.getLogger(name)
    
    # Only configure once per logger
    if logger.handlers:
        return logger
    
    handler = logging.StreamHandler(sys.stdout)
    
    if HAS_PYTHONJSONLOGGER and LOG_FORMAT == "json":
        # Structured JSON output
        formatter = jsonlogger.JsonFormatter(
            fmt="%(asctime)s %(name)s %(levelname)s %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S%z",
            rename_fields={"asctime": "ts", "name": "svc", "levelname": "level", "message": "msg"},
        )
    else:
        # Fallback to text format if pythonjsonlogger unavailable
        formatter = logging.Formatter(
            fmt="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S",
        )
    
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.setLevel(LOG_LEVEL)
    logger.propagate = False
    
    return logger


# Module-level convenience logger
log = get_logger("agent-runtime")


def log_event(
    logger: logging.Logger,
    event: str,
    execution_id: Optional[str] = None,
    trace_id: Optional[str] = None,
    **kwargs: Any,
) -> None:
    """
    Emit a structured log record with a named event key and correlation IDs.
    
    Usage:
        log_event(logger, "agent_execution_start", execution_id="exec-xyz", agent_type="code-reviewer")
    
    Args:
        logger: Logger instance
        event: Named event string (e.g., "agent_execution_start")
        execution_id: Optional execution ID for tracing
        trace_id: Optional distributed trace ID
        **kwargs: Additional fields to include in log record
    """
    extra = {
        "event": event,
    }
    if execution_id:
        extra["execution_id"] = execution_id
    if trace_id:
        extra["trace_id"] = trace_id
    extra.update(kwargs)
    
    logger.info(event, extra=extra)
