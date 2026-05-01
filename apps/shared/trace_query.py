"""Trace querying system for searching and filtering distributed traces.

Provides:
- Query builders for flexible trace searches
- Filtering by trace ID, service, operation, tags
- Aggregation and grouping
- Range queries and time-based searches
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Callable
from datetime import datetime, timedelta
from enum import Enum


class ComparisonOperator(str, Enum):
    """Comparison operators for queries."""

    EQ = "eq"  # Equal
    NE = "ne"  # Not equal
    LT = "lt"  # Less than
    LE = "le"  # Less or equal
    GT = "gt"  # Greater than
    GE = "ge"  # Greater or equal
    IN = "in"  # In list
    CONTAINS = "contains"  # String contains
    MATCHES = "matches"  # Regex match


class SortOrder(str, Enum):
    """Sort order for results."""

    ASC = "asc"
    DESC = "desc"


@dataclass
class FilterCondition:
    """A single filter condition."""

    field: str
    operator: ComparisonOperator
    value: Any

    def matches(self, obj: Dict[str, Any]) -> bool:
        """Check if object matches condition.

        Args:
            obj: Object to check

        Returns:
            True if matches
        """
        obj_value = obj.get(self.field)

        if obj_value is None:
            return False

        if self.operator == ComparisonOperator.EQ:
            return obj_value == self.value
        elif self.operator == ComparisonOperator.NE:
            return obj_value != self.value
        elif self.operator == ComparisonOperator.LT:
            return obj_value < self.value
        elif self.operator == ComparisonOperator.LE:
            return obj_value <= self.value
        elif self.operator == ComparisonOperator.GT:
            return obj_value > self.value
        elif self.operator == ComparisonOperator.GE:
            return obj_value >= self.value
        elif self.operator == ComparisonOperator.IN:
            return obj_value in self.value
        elif self.operator == ComparisonOperator.CONTAINS:
            return self.value in str(obj_value)
        elif self.operator == ComparisonOperator.MATCHES:
            import re
            return re.match(self.value, str(obj_value)) is not None

        return False

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "field": self.field,
            "operator": self.operator.value,
            "value": self.value,
        }


@dataclass
class TraceQuery:
    """Query builder for trace searches."""

    filters: List[FilterCondition] = field(default_factory=list)
    sort_by: Optional[str] = None
    sort_order: SortOrder = SortOrder.DESC
    limit: int = 100
    offset: int = 0
    time_start: Optional[datetime] = None
    time_end: Optional[datetime] = None

    def add_filter(
        self,
        field: str,
        operator: ComparisonOperator,
        value: Any,
    ) -> TraceQuery:
        """Add filter condition.

        Args:
            field: Field name
            operator: Comparison operator
            value: Filter value

        Returns:
            Self for chaining
        """
        self.filters.append(FilterCondition(field, operator, value))
        return self

    def filter_trace_id(self, trace_id: str) -> TraceQuery:
        """Filter by trace ID.

        Args:
            trace_id: Trace ID

        Returns:
            Self for chaining
        """
        return self.add_filter("trace_id", ComparisonOperator.EQ, trace_id)

    def filter_service(self, service_name: str) -> TraceQuery:
        """Filter by service name.

        Args:
            service_name: Service name

        Returns:
            Self for chaining
        """
        return self.add_filter("service_name", ComparisonOperator.EQ, service_name)

    def filter_operation(self, operation_name: str) -> TraceQuery:
        """Filter by operation name.

        Args:
            operation_name: Operation name

        Returns:
            Self for chaining
        """
        return self.add_filter("operation_name", ComparisonOperator.EQ, operation_name)

    def filter_min_duration(self, duration_ms: float) -> TraceQuery:
        """Filter by minimum duration.

        Args:
            duration_ms: Minimum duration in milliseconds

        Returns:
            Self for chaining
        """
        return self.add_filter("duration_ms", ComparisonOperator.GE, duration_ms)

    def filter_max_duration(self, duration_ms: float) -> TraceQuery:
        """Filter by maximum duration.

        Args:
            duration_ms: Maximum duration in milliseconds

        Returns:
            Self for chaining
        """
        return self.add_filter("duration_ms", ComparisonOperator.LE, duration_ms)

    def filter_status(self, status: str) -> TraceQuery:
        """Filter by status.

        Args:
            status: Status (OK, ERROR, etc.)

        Returns:
            Self for chaining
        """
        return self.add_filter("status", ComparisonOperator.EQ, status)

    def filter_tag(self, key: str, value: Any) -> TraceQuery:
        """Filter by tag value.

        Args:
            key: Tag key
            value: Tag value

        Returns:
            Self for chaining
        """
        return self.add_filter(f"tags.{key}", ComparisonOperator.EQ, value)

    def filter_time_range(
        self,
        start: datetime,
        end: datetime,
    ) -> TraceQuery:
        """Filter by time range.

        Args:
            start: Start time
            end: End time

        Returns:
            Self for chaining
        """
        self.time_start = start
        self.time_end = end
        return self

    def sort(
        self,
        field: str,
        order: SortOrder = SortOrder.DESC,
    ) -> TraceQuery:
        """Set sort order.

        Args:
            field: Field to sort by
            order: Sort order

        Returns:
            Self for chaining
        """
        self.sort_by = field
        self.sort_order = order
        return self

    def set_limit(self, limit: int) -> TraceQuery:
        """Set result limit.

        Args:
            limit: Maximum results

        Returns:
            Self for chaining
        """
        self.limit = limit
        return self

    def set_offset(self, offset: int) -> TraceQuery:
        """Set result offset.

        Args:
            offset: Result offset

        Returns:
            Self for chaining
        """
        self.offset = offset
        return self

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "filters": [f.to_dict() for f in self.filters],
            "sortBy": self.sort_by,
            "sortOrder": self.sort_order.value,
            "limit": self.limit,
            "offset": self.offset,
            "timeStart": self.time_start.isoformat() if self.time_start else None,
            "timeEnd": self.time_end.isoformat() if self.time_end else None,
        }


@dataclass
class QueryResult:
    """Query result."""

    total_count: int
    returned_count: int
    traces: List[Dict[str, Any]]
    query_time_ms: float
    executed_at: datetime = field(default_factory=datetime.now)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "totalCount": self.total_count,
            "returnedCount": self.returned_count,
            "traces": self.traces,
            "queryTimeMs": round(self.query_time_ms, 2),
            "executedAt": self.executed_at.isoformat(),
        }


class TraceQueryEngine:
    """Executes trace queries."""

    def __init__(self):
        """Initialize engine."""
        self.traces: List[Dict[str, Any]] = []

    def add_trace(self, trace: Dict[str, Any]) -> None:
        """Add trace to engine.

        Args:
            trace: Trace data
        """
        self.traces.append(trace)

    def execute(self, query: TraceQuery) -> QueryResult:
        """Execute query.

        Args:
            query: Query to execute

        Returns:
            Query result
        """
        import time
        start_time = time.time()

        # Apply filters
        filtered_traces = self._apply_filters(query)

        # Apply time range filter
        if query.time_start or query.time_end:
            filtered_traces = self._apply_time_filter(filtered_traces, query)

        # Get total count
        total_count = len(filtered_traces)

        # Sort
        if query.sort_by:
            filtered_traces = self._apply_sort(filtered_traces, query)

        # Paginate
        paginated_traces = filtered_traces[query.offset:query.offset + query.limit]

        # Calculate query time
        query_time_ms = (time.time() - start_time) * 1000

        return QueryResult(
            total_count=total_count,
            returned_count=len(paginated_traces),
            traces=paginated_traces,
            query_time_ms=query_time_ms,
        )

    def _apply_filters(self, query: TraceQuery) -> List[Dict[str, Any]]:
        """Apply all filters.

        Args:
            query: Query

        Returns:
            Filtered traces
        """
        filtered = self.traces

        for condition in query.filters:
            filtered = [t for t in filtered if condition.matches(t)]

        return filtered

    def _apply_time_filter(
        self,
        traces: List[Dict[str, Any]],
        query: TraceQuery,
    ) -> List[Dict[str, Any]]:
        """Apply time range filter.

        Args:
            traces: Traces to filter
            query: Query with time range

        Returns:
            Filtered traces
        """
        filtered = []

        for trace in traces:
            trace_time = trace.get("timestamp")

            if trace_time is None:
                continue

            # Convert to datetime if string
            if isinstance(trace_time, str):
                trace_time = datetime.fromisoformat(trace_time.replace("Z", "+00:00"))

            if query.time_start and trace_time < query.time_start:
                continue

            if query.time_end and trace_time > query.time_end:
                continue

            filtered.append(trace)

        return filtered

    def _apply_sort(
        self,
        traces: List[Dict[str, Any]],
        query: TraceQuery,
    ) -> List[Dict[str, Any]]:
        """Apply sorting.

        Args:
            traces: Traces to sort
            query: Query with sort specification

        Returns:
            Sorted traces
        """
        reverse = query.sort_order == SortOrder.DESC

        try:
            return sorted(
                traces,
                key=lambda t: t.get(query.sort_by, 0),
                reverse=reverse,
            )
        except (TypeError, KeyError):
            return traces


class TraceAggregator:
    """Aggregates trace data."""

    @staticmethod
    def by_service(traces: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
        """Group traces by service.

        Args:
            traces: Traces to group

        Returns:
            Traces grouped by service name
        """
        grouped = {}

        for trace in traces:
            service = trace.get("service_name", "unknown")

            if service not in grouped:
                grouped[service] = []

            grouped[service].append(trace)

        return grouped

    @staticmethod
    def by_operation(traces: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
        """Group traces by operation.

        Args:
            traces: Traces to group

        Returns:
            Traces grouped by operation name
        """
        grouped = {}

        for trace in traces:
            operation = trace.get("operation_name", "unknown")

            if operation not in grouped:
                grouped[operation] = []

            grouped[operation].append(trace)

        return grouped

    @staticmethod
    def by_status(traces: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
        """Group traces by status.

        Args:
            traces: Traces to group

        Returns:
            Traces grouped by status
        """
        grouped = {}

        for trace in traces:
            status = trace.get("status", "unknown")

            if status not in grouped:
                grouped[status] = []

            grouped[status].append(trace)

        return grouped

    @staticmethod
    def summary_stats(traces: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Calculate summary statistics.

        Args:
            traces: Traces to analyze

        Returns:
            Summary statistics
        """
        if not traces:
            return {}

        durations = [t.get("duration_ms", 0) for t in traces]
        durations = [d for d in durations if d > 0]

        if not durations:
            return {}

        return {
            "count": len(traces),
            "min_duration_ms": min(durations),
            "max_duration_ms": max(durations),
            "avg_duration_ms": sum(durations) / len(durations),
            "median_duration_ms": sorted(durations)[len(durations) // 2],
            "p95_duration_ms": sorted(durations)[int(len(durations) * 0.95)],
            "p99_duration_ms": sorted(durations)[int(len(durations) * 0.99)],
        }


__all__ = [
    "ComparisonOperator",
    "SortOrder",
    "FilterCondition",
    "TraceQuery",
    "QueryResult",
    "TraceQueryEngine",
    "TraceAggregator",
]
