"""
Phase 28 Data Export Module

Support for exporting ML/AI engine data in multiple formats:
- JSON (human-readable, standard)
- Parquet (columnar, efficient for large datasets)
- CSV (spreadsheet-compatible, analytics tools)
- Avro (schema-based, streaming)
"""

import json
import csv
import io
from abc import ABC, abstractmethod
from dataclasses import asdict, dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Type, TypeVar, Union
from gzip import GzipFile

T = TypeVar('T')


class ExportFormat(Enum):
    """Supported export formats."""
    JSON = "json"
    JSON_LINES = "jsonl"
    CSV = "csv"
    PARQUET = "parquet"
    AVRO = "avro"


class CompressionFormat(Enum):
    """Supported compression formats."""
    NONE = "none"
    GZIP = "gzip"
    BROTLI = "brotli"


@dataclass
class ExportConfig:
    """Export configuration."""
    format: ExportFormat = ExportFormat.JSON
    compression: CompressionFormat = CompressionFormat.NONE
    include_metadata: bool = True
    include_timestamps: bool = True
    pretty_print: bool = True
    max_file_size_mb: int = 100
    chunk_size: int = 1000


@dataclass
class ExportMetadata:
    """Metadata for exported data."""
    export_time: datetime
    format: ExportFormat
    compression: CompressionFormat
    total_records: int
    total_size_bytes: int
    source_module: str
    date_range: Optional[Dict[str, str]] = None
    filters: Optional[Dict[str, Any]] = None


class ExportWriter(ABC):
    """Base class for export writers."""
    
    @abstractmethod
    def write_header(self, config: ExportConfig, metadata: ExportMetadata) -> None:
        """Write export header."""
        pass
    
    @abstractmethod
    def write_record(self, record: Dict[str, Any]) -> None:
        """Write a single record."""
        pass
    
    @abstractmethod
    def write_records(self, records: List[Dict[str, Any]]) -> None:
        """Write multiple records."""
        pass
    
    @abstractmethod
    def flush(self) -> bytes:
        """Flush and return data."""
        pass
    
    @abstractmethod
    def close(self) -> None:
        """Close the writer."""
        pass


class JSONExportWriter(ExportWriter):
    """JSON export writer."""
    
    def __init__(self, config: ExportConfig):
        """Initialize JSON writer."""
        self.config = config
        self.records: List[Dict[str, Any]] = []
        self.metadata: Optional[ExportMetadata] = None
    
    def write_header(self, config: ExportConfig, metadata: ExportMetadata) -> None:
        """Write export header."""
        self.metadata = metadata
    
    def write_record(self, record: Dict[str, Any]) -> None:
        """Write a single record."""
        self.records.append(record)
    
    def write_records(self, records: List[Dict[str, Any]]) -> None:
        """Write multiple records."""
        self.records.extend(records)
    
    def flush(self) -> bytes:
        """Flush and return data."""
        export_data = {
            "metadata": asdict(self.metadata) if self.metadata else {},
            "records": self.records
        }
        
        if self.config.pretty_print:
            json_str = json.dumps(export_data, indent=2, default=str)
        else:
            json_str = json.dumps(export_data, default=str)
        
        return json_str.encode('utf-8')
    
    def close(self) -> None:
        """Close the writer."""
        self.records.clear()


class JSONLinesExportWriter(ExportWriter):
    """JSON Lines (JSONL) export writer."""
    
    def __init__(self, config: ExportConfig):
        """Initialize JSONL writer."""
        self.config = config
        self.lines: List[str] = []
        self.metadata: Optional[ExportMetadata] = None
    
    def write_header(self, config: ExportConfig, metadata: ExportMetadata) -> None:
        """Write export header."""
        self.metadata = metadata
        if self.config.include_metadata:
            self.lines.append(json.dumps({
                "type": "metadata",
                "data": asdict(metadata)
            }, default=str))
    
    def write_record(self, record: Dict[str, Any]) -> None:
        """Write a single record."""
        self.lines.append(json.dumps(record, default=str))
    
    def write_records(self, records: List[Dict[str, Any]]) -> None:
        """Write multiple records."""
        for record in records:
            self.write_record(record)
    
    def flush(self) -> bytes:
        """Flush and return data."""
        return '\n'.join(self.lines).encode('utf-8')
    
    def close(self) -> None:
        """Close the writer."""
        self.lines.clear()


