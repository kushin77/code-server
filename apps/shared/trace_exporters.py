"""Trace exporters for standard formats (JSON, Jaeger, Zipkin, OTLP).

Provides converters for exporting distributed traces to common observability platforms:
- JSON: Standard JSON representation
- Jaeger: Jaeger compatible format
- Zipkin: Zipkin B3 compatible format
- OTLP: OpenTelemetry Protocol format
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
import json
import base64


class ExportFormat(str, Enum):
    """Supported export formats."""

    JSON = "json"
    JAEGER = "jaeger"
    ZIPKIN = "zipkin"
    OTLP = "otlp"


@dataclass
class ExportedSpan:
    """Exported span data."""

    trace_id: str
    span_id: str
    parent_span_id: Optional[str]
    operation_name: str
    service_name: str
    start_time_unix_nano: int
    end_time_unix_nano: int
    duration_ns: int
    status: str  # OK, ERROR, UNSET
    tags: Dict[str, Any]
    logs: List[Dict[str, Any]]
    refs: List[Dict[str, str]]


@dataclass
class ExportedTrace:
    """Complete exported trace."""

    trace_id: str
    spans: List[ExportedSpan]
    span_count: int
    start_time_unix_nano: int
    end_time_unix_nano: int
    duration_ns: int
    tag_count: int


class TraceExporter:
    """Base trace exporter."""

    def export(self, trace: ExportedTrace) -> str:
        """Export trace to string format.

        Args:
            trace: Trace to export

        Returns:
            Exported trace as string
        """
        raise NotImplementedError


class JSONExporter(TraceExporter):
    """Exports traces to JSON format."""

    def export(self, trace: ExportedTrace, pretty: bool = True) -> str:
        """Export trace to JSON.

        Args:
            trace: Trace to export
            pretty: Whether to pretty-print

        Returns:
            JSON string
        """
        trace_dict = {
            "traceId": trace.trace_id,
            "spanCount": trace.span_count,
            "startTime": self._unix_nano_to_iso(trace.start_time_unix_nano),
            "endTime": self._unix_nano_to_iso(trace.end_time_unix_nano),
            "durationNs": trace.duration_ns,
            "spans": [self._span_to_dict(span) for span in trace.spans],
        }

        if pretty:
            return json.dumps(trace_dict, indent=2)
        else:
            return json.dumps(trace_dict)

    def _span_to_dict(self, span: ExportedSpan) -> Dict[str, Any]:
        """Convert span to dictionary."""
        return {
            "traceId": span.trace_id,
            "spanId": span.span_id,
            "parentSpanId": span.parent_span_id,
            "operationName": span.operation_name,
            "serviceName": span.service_name,
            "startTime": self._unix_nano_to_iso(span.start_time_unix_nano),
            "endTime": self._unix_nano_to_iso(span.end_time_unix_nano),
            "durationNs": span.duration_ns,
            "status": span.status,
            "tags": span.tags,
            "logs": span.logs,
            "references": span.refs,
        }

    @staticmethod
    def _unix_nano_to_iso(unix_nano: int) -> str:
        """Convert Unix nanosecond timestamp to ISO format."""
        unix_sec = unix_nano / 1e9
        return datetime.utcfromtimestamp(unix_sec).isoformat() + "Z"


class JaegerExporter(TraceExporter):
    """Exports traces to Jaeger format."""

    def export(self, trace: ExportedTrace, batch_size: int = 100) -> str:
        """Export trace to Jaeger format.

        Args:
            trace: Trace to export
            batch_size: Batch size for export

        Returns:
            Jaeger JSON string
        """
        # Group spans by service
        spans_by_service: Dict[str, List[Dict[str, Any]]] = {}

        for span in trace.spans:
            if span.service_name not in spans_by_service:
                spans_by_service[span.service_name] = []

            spans_by_service[span.service_name].append(
                self._span_to_jaeger_dict(span)
            )

        # Build Jaeger batch
        jaeger_dict = {
            "traceID": trace.trace_id,
            "spans": [s for spans in spans_by_service.values() for s in spans],
            "processes": self._build_processes(spans_by_service),
        }

        return json.dumps(jaeger_dict, indent=2)

    def _span_to_jaeger_dict(self, span: ExportedSpan) -> Dict[str, Any]:
        """Convert span to Jaeger format."""
        return {
            "traceID": span.trace_id,
            "spanID": span.span_id,
            "operationName": span.operation_name,
            "references": [
                {
                    "refType": "CHILD_OF",
                    "traceID": span.trace_id,
                    "spanID": span.parent_span_id,
                }
                for _ in ([span.parent_span_id] if span.parent_span_id else [])
            ],
            "startTime": int(span.start_time_unix_nano / 1000),  # Convert to microseconds
            "duration": int(span.duration_ns / 1000),  # Convert to microseconds
            "tags": self._tags_to_jaeger_format(span.tags),
            "logs": self._logs_to_jaeger_format(span.logs),
        }

    @staticmethod
    def _tags_to_jaeger_format(tags: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Convert tags to Jaeger format."""
        jaeger_tags = []

        for key, value in tags.items():
            tag_type = "string"

            if isinstance(value, bool):
                tag_type = "bool"
            elif isinstance(value, (int, float)):
                tag_type = "number"

            jaeger_tags.append(
                {
                    "key": key,
                    "type": tag_type,
                    "value": value,
                }
            )

        return jaeger_tags

    @staticmethod
    def _logs_to_jaeger_format(logs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Convert logs to Jaeger format."""
        jaeger_logs = []

        for log in logs:
            jaeger_logs.append(
                {
                    "timestamp": log.get("timestamp", 0),
                    "fields": [
                        {"key": k, "type": "string", "value": str(v)}
                        for k, v in log.get("fields", {}).items()
                    ],
                }
            )

        return jaeger_logs

    @staticmethod
    def _build_processes(spans_by_service: Dict[str, List[Any]]) -> Dict[str, Dict[str, Any]]:
        """Build process definitions for Jaeger."""
        processes = {}

        for service_name in spans_by_service.keys():
            processes[service_name] = {
                "serviceName": service_name,
                "tags": [
                    {"key": "sampler.type", "type": "string", "value": "const"},
                    {"key": "sampler.param", "type": "number", "value": 1},
                ],
            }

        return processes


class ZipkinExporter(TraceExporter):
    """Exports traces to Zipkin B3 format."""

    def export(self, trace: ExportedTrace) -> str:
        """Export trace to Zipkin format.

        Args:
            trace: Trace to export

        Returns:
            Zipkin JSON string
        """
        zipkin_spans = [self._span_to_zipkin_dict(span) for span in trace.spans]

        return json.dumps(zipkin_spans, indent=2)

    def _span_to_zipkin_dict(self, span: ExportedSpan) -> Dict[str, Any]:
        """Convert span to Zipkin format."""
        return {
            "traceId": span.trace_id,
            "id": span.span_id,
            "parentId": span.parent_span_id,
            "name": span.operation_name,
            "localEndpoint": {
                "serviceName": span.service_name,
            },
            "timestamp": int(span.start_time_unix_nano / 1000),  # Microseconds
            "duration": int(span.duration_ns / 1000),  # Microseconds
            "kind": "SERVER",
            "tags": span.tags,
            "annotations": self._logs_to_zipkin_annotations(span.logs),
        }

    @staticmethod
    def _logs_to_zipkin_annotations(logs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Convert logs to Zipkin annotations."""
        annotations = []

        for log in logs:
            annotations.append(
                {
                    "timestamp": log.get("timestamp", 0),
                    "value": json.dumps(log.get("fields", {})),
                }
            )

        return annotations


class OTLPExporter(TraceExporter):
    """Exports traces to OpenTelemetry Protocol format."""

    def export(self, trace: ExportedTrace, use_protobuf: bool = False) -> str:
        """Export trace to OTLP format.

        Args:
            trace: Trace to export
            use_protobuf: If True, returns base64-encoded protobuf; if False, returns JSON

        Returns:
            OTLP format string (JSON or base64-encoded protobuf)
        """
        if use_protobuf:
            return self._export_protobuf(trace)
        else:
            return self._export_json(trace)

    def _export_json(self, trace: ExportedTrace) -> str:
        """Export trace to OTLP JSON format."""
        resource_spans = self._build_resource_spans(trace)

        otlp_dict = {
            "resourceSpans": [resource_spans],
        }

        return json.dumps(otlp_dict, indent=2)

    def _export_protobuf(self, trace: ExportedTrace) -> str:
        """Export trace to OTLP protobuf format (base64-encoded for transport)."""
        # In production, this would use protobuf serialization
        # For now, we'll JSON-encode and base64-encode as a placeholder
        json_export = self._export_json(trace)
        protobuf_bytes = json_export.encode("utf-8")
        return base64.b64encode(protobuf_bytes).decode("utf-8")

    def _build_resource_spans(self, trace: ExportedTrace) -> Dict[str, Any]:
        """Build ResourceSpans for OTLP."""
        # Group spans by service
        spans_by_service: Dict[str, List[Dict[str, Any]]] = {}

        for span in trace.spans:
            if span.service_name not in spans_by_service:
                spans_by_service[span.service_name] = []

            spans_by_service[span.service_name].append(self._span_to_otlp_dict(span))

        # Build first resource (typically the main service)
        first_service = next(iter(spans_by_service.keys()))

        return {
            "resource": {
                "attributes": [
                    {
                        "key": "service.name",
                        "value": {"stringValue": first_service},
                    },
                ],
            },
            "scopeSpans": [
                {
                    "scope": {
                        "name": "observability",
                        "version": "1.0.0",
                    },
                    "spans": spans_by_service[first_service],
                },
            ],
        }

    def _span_to_otlp_dict(self, span: ExportedSpan) -> Dict[str, Any]:
        """Convert span to OTLP format."""
        return {
            "traceId": span.trace_id,
            "spanId": span.span_id,
            "parentSpanId": span.parent_span_id or "",
            "name": span.operation_name,
            "kind": 1,  # SPAN_KIND_SERVER
            "startTimeUnixNano": str(span.start_time_unix_nano),
            "endTimeUnixNano": str(span.end_time_unix_nano),
            "attributes": [
                {"key": k, "value": {"stringValue": str(v)}}
                for k, v in span.tags.items()
            ],
            "status": {
                "code": 0 if span.status == "OK" else (2 if span.status == "ERROR" else 0),
            },
        }


class ExporterFactory:
    """Factory for creating exporters."""

    _exporters = {
        ExportFormat.JSON: JSONExporter,
        ExportFormat.JAEGER: JaegerExporter,
        ExportFormat.ZIPKIN: ZipkinExporter,
        ExportFormat.OTLP: OTLPExporter,
    }

    @classmethod
    def create(cls, format_type: ExportFormat) -> TraceExporter:
        """Create exporter for format.

        Args:
            format_type: Export format

        Returns:
            Exporter instance

        Raises:
            ValueError: If format not supported
        """
        if format_type not in cls._exporters:
            raise ValueError(f"Unsupported export format: {format_type}")

        return cls._exporters[format_type]()

    @classmethod
    def export(
        cls,
        trace: ExportedTrace,
        format_type: ExportFormat = ExportFormat.JSON,
    ) -> str:
        """Export trace directly.

        Args:
            trace: Trace to export
            format_type: Export format

        Returns:
            Exported trace string
        """
        exporter = cls.create(format_type)
        return exporter.export(trace)


__all__ = [
    "ExportFormat",
    "ExportedSpan",
    "ExportedTrace",
    "TraceExporter",
    "JSONExporter",
    "JaegerExporter",
    "ZipkinExporter",
    "OTLPExporter",
    "ExporterFactory",
]
