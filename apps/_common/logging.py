import logging
import json
import os
import sys
from datetime import datetime
from typing import Any, Dict

class JsonFormatter(logging.Formatter):
    """Standardized JSON Formatter for SLOG (System Log)."""
    def format(self, record: logging.LogRecord) -> str:
        log_data: Dict[str, Any] = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
            "module": record.module,
            "process": record.process,
            "thread": record.threadName,
        }
        
        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)
            
        # Environment metadata
        log_data["host"] = os.getenv("HOSTNAME", "unknown")
        log_data["service"] = os.getenv("SERVICE_NAME", "unknown")
        log_data["epic"] = "1532"
        
        return json.dumps(log_data)

def setup_logging(service_name: str = None, level: str = "INFO"):
    """Initializes standardized JSON logging for the service."""
    if service_name:
        os.environ["SERVICE_NAME"] = service_name
        
    log_level_str = os.getenv("LOG_LEVEL", level).upper()
    log_level = getattr(logging, log_level_str, logging.INFO)
    
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)
    
    # Clear existing handlers
    while root_logger.handlers:
        root_logger.removeHandler(root_logger.handlers[0])
    
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root_logger.addHandler(handler)
    
    logging.info(f"Logging initialized for {service_name or 'unknown'} in JSON format")