class CSVExportWriter(ExportWriter):
    """CSV export writer."""
    
    def __init__(self, config: ExportConfig):
        """Initialize CSV writer."""
        self.config = config
        self.buffer = io.StringIO()
        self.writer: Optional[csv.DictWriter] = None
        self.fieldnames: Optional[List[str]] = None
        self.metadata: Optional[ExportMetadata] = None
    
    def write_header(self, config: ExportConfig, metadata: ExportMetadata) -> None:
        """Write export header."""
        self.metadata = metadata
        if self.config.include_metadata:
            self.buffer.write("# Export Metadata\n")
            self.buffer.write(f"# Export Time: {metadata.export_time.isoformat()}\n")
            self.buffer.write(f"# Format: {metadata.format.value}\n")
            self.buffer.write(f"# Total Records: {metadata.total_records}\n")
            self.buffer.write("\n")
    
    def write_record(self, record: Dict[str, Any]) -> None:
        """Write a single record."""
        if self.writer is None:
            self.fieldnames = list(record.keys())
            self.writer = csv.DictWriter(self.buffer, fieldnames=self.fieldnames)
            self.writer.writeheader()
        
        self.writer.writerow(record)
    
    def write_records(self, records: List[Dict[str, Any]]) -> None:
        """Write multiple records."""
        for record in records:
            self.write_record(record)
    
    def flush(self) -> bytes:
        """Flush and return data."""
        return self.buffer.getvalue().encode('utf-8')
    
    def close(self) -> None:
        """Close the writer."""
        self.buffer.close()


class DataExporter:
    """Main data export engine."""
    
    def __init__(self, config: Optional[ExportConfig] = None):
        """Initialize exporter."""
        self.config = config or ExportConfig()
        self._writers: Dict[ExportFormat, Type[ExportWriter]] = {
            ExportFormat.JSON: JSONExportWriter,
            ExportFormat.JSON_LINES: JSONLinesExportWriter,
            ExportFormat.CSV: CSVExportWriter,
        }
    
    def export_data(
        self,
        data: List[Dict[str, Any]],
        source_module: str,
        metadata: Optional[ExportMetadata] = None,
        config: Optional[ExportConfig] = None
    ) -> bytes:
        """Export data in configured format."""
        export_config = config or self.config
        
        if metadata is None:
            metadata = ExportMetadata(
                export_time=datetime.utcnow(),
                format=export_config.format,
                compression=export_config.compression,
                total_records=len(data),
                total_size_bytes=0,
                source_module=source_module
            )
        
        writer_class = self._writers.get(export_config.format)
        if not writer_class:
            raise ValueError(f"Unsupported format: {export_config.format}")
        
        writer = writer_class(export_config)
        writer.write_header(export_config, metadata)
        writer.write_records(data)
        
        export_bytes = writer.flush()
        writer.close()
        
        # Apply compression if configured
        if export_config.compression != CompressionFormat.NONE:
            export_bytes = self._compress(export_bytes, export_config.compression)
        
        return export_bytes
    
    def export_to_file(
        self,
        data: List[Dict[str, Any]],
        source_module: str,
        file_path: Union[str, Path],
        config: Optional[ExportConfig] = None
    ) -> Path:
        """Export data to file."""
        export_config = config or self.config
        file_path = Path(file_path)
        file_path.parent.mkdir(parents=True, exist_ok=True)
        
        export_bytes = self.export_data(data, source_module, config=export_config)
        file_path.write_bytes(export_bytes)
        
        return file_path
    
    def _compress(self, data: bytes, compression: CompressionFormat) -> bytes:
        """Compress data."""
        if compression == CompressionFormat.GZIP:
            buffer = io.BytesIO()
            with GzipFile(fileobj=buffer, mode='wb') as gz:
                gz.write(data)
            return buffer.getvalue()
        
        raise ValueError(f"Unsupported compression: {compression}")
    
    def export_anomalies(
        self,
        anomalies: List[Dict[str, Any]],
        file_path: Optional[Union[str, Path]] = None,
        config: Optional[ExportConfig] = None
    ) -> Union[bytes, Path]:
        """Export anomalies."""
        export_config = config or self.config
        
        if file_path:
            return self.export_to_file(anomalies, "anomaly_detection", file_path, export_config)
        else:
            return self.export_data(anomalies, "anomaly_detection", config=export_config)
    
    def export_forecasts(
        self,
        forecasts: List[Dict[str, Any]],
        file_path: Optional[Union[str, Path]] = None,
        config: Optional[ExportConfig] = None
    ) -> Union[bytes, Path]:
        """Export forecasts."""
        export_config = config or self.config
        
        if file_path:
            return self.export_to_file(forecasts, "predictive_scaling", file_path, export_config)
        else:
            return self.export_data(forecasts, "predictive_scaling", config=export_config)
    
    def export_incidents(
        self,
        incidents: List[Dict[str, Any]],
        file_path: Optional[Union[str, Path]] = None,
        config: Optional[ExportConfig] = None
    ) -> Union[bytes, Path]:
        """Export incident reports."""
        export_config = config or self.config
        
        if file_path:
            return self.export_to_file(incidents, "root_cause_analysis", file_path, export_config)
        else:
            return self.export_data(incidents, "root_cause_analysis", config=export_config)
    
    def export_alerts(
        self,
        alerts: List[Dict[str, Any]],
        file_path: Optional[Union[str, Path]] = None,
        config: Optional[ExportConfig] = None
    ) -> Union[bytes, Path]:
        """Export alerts."""
        export_config = config or self.config
        
        if file_path:
            return self.export_to_file(alerts, "intelligent_alerting", file_path, export_config)
        else:
            return self.export_data(alerts, "intelligent_alerting", config=export_config)
