"""
Centralized Logging Module for Code Server Enterprise
Consolidates 24 duplicate logging functions across the codebase
"""
import os
import json
import sys
import logging
from datetime import datetime
from typing import Optional, Dict, Any
from enum import Enum


class LogLevel(Enum):
    """Log level enumeration."""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class LogFormat(Enum):
    """Log format enumeration."""
    TEXT = "text"
    JSON = "json"
    STRUCTURED = "structured"


class CodeServerLogger:
    """
    Centralized logger for Code Server Enterprise.
    
    Features:
    - Structured logging (JSON, text, or custom format)
    - ANSI color support for terminal output
    - File logging support
    - Timestamp and context tracking
    - Log filtering and leveling
    """
    
    # ANSI color codes
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN = "\033[96m"
    WHITE = "\033[97m"
    GRAY = "\033[90m"
    RESET = "\033[0m"
    BOLD = "\033[1m"
    
    def __init__(
        self,
        name: str,
        level: str = "INFO",
        log_format: str = "text",
        log_file: Optional[str] = None,
        use_colors: bool = True,
    ):
        """
        Initialize logger.
        
        Args:
            name: Logger name
            level: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
            log_format: Log format (text, json, structured)
            log_file: Optional file path for logging
            use_colors: Enable ANSI colors in output
        """
        self.name = name
        self.level = level
        self.log_format = log_format
        self.log_file = log_file
        self.use_colors = use_colors and sys.stderr.isatty()
        
        # Create Python logger
        self.logger = logging.getLogger(name)
        self.logger.setLevel(getattr(logging, level.upper()))
        
        # Add handlers
        self._setup_handlers()
    
    def _setup_handlers(self) -> None:
        """Setup logging handlers."""
        # Console handler
        console_handler = logging.StreamHandler(sys.stderr)
        console_handler.setLevel(getattr(logging, self.level.upper()))
        console_handler.setFormatter(self._get_formatter())
        self.logger.addHandler(console_handler)
        
        # File handler if specified
        if self.log_file:
            try:
                file_handler = logging.FileHandler(self.log_file, mode="a")
                file_handler.setLevel(getattr(logging, self.level.upper()))
                file_handler.setFormatter(self._get_formatter(for_file=True))
                self.logger.addHandler(file_handler)
            except Exception as e:
                self.error(f"Failed to setup file logging to {self.log_file}: {e}")
    
    def _get_formatter(self, for_file: bool = False) -> logging.Formatter:
        """Get appropriate formatter based on log format."""
        if self.log_format == "json" or for_file:
            return logging.Formatter(
                '{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
            )
        else:
            timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
            if self.use_colors and not for_file:
                return logging.Formatter(
                    f"{self.GRAY}[%(asctime)s]{self.RESET} %(message)s",
                    datefmt="%H:%M:%S"
                )
            else:
                return logging.Formatter(
                    "[%(asctime)s] %(levelname)s: %(message)s",
                    datefmt="%Y-%m-%d %H:%M:%S"
                )
    
    def _colorize(self, text: str, color: str) -> str:
        """Apply color to text if colors enabled."""
        if self.use_colors:
            return f"{color}{text}{self.RESET}"
        return text
    
    def debug(self, message: str, **kwargs) -> None:
        """Log debug message."""
        self.logger.debug(self._format_message(message, **kwargs))
    
    def info(self, message: str, **kwargs) -> None:
        """Log info message."""
        self.logger.info(self._format_message(message, **kwargs))
    
    def success(self, message: str, **kwargs) -> None:
        """Log success message (info level with green color)."""
        colored_msg = self._colorize(f"✓ {message}", self.GREEN)
        self.logger.info(self._format_message(colored_msg, **kwargs))
    
    def warning(self, message: str, **kwargs) -> None:
        """Log warning message."""
        colored_msg = self._colorize(f"⚠ {message}", self.YELLOW)
        self.logger.warning(self._format_message(colored_msg, **kwargs))
    
    def error(self, message: str, **kwargs) -> None:
        """Log error message."""
        colored_msg = self._colorize(f"✗ {message}", self.RED)
        self.logger.error(self._format_message(colored_msg, **kwargs))
    
    def critical(self, message: str, **kwargs) -> None:
        """Log critical message."""
        colored_msg = self._colorize(f"FATAL: {message}", f"{self.RED}{self.BOLD}")
        self.logger.critical(self._format_message(colored_msg, **kwargs))
    
    def _format_message(self, message: str, **kwargs) -> str:
        """Format log message with optional context."""
        if not kwargs:
            return message
        
        # Add context as structured data if JSON format
        if self.log_format == "json":
            return f"{message} | context={json.dumps(kwargs)}"
        else:
            context_str = " | ".join(f"{k}={v}" for k, v in kwargs.items())
            return f"{message} [{context_str}]"


