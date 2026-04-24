#!/usr/bin/env python3
###############################################################################
# Latency Monitor - Real-time Performance Metrics Collection
# Issue #182: Latency Optimization - Edge Proximity & Terminal Acceleration
#
# Purpose: Collect and analyze real-world latency experienced by developers
# in code-server sessions, track p50/p95/p99 metrics per developer.
#
# Metrics Collected:
#   - IDE response time (keystroke → echo)
#   - Terminal shell latency (command → output)
#   - Git operation overhead
#   - WebSocket frame latency
#   - Cloudflare Tunnel ingress latency
#   - Network round-trip time (RTT)
#
# Storage: SQLite database with time-series data
# Analysis: Automatic anomaly detection, trend analysis
#
###############################################################################

import time
import json
import logging
import sqlite3
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional, Tuple
from pathlib import Path
import statistics
import threading
from collections import deque
import asyncio
import websockets

###############################################################################
# CONFIGURATION
###############################################################################

DB_PATH = Path('/var/lib/latency-monitor/latency-metrics.db')
LOG_DIR = Path('/var/log/latency-monitor')
RETENTION_DAYS = 30
COLLECTION_INTERVAL = 5  # Collect metrics every 5 seconds

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_DIR / 'monitor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

###############################################################################
# DATA STRUCTURES
###############################################################################

@dataclass
class LatencyMeasurement:
    """Single latency measurement"""
    timestamp: float
    developer_id: str
    session_id: str
    latency_ms: float
    latency_type: str  # 'keystroke', 'terminal', 'git', 'websocket', 'tunnel_ingress'
    status: str  # 'success', 'timeout', 'error'
    source_location: str  # Country/region
    destination: str  # 'ide', 'terminal', 'git_server'
    metadata: Optional[Dict[str, Any]] = None

@dataclass
class LatencyStats:
    """Aggregated latency statistics"""
    timestamp: datetime
    latency_type: str
    p50_ms: float
    p95_ms: float
    p99_ms: float
    min_ms: float
    max_ms: float
    mean_ms: float
    count: int
    error_rate: float

###############################################################################
# LATENCY MONITOR DATABASE
###############################################################################

