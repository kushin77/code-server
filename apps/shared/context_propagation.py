"""
Distributed Context Propagation System

Provides context management for distributed tracing across services:
- Correlation IDs for request tracking
- Baggage for metadata propagation
- Request context scopes
- Header propagation for W3C Trace Context and Jaeger standards
- Context extraction/injection for HTTP and messaging

This enables full end-to-end visibility of distributed requests.
"""

from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Any, Callable, Set, Tuple
from contextvars import ContextVar, copy_context
from enum import Enum
from datetime import datetime
from uuid import uuid4
import json
import base64
import re
from abc import ABC, abstractmethod
from threading import Lock


class ContextFormat(Enum):
    """Context header format standards."""
    W3C_TRACE_CONTEXT = "w3c"  # W3C standard
    JAEGER = "jaeger"  # Jaeger format
    B3 = "b3"  # B3 Propagation
    UBER_TRACE_ID = "uber"  # Uber format


@dataclass
class TraceIdentifiers:
    """Trace identity information."""
    trace_id: str
    span_id: str
    parent_span_id: Optional[str] = None
    trace_flags: int = 0x01  # sampled=1
    
    def to_dict(self) -> Dict[str, str]:
        """Convert to dictionary."""
        return asdict(self)
    
    @staticmethod
    def generate() -> 'TraceIdentifiers':
        """Generate new trace identifiers."""
        return TraceIdentifiers(
            trace_id=format(int.from_bytes(uuid4().bytes[:8], 'big'), '016x'),
            span_id=format(int.from_bytes(uuid4().bytes[:8], 'big'), '016x')
        )


@dataclass
class BaggageItem:
    """Individual baggage item with metadata."""
    key: str
    value: str
    properties: Dict[str, str] = field(default_factory=dict)
    timestamp: datetime = field(default_factory=datetime.utcnow)
    
    def to_header(self) -> str:
        """Convert to header format (W3C Baggage)."""
        header = f"{self.key}={self.value}"
        if self.properties:
            props = ";".join(f"{k}={v}" for k, v in self.properties.items())
            header += f";{props}"
        return header


@dataclass
class RequestBaggage:
    """Collection of baggage items for a request."""
    items: Dict[str, BaggageItem] = field(default_factory=dict)
    _lock: Lock = field(default_factory=Lock)
    
    def set(self, key: str, value: str, properties: Optional[Dict[str, str]] = None):
        """Set baggage item."""
        with self._lock:
            self.items[key] = BaggageItem(key, value, properties or {})
    
    def get(self, key: str) -> Optional[str]:
        """Get baggage item value."""
        with self._lock:
            return self.items.get(key, BaggageItem("", "")).value if key in self.items else None
    
    def all(self) -> Dict[str, str]:
        """Get all baggage items as key-value pairs."""
        with self._lock:
            return {k: v.value for k, v in self.items.items()}
    
    def to_header(self) -> str:
        """Convert to W3C Baggage header."""
        with self._lock:
            if not self.items:
                return ""
            headers = [item.to_header() for item in self.items.values()]
            return ",".join(headers)
    
    def from_header(self, header: str):
        """Parse from W3C Baggage header."""
        with self._lock:
            for part in header.split(","):
                part = part.strip()
                if "=" not in part:
                    continue
                
                # Split key=value and properties
                kv_part, *prop_parts = part.split(";")
                key, value = kv_part.split("=", 1)
                
                properties = {}
                for prop in prop_parts:
                    if "=" in prop:
                        pk, pv = prop.split("=", 1)
                        properties[pk.strip()] = pv.strip()
                
                self.set(key.strip(), value.strip(), properties)


@dataclass
class DistributedContext:
    """Complete distributed request context."""
    trace_ids: TraceIdentifiers
    request_id: str = field(default_factory=lambda: str(uuid4()))
    correlation_id: str = field(default_factory=lambda: str(uuid4()))
    baggage: RequestBaggage = field(default_factory=RequestBaggage)
    format: ContextFormat = ContextFormat.W3C_TRACE_CONTEXT
    user_id: Optional[str] = None
    tenant_id: Optional[str] = None
    service_name: str = ""
    created_at: datetime = field(default_factory=datetime.utcnow)
    sampling_rate: float = 1.0
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "trace_id": self.trace_ids.trace_id,
            "span_id": self.trace_ids.span_id,
            "parent_span_id": self.trace_ids.parent_span_id,
            "request_id": self.request_id,
            "correlation_id": self.correlation_id,
            "user_id": self.user_id,
            "tenant_id": self.tenant_id,
            "service_name": self.service_name,
            "created_at": self.created_at.isoformat(),
            "sampling_rate": self.sampling_rate,
        }


