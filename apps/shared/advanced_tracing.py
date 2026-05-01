"""Advanced tracing utilities integrating patterns, sampling, and profiling.

Provides unified interface for:
- Automatic trace sampling based on configuration
- W3C Trace Context propagation across services
- Baggage handling for user/tenant context
- Performance profiling of spans
- Trace header generation and parsing
"""

from __future__ import annotations

from typing import Any, Callable, Dict, Optional
from functools import wraps
import inspect

from apps.shared.trace_patterns import (
    TraceSamplingConfig,
    TraceSampler,
    W3CTraceContext,
    ContextBaggage,
    PerformanceProfile,
    TraceContextManager,
    SamplingStrategy,
    profile_span,
)


class AdvancedTracingConfig:
    """Configuration for advanced tracing."""

    def __init__(
        self,
        sampling_config: Optional[TraceSamplingConfig] = None,
        trace_context_manager: Optional[TraceContextManager] = None,
    ):
        """Initialize advanced tracing config.

        Args:
            sampling_config: Trace sampling configuration
            trace_context_manager: Context manager for traces
        """
        self.sampling_config = sampling_config or TraceSamplingConfig()
        self.trace_context_manager = trace_context_manager or TraceContextManager()
        self.sampler = TraceSampler(self.sampling_config)


