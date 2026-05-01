"""OpenTelemetry integration for distributed tracing.

Provides:
- OpenTelemetry SDK bridge for exporting traces
- Trace context propagation (W3C Trace Context, Jaeger)
- Automatic instrumentation helpers
- Resource definitions and attributes
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional
from enum import Enum
import time
import uuid


class TraceContextFormat(str, Enum):
    """Trace context propagation formats."""

    W3C = "w3c"  # W3C Trace Context
    JAEGER = "jaeger"  # Jaeger format
    B3 = "b3"  # Zipkin B3 format


@dataclass
class TraceContext:
    """W3C Trace Context representation."""

    version: str = "00"
    trace_id: str = field(default_factory=lambda: uuid.uuid4().hex[:32])
    parent_id: str = field(default_factory=lambda: uuid.uuid4().hex[:16])
    trace_flags: str = "01"  # Sampled
    state: Dict[str, str] = field(default_factory=dict)

    def to_header(self) -> str:
        """Convert to W3C Trace Context header.

        Returns:
            Header value
        """
        return f"{self.version}-{self.trace_id}-{self.parent_id}-{self.trace_flags}"

    @classmethod
    def from_header(cls, header: str) -> Optional[TraceContext]:
        """Parse from W3C Trace Context header.

        Args:
            header: Header value

        Returns:
            TraceContext or None if invalid
        """
        parts = header.split("-")

        if len(parts) < 4:
            return None

        try:
            return cls(
                version=parts[0],
                trace_id=parts[1],
                parent_id=parts[2],
                trace_flags=parts[3],
            )
        except (IndexError, ValueError):
            return None


@dataclass
class JaegerTraceContext:
    """Jaeger trace context (for backward compatibility)."""

    trace_id: str = field(default_factory=lambda: uuid.uuid4().hex[:32])
    span_id: str = field(default_factory=lambda: uuid.uuid4().hex[:16])
    parent_id: str = ""
    flags: int = 1

    def to_header(self) -> str:
        """Convert to Jaeger header format (trace-id:span-id:parent-id:flags).

        Returns:
            Header value
        """
        return f"{self.trace_id}:{self.span_id}:{self.parent_id}:{self.flags}"

    @classmethod
    def from_header(cls, header: str) -> Optional[JaegerTraceContext]:
        """Parse from Jaeger header.

        Args:
            header: Header value

        Returns:
            JaegerTraceContext or None if invalid
        """
        parts = header.split(":")

        if len(parts) < 3:
            return None

        try:
            return cls(
                trace_id=parts[0],
                span_id=parts[1],
                parent_id=parts[2] if parts[2] else "",
                flags=int(parts[3]) if len(parts) > 3 else 1,
            )
        except (IndexError, ValueError):
            return None


class ContextPropagator:
    """Propagates trace context across service boundaries."""

    @staticmethod
    def extract(
        headers: Dict[str, str],
        format_type: TraceContextFormat = TraceContextFormat.W3C,
    ) -> Optional[Dict[str, Any]]:
        """Extract trace context from headers.

        Args:
            headers: HTTP headers
            format_type: Context format

        Returns:
            Extracted context or None
        """
        if format_type == TraceContextFormat.W3C:
            header_value = headers.get("traceparent")
            if header_value:
                ctx = TraceContext.from_header(header_value)
                return {
                    "trace_id": ctx.trace_id,
                    "parent_id": ctx.parent_id,
                } if ctx else None

        elif format_type == TraceContextFormat.JAEGER:
            header_value = headers.get("uber-trace-id")
            if header_value:
                ctx = JaegerTraceContext.from_header(header_value)
                return {
                    "trace_id": ctx.trace_id,
                    "span_id": ctx.span_id,
                    "parent_id": ctx.parent_id,
                } if ctx else None

        return None

    @staticmethod
    def inject(
        context: Dict[str, str],
        format_type: TraceContextFormat = TraceContextFormat.W3C,
    ) -> Dict[str, str]:
        """Inject trace context into headers.

        Args:
            context: Trace context
            format_type: Context format

        Returns:
            Headers with injected context
        """
        headers = {}

        if format_type == TraceContextFormat.W3C:
            trace_ctx = TraceContext(
                trace_id=context.get("trace_id", uuid.uuid4().hex[:32]),
                parent_id=context.get("parent_id", uuid.uuid4().hex[:16]),
            )
            headers["traceparent"] = trace_ctx.to_header()

        elif format_type == TraceContextFormat.JAEGER:
            jaeger_ctx = JaegerTraceContext(
                trace_id=context.get("trace_id", uuid.uuid4().hex[:32]),
                span_id=context.get("span_id", uuid.uuid4().hex[:16]),
                parent_id=context.get("parent_id", ""),
            )
            headers["uber-trace-id"] = jaeger_ctx.to_header()

        return headers


@dataclass
class ResourceAttribute:
    """Resource attribute for service metadata."""

    key: str
    value: Any

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {"key": self.key, "value": self.value}


class ResourceBuilder:
    """Builds resource attributes for spans."""

    def __init__(self):
        """Initialize builder."""
        self.attributes: Dict[str, Any] = {}

    def set_service(
        self,
        service_name: str,
        service_version: str = "1.0.0",
    ) -> ResourceBuilder:
        """Set service attributes.

        Args:
            service_name: Service name
            service_version: Service version

        Returns:
            Self for chaining
        """
        self.attributes["service.name"] = service_name
        self.attributes["service.version"] = service_version
        return self

    def set_environment(
        self,
        environment: str,
        region: str = "",
        zone: str = "",
    ) -> ResourceBuilder:
        """Set environment attributes.

        Args:
            environment: Environment (production, staging, etc.)
            region: Region name
            zone: Zone/AZ name

        Returns:
            Self for chaining
        """
        self.attributes["deployment.environment"] = environment

        if region:
            self.attributes["cloud.region"] = region

        if zone:
            self.attributes["cloud.availability_zone"] = zone

        return self

    def set_host(
        self,
        hostname: str,
        host_id: str = "",
        container_id: str = "",
    ) -> ResourceBuilder:
        """Set host attributes.

        Args:
            hostname: Hostname
            host_id: Host ID
            container_id: Container ID

        Returns:
            Self for chaining
        """
        self.attributes["host.name"] = hostname

        if host_id:
            self.attributes["host.id"] = host_id

        if container_id:
            self.attributes["container.id"] = container_id

        return self

    def set_process(
        self,
        process_id: int,
        process_executable: str = "",
    ) -> ResourceBuilder:
        """Set process attributes.

        Args:
            process_id: Process ID
            process_executable: Executable name

        Returns:
            Self for chaining
        """
        self.attributes["process.pid"] = process_id

        if process_executable:
            self.attributes["process.executable.name"] = process_executable

        return self

    def add_attribute(self, key: str, value: Any) -> ResourceBuilder:
        """Add custom attribute.

        Args:
            key: Attribute key
            value: Attribute value

        Returns:
            Self for chaining
        """
        self.attributes[key] = value
        return self

    def build(self) -> Dict[str, Any]:
        """Build resource attributes.

        Returns:
            Attributes dictionary
        """
        return self.attributes.copy()


class InstrumentationScope:
    """Defines instrumentation library/scope."""

    def __init__(
        self,
        name: str,
        version: str = "1.0.0",
        schema_url: str = "",
    ):
        """Initialize scope.

        Args:
            name: Instrumentation name
            version: Version
            schema_url: Schema URL
        """
        self.name = name
        self.version = version
        self.schema_url = schema_url

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "name": self.name,
            "version": self.version,
            "schemaUrl": self.schema_url,
        }


class SpanEventBuilder:
    """Builds span events (logs)."""

    def __init__(self, name: str):
        """Initialize builder.

        Args:
            name: Event name
        """
        self.name = name
        self.timestamp = time.time_ns()
        self.attributes: Dict[str, Any] = {}

    def set_timestamp(self, timestamp_ns: int) -> SpanEventBuilder:
        """Set event timestamp.

        Args:
            timestamp_ns: Unix nanoseconds

        Returns:
            Self for chaining
        """
        self.timestamp = timestamp_ns
        return self

    def add_attribute(self, key: str, value: Any) -> SpanEventBuilder:
        """Add event attribute.

        Args:
            key: Attribute key
            value: Attribute value

        Returns:
            Self for chaining
        """
        self.attributes[key] = value
        return self

    def build(self) -> Dict[str, Any]:
        """Build event.

        Returns:
            Event dictionary
        """
        return {
            "name": self.name,
            "timestamp": self.timestamp,
            "attributes": self.attributes,
        }


class LinkBuilder:
    """Builds span links (references to other spans)."""

    def __init__(
        self,
        trace_id: str,
        span_id: str,
    ):
        """Initialize builder.

        Args:
            trace_id: Linked trace ID
            span_id: Linked span ID
        """
        self.trace_id = trace_id
        self.span_id = span_id
        self.attributes: Dict[str, Any] = {}

    def add_attribute(self, key: str, value: Any) -> LinkBuilder:
        """Add link attribute.

        Args:
            key: Attribute key
            value: Attribute value

        Returns:
            Self for chaining
        """
        self.attributes[key] = value
        return self

    def build(self) -> Dict[str, Any]:
        """Build link.

        Returns:
            Link dictionary
        """
        return {
            "traceId": self.trace_id,
            "spanId": self.span_id,
            "attributes": self.attributes,
        }


class OpenTelemetryBridge:
    """Bridge between our tracing system and OpenTelemetry conventions."""

    @staticmethod
    def create_resource(
        service_name: str,
        service_version: str = "1.0.0",
        environment: str = "production",
    ) -> Dict[str, Any]:
        """Create resource for OpenTelemetry.

        Args:
            service_name: Service name
            service_version: Service version
            environment: Environment

        Returns:
            Resource dictionary
        """
        builder = ResourceBuilder()
        builder.set_service(service_name, service_version)
        builder.set_environment(environment)
        return builder.build()

    @staticmethod
    def create_instrumentation_scope(
        library_name: str,
        library_version: str = "1.0.0",
    ) -> InstrumentationScope:
        """Create instrumentation scope.

        Args:
            library_name: Library name
            library_version: Library version

        Returns:
            InstrumentationScope
        """
        return InstrumentationScope(
            name=library_name,
            version=library_version,
            schema_url="https://opentelemetry.io/schemas/1.20.0",
        )

    @staticmethod
    def span_kind_to_string(kind: int) -> str:
        """Convert span kind to string.

        Args:
            kind: Span kind (0=UNSPECIFIED, 1=INTERNAL, 2=SERVER, 3=CLIENT, 4=PRODUCER, 5=CONSUMER)

        Returns:
            Kind string
        """
        kind_map = {
            0: "UNSPECIFIED",
            1: "INTERNAL",
            2: "SERVER",
            3: "CLIENT",
            4: "PRODUCER",
            5: "CONSUMER",
        }
        return kind_map.get(kind, "UNSPECIFIED")

    @staticmethod
    def status_code_to_string(code: int) -> str:
        """Convert status code to string.

        Args:
            code: Status code (0=UNSET, 1=OK, 2=ERROR)

        Returns:
            Status string
        """
        status_map = {
            0: "UNSET",
            1: "OK",
            2: "ERROR",
        }
        return status_map.get(code, "UNSET")


__all__ = [
    "TraceContextFormat",
    "TraceContext",
    "JaegerTraceContext",
    "ContextPropagator",
    "ResourceAttribute",
    "ResourceBuilder",
    "InstrumentationScope",
    "SpanEventBuilder",
    "LinkBuilder",
    "OpenTelemetryBridge",
]