class ContextPropagator(ABC):
    """Abstract base for context propagation formats."""
    
    @abstractmethod
    def extract(self, carrier: Dict[str, str]) -> Optional[DistributedContext]:
        """Extract context from carrier (headers)."""
        pass
    
    @abstractmethod
    def inject(self, context: DistributedContext, carrier: Dict[str, str]):
        """Inject context into carrier (headers)."""
        pass


class W3CTracePropagator(ContextPropagator):
    """W3C Trace Context propagation."""
    
    TRACE_PARENT = "traceparent"
    TRACE_STATE = "tracestate"
    BAGGAGE = "baggage"
    
    def extract(self, carrier: Dict[str, str]) -> Optional[DistributedContext]:
        """Extract W3C trace context."""
        trace_parent = carrier.get(self.TRACE_PARENT)
        if not trace_parent:
            return None
        
        # Parse: version-trace_id-parent_id-trace_flags
        try:
            parts = trace_parent.split("-")
            if len(parts) < 4:
                return None
            
            version, trace_id, parent_id, flags = parts[0], parts[1], parts[2], parts[3]
            
            context = DistributedContext(
                trace_ids=TraceIdentifiers(
                    trace_id=trace_id,
                    span_id=parent_id,
                    parent_span_id=parent_id,
                    trace_flags=int(flags, 16)
                ),
                format=ContextFormat.W3C_TRACE_CONTEXT
            )
            
            # Extract baggage
            baggage_header = carrier.get(self.BAGGAGE)
            if baggage_header:
                context.baggage.from_header(baggage_header)
            
            return context
        except (ValueError, IndexError):
            return None
    
    def inject(self, context: DistributedContext, carrier: Dict[str, str]):
        """Inject W3C trace context."""
        # Create new span ID for this hop
        new_span_id = format(int.from_bytes(uuid4().bytes[:8], 'big'), '016x')
        
        trace_parent = (
            f"00-{context.trace_ids.trace_id}-{new_span_id}-"
            f"{context.trace_ids.trace_flags:02x}"
        )
        carrier[self.TRACE_PARENT] = trace_parent
        
        # Inject baggage
        if context.baggage.items:
            carrier[self.BAGGAGE] = context.baggage.to_header()


class JaegerPropagator(ContextPropagator):
    """Jaeger trace propagation."""
    
    UBER_TRACE_ID = "uber-trace-id"
    BAGGAGE_PREFIX = "uberctx-"
    
    def extract(self, carrier: Dict[str, str]) -> Optional[DistributedContext]:
        """Extract Jaeger trace context."""
        trace_id_header = carrier.get(self.UBER_TRACE_ID)
        if not trace_id_header:
            return None
        
        try:
            # Parse: trace_id:span_id:parent_span_id:sampled
            parts = trace_id_header.split(":")
            if len(parts) < 3:
                return None
            
            trace_id, span_id, sampled = parts[0], parts[1], parts[3] if len(parts) > 3 else "1"
            
            context = DistributedContext(
                trace_ids=TraceIdentifiers(
                    trace_id=trace_id,
                    span_id=span_id,
                    trace_flags=int(sampled)
                ),
                format=ContextFormat.JAEGER
            )
            
            # Extract baggage with prefix
            for key, value in carrier.items():
                if key.lower().startswith(self.BAGGAGE_PREFIX):
                    baggage_key = key[len(self.BAGGAGE_PREFIX):]
                    context.baggage.set(baggage_key, value)
            
            return context
        except (ValueError, IndexError):
            return None
    
    def inject(self, context: DistributedContext, carrier: Dict[str, str]):
        """Inject Jaeger trace context."""
        new_span_id = format(int.from_bytes(uuid4().bytes[:8], 'big'), '016x')
        
        trace_id_header = (
            f"{context.trace_ids.trace_id}:"
            f"{new_span_id}:"
            f"0:"
            f"{context.trace_ids.trace_flags}"
        )
        carrier[self.UBER_TRACE_ID] = trace_id_header
        
        # Inject baggage with prefix
        for key, value in context.baggage.all().items():
            carrier[f"{self.BAGGAGE_PREFIX}{key}"] = value


