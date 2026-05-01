"""Trace visualization data structures for timelines, flame graphs, and service maps.

Provides:
- Timeline visualization
- Flame graph representation
- Service dependency map
- Sequence diagram data
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime


@dataclass
class TimelineSpan:
    """Span representation for timeline visualization."""

    span_id: str
    trace_id: str
    operation_name: str
    service_name: str
    start_time_ms: float
    duration_ms: float
    status: str
    tags: Dict[str, Any] = field(default_factory=dict)
    depth: int = 0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "spanId": self.span_id,
            "traceId": self.trace_id,
            "operation": self.operation_name,
            "service": self.service_name,
            "startTime": self.start_time_ms,
            "duration": self.duration_ms,
            "status": self.status,
            "tags": self.tags,
            "depth": self.depth,
        }


@dataclass
class Timeline:
    """Timeline visualization for a trace."""

    trace_id: str
    spans: List[TimelineSpan] = field(default_factory=list)
    total_duration_ms: float = 0.0
    service_count: int = 0
    span_count: int = 0

    def add_span(self, span: TimelineSpan) -> Timeline:
        """Add span to timeline.

        Args:
            span: Span to add

        Returns:
            Self for chaining
        """
        self.spans.append(span)
        self.span_count = len(self.spans)
        return self

    def calculate_depth(self) -> None:
        """Calculate span depths for rendering."""
        # Sort by start time
        sorted_spans = sorted(self.spans, key=lambda s: s.start_time_ms)

        # Group overlapping spans
        depth_levels: List[List[TimelineSpan]] = []

        for span in sorted_spans:
            span_end = span.start_time_ms + span.duration_ms

            # Find first available level
            placed = False

            for level_idx, level_spans in enumerate(depth_levels):
                # Check if span fits at this level
                can_fit = True

                for existing_span in level_spans:
                    existing_end = existing_span.start_time_ms + existing_span.duration_ms

                    # Check for overlap
                    if not (span_end <= existing_span.start_time_ms or span.start_time_ms >= existing_end):
                        can_fit = False
                        break

                if can_fit:
                    span.depth = level_idx
                    level_spans.append(span)
                    placed = True
                    break

            if not placed:
                span.depth = len(depth_levels)
                depth_levels.append([span])

    def calculate_stats(self) -> None:
        """Calculate timeline statistics."""
        if self.spans:
            start_times = [s.start_time_ms for s in self.spans]
            end_times = [s.start_time_ms + s.duration_ms for s in self.spans]

            self.total_duration_ms = max(end_times) - min(start_times) if start_times else 0

            # Count unique services
            services = set(s.service_name for s in self.spans)
            self.service_count = len(services)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        self.calculate_depth()
        self.calculate_stats()

        return {
            "traceId": self.trace_id,
            "spans": [s.to_dict() for s in self.spans],
            "totalDuration": self.total_duration_ms,
            "serviceCount": self.service_count,
            "spanCount": self.span_count,
        }


@dataclass
class FlameGraphNode:
    """Node in flame graph representation."""

    span_id: str
    operation_name: str
    service_name: str
    duration_ms: float
    value: float  # For sizing
    children: List[FlameGraphNode] = field(default_factory=list)
    parent: Optional[FlameGraphNode] = None

    def add_child(self, child: FlameGraphNode) -> FlameGraphNode:
        """Add child node.

        Args:
            child: Child node

        Returns:
            Self for chaining
        """
        child.parent = self
        self.children.append(child)
        return self

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "spanId": self.span_id,
            "operation": self.operation_name,
            "service": self.service_name,
            "duration": self.duration_ms,
            "value": self.value,
            "children": [c.to_dict() for c in self.children],
        }


@dataclass
class FlameGraph:
    """Flame graph visualization."""

    trace_id: str
    root: Optional[FlameGraphNode] = None
    total_duration_ms: float = 0.0

    def build_from_spans(self, spans: List[Dict[str, Any]]) -> None:
        """Build flame graph from spans.

        Args:
            spans: List of span data
        """
        # Create nodes map
        nodes = {}

        for span in spans:
            span_id = span.get("span_id")
            node = FlameGraphNode(
                span_id=span_id,
                operation_name=span.get("operation_name", "unknown"),
                service_name=span.get("service_name", "unknown"),
                duration_ms=span.get("duration_ms", 0),
                value=span.get("duration_ms", 0),
            )
            nodes[span_id] = node

        # Build parent-child relationships
        for span in spans:
            span_id = span.get("span_id")
            parent_id = span.get("parent_span_id")

            if parent_id and parent_id in nodes:
                nodes[parent_id].add_child(nodes[span_id])
            elif not parent_id:
                # Root node
                self.root = nodes[span_id]

        # Calculate total duration
        if self.root:
            self.total_duration_ms = self.root.duration_ms

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "traceId": self.trace_id,
            "root": self.root.to_dict() if self.root else None,
            "totalDuration": self.total_duration_ms,
        }


@dataclass
class ServiceNode:
    """Node in service map."""

    service_name: str
    operation_count: int = 0
    error_count: int = 0
    latency_ms: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "service": self.service_name,
            "operationCount": self.operation_count,
            "errorCount": self.error_count,
            "latencyMs": round(self.latency_ms, 2),
        }


@dataclass
class ServiceEdge:
    """Edge (dependency) between services in service map."""

    source_service: str
    target_service: str
    call_count: int = 0
    error_count: int = 0
    avg_latency_ms: float = 0.0
    p99_latency_ms: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "source": self.source_service,
            "target": self.target_service,
            "callCount": self.call_count,
            "errorCount": self.error_count,
            "avgLatency": round(self.avg_latency_ms, 2),
            "p99Latency": round(self.p99_latency_ms, 2),
        }


class ServiceMap:
    """Service dependency map visualization."""

    def __init__(self, trace_id: str):
        """Initialize service map.

        Args:
            trace_id: Trace ID
        """
        self.trace_id = trace_id
        self.nodes: Dict[str, ServiceNode] = {}
        self.edges: Dict[Tuple[str, str], ServiceEdge] = {}

    def add_service(self, service_name: str) -> ServiceMap:
        """Add service node.

        Args:
            service_name: Service name

        Returns:
            Self for chaining
        """
        if service_name not in self.nodes:
            self.nodes[service_name] = ServiceNode(service_name)

        return self

    def add_dependency(
        self,
        source: str,
        target: str,
        latency_ms: float = 0.0,
        error: bool = False,
    ) -> ServiceMap:
        """Add service dependency.

        Args:
            source: Source service
            target: Target service
            latency_ms: Call latency
            error: Whether call failed

        Returns:
            Self for chaining
        """
        self.add_service(source)
        self.add_service(target)

        edge_key = (source, target)

        if edge_key not in self.edges:
            self.edges[edge_key] = ServiceEdge(source, target)

        edge = self.edges[edge_key]
        edge.call_count += 1

        if error:
            edge.error_count += 1

        # Update average latency
        if latency_ms > 0:
            total_latency = edge.avg_latency_ms * (edge.call_count - 1) + latency_ms
            edge.avg_latency_ms = total_latency / edge.call_count

        return self

    def build_from_trace(self, spans: List[Dict[str, Any]]) -> None:
        """Build service map from trace spans.

        Args:
            spans: List of spans
        """
        # Add all services
        services = set(s.get("service_name") for s in spans if s.get("service_name"))

        for service in services:
            self.add_service(service)

        # Build span map for parent lookup
        span_map = {s.get("span_id"): s for s in spans}

        # Add dependencies
        for span in spans:
            parent_id = span.get("parent_span_id")

            if parent_id and parent_id in span_map:
                parent_span = span_map[parent_id]
                source = parent_span.get("service_name")
                target = span.get("service_name")

                if source and target and source != target:
                    self.add_dependency(
                        source,
                        target,
                        latency_ms=span.get("duration_ms", 0),
                        error=span.get("status") == "ERROR",
                    )

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "traceId": self.trace_id,
            "nodes": [n.to_dict() for n in self.nodes.values()],
            "edges": [e.to_dict() for e in self.edges.values()],
            "nodeCount": len(self.nodes),
            "edgeCount": len(self.edges),
        }


class SequenceDiagram:
    """Sequence diagram representation of trace."""

    def __init__(self, trace_id: str):
        """Initialize sequence diagram.

        Args:
            trace_id: Trace ID
        """
        self.trace_id = trace_id
        self.actors: List[str] = []
        self.interactions: List[Dict[str, Any]] = []

    def add_actor(self, actor: str) -> SequenceDiagram:
        """Add actor (service).

        Args:
            actor: Actor name

        Returns:
            Self for chaining
        """
        if actor not in self.actors:
            self.actors.append(actor)

        return self

    def add_interaction(
        self,
        from_actor: str,
        to_actor: str,
        operation: str,
        duration_ms: float,
        status: str = "OK",
    ) -> SequenceDiagram:
        """Add interaction between actors.

        Args:
            from_actor: Source actor
            to_actor: Target actor
            operation: Operation name
            duration_ms: Duration
            status: Status

        Returns:
            Self for chaining
        """
        self.add_actor(from_actor)
        self.add_actor(to_actor)

        self.interactions.append(
            {
                "from": from_actor,
                "to": to_actor,
                "operation": operation,
                "duration": duration_ms,
                "status": status,
            }
        )

        return self

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "traceId": self.trace_id,
            "actors": self.actors,
            "interactions": self.interactions,
            "actorCount": len(self.actors),
            "interactionCount": len(self.interactions),
        }


__all__ = [
    "TimelineSpan",
    "Timeline",
    "FlameGraphNode",
    "FlameGraph",
    "ServiceNode",
    "ServiceEdge",
    "ServiceMap",
    "SequenceDiagram",
]
