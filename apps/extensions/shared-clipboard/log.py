"""Structured logging for shared-clipboard extension."""
import logging, os, sys
from typing import Any, Optional

try:
    from pythonjsonlogger import jsonlogger
    HAS_JSON = True
except ImportError:
    HAS_JSON = False

_LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

def get_logger(name: str, extra_fields: Optional[dict[str, Any]] = None) -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger
    handler = logging.StreamHandler(sys.stdout)
    if HAS_JSON:
        handler.setFormatter(jsonlogger.JsonFormatter(
            fmt="%(asctime)s %(name)s %(levelname)s %(message)s",
            rename_fields={"asctime": "ts", "name": "svc", "levelname": "level", "message": "msg"},
        ))
    else:
        handler.setFormatter(logging.Formatter("%(asctime)s [%(name)s] %(levelname)s: %(message)s"))
    logger.addHandler(handler)
    logger.setLevel(_LOG_LEVEL)
    logger.propagate = False
    return logger