class B3Propagator(ContextPropagator):
    """B3 Single and Multi-header propagation."""
    
    B3_SINGLE = "b3"
    B3_TRACE_ID = "x-b3-traceid"
    B3_SPAN_ID = "x-b3-spanid"
    B3_PARENT_ID = "x-b3-parentspanid"
    B3_SAMPLED = "x-b3-sampled"
    
    def extract(self, carrier: Dict[str, str]) -> Optional[DistributedContext]:
        """Extract B3 trace context (single or multi-header)."""
        # Try single-header format first
        single = carrier.get(self.B3_SINGLE)
        if single:
            return self._extract_single(single)
        
        # Try multi-header format
        trace_id = carrier.get(self.B3_TRACE_ID)
        if trace_id:
            return self._extract_multi(carrier)
        
        return None
    
    def _extract_single(self, header: str) -> Optional[DistributedContext]:
        """Extract from B3 single header: trace_id-span_id-sampled-parent_id."""
        try:
            parts = header.split("-")
            if len(parts) < 2:
                return None
            
            trace_id = parts[0]
            span_id = parts[1]
            sampled = int(parts[2]) if len(parts) > 2 else 1
            parent_id = parts[3] if len(parts) > 3 else None
            
            return DistributedContext(
                trace_ids=TraceIdentifiers(
                    trace_id=trace_id,
                    span_id=span_id,
                    parent_span_id=parent_id,
                    trace_flags=sampled
                ),
                format=ContextFormat.B3
            )
        except (ValueError, IndexError):
            return None
    
    def _extract_multi(self, carrier: Dict[str, str]) -> Optional[DistributedContext]:
        """Extract from B3 multi-header format."""
        try:
            trace_id = carrier.get(self.B3_TRACE_ID)
            span_id = carrier.get(self.B3_SPAN_ID)
            parent_id = carrier.get(self.B3_PARENT_ID)
            sampled = int(carrier.get(self.B3_SAMPLED, "1"))
            
            if not trace_id or not span_id:
                return None
            
            return DistributedContext(
                trace_ids=TraceIdentifiers(
                    trace_id=trace_id,
                    span_id=span_id,
                    parent_span_id=parent_id,
                    trace_flags=sampled
                ),
                format=ContextFormat.B3
            )
        except (ValueError, TypeError):
            return None
    
    def inject(self, context: DistributedContext, carrier: Dict[str, str]):
        """Inject using multi-header format."""
        new_span_id = format(int.from_bytes(uuid4().bytes[:8], 'big'), '016x')
        
        carrier[self.B3_TRACE_ID] = context.trace_ids.trace_id
        carrier[self.B3_SPAN_ID] = new_span_id
        carrier[self.B3_SAMPLED] = str(context.trace_ids.trace_flags)
        if context.trace_ids.parent_span_id:
            carrier[self.B3_PARENT_ID] = context.trace_ids.parent_span_id


class ContextManager:
    """Manages distributed context for requests."""
    
    _context_var: ContextVar[Optional[DistributedContext]] = ContextVar(
        'distributed_context', default=None
    )
    
    _propagators: Dict[ContextFormat, ContextPropagator] = {
        ContextFormat.W3C_TRACE_CONTEXT: W3CTracePropagator(),
        ContextFormat.JAEGER: JaegerPropagator(),
        ContextFormat.B3: B3Propagator(),
    }
    
    _default_format = ContextFormat.W3C_TRACE_CONTEXT
    
    @classmethod
    def set_context(cls, context: DistributedContext):
        """Set the current context."""
        cls._context_var.set(context)
    
    @classmethod
    def get_context(cls) -> Optional[DistributedContext]:
        """Get the current context."""
        return cls._context_var.get()
    
    @classmethod
    def get_or_create(cls, service_name: str = "") -> DistributedContext:
        """Get current context or create new one."""
        context = cls.get_context()
        if context:
            return context
        
        context = DistributedContext(
            trace_ids=TraceIdentifiers.generate(),
            service_name=service_name
        )
        cls.set_context(context)
        return context
    
    @classmethod
    def extract_context(cls, headers: Dict[str, str], 
                       formats: Optional[List[ContextFormat]] = None) -> Optional[DistributedContext]:
        """Extract context from headers, trying formats in order."""
        if formats is None:
            formats = [ContextFormat.W3C_TRACE_CONTEXT, ContextFormat.JAEGER, ContextFormat.B3]
        
        for fmt in formats:
            if fmt in cls._propagators:
                context = cls._propagators[fmt].extract(headers)
                if context:
                    return context
        
        return None
    
    @classmethod
    def inject_context(cls, context: Optional[DistributedContext] = None, 
                      fmt: Optional[ContextFormat] = None) -> Dict[str, str]:
        """Inject context into headers."""
        context = context or cls.get_context()
        if not context:
            return {}
        
        fmt = fmt or context.format or cls._default_format
        propagator = cls._propagators.get(fmt)
        if not propagator:
            return {}
        
        headers = {}
        propagator.inject(context, headers)
        return headers
    
    @classmethod
    def with_context(cls, context: DistributedContext):
        """Context manager for scoped context."""
        class ScopedContext:
            def __init__(self, ctx):
                self.ctx = ctx
                self.token = None
            
            def __enter__(self):
                self.token = cls._context_var.set(self.ctx)
                return self.ctx
            
            def __exit__(self, exc_type, exc_val, exc_tb):
                if self.token:
                    cls._context_var.reset(self.token)
        
        return ScopedContext(context)
    
    @classmethod
    def new_child_span(cls) -> TraceIdentifiers:
        """Create child span from current context."""
        context = cls.get_context()
        if not context:
            # Create root context
            return TraceIdentifiers.generate()
        
        # Create child span
        new_span = TraceIdentifiers(
            trace_id=context.trace_ids.trace_id,
            span_id=format(int.from_bytes(uuid4().bytes[:8], 'big'), '016x'),
            parent_span_id=context.trace_ids.span_id,
            trace_flags=context.trace_ids.trace_flags
        )
        return new_span


