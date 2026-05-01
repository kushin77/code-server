"""Integration bridge between advanced tracing patterns and existing OpenTelemetry setup.

Extends the existing hermes_tracing module with:
- Trace sampling strategies
- W3C Trace Context propagation
- Context baggage handling
- Performance profiling integration

Works alongside existing OpenTelemetry instrumentation, adding advanced
capabilities for sampling, context management, and profiling.
"""

from __future__ import annotations

from typing import Any, Callable, Dict, Optional
from functools import wraps
import inspect

from apps.shared.advanced_tracing import (
    AdvancedTracingConfig,
    AdvancedTracer,
    get_advanced_tracer,
)
from apps.shared.trace_patterns import (
    TraceSamplingConfig,
    SamplingStrategy,
    W3CTraceContext,
    ContextBaggage,
)


class TraceEnhancer:
    """Enhances existing OpenTelemetry tracing with advanced patterns."""

    def __init__(self, advanced_tracer: AdvancedTracer):
        """Initialize trace enhancer.

        Args:
            advanced_tracer: AdvancedTracer instance
        """
        self.tracer = advanced_tracer

    def wrap_service_call(
        self,
        service_name: str,
        operation_name: str,
        propagate_context: bool = True,
    ) -> Callable:
        """Decorator for wrapping service calls with advanced tracing.

        Args:
            service_name: Name of remote service
            operation_name: Operation being performed
            propagate_context: Whether to propagate context headers

        Returns:
            Decorated function
        """

        def decorator(func: Callable) -> Callable:
            if inspect.iscoroutinefunction(func):

                @wraps(func)
                async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
                    # Get propagation headers if needed
                    headers = {}
                    if propagate_context:
                        headers = self.tracer.get_propagation_headers()

                    # Merge with existing headers in kwargs
                    if "headers" in kwargs:
                        if isinstance(kwargs["headers"], dict):
                            kwargs["headers"].update(headers)
                    else:
                        kwargs["headers"] = headers

                    # Call wrapped function
                    return await func(*args, **kwargs)

                return async_wrapper
            else:

                @wraps(func)
                def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
                    # Get propagation headers if needed
                    headers = {}
                    if propagate_context:
                        headers = self.tracer.get_propagation_headers()

                    # Merge with existing headers in kwargs
                    if "headers" in kwargs:
                        if isinstance(kwargs["headers"], dict):
                            kwargs["headers"].update(headers)
                    else:
                        kwargs["headers"] = headers

                    # Call wrapped function
                    return func(*args, **kwargs)

                return sync_wrapper

        return decorator

    def setup_sampling_for_request(
        self,
        path: str,
        headers: Optional[Dict[str, str]] = None,
    ) -> bool:
        """Set up sampling for incoming request.

        Args:
            path: Request path
            headers: Request headers

        Returns:
            Whether request should be traced
        """
        headers = headers or {}

        # Extract debug header
        debug_header = headers.get("X-Debug-Trace") or headers.get("x-debug-trace")

        # Get sampling decision
        should_sample = self.tracer.should_sample(path, debug_header)

        if should_sample:
            # Extract trace context and baggage from request
            context = self.tracer.extract_trace_context(headers)
            baggage = self.tracer.extract_baggage(headers)

            # If no existing context, create new one
            if not context:
                import uuid
                trace_id = uuid.uuid4().hex
                parent_id = uuid.uuid4().hex[:16]
                context = self.tracer.create_trace_context(trace_id, parent_id)

            # Start trace
            self.tracer.context_manager.set_trace_context(context)
            self.tracer.context_manager.set_baggage(baggage)

        return should_sample

    def get_request_trace_headers(self) -> Dict[str, str]:
        """Get headers to include in outgoing requests.

        Returns:
            Dictionary of headers for trace propagation
        """
        return self.tracer.get_propagation_headers()

    def end_request_trace(self) -> None:
        """End the request trace."""
        self.tracer.end_trace()


# Global trace enhancer instance
_trace_enhancer: Optional[TraceEnhancer] = None


def initialize_trace_enhancement(
    sampling_config: Optional[TraceSamplingConfig] = None,
) -> TraceEnhancer:
    """Initialize trace enhancement.

    Args:
        sampling_config: Optional custom sampling configuration

    Returns:
        Initialized TraceEnhancer
    """
    global _trace_enhancer

    # Get or create advanced tracer
    adv_tracer = get_advanced_tracer()

    if sampling_config:
        # Reinitialize with custom config
        from apps.shared.advanced_tracing import AdvancedTracingConfig, initialize_advanced_tracing
        config = AdvancedTracingConfig(sampling_config=sampling_config)
        adv_tracer = initialize_advanced_tracing(config)

    _trace_enhancer = TraceEnhancer(adv_tracer)
    return _trace_enhancer


def get_trace_enhancer() -> TraceEnhancer:
    """Get global trace enhancer."""
    global _trace_enhancer

    if _trace_enhancer is None:
        initialize_trace_enhancement()

    return _trace_enhancer


# Convenience functions
def wrap_service_call(
    service_name: str,
    operation_name: str,
) -> Callable:
    """Convenient decorator for service calls.

    Args:
        service_name: Name of service
        operation_name: Operation name

    Returns:
        Decorated function
    """
    enhancer = get_trace_enhancer()
    return enhancer.wrap_service_call(service_name, operation_name)


def setup_request_sampling(
    path: str,
    headers: Optional[Dict[str, str]] = None,
) -> bool:
    """Set up sampling for request.

    Args:
        path: Request path
        headers: Request headers

    Returns:
        Whether to trace
    """
    enhancer = get_trace_enhancer()
    return enhancer.setup_sampling_for_request(path, headers)


def get_outbound_trace_headers() -> Dict[str, str]:
    """Get headers for outbound calls.

    Returns:
        Propagation headers
    """
    enhancer = get_trace_enhancer()
    return enhancer.get_request_trace_headers()


def end_request_trace() -> None:
    """End current request trace."""
    enhancer = get_trace_enhancer()
    enhancer.end_request_trace()


__all__ = [
    "TraceEnhancer",
    "initialize_trace_enhancement",
    "get_trace_enhancer",
    "wrap_service_call",
    "setup_request_sampling",
    "get_outbound_trace_headers",
    "end_request_trace",
]
