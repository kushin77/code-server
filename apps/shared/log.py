"""
Logging factory for shared monitoring module.

Usage:
    from log import get_logger
    logger = get_logger(__name__)
    logger.info("message")
"""

import logging.config
import sys

import structlog


def get_logger(name: str) -> structlog.BoundLogger:
    """Get a configured logger instance."""
    return structlog.get_logger(name)