# Global logger instance
_global_logger: Optional[CodeServerLogger] = None


def get_logger(
    name: str,
    level: Optional[str] = None,
    log_format: Optional[str] = None,
) -> CodeServerLogger:
    """
    Get or create a logger instance.
    
    Args:
        name: Logger name
        level: Log level (uses LOG_LEVEL env var if not specified)
        log_format: Log format (uses LOG_FORMAT env var if not specified)
    
    Returns:
        CodeServerLogger instance
    """
    level = level or os.getenv("LOG_LEVEL", "INFO")
    log_format = log_format or os.getenv("LOG_FORMAT", "text")
    
    return CodeServerLogger(
        name=name,
        level=level,
        log_format=log_format,
        use_colors=True,
    )


def setup_global_logging(
    level: str = "INFO",
    log_format: str = "text",
    log_file: Optional[str] = None,
) -> CodeServerLogger:
    """
    Setup the global logger instance.
    
    Args:
        level: Log level
        log_format: Log format
        log_file: Optional log file path
    
    Returns:
        Global logger instance
    """
    global _global_logger
    _global_logger = CodeServerLogger(
        name="code-server",
        level=level,
        log_format=log_format,
        log_file=log_file,
    )
    return _global_logger


def log_info(message: str, **kwargs) -> None:
    """Log info message using global logger."""
    if _global_logger:
        _global_logger.info(message, **kwargs)
    else:
        print(f"[INFO] {message}", file=sys.stderr)


def log_success(message: str, **kwargs) -> None:
    """Log success message using global logger."""
    if _global_logger:
        _global_logger.success(message, **kwargs)
    else:
        print(f"✓ {message}", file=sys.stderr)


def log_warning(message: str, **kwargs) -> None:
    """Log warning message using global logger."""
    if _global_logger:
        _global_logger.warning(message, **kwargs)
    else:
        print(f"⚠ {message}", file=sys.stderr)


def log_error(message: str, **kwargs) -> None:
    """Log error message using global logger."""
    if _global_logger:
        _global_logger.error(message, **kwargs)
    else:
        print(f"✗ {message}", file=sys.stderr)


def log_debug(message: str, **kwargs) -> None:
    """Log debug message using global logger."""
    if _global_logger:
        _global_logger.debug(message, **kwargs)


class _JsonFormatter(logging.Formatter):
    """JSON log formatter for structured log output (SLOG compliance)."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict = {
            "timestamp": self.formatTime(record, datefmt="%Y-%m-%dT%H:%M:%S"),
            "level": record.levelname,
            "service": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def setup_logging(service: str = "code-server") -> logging.Logger:
    """
    Configure root logger with JSON structured output (SLOG).

    Call once at application startup:
        from apps._shared.python.logging import setup_logging
        logger = setup_logging("my-service")

    Respects LOG_LEVEL env var (default: INFO).
    Output is newline-delimited JSON suitable for Loki/OTel ingestion.
    """
    level_name = os.environ.get("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_JsonFormatter())

    root = logging.getLogger()
    root.setLevel(level)
    root.handlers = [handler]

    return logging.getLogger(service)