class ContextPropagationMiddleware:
    """Middleware for HTTP frameworks to handle context propagation."""
    
    def __init__(self, service_name: str = "", 
                 formats: Optional[List[ContextFormat]] = None,
                 enable_baggage: bool = True):
        self.service_name = service_name
        self.formats = formats or [ContextFormat.W3C_TRACE_CONTEXT]
        self.enable_baggage = enable_baggage
    
    def extract_from_headers(self, headers: Dict[str, str]) -> DistributedContext:
        """Extract context from request headers."""
        # Try to extract existing context
        context = ContextManager.extract_context(headers, self.formats)
        
        if context:
            # Update service name if not set
            if not context.service_name:
                context.service_name = self.service_name
            return context
        
        # Create new context
        return DistributedContext(
            trace_ids=TraceIdentifiers.generate(),
            service_name=self.service_name
        )
    
    def inject_into_headers(self, context: DistributedContext) -> Dict[str, str]:
        """Inject context into response headers."""
        headers = {}
        for fmt in self.formats:
            propagator = ContextManager._propagators.get(fmt)
            if propagator:
                propagator.inject(context, headers)
        return headers


# Context-aware decorators

def require_context(func: Callable) -> Callable:
    """Decorator requiring distributed context."""
    def wrapper(*args, **kwargs):
        context = ContextManager.get_context()
        if not context:
            context = ContextManager.get_or_create()
        
        return func(*args, **kwargs)
    return wrapper


def with_child_span(span_name: str = ""):
    """Decorator to create and track child spans."""
    def decorator(func: Callable) -> Callable:
        def wrapper(*args, **kwargs):
            context = ContextManager.get_context()
            if not context:
                context = DistributedContext(trace_ids=TraceIdentifiers.generate())
                ContextManager.set_context(context)
            
            # Create child span
            parent_ids = context.trace_ids
            child_ids = TraceIdentifiers(
                trace_id=parent_ids.trace_id,
                span_id=format(int.from_bytes(uuid4().bytes[:8], 'big'), '016x'),
                parent_span_id=parent_ids.span_id,
                trace_flags=parent_ids.trace_flags
            )
            
            # Create child context
            child_context = DistributedContext(
                trace_ids=child_ids,
                correlation_id=context.correlation_id,
                request_id=context.request_id,
                baggage=context.baggage,
                user_id=context.user_id,
                tenant_id=context.tenant_id
            )
            
            with ContextManager.with_context(child_context):
                return func(*args, **kwargs)
        
        return wrapper
    return decorator


def set_baggage(key: str, value: str, properties: Optional[Dict[str, str]] = None):
    """Decorator to set baggage items."""
    def decorator(func: Callable) -> Callable:
        def wrapper(*args, **kwargs):
            context = ContextManager.get_or_create()
            context.baggage.set(key, value, properties)
            return func(*args, **kwargs)
        return wrapper
    return decorator


__all__ = [
    'ContextFormat',
    'TraceIdentifiers',
    'BaggageItem',
    'RequestBaggage',
    'DistributedContext',
    'ContextPropagator',
    'W3CTracePropagator',
    'JaegerPropagator',
    'B3Propagator',
    'ContextManager',
    'ContextPropagationMiddleware',
    'require_context',
    'with_child_span',
    'set_baggage',
]
