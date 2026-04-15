#!/usr/bin/env python3
"""
Telemetry Logger Module (Python)

Enforces structured logging schema per TELEMETRY-ARCHITECTURE.md

Usage:
    from telemetry_logger import create_logger
    logger = create_logger(service='git-proxy', environment='production')
    logger.info('Request received', trace_id=trace_id, request_path='/clone')
"""

import json
import logging
import os
import uuid
import hashlib
from datetime import datetime
from functools import wraps
from typing import Optional, Dict, Any


def generate_uuid() -> str:
    """Generates a UUID v4 string"""
    return str(uuid.uuid4())


def hash_user_id(user_id: Optional[str]) -> Optional[str]:
    """Hashes a user ID (SHA-256) for privacy-safe correlation"""
    if not user_id:
        return None
    return hashlib.sha256(str(user_id).encode()).hexdigest()


def generate_error_fingerprint(error: Optional[Exception]) -> str:
    """Generates deterministic error fingerprint for grouping similar errors"""
    if not error:
        return ''
    
    message = str(getattr(error, 'message', str(error)))
    # Try to get stack trace
    stack = ''
    import traceback
    try:
        stack = traceback.format_exc().split('\n')[0]
    except:
        pass
    
    fingerprint = f"{message}|{stack}"[:100]
    return hashlib.sha256(fingerprint.encode()).hexdigest()[:16]


class StructuredLogHandler(logging.Handler):
    """Custom logging handler that outputs JSON in telemetry schema"""
    
    def __init__(self, config: Dict[str, str]):
        super().__init__()
        self.config = config
    
    def emit(self, record: logging.LogRecord):
        """Emit a log record as JSON"""
        try:
            log_data = {
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'level': record.levelname.lower(),
                'service': self.config.get('service', 'unknown'),
                'region': self.config.get('region', 'unknown'),
                'host': self.config.get('host', 'unknown'),
                'environment': self.config.get('environment', 'unknown'),
                'trace_id': getattr(record, 'trace_id', generate_uuid()),
                'span_id': getattr(record, 'span_id', None),
                'request_id': getattr(record, 'request_id', None),
                'request_path': getattr(record, 'request_path', None),
                'request_method': getattr(record, 'request_method', None),
                'user_id_hash': getattr(record, 'user_id_hash', None),
                'session_id': getattr(record, 'session_id', None),
                'status_code': getattr(record, 'status_code', None),
                'duration_ms': getattr(record, 'duration_ms', None),
                'message': record.getMessage(),
                'error_fingerprint': getattr(record, 'error_fingerprint', ''),
                'context': getattr(record, 'context', {})
            }
            
            # Remove None values to keep JSON clean
            log_data = {k: v for k, v in log_data.items() if v is not None}
            
            print(json.dumps(log_data))
        except Exception:
            self.handleError(record)


def create_logger(
    service: str = 'unknown',
    region: Optional[str] = None,
    environment: Optional[str] = None,
    host: Optional[str] = None
) -> logging.Logger:
    """
    Creates a logger instance bound to a service/environment
    
    Args:
        service: Service name (code-server, git-proxy, oauth2-proxy, caddy)
        region: Deployment region (defaults to REGION env var)
        environment: Environment name (defaults to ENV or FLASK_ENV)
        host: Hostname (defaults to socket.gethostname())
    
    Returns:
        Logger instance configured for structured logging
    """
    import socket
    
    region = region or os.getenv('REGION', 'unknown')
    environment = environment or os.getenv('ENV') or os.getenv('FLASK_ENV', 'development')
    host = host or socket.gethostname()
    
    config = {
        'service': service,
        'region': region,
        'environment': environment,
        'host': host
    }
    
    logger = logging.getLogger(service)
    logger.setLevel(logging.DEBUG)
    
    # Remove existing handlers
    logger.handlers = []
    
    # Add structured JSON handler
    handler = StructuredLogHandler(config)
    handler.setFormatter(logging.Formatter('%(message)s'))
    logger.addHandler(handler)
    
    return logger


def telemetry_decorator(logger: logging.Logger):
    """
    Flask/Django view decorator to automatically capture telemetry
    
    Usage:
        @app.before_request
        def inject_trace():
            g.trace_id = request.headers.get('x-trace-id', generate_uuid())
        
        @app.route('/api/endpoint')
        @telemetry_decorator(logger)
        def my_endpoint():
            return {'status': 'ok'}
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            import time
            import traceback
            from flask import request, g
            
            trace_id = getattr(g, 'trace_id', generate_uuid())
            request_id = getattr(g, 'request_id', generate_uuid())
            start_time = time.time()
            
            try:
                # Log request
                extra = {
                    'trace_id': trace_id,
                    'request_id': request_id,
                    'request_method': request.method,
                    'request_path': request.path
                }
                logger.info('Request started', extra=extra)
                
                # Execute handler
                result = f(*args, **kwargs)
                
                # Log response
                duration_ms = int((time.time() - start_time) * 1000)
                extra['duration_ms'] = duration_ms
                extra['status_code'] = 200
                logger.info('Request completed', extra=extra)
                
                return result
            except Exception as e:
                duration_ms = int((time.time() - start_time) * 1000)
                error_fp = generate_error_fingerprint(e)
                extra = {
                    'trace_id': trace_id,
                    'request_id': request_id,
                    'request_method': request.method,
                    'request_path': request.path,
                    'duration_ms': duration_ms,
                    'error_fingerprint': error_fp,
                    'status_code': 500
                }
                logger.error(f'Request failed: {str(e)}', extra=extra)
                raise
        
        return decorated_function
    return decorator


# Example usage for standalone scripts
if __name__ == '__main__':
    logger = create_logger(
        service='example',
        environment='development'
    )
    
    trace_id = generate_uuid()
    
    # Log examples
    logger.info('Service started', extra={
        'trace_id': trace_id,
        'context': {'port': 8000}
    })
    
    logger.debug('Debug info', extra={
        'trace_id': trace_id,
        'context': {'debug_key': 'debug_value'}
    })
    
    try:
        raise ValueError('Example error')
    except Exception as e:
        logger.error('Operation failed', extra={
            'trace_id': trace_id,
            'error_fingerprint': generate_error_fingerprint(e)
        })
