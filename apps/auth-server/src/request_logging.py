"""
Request Logging and Monitoring Middleware
Issue #1545: Enterprise SSO Portal - Request Logging & Monitoring
"""
import json
import time
from typing import Optional, Dict, Any
from datetime import datetime

from log import get_logger
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response


logger = get_logger(__name__)


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """
    Middleware for comprehensive request logging and monitoring.
    
    Logs:
    - Request method, path, query parameters
    - Response status code and latency
    - Request/response sizes
    - User ID (if available)
    - Error details on failures
    """
    
    def __init__(self, app, log_format: str = "json"):
        """
        Initialize request logging middleware.
        
        Args:
            app: FastAPI application
            log_format: Log format ("json" or "text")
        """
        super().__init__(app)
        self.log_format = log_format
    
    async def dispatch(self, request: Request, call_next) -> Response:
        """
        Process request and log details.
        """
        # Record request start time
        start_time = time.time()
        request_body_size = 0
        user_id = None
        
        # Extract user ID from request state if available
        try:
            user_id = getattr(request.state, "user_id", None)
        except Exception:
            pass
        
        # Try to get request body size
        try:
            if request.method in ["POST", "PUT", "PATCH"]:
                request_body_size = len(await request.body())
                # Reset body for endpoint to read it
                async def receive():
                    return {"type": "http.request", "body": request._body}
                request._receive = receive
        except Exception:
            pass
        
        # Call the actual endpoint
        response = await call_next(request)
        
        # Record end time and calculate latency
        end_time = time.time()
        latency_ms = (end_time - start_time) * 1000
        
        # Try to get response body size
        response_body_size = 0
        if hasattr(response, "body"):
            response_body_size = len(response.body)
        
        # Prepare log data
        log_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "request": {
                "method": request.method,
                "path": request.url.path,
                "query_params": dict(request.query_params) if request.query_params else None,
                "size_bytes": request_body_size,
            },
            "response": {
                "status_code": response.status_code,
                "size_bytes": response_body_size,
            },
            "latency_ms": round(latency_ms, 2),
            "client_ip": request.client.host if request.client else None,
            "user_id": user_id,
        }
        
        # Log in configured format
        if self.log_format == "json":
            logger.info(json.dumps(log_data))
        else:
            self._log_text_format(log_data)
        
        return response
    
    def _log_text_format(self, log_data: Dict[str, Any]) -> None:
        """Log in human-readable text format."""
        request_info = log_data["request"]
        response_info = log_data["response"]
        latency = log_data["latency_ms"]
        
        query_str = ""
        if request_info["query_params"]:
            query_str = f"?{self._dict_to_query_string(request_info['query_params'])}"
        
        log_msg = (
            f"{request_info['method']} {request_info['path']}{query_str} "
            f"→ {response_info['status_code']} ({latency}ms) "
            f"[{request_info['size_bytes']}B → {response_info['size_bytes']}B]"
        )
        
        if log_data.get("user_id"):
            log_msg += f" [user={log_data['user_id']}]"
        
        logger.info(log_msg)
    
    @staticmethod
    def _dict_to_query_string(params: Dict[str, Any]) -> str:
        """Convert dict to query string."""
        if not params:
            return ""
        pairs = []
        for key, value in params.items():
            if isinstance(value, list):
                for v in value:
                    pairs.append(f"{key}={v}")
            else:
                pairs.append(f"{key}={value}")
        return "&".join(pairs)


class RequestMonitoringMiddleware(BaseHTTPMiddleware):
    """
    Middleware for request monitoring and metrics.
    
    Tracks:
    - Request counts by endpoint
    - Error rates
    - Response time statistics
    """
    
    def __init__(self, app):
        """Initialize monitoring middleware."""
        super().__init__(app)
        self.metrics = {
            "total_requests": 0,
            "total_errors": 0,
            "endpoints": {},
        }
    
    async def dispatch(self, request: Request, call_next) -> Response:
        """
        Process request and update metrics.
        """
        # Update total request count
        self.metrics["total_requests"] += 1
        
        # Track by endpoint
        endpoint = f"{request.method} {request.url.path}"
        if endpoint not in self.metrics["endpoints"]:
            self.metrics["endpoints"][endpoint] = {
                "count": 0,
                "errors": 0,
                "total_latency_ms": 0,
            }
        
        start_time = time.time()
        response = await call_next(request)
        latency_ms = (time.time() - start_time) * 1000
        
        # Update endpoint metrics
        endpoint_metrics = self.metrics["endpoints"][endpoint]
        endpoint_metrics["count"] += 1
        endpoint_metrics["total_latency_ms"] += latency_ms
        
        # Track errors
        if response.status_code >= 400:
            self.metrics["total_errors"] += 1
            endpoint_metrics["errors"] += 1
        
        # Add metrics to response headers (optional)
        response.headers["X-Process-Time"] = str(round(latency_ms, 2))
        
        return response
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get current metrics."""
        return self.metrics.copy()


def setup_request_logging(app, config) -> None:
    """
    Setup request logging and monitoring for FastAPI app.
    
    Args:
        app: FastAPI application
        config: Configuration object with LOG_FORMAT setting
    """
    log_format = getattr(config, "LOG_FORMAT", "json")
    
    # Add request logging middleware
    app.add_middleware(
        RequestLoggingMiddleware,
        log_format=log_format,
    )
    
    # Add monitoring middleware
    app.add_middleware(RequestMonitoringMiddleware)
    
    logger.info(
        f"Request logging and monitoring enabled (format={log_format})"
    )