class AdvancedTracer:
    """Advanced tracer with sampling, context propagation, and profiling."""

    def __init__(self, config: AdvancedTracingConfig):
        """Initialize advanced tracer.

        Args:
            config: Advanced tracing configuration
        """
        self.config = config
        self.sampling_config = config.sampling_config
        self.sampler = config.sampler
        self.context_manager = config.trace_context_manager

    def should_sample(
        self,
        path: str = "/",
        debug_header: Optional[str] = None,
    ) -> bool:
        """Check if request should be sampled.

        Args:
            path: Request path
            debug_header: Debug header value

        Returns:
            True if should be sampled
        """
        return self.sampler.should_sample(path, debug_header)

    def create_trace_context(
        self,
        trace_id: str,
        parent_id: str,
        trace_flags: str = "01",
    ) -> W3CTraceContext:
        """Create trace context.

        Args:
            trace_id: Trace ID
            parent_id: Parent span ID
            trace_flags: Trace flags

        Returns:
            W3CTraceContext
        """
        return W3CTraceContext(
            trace_id=trace_id,
            parent_id=parent_id,
            trace_flags=trace_flags,
        )

    def extract_trace_context(self, headers: Dict[str, str]) -> Optional[W3CTraceContext]:
        """Extract trace context from headers.

        Args:
            headers: HTTP headers

        Returns:
            W3CTraceContext or None
        """
        return W3CTraceContext.from_headers(headers)

    def extract_baggage(self, headers: Dict[str, str]) -> ContextBaggage:
        """Extract baggage from headers.

        Args:
            headers: HTTP headers

        Returns:
            ContextBaggage
        """
        baggage_header = headers.get("baggage") or headers.get("Baggage")
        return ContextBaggage.from_header(baggage_header)

    def get_propagation_headers(
        self,
        trace_context: Optional[W3CTraceContext] = None,
        baggage: Optional[ContextBaggage] = None,
    ) -> Dict[str, str]:
        """Get headers for propagating trace to downstream services.

        Args:
            trace_context: Trace context (or uses current)
            baggage: Baggage (or uses current)

        Returns:
            Dictionary of headers
        """
        headers = {}

        # Use provided context or get from manager
        context = trace_context or self.context_manager.get_trace_context()
        if context:
            headers.update(context.to_headers())

        # Use provided baggage or get from manager
        baggage = baggage or self.context_manager.get_baggage()
        if baggage:
            baggage_header = baggage.to_header()
            if baggage_header:
                headers["baggage"] = baggage_header

        return headers

    def start_trace(
        self,
        trace_id: str,
        parent_id: str,
        user_id: Optional[str] = None,
        tenant_id: Optional[str] = None,
        correlation_id: Optional[str] = None,
    ) -> W3CTraceContext:
        """Start a new trace.

        Args:
            trace_id: Trace ID
            parent_id: Parent span ID
            user_id: Optional user ID
            tenant_id: Optional tenant ID
            correlation_id: Optional correlation ID

        Returns:
            W3CTraceContext
        """
        context = self.create_trace_context(trace_id, parent_id)
        baggage = ContextBaggage(
            user_id=user_id,
            tenant_id=tenant_id,
            correlation_id=correlation_id,
        )

        self.context_manager.set_trace_context(context)
        self.context_manager.set_baggage(baggage)

        return context

    def end_trace(self) -> None:
        """End current trace."""
        self.context_manager.set_trace_context(None)
        self.context_manager.set_baggage(ContextBaggage())

    def get_current_profile(self) -> Optional[PerformanceProfile]:
        """Get current performance profile."""
        return self.context_manager.get_performance_profile()

    def trace_request(
        self,
        path: str = "/",
        debug_header: Optional[str] = None,
        profile: bool = True,
    ) -> Callable:
        """Decorator for tracing HTTP requests.

        Args:
            path: Request path for sampling
            debug_header: Debug header value
            profile: Whether to profile

        Returns:
            Decorated function
        """

        def decorator(func: Callable) -> Callable:
            if inspect.iscoroutinefunction(func):

                @wraps(func)
                async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
                    # Check if should sample
                    if not self.should_sample(path, debug_header):
                        return await func(*args, **kwargs)

                    # Extract trace context from request (if passed in kwargs)
                    headers = kwargs.get("headers", {})
                    context = self.extract_trace_context(headers)
                    baggage = self.extract_baggage(headers)

                    # Create new context if not present
                    if not context:
                        import uuid
                        trace_id = uuid.uuid4().hex
                        parent_id = uuid.uuid4().hex[:16]
                        context = self.create_trace_context(trace_id, parent_id)

                    # Optionally profile
                    profile_obj = None
                    if profile:
                        profile_obj = PerformanceProfile(
                            span_name=func.__name__,
                            start_time=__import__("time").time(),
                        )

                    try:
                        with self.context_manager.trace_scope(context, baggage):
                            result = await func(*args, **kwargs)
                            return result
                    finally:
                        if profile_obj:
                            profile_obj.finalize()
                            self.context_manager.set_performance_profile(profile_obj)

                return async_wrapper
            else:

                @wraps(func)
                def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
                    # Check if should sample
                    if not self.should_sample(path, debug_header):
                        return func(*args, **kwargs)

                    # Extract trace context from request
                    headers = kwargs.get("headers", {})
                    context = self.extract_trace_context(headers)
                    baggage = self.extract_baggage(headers)

                    # Create new context if not present
                    if not context:
                        import uuid
                        trace_id = uuid.uuid4().hex
                        parent_id = uuid.uuid4().hex[:16]
                        context = self.create_trace_context(trace_id, parent_id)

                    # Optionally profile
                    profile_obj = None
                    if profile:
                        profile_obj = PerformanceProfile(
                            span_name=func.__name__,
                            start_time=__import__("time").time(),
                        )

                    try:
                        with self.context_manager.trace_scope(context, baggage):
                            result = func(*args, **kwargs)
                            return result
                    finally:
                        if profile_obj:
                            profile_obj.finalize()
                            self.context_manager.set_performance_profile(profile_obj)

                return sync_wrapper

        return decorator


# Global advanced tracer instance
_advanced_tracer: Optional[AdvancedTracer] = None


def initialize_advanced_tracing(
    config: Optional[AdvancedTracingConfig] = None,
) -> AdvancedTracer:
    """Initialize global advanced tracer.

    Args:
        config: Configuration (uses defaults if not provided)

    Returns:
        Initialized AdvancedTracer
    """
    global _advanced_tracer

    if config is None:
        config = AdvancedTracingConfig()

    _advanced_tracer = AdvancedTracer(config)
    return _advanced_tracer


def get_advanced_tracer() -> AdvancedTracer:
    """Get global advanced tracer.

    Returns:
        AdvancedTracer instance
    """
    global _advanced_tracer

    if _advanced_tracer is None:
        initialize_advanced_tracing()

    return _advanced_tracer


__all__ = [
    "AdvancedTracingConfig",
    "AdvancedTracer",
    "initialize_advanced_tracing",
    "get_advanced_tracer",
]