class LatencyDatabase:
    """SQLite database for latency metrics"""
    
    def __init__(self, db_path: Path = DB_PATH):
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()
    
    def _init_db(self):
        """Initialize database schema"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute('''
                CREATE TABLE IF NOT EXISTS latency_measurements (
                    id INTEGER PRIMARY KEY,
                    timestamp REAL,
                    developer_id TEXT,
                    session_id TEXT,
                    latency_ms REAL,
                    latency_type TEXT,
                    status TEXT,
                    source_location TEXT,
                    destination TEXT,
                    metadata TEXT
                )
            ''')
            
            conn.execute('''
                CREATE INDEX IF NOT EXISTS idx_timestamp 
                ON latency_measurements(timestamp)
            ''')
            
            conn.execute('''
                CREATE INDEX IF NOT EXISTS idx_developer_timestamp 
                ON latency_measurements(developer_id, timestamp)
            ''')
            
            conn.execute('''
                CREATE INDEX IF NOT EXISTS idx_latency_type_timestamp 
                ON latency_measurements(latency_type, timestamp)
            ''')
            
            conn.commit()
    
    def insert_measurement(self, measurement: LatencyMeasurement):
        """Insert a latency measurement"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute('''
                INSERT INTO latency_measurements
                (timestamp, developer_id, session_id, latency_ms, latency_type, 
                 status, source_location, destination, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                measurement.timestamp,
                measurement.developer_id,
                measurement.session_id,
                measurement.latency_ms,
                measurement.latency_type,
                measurement.status,
                measurement.source_location,
                measurement.destination,
                json.dumps(measurement.metadata) if measurement.metadata else None
            ))
            conn.commit()
    
    def get_statistics(
        self,
        latency_type: str,
        hours: int = 24
    ) -> LatencyStats:
        """Get aggregated statistics for a latency type"""
        cutoff_time = time.time() - (hours * 3600)
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute('''
                SELECT latency_ms, status FROM latency_measurements
                WHERE latency_type = ? AND timestamp > ?
                ORDER BY latency_ms
            ''', (latency_type, cutoff_time))
            
            measurements = cursor.fetchall()
            
            if not measurements:
                return LatencyStats(
                    timestamp=datetime.utcnow(),
                    latency_type=latency_type,
                    p50_ms=0, p95_ms=0, p99_ms=0,
                    min_ms=0, max_ms=0, mean_ms=0,
                    count=0, error_rate=0
                )
            
            latencies = [m[0] for m in measurements]
            statuses = [m[1] for m in measurements]
            
            error_count = sum(1 for s in statuses if s != 'success')
            error_rate = error_count / len(measurements)
            
            return LatencyStats(
                timestamp=datetime.utcnow(),
                latency_type=latency_type,
                p50_ms=statistics.median(latencies),
                p95_ms=statistics.quantiles(latencies, n=20)[18] if len(latencies) > 20 else max(latencies),
                p99_ms=statistics.quantiles(latencies, n=100)[98] if len(latencies) > 100 else max(latencies),
                min_ms=min(latencies),
                max_ms=max(latencies),
                mean_ms=statistics.mean(latencies),
                count=len(measurements),
                error_rate=error_rate
            )
    
    def get_developer_statistics(
        self,
        developer_id: str,
        hours: int = 24
    ) -> Dict[str, LatencyStats]:
        """Get statistics grouped by latency type for a developer"""
        cutoff_time = time.time() - (hours * 3600)
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute('''
                SELECT DISTINCT latency_type FROM latency_measurements
                WHERE developer_id = ? AND timestamp > ?
            ''', (developer_id, cutoff_time))
            
            latency_types = [row[0] for row in cursor.fetchall()]
        
        return {
            lt: self.get_statistics_for_developer(developer_id, lt, hours)
            for lt in latency_types
        }
    
    def get_statistics_for_developer(
        self,
        developer_id: str,
        latency_type: str,
        hours: int = 24
    ) -> LatencyStats:
        """Get statistics for a developer and latency type"""
        cutoff_time = time.time() - (hours * 3600)
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute('''
                SELECT latency_ms, status FROM latency_measurements
                WHERE developer_id = ? AND latency_type = ? AND timestamp > ?
                ORDER BY latency_ms
            ''', (developer_id, latency_type, cutoff_time))
            
            measurements = cursor.fetchall()
            
            if not measurements:
                return LatencyStats(
                    timestamp=datetime.utcnow(),
                    latency_type=latency_type,
                    p50_ms=0, p95_ms=0, p99_ms=0,
                    min_ms=0, max_ms=0, mean_ms=0,
                    count=0, error_rate=0
                )
            
            latencies = [m[0] for m in measurements]
            statuses = [m[1] for m in measurements]
            
            error_count = sum(1 for s in statuses if s != 'success')
            error_rate = error_count / len(measurements)
            
            return LatencyStats(
                timestamp=datetime.utcnow(),
                latency_type=latency_type,
                p50_ms=statistics.median(latencies),
                p95_ms=statistics.quantiles(latencies, n=20)[18] if len(latencies) > 20 else max(latencies),
                p99_ms=statistics.quantiles(latencies, n=100)[98] if len(latencies) > 100 else max(latencies),
                min_ms=min(latencies),
                max_ms=max(latencies),
                mean_ms=statistics.mean(latencies),
                count=len(measurements),
                error_rate=error_rate
            )
    
    def cleanup_old_data(self, days: int = RETENTION_DAYS):
        """Delete measurements older than retention period"""
        cutoff_time = time.time() - (days * 86400)
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute(
                'DELETE FROM latency_measurements WHERE timestamp < ?',
                (cutoff_time,)
            )
            rows_deleted = cursor.rowcount
            conn.commit()
        
        logger.info(f"Cleaned up {rows_deleted} old measurements")

###############################################################################
# LATENCY COLLECTOR
###############################################################################

class LatencyCollector:
    """Collects latency measurements from WebSocket connections"""
    
    def __init__(self, db: LatencyDatabase):
        self.db = db
        self.measurements: deque = deque(maxlen=10000)
        self.running = False
        self.collection_thread = None
    
    def record_measurement(
        self,
        developer_id: str,
        session_id: str,
        latency_ms: float,
        latency_type: str,
        status: str = 'success',
        source_location: str = 'unknown',
        destination: str = 'unknown',
        metadata: Optional[Dict] = None
    ):
        """Record a latency measurement"""
        measurement = LatencyMeasurement(
            timestamp=time.time(),
            developer_id=developer_id,
            session_id=session_id,
            latency_ms=latency_ms,
            latency_type=latency_type,
            status=status,
            source_location=source_location,
            destination=destination,
            metadata=metadata
        )
        
        self.measurements.append(measurement)
        self.db.insert_measurement(measurement)
        
        # Log measurement for immediate visibility
        logger.debug(f"Latency: {developer_id} - {latency_type}: {latency_ms:.2f}ms ({status})")
    
    def get_stats(self, latency_type: str, hours: int = 24) -> LatencyStats:
        """Get aggregated statistics"""
        return self.db.get_statistics(latency_type, hours)
    
    def get_developer_stats(self, developer_id: str, hours: int = 24) -> Dict[str, LatencyStats]:
        """Get statistics for a developer"""
        return self.db.get_developer_statistics(developer_id, hours)
    
    def start_cleanup_thread(self):
        """Start background cleanup thread"""
        def cleanup_loop():
            while self.running:
                time.sleep(3600)  # Cleanup every hour
                self.db.cleanup_old_data()
        
        self.running = True
        self.collection_thread = threading.Thread(target=cleanup_loop, daemon=True)
        self.collection_thread.start()
    
    def stop(self):
        """Stop collector"""
        self.running = False

