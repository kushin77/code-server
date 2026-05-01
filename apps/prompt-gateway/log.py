"""
Prompt Gateway — Structured Logging Factory

Usage:
    from log import get_logger
    logger = get_logger(__name__)
"""

import logging
import os

try:
    from pythonjsonlogger import jsonlogger  # type: ignore

    class _JsonFmt(jsonlogger.JsonFormatter):
        def add_fields(self, log_record, record, message_dict):
            super().add_fields(log_record, record, message_dict)
            log_record.setdefault("service", "prompt-gateway")
            log_record.setdefault("level", record.levelname)

    _FMT: logging.Formatter = _JsonFmt("%(asctime)s %(name)s %(levelname)s %(message)s")
except ImportError:
    _FMT = logging.Formatter("%(asctime)s %(name)s %(levelname)s %(message)s")

_LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")


def get_logger(name: str) -> logging.Logger:
    """Return a structured logger for *name*."""
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(_FMT)
        logger.addHandler(handler)
    logger.setLevel(_LOG_LEVEL)
    logger.propagate = False
    return logger
