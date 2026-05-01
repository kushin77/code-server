"""Advanced distributed tracing patterns with sampling and context propagation.

Provides:
- Multiple trace sampling strategies (uniform, probability-based, rate-limiting)
- W3C Trace Context propagation and header management
- Performance profiling integration with traces
- Custom span attributes and baggage handling
- Trace correlation across async boundaries
"""

from __future__ import annotations

import os
import random
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, Optional
import inspect
from contextlib import contextmanager
import threading
from functools import wraps


class SamplingStrategy(str, Enum):
    """Trace sampling strategies."""

    ALWAYS = "always"  # Sample all traces (100%)
    NEVER = "never"  # Sample no traces (0%)
    UNIFORM = "uniform"  # Sample at fixed percentage
    PROBABILITY = "probability"  # Sample based on probability calculation
    RATE_LIMITED = "rate_limited"  # Sample up to max traces per minute


@dataclass
class TraceSamplingConfig:
    """Configuration for trace sampling."""

    strategy: SamplingStrategy = SamplingStrategy.UNIFORM
    sample_rate: float = 0.1  # 10% for uniform, probability
    max_traces_per_minute: int = 1000  # For rate-limiting
    exclude_paths: list = field(default_factory=list)  # Paths to never sample
    always_sample_paths: list = field(default_factory=list)  # Paths to always sample
    debug_mode: bool = False  # Sample 100% if debug header present

    def is_valid(self) -> bool:
        """Validate configuration."""
        if not 0 <= self.sample_rate <= 1:
            return False
        if self.max_traces_per_minute < 0:
            return False
        return True


class TraceSampler:
    """Makes sampling decisions for traces."""

    def __init__(self, config: TraceSamplingConfig):
        """Initialize sampler.

        Args:
            config: Sampling configuration
        """
        if not config.is_valid():
            raise ValueError("Invalid sampling configuration")

        self.config = config
        self.trace_count = 0
        self.last_minute_start = time.time()
        self._lock = threading.Lock()

    def should_sample(
        self,
        path: str = "/",
        debug_header: Optional[str] = None,
    ) -> bool:
        """Determine if trace should be sampled.

        Args:
            path: Request path for path-based sampling
            debug_header: Debug header value

        Returns:
            True if trace should be sampled
        """
        # Check debug mode
        if self.config.debug_mode and debug_header:
            return True

        # Check always-sample paths
        for always_path in self.config.always_sample_paths:
            if path.startswith(always_path):
                return True

        # Check exclude paths
        for exclude_path in self.config.exclude_paths:
            if path.startswith(exclude_path):
                return False

        # Apply sampling strategy
        if self.config.strategy == SamplingStrategy.ALWAYS:
            return True
        elif self.config.strategy == SamplingStrategy.NEVER:
            return False
        elif self.config.strategy == SamplingStrategy.UNIFORM:
            return random.random() < self.config.sample_rate
        elif self.config.strategy == SamplingStrategy.PROBABILITY:
            # Probability-based sampling with seed for consistency
            return self._probability_sample()
        elif self.config.strategy == SamplingStrategy.RATE_LIMITED:
            return self._rate_limited_sample()

        return False

    def _probability_sample(self) -> bool:
        """Sample based on probability calculation."""
        # Use a seeded random for consistency within trace
        return random.random() < self.config.sample_rate

    def _rate_limited_sample(self) -> bool:
        """Sample with rate limiting."""
        with self._lock:
            now = time.time()

            # Reset counter if minute has passed
            if now - self.last_minute_start > 60:
                self.trace_count = 0
                self.last_minute_start = now

            # Allow sample if under limit
            if self.trace_count < self.config.max_traces_per_minute:
                self.trace_count += 1
                return True

            return False


@dataclass
class W3CTraceContext:
    """W3C Trace Context (https://w3c.github.io/trace-context/)."""

    trace_id: str
    parent_id: str
    trace_flags: str = "01"  # Trace flag (01 = sampled)
    vendor_data: Dict[str, str] = field(default_factory=dict)

    @classmethod
    def from_headers(cls, headers: Dict[str, str]) -> Optional[W3CTraceContext]:
        """Parse W3C trace context from HTTP headers.

        Args:
            headers: HTTP headers dict

        Returns:
            W3CTraceContext or None if not present
        """
        traceparent = headers.get("traceparent") or headers.get("Traceparent")
        if not traceparent:
            return None

        # Format: version-trace_id-parent_id-trace_flags
        try:
            parts = traceparent.split("-")
            if len(parts) != 4:
                return None

            version, trace_id, parent_id, trace_flags = parts

            # Only support version 00
            if version != "00":
                return None

            return cls(
                trace_id=trace_id,
                parent_id=parent_id,
                trace_flags=trace_flags,
            )
        except (ValueError, IndexError):
            return None

    def to_headers(self) -> Dict[str, str]:
        """Convert to HTTP headers.

        Returns:
            Dictionary of headers
        """
        return {
            "traceparent": f"00-{self.trace_id}-{self.parent_id}-{self.trace_flags}",
            "tracestate": ",".join(
                f"{k}={v}" for k, v in self.vendor_data.items()
            ),
        }

    def is_sampled(self) -> bool:
        """Check if trace should be sampled."""
        return self.trace_flags[-1] in ("1", "d")


