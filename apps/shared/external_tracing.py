"""External service tracing instrumentation for distributed tracing.

Provides decorators and utilities for tracing calls to external services:
- GitHub API
- Google Cloud Platform (GCP)
- External databases
- Third-party webhooks

Automatically captures:
- Service name and endpoint
- Request and response metadata
- Error status and messages
- Performance metrics (latency)
- Span correlation for multi-hop requests

Usage:
    from apps.shared.external_tracing import trace_external_call, GitHubTracer

    tracer = GitHubTracer(base_url="https://api.github.com")
    
    @trace_external_call(tracer, "github.get_repo")
    async def fetch_repo(owner: str, repo: str):
        # Call GitHub API
        return await tracer.get(f"/repos/{owner}/{repo}")
"""

from __future__ import annotations

import functools
import inspect
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional
from abc import ABC, abstractmethod


@dataclass
class ExternalCallSpan:
    """Span for external service call."""

    service: str
    operation: str
    endpoint: str
    method: str = "GET"
    start_time: float = 0.0
    end_time: Optional[float] = None
    status_code: Optional[int] = None
    error: Optional[str] = None
    request_size: int = 0
    response_size: int = 0
    attributes: Dict[str, Any] = None

    def __post_init__(self):
        if self.start_time == 0.0:
            self.start_time = time.time()
        if self.attributes is None:
            self.attributes = {}

    @property
    def duration_ms(self) -> float:
        """Duration in milliseconds."""
        end = self.end_time or time.time()
        return (end - self.start_time) * 1000

    @property
    def status(self) -> str:
        """Span status based on error/status code."""
        if self.error:
            return "ERROR"
        if self.status_code and 400 <= self.status_code < 500:
            return "ERROR"
        if self.status_code and self.status_code >= 500:
            return "ERROR"
        return "OK"

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for logging/tracing."""
        return {
            "service": self.service,
            "operation": self.operation,
            "endpoint": self.endpoint,
            "method": self.method,
            "status": self.status,
            "status_code": self.status_code,
            "duration_ms": self.duration_ms,
            "request_size": self.request_size,
            "response_size": self.response_size,
            "error": self.error,
            "attributes": self.attributes,
        }


class ExternalServiceTracer(ABC):
    """Base class for external service tracers."""

    def __init__(self, service_name: str, base_url: str):
        self.service_name = service_name
        self.base_url = base_url
        self.spans: List[ExternalCallSpan] = []

    @abstractmethod
    async def get(self, endpoint: str, **kwargs) -> Any:
        """Make GET request."""
        pass

    @abstractmethod
    async def post(self, endpoint: str, data: Any = None, **kwargs) -> Any:
        """Make POST request."""
        pass

    def record_span(self, span: ExternalCallSpan) -> None:
        """Record an external call span."""
        span.end_time = time.time()
        self.spans.append(span)

    def get_spans(self) -> List[ExternalCallSpan]:
        """Get all recorded spans."""
        return self.spans.copy()

    def export_spans(self) -> List[Dict[str, Any]]:
        """Export spans for Jaeger/backend."""
        return [span.to_dict() for span in self.spans]

    def clear_spans(self) -> None:
        """Clear recorded spans."""
        self.spans.clear()


class GitHubTracer(ExternalServiceTracer):
    """Tracer for GitHub API calls."""

    def __init__(
        self,
        base_url: str = "https://api.github.com",
        token: Optional[str] = None,
    ):
        super().__init__("github", base_url)
        self.token = token
        self.headers = {"Accept": "application/vnd.github.v3+json"}
        if token:
            self.headers["Authorization"] = f"token {token}"

    async def get(self, endpoint: str, **kwargs) -> Any:
        """Make GitHub API GET request."""
        span = ExternalCallSpan(
            service=self.service_name,
            operation=f"github.{endpoint.split('/')[1] if '/' in endpoint else 'unknown'}",
            endpoint=endpoint,
            method="GET",
        )

        try:
            # Simulate API call with tracing
            url = f"{self.base_url}{endpoint}"
            span.attributes["url"] = url
            span.attributes["headers_set"] = len(self.headers)

            # In real implementation, would use aiohttp/httpx here
            # For now, return mock response with span recording
            span.status_code = 200
            span.response_size = 1024  # Mock response size
            return {"_span": span, "status": "ok"}

        except Exception as e:
            span.error = str(e)
            raise
        finally:
            self.record_span(span)

    async def post(self, endpoint: str, data: Any = None, **kwargs) -> Any:
        """Make GitHub API POST request."""
        span = ExternalCallSpan(
            service=self.service_name,
            operation=f"github.{endpoint.split('/')[1] if '/' in endpoint else 'unknown'}",
            endpoint=endpoint,
            method="POST",
        )

        try:
            url = f"{self.base_url}{endpoint}"
            span.attributes["url"] = url
            span.attributes["headers_set"] = len(self.headers)
            span.request_size = len(str(data)) if data else 0

            # In real implementation, would use aiohttp/httpx here
            span.status_code = 201
            span.response_size = 512
            return {"_span": span, "status": "created"}

        except Exception as e:
            span.error = str(e)
            raise
        finally:
            self.record_span(span)


class GCPTracer(ExternalServiceTracer):
    """Tracer for Google Cloud Platform service calls."""

    def __init__(
        self,
        project_id: str,
        service: str = "generic",
        credentials_path: Optional[str] = None,
    ):
        super().__init__(f"gcp-{service}", f"https://googleapis.com")
        self.project_id = project_id
        self.service = service
        self.credentials_path = credentials_path

    async def get(self, endpoint: str, **kwargs) -> Any:
        """Make GCP API GET request."""
        span = ExternalCallSpan(
            service=self.service_name,
            operation=f"gcp.{self.service}.get",
            endpoint=endpoint,
            method="GET",
        )

        try:
            span.attributes["project_id"] = self.project_id
            span.attributes["gcp_service"] = self.service
            # In real implementation, would use google-cloud-* libraries
            span.status_code = 200
            span.response_size = 2048
            return {"_span": span, "status": "ok"}

        except Exception as e:
            span.error = str(e)
            raise
        finally:
            self.record_span(span)

    async def post(self, endpoint: str, data: Any = None, **kwargs) -> Any:
        """Make GCP API POST request."""
        span = ExternalCallSpan(
            service=self.service_name,
            operation=f"gcp.{self.service}.create",
            endpoint=endpoint,
            method="POST",
        )

        try:
            span.attributes["project_id"] = self.project_id
            span.attributes["gcp_service"] = self.service
            span.request_size = len(str(data)) if data else 0
            # In real implementation, would use google-cloud-* libraries
            span.status_code = 200
            span.response_size = 1024
            return {"_span": span, "status": "created"}

        except Exception as e:
            span.error = str(e)
            raise
        finally:
            self.record_span(span)


def trace_external_call(
    tracer: ExternalServiceTracer,
    operation_name: str,
    capture_response: bool = False,
):
    """Decorator for tracing external service calls.

    Args:
        tracer: ExternalServiceTracer instance
        operation_name: Name of the operation (e.g., "github.get_repo")
        capture_response: Whether to capture response in span attributes

    Example:
        @trace_external_call(github_tracer, "github.get_repo")
        async def fetch_repo(owner: str, repo: str):
            return await github_tracer.get(f"/repos/{owner}/{repo}")
    """

    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        async def async_wrapper(*args, **kwargs) -> Any:
            result = await func(*args, **kwargs)

            # Extract span from result if present
            if isinstance(result, dict) and "_span" in result:
                span = result.pop("_span")
                if capture_response:
                    span.attributes["response_type"] = type(result).__name__
                span.attributes["operation"] = operation_name
            return result

        @functools.wraps(func)
        def sync_wrapper(*args, **kwargs) -> Any:
            result = func(*args, **kwargs)

            # Extract span from result if present
            if isinstance(result, dict) and "_span" in result:
                span = result.pop("_span")
                if capture_response:
                    span.attributes["response_type"] = type(result).__name__
                span.attributes["operation"] = operation_name
            return result

        if inspect.iscoroutinefunction(func):
            return async_wrapper
        return sync_wrapper

    return decorator


__all__ = [
    "ExternalCallSpan",
    "ExternalServiceTracer",
    "GitHubTracer",
    "GCPTracer",
    "trace_external_call",
]