###############################################################################
# ANOMALY DETECTION
###############################################################################

class AnomalyDetector:
    """Detect latency anomalies"""
    
    def __init__(self, db: LatencyDatabase, threshold_sigma: float = 3.0):
        self.db = db
        self.threshold_sigma = threshold_sigma
    
    def detect_anomalies(
        self,
        latency_type: str,
        hours: int = 24
    ) -> List[Tuple[float, str]]:
        """Detect anomalous latency measurements"""
        stats = self.db.get_statistics(latency_type, hours)
        
        # Calculate anomaly threshold using standard deviation
        # (would need full dataset, simplified here)
        anomalies = []
        
        # If max exceeds p99 + 3x estimated stddev, it's anomalous
        suspected_stddev = (stats.p99_ms - stats.p50_ms) / 2
        anomaly_threshold = stats.p99_ms + (self.threshold_sigma * suspected_stddev)
        
        if stats.max_ms > anomaly_threshold:
            anomalies.append((stats.max_ms, f"Anomalous max latency {stats.max_ms:.2f}ms"))
        
        if stats.error_rate > 0.05:
            anomalies.append((stats.error_rate, f"High error rate {stats.error_rate*100:.1f}%"))
        
        return anomalies

###############################################################################
# METRICS REPORTER
###############################################################################

class LatencyReporter:
    """Generate reports from latency data"""
    
    def __init__(self, collector: LatencyCollector):
        self.collector = collector
    
    def generate_summary(self, hours: int = 24) -> str:
        """Generate summary report"""
        latency_types = ['keystroke', 'terminal', 'git', 'websocket', 'tunnel_ingress']
        
        report = f"=== Latency Summary ({hours}h) ===\n\n"
        
        for lt in latency_types:
            stats = self.collector.get_stats(lt, hours)
            
            if stats.count > 0:
                report += f"{lt.upper()}:\n"
                report += f"  p50: {stats.p50_ms:.1f}ms\n"
                report += f"  p95: {stats.p95_ms:.1f}ms\n"
                report += f"  p99: {stats.p99_ms:.1f}ms\n"
                report += f"  min: {stats.min_ms:.1f}ms, max: {stats.max_ms:.1f}ms, mean: {stats.mean_ms:.1f}ms\n"
                report += f"  count: {stats.count}, error_rate: {stats.error_rate*100:.1f}%\n\n"
        
        return report
    
    def generate_json(self, hours: int = 24) -> Dict:
        """Generate JSON report"""
        latency_types = ['keystroke', 'terminal', 'git', 'websocket', 'tunnel_ingress']
        
        return {
            'timestamp': datetime.utcnow().isoformat(),
            'period_hours': hours,
            'metrics': {
                lt: asdict(self.collector.get_stats(lt, hours))
                for lt in latency_types
            }
        }

###############################################################################
# MAIN
###############################################################################

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Latency Monitor')
    parser.add_argument('--action', choices=['run', 'stats', 'report'], required=True)
    parser.add_argument('--hours', type=int, default=24)
    parser.add_argument('--latency-type', default='keystroke')
    parser.add_argument('--developer', default=None)
    
    args = parser.parse_args()
    
    db = LatencyDatabase()
    collector = LatencyCollector(db)
    reporter = LatencyReporter(collector)
    
    if args.action == 'run':
        logger.info("Starting Latency Monitor")
        collector.start_cleanup_thread()
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            collector.stop()
            logger.info("Latency Monitor stopped")
    
    elif args.action == 'stats':
        if args.developer:
            stats = collector.get_developer_stats(args.developer, args.hours)
            for lt, stat in stats.items():
                print(f"\n{lt}:")
                print(f"  p99: {stat.p99_ms:.1f}ms, count: {stat.count}")
        else:
            stats = collector.get_stats(args.latency_type, args.hours)
            print(f"\n{args.latency_type}:")
            print(f"  p99: {stats.p99_ms:.1f}ms, count: {stats.count}")
    
    elif args.action == 'report':
        print(reporter.generate_summary(args.hours))