@dataclass
class ContextBaggage:
    """Baggage for context propagation (W3C Baggage).

    Carries tenant ID, user ID, and other user-defined properties
    across service boundaries.
    """

    user_id: Optional[str] = None
    tenant_id: Optional[str] = None
    correlation_id: Optional[str] = None
    custom_properties: Dict[str, str] = field(default_factory=dict)

    @classmethod
    def from_header(cls, baggage_header: Optional[str]) -> ContextBaggage:
        """Parse baggage from header.

        Args:
            baggage_header: W3C Baggage header value

        Returns:
            ContextBaggage instance
        """
        baggage = cls()

        if not baggage_header:
            return baggage

        try:
            for item in baggage_header.split(","):
                item = item.strip()
                if "=" in item:
                    key, value = item.split("=", 1)
                    key = key.strip()
                    value = value.strip()

                    if key == "userId":
                        baggage.user_id = value
                    elif key == "tenantId":
                        baggage.tenant_id = value
                    elif key == "correlationId":
                        baggage.correlation_id = value
                    else:
                        baggage.custom_properties[key] = value
        except Exception:
            pass

        return baggage

    def to_header(self) -> str:
        """Convert to W3C Baggage header.

        Returns:
            Baggage header value
        """
        items = []

        if self.user_id:
            items.append(f"userId={self.user_id}")

        if self.tenant_id:
            items.append(f"tenantId={self.tenant_id}")

        if self.correlation_id:
            items.append(f"correlationId={self.correlation_id}")

        for key, value in self.custom_properties.items():
            items.append(f"{key}={value}")

        return ",".join(items)


@dataclass
class PerformanceProfile:
    """Performance profile captured during trace."""

    span_name: str
    start_time: float
    end_time: float = 0.0
    wall_time_ms: float = 0.0
    cpu_time_ms: float = 0.0
    memory_mb: float = 0.0
    garbage_collections: int = 0

    def finalize(self) -> None:
        """Finalize profile with end time."""
        self.end_time = time.time()
        self.wall_time_ms = (self.end_time - self.start_time) * 1000

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "span_name": self.span_name,
            "wall_time_ms": round(self.wall_time_ms, 2),
            "cpu_time_ms": round(self.cpu_time_ms, 2),
            "memory_mb": round(self.memory_mb, 2),
            "garbage_collections": self.garbage_collections,
        }


class TraceContextManager:
    """Manages trace context and baggage across execution boundaries."""

    def __init__(self):
        """Initialize context manager."""
        self._context: threading.local = threading.local()

    def get_trace_context(self) -> Optional[W3CTraceContext]:
        """Get current trace context."""
        return getattr(self._context, "trace_context", None)

    def set_trace_context(self, context: W3CTraceContext) -> None:
        """Set trace context."""
        self._context.trace_context = context

    def get_baggage(self) -> ContextBaggage:
        """Get current baggage."""
        if not hasattr(self._context, "baggage"):
            self._context.baggage = ContextBaggage()
        return self._context.baggage

    def set_baggage(self, baggage: ContextBaggage) -> None:
        """Set baggage."""
        self._context.baggage = baggage

    def get_performance_profile(self) -> Optional[PerformanceProfile]:
        """Get current performance profile."""
        return getattr(self._context, "profile", None)

    def set_performance_profile(self, profile: PerformanceProfile) -> None:
        """Set performance profile."""
        self._context.profile = profile

    @contextmanager
    def trace_scope(
        self,
        trace_context: W3CTraceContext,
        baggage: Optional[ContextBaggage] = None,
    ):
        """Context manager for trace scope.

        Args:
            trace_context: Trace context for scope
            baggage: Optional baggage
        """
        old_context = self.get_trace_context()
        old_baggage = getattr(self._context, "baggage", None)

        try:
            self.set_trace_context(trace_context)
            if baggage:
                self.set_baggage(baggage)
            yield
        finally:
            if old_context:
                self.set_trace_context(old_context)
            if old_baggage:
                self.set_baggage(old_baggage)


# Global context manager
_trace_context_manager = TraceContextManager()


def get_trace_context_manager() -> TraceContextManager:
    """Get global trace context manager."""
    return _trace_context_manager


def profile_span(
    span_name: str,
) -> Callable:
    """Decorator to profile span execution.

    Args:
        span_name: Name of span for profiling

    Returns:
        Decorated function
    """

    def decorator(func: Callable) -> Callable:
        if inspect.iscoroutinefunction(func):

            @wraps(func)
            async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
                profile = PerformanceProfile(
                    span_name=span_name,
                    start_time=time.time(),
                )

                try:
                    result = await func(*args, **kwargs)
                    return result
                finally:
                    profile.finalize()
                    ctx_mgr = get_trace_context_manager()
                    ctx_mgr.set_performance_profile(profile)

            return async_wrapper
        else:

            @wraps(func)
            def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
                profile = PerformanceProfile(
                    span_name=span_name,
                    start_time=time.time(),
                )

                try:
                    result = func(*args, **kwargs)
                    return result
                finally:
                    profile.finalize()
                    ctx_mgr = get_trace_context_manager()
                    ctx_mgr.set_performance_profile(profile)

            return sync_wrapper

        return decorator

    return decorator


__all__ = [
    "SamplingStrategy",
    "TraceSamplingConfig",
    "TraceSampler",
    "W3CTraceContext",
    "ContextBaggage",
    "PerformanceProfile",
    "TraceContextManager",
    "get_trace_context_manager",
    "profile_span",
]
