#!/usr/bin/env python3
# @file        scripts/_common/logging.py
# @module      common/logging
# @description Standardized Python logging library matching shell logging standards.
# @owner       DevOps Team
# @status      Stable
#

import os
import sys
import json
from datetime import datetime
from typing import Any

# Color codes (can be disabled with LOG_NO_COLOR=1)
COLOR_RED = '\033[0;31m'
COLOR_YELLOW = '\033[0;33m'
COLOR_GREEN = '\033[0;32m'
COLOR_BLUE = '\033[0;34m'
COLOR_GRAY = '\033[0;37m'
COLOR_RESET = '\033[0m'

# Level constants
DEBUG = 0
INFO = 1
WARN = 2
ERROR = 3
FATAL = 4

LEVEL_NAMES = {
    DEBUG: "DEBUG",
    INFO: "INFO",
    WARN: "WARN",
    ERROR: "ERROR",
    FATAL: "FATAL"
}

# Resolve script name for logging
SCRIPT_NAME = os.path.basename(sys.argv[0])

def _get_env_int(var: str, default: int) -> int:
    val = os.environ.get(var)
    if not val:
        return default
    
    # Handle descriptive names
    val = val.lower().strip()
    if val in ('debug', '0'): return 0
    if val in ('info', '1'): return 1
    if val in ('warn', 'warning', '2'): return 2
    if val in ('error', '3'): return 3
    if val in ('fatal', '4'): return 4
    
    return default

# Global configuration
LOG_LEVEL = _get_env_int('LOG_LEVEL', INFO)
LOG_NO_COLOR = os.environ.get('LOG_NO_COLOR', '0') == '1'
LOG_FORMAT = os.environ.get('LOG_FORMAT', 'text').lower()
LOG_FILE = os.environ.get('LOG_FILE')

def _timestamp() -> str:
    """Get UTC timestamp in ISO 8601 format."""
    return datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

def _colorize_level(level: int, name: str) -> str:
    """Apply ANSI colors to level name."""
    if LOG_NO_COLOR:
        return name
    
    if level == DEBUG: return f"{COLOR_GRAY}{name}{COLOR_RESET}"
    if level == INFO:  return f"{COLOR_BLUE}{name}{COLOR_RESET}"
    if level == WARN:  return f"{COLOR_YELLOW}{name}{COLOR_RESET}"
    if level == ERROR: return f"{COLOR_RED}{name}{COLOR_RESET}"
    if level == FATAL: return f"{COLOR_RED}{name}{COLOR_RESET}"
    return name

def _log(level: int, msg: str):
    """Core logging implementation matching _log in logging.sh."""
    if level < LOG_LEVEL:
        return

    ts = _timestamp()
    level_name = LEVEL_NAMES.get(level, "UNKNOWN")

    if LOG_FORMAT == 'json':
        log_entry = {
            "ts": ts,
            "level": level_name,
            "script": SCRIPT_NAME,
            "msg": msg
        }
        json_line = json.dumps(log_entry)
        output = sys.stdout if level <= INFO else sys.stderr
        output.write(json_line + '\n')
        output.flush()
        
        if LOG_FILE:
            try:
                with open(LOG_FILE, 'a', encoding='utf-8') as f:
                    f.write(json_line + '\n')
            except Exception:
                pass
        return

    # Text mode
    colored_level = _colorize_level(level, level_name)
    formatted = f"[{ts}] [{colored_level}] {msg}"
    plain = f"[{ts}] [{level_name}] {msg}"

    output = sys.stdout if level <= INFO else sys.stderr
    output.write(formatted + '\n')
    output.flush()

    if LOG_FILE:
        try:
            with open(LOG_FILE, 'a', encoding='utf-8') as f:
                f.write(plain + '\n')
        except Exception:
            pass

def log_debug(msg: str): _log(DEBUG, msg)
def log_info(msg: str):  _log(INFO, msg)
def log_warn(msg: str):  _log(WARN, msg)

def log_error(msg: str):
    _log(ERROR, msg)
    return False

def log_fatal(msg: str):
    _log(FATAL, msg)
    sys.exit(1)

def log_success(msg: str):
    if LOG_NO_COLOR:
        log_info(f"✓ {msg}")
    else:
        sys.stdout.write(f"{COLOR_GREEN}✓ {msg}{COLOR_RESET}\n")
        sys.stdout.flush()

def log_failure(msg: str):
    if LOG_NO_COLOR:
        log_error(f"✗ {msg}")
    else:
        sys.stderr.write(f"{COLOR_RED}✗ {msg}{COLOR_RESET}\n")
        sys.stderr.flush()

def log_section(title: str):
    """Log section header matching log_section in logging.sh."""
    print()
    log_info("───────────────────────────────────────────────────────────────")
    log_info(title)
    log_info("───────────────────────────────────────────────────────────────")
